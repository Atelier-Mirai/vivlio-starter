# frozen_string_literal: true

# ================================================================
# Test: text_metrics_commands_test.rb
# ================================================================
# テスト対象:
#   TextMetricsCommands（lib/vivlio_starter/cli/text_metrics.rb）
#
# 検証内容:
#   - 対象ファイル未検出時の警告出力
#   - JSON 形式での統計出力
#   - 文字数・段落数などのメトリクス計算
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'vivlio_starter/cli'
require 'vivlio_starter/cli/metrics'

module VivlioStarter
  module CLI
    # TextMetricsCommands のユニットテスト
    class TextMetricsCommandsTest < Minitest::Test
      # 対象 Markdown が見つからない場合に警告を出力することを確認
      def test_text_metrics_warns_when_no_targets
        within_temp_dir do
          logged_warnings = []
          Common.stub :log_warn, ->(msg) { logged_warnings << msg } do
            capture_io { TextMetricsCommands.execute_text_metrics(['missing']) }
          end

          assert logged_warnings.any? { it.include?('見つかりません') },
                 "missing 警告が出力されること: #{logged_warnings.inspect}"
        end
      end

      # JSON 出力オプションで統計が JSON 形式になることを確認
      def test_text_metrics_outputs_json
        within_temp_dir do
          write_markdown('contents/11-sample.md', "本文。テストです、はい。\n")

          output = capture_io { TextMetricsCommands.execute_text_metrics([], { json: true }) }.first
          parsed = JSON.parse(output)

          assert_equal ['stats', 'totals'], parsed.keys.sort
          assert_equal 'contents/11-sample.md', parsed['stats'].first['path']
        end
      end

      def test_text_metrics_handles_numeric_only_target
        within_temp_dir do
          write_markdown('contents/15.md', "数字だけの章です。\n")
          write_catalog(%w[15])

          output = capture_io { TextMetricsCommands.execute_text_metrics(['15'], { json: true }) }.first
          parsed = JSON.parse(output)

          assert_equal ['contents/15.md'], parsed['stats'].map { it['path'] }
        end
      end

      private

      def within_temp_dir
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p('contents')
            FileUtils.mkdir_p('config')
            yield dir
          end
        end
      end

      def write_markdown(path, content)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end

      def write_catalog(entries)
        body = "CHAPTERS:\n" + entries.map { "  - #{it}" }.join("\n") + "\n"
        File.write('config/catalog.yml', body)
      end
    end
  end
end
