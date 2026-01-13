# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/lint_command.rb
# ================================================================
# 責務:
#   Samovar CLI の lint コマンドを実装する。
#   textlint を使用した Markdown ファイルの文章校正を実行する。
#
# 機能:
#   - contents/ 以下の Markdown ファイルを textlint で検査
#   - 章番号指定・範囲指定による部分検査
#   - 英語エラーメッセージの日本語翻訳
#
# 依存:
#   - LintCommands: textlint 実行ロジック
# ================================================================

require_relative '../lint'

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # lint コマンドの Samovar 実装
        class LintCommand < Samovar::Command
          self.description = 'contents/ 以下の Markdown を textlint で検査します'

          options do
            option '--config PATH', '使用する .textlintrc.yml のパス', key: :config
            option '--format NAME', '出力フォーマット (stylish/compact/pretty-error)', key: :format
            option '--fix', '自動修正可能なエラーを修正', default: false, key: :fix
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          many :files, '対象ファイル（省略時は全章）'

          def call
            return print_help if options[:help]

            targets = files || []
            LintCommands.execute_lint(targets, build_options)
          rescue SystemExit => e
            e.status
          rescue StandardError => e
            Common.log_error("lint 実行中にエラー: #{e.message}")
            Common.log_error(e.backtrace.first(5).join("\n")) if ENV['VERBOSE']
            1
          end

          private

          def print_help
            puts <<~HELP
              vs lint - contents/ 以下の Markdown を textlint で検査します

              Usage: vs lint [OPTIONS] [FILES...]

              引数:
                FILES   対象ファイル（省略時は全 Markdown）
                        章番号のみ: vs lint 91 93
                        範囲指定:   vs lint 11-21

              オプション:
                --config PATH    使用する .textlintrc.yml のパスを切り替えます
                --format NAME    出力フォーマット (stylish/compact/pretty-error)
                --fix            自動修正可能なエラーを修正します

              例:
                vs lint                 # 全 Markdown を検査
                vs lint 11-install      # 11-install.md のみ検査
                vs lint 91 93           # 91-*.md と 93-*.md を検査
                vs lint 11-21           # 11-*.md から 21-*.md の範囲を検査
                vs lint --fix           # 自動修正を適用
            HELP
            0
          end

          def build_options
            {
              config: options[:config],
              format: options[:format],
              fix: options[:fix]
            }
          end
        end

        # lint:check は lint のエイリアス
        class LintCheckCommand < LintCommand
          self.description = 'lint のエイリアス'
        end
      end
    end
  end
end
