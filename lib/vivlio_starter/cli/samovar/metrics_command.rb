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
require_relative '../guards'

module VivlioStarter
  module CLI
    module SamovarCommands
      # metrics コマンドの Samovar 実装
      class MetricsCommand < Samovar::Command
        self.description = 'Markdown の行数・文字数を集計します'

        options do
          option '--all', '解析結果に加えて推敲用の参考資料（ばらつき・長い文・文末リズム・内容語・漢字レベル）も表示', default: false, key: :all
          option '--sections', '全章を節まで展開', default: false, key: :sections
          option '--warn', '警告がある章のみ節まで展開', default: false, key: :warn
          option '--json', 'JSON形式で出力（参考資料を含む）', default: false, key: :json
          option '--yaml', 'YAML形式で出力（参考資料を含む）', default: false, key: :yaml
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        many :files, '対象ファイル（省略時は全章）'

        def call
          return print_help if options[:help]

          # 前提条件の検証（ProjectRoot ◎ / CatalogFile ○ / ContentsDir ◎）
          guard_failure = Guards.precheck(
            Guards::ProjectRootCheck.new,
            Guards::RelaxedCheck.new(Guards::CatalogFileCheck.new),
            Guards::ContentsDirCheck.new
          )
          return guard_failure if guard_failure

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
              --all       解析結果＋推敲用の参考資料も表示
              --sections  全章を節まで展開
              --warn      警告がある章のみ節まで展開
              --json      JSON形式で出力（参考資料を含む）
              --yaml      YAML形式で出力（参考資料を含む）

            例:
              vs metrics              # 全章の解析結果を表示
              vs metrics --all        # 解析結果＋推敲用の参考資料も表示
              vs metrics 2            # 第2章を節まで表示
              vs metrics --sections   # 全章を節まで展開
              vs metrics --warn       # 警告がある章のみ節まで展開
          HELP
          0
        end

        def build_options
          {
            all: options[:all],
            sections: options[:sections],
            warn: options[:warn],
            json: options[:json],
            yaml: options[:yaml]
          }
        end
      end
    end
  end
end
