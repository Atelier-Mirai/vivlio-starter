# frozen_string_literal: true

# ================================================================
# Test: common_validate_book_config_test.rb
# ================================================================
# 検証内容:
#   - Common.validate_book_config! が必須推奨キーの欠落時に警告を出す（9-2 の回帰テスト）
#   - 欠落がない場合は警告を出さない
#   - abort しないこと（既存最小構成プロジェクトとの互換性）
# ================================================================

require_relative '../../test_helper'
require 'vivlio_starter/cli/common'

module VivlioStarter
  module CLI
    class CommonValidateBookConfigTest < Minitest::Test
      # 主要キーが揃っていれば警告を出さない
      def test_no_warning_when_all_required_keys_present
        cfg = {
          book: { main_title: 'タイトル', author: '著者' },
          project: { name: 'mybook' }
        }
        _out, err = capture_io { Common.validate_book_config!(cfg) }
        refute_match(/book\.yml/, err)
      end

      # book.main_title が欠落していれば警告が出る
      def test_warns_when_main_title_missing
        cfg = { book: { author: 'A' }, project: { name: 'x' } }
        _out, err = capture_io { Common.validate_book_config!(cfg) }
        assert_match(/book\.main_title/, err)
      end

      # 複数キー欠落時は全部列挙される
      def test_lists_all_missing_keys
        cfg = {}
        _out, err = capture_io { Common.validate_book_config!(cfg) }
        assert_match(/book\.main_title/, err)
        assert_match(/book\.author/, err)
        assert_match(/project\.name/, err)
      end

      # 空文字列は blank 扱いされる
      def test_blank_string_treated_as_missing
        cfg = { book: { main_title: '', author: '   ' }, project: { name: nil } }
        _out, err = capture_io { Common.validate_book_config!(cfg) }
        assert_match(/book\.main_title/, err)
        assert_match(/book\.author/, err)
        assert_match(/project\.name/, err)
      end

      # abort しない（exception を送出しない）
      def test_does_not_abort
        cfg = {}
        capture_io { Common.validate_book_config!(cfg) }
        assert true, 'abort せずに通常終了することを確認'
      end
    end
  end
end
