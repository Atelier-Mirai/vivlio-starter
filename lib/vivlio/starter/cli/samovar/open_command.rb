# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/open_command.rb
# ================================================================
# 責務:
#   生成されたPDFを開く（macOS専用）
#   vs pdf:open のショートハンド
# ================================================================

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # open コマンド - 生成されたPDFを開く
        class OpenCommand < Samovar::Command
          self.description = '生成されたPDFを開く（macOS専用）'

          options do
            option '-v/--verbose', '冗長出力', default: false, key: :verbose
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          def call
            apply_verbose

            if options[:help]
              print_usage
              return 0
            end

            PdfCommands.execute_open_pdf(build_options)
            0
          rescue SystemExit => e
            raise e
          rescue StandardError => e
            Common.log_error("open 実行中にエラー: #{e.message}")
            Common.log_error(e.backtrace.first(5).join("\n")) if ENV['VERBOSE']
            1
          end

          private

          def apply_verbose
            ENV['VERBOSE'] = '1' if options[:verbose]
          end

          def build_options
            { verbose: options[:verbose] }
          end

          def print_usage
            puts 'vs open - 生成されたPDFを開く（macOS専用）'
            puts ''
            puts 'Usage: vs open [-v/--verbose] [-h/--help]'
          end
        end
      end
    end
  end
end
