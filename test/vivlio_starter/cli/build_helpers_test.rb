# frozen_string_literal: true

# ================================================================
# Test: build_helpers_test.rb
# ================================================================
# テスト対象:
#   Build::ChapterConfig（lib/vivlio_starter/cli/build/chapter_config.rb）
#
# 検証内容:
#   - parse_chapter_numbers_from_string: 単一・範囲・カンマ区切りの展開
#   - 番号指定でない綴り（ファイルベース名混在）に nil を返すこと
#     ＝ HeadingProcessor が「行ごとのトークン」解釈へ抜ける合図
#   - 逆順の範囲をその部分だけ落とすこと
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build'

module VivlioStarter
  module CLI
    # Build::ChapterConfig のユニットテスト
    class BuildHelpersTest < Minitest::Test
      def test_should_expand_single_numbers_and_ranges
        parse = ->(str) { Build::ChapterConfig.parse_chapter_numbers_from_string(str) }

        assert_equal [11], parse.call('11')
        assert_equal [11, 12, 13, 14, 15], parse.call('11-15')
        assert_equal [2], parse.call('2-2')
        assert_equal [2, 11, 12, 91], parse.call('02, 11, 12, 91')
        assert_equal [2, 3, 4, 5, 11, 91], parse.call('02-05, 11, 91')
      end

      def test_should_sort_and_deduplicate
        result = Build::ChapterConfig.parse_chapter_numbers_from_string('12, 02, 11, 02, 11-12')

        assert_equal [2, 11, 12], result
      end

      # 番号指定でなければ nil。呼び出し側（HeadingProcessor）はこれを合図に
      # ファイルベース名の並びとして読み直す
      def test_should_return_nil_when_not_a_number_spec
        parse = ->(str) { Build::ChapterConfig.parse_chapter_numbers_from_string(str) }

        assert_nil parse.call('02-12, 21-customize, 91')
        assert_nil parse.call('11-install')
        assert_nil parse.call('abc')
        assert_nil parse.call("11-install\n12-tutorial")
      end

      # 空の指定は「番号指定だが 1 章も選ばれていない」＝ [] であって nil ではない
      def test_should_return_empty_array_for_blank_input
        parse = ->(str) { Build::ChapterConfig.parse_chapter_numbers_from_string(str) }

        assert_equal [], parse.call('')
        assert_equal [], parse.call('  ,  ')
        assert_equal [], parse.call(nil)
      end

      # 逆順の範囲は展開すると著者が書いた向きと逆の章立てが黙ってできるので落とす
      def test_should_drop_reversed_ranges_only
        parse = ->(str) { Build::ChapterConfig.parse_chapter_numbers_from_string(str) }

        assert_equal [], parse.call('5-2')
        assert_equal [11, 91], parse.call('5-2, 11, 91')
      end
    end
  end
end
