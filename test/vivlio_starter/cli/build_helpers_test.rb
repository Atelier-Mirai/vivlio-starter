# frozen_string_literal: true

# ================================================================
# Test: build_helpers_test.rb
# ================================================================
# テスト対象:
#   Build::ChapterConfig（lib/vivlio_starter/cli/build/chapter_config.rb）
#
# 検証内容:
#   - expand_chapter_range: 範囲文字列 "2-5" → [2,3,4,5] への展開
#   - parse_chapter_numbers_from_string: カンマ区切り・範囲の解析
#   - 無効な入力（逆順、文字列等）のエラーハンドリング
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build'

module VivlioStarter
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

    end
  end
end
