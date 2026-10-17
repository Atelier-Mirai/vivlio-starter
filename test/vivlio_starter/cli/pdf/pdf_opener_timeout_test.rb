# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/cli/pdf/pdf_opener_timeout_test.rb
#
# Preview が応答しないとき、PdfOpener が待ち続けずに打ち切り、
# 次の手を添えて知らせることを確かめる。
#
# 応答の無い Preview には、osascript も `open -a Preview` も AppleEvent の既定
# （約 2 分）まで戻らず、`vs build` が止まって見えていた（2026-10-13）。
# =============================================================================

require 'test_helper'
require 'tmpdir'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/pdf'

module VivlioStarter
  module CLI
    module PdfCommands
      class PdfOpenerTimeoutTest < Minitest::Test
        def test_should_tell_ok_failed_and_timeout_apart
          opener = PdfOpener.new({}, nil)

          assert_equal :ok, opener.send(:run_preview_command, 'true')
          assert_equal :failed, opener.send(:run_preview_command, 'false')
          assert_equal :failed, opener.send(:run_preview_command, 'no-such-command-for-vs-test')

          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          assert_equal :timeout, opener.send(:run_preview_command, 'sleep', '5', timeout: 0.3)
          assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2,
                          '時間切れで打ち切り、指示したプロセスの終わりを待たない'
        end

        # 開く指示（open -a）そのものが戻らないときは、待ち続けずに vs open を案内する
        def test_should_stop_and_point_to_vs_open_when_preview_does_not_respond
          outcome = open_with(preview_running: true) { |argv| argv.first == 'open' ? :timeout : :ok }

          assert_empty outcome[:results], '開けていないので「開きました」とは言わない'
          message, detail = outcome[:warnings].last
          assert_includes message, 'Preview が応答しない'
          assert_includes detail, 'PDF はできています: 61-developer.pdf'
          assert_includes detail, 'vs open 61-developer'
        end

        # 何も入っていない Mac では、閉じる指示が macOS の許可待ちで時間切れになる。
        # 以前はそこで止まり、PDF は毎回開かなかった（改善案.md #87）
        def test_should_still_open_when_closing_windows_waits_for_permission
          outcome = open_with(preview_running: true) { |argv| argv.first == 'osascript' ? :timeout : :ok }

          assert_equal %w[osascript open], outcome[:commands],
                       '閉じられなくても開く。並べる指示も許可が要るので出さない'
          assert_equal [:called], outcome[:results]
          assert_empty outcome[:warnings]
          assert outcome[:hints].any? { it.start_with?('💡') && it.include?('「許可」') }, '許可の押し方を案内する'
        end

        # Preview が起動していなければ閉じるものは無いので、許可の要る指示を出さずに開く
        def test_should_not_close_windows_when_preview_is_not_running
          outcome = open_with(preview_running: false) { :ok }

          assert_equal %w[open osascript], outcome[:commands], '閉じる指示は出さず、開いてから並べる'
          assert_equal [:called], outcome[:results]
          assert_empty outcome[:hints]
        end

        private

        # 61-developer.pdf を開かせ、Preview へ出した指示と、出たログを集める。
        # 指示の結果はブロックが argv から決める（実際の Preview・osascript は動かさない）
        def open_with(preview_running:, &result_for)
          outcome = { commands: [], warnings: [], results: [], hints: [] }
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              File.write('61-developer.pdf', '%PDF-1.4')
              opener = PdfOpener.new({}, '61-developer')

              opener.stub(:macos?, true) do
                opener.stub(:close_existing_windows?, true) do
                  opener.stub(:preview_running?, preview_running) do
                    run = lambda { |*argv, **|
                      outcome[:commands] << argv.first
                      result_for.call(argv)
                    }
                    opener.stub(:run_preview_command, run) do
                      Common.stub(:log_warn, ->(msg, detail: nil) { outcome[:warnings] << [msg, detail] }) do
                        Common.stub(:log_result, ->(*) { outcome[:results] << :called }) do
                          Common.stub(:log_always, ->(msg) { outcome[:hints] << msg }) do
                            capture_io { opener.call }
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
          outcome
        end
      end
    end
  end
end
