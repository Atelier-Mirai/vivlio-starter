# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/post_process_command.rb
# ================================================================
# 責務:
#   Samovar CLI の post_process コマンドを実装する。
#   HTML ファイルの後処理（見出し番号付け、コードハイライト等）を行う。
#
# 処理内容:
#   - 見出しへの章番号・節番号の付与
#   - コードブロックへの行番号付与
#   - 図表番号の自動採番
#
# 依存:
#   - PostProcessCommands: 実際の後処理ロジック
# ================================================================

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # post_process コマンドの Samovar 実装
        class PostProcessCommand < Samovar::Command
          self.description = 'HTMLファイルのポスト置換処理を行います'

          many :tokens, '対象ファイル（省略時は全ファイル）'

          def call
            PostProcessCommands.execute_post_process(context_options, tokens || [])
          end

          private

          def context_options
            { options: parent_options }
          end

          def parent_options
            parent&.options || {}
          end
        end
      end
    end
  end
end
