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
#
# 原稿は書き換えない（ビルドの中だけ）。vs lint は同じ読み替えを通した文で見る
# （Lint::NotationGuard）。コードの中と、vs のルビ `{漢字|かんじ}` の中は読まない。
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

        module_function

        # @param content [String] 章の Markdown
        # @param drop_indent [Boolean] 行頭の全角空白を落とすか（lint は落とさずに読む）
        # @return [String] 投稿サイトの書き方を vs の記法にした Markdown
        def transform(content, drop_indent: true)
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
          text = text.gsub(LEADING_IDEOGRAPHIC_SPACE, '') if drop_indent
          text = text.gsub(VS_RUBY_MARK) { rubies.shift }.tr(ESCAPED_OPEN_MARK, '《')
          Masking.restore_code(text, code)
        end
      end
    end
  end
end
