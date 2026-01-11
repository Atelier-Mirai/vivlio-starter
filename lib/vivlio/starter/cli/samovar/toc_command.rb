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
        # toc コマンドの Samovar 実装（内部コマンド）
        class TocCommand < Samovar::Command
          self.description = '目次HTMLを生成します（内部コマンド）'

          many :htmls, '対象HTMLファイル（省略時は自動検出）'

          def call
            TocCommands.execute_toc(build_options, htmls || [])
          end

          private

          def build_options
            { verbose: parent_verbose? }
          end

          def parent_verbose?
            parent&.options&.[](:verbose) || false
          end
        end
      end
    end
  end
end
