# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/convert_command.rb
# ================================================================
# 責務:
#   Samovar CLI の convert コマンドを実装する。
#   Markdown ファイルを HTML に変換する。
#
# 処理内容:
#   - Vivliostyle CLI を使用した Markdown → HTML 変換
#   - 複数ファイルの一括変換対応
#
# 依存:
#   - ConvertCommands: 実際の変換処理
# ================================================================

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # convert コマンドの Samovar 実装
        class ConvertCommand < Samovar::Command
          self.description = 'MarkdownをHTMLに変換します'

          many :tokens, '対象ファイル（省略時は全ファイル）'

          def call
            ConvertCommands.execute_convert(context_options, tokens || [])
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
