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

        # titleタグがない場合はファイル名から番号を除いたものがタイトルになる
        def test_build_entry_uses_filename_when_no_title_tag
          Dir.mktmpdir do |dir|
            path = File.join(dir, '11-quickstart.html')
            File.write(path, '<html><body>no title</body></html>')

            entry = EntriesCommands.build_entry(path)

            assert_equal 'quickstart', entry[:title]
          end
        end

        # titleタグがある場合はそちらが優先される
        def test_build_entry_prefers_html_title_tag
          Dir.mktmpdir do |dir|
            path = File.join(dir, '11-quickstart.html')
            File.write(path, '<html><title>はじめに</title></html>')

            entry = EntriesCommands.build_entry(path)

            assert_equal 'はじめに', entry[:title]
          end
        end

        # パスが ./ で始まっていない場合は正規化される
        def test_build_entry_normalizes_path_prefix
          Dir.mktmpdir do |dir|
            path = File.join(dir, '11-intro.html')
            File.write(path, '<html></html>')

            entry = EntriesCommands.build_entry(path)

            assert entry[:path].start_with?('./'), "パスが ./ で始まるはずです: #{entry[:path]}"
          end
        end

        # 存在しないファイルの場合 extract_html_title は nil を返す
        def test_extract_html_title_returns_nil_for_missing_file
          result = EntriesCommands.extract_html_title('/nonexistent/path/file.html')

          assert_nil result
        end

        # resolve_token は .html 拡張子付きトークンをそのまま解決する
        def test_resolve_token_with_html_extension
          Dir.mktmpdir do |dir|
            File.write(File.join(dir, '11-intro.html'), '')

            result = EntriesCommands.resolve_token(dir, '11-intro.html')

            assert_equal [File.join(dir, '11-intro.html')], result
          end
        end

        # resolve_token は拡張子なしトークンをワイルドカードで解決する
        def test_resolve_token_without_extension_matches_glob
          Dir.mktmpdir do |dir|
            File.write(File.join(dir, '11-intro.html'), '')

            result = EntriesCommands.resolve_token(dir, '11-intro')

            assert_includes result, File.join(dir, '11-intro.html')
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
