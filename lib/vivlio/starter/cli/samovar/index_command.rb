# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/index_command.rb
# ================================================================
# 責務:
#   Samovar CLI の index コマンドを実装する。
#   索引機能（スキャン、ビルド）のサブコマンドを提供する。
#
# サブコマンド:
#   - index:build: 索引ページを生成
#
# 依存:
#   - IndexCommands: 実際の索引処理
# ================================================================

require_relative '../index'

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # index コマンドの Samovar 実装
        class IndexCommand < Samovar::Command
          self.description = '索引機能のサブコマンドを表示します'

          options do
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          def call
            puts <<~HELP
              索引機能のコマンド:
              
                vs index:match    - 手動マークアップ [用語|読み] をスキャン
                vs index:build    - 索引ページ (_indexpage.html) を生成
                vs index:candidate - 索引候補を自動抽出（Phase 2）
              
              詳細は各コマンドに --help を付けて確認してください。
            HELP
            0
          end
        end

        # index:match コマンド
        class IndexMatchCommand < Samovar::Command
          self.description = '索引候補を自動抽出し、YAML を生成します'

          options do
            option '-v/--verbose', '詳細出力', default: false, key: :verbose
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          many :files, 'スキャン対象ファイル（省略時は全章）'

          def call
            return print_usage if options[:help]

            IndexCommands.execute_index_match(options, files || [])
            0
          rescue SystemExit => e
            raise e
          rescue StandardError => e
            Common.log_error("index:match 実行中にエラー: #{e.message}")
            Common.log_error(e.backtrace.first(5).join("\n")) if ENV['VERBOSE']
            1
          end
        end

        # index:build コマンド
        class IndexBuildCommand < Samovar::Command
          self.description = '索引ページを生成します'

          options do
            option '-v/--verbose', '詳細出力', default: false, key: :verbose
            option '--preview', 'ブラウザでプレビュー', default: false, key: :preview
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          def call
            return print_usage if options[:help]

            IndexCommands.execute_index_build(options)
            0
          rescue SystemExit => e
            raise e
          rescue StandardError => e
            Common.log_error("index:build 実行中にエラー: #{e.message}")
            Common.log_error(e.backtrace.first(5).join("\n")) if ENV['VERBOSE']
            1
          end
        end

        # index:candidate コマンド（Phase 2）
        class IndexCandidateCommand < Samovar::Command
          self.description = '索引候補を自動抽出します（Phase 2）'

          options do
            option '-v/--verbose', '詳細出力', default: false, key: :verbose
            option '-t/--threshold', 'スコア閾値（デフォルト: 150）', default: 150, key: :threshold
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          many :files, '抽出対象ファイル（省略時は全章）'

          def call
            return print_usage if options[:help]

            IndexCommands.execute_index_candidate(options, files || [])
            0
          rescue SystemExit => e
            raise e
          rescue StandardError => e
            Common.log_error("index:candidate 実行中にエラー: #{e.message}")
            Common.log_error(e.backtrace.first(5).join("\n")) if ENV['VERBOSE']
            1
          end
        end
      end
    end
  end
end
