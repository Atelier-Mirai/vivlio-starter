# frozen_string_literal: true

# ================================================================
# Test: build_helpers_test.rb
# ================================================================
# テスト対象:
#   Build::ChapterConfig（lib/vivlio/starter/cli/build/chapter_config.rb）
#
# 検証内容:
#   - expand_chapter_range: 範囲文字列 "2-5" → [2,3,4,5] への展開
#   - parse_chapter_numbers_from_string: カンマ区切り・範囲の解析
#   - 無効な入力（逆順、文字列等）のエラーハンドリング
# ================================================================

require 'test_helper'
require 'vivlio/starter/cli/common'
require 'vivlio/starter/cli/build'

module Vivlio
  module Starter
    module CLI
      # Build::ChapterConfig のユニットテスト
      class BuildHelpersTest < Minitest::Test
        # expand_chapter_range: 正常系
        def test_expand_chapter_range_valid
          assert_equal [2, 3, 4, 5], Build::ChapterConfig.expand_chapter_range('2-5')
          assert_equal [11, 12, 13], Build::ChapterConfig.expand_chapter_range('11-13')
          assert_equal [2], Build::ChapterConfig.expand_chapter_range('2-2')
        end

        def test_expand_chapter_range_invalid
          assert_equal [], Build::ChapterConfig.expand_chapter_range('5-2') # 逆順
          assert_equal [], Build::ChapterConfig.expand_chapter_range('abc')
          assert_equal [], Build::ChapterConfig.expand_chapter_range('11')
          assert_equal [], Build::ChapterConfig.expand_chapter_range(nil)
        end

        # ================================================================
        # parse_chapter_numbers_from_string のテスト
        # ================================================================
        def test_parse_chapter_numbers_from_string_comma_separated
          result = Build::ChapterConfig.parse_chapter_numbers_from_string('02, 11, 12, 91')
          assert_equal [2, 11, 12, 91], result
        end

        def test_parse_chapter_numbers_from_string_with_range
          result = Build::ChapterConfig.parse_chapter_numbers_from_string('02-05, 11, 91')
          assert_equal [2, 3, 4, 5, 11, 91], result
        end

        def test_parse_chapter_numbers_from_string_only_range
          result = Build::ChapterConfig.parse_chapter_numbers_from_string('11-15')
          assert_equal [11, 12, 13, 14, 15], result
        end

        def test_parse_chapter_numbers_from_string_with_duplicates
          result = Build::ChapterConfig.parse_chapter_numbers_from_string('02, 11, 02, 12')
          assert_equal [2, 11, 12], result # 重複除去 + ソート
        end

        def test_parse_chapter_numbers_from_string_mixed_format_error
          # 混在形式はエラー
          error = assert_raises(ArgumentError) do
            Build::ChapterConfig.parse_chapter_numbers_from_string('02-12, 21-customize, 91')
          end
          assert_match(/混在形式は非対応です/, error.message)
        end

        # ================================================================
        # all_integers? のテスト
        # ================================================================
        def test_all_integers_true
          assert Build::ChapterConfig.all_integers?([1, 2, 3])
          assert Build::ChapterConfig.all_integers?(['1', '2', '3'])
          assert Build::ChapterConfig.all_integers?([02, 11, 12])
        end

        def test_all_integers_false
          refute Build::ChapterConfig.all_integers?([1, 2, 'abc'])
          refute Build::ChapterConfig.all_integers?(['11-install', '12-tutorial'])
          refute Build::ChapterConfig.all_integers?(nil)
          refute Build::ChapterConfig.all_integers?('not an array')
        end

        # ================================================================
        # configured_chapters のテスト（catalog.yml ベース）
        # ================================================================
        def test_configured_chapters_from_catalog
          catalog = {
            'PREFACE' => ['00-preface'],
            'CHAPTERS' => ['11-install', '12-tutorial'],
            'APPENDICES' => ['91-appendix'],
            'POSTFACE' => ['99-postface']
          }
          with_mock_catalog(catalog) do
            with_mock_chapter_files(['00-preface.md', '11-install.md', '12-tutorial.md', '91-appendix.md', '99-postface.md']) do
              result = Build::ChapterConfig.configured_chapters
              assert_equal ['00-preface.md', '11-install.md', '12-tutorial.md', '91-appendix.md', '99-postface.md'], result
            end
          end
        end

        def test_configured_chapters_with_shorthand
          catalog = {
            'CHAPTERS' => ['11-13']  # ショートハンド
          }
          with_mock_catalog(catalog) do
            with_mock_chapter_files(['11-install.md', '12-tutorial.md', '13-advanced.md']) do
              result = Build::ChapterConfig.configured_chapters
              assert_equal ['11-install.md', '12-tutorial.md', '13-advanced.md'], result
            end
          end
        end

        def test_configured_chapters_missing_files
          catalog = {
            'CHAPTERS' => ['11-install', '12-tutorial', '13-nonexistent']
          }
          with_mock_catalog(catalog) do
            with_mock_chapter_files(['11-install.md', '12-tutorial.md']) do
              result = Build::ChapterConfig.configured_chapters
              # 存在しない 13-nonexistent はスキップ
              assert_equal ['11-install.md', '12-tutorial.md'], result
            end
          end
        end

        private

        # catalog.yml をモック
        def with_mock_catalog(catalog_hash)
          Build::CatalogLoader.stub(:load_catalog, catalog_hash) do
            yield
          end
        end

        # Dir.glob をスタブしてモックファイルを返す
        def with_mock_chapter_files(files)
          full_paths = files.map { |f| File.join(Common::CONTENTS_DIR, f) }
          Dir.stub(:glob, full_paths) do
            # File.exist? もモック
            File.stub(:exist?, ->(path) { full_paths.include?(path) || path == Build::CatalogLoader::CATALOG_FILE }) do
              yield
            end
          end
        end
      end
    end
  end
end
