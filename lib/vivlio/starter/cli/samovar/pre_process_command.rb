# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/pre_process_command.rb
# ================================================================
# 責務:
#   Samovar CLI の pre_process コマンドを実装する。
#   Markdown ファイルの前処理（frontmatter 付加等）を行う。
#
# 処理内容:
#   - 章 Markdown を contents/ からプロジェクトルートへ展開
#   - frontmatter（YAML メタデータ）の付加
#
# 依存:
#   - PreProcessCommands: 実際の前処理ロジック
# ================================================================

require_relative '../pre_process'

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # pre_process コマンドの Samovar 実装
        class PreProcessCommand < Samovar::Command
          self.description = 'Markdownファイルの前処理を行います'

          many :tokens, '対象ファイル（省略時は全ファイル）'

          def call
            PreProcessCommands.execute_pre_process(context_options, tokens || [])
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
