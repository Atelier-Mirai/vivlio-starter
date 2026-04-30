# frozen_string_literal: true

require_relative '../../../../test_helper'
require_relative '../../../../../lib/vivlio/starter/cli/techbook/emoji_replacer'

module Vivlio
  module Starter
    module CLI
      module Techbook
        class EmojiReplacerTest < Minitest::Test
          FIXTURES_DIR = File.expand_path('fixtures/twemoji', __dir__)

          def test_should_replace_checkmark_emoji
            replacer = EmojiReplacer.new(FIXTURES_DIR)
            html = "Task ✅ done"

            result = replacer.process(html)

            svg_path = File.join(FIXTURES_DIR, "2705.svg")
            expected_img = %(<img src="#{svg_path}" alt="✅" class="emoji vs-emoji" width="1em" height="1em" style="vertical-align: -0.15em;">)
            assert_includes result, expected_img
            assert_equal "Task #{expected_img} done", result
          end

          def test_should_skip_emoji_without_svg
            replacer = EmojiReplacer.new(FIXTURES_DIR)
            # 🎉 (1f389) has no SVG fixture file
            html = "Party 🎉 time"

            result = replacer.process(html)

            assert_includes result, "🎉"
            refute_includes result, "<img"
          end

          def test_should_replace_all_occurrences_of_same_emoji
            replacer = EmojiReplacer.new(FIXTURES_DIR)
            html = "✅ first ✅ second ✅ third"

            result = replacer.process(html)

            svg_path = File.join(FIXTURES_DIR, "2705.svg")
            assert_equal 3, result.scan(%(<img src="#{svg_path}")).count
            # alt 属性内の ✅ は残るが、テキストノードとしての ✅ はすべて置換される
            result_without_alt = result.gsub(/alt="[^"]*"/, "")
            refute_includes result_without_alt, "✅"
          end

          def test_should_return_html_unchanged_when_no_emoji
            replacer = EmojiReplacer.new(FIXTURES_DIR)
            html = "<p>Plain text with no emoji at all.</p>"

            result = replacer.process(html)

            assert_equal html, result
          end

          def test_should_preserve_surrounding_html_tags
            replacer = EmojiReplacer.new(FIXTURES_DIR)
            html = "<p>✅ OK</p>"

            result = replacer.process(html)

            svg_path = File.join(FIXTURES_DIR, "2705.svg")
            expected_img = %(<img src="#{svg_path}" alt="✅" class="emoji vs-emoji" width="1em" height="1em" style="vertical-align: -0.15em;">)
            assert_equal "<p>#{expected_img} OK</p>", result
          end

          def test_should_handle_compound_emoji
            replacer = EmojiReplacer.new(FIXTURES_DIR)

            # テスト対象は emoji_codepoint の変換ロジック
            # send で private メソッドを直接テストする
            # 👨‍💻 = U+1F468 U+200D U+1F4BB
            codepoint = replacer.send(:emoji_codepoint, "👨‍💻")
            assert_equal "1f468-200d-1f4bb", codepoint

            # Variation Selector-16 (U+FE0F) が除外されることを検証
            # ✅️ = U+2705 U+FE0F
            codepoint_with_vs16 = replacer.send(:emoji_codepoint, "✅\uFE0F")
            assert_equal "2705", codepoint_with_vs16
          end

          def test_should_resolve_emoji_dir_from_project_root
            replacer = EmojiReplacer.new

            default_dir = replacer.send(:default_emoji_dir)

            assert default_dir.end_with?("stylesheets/twemoji"), "Expected path to end with stylesheets/twemoji, got: #{default_dir}"
          end
        end
      end
    end
  end
end
