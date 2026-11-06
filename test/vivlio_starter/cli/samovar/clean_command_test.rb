# frozen_string_literal: true

# ================================================================
# Test: clean_command_test.rb
# ================================================================
# テスト対象:
#   SamovarCommands::CleanCommand の結果報告（lib/vivlio_starter/cli/samovar/clean_command.rb）
#
# 検証内容:
#   - 削除したものがあれば内訳を 1 行で報告する
#   - 何も無ければ「削除対象はありませんでした」
#   - 辞書の削除を確認で断ったら「削除しませんでした」（対象が無かったのではない）
#
# 削除そのものは clean_commands_test.rb が一時ディレクトリで見ている。ここでは
# CleanCommands.execute_clean を差し替え、返した内訳の読み方だけを確かめる。
# ================================================================

require 'test_helper'
require 'vivlio_starter'
require 'vivlio_starter/cli'

module VivlioStarter
  module CLI
    module SamovarCommands
      class CleanCommandTest < Minitest::Test
        def test_should_report_the_breakdown_of_what_was_deleted
          out = run_clean(CleanCommands::CleanSummary.new(cache: 2, artifacts: 3, dictionaries: 0))

          assert_includes out, '✅ 削除しました（キャッシュ 2 件・生成物 3 件）'
        end

        def test_should_report_that_nothing_was_found
          out = run_clean(CleanCommands::CleanSummary.new(cache: 0, artifacts: 0, dictionaries: 0))

          assert_includes out, '✅ 削除対象はありませんでした'
        end

        def test_should_report_that_nothing_was_deleted_when_declined
          out = run_clean(CleanCommands::CleanSummary.new(cache: 0, artifacts: 0, dictionaries: 0, declined: true),
                          ['--index-dictionaries'])

          assert_includes out, '✅ 削除しませんでした'
          refute_includes out, '削除対象はありませんでした'
        end

        # --purge と一緒に指定して辞書だけ断ったときは、消した分と断った分を両方伝える
        def test_should_report_the_declined_dictionaries_alongside_the_deletions
          out = run_clean(CleanCommands::CleanSummary.new(cache: 2, artifacts: 3, dictionaries: 0, declined: true),
                          ['--purge', '--index-dictionaries'])

          assert_includes out, '✅ 削除しました（キャッシュ 2 件・生成物 3 件）。辞書は削除しませんでした'
        end

        private

        def run_clean(summary, arguments = [])
          status = nil
          out, = capture_io do
            CleanCommands.stub :execute_clean, ->(_opts) { summary } do
              status = CleanCommand.new(arguments).call
            end
          end
          assert_equal 0, status
          out
        end
      end
    end
  end
end
