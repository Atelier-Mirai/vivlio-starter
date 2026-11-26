# frozen_string_literal: true

require 'did_you_mean'
require_relative 'container_scanner'
require_relative 'manuscript_scope'
require_relative '../masking'
require_relative '../pre_process/inline_span_transformer'

module VivlioStarter
  module CLI
    module Guards
      # contents/*.md の `:::{.class}` と行内の属性 `[文字]{.class}`・蛍光ペン `==文字=={…}` に、
      # 未知のクラス名・読めない色が使われていないかを検出して警告する（行内は v2-architecture-spec.md
      # §7.1 の D 型、色は inline-color-mark-spec.md §2.3）。コードのコメントの `[!]{…}` の色も見る。
      #
      # なぜ黙殺されるのか:
      #   `:::{.class}` の div 化には二経路ある。Ruby 前処理（convert_container_blocks）が扱う
      #   のは 6 クラスのみで、残りはすべて組み込み置換ルール（ReplacementRules）の汎用正規表現が
      #   `<div class="$1">` へ置換する。後者はクラス名を一切知らないため、`:::{.notion}` は
      #   無言で `<div class="notion">` になり、CSS が当たらないまま素の段落として組まれる。
      #   著者は完成 PDF を目視するまで気づけない。
      #
      # なぜ警告（停止しない）なのか:
      #   「CSS を書く前に原稿を先に書く」という順序を妨げないため。
      #
      # 許可リスト: stylesheets/**/*.css のクラスセレクタを自動抽出する。custom.css が
      #   著者の自由記述用に用意されているため「クラスに CSS を書けば自動的に許可される」で
      #   完結する。過剰許可（Prism のトークンクラス等が混ざる）は偽陰性しか生まないため許容する。
      class ContainerClassCheck < BaseCheck
        include ManuscriptScope

        # 経路 A（Ruby 前処理）が扱うクラス。convert_container_blocks の 6 クラスに加え、
        # showcase は ShowcaseTransformer がブロックごと消費して figure.vs-showcase へ
        # 変換するため、CSS に `.showcase` セレクタが存在しないのが正しい状態。
        # 他は CSS にも存在するが、CSS 側が消えても検証が壊れないよう明示しておく。
        PREPROCESSED_CLASSES = %w[
          book-card rotate-table long-table text-right text-center text-left showcase talk
        ].freeze

        # CSS のクラスセレクタ。小数（`0.5em`）や `nth-child()` を拾わないよう直前を除外する。
        CSS_CLASS_SELECTOR = /(?<![\w.\-])\.([a-zA-Z_][\w-]*)/

        # 提示する修正候補の上限。実データでは 1 件に収まるが、似た名前のクラスが
        # 増えたときに候補が並びすぎないよう蓋をする。
        MAX_SUGGESTIONS = 3

        # 行内の属性の読み方（クラス・キー・色の値）の正典
        Inline = PreProcessCommands::InlineSpanTransformer

        # @return [Array<Violation>] 警告の配列（合格なら空配列）
        def validate
          markdown_files.flat_map { check_file(it) }
        end

        private

        def check_file(path)
          containers = ContainerScanner.scan(path).select { it.kind == :open }.flat_map do |directive|
            directive.classes
                     .reject { known_classes.include?(it) }
                     .map { unknown_class_warning(path, directive, it) }
          end
          text = File.read(path, encoding: 'utf-8')
          containers + inline_warnings(path, text) + alert_comment_warnings(path, text)
        end

        # --- 行内の属性 `[文字]{…}`・`==文字=={…}`（inline-color-mark-spec.md §2.3） ---------

        # 行内の属性の未知のクラス・読めない色・知らないキー・同じキーの重ね書き。
        # コードの中は見ない（Masking.each_prose_line）
        def inline_warnings(path, text)
          Masking.each_prose_line(text).flat_map do |line, lineno|
            PreProcessCommands::InlineSpanTransformer.each_span(line).flat_map do |span|
              location = "#{path}:#{lineno}"
              span.classes.reject { known_classes.include?(it) }.map { unknown_inline_warning(location, span, it) } +
                attribute_warnings(location, span, Inline::KEYS)
            end
          end
        end

        def unknown_inline_warning(location, span, klass)
          candidates = suggest_word(klass, known_classes)
          detail = ["現状: #{span.source}"]
          unless candidates.empty?
            detail << "候補: #{candidates.map { span.with_item(".#{klass}", ".#{it}") }.join(', ')}"
          end
          detail << '→ CSS が当たらないため、飾りの無い字のまま組まれます'
          detail << '→ 意図したクラスであれば stylesheets/custom.css に定義を追加してください'
          warning("#{location} - 未知の行内のクラス '.#{klass}' を検出しました", detail:)
        end

        # `キー=値` の項目の点検。keys は書けるキー（行内の属性は color・background、`[!]` は color）
        def attribute_warnings(location, span, keys, fallback: '色を付けずに組まれます')
          unknown = span.pairs.reject { |key, _| keys.include?(key) }
                        .map { |key, value| unknown_key_warning(location, span, key, value, keys) }
          values = span.pairs.select { |key, _| keys.include?(key) }.filter_map do |key, value|
            color_value_warning(location, span, key, value, fallback) unless Inline.normalize_color(value)
          end
          unknown + values + repeated_key_warnings(location, span)
        end

        # 書き間違えやすいキーと、正しいキー（綴りの近さでは見つからないもの）
        KEY_ALIASES = {
          'bg' => 'background', 'bgcolor' => 'background', 'background-color' => 'background',
          'fg' => 'color', 'text-color' => 'color'
        }.freeze

        def unknown_key_warning(location, span, key, value, keys)
          candidate = KEY_ALIASES[key] if keys.include?(KEY_ALIASES[key])
          candidate ||= DidYouMean::SpellChecker.new(dictionary: keys).correct(key).first
          detail = ["現状: #{span.source}"]
          detail << "候補: #{span.with_item("#{key}=#{value}", "#{candidate}=#{value}")}" if candidate
          detail << "→ 書けるキーは #{keys.map { "#{it}=" }.join('・')} です"
          warning("#{location} - 知らないキー '#{key}=' を検出しました", detail:)
        end

        # 読めない色の値。`rgb()`・`#rrggbbaa` など、まだ受けない書き方は `#rrggbb` へ直した形を示す
        def color_value_warning(location, span, key, value, fallback)
          item = "#{key}=#{value}"
          hex = Inline.hex_of_unsupported(value)
          candidates = hex ? [hex] : suggest_color(value)
          detail = ["現状: #{span.source}"]
          detail << "候補: #{candidates.map { span.with_item(item, "#{key}=#{it}") }.join(', ')}" unless candidates.empty?
          detail << "→ #{fallback}"
          detail << '→ 書ける値は CSS の色の名前（red・rebeccapurple など）・#rrggbb・theme（本のテーマ色）です'
          kind = hex || value.match?(/\A(?:rgba?|hsla?)\(/i) ? 'まだ受けない色の書き方' : '読めない色の値'
          warning("#{location} - #{kind} '#{item}' を検出しました", detail:)
        end

        def suggest_color(value) = suggest_word(value.downcase, [*Inline::CSS_COLOR_NAMES, Inline::THEME_VALUE])

        # 綴りの近い語。DidYouMean は 3〜4 字の語では 1 字の違いも候補にしないので、隣り合う 2 字の
        # 入れ替え（`rde` → `red`・`bleu` → `blue`）を先に足す。色の名前は短いものが多い
        def suggest_word(word, dictionary)
          swaps = (0...(word.length - 1)).map { word[0...it] + word[it + 1] + word[it] + word[(it + 2)..] }
          (swaps.select { dictionary.include?(it) } + DidYouMean::SpellChecker.new(dictionary:).correct(word))
            .uniq.first(MAX_SUGGESTIONS)
        end

        def repeated_key_warnings(location, span)
          span.pairs.group_by(&:first).select { |_, pairs| pairs.size > 1 }.map do |key, pairs|
            detail = ["現状: #{span.source}",
                      "→ 後ろの値（#{key}=#{pairs.last.last}）で組まれます。どちらか一つにしてください"]
            warning("#{location} - 同じキー '#{key}=' を #{pairs.size} 回書いています", detail:)
          end
        end

        # --- コードのコメントの `[!]{…}`（inline-color-mark-spec.md §2.4） -----------------

        # コードの中の `# [!]{.blue}`。クラスはテーマ色の 13 個だけ、キーは color= だけ。
        # 記法の説明（```markdown の中）は紙面で色にしないので見ない
        def alert_comment_warnings(path, text)
          warnings = []
          Masking.replace_top_level_fences(text) do |block, start|
            next nil if block.lines.first.to_s.match?(MARKDOWN_FENCE)

            block.each_line.with_index do |line, offset|
              line.scan(ALERT_ATTRIBUTES) do
                warnings.concat(alert_warnings("#{path}:#{start + offset}", ::Regexp.last_match))
              end
            end
            nil
          end
          warnings
        end

        # 記法の説明のフェンス（```markdown・```md）
        MARKDOWN_FENCE = /\A\s*(?:`{3,}|~{3,})\s*(?:markdown|md)\b/

        # コメントの記号に続く `[!]{…}`（PrismLinesCommands::ALERT_COMMENT_PATTERN と同じ記号）
        ALERT_ATTRIBUTES = %r{(?:\#|//|--|/\*|<!--)\s*\[!\]\{(?<attributes>[^{}\n]*)\}}

        def alert_warnings(location, match)
          attributes = match[:attributes]
          span = Inline::Span.new(text: '!', classes: Inline.classes_of(attributes), source: "[!]{#{attributes}}",
                                  pairs: Inline.pairs_of(attributes), attributes:)
          classes = span.classes.reject { Inline::THEME_COLOR_NAMES.include?(it) }.map do |klass|
            alert_class_warning(location, span, klass)
          end
          classes + attribute_warnings(location, span, %w[color], fallback: '既定の赤（#eb0000）で組まれます')
        end

        def alert_class_warning(location, span, klass)
          candidates = suggest_word(klass, Inline::THEME_COLOR_NAMES)
          detail = ["現状: #{span.source}"]
          detail << "候補: #{candidates.map { span.with_item(".#{klass}", ".#{it}") }.join(', ')}" unless candidates.empty?
          detail << '→ 既定の赤（#eb0000）で組まれます'
          detail << "→ 書けるクラスはテーマ色の #{Inline::THEME_COLOR_NAMES.join('・')} です（ほかの色は color=#3a9d5d のように値で）"
          warning("#{location} - コメントの [!] の知らない色のクラス '.#{klass}' を検出しました", detail:)
        end

        # 行番号を持つ警告は `path:line - 内容` の形にする（LinkImageValidator と同形。
        # 端末でクリックして該当行へ飛べる）。
        def unknown_class_warning(path, directive, klass)
          warning(
            "#{path}:#{directive.line_number} - 未知のコンテナクラス '.#{klass}' を検出しました",
            detail: warning_detail(directive, klass)
          )
        end

        # 現状・候補・対処方法を行配列で返す（warning-messages-actionable 方針）。
        def warning_detail(directive, klass)
          detail = ["現状: #{opener_for(directive.classes)}"]
          candidates = suggest(klass)
          detail << "候補: #{candidate_openers(directive, klass, candidates).join(', ')}" unless candidates.empty?
          detail << '→ CSS が当たらないため、枠が付かず素の段落として組まれます'
          detail << '→ 意図したクラスであれば stylesheets/custom.css に定義を追加してください'
          detail << '  （CSS を書けば、そのクラスは自動的に許可されます）'
          detail
        end

        # 誤りのクラスだけを候補で差し替えた開始行を、候補ごとに組み立てる。
        # 複数クラス（`:::{.notice .colunm}`）でもそのまま貼り替えられる形で示す。
        def candidate_openers(directive, klass, candidates)
          candidates.map do |candidate|
            opener_for(directive.classes.map { |cls| cls == klass ? candidate : cls })
          end
        end

        def opener_for(classes) = ":::{#{classes.map { ".#{it}" }.join(' ')}}"

        # DidYouMean::SpellChecker#correct は Jaro-Winkler 類似度の降順に並び、
        # さらにレーベンシュタイン距離（語長 × 0.25 が上限）で足切り済み。
        # 独自の並べ替えを重ねても順序は変わらないため、stdlib の結果をそのまま使う。
        def suggest(klass)
          DidYouMean::SpellChecker.new(dictionary: known_classes).correct(klass).first(MAX_SUGGESTIONS)
        end

        # CSS 抽出は I/O を伴うため、ガード 1 回の実行につき一度だけ構築する。
        # sort するのは、SpellChecker の sort_by! が安定ソートではなく、Dir.glob 由来の
        # 辞書順が環境依存だと Jaro-Winkler 同点時の候補順がぶれるため。
        def known_classes
          @known_classes ||= (css_classes + PREPROCESSED_CLASSES).uniq.sort.freeze
        end

        def css_classes
          Dir.glob(File.join(Common.stylesheets_dir, '**', '*.css')).flat_map do |path|
            strip_css_noise(File.read(path, encoding: 'utf-8')).scan(CSS_CLASS_SELECTOR).flatten
          end
        end

        # コメントと文字列リテラルを除去する。`content: ".foo"` を
        # クラスセレクタとして誤って拾わないため。
        def strip_css_noise(css) = css.gsub(%r{/\*.*?\*/}m, ' ').gsub(/"[^"]*"|'[^']*'/, ' ')

      end
    end
  end
end
