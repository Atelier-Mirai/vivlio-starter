# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/metrics/parallel_runner'

module VivlioStarter
  module CLI
    module Metrics
      class ParallelRunnerTest < Minitest::Test
        def teardown
          ENV.delete('VIVLIO_METRICS_CONCURRENCY')
        end

        def test_determine_concurrency_uses_env_when_set
          ENV['VIVLIO_METRICS_CONCURRENCY'] = '8'
          runner = ParallelRunner.new

          assert_equal 8, runner.concurrency
        end

        def test_determine_concurrency_respects_max_limit
          runner = ParallelRunner.new

          assert runner.concurrency <= ParallelRunner::MAX_CONCURRENCY
          assert runner.concurrency >= 1
        end

        def test_parallel_map_returns_results_in_order
          runner = ParallelRunner.new(concurrency: 2)
          items = [1, 2, 3, 4, 5]

          results = runner.parallel_map(items) { it * 2 }

          assert_equal [2, 4, 6, 8, 10], results
        end

        def test_parallel_map_with_single_concurrency
          runner = ParallelRunner.new(concurrency: 1)
          items = [1, 2, 3]

          results = runner.parallel_map(items) { it * 2 }

          assert_equal [2, 4, 6], results
        end

        def test_parallel_map_returns_empty_for_empty_input
          runner = ParallelRunner.new(concurrency: 2)

          results = runner.parallel_map([]) { it * 2 }

          assert_empty results
        end

        def test_parallel_each_with_progress_calls_on_complete
          runner = ParallelRunner.new(concurrency: 2)
          items = [1, 2, 3]
          completed_items = []
          mutex = Mutex.new

          runner.parallel_each_with_progress(items, on_complete: ->(item, result) {
            mutex.synchronize { completed_items << [item, result] }
          }) do |item|
            item * 2
          end

          assert_equal 3, completed_items.size
          completed_items.each do |item, result|
            assert_equal item * 2, result
          end
        end

        def test_parallel_each_with_progress_single_concurrency
          runner = ParallelRunner.new(concurrency: 1)
          items = [1, 2, 3]
          results = []

          runner.parallel_each_with_progress(items, on_complete: ->(item, result) {
            results << [item, result]
          }) do |item|
            item * 2
          end

          assert_equal [[1, 2], [2, 4], [3, 6]], results
        end

        def test_parallel_each_with_progress_handles_nil_callback
          runner = ParallelRunner.new(concurrency: 2)
          items = [1, 2, 3]

          # エラーが起きないことを確認
          runner.parallel_each_with_progress(items, on_complete: nil) { it * 2 }

          assert true
        end
      end
    end
  end
end
