# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require 'nokogiri'
require_relative '../../../../lib/vivlio_starter/cli/post_process'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # split_kbd_combinations! は、`<kbd>Ctrl + S</kbd>` を `<kbd>Ctrl</kbd> + <kbd>S</kbd>` と
      # 同じに組む（改善案.md #9）。キーごとに <kbd> を閉じて開き直さずに書けるようにする。
      class KbdCombinationTest < Minitest::Test
        def apply(body_html)
          html = "<!DOCTYPE html>\n<html><head><title>t</title></head><body>\n#{body_html}\n</body></html>\n"

          Tempfile.create(['vs_kbd_combination_', '.html']) do |f|
            f.write(html)
            f.flush
            PostProcessCommands.split_kbd_combinations!(f.path)
            return Nokogiri::HTML(File.read(f.path, encoding: 'utf-8')).at_css('p').inner_html
          end
        end

        def test_should_split_combination_keeping_spaces_around_plus
          assert_equal '保存は <kbd>Ctrl</kbd> + <kbd>S</kbd> で行います。',
                       apply('<p>保存は <kbd>Ctrl + S</kbd> で行います。</p>')
        end

        def test_should_split_combination_written_without_spaces
          assert_equal '<kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>S</kbd>',
                       apply('<p><kbd>Ctrl+Shift+S</kbd></p>')
        end

        # `+` のキーそのものは分けない
        def test_should_keep_plus_key
          assert_equal '<kbd>+</kbd>', apply('<p><kbd>+</kbd></p>')
          assert_equal '<kbd>Ctrl</kbd> + <kbd>+</kbd>', apply('<p><kbd>Ctrl + +</kbd></p>')
          assert_equal '<kbd>Ctrl</kbd>+<kbd>+</kbd>', apply('<p><kbd>Ctrl++</kbd></p>')
        end

        # 1 つのキーや、キーを入れ子にした HTML はそのまま
        def test_should_leave_single_keys_and_nested_markup
          assert_equal '<kbd>Enter</kbd>', apply('<p><kbd>Enter</kbd></p>')

          nested = '<kbd><kbd>Ctrl</kbd>+<kbd>S</kbd></kbd>'

          assert_equal nested, apply("<p>#{nested}</p>")
        end

        def test_should_keep_attributes_on_each_key
          assert_equal '<kbd class="mac">⌘</kbd> + <kbd class="mac">S</kbd>',
                       apply('<p><kbd class="mac">⌘ + S</kbd></p>')
        end
      end
    end
  end
end
