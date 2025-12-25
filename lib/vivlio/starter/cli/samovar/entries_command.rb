# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/entries_command.rb
# ================================================================
# 責務:
#   Samovar CLI の entries コマンドを実装する。
#   HTML ファイルから Vivliostyle 用の entries.js を生成する。
#
# 生成ファイル:
#   - entries.js: 章エントリを定義する ES Module
#     Vivliostyle がビルド時に読み込む章リストを提供
#
# 依存:
#   - EntriesCommands: 実際の生成処理
# ================================================================

require_relative '../entries'

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # entries コマンドの Samovar 実装
        class EntriesCommand < Samovar::Command
          self.description = 'HTML から entries.js (ES Module) を生成します'

          many :tokens, '対象 HTML のスラッグまたはファイルパス（省略時は *.html 全体）', default: []

          options do
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          def call
            return print_usage if options[:help]

            EntriesCommands.execute_entries(context_options, tokens)
            0
          rescue SystemExit => e
            raise e
          rescue StandardError => e
            Vivlio::Starter::CLI::Common.log_error("entries コマンド実行中にエラー: #{e.message}")
            1
          end

          private

          def context_options
            {
              options: {
                verbose: verbose_from_parent
              }
            }
          end

          def verbose_from_parent
            return false unless parent.respond_to?(:options)

            !!parent.options[:verbose]
          end
        end
      end
    end
  end
end
