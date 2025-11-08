# frozen_string_literal: true

require 'test_helper'
require 'vivlio/starter/cli/common'
require 'vivlio/starter/cli/build_helpers'

module Vivlio
  module Starter
    module CLI
      class BuildHelpersTest < Minitest::Test
        # ================================================================
        # expand_chapter_range のテスト
        # ================================================================
        def test_expand_chapter_range_valid
          assert_equal [2, 3, 4, 5], BuildHelpers.expand_chapter_range('2-5')
          assert_equal [11, 12, 13], BuildHelpers.expand_chapter_range('11-13')
          assert_equal [2], BuildHelpers.expand_chapter_range('2-2')
        end

        def test_expand_chapter_range_invalid
          assert_equal [], BuildHelpers.expand_chapter_range('5-2') # 逆順
          assert_equal [], BuildHelpers.expand_chapter_range('abc')
          assert_equal [], BuildHelpers.expand_chapter_range('11')
          assert_equal [], BuildHelpers.expand_chapter_range(nil)
        end

        # ================================================================
        # parse_chapter_numbers_from_string のテスト
        # ================================================================
        def test_parse_chapter_numbers_from_string_comma_separated
          result = BuildHelpers.parse_chapter_numbers_from_string('02, 11, 12, 91')
          assert_equal [2, 11, 12, 91], result
        end

        def test_parse_chapter_numbers_from_string_with_range
          result = BuildHelpers.parse_chapter_numbers_from_string('02-05, 11, 91')
          assert_equal [2, 3, 4, 5, 11, 91], result
        end

        def test_parse_chapter_numbers_from_string_only_range
          result = BuildHelpers.parse_chapter_numbers_from_string('11-15')
          assert_equal [11, 12, 13, 14, 15], result
        end

        def test_parse_chapter_numbers_from_string_with_duplicates
          result = BuildHelpers.parse_chapter_numbers_from_string('02, 11, 02, 12')
          assert_equal [2, 11, 12], result # 重複除去 + ソート
        end

        def test_parse_chapter_numbers_from_string_mixed_format_error
          # 混在形式はエラー
          error = assert_raises(ArgumentError) do
            BuildHelpers.parse_chapter_numbers_from_string('02-12, 21-customize, 91')
          end
          assert_match(/混在形式は非対応です/, error.message)
        end

        # ================================================================
        # all_integers? のテスト
        # ================================================================
        def test_all_integers_true
          assert BuildHelpers.all_integers?([1, 2, 3])
          assert BuildHelpers.all_integers?(['1', '2', '3'])
          assert BuildHelpers.all_integers?([02, 11, 12])
        end

        def test_all_integers_false
          refute BuildHelpers.all_integers?([1, 2, 'abc'])
          refute BuildHelpers.all_integers?(['11-install', '12-tutorial'])
          refute BuildHelpers.all_integers?(nil)
          refute BuildHelpers.all_integers?('not an array')
        end

        # ================================================================
        # configured_chapters のテスト（統合テスト）
        # ================================================================
        def test_configured_chapters_all
          with_mock_chapter_files(['02-preface.md', '11-install.md', '12-tutorial.md', '91-appendix.md']) do
            with_config({ 'chapters' => 'all' }) do
              result = BuildHelpers.configured_chapters
              # 'all' は全章のファイル名リストを返す
              assert_equal ['02-preface.md', '11-install.md', '12-tutorial.md', '91-appendix.md'], result
            end
          end
        end

        def test_configured_chapters_filename_array
          with_config({ 'chapters' => ['11-install', '12-tutorial'] }) do
            result = BuildHelpers.configured_chapters
            assert_equal ['11-install.md', '12-tutorial.md'], result
          end
        end

        def test_configured_chapters_number_array
          # テスト用のダミーファイルを想定（実際のファイルは不要）
          with_mock_chapter_files(['02-preface.md', '11-install.md', '12-tutorial.md']) do
            with_config({ 'chapters' => [2, 11, 12] }) do
              result = BuildHelpers.configured_chapters
              assert_equal ['02-preface.md', '11-install.md', '12-tutorial.md'], result
            end
          end
        end

        def test_configured_chapters_comma_separated_string
          with_mock_chapter_files(['02-preface.md', '11-install.md', '91-appendix.md']) do
            with_config({ 'chapters' => '02, 11, 91' }) do
              result = BuildHelpers.configured_chapters
              assert_equal ['02-preface.md', '11-install.md', '91-appendix.md'], result
            end
          end
        end

        def test_configured_chapters_range_string
          with_mock_chapter_files(['11-install.md', '12-tutorial.md', '13-advanced.md']) do
            with_config({ 'chapters' => '11-13' }) do
              result = BuildHelpers.configured_chapters
              assert_equal ['11-install.md', '12-tutorial.md', '13-advanced.md'], result
            end
          end
        end

        def test_configured_chapters_range_with_comma
          with_mock_chapter_files(['02-preface.md', '11-install.md', '12-tutorial.md', '91-appendix.md']) do
            with_config({ 'chapters' => '02, 11-12, 91' }) do
              result = BuildHelpers.configured_chapters
              assert_equal ['02-preface.md', '11-install.md', '12-tutorial.md', '91-appendix.md'], result
            end
          end
        end

        def test_configured_chapters_nonexistent_numbers
          # 存在しない番号はスキップされる
          with_mock_chapter_files(['11-install.md', '12-tutorial.md']) do
            with_config({ 'chapters' => [02, 11, 12, 13] }) do
              result = BuildHelpers.configured_chapters
              # 02 と 13 は存在しないのでスキップ
              assert_equal ['11-install.md', '12-tutorial.md'], result
            end
          end
        end

        private

        # CONFIG を一時的に上書き
        def with_config(config_hash)
          original_config = Common.const_get(:CONFIG).dup
          Common.const_set(:CONFIG, original_config.merge(config_hash))
          yield
        ensure
          Common.const_set(:CONFIG, original_config)
        end

        # Dir.glob をスタブしてモックファイルを返す
        def with_mock_chapter_files(files)
          full_paths = files.map { |f| File.join(Common::CONTENTS_DIR, f) }
          Dir.stub(:glob, full_paths) do
            yield
          end
        end
      end
    end
  end
end
