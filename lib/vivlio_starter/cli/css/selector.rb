# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/css/selector.rb
# ================================================================
# 責務:
#   選択子 1 つ（選択子の並びをカンマで分けた 1 つ）を読み、詳細度と、
#   選ぶ対象（最後の複合選択子）を返す。組み上がった HTML で当たる要素を
#   Nokogiri で数えるための書き換えも受け持つ。
#
# なぜ自前で読むか:
#   crass は選択子を文字列のまま返す。層を外したときに勝ち負けが変わる組を挙げる
#   （css-layer-restructure-spec.md §4.3 の InversionCheck）には、詳細度と、二つの選択子が
#   同じ要素に当たりうるかの二つだけが分かればよく、選択子の全文法は要らない。
#   scripts/css_cascade_diff.rb（S2 の確かめの道具）も同じ部品を使う。
# ================================================================

module VivlioStarter
  module CLI
    module Css
      # 選択子の読み取り
      module Selector
        # 選ぶ対象（最後の複合選択子）。
        #   tags     要素名の候補（nil なら何の要素でもよい）
        #   excluded :not() で外した要素名
        #   classes  クラス（:not() の中は含めない）
        #   pseudo_element 疑似要素の名前（無ければ nil）
        Subject = Data.define(:tags, :excluded, :classes, :pseudo_element)

        # コロン 1 つでも疑似要素になる古い名前
        LEGACY_PSEUDO_ELEMENTS = %w[before after first-line first-letter].freeze

        # 静的な HTML では決まらない疑似クラスと、疑似要素（対象はその元の要素で数える）
        STRIPPED_PSEUDO = /::[\w-]+(?:\([^()]*\))?|:(?:before|after|first-line|first-letter|hover|focus|active|visited|link)\b/

        module_function

        # 括弧と角括弧の外で sep の位置を切る（`a, :is(b, c)` を 2 つに）
        def split_top(text, sep)
          parts = []
          depth = 0
          current = +''
          text.each_char do |ch|
            depth += 1 if '(['.include?(ch)
            depth -= 1 if ')]'.include?(ch)
            if ch == sep && depth.zero?
              parts << current.strip
              current = +''
            else
              current << ch
            end
          end
          parts << current.strip
          parts.reject(&:empty?)
        end

        # 詳細度 [a, b, c]。:is()・:not()・:has() は引数の最大、:where() は 0
        def specificity(selector)
          score = [0, 0, 0]
          i = 0
          while i < selector.length
            case selector[i]
            when '#' then score[0] += 1
                          i = skip_ident(selector, i + 1)
            when '.' then score[1] += 1
                          i = skip_ident(selector, i + 1)
            when '[' then score[1] += 1
                          i = (selector.index(']', i) || selector.length) + 1
            when ':' then i = pseudo_specificity(selector, i, score)
            when /[a-zA-Z_]/ then score[2] += 1
                                  i = skip_ident(selector, i)
            else i += 1
            end
          end
          score
        end

        # 疑似クラス・疑似要素 1 つ分の詳細度を score に足し、次の位置を返す
        def pseudo_specificity(selector, index, score)
          if selector[index + 1] == ':'
            score[2] += 1
            stop = skip_ident(selector, index + 2)
            return selector[stop] == '(' ? matching_paren(selector, stop) + 1 : stop
          end

          stop = skip_ident(selector, index + 1)
          name = selector[(index + 1)...stop].downcase
          unless selector[stop] == '('
            LEGACY_PSEUDO_ELEMENTS.include?(name) ? score[2] += 1 : score[1] += 1
            return stop
          end

          close = matching_paren(selector, stop)
          args = selector[(stop + 1)...close]
          inner = case name
                  when 'where' then [0, 0, 0]
                  when 'is', 'not', 'has', 'matches' then split_top(args, ',').map { specificity(it) }.max
                  when 'nth-child', 'nth-last-child'
                    of = args[/\bof\b(.*)/m, 1]
                    [0, 1, 0].zip(of ? split_top(of, ',').map { specificity(it) }.max : [0, 0, 0]).map(&:sum)
                  else [0, 1, 0]
                  end
          score.each_index { score[it] += inner[it] }
          close + 1
        end

        # 選ぶ対象を読む
        def subject_of(selector)
          compound = last_compound(selector)
          head = compound[/\A([a-zA-Z][\w-]*)/, 1]&.downcase
          tags = head ? [head] : nil
          tags = ['html'] if compound.match?(/:root\b/i)
          pseudo_args(compound, 'is').each do |args|
            names = args.map(&:downcase)
            tags = tags ? tags & names : names if names.all? { it.match?(/\A[a-z][\w-]*\z/) }
          end
          excluded = pseudo_args(compound, 'not').flat_map do |args|
            args.flat_map { |arg| arg.match?(/\A:is\(/i) ? pseudo_args(arg, 'is').flatten : [arg] }
                .map(&:downcase).grep(/\A[a-z][\w-]*\z/)
          end
          legacy = compound[/:(#{LEGACY_PSEUDO_ELEMENTS.join('|')})\b/o, 1]
          pseudo = compound[/::([\w-]+)/, 1] || legacy
          Subject.new(tags:, excluded:, classes: outer_classes(compound), pseudo_element: pseudo)
        end

        # 二つの対象が同じ要素に当たりうるか（控えめ: 要素名と疑似要素で当たらないと言えるときだけ false）
        def may_overlap?(left, right)
          return false unless left.pseudo_element == right.pseudo_element

          tags = if left.tags && right.tags then left.tags & right.tags
                 else left.tags || right.tags
                 end
          return true if tags.nil?

          (tags - left.excluded - right.excluded).any?
        end

        # Nokogiri が読める形の選択子の列にする。:is()・:where() は選択子の並びに、
        # :not(:is(a, b)) は :not(a):not(b) に展開する。疑似要素と動的な疑似クラスは外す
        def nokogiri_selectors(selector)
          text = selector.gsub(STRIPPED_PSEUDO, '').gsub(/:root\b/, 'html').gsub(':checked', '[checked]')
          expand_matches(text)
        end

        # :is()・:where() を選択子の並びに、:not(:is(a, b)) を :not(a):not(b) に展開する。
        # KFX は :is() を含む規則を丸ごと捨てるので、Kindle 用の CSS でも使う（LiteralResolver）
        def expand_matches(selector) = expand_is(expand_not_is(selector))

        # --- 以下は読み取りの下請け ---

        def skip_ident(text, index)
          index += 1 while index < text.length && text[index].match?(/[\w\-\\]/)
          index
        end

        def matching_paren(text, open)
          depth = 0
          (open...text.length).each do |i|
            depth += 1 if text[i] == '('
            depth -= 1 if text[i] == ')'
            return i if depth.zero?
          end
          text.length - 1
        end

        # 最後の複合選択子（結合子の後ろ）
        def last_compound(selector)
          depth = 0
          start = 0
          selector.each_char.with_index do |ch, i|
            depth += 1 if '(['.include?(ch)
            depth -= 1 if ')]'.include?(ch)
            start = i + 1 if depth.zero? && (ch.match?(/\s/) || '>+~'.include?(ch))
          end
          selector[start..].strip
        end

        # 複合選択子の、括弧の外にある :name(…) の引数を集める
        def pseudo_args(compound, name)
          compound.to_enum(:scan, /:#{name}\(/i).map do
            open = Regexp.last_match.end(0) - 1
            split_top(compound[(open + 1)...matching_paren(compound, open)], ',')
          end
        end

        # 括弧の外にあるクラス（:not(.x) の x は対象のクラスではなく、
        # [href$=".pdf"] の .pdf もクラスではない）
        def outer_classes(compound)
          outside = +''
          depth = 0
          compound.each_char do |ch|
            depth += 1 if '(['.include?(ch)
            outside << ch if depth.zero?
            depth -= 1 if ')]'.include?(ch)
          end
          outside.scan(/\.([\w-]+)/).flatten.uniq
        end

        def expand_not_is(text)
          while (match = text.match(/:not\(:is\(/))
            is_open = match.end(0) - 1
            is_close = matching_paren(text, is_open)
            not_close = matching_paren(text, match.begin(0) + 4)
            args = split_top(text[(is_open + 1)...is_close], ',')
            text = text[0...match.begin(0)] + args.map { ":not(#{it})" }.join + text[(not_close + 1)..]
          end
          text
        end

        def expand_is(selector)
          match = selector.match(/:(?:is|where|matches)\(/)
          return [selector.strip] unless match

          open = match.end(0) - 1
          close = matching_paren(selector, open)
          head = selector[0...match.begin(0)]
          tail = selector[(close + 1)..]
          split_top(selector[(open + 1)...close], ',').flat_map { expand_is("#{head}#{it}#{tail}") }
        end
      end
    end
  end
end
