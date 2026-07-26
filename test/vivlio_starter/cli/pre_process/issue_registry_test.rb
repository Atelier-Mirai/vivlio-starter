# frozen_string_literal: true

# ================================================================
# Test: issue_registry_test.rb
# ================================================================
# テスト対象:
#   PreProcessCommands::IssueRegistry — 前処理の指摘を横断集計する収集器
#
# 検証内容:
#   - record / counts / summary_by_chapter の基本動作
#   - 章キーの正規化（拡張子付き・パス付きでも同一章に集約される）
#   - 章に紐付かない指摘（chapter: nil）が nil キーにまとまる
#   - reset! で蓄積が空になる
#   - 並列 record（スレッド 8 本）で取りこぼしが起きない
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/pre_process/issue_registry'

module VivlioStarter
  module CLI
    module PreProcessCommands
      class IssueRegistryTest < Minitest::Test
        def setup
          IssueRegistry.reset!
        end

        def teardown
          IssueRegistry.reset!
        end

        # record した指摘が severity 別に集計される
        def test_should_count_issues_by_severity
          IssueRegistry.record(chapter: '21-images', severity: :error, category: :image, message: '存在しない画像: a.png')
          IssueRegistry.record(chapter: '21-images', severity: :warn, category: :link, message: '裸 URL: https://example.com')
          IssueRegistry.record(chapter: '10-intro', severity: :warn, category: :link, message: '裸 URL: https://example.org')

          counts = IssueRegistry.counts
          assert_equal 1, counts.errors
          assert_equal 2, counts.warns
          assert_equal 3, counts.total
          refute counts.clean?
        end

        # 指摘ゼロなら counts は clean? を返す
        def test_should_report_clean_when_no_issues_recorded
          counts = IssueRegistry.counts
          assert_equal 0, counts.total
          assert counts.clean?
        end

        # summary_by_chapter が章ごとの件数を返す
        def test_should_summarize_counts_per_chapter
          IssueRegistry.record(chapter: '21-images', severity: :error, category: :image, message: 'e1')
          IssueRegistry.record(chapter: '21-images', severity: :error, category: :image, message: 'e2')
          IssueRegistry.record(chapter: '21-images', severity: :warn, category: :link, message: 'w1')
          IssueRegistry.record(chapter: '10-intro', severity: :warn, category: :link, message: 'w2')

          summary = IssueRegistry.summary_by_chapter
          assert_equal 2, summary['21-images'].errors
          assert_equal 1, summary['21-images'].warns
          assert_equal 0, summary['10-intro'].errors
          assert_equal 1, summary['10-intro'].warns
        end

        # 章キーは拡張子・ディレクトリを落として正規化される（発生源ごとの形式差を吸収）
        def test_should_normalize_chapter_key_across_source_formats
          IssueRegistry.record(chapter: '21-images.md', severity: :warn, category: :link, message: 'w1')
          IssueRegistry.record(chapter: 'contents/21-images.md', severity: :warn, category: :link, message: 'w2')
          IssueRegistry.record(chapter: '21-images', severity: :warn, category: :link, message: 'w3')

          summary = IssueRegistry.summary_by_chapter
          assert_equal ['21-images'], summary.keys
          assert_equal 3, summary['21-images'].warns
        end

        # 章に紐付かない指摘は nil キーにまとまる（Guard 警告など）
        def test_should_group_unattached_issues_under_nil_key
          IssueRegistry.record(severity: :warn, category: :guard, message: '未知のコンテナクラス')
          IssueRegistry.record(chapter: '  ', severity: :warn, category: :guard, message: '空文字も章なし扱い')

          summary = IssueRegistry.summary_by_chapter
          assert_equal 2, summary[nil].warns
          assert_nil summary['']
        end

        # 記録された Issue が category / line を保持する
        def test_should_retain_category_and_line_on_issue
          IssueRegistry.record(
            chapter: '21-images.md', line: 42, severity: :error,
            category: :code_include, message: '存在しないコード: sample.rb'
          )

          issue = IssueRegistry.issues.first
          assert_pattern do
            issue => { chapter: '21-images', line: 42, severity: :error, category: :code_include }
          end
        end

        # reset! で蓄積が空になる
        def test_should_clear_issues_on_reset
          IssueRegistry.record(chapter: '21-images', severity: :error, category: :image, message: 'e1')
          IssueRegistry.reset!

          assert_empty IssueRegistry.issues
          assert IssueRegistry.counts.clean?
        end

        # 並列前処理を想定し、8 スレッドから同時 record しても取りこぼさない
        def test_should_record_safely_from_multiple_threads
          threads = 8.times.map do |i|
            Thread.new do
              10.times do |j|
                IssueRegistry.record(
                  chapter: format('%02d-chapter', i), line: j,
                  severity: j.even? ? :error : :warn, category: :link, message: "issue #{i}-#{j}"
                )
              end
            end
          end
          threads.each(&:join)

          counts = IssueRegistry.counts
          assert_equal 80, counts.total
          assert_equal 40, counts.errors
          assert_equal 40, counts.warns
          assert_equal 8, IssueRegistry.summary_by_chapter.size
        end
      end
    end
  end
end
