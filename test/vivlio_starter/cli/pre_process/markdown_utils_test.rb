# frozen_string_literal: true

# ================================================================
# Test: pre_process/markdown_utils_test.rb
# ================================================================
# テスト対象:
#   MarkdownUtils.apply_hard_line_breaks
#   （lib/vivlio_starter/cli/pre_process/markdown_utils.rb）
#
# 検証内容:
#   text-* コンテナ等の生 HTML 化経路は VFM を通らずハード改行が失われるため、
#   Kramdown へ渡す前に段落内改行を強制改行（行末スペース 2 つ）へ変換する。
#   - 段落内の改行 → <br> になること（Kramdown 連携）
#   - 空行区切りの段落・リスト・表には作用しないこと
# ================================================================

require 'minitest/autorun'
require_relative '../../../../lib/vivlio_starter/cli/pre_process/markdown_utils'

module VivlioStarter
  module CLI
    module PreProcessCommands
      class MarkdownUtilsTest < Minitest::Test
        def render(md)
          MarkdownUtils.render_markdown_to_html(MarkdownUtils.apply_hard_line_breaks(md))
        end

        def test_should_convert_paragraph_inner_newlines_to_br
          html = render("この段落全体が右寄せで表示されます。\n複数行あっても、すべて右端に揃います。")

          assert_includes html, '<br />'
          assert_includes html, "この段落全体が右寄せで表示されます。<br />\n複数行あっても、すべて右端に揃います。"
        end

        def test_should_keep_blank_line_separated_paragraphs_untouched
          html = render("1段落目。\n\n2段落目。")

          refute_includes html, '<br />'
          assert_equal 2, html.scan('<p>').size
        end

        def test_should_not_inject_br_into_lists
          html = render("- 項目A\n- 項目B")

          refute_includes html, '<br />'
          assert_includes html, '<li>項目A</li>'
          assert_includes html, '<li>項目B</li>'
        end

        def test_should_not_break_table_structure
          html = render("| a | b |\n|---|---|\n| 1 | 2 |")

          refute_includes html, '<br />'
          assert_includes html, '<table>'
          assert_includes html, '<td>1</td>'
        end

        # =================================================================
        # 属性つきの画像（改善案.md #56）
        # Kramdown は VFM の `{width=10%}` を知らないので、渡す前に <img> へ直す
        # =================================================================

        def test_should_turn_image_attributes_into_img_attributes
          html = MarkdownUtils.render_markdown_to_html('項目 ![a](x.webp){width=10% .vs-bordered #pic} です。')

          assert_includes html, '<img src="x.webp" alt="a" width="10%" id="pic" class="vs-bordered" />'
          refute_includes html, '{width'
        end

        def test_should_keep_quoted_attribute_values_and_escape_them
          html = MarkdownUtils.render_markdown_to_html(%(![a&b](x.webp){crop="30 100" title='x"y'}))

          assert_includes html, 'alt="a&amp;b"'
          assert_includes html, 'crop="30 100"'
          assert_includes html, 'title="x&quot;y"'
        end

        # 記法を解説するインラインコードの中は書き換えない
        def test_should_leave_image_attributes_in_inline_code_untouched
          html = MarkdownUtils.render_markdown_to_html('書き方は `![a](x.webp){width=10%}` です。')

          assert_includes html, '<code>![a](x.webp){width=10%}</code>'
        end
      end
    end
  end
end
