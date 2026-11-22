# frozen_string_literal: true

require_relative '../../../test_helper'
require_relative '../../../../lib/vivlio_starter/cli/techbook/emoji_replacer'

module VivlioStarter
  module CLI
    module Techbook
      class EmojiReplacerTest < Minitest::Test
        FIXTURES_DIR = File.expand_path('fixtures/twemoji', __dir__)

        def test_should_replace_checkmark_emoji
          replacer = EmojiReplacer.new(FIXTURES_DIR)
          html = "Task ✅ done"

          result = replacer.process(html)

          svg_path = File.join(FIXTURES_DIR, "2705.svg")
          expected_img = %(<img src="#{svg_path}" alt="✅" class="emoji vs-emoji" style="width: 1em; height: 1em; vertical-align: -0.15em;">)
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
          expected_img = %(<img src="#{svg_path}" alt="✅" class="emoji vs-emoji" style="width: 1em; height: 1em; vertical-align: -0.15em;">)
          assert_equal "<p>#{expected_img} OK</p>", result
        end

        def test_should_handle_compound_emoji
          # テスト対象は emoji_codepoint の変換ロジック
          # 👨‍💻 = U+1F468 U+200D U+1F4BB
          codepoint = EmojiReplacer.emoji_codepoint("👨‍💻")
          assert_equal "1f468-200d-1f4bb", codepoint

          # Variation Selector-16 (U+FE0F) が除外されることを検証
          # ✅️ = U+2705 U+FE0F
          codepoint_with_vs16 = EmojiReplacer.emoji_codepoint("✅\uFE0F")
          assert_equal "2705", codepoint_with_vs16
        end

        def test_should_not_replace_emoji_inside_img_attributes_when_reprocessed
          replacer = EmojiReplacer.new(FIXTURES_DIR)
          first = replacer.process("Task ✅ done")

          second = replacer.process(first)

          assert_equal first, second
          assert_equal 1, second.scan('<img').count
          assert_includes second, 'alt="✅"'
        end

        def test_should_skip_style_and_script_contents
          replacer = EmojiReplacer.new(FIXTURES_DIR)
          html = '<style>.x::before{content:"✅"}</style><script>const x="✅";</script><p>✅</p>'

          result = replacer.process(html)

          assert_includes result, '<style>.x::before{content:"✅"}</style>'
          assert_includes result, '<script>const x="✅";</script>'
          assert_equal 1, result.scan('<img').count
        end

        def test_should_resolve_emoji_dir_from_project_root
          replacer = EmojiReplacer.new

          default_dir = replacer.send(:default_emoji_dir)

          assert default_dir.end_with?("stylesheets/twemoji"), "Expected path to end with stylesheets/twemoji, got: #{default_dir}"
        end

        # 並んだ絵文字・合成の絵文字の置き換え（改善案 #156）。画像は一時ディレクトリに置く。
        TWEMOJI_NAMES = %w[1f30a 1f5fb 1f468-200d-1f4bb 1f3d4 1f1ef-1f1f5 31-20e3 1f3f3-fe0f-200d-1f308].freeze

        def with_twemoji_dir
          Dir.mktmpdir do |dir|
            TWEMOJI_NAMES.each { File.write(File.join(dir, "#{it}.svg"), '<svg/>') }
            yield EmojiReplacer.new(dir), dir
          end
        end

        def test_should_replace_each_emoji_in_adjacent_run
          with_twemoji_dir do |replacer, dir|
            result = replacer.process('"🌊🌊🗻"')

            assert_equal 3, result.scan('<img').count
            assert_equal 2, result.scan(File.join(dir, '1f30a.svg')).count
            assert_includes result, File.join(dir, '1f5fb.svg')
            assert result.start_with?('"<img') && result.end_with?('">"'), result
          end
        end

        def test_should_keep_compound_emoji_as_one_image
          with_twemoji_dir do |replacer, dir|
            { '👨‍💻' => '1f468-200d-1f4bb', "🏔️" => '1f3d4', '🇯🇵' => '1f1ef-1f1f5',
              "1️⃣" => '31-20e3', "🏳️‍🌈" => '1f3f3-fe0f-200d-1f308' }.each do |emoji, name|
              result = replacer.process("x#{emoji}y")

              assert_equal 1, result.scan('<img').count, emoji
              assert_includes result, File.join(dir, "#{name}.svg")
              assert_includes result, %(alt="#{emoji}")
            end
          end
        end

        def test_should_leave_ascii_digits_and_symbols_as_text
          with_twemoji_dir do |replacer, _dir|
            html = 'x = 24 # ok * 2'

            assert_equal html, replacer.process(html)
          end
        end

        def test_should_drop_variation_selector_only_without_zwj
          assert_equal '1f3d4', EmojiReplacer.emoji_codepoint("🏔️")
          assert_equal '1f3f3-fe0f-200d-1f308', EmojiReplacer.emoji_codepoint("🏳️‍🌈")
        end
      end
    end
  end
end
