# frozen_string_literal: true

# ================================================================
# Test: post_process/step_table_test.rb
# ================================================================
# テスト対象:
#   PostProcessCommands の段の表（first_pass_steps・page_steps）と、それを回す
#   run_post_process_steps（v2-architecture-spec.md §3.4）
#   - 失敗したときの扱い: [:error, 文] は 🔴、[:warn, 文] は 🟡 で記録して次の段へ進む。
#     nil は例外をそのまま上げる（表にする前の begin/rescue の有無と同じ）
#   - 条件が偽の段は走らない
#   - 表の行の形（名前の重複が無い・処理が 2 引数）
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/post_process'

module VivlioStarter
  module CLI
    class PostProcessStepTableTest < Minitest::Test
      PLAN = BuildPlan.resolve

      def test_should_log_an_error_row_in_red_and_continue
        ran = []
        steps = [[:a, ->(*) { raise 'こわれた' }, [:error, 'A の処理中にエラー'], nil],
                 [:b, ->(*) { ran << :b }, nil, nil]]

        errors = capture_log(:log_error) { PostProcessCommands.run_post_process_steps(steps, 'x.html', nil, PLAN) }

        assert_equal ['x.html: A の処理中にエラー: こわれた'], errors
        assert_equal [:b], ran, '失敗した段の次へ進む'
      end

      def test_should_log_a_warn_row_in_yellow
        steps = [[:a, ->(*) { raise 'こわれた' }, [:warn, 'A に失敗'], nil]]

        warns = capture_log(:log_warn) { PostProcessCommands.run_post_process_steps(steps, 'x.html', nil, PLAN) }

        assert_equal ['x.html: A に失敗: こわれた'], warns
      end

      def test_should_raise_from_a_row_without_error_handling
        steps = [[:a, ->(*) { raise ArgumentError, 'こわれた' }, nil, nil]]

        assert_raises(ArgumentError) { PostProcessCommands.run_post_process_steps(steps, 'x.html', nil, PLAN) }
      end

      def test_should_skip_a_row_whose_condition_is_false
        ran = []
        steps = [[:a, ->(*) { ran << :a }, nil, ->(_plan) { false }],
                 [:b, ->(html, entry) { ran << [html, entry] }, nil, ->(plan) { plan.equal?(PLAN) }]]

        PostProcessCommands.run_post_process_steps(steps, 'x.html', :entry, PLAN)

        assert_equal [['x.html', :entry]], ran, '条件は plan を受け、処理は html と entry を受ける'
      end

      def test_tables_should_have_unique_names_and_two_argument_handlers
        tables = { first_pass_steps: PostProcessCommands.first_pass_steps,
                   page_steps: PostProcessCommands.page_steps(->(_) {}) }

        tables.each do |table_name, steps|
          names = steps.map(&:first)
          assert_equal names.uniq, names, "#{table_name} に同じ名前の段がある"
          steps.each do |name, handler, on_error, condition|
            assert_equal 2, handler.arity, "#{table_name}.#{name}"
            assert(on_error.nil? || (%i[error warn].include?(on_error[0]) && on_error[1].is_a?(String)), name.to_s)
            assert(condition.nil? || condition.respond_to?(:call), name.to_s)
          end
        end
        assert_equal :normalize_page_breaks, tables[:page_steps].last.first, '二重改ページの正規化は最後'
      end

      private

      def capture_log(level)
        messages = []
        Common.stub(level, ->(message, **) { messages << message }) { yield }
        messages
      end
    end
  end
end
