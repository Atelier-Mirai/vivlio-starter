# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/vivliostyle_command.rb
# ================================================================
# 責務:
#   Samovar CLI の vivliostyle コマンドを実装する。
#   book.yml の設定から vivliostyle.config.js を生成する。
#
# 分類:
#   内部コマンド（vs --help に非表示）
#   使用方法は docs/DEVELOPER_GUIDE.md を参照
#
# 依存:
#   - VivliostyleCommands: config.js 生成ロジック
# ================================================================

require_relative '../vivliostyle'

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # vivliostyle コマンドの Samovar 実装（内部コマンド）
        class VivliostyleCommand < Samovar::Command
          self.description = 'vivliostyle.config.js を生成します（内部コマンド）'

          options do
            option '-v/--verbose', '詳細出力', default: false, key: :verbose
          end

          def call
            VivliostyleCommands.execute_vivliostyle_config(verbose: options[:verbose])
            0
          rescue StandardError => e
            Common.log_error("vivliostyle 実行中にエラー: #{e.message}")
            Common.log_error(e.backtrace.first(5).join("\n")) if ENV['VERBOSE']
            1
          end
        end
      end
    end
  end
end
