# frozen_string_literal: true

# ================================================================
# Test: guards/guard_test.rb
# ================================================================
# テスト対象:
#   Guards::Guard.run!（lib/vivlio_starter/cli/guards.rb）
#
# 検証内容（docs/specs/precondition-guard-spec.md §7.2）:
#   GG-01: error 違反あり → GuardError を raise・件数メッセージ・🔴 出力
#   GG-02: warn のみ → raise しない・🟡 出力
#   GG-03: 違反なし → raise しない・出力なし
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/guards'

module VivlioStarter
  module CLI
    class GuardRunTest < Minitest::Test
      # GG-01: error 違反があれば GuardError を送出し、🔴 で違反を出力する
      def test_should_raise_guard_error_with_counts_when_error_violation_exists
        out, = capture_io do
          error = assert_raises(Guards::GuardError) do
            Guards::Guard.run!(stub_check(:error, '致命的な違反'), stub_check(:warn, '軽微な違反'))
          end
          assert_includes error.message, 'エラー 1 件 / 警告 1 件'
        end

        assert_includes out, '🔴 致命的な違反'
        assert_includes out, '🟡 軽微な違反'
      end

      # GG-02: warn のみなら raise せず、🟡 出力のみで本処理へ進める
      def test_should_not_raise_when_only_warnings
        out, = capture_io do
          Guards::Guard.run!(stub_check(:warn, '軽微な違反'))
        end

        assert_includes out, '🟡 軽微な違反'
      end

      # GG-03: 違反なしなら何も出力せず通過する
      def test_should_pass_silently_when_no_violations
        out, = capture_io do
          Guards::Guard.run!(stub_check(nil, nil))
        end

        assert_empty out
      end

      # detail は Common.log_* の detail: としてインデント表示される
      def test_should_print_detail_lines_indented
        check = Class.new(Guards::BaseCheck) do
          define_method(:validate) do
            [Guards::Violation.new(severity: :error, message: '違反', detail: ['- contents/89.md'])]
          end
        end.new

        out, = capture_io do
          assert_raises(Guards::GuardError) { Guards::Guard.run!(check) }
        end

        assert_includes out, '- contents/89.md'
      end

      private

      # 指定 severity の違反を1件返す Check を生成する（severity が nil なら合格）
      def stub_check(severity, message)
        Class.new(Guards::BaseCheck) do
          define_method(:validate) do
            return [] if severity.nil?

            [Guards::Violation.new(severity:, message:, detail: nil)]
          end
        end.new
      end
    end
  end
end
