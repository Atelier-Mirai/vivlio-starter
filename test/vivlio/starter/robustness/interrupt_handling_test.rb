# frozen_string_literal: true

# ================================================================
# robustness: 中断シグナル・シグナルハンドリング
# ================================================================
# 対応する堅牢性テスト仕様書項目:
#   - 4-3-2 (L202): ビルド中に Ctrl+C → trap 済みで ensure が走り、
#                   中間ファイルが残らない。UNIX 規約の exit code 130。
#   - 5-6-2 (L231): `vs lint --fix` 実行中に Ctrl+C → 元ファイルを破壊せずに中断
#
#   共通の入口ハンドラは `CLI.start` / `CLI.handle_interrupt` / `CLI.handle_signal`。
#   docs/specs/vivlio_starter_robustness_test_spec.md
#
# 期待される挙動:
#   1. コマンド実行中の Interrupt 発生 → `CLI.start` が捕捉し exit 130 を返す
#   2. SIGTERM 等の SignalException → 128 + signo を返す
#   3. ensure ブロックが確実に走る（中間ファイル削除の機会を提供）
#   4. 想定外例外は exit 1 で人間可読なメッセージ表示（生のトレースバックは VS_DEBUG のみ）
#   5. SystemExit のステータスはそのまま伝播
# ================================================================

require 'test_helper'
require 'stringio'
require 'vivlio/starter/cli/startup'

module Vivlio
  module Starter
    module CLI
      class InterruptHandlingTest < Minitest::Test
        # ================================================================
        # handle_interrupt / handle_signal の直接テスト
        # ================================================================

        def test_handle_interrupt_returns_exit_code_130
          code = nil
          stderr = capture_stderr { code = CLI.handle_interrupt }
          assert_equal 130, code, 'Ctrl+C は UNIX 規約で exit 130 を返す'
          assert_includes stderr, '中断されました', 'ユーザー向け案内を stderr に出す'
        end

        def test_handle_signal_returns_128_plus_signal_number_for_sigterm
          # SignalException は raise/rescue の形で生成する必要がある
          error = begin
            raise SignalException, 'SIGTERM'
          rescue SignalException => e
            e
          end

          code = nil
          stderr = capture_stderr { code = CLI.handle_signal(error) }

          sigterm_number = Signal.list.fetch('TERM')
          assert_equal 128 + sigterm_number, code
          assert_includes stderr, '中断されました'
        end

        def test_handle_unexpected_error_returns_1_and_hides_trace_by_default
          error = RuntimeError.new('boom')
          error.set_backtrace(['lib/foo.rb:1:in `bar\''])

          stderr = nil
          code = nil
          with_env('VS_DEBUG' => nil) do
            stderr = capture_stderr { code = CLI.handle_unexpected_error(error) }
          end

          assert_equal 1, code
          assert_includes stderr, 'RuntimeError'
          assert_includes stderr, 'boom'
          refute_includes stderr, "lib/foo.rb:1",
                          'VS_DEBUG 未設定時はバックトレースを隠すべき'
        end

        def test_handle_unexpected_error_emits_trace_when_vs_debug
          error = RuntimeError.new('boom')
          error.set_backtrace(['lib/foo.rb:1:in `bar\''])

          stderr = nil
          code = nil
          with_env('VS_DEBUG' => '1') do
            stderr = capture_stderr { code = CLI.handle_unexpected_error(error) }
          end

          assert_equal 1, code
          assert_includes stderr, 'lib/foo.rb:1',
                          'VS_DEBUG 時はバックトレースを出すべき'
        end

        # ================================================================
        # CLI.start の経路：Interrupt が command.call 内で発生
        # ================================================================

        # Interrupt を発生させる Fake コマンド
        FakeInterruptCommand = Struct.new(:raised) do
          def call
            raise Interrupt
          end
        end

        # 例外ではなく整数を返す Fake コマンド
        FakeIntegerResultCommand = Struct.new(:status) do
          def call = status
        end

        # SignalException を発生させる Fake コマンド
        FakeSignalCommand = Struct.new(:signal_name) do
          def call
            raise SignalException, signal_name
          end
        end

        # SystemExit を発生させる Fake コマンド
        FakeSystemExitCommand = Struct.new(:status) do
          def call
            raise SystemExit.new(status)
          end
        end

        # 想定外例外を発生させる Fake コマンド
        FakeUnexpectedCommand = Struct.new(:error) do
          def call
            raise error
          end
        end

        def test_start_returns_130_when_command_raises_interrupt
          with_stubbed_root_command(FakeInterruptCommand.new) do
            stderr = nil
            code = capture_stderr_return do
              code = CLI.start([])
              code
            end.then { |result| stderr, code = result.values_at(:stderr, :result); code }
            assert_equal 130, code
            assert_includes stderr, '中断されました'
          end
        end

        def test_start_returns_128_plus_signo_on_signal_exception
          with_stubbed_root_command(FakeSignalCommand.new('SIGTERM')) do
            result = capture_stderr_return { CLI.start([]) }
            assert_equal 128 + Signal.list.fetch('TERM'), result[:result]
            assert_includes result[:stderr], '中断されました'
          end
        end

        def test_start_propagates_systemexit_status
          with_stubbed_root_command(FakeSystemExitCommand.new(42)) do
            result = capture_stderr_return { CLI.start([]) }
            assert_equal 42, result[:result], 'SystemExit のステータスはそのまま伝播'
          end
        end

        def test_start_handles_unexpected_exception_without_crashing
          err = RuntimeError.new('unexpected failure')
          with_stubbed_root_command(FakeUnexpectedCommand.new(err)) do
            result = nil
            with_env('VS_DEBUG' => nil) do
              result = capture_stderr_return { CLI.start([]) }
            end
            assert_equal 1, result[:result]
            assert_includes result[:stderr], 'RuntimeError'
            assert_includes result[:stderr], 'unexpected failure'
          end
        end

        def test_start_returns_command_integer_result_as_is
          with_stubbed_root_command(FakeIntegerResultCommand.new(7)) do
            assert_equal 7, CLI.start([])
          end
        end

        def test_start_returns_zero_when_command_returns_non_integer
          non_integer = Object.new
          def non_integer.call = :ok
          with_stubbed_root_command(non_integer) do
            assert_equal 0, CLI.start([])
          end
        end

        private

        # SamovarCommands::RootCommand.parse をスタブし、渡した fake コマンドを返す
        def with_stubbed_root_command(fake)
          root = SamovarCommands::RootCommand
          original = root.method(:parse)
          root.define_singleton_method(:parse) { |_args| fake }
          yield
        ensure
          root.singleton_class.send(:remove_method, :parse)
          root.define_singleton_method(:parse, original)
        end

        def capture_stderr
          original = $stderr
          io = StringIO.new
          $stderr = io
          yield
          io.string
        ensure
          $stderr = original
        end

        # ブロックの戻り値と stderr を両方返す
        def capture_stderr_return
          original = $stderr
          io = StringIO.new
          $stderr = io
          result = yield
          { result: result, stderr: io.string }
        ensure
          $stderr = original
        end

        def with_env(overrides)
          original = {}
          overrides.each do |k, v|
            original[k] = ENV.fetch(k, nil)
            if v.nil?
              ENV.delete(k)
            else
              ENV[k] = v
            end
          end
          yield
        ensure
          original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
        end
      end
    end
  end
end
