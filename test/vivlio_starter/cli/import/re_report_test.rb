# frozen_string_literal: true

require_relative '../../../test_helper'
require 'vivlio_starter/cli/import/re_report'

module VivlioStarter
  module CLI
    module Import
      # 通知の集約と報告（re-direct-import-spec.md §4）
      class ReReportTest < Minitest::Test
        def setup
          @report = ReReport.new
        end

        def test_should_collect_findings_with_level_and_place
          @report.unsupported('//hr', file: 'a.re', line: 12, message: '対応する記法がありません。')

          finding = @report.findings.first
          assert_equal :unsupported, finding.level
          assert_equal 'a.re', finding.file
          assert_equal 12, finding.line
        end

        # 同じ記法の指摘は 1 行に畳み、場所は先頭 3 件までを挙げる
        def test_should_fold_findings_of_same_kind
          5.times { |i| @report.unsupported('//hr', file: 'a.re', line: i + 1, message: '水平線です。') }

          output, = capture_io { @report.emit! }

          assert_includes output, 'a.re:1、a.re:2、a.re:3'
          assert_includes output, 'ほか 2 箇所'
          assert_includes output, '計 5 箇所'
        end

        def test_should_separate_levels_in_output
          @report.unsupported('//hr', file: 'a.re', line: 1, message: '未対応です。')
          @report.degraded('//table', file: 'a.re', line: 2, message: '指定が落ちました。')

          output, = capture_io { @report.emit! }

          assert_includes output, '🔴'
          assert_includes output, '🟡'
        end

        # 「静かに終わった＝全部うまくいった」と誤解させないための総括
        def test_should_summarize_counts
          3.times { @report.count(:block) }
          2.times { @report.count(:inline) }
          @report.count(:relabel)
          @report.unsupported('//hr', file: 'a.re', line: 1, message: '未対応です。')

          output, = capture_io { @report.summary(chapters: 2, lines: 100) }

          assert_includes output, '変換サマリ（2 章 / 100 行）'
          assert_includes output, 'ブロック命令 3 件を変換'
          assert_includes output, 'インライン命令 2 件を変換'
          assert_includes output, 'ラベル ID 1 件'
          assert_includes output, '🔴 1 件'
        end

        def test_should_say_when_nothing_was_left_behind
          @report.count(:block)
          output, = capture_io { @report.summary(chapters: 1, lines: 10) }

          assert_includes output, '変換できなかった記法はありません'
        end
      end
    end
  end
end
