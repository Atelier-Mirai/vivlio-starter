# frozen_string_literal: true

require_relative '../common'
require_relative '../masking'
require_relative 'notation_guard'

module VivlioStarter
  module CLI
    module Lint
      # Markdownファイルから英単語トークンを抽出する
      module Tokenizer
        module_function

        FRONTMATTER_SEP  = /^---\s*$/

        # 抑止コメントの定義。正典は NotationGuard 側に一本化してある。
        VS_LINT_DISABLE           = NotationGuard::SUPPRESS_START
        VS_LINT_ENABLE            = NotationGuard::SUPPRESS_END
        VS_LINT_DISABLE_NEXT_LINE = NotationGuard::SUPPRESS_NEXT_LINE

        # @param content [String] Markdownファイル全体の内容
        # @param check_code_blocks [Boolean] コードブロック内もチェックするか
        # @return [Array<[String, Integer]>] [word, line_no] のペア配列
        def tokenize(content, check_code_blocks: false)
          # VFM 記法（showcase の座標行・クラス属性など）を先に中和する。textlint 側と
          # 同じ NotationGuard を通すことで、記法の判定が lint 全体で一本化される。
          # 行数は保存されるため、以降の行番号は原稿のものと一致したままになる。
          content = NotationGuard.strip_notation(content)

          tokens           = []
          in_frontmatter   = false
          line_no          = 0

          # 抑止コメントによる除外行番号セットを構築
          # 閉じ忘れは日本語校正の [unclosed-suppression] が報告する（ここでも出すと二重になる）
          excluded_lines = build_excluded_lines(content)

          # コードフェンス行の集合を Masking（唯一の実装）で判定する。
          # 従来の /^```/ 単純トグルと異なり、可変長フェンス（```/````/~~~）と
          # 入れ子・```include: 除外に追従するため、入れ子フェンスで本文を誤って
          # コード扱いしなくなる。check_code_blocks 時はコードも検査対象に含める。
          code_lines = check_code_blocks ? Set.new : Masking.code_lines(content)

          content.each_line do |line|
            line_no += 1

            # YAMLフロントマター（先頭 --- 〜 --- ）をスキップ
            if line_no == 1 && line.match?(FRONTMATTER_SEP)
              in_frontmatter = true
              next
            end

            if in_frontmatter
              in_frontmatter = false if line.match?(FRONTMATTER_SEP)
              next
            end

            # コードブロック内のスキップ
            next if code_lines.include?(line_no)

            # 抑止コメントによる除外
            next if excluded_lines.include?(line_no)

            extract_words(line).each { |word| tokens << [word, line_no] }
          end

          tokens
        end

        # 抑止コメントに基づいて除外すべき行番号のセットを構築する
        #
        # **コード領域の中は見ない。** 校正の使い方を解説する原稿は、フェンスの中へ
        # `<!-- no-lint-start -->` を書き写す。それを本物の指示として解釈すると、
        # 例示のつもりの 1 行がファイル末尾までの抑止になる（実測: ```markdown の中に
        # 閉じない disable を置くと、その下の本文の綴り誤りが検出されなくなった）。
        # 記法かどうかの判定は Masking へ委ね、ProseChecker と同じ扱いに揃える。
        #
        # @param content [String] Markdownファイル全体の内容
        # @return [Set<Integer>] 除外する行番号（閉じていない範囲はファイル末尾まで）
        def build_excluded_lines(content)
          excluded_lines = Set.new
          disabled = false
          prose = Set.new
          Masking.each_prose_line(content) { |_line, lineno| prose << lineno }
          line_no = 0

          content.each_line do |line|
            line_no += 1
            next unless prose.include?(line_no)

            # no-lint-start コメント行自体を除外
            if line.match?(VS_LINT_DISABLE)
              disabled = true
              excluded_lines.add(line_no)
              next
            end

            # no-lint-end コメント行自体を除外
            if line.match?(VS_LINT_ENABLE)
              disabled = false
              excluded_lines.add(line_no)
              next
            end

            # no-lint コメント行自体を除外し、次の行も除外
            if line.match?(VS_LINT_DISABLE_NEXT_LINE)
              excluded_lines.add(line_no)
              excluded_lines.add(line_no + 1)
              next
            end

            # disable ブロック内の行を除外
            excluded_lines.add(line_no) if disabled
          end

          excluded_lines
        end

        # 欧文の単語。アクセント記号の付いた文字（Latin-1 補助と拡張 A・B。× と ÷ は除く）も
        # 単語の一部として扱う（改善案.md #63）。ASCII の英字だけで切ると `Håkon` が `kon` に、
        # `Poincaré` が `Poincar` に割れ、辞書に正しい綴りを載せても割れた後の断片が指摘されていた。
        # `\p{Latin}` にしないのは、和文の中の全角英字（Ａ〜Ｚ）まで拾ってしまうため。
        WORD_LETTER = "a-zA-ZÀ-ÖØ-öø-ɏ"

        # 語は英字で始まり、英字・数字が続く。ハイフンと、英字に挟まれたアポストロフィ
        # （`'`・`’`）でつないだものまでを 1 語とする（改善案 #179）。
        # 語の途中で割ると、辞書に正しい綴りがあっても割れた断片を引いていた
        # （`doesn't` → `doesn`、`CanvasRenderingContext2D` → `CanvasRenderingContext`）。
        # 語頭・語末のアポストロフィは引用符なので含めない。数字で始まる `3D`・`2nd` は今までどおり
        # 英字の部分（`D` は 1 字なので捨てる・`nd`）から語になる。
        # 1 語として取り出した語の照らし方は SpellChecker.known? にある
        WORD_SEGMENT = /[#{WORD_LETTER}][#{WORD_LETTER}0-9]*/
        WORD = /#{WORD_SEGMENT}(?:(?:-|['’](?=[#{WORD_LETTER}]))#{WORD_SEGMENT})*/

        # 点検する語の最短の字数（英字だけを数える）。1 字（`c`・`a`）は略語や記号の名前で、
        # 綴りを論じられない。英字が 1 字の型番（`Z80`・`s2`）も同じ扱いにする。
        # 綴りの候補もこの字数以上の語から選ぶ（SpellChecker::Suggester）
        MIN_WORD_LENGTH = 2

        # @return [Integer] 語の英字の字数
        def letter_count(word) = word.count(WORD_LETTER)

        # `.`・`/`・`@` で英数字どうしをつないだ名前（`main.py`・`src/led.c`・`ruby/ruby.wasm`・
        # `example.com`・`contact@example.com`）。ファイル名・パッケージ名・ドメイン・宛先は
        # 英単語ではなく、綴りの直す先も原稿の側に無いので、丸ごと点検しない（改善案 #171）。
        # 割って点検すると、拡張子が辞書にあるかの偶然で指摘が決まっていた（`main.py` は
        # `py => y`・`main.hpp` は `hpp => app` と指摘され、`main.rb`・`main.js` は指摘されない）。
        # 名前の形は spellcheck-tech-word.js の partOfName と同じ（`.`・`/` の両側が英数字）
        NAME = %r{[A-Za-z0-9_-]+(?:[./@][A-Za-z0-9_-]+)+}

        # @param line [String] 1行のMarkdownテキスト
        # @return [Array<String>] 抽出された英単語の配列
        def extract_words(line)
          # インラインコードの退避は Masking（コード領域解釈の唯一の実装）へ委ねる。
          # 自前の /`[^`]*`/ はバッククォートを 1 つずつ数えるため、可変長のコードスパン
          # （```` ```mermaid ```` のような記法の解説）で対が食い違い、**後続の地の文まで
          # コード扱いを外して**しまっていた（実測: 61 章でファイル名が未知語になった）。
          protected_line, = Masking.protect_code(line)
          cleaned = protected_line.gsub(/#{Masking::CODE_SPAN_PLACEHOLDER_PREFIX}\d+__/, ' ')
          cleaned.gsub!(/<[^>]+>/, ' ')                          # HTMLタグを除去
          cleaned.gsub!(/\{[^}]*\}/, ' ')                        # Vivliostyle拡張記法 {.aki} 等
          # URL は**ラベルより先に**落とす。`@qr:https://example.com/Foo` のように
          # 値が URL の記法があり、先にラベルを削ると `@qr:https` までが消えて
          # 残りが URL と認識されなくなる（実測: リポジトリ名が未知語になった）
          cleaned.gsub!(Masking::URL, ' ')                       # URLを除去
          # 相互参照ラベル @id（メールは除外）。`@pageref:見出しラベル` のように
          # コロンで続く形も 1 つの記法なので、まとめて落とす
          cleaned.gsub!(/(?<![A-Za-z0-9_])@[A-Za-z][A-Za-z0-9-]*(?::[A-Za-z][A-Za-z0-9-]*)?/, ' ')
          cleaned.gsub!(/\[\^[^\]]*\]/, ' ')                     # 脚注のラベル [^id]（定義行の説明文は残す）
          # 画像は代替テキストごと落とし、リンクはラベルを本文として残す（改善案.md #146）。
          # 代替テキストは紙面に組まれず、索引の候補・一文の読点の数も読まない。参考画像の
          # パス（`sources/images/haruka-winter-casual.png`）を書くと、断片が未知語になっていた。
          # 画像を先に落とすのは、`[![バッジ](img)](url)` のリンクのラベルから画像だけを外すため
          cleaned.gsub!(/!\[[^\]]*\](?:\([^)]*\)|\[[^\]]*\])/, ' ') # 画像（インライン・参照）
          cleaned.gsub!(/\[([^\]]*)\]\([^)]*\)/, '\1')             # Markdownリンク
          cleaned.gsub!(/\[([^\]]*)\]\[[^\]]*\]/, '\1')            # 参照リンク
          cleaned.gsub!(/^#+\s*/, '')                            # 見出し記号を除去

          cleaned.gsub!(NAME, ' ')                               # ファイル名・ドメインなどの名前

          cleaned.scan(WORD).select { letter_count(it) >= MIN_WORD_LENGTH }
        end
      end
    end
  end
end
