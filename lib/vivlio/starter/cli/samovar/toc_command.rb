# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/toc_command.rb
# ================================================================
# 責務:
#   Samovar CLI の toc コマンドを実装する。
#   HTML ファイルから目次を生成する。
#
# 生成ファイル:
#   - _toc.md: 目次 Markdown
#   - _toc.html: 目次 HTML
#
# 依存:
#   - TocCommands: 実際の目次生成処理
# ================================================================

require_relative '../toc'

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # toc コマンドの Samovar 実装
        class TocCommand < Samovar::Command
          self.description = '目次HTMLを生成します'

          many :htmls, '対象HTMLファイル（省略時は自動検出）'

          def call
            TocCommands.execute_toc(context_options, htmls || [])
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
