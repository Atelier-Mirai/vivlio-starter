# frozen_string_literal: true

# ================================================================
# Test: metrics_commands_test.rb
# ================================================================
# テスト対象:
#   MetricsCommands のエントリポイント（lib/vivlio_starter/cli/metrics.rb）
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
    # MetricsCommands のエントリポイントのユニットテスト
    class MetricsCommandsEntrypointTest < Minitest::Test
      # 見つからない章を指したら、vs build と同じ文面の 🔴 で止める。黙って落とすと
      # 何を打ち間違えたかが分からない（改善案 #113）
      def test_text_metrics_stops_on_an_unknown_target
        within_temp_dir do
          out, = capture_io { MetricsCommands.execute_metrics(['missing']) }

          assert_includes out, '🔴 指定した章が見つかりません: missing'
          refute_includes out, '対象となる Markdown ファイルが見つかりません', '同じことを 🟡 で重ねない'
        end
      end

      # JSON 出力オプションで統計が JSON 形式になることを確認
      def test_text_metrics_outputs_json
        within_temp_dir do
          write_markdown('contents/11-sample.md', "本文。テストです、はい。\n")

          output = capture_io { MetricsCommands.execute_metrics([], { json: true }) }.first
          parsed = JSON.parse(output)

          assert_equal %w[advice stats totals], parsed.keys.sort
          assert_equal 'contents/11-sample.md', parsed['stats'].first['path']
        end
      end

      # JSON 出力に推敲用の参考資料（advice）と語彙集計が含まれることを確認
      def test_text_metrics_json_includes_advice_and_vocabulary
        within_temp_dir do
          write_markdown('contents/11-sample.md', "本文です。テストの文章を、いくつか並べます。\n")

          output = capture_io { MetricsCommands.execute_metrics([], { json: true }) }.first
          parsed = JSON.parse(output)

          advice = parsed['advice']
          assert_equal %w[consistency content_words kanji_levels long_sentences sentence_rhythm], advice.keys.sort
          assert parsed['totals'].key?('vocabulary'), "totals に vocabulary が含まれること: #{parsed['totals'].keys.inspect}"
          assert_kind_of Numeric, parsed['totals']['vocabulary']['mattr']
        end
      end

      # JSON の totals に読解難度（建石式 RS）の集計が含まれることを確認
      def test_text_metrics_json_totals_include_readability
        within_temp_dir do
          write_markdown('contents/11-sample.md', "本文です。テストの文章を、いくつか並べます。\n")

          output = capture_io { MetricsCommands.execute_metrics([], { json: true }) }.first
          totals = JSON.parse(output)['totals']

          assert totals.key?('readability'), "totals に readability が含まれること: #{totals.keys.inspect}"
          assert_kind_of Numeric, totals['readability']['score']
          assert_includes %w[Easy Standard Professional], totals['readability']['label']
        end
      end

      def test_text_metrics_handles_numeric_only_target
        within_temp_dir do
          write_markdown('contents/15.md', "数字だけの章です。\n")
          write_catalog(%w[15])

          output = capture_io { MetricsCommands.execute_metrics(['15'], { json: true }) }.first
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
