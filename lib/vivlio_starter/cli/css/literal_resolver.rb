# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/css/literal_resolver.rb
# ================================================================
# 責務:
#   Kindle 用の平らな CSS から、KFX が解さない書き方を生成のときに解く
#   （css-layer-restructure-spec.md §4.4・§4.2 の 5。形 flat_literal）。
#     var()        ページの種類ごとの変数の表の値で置き換える
#     calc()       単位のそろった加減と、数との乗除を計算する
#     color-mix()  in srgb の混色を計算して #rrggbb にする
#     :is()・:where()  選択子の並びに展開する
#     :has()       解けないので、その選択子を落とす
#     clamp()・min()・max()  紙の寸法。解かずに、含む宣言を落とす（下の「紙の寸法」）
#   変数の定義（--x: …）は、値を解いた形で残す（resolve_declarations の説明）。
#
# 解く層（css-layer-restructure-spec.md §4.4 の「解く層」）:
#   どの層の規則も解く。部品の色・枠・書体の指定は、PDF と同じ変数で Kindle に届く。
#   PDF 向けの本文の字の大きさと行送り（--book-font-size: 10.5pt など）は、Kindle の束が最初に読む
#   targets/kindle-tokens.css が端末の既定に置き換える。
#
# 紙の寸法（css-layer-restructure-spec.md §4.4 の「関数と選択子」・theme-contract-spec.md §3.5）:
#   見出し・前書き・奥付などの寸法は clamp(…mm, calc(var(--book-paper-scale) * …), …) の形で書いてある。
#   判型に対する比で決めた値で、判型の無い端末では基準が無いので、Kindle には届けない。
#   clamp()・min()・max() を含む宣言は、理由 :paper_dimension を付けて落とす（変数の値から入って
#   きたものも落とす）。以前は解かずに残し、KFX と Kindle Previewer の前処理が宣言ごと捨てるのに
#   任せていた。下流の二つが同じに捨てることに頼らないために、ここで落とす。
#   Kindle での大きさと余白は、targets/kindle*.css に em で書く。
#
# なぜ要るか:
#   KFX は var()・calc()・color-mix() を含む宣言を捨て、:is() を含む規則を丸ごと捨てる
#   （kindle-css-compatibility-notes.md §2）。1.x は Kindle の規則にリテラルの色を直書きし、
#   テーマ色は BookSettingsCss が後から上書きしていた。ここで解けば、Kindle の規則も部品と
#   同じ変数で書け、テーマ色と custom.css の色がそのまま届く。
#
# 変数の表（§4.4）:
#   集めるのは、選択子が :root・html・body・body.<クラス> の規則の定義である。
#   body.<クラス> は、そのページの種類の body に付くクラスだけを含むものを採る（Scope）。
#   body の定義は html・:root の定義に勝ち（継承より自分の値）、同じ要素の中では
#   !important・詳細度・平らにした後の順で決める（Chromium が平らな CSS に対して決めるのと同じ）。
#   それより深い要素（.talk など）や、ページごとに付くクラス（chapter-first）の下で定義された
#   変数、HTML の style 属性で定義された変数は、要素ごとに値が違いうるので解かない。
#   その変数を読む宣言は落とす。KFX も var() を含む宣言を捨てるので、Kindle の結果は今と同じになる。
#
# @media:
#   Kindle は画面の媒体なので、@media print の中の定義は表に入れない。宣言の値は、
#   @media print の中でも同じ表で解く（var( を残さないため）。
# ================================================================

require 'crass'
require 'set'
require_relative 'selector'
require_relative '../html_contract'

module VivlioStarter
  module CLI
    module Css
      # Kindle 用の平らな CSS のリテラル化
      module LiteralResolver
        # 落とした宣言・選択子 1 つ。declaration は宣言（選択子を落としたときは nil）、
        # reason は :variable / :calc / :color_mix / :has / :paper_dimension（紙の寸法。意図した書き方で、
        # 著者に直してもらうものではないので、ほかの理由と分けて扱う）
        Dropped = Data.define(:source, :selector, :declaration, :reason)

        # 解いた結果。pieces は書き換えた規則の列、dropped は落としたもの
        Result = Data.define(:pieces, :dropped)

        # 変数の表を作る範囲。
        #   body_classes  そのページの種類の body に付くクラス（出力先のクラスを含む）
        #   page_classes  body に付きうるページ単位のクラスの全部（ほかのページの種類のもの。
        #                 body_classes に無くても「深い」とはみなさず、当たらない定義として捨てる）
        #   language      本の言語（:root:lang(ja) の判定）
        #   scoped        HTML の style 属性で定義された変数の名前（要素ごとに値が違う）
        Scope = Data.define(:body_classes, :page_classes, :language, :scoped)

        # body に付くクラスのうち、ページの種類で決まるもの（HtmlContract の分類）。
        # 位置（chapter-first）はページごとに付くので含めない
        PAGE_CATEGORIES = %i[page_kind writing_mode layout theme_option target].freeze

        # 値の中の var() を解く深さの上限（循環を止める）
        MAX_DEPTH = 16

        # 解く関数の名前（ここに無い関数の中は触らない）
        LITERAL_FUNCTIONS = /\b(?:var|calc|color-mix)\(/i

        # 紙の寸法の関数。含む宣言は落とす（call_start で引用符の外・名前の頭だけを見るので、
        # minmax() の max( や、min-width のようなプロパティの名前には当たらない）
        PAPER_DIMENSION_FUNCTION = /\A(?:clamp|min|max)\(/i

        # 色の名前（color-mix() の引数で読むもの。CSS の色名のうち、vs の CSS と著者がよく使うもの）
        NAMED_COLORS = {
          'white' => [255, 255, 255, 1.0], 'black' => [0, 0, 0, 1.0], 'transparent' => [0, 0, 0, 0.0],
          'red' => [255, 0, 0, 1.0], 'green' => [0, 128, 0, 1.0], 'blue' => [0, 0, 255, 1.0],
          'yellow' => [255, 255, 0, 1.0], 'orange' => [255, 165, 0, 1.0], 'purple' => [128, 0, 128, 1.0],
          'gray' => [128, 128, 128, 1.0], 'grey' => [128, 128, 128, 1.0], 'silver' => [192, 192, 192, 1.0],
          'navy' => [0, 0, 128, 1.0], 'teal' => [0, 128, 128, 1.0], 'maroon' => [128, 0, 0, 1.0],
          'olive' => [128, 128, 0, 1.0], 'lime' => [0, 255, 0, 1.0], 'aqua' => [0, 255, 255, 1.0],
          'fuchsia' => [255, 0, 255, 1.0]
        }.freeze

        module_function

        # ページの種類の body のクラスから、変数の表を作る範囲を決める。
        # @param html_body_classes [Array<Array<String>>] そのページの種類を読む HTML の body のクラス
        # @param target_classes [Array<String>] 出力先の変換が後で足すクラス（vs-epub・vs-kindle）
        def scope_for(html_body_classes, target_classes:, language:, scoped: [])
          page_classes = HtmlContract::GROUPS.filter_map { |category, _, _, names| names if PAGE_CATEGORIES.include?(category) }
                                             .flatten.to_set
          common = html_body_classes.map { it.to_set & page_classes }.reduce(:&) || Set.new
          Scope.new(body_classes: common | target_classes, page_classes:, language:, scoped: scoped.to_set)
        end

        # 規則の列を解く。
        # @param pieces [Array<Flattener::Piece>] 書き換える規則（出力先のフィルタを掛けた後）
        # @param scope [Scope]
        # @param base [Array<Flattener::Piece>] 変数の表にだけ使う、pieces より前の規則
        #   （章の frontmatter が足した CSS を、本文の束の変数で解くため）
        # @return [Result]
        def resolve(pieces, scope:, base: [])
          table = variable_table([*base, *pieces], scope)
          dropped = []
          resolved = pieces.filter_map do |piece|
            text = rewrite(Crass.parse(piece.text), Context.new(table:, source: piece.source, dropped:))
            piece.with(text:) unless text.empty?
          end
          Result.new(pieces: resolved, dropped:)
        end

        # 書き換えの文脈
        Context = Data.define(:table, :source, :dropped)

        # ================================================================
        # 変数の表
        # ================================================================

        # 変数の表。root・body は 名前 → 値、scoped は解かない変数の名前
        Table = Data.define(:root, :body, :scoped)

        def variable_table(pieces, scope)
          candidates = { root: {}, body: {} }
          scoped = Set.new(scope.scoped)
          order = 0
          pieces.each do |piece|
            each_style_rule(Crass.parse(piece.text), screen: true) do |selectors, properties, screen|
              properties.each do |prop|
                next unless prop[:name].start_with?('--')

                order += 1
                selectors.each do |selector|
                  level = definition_level(selector, scope)
                  next scoped << prop[:name] if level == :scoped
                  next if level.nil? || !screen

                  rank = [prop[:important] ? 1 : 0, *Selector.specificity(selector), order]
                  current = candidates[level][prop[:name]]
                  candidates[level][prop[:name]] = [rank, prop[:value].strip] if current.nil? || (current[0] <=> rank) <= 0
                end
              end
            end
          end
          Table.new(root: candidates[:root].transform_values(&:last), body: candidates[:body].transform_values(&:last),
                    scoped:)
        end

        # 選択子が変数の表のどの段に当たるか。:root / :body、当たらない定義は nil、
        # 要素ごとに値が違いうる定義は :scoped
        def definition_level(selector, scope)
          case selector
          when /\A(?::root|html)((?::lang\([^)]*\))*)\z/
            langs = Regexp.last_match(1).scan(/:lang\(\s*["']?([\w-]+)["']?\s*\)/).flatten
            :root if langs.all? { language_matches?(scope.language, it) }
          when /\Abody((?:\.[\w-]+)*)\z/
            classes = Regexp.last_match(1).split('.').reject(&:empty?)
            if classes.all? { scope.body_classes.include?(it) } then :body
            elsif classes.all? { scope.page_classes.include?(it) } then nil
            else :scoped
            end
          else :scoped
          end
        end

        def language_matches?(book, lang)
          book = book.to_s.downcase
          lang = lang.downcase
          book == lang || book.start_with?("#{lang}-")
        end

        # 規則をたどり、style rule ごとに [選択子の列, 宣言の列, 画面に当たるか] を渡す
        def each_style_rule(nodes, screen:, &block)
          nodes.each do |node|
            case node
            in { node: :style_rule, selector: { value: list }, children: }
              selectors = Selector.split_top(list, ',').map { it.gsub(/\s+/, ' ') }
              block.call(selectors, children.select { it[:node] == :property }, screen)
            in { node: :at_rule, name: /\A(media|supports)\z/i => name, prelude:, block: Array => inner }
              applies = name.casecmp?('supports') || screen_media?(Crass::Parser.stringify(prelude))
              each_style_rule(Crass::Parser.parse_rules(inner), screen: screen && applies, &block)
            else nil
            end
          end
        end

        # @media の条件が画面の媒体に当たるか（Kindle は画面）
        def screen_media?(prelude)
          media = prelude.downcase
          !media.match?(/\bprint\b/) || media.match?(/\bnot\s+print\b/)
        end

        # ================================================================
        # 規則の書き換え
        # ================================================================

        def rewrite(nodes, context)
          nodes.filter_map do |node|
            case node
            in { node: :style_rule, selector: { value: list }, children: }
              rewrite_style_rule(list, children.select { it[:node] == :property }, context)
            in { node: :at_rule, name: /\A(media|supports)\z/i => name, prelude:, block: Array => inner }
              body = rewrite(Crass::Parser.parse_rules(inner), context)
              "@#{name} #{Crass::Parser.stringify(prelude).strip} {\n#{body}\n}" unless body.empty?
            in { node: :at_rule, name: /\A(page|font-face)\z/i => name, prelude:, block: Array => inner }
              properties = Crass::Parser.parse_properties(inner).select { it[:node] == :property }
              declarations = resolve_declarations(properties, "@#{name}", context)
              prelude_text = Crass::Parser.stringify(prelude).strip
              "@#{name}#{" #{prelude_text}" unless prelude_text.empty?} {\n#{declarations.join("\n")}\n}" if declarations.any?
            in { node: :at_rule }
              Crass::Parser.stringify([node]).strip
            else nil
            end
          end.join("\n")
        end

        # 選択子を展開し、宣言を解いた style rule の文字列。残る選択子か宣言が無ければ nil
        def rewrite_style_rule(list, properties, context)
          original = list.gsub(/\s+/, ' ').strip
          selectors = Selector.split_top(list, ',').map { it.gsub(/\s+/, ' ') }.flat_map do |selector|
            if selector.match?(/:has\(/i)
              context.dropped << Dropped.new(source: context.source, selector:, declaration: nil, reason: :has)
              next []
            end
            Selector.expand_matches(selector)
          end
          return nil if selectors.empty?

          declarations = resolve_declarations(properties, original, context)
          "#{selectors.uniq.join(",\n")} {\n#{declarations.join("\n")}\n}" if declarations.any?
        end

        # 宣言を解く。解けない宣言は落として dropped に足す。
        # 変数の定義も値を解いて残す。KFX は定義を読まないが、HTML の中の <style>（Techbook の
        # `pre { font-family: var(--book-font-code) !important }` など）が var() で読むので、消すと
        # Kindle Previewer の前処理（Chromium と同じ組み方）でそこが解けなくなる。
        # 解けない定義は知らせずに落とす（定義そのものは表示に出ない）
        def resolve_declarations(properties, selector, context)
          properties.filter_map do |prop|
            custom = prop[:name].start_with?('--')
            value, reason = literal_value(prop[:value].strip, context.table)
            next if value.nil? && custom

            if value.nil?
              context.dropped << Dropped.new(source: context.source, selector:,
                                             declaration: "#{prop[:name]}: #{prop[:value].strip}", reason:)
              next
            end
            "  #{prop[:name]}: #{value}#{' !important' if prop[:important]};"
          end
        end

        # 宣言の値をリテラルにする。
        # @return [Array(String, nil)] 解いた値と nil、または nil と落とした理由
        def literal_value(value, table)
          return [nil, :paper_dimension] if paper_dimension?(value)
          return [value, nil] unless value.match?(LITERAL_FUNCTIONS)

          substituted = substitute_variables(value, [table.body, table.root], table.scoped, 0)
          return [nil, :variable] unless substituted
          return [nil, :paper_dimension] if paper_dimension?(substituted)

          calculated = replace_calls(substituted, 'calc') { evaluate_calc(it) }
          return [nil, :calc] unless calculated

          mixed = replace_calls(calculated, 'color-mix') { mix_colors(it) }
          return [nil, :color_mix] unless mixed

          [mixed, nil]
        end

        # 値が紙の寸法の関数（clamp()・min()・max()）を含むか
        def paper_dimension?(value) = !call_start(value, PAPER_DIMENSION_FUNCTION).nil?

        # ================================================================
        # var()
        # ================================================================

        # 値の中の var() を全部置き換える。解けない変数があれば nil。
        # levels は近い段から順の表（body・root）。ある段で見つかった定義の値は、その段から先の表で解く
        # （:root の値の中の var() は、body の定義ではなく :root の定義を読む。Chromium の継承と同じ）
        def substitute_variables(value, levels, scoped, depth)
          return nil if depth > MAX_DEPTH

          replace_calls(value, 'var') do |args|
            name, fallback = Selector.split_top(args, ',').then { [it.first.to_s.strip, args[/\A[^,]*,(.*)\z/m, 1]] }
            next nil if scoped.include?(name)

            index = levels.index { it.key?(name) }
            if index
              substitute_variables(levels[index][name], levels[index..], scoped, depth + 1)
            elsif fallback
              substitute_variables(fallback.strip, levels, scoped, depth + 1)
            end
          end
        end

        # name(…) の呼び出しを、左から順にブロックの返す文字列で置き換える（引数は括弧の中の文字列）。
        # ブロックが nil を返したら nil。引用符の中は見ない
        def replace_calls(text, name)
          pattern = /\A#{Regexp.escape(name)}\(/i
          result = +''
          rest = text
          while (start = call_start(rest, pattern))
            open = start + rest[start..].index('(')
            close = closing_paren(rest, open) or return nil
            replacement = yield(rest[(open + 1)...close]) or return nil
            result << rest[0...start] << replacement
            rest = rest[(close + 1)..]
          end
          result << rest
        end

        # 引用符の外で pattern が始まる位置。名前の途中（-webkit-calc の calc）には当てない
        def call_start(text, pattern)
          quote = nil
          text.each_char.with_index do |ch, index|
            if quote
              quote = nil if ch == quote
            elsif %w[" '].include?(ch)
              quote = ch
            elsif (index.zero? || !text[index - 1].match?(/[\w-]/)) && text[index..].match?(pattern)
              return index
            end
          end
          nil
        end

        # open の括弧に対応する閉じ括弧の位置（引用符の中は数えない）
        def closing_paren(text, open)
          depth = 0
          quote = nil
          (open...text.length).each do |index|
            ch = text[index]
            if quote
              quote = nil if ch == quote
            elsif %w[" '].include?(ch)
              quote = ch
            elsif ch == '('
              depth += 1
            elsif ch == ')'
              depth -= 1
              return index if depth.zero?
            end
          end
          nil
        end

        # ================================================================
        # calc()
        # ================================================================

        # calc() の中身を計算する。値は 単位 → 係数 の Hash で持ち、加減は単位ごとに足し、
        # 乗除は片方が数のときだけ行う。単位が 2 つ以上残るもの（100% - 2mm）は解けない。
        # 中に clamp()・min()・max() は来ない（含む宣言は literal_value が先に落とす）
        def evaluate_calc(expression)
          tokens = calc_tokens(expression) or return nil
          value, rest = calc_sum(tokens)
          return nil unless value && rest.empty?

          format_quantity(value)
        end

        CALC_TOKEN = %r{\s+|calc\(|\(|\)|[*/]|[+-](?=\s)|[+-]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?(?:%|[a-z]+)?}i

        # 数（単位つき）・演算子・括弧の列。読めない字句（別の関数・名前）があれば nil
        def calc_tokens(expression)
          tokens = []
          position = 0
          while position < expression.length
            token = expression[position..][/\A#{CALC_TOKEN}/] or return nil
            position += token.length
            next if token.strip.empty?

            tokens << (token.casecmp?('calc(') ? '(' : token)
          end
          tokens
        end

        def calc_sum(tokens)
          left, rest = calc_product(tokens)
          while left && %w[+ -].include?(rest.first)
            operator = rest.first
            right, rest = calc_product(rest.drop(1))
            return nil unless right

            left = left.merge(right.transform_values { operator == '-' ? -it : it }) { |_, a, b| a + b }
          end
          [left, rest]
        end

        def calc_product(tokens)
          left, rest = calc_factor(tokens)
          while left && %w[* /].include?(rest.first)
            operator = rest.first
            right, rest = calc_factor(rest.drop(1))
            return nil unless right

            left = multiply(left, right, operator) or return nil
          end
          [left, rest]
        end

        def calc_factor(tokens)
          case tokens.first
          when '('
            value, rest = calc_sum(tokens.drop(1))
            return nil unless value && rest.first == ')'

            [value, rest.drop(1)]
          when /\A([+-]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?)(%|[a-z]+)?\z/i
            [{ Regexp.last_match(2).to_s => Regexp.last_match(1).to_f }, tokens.drop(1)]
          end
        end

        # 乗除。片方が数（単位の無い値）のときだけ計算できる
        def multiply(left, right, operator)
          if unitless?(right)
            factor = right.fetch('', 0.0)
            return nil if operator == '/' && factor.zero?

            left.transform_values { operator == '*' ? it * factor : it / factor }
          elsif operator == '*' && unitless?(left)
            factor = left.fetch('', 0.0)
            right.transform_values { it * factor }
          end
        end

        def unitless?(quantity) = quantity.keys.all?(&:empty?)

        # 単位が 1 つにそろった値を文字列にする。係数が 0 の単位は数えない
        def format_quantity(quantity)
          live = quantity.reject { |_, coefficient| coefficient.zero? }
          return nil if live.size > 1

          unit, coefficient = live.first || [quantity.keys.first, 0.0]
          "#{format_number(coefficient)}#{unit}"
        end

        def format_number(number)
          text = format('%.6f', number.round(6)).sub(/0+\z/, '').sub(/\.\z/, '')
          text == '-0' ? '0' : text
        end

        # ================================================================
        # color-mix()
        # ================================================================

        # color-mix(in srgb, A p%, B q%) を #rrggbb にする。srgb 以外の色空間と、透明を含む混色は
        # 解けない（KFX が透明度つきの色を解すかは確かめていない。§9 の論点 1）
        def mix_colors(args)
          space, first, second = Selector.split_top(args, ',')
          return nil unless space&.match?(/\Ain\s+srgb\z/i) && first && second

          color1, percent1 = color_stop(first)
          color2, percent2 = color_stop(second)
          return nil unless color1 && color2 && color1[3] == 1.0 && color2[3] == 1.0

          weights = mix_weights(percent1, percent2) or return nil
          weight1, weight2 = weights
          rgb = (0..2).map { ((color1[it] * weight1) + (color2[it] * weight2)).round.clamp(0, 255) }
          format('#%02x%02x%02x', *rgb)
        end

        # 「色 p%」「p% 色」「色」を [色, p] にする
        def color_stop(text)
          stop = text.strip
          case stop
          when /\A(.+?)\s+([\d.]+)%\z/ then [parse_color(Regexp.last_match(1)), Regexp.last_match(2).to_f]
          when /\A([\d.]+)%\s+(.+)\z/ then [parse_color(Regexp.last_match(2)), Regexp.last_match(1).to_f]
          else [parse_color(stop), nil]
          end
        end

        # 二つの割合（0〜1）。合計が 100% に満たない混色は透明度が下がるので解かない
        def mix_weights(percent1, percent2)
          percent1 ||= percent2 ? 100 - percent2 : 50
          percent2 ||= 100 - percent1
          total = percent1 + percent2
          return nil unless (total - 100).abs < 1e-9

          [percent1 / 100.0, percent2 / 100.0]
        end

        # 色を [r, g, b, a] にする（r・g・b は 0〜255、a は 0〜1）。読めなければ nil
        def parse_color(text)
          color = text.strip.downcase
          case color
          when /\A#(\h{3}|\h{4}|\h{6}|\h{8})\z/ then hex_color(Regexp.last_match(1))
          when /\Argba?\((.*)\)\z/ then rgb_function(Regexp.last_match(1))
          else NAMED_COLORS[color]
          end
        end

        def hex_color(digits)
          digits = digits.chars.map { it * 2 }.join if digits.length <= 4
          channels = digits.scan(/../).map { it.to_i(16) }
          [*channels.take(3), channels.length == 4 ? channels[3] / 255.0 : 1.0]
        end

        # rgb(r, g, b)・rgb(r g b / a)・rgba(r, g, b, a)
        def rgb_function(inner)
          parts = inner.split(%r{[\s,/]+}).reject(&:empty?)
          return nil unless [3, 4].include?(parts.size)

          rgb = parts.take(3).map { it.end_with?('%') ? it.to_f * 2.55 : it.to_f }
          alpha = parts[3] ? (parts[3].end_with?('%') ? parts[3].to_f / 100 : parts[3].to_f) : 1.0
          [*rgb, alpha]
        end
      end
    end
  end
end
