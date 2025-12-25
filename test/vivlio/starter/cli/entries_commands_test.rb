# frozen_string_literal: true

# ================================================================
# Test: entries_commands_test.rb
# ================================================================
# テスト対象:
#   EntriesCommands モジュール（lib/vivlio/starter/cli/entries.rb）
#
# 検証内容:
#   - 指定ファイルからの entries.js 生成
#   - 引数なし時の全 HTML ファイル検出
#   - 生成される JSON 構造の正確性
# ================================================================

require 'test_helper'
require 'fileutils'
require 'tmpdir'
require 'vivlio/starter/cli/entries'

module Vivlio
  module Starter
    module CLI
      # EntriesCommands のユニットテスト
      class EntriesCommandsTest < Minitest::Test
        # 指定ファイルから entries.js が生成されることを確認
        def test_execute_entries_generates_entries_js_for_specified_files
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              File.write('11-intro.html', '<html><title>Intro</title></html>')
              File.write('12-guide.html', '<html><title>Guide</title></html>')

              EntriesCommands.execute_entries(options_context, %w[11-intro 12-guide])

              output = File.read('entries.js')
              assert_includes output, '"path": "./11-intro.html"'
              assert_includes output, '"title": "Intro"'
              assert_includes output, '"path": "./12-guide.html"'
            end
          end
        end

        def test_execute_entries_defaults_to_all_html_when_no_tokens
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              File.write('11-intro.html', '<html><title>Intro</title></html>')
              File.write('draft.txt', 'ignore me')

              EntriesCommands.execute_entries(options_context, [])

              output = File.read('entries.js')
              assert_includes output, '"path": "./11-intro.html"'
              refute_includes output, 'draft.txt'
            end
          end
        end

        private

        def options_context
          { options: { verbose: false } }
        end
      end
    end
  end
end
