# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/glossary_command.rb
# ================================================================
# 責務:
#   Samovar CLI の glossary 系コマンドを実装する。
#   用語集（glossary.yml）の管理機能を提供する。
#
# 公開コマンド:
#   - glossary: サブコマンド一覧を表示
#   - glossary:add: 新規用語の追加
#   - glossary:lint: 表記揺れの検出
#   - glossary:fix: 表記揺れの自動修正
#   - glossary:canonicalize: YAML の正準化
#
# 依存:
#   - GlossaryAddCommands: 追加処理
#   - GlossaryLintCommands: 検出処理
#   - GlossaryFixCommands: 修正処理
#   - GlossaryCanonicalizeCommands: 正準化処理
# ================================================================

require_relative '../glossary'

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # glossary コマンドの Samovar 実装
        class GlossaryCommand < Samovar::Command
          self.description = '用語集（glossary.yml）を管理します'

          options do
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          def call
            puts <<~HELP
              用語集管理コマンド:

                vs glossary:add           - 新規用語を対話的に追加
                vs glossary:lint          - 表記揺れを検出
                vs glossary:fix           - 表記揺れを自動修正
                vs glossary:canonicalize  - YAML を正準形式に整形

              ワークフロー:
                1. vs glossary:add        → 用語を追加
                2. vs glossary:lint       → 表記揺れをチェック
                3. vs glossary:fix        → 自動修正を適用

              詳細は各コマンドに --help を付けて確認してください。
            HELP
            0
          end
        end

        # glossary:add コマンド - 新規用語の追加
        class GlossaryAddCommand < Samovar::Command
          self.description = '新規用語を対話的に追加します'

          options do
            option '-v/--verbose', '詳細出力', default: false, key: :verbose
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          one :input, '略称と正式名称（例: "HTML HyperText Markup Language"）', required: false

          def call
            return print_usage if options[:help]

            GlossaryAddCommands.execute_glossary_add(input, verbose: options[:verbose])
            0
          rescue SystemExit => e
            e.status
          rescue StandardError => e
            Common.log_error("glossary:add 実行中にエラー: #{e.message}")
            Common.log_error(e.backtrace.first(5).join("\n")) if ENV['VERBOSE']
            1
          end
        end

        # glossary:lint コマンド - 表記揺れの検出
        class GlossaryLintCommand < Samovar::Command
          self.description = '用語集に基づいて表記揺れを検出します'

          options do
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          def call
            return print_usage if options[:help]

            GlossaryLintCommands.execute_glossary_lint
          rescue SystemExit => e
            e.status
          rescue StandardError => e
            Common.log_error("glossary:lint 実行中にエラー: #{e.message}")
            1
          end
        end

        # glossary:fix コマンド - 表記揺れの自動修正
        class GlossaryFixCommand < Samovar::Command
          self.description = '用語集に基づいて表記揺れを自動修正します'

          options do
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          def call
            return print_usage if options[:help]

            GlossaryFixCommands.execute_glossary_fix
            0
          rescue SystemExit => e
            e.status
          rescue StandardError => e
            Common.log_error("glossary:fix 実行中にエラー: #{e.message}")
            1
          end
        end

        # glossary:canonicalize コマンド - YAML の正準化
        class GlossaryCanonicalizeCommand < Samovar::Command
          self.description = 'glossary.yml を正準形式に整形します'

          options do
            option '--check', '差分があるかチェックのみ（CI用）', default: false, key: :check
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          def call
            return print_usage if options[:help]

            if options[:check]
              GlossaryCanonicalizeCommands.execute_glossary_canonicalize_check
            else
              GlossaryCanonicalizeCommands.execute_glossary_canonicalize
            end
            0
          rescue SystemExit => e
            e.status
          rescue StandardError => e
            Common.log_error("glossary:canonicalize 実行中にエラー: #{e.message}")
            1
          end
        end
      end
    end
  end
end
