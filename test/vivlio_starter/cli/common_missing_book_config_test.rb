# frozen_string_literal: true

# ================================================================
# Test: common_missing_book_config_test.rb
# ================================================================
# 検証内容:
#   - Common.missing_book_config_keys が主要キーの欠落を漏れなく拾う
#   - Common.warn_missing_book_config が ensure_configured! の関門で 1 回だけ案内する
#   - 案内に「直し方」（book.yml へ貼れる記入例）が含まれる
#   - abort しないこと（既存最小構成プロジェクトとの互換性）
# ================================================================

require_relative '../../test_helper'
require 'vivlio_starter/cli/common'

module VivlioStarter
  module CLI
    class CommonMissingBookConfigTest < Minitest::Test
      # 検査対象の状態はモジュール変数なので、他テストへ漏らさないよう退避・復元する
      def setup
        @saved_keys = Common.instance_variable_get(:@missing_book_keys)
        @saved_reported = Common.instance_variable_get(:@missing_book_keys_reported)
      end

      def teardown
        Common.instance_variable_set(:@missing_book_keys, @saved_keys)
        Common.instance_variable_set(:@missing_book_keys_reported, @saved_reported)
      end

      # 主要キーが揃っていれば欠落なし
      def test_should_report_no_missing_keys_when_all_present
        cfg = { book: { main_title: 'タイトル', author: '著者' }, project: { name: 'mybook' } }

        assert_empty Common.missing_book_config_keys(cfg)
      end

      # 空文字列・空白のみ・nil はいずれも未設定として扱う
      def test_should_treat_blank_values_as_missing
        cfg = { book: { main_title: '', author: '   ' }, project: { name: nil } }

        assert_equal [%i[book main_title], %i[book author], %i[project name]],
                     Common.missing_book_config_keys(cfg)
      end

      # 欠落キーだけを拾う
      def test_should_report_only_missing_keys
        cfg = { book: { author: 'A' }, project: { name: 'x' } }

        assert_equal [%i[book main_title]], Common.missing_book_config_keys(cfg)
      end

      # 案内はキー名と、book.yml へそのまま貼れる記入例の両方を含む
      def test_should_warn_with_actionable_example
        arm_missing([%i[book main_title], %i[project name]])

        out, = capture_io { Common.warn_missing_book_config }

        assert_includes out, 'book.main_title'
        assert_includes out, 'project.name'
        assert_includes out, 'book:'
        assert_includes out, 'main_title: 本のタイトル'
        assert_includes out, 'project:'
        assert_includes out, 'name: mybook'
      end

      # 全コマンドが通る関門に置くので、2 回目以降は黙る
      def test_should_warn_only_once
        arm_missing([%i[book author]])

        first, = capture_io { Common.warn_missing_book_config }
        second, = capture_io { Common.warn_missing_book_config }

        assert_includes first, 'book.author'
        assert_empty second
      end

      # 欠落がなければ何も出さない
      def test_should_stay_silent_when_nothing_missing
        arm_missing([])

        out, = capture_io { Common.warn_missing_book_config }

        assert_empty out
      end

      # 欠落があっても abort しない（最小構成プロジェクトを弾かない）
      def test_should_not_abort_on_missing_keys
        arm_missing([%i[book main_title], %i[book author], %i[project name]])

        capture_io { Common.warn_missing_book_config }

        assert true, 'abort せずに通常終了することを確認'
      end

      private

      # reload_configuration! が検査を終えた直後の状態を作る
      def arm_missing(keys)
        Common.instance_variable_set(:@missing_book_keys, keys)
        Common.instance_variable_set(:@missing_book_keys_reported, false)
      end
    end
  end
end
