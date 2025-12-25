# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/help_command.rb
# ================================================================
# 責務:
#   Samovar CLI の help コマンドを実装する。
#   利用可能なコマンド一覧とヘルプ情報を表示する。
#
# 表示内容:
#   - Vivlio Starter の概要
#   - 利用可能なサブコマンド一覧
#   - グローバルオプション
# ================================================================

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # help コマンドの Samovar 実装
        class HelpCommand < Samovar::Command
          self.description = 'Vivlio Starter の主要コマンド一覧を表示します'

          options do
            option '-h/--help', 'ヘルプを表示', key: :help
          end

          def call
            return print_usage if options[:help]

            if defined?(Vivlio::Starter::CLI::HelpCommands::HELP_MESSAGE)
              puts Vivlio::Starter::CLI::HelpCommands::HELP_MESSAGE
              puts
            end

            parent&.print_usage || print_usage
            0
          end
        end
      end
    end
  end
end
