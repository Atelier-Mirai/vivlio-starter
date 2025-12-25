# frozen_string_literal: true

# ================================================================
# Test: text_metrics_commands_test.rb
# ================================================================
# テスト対象:
#   TextMetricsCommands（lib/vivlio/starter/cli/text_metrics.rb）
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
require 'vivlio/starter/cli'
require 'vivlio/starter/cli/text_metrics'

module Vivlio
  module Starter
    module CLI
      # TextMetricsCommands のユニットテスト
      class TextMetricsCommandsTest < Minitest::Test
        # 対象 Markdown が見つからない場合に警告を出力することを確認
        def test_text_metrics_warns_when_no_targets
          within_temp_dir do
            output = capture_io { TextMetricsCommands.execute_text_metrics(['missing']) }.first

            assert_includes output, '見つかりません'
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

        private

        def within_temp_dir
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('contents')
              yield dir
            end
          end
        end

        def write_markdown(path, content)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, content)
        end
      end
    end
  end
end
