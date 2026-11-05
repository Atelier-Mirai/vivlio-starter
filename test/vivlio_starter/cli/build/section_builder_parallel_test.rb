# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/build'

module VivlioStarter
  module CLI
    module Build
      # SectionBuilder.parallel_each が CLI の検証オプションを作業スレッドへ渡すことの確認。
      # 渡さないと、章の前処理が --verify-links を読めず外部 URL を確かめない
      class SectionBuilderParallelTest < Minitest::Test
        def teardown
          Thread.current[:vs_verify_options] = nil
        end

        def test_should_pass_verify_options_to_worker_threads
          Thread.current[:vs_verify_options] = { verify_external_links: true }
          seen = Queue.new

          SectionBuilder.parallel_each(%w[a b c d], concurrency: 2) do
            seen << [Thread.current == Thread.main, Thread.current[:vs_verify_options]]
          end

          results = Array.new(seen.size) { seen.pop }
          assert_equal 4, results.size
          assert results.none?(&:first), '作業スレッドで実行されるはずです'
          assert(results.all? { |_, opts| opts == { verify_external_links: true } },
                 '呼び出し元の --verify-links の指定が作業スレッドから読めるはずです')
        end
      end
    end
  end
end
