# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/metrics/parallel_runner.rb
# ================================================================
# 責務:
#   章解析をスレッドプールで並列実行する。
#
# 機能:
#   - 自動並列度決定（Etc.nprocessors と上限4の小さい方）
#   - VIVLIO_METRICS_CONCURRENCY 環境変数で上書き可能
#   - キューベースのスレッドプール実装
#
# Ruby 4.0+ 構文:
#   - it パラメータ
#   - エンドレスメソッド
# ================================================================

require 'etc'

module Vivlio
  module Starter
    module CLI
      module Metrics
        # 並列実行を管理する
        class ParallelRunner
          CONCURRENCY_ENV = 'VIVLIO_METRICS_CONCURRENCY'
          MAX_CONCURRENCY = 4

          def initialize(concurrency: nil)
            @concurrency = concurrency || determine_concurrency
          end

          attr_reader :concurrency

          # 並列度を決定する（build コマンドと同じロジック）
          def determine_concurrency
            env_value = ENV[CONCURRENCY_ENV].to_i
            return env_value if env_value.positive?

            n_cores = Etc.respond_to?(:nprocessors) ? Etc.nprocessors : 2
            n_cores.clamp(1, MAX_CONCURRENCY)
          end

          # アイテムを並列処理する
          def parallel_map(items, &block)
            list = Array(items)
            return [] if list.empty?
            return list.map(&block) if concurrency <= 1

            results = Array.new(list.size)
            mutex = Mutex.new
            queue = Queue.new

            list.each_with_index { |item, idx| queue << [item, idx] }
            sentinel = Object.new
            concurrency.times { queue << sentinel }

            workers = Array.new(concurrency) do
              Thread.new do
                loop do
                  entry = queue.pop
                  break if entry.equal?(sentinel)

                  item, idx = entry
                  result = block.call(item)
                  mutex.synchronize { results[idx] = result }
                end
              end
            end

            workers.each(&:join)
            results
          end

          # アイテムを並列処理し、完了時にコールバックを呼ぶ
          def parallel_each_with_progress(items, on_complete: nil, &block)
            list = Array(items)
            return if list.empty?

            if concurrency <= 1
              list.each do |item|
                result = block.call(item)
                on_complete&.call(item, result)
              end
              return
            end

            mutex = Mutex.new
            queue = Queue.new

            list.each { queue << it }
            sentinel = Object.new
            concurrency.times { queue << sentinel }

            workers = Array.new(concurrency) do
              Thread.new do
                loop do
                  item = queue.pop
                  break if item.equal?(sentinel)

                  result = block.call(item)
                  mutex.synchronize { on_complete&.call(item, result) }
                end
              end
            end

            workers.each(&:join)
          end
        end
      end
    end
  end
end
