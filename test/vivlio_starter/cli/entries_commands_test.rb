# frozen_string_literal: true

# ================================================================
# Test: entries_commands_test.rb
# ================================================================
# テスト対象:
#   EntriesCommands モジュール（lib/vivlio_starter/cli/entries.rb）
#
# 検証内容:
#   - build_entry: HTML からのエントリ組み立て（title 優先順位・パス正規化）
#   - extract_html_title: <title> 抽出のフォールバック挙動
#
# 注: 旧 `vs entries`（execute_entries によるルート entries.js 生成）は
#     手動フロー撤去（vivlioverso-manual-flow-removal-spec.md）で削除済み。
#     本モジュールは workspace entries 生成（VivliostyleConfigWriter /
#     EpubBuilder）の実装基盤としてヘルパのみを提供する。
# ================================================================

require 'test_helper'
require 'fileutils'
require 'tmpdir'
require 'vivlio_starter/cli/entries'

module VivlioStarter
  module CLI
    # EntriesCommands のユニットテスト
    class EntriesCommandsTest < Minitest::Test
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
    end
  end
end
