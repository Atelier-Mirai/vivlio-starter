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

        def test_should_stop_and_point_to_vs_open_when_preview_does_not_respond
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              File.write('61-developer.pdf', '%PDF-1.4')
              opener = PdfOpener.new({}, '61-developer')
              commands = []
              warnings = []
              results = []

              opener.stub(:macos?, true) do
                opener.stub(:close_existing_windows?, true) do
                  opener.stub(:run_preview_command, ->(*argv, **) { commands << argv.first; :timeout }) do
                    Common.stub(:log_warn, ->(msg, detail: nil) { warnings << [msg, detail] }) do
                      Common.stub(:log_result, ->(*) { results << :called }) do
                        capture_io { opener.call }
                      end
                    end
                  end
                end
              end

              assert_equal ['osascript'], commands, 'ウィンドウを閉じる指示が時間切れなら、開く指示は出さない'
              assert_empty results, '開けていないので「開きました」とは言わない'
              message, detail = warnings.last
              assert_includes message, 'Preview が応答しない'
              assert_includes detail, 'PDF はできています: 61-developer.pdf'
              assert_includes detail, 'vs open 61-developer'
            end
          end
        end
      end
    end
  end
end
