# frozen_string_literal: true

# ================================================================
# Test: build/branch_parallelism_test.rb
# ================================================================
# テスト対象:
#   UnifiedBuildPipeline の枝並列実行（build-target-parallelization-spec.md §1・§3.6）
#
# 検証内容:
#   - 分岐条件: 両枝に仕事があるときだけ分岐する / VIVLIO_BUILD_PARALLEL=0 で戻る
#   - 逐次等価: 並列でもステップ計時の並びは「共通前段 → PDF 枝 → EPUB 枝 → 合流」
#   - ログ: 子枝のログは合流時にまとめて出る（PDF 枝の出力より後ろ）
#   - 失敗の伝播: 子枝の例外は合流時に親へ投げ直される
#   - 中断: 中断フラグが立つと、子枝は次のステップへ進まない
#
# 実ステップは差し替えたダミーで、ここで検証するのは骨組みだけである。
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/loader'
require 'vivlio_starter/cli/build'
require 'vivlio_starter/cli/build/pipeline'

module VivlioStarter
  module CLI
    class BranchParallelismTest < Minitest::Test
      def setup
        @original_level = Common.log_level
        @original_flag = ENV.fetch('VIVLIO_BUILD_PARALLEL', nil)
        Common.log_level = Common::LEVELS['info']
      end

      def teardown
        Common.log_level = @original_level
        ENV['VIVLIO_BUILD_PARALLEL'] = @original_flag
      end

      # --- 分岐条件 -------------------------------------------------------------

      def test_should_fork_only_when_both_branches_have_work
        assert pipeline(pdf: [noop('pdf')], epub: [noop('epub')]).send(:fork_branches?),
               '両枝に仕事があるときは分岐するべき'
        refute pipeline(pdf: [noop('pdf')]).send(:fork_branches?),
               'PDF 単独ではスレッドを起こしても待つ相手がいない'
        refute pipeline(epub: [noop('epub')]).send(:fork_branches?),
               'EPUB 単独ではスレッドを起こしても待つ相手がいない'
      end

      # 切り分けの道具として、1 コマンドで逐次へ戻せること
      def test_should_fall_back_to_sequential_when_the_env_var_disables_it
        ENV['VIVLIO_BUILD_PARALLEL'] = '0'
        build = pipeline(pdf: [noop('pdf')], epub: [noop('epub')])

        refute build.send(:fork_branches?), 'VIVLIO_BUILD_PARALLEL=0 では分岐しないべき'

        capture_io { build.run }

        assert_empty build.parallel_step_labels, '逐次実行では並行ステップは無いはず'
      end

      # --- 逐次等価 -------------------------------------------------------------

      # 並列に走らせても、記録されるステップの並びは逐次のときと同じにする
      # （どちらのログでも同じ順で読めることが、比較を成立させる前提）。
      def test_should_keep_the_sequential_step_order_when_running_in_parallel
        build = pipeline(shared: [noop('shared')], pdf: [noop('pdf')],
                         epub: [noop('epub')], join: [noop('join')])

        capture_io { build.run }

        assert_equal %w[shared pdf epub join], build.timings.map(&:first)
        assert_equal ['epub'], build.parallel_step_labels
      end

      # --- ログ -----------------------------------------------------------------

      # 子枝のログは溜めておき、合流時にまとめて吐く。EPUB 枝が先に終わっても
      # 出力は PDF 枝の後ろに並ぶ（書き手を常に 1 つに保つため）。
      def test_should_flush_the_child_branch_logs_after_the_parent_branch
        epub_finished = Queue.new
        build = pipeline(
          pdf: [['pdf', lambda {
            epub_finished.pop
            Common.log_info('PDF 枝のログ')
          }]],
          epub: [['epub', lambda {
            Common.log_info('EPUB 枝のログ')
            epub_finished << :done
          }]]
        )

        out, = capture_io { build.run }

        assert_includes out, 'EPUB 枝のログ'
        assert_operator out.index('PDF 枝のログ'), :<, out.index('EPUB 枝のログ'),
                        'EPUB 枝が先に終わっても、ログは PDF 枝の後ろへ並ぶべき'
      end

      # --- 失敗の伝播 -----------------------------------------------------------

      def test_should_reraise_a_child_branch_failure_at_the_join
        build = pipeline(pdf: [noop('pdf')],
                         epub: [['epub', -> { raise 'EPUB 枝が落ちた' }]])

        error = assert_raises(RuntimeError) { capture_io { build.run } }

        assert_equal 'EPUB 枝が落ちた', error.message
      end

      # 親が先に落ちた場合は親の例外を優先し、走り出した子枝は待ってから終わる
      # （外部プロセスの pid を握っていないので、待たないと宙ぶらりんの Chromium が残る）。
      def test_should_prefer_the_parent_failure_and_still_wait_for_the_child
        epub_started = Queue.new
        ran = []
        build = pipeline(
          pdf: [['pdf', lambda {
            epub_started.pop
            raise 'PDF 枝が落ちた'
          }]],
          epub: [['epub', lambda {
            epub_started << :go
            ran << :epub_ran
          }]]
        )

        error = assert_raises(RuntimeError) { capture_io { build.run } }

        assert_equal 'PDF 枝が落ちた', error.message
        assert_equal [:epub_ran], ran, '走り出した子枝の完了は待つべき'
      end

      # --- 中断 -----------------------------------------------------------------

      # Ruby の Interrupt はメインスレッドにしか上がらないため、子枝はフラグを見て止まる。
      def test_should_stop_the_child_branch_at_the_next_step_boundary
        ran = []
        build = pipeline(epub: [['epub-1', -> { ran << :one }], ['epub-2', -> { ran << :two }]])
        build.instance_variable_set(:@aborted, true)

        capture_io { build.send(:run_phase, :epub) }

        assert_empty ran, '中断後はステップを実行しないべき'
      end

      def test_should_finish_the_running_step_before_stopping
        ran = []
        build = nil
        build = pipeline(epub: [['epub-1', lambda {
          ran << :one
          build.instance_variable_set(:@aborted, true)
        }], ['epub-2', -> { ran << :two }]])

        capture_io { build.send(:run_phase, :epub) }

        assert_equal [:one], ran, '走っているステップは最後まで走り、次から止まるべき'
      end

      private

      def noop(label) = [label, -> {}]

      # 相ごとのダミーステップを持つパイプラインを組み立てる。
      # @param shared/pdf/epub/join [Array<[String, Proc]>] 各相のステップ
      def pipeline(shared: [], pdf: [], epub: [], join: [])
        table = { shared:, pdf:, epub:, join: }
        klass = Class.new(BuildCommands::UnifiedBuildPipeline) do
          define_method(:register_steps) do
            table.each { |phase, steps| steps.each { |label, handler| add_step(label, handler, phase) } }
          end
        end
        command = Struct.new(:options).new({ clean: false, resize: false })
        klass.new(command, entries: [], mode: :full,
                           targets: Build::Targets.new(pdf: true, print_pdf: false, epub: true, kindle: false))
      end
    end
  end
end
