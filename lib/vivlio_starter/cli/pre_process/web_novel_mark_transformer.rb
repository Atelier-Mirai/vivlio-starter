# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/web_novel_mark_transformer.rb
# ================================================================
# 責務:
#   小説投稿サイト（小説家になろう・カクヨム）の書き方を、vs の記法へ読み替える
#   （novel-vertical-spec.md §5.4。条件は notation.web_novel）。
#
#   | 書き方                          | 読み替え先           |
#   | `|漢字《かんじ》`・`｜漢字《かんじ》` | `{漢字|かんじ}`      |
#   | `漢字《かんじ》`（読みが仮名だけ）  | `{漢字|かんじ}`      |
#   | `《《文字》》`                    | `[文字]{.sesame}`    |
#   | `|《`・`｜《`                     | `《`（ルビにしない） |
#   | 行頭の全角空白 1 つ               | 落とす（字下げは CSS が付ける） |
#   | 空行を挟まずに続く地の文の行      | 1 行を 1 段落にする（行の間に空行を足す） |
#
# 原稿は書き換えない（ビルドの中だけ）。vs lint は同じ読み替えを通した文で見る
# （Lint::NotationGuard）。ただし字下げと段落の分け方は組むための読み替えなので、lint には
# 掛けない（layout: false。行頭の全角空白は小説の規則が見て、行番号は原稿と同じに保つ）。
# コードの中と、vs のルビ `{漢字|かんじ}` の中は読まない。
# 括弧のルビ（`漢字（かんじ）`）は、地の文の括弧と見分けられないので受けない。
# ================================================================

require_relative '../masking'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # 投稿サイトの書き方を vs の記法へ読み替える
      module WebNovelMarkTransformer
        # vs のルビ `{親文字|読み}`。縦棒のルビの親文字の始まりと読まないよう、先に退避する
        VS_RUBY = /\{[^{}|\n]*\|[^{}\n]*\}/

        # 打ち消し `|《`。ルビの読みの始まりと読まないよう、先に目印へ替える
        ESCAPED_OPEN = /[|｜]《/

        # 退避の目印。私用領域の字なので、原稿の字と取り違えない
        ESCAPED_OPEN_MARK = "\u{F8F0}"
        VS_RUBY_MARK = "\u{F8F1}"

        # カクヨムの傍点 `《《文字》》`
        SESAME = /《《([^《》\n]+)》》/

        # 縦棒のルビ。親文字は縦棒から `《` まで。空白・縦棒・波括弧をまたがない
        # （表の区切り `| 漢字《かんじ》 |` を親文字の始まりと読まない）
        BAR_RUBY = /[|｜]([^\s|｜《》{}]+)《([^《》\n]+)》/

        # 縦棒の無いルビ。親文字は `《` の直前の漢字の並び、読みは仮名と長音だけ
        # （小説家になろうの自動のルビと同じ条件。読みに漢字のある `《題名》` はルビにしない）
        KANJI = /[\p{Han}々〆ヶ]/
        BARE_RUBY = /(#{KANJI}+)《([\p{Hiragana}\p{Katakana}ー]+)》/

        # 行頭の全角空白 1 つ（投稿サイトの字下げ）
        LEADING_IDEOGRAPHIC_SPACE = /^　/

        # 1 行を 1 段落にするとき、間に空行を足さない行。行をまたいで続く Markdown の形
        # （箇条書きと続きの字下げ・表・引用・脚注の定義・定義の説明・HTML・囲みのマーカー）と、
        # setext 見出しの下線。足すと、形が切れて別のものに組まれる
        MULTILINE_BLOCK = /\A(?:[ \t]{2,}|\t|[-*+][ \t]|\d+[.)][ \t]|\||>|\[\^[^\]]*\]:|:[ \t]|<|:{3,}|[=-]+[ \t]*\z)/
        CONTAINER_OPEN  = /\A[ \t]*:{3,}[ \t]*\S/
        CONTAINER_CLOSE = /\A[ \t]*:{3,}[ \t]*\z/
        # 行末の明示の改行（空白 2 つか `\`）。著者が段落の中で改めた行なので、分けない
        HARD_BREAK = /(?: {2,}|\\)\z/
        FRONT_MATTER = /\A---\r?\n.*?^---\r?\n/m

        module_function

        # @param content [String] 章の Markdown
        # @param layout [Boolean] 組むための読み替え（行頭の全角空白を落とし、1 行を 1 段落にする）
        #   も行うか。vs lint は行わない
        # @return [String] 投稿サイトの書き方を vs の記法にした Markdown
        def transform(content, layout: true)
          protected_text, code = Masking.protect_code(content)
          rubies = []
          text = protected_text.gsub(VS_RUBY) do
            rubies << it
            VS_RUBY_MARK
          end
          # 打ち消し → 傍点 → 縦棒のルビ → 縦棒の無いルビの順。傍点を先に読まないと、
          # `《《文字》》` の内側の `《文字》` を縦棒の無いルビの読みと取り違える
          text = text.gsub(ESCAPED_OPEN, ESCAPED_OPEN_MARK)
                     .gsub(SESAME) { "[#{::Regexp.last_match(1)}]{.sesame}" }
                     .gsub(BAR_RUBY) { "{#{::Regexp.last_match(1)}|#{::Regexp.last_match(2)}}" }
                     .gsub(BARE_RUBY) { "{#{::Regexp.last_match(1)}|#{::Regexp.last_match(2)}}" }
          text = text.gsub(LEADING_IDEOGRAPHIC_SPACE, '') if layout
          text = text.gsub(VS_RUBY_MARK) { rubies.shift }.tr(ESCAPED_OPEN_MARK, '《')
          restored = Masking.restore_code(text, code)
          layout ? split_paragraph_lines(restored) : restored
        end

        # 空行を挟まずに続く地の文の行の間に、空行を足す。投稿サイトでは 1 行が 1 段落で、
        # 段落の間に空行を入れない原稿が多い。Markdown のままでは続く行が 1 つの段落になり
        # （行は改行でつながる）、2 行目からの字下げも、会話の行の括弧の段落の印も付かない。
        #
        # 囲みの中・HTML のかたまりの中・コードの中と、行をまたぐ Markdown の形には足さない。
        # 足した行の分だけ後ろの行番号がずれるが、後の段の指摘は原稿から行番号を引き直す
        # （MarkdownPreprocessor#warn_math_errors など）。
        def split_paragraph_lines(text)
          prose = Masking.each_prose_line(text).to_h { |line, lineno| [lineno, line] }
          front_matter_lines = text[FRONT_MATTER]&.count("\n").to_i
          depth = 0
          in_html = false
          previous = nil
          text.each_line.with_index(1).map do |line, lineno|
            body = prose[lineno]&.chomp
            if body.nil? || body.strip.empty? || lineno <= front_matter_lines
              in_html = false
              previous = nil
              next line
            end

            depth += 1 if body.match?(CONTAINER_OPEN)
            depth -= 1 if body.match?(CONTAINER_CLOSE) && depth.positive?
            in_html = true if body.start_with?('<')
            splittable = depth.zero? && !in_html && !body.match?(MULTILINE_BLOCK)
            joined = previous && splittable && !previous.match?(HARD_BREAK) ? "\n#{line}" : line
            previous = splittable ? body : nil
            joined
          end.join
        end
      end
    end
  end
end
