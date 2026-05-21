# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/samovar/metrics_command.rb
# ================================================================
# 責務:
#   Samovar CLI の metrics コマンドを実装する。
#   Markdown コンテンツの文章品質メトリクスを分析・表示する。
#
# 機能:
#   - 基本統計（文字数、行数、文数、節数）
#   - 語彙難度・語彙多様度・読解難度
#   - 章・節単位の分量可視化
#
# 依存:
#   - MetricsCommands: 統計処理ロジック
# ================================================================

require_relative '../metrics'

module VivlioStarter
  module CLI
    module SamovarCommands
      # metrics コマンドの Samovar 実装
      class MetricsCommand < Samovar::Command
        self.description = 'Markdown の行数・文字数を集計します'

        options do
          option '--all', '全章の節まで表示', default: false, key: :all
          option '--warn', '警告がある章のみ節まで表示', default: false, key: :warn
          option '--json', 'JSON形式で出力', default: false, key: :json
          option '--yaml', 'YAML形式で出力', default: false, key: :yaml
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        many :files, '対象ファイル（省略時は全章）'

        def call
          return print_help if options[:help]

          targets = files || []
          MetricsCommands.execute_metrics(targets, build_options)
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
            vs metrics - Markdown の文章品質メトリクスを分析します

            Usage: vs metrics [OPTIONS] [CHAPTERS...]

            引数:
              CHAPTERS  対象章（省略時は全章の概要を表示）
                        章番号:     vs metrics 2
                        複数指定:   vs metrics 1,3,5
                        範囲指定:   vs metrics 1-3
                        組み合わせ: vs metrics 1-3,5,8-10

            オプション:
              --all     全章の節まで表示
              --warn    警告がある章のみ節まで表示
              --json    JSON形式で出力
              --yaml    YAML形式で出力

            例:
              vs metrics              # 全章の概要を表示
              vs metrics 2            # 第2章の節まで表示
              vs metrics --all        # 全章の節まで表示
              vs metrics --warn       # 警告がある章のみ節まで表示
          HELP
          0
        end

        def build_options
          {
            all: options[:all],
            warn: options[:warn],
            json: options[:json],
            yaml: options[:yaml]
          }
        end
      end
    end
  end
end
