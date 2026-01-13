# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/metrics_command.rb
# ================================================================
# 責務:
#   Samovar CLI の metrics コマンドを実装する。
#   Markdown コンテンツの行数・文字数などの統計を表示する。
#
# 機能:
#   - contents/ 以下の Markdown ファイルについて行数・文字数を集計
#   - JSON/YAML/表形式での出力
#
# 依存:
#   - MetricsCommands: 統計処理ロジック
# ================================================================

require_relative '../metrics'

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # metrics コマンドの Samovar 実装
        class MetricsCommand < Samovar::Command
          self.description = 'Markdown の行数・文字数などの統計を表示します'

          options do
            option '--json', 'JSON形式で出力', default: false, key: :json
            option '--yaml', 'YAML形式で出力', default: false, key: :yaml
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          many :files, '対象ファイル（省略時は全章）'

          def call
            return print_help if options[:help]

            targets = files || []
            MetricsCommands.execute_metrics(targets, build_options)
            0
          rescue SystemExit => e
            e.status
          rescue StandardError => e
            Common.log_error("metrics 実行中にエラー: #{e.message}")
            Common.log_error(e.backtrace.first(5).join("\n")) if ENV['VERBOSE']
            1
          end

          private

          def print_help
            puts <<~HELP
              vs metrics - Markdown の行数・文字数などの統計を表示します

              Usage: vs metrics [OPTIONS] [FILES...]

              引数:
                FILES   対象ファイル（省略時は全 Markdown）

              オプション:
                --json    JSON形式で出力
                --yaml    YAML形式で出力

              例:
                vs metrics              # 全 Markdown の統計を表示
                vs metrics 11-install   # 11-install.md のみ
                vs metrics --json       # JSON形式で出力
            HELP
            0
          end

          def build_options
            {
              json: options[:json],
              yaml: options[:yaml]
            }
          end
        end
      end
    end
  end
end
