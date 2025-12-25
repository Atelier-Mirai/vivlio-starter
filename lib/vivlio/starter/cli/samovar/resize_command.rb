# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/resize_command.rb
# ================================================================
# 責務:
#   Samovar CLI の resize 系コマンドを実装する。
#   画像ファイルを WebP 形式に変換・リサイズする。
#
# 提供コマンド:
#   - resize: 標準品質で変換（--high/--low で品質変更可）
#   - resize:high: 高品質プリセット
#   - resize:medium: 標準品質プリセット
#   - resize:low: 軽量品質プリセット
#
# 依存:
#   - ResizeCommands: 実際のリサイズ処理
#   - ImageMagick: 画像変換エンジン
# ================================================================

require_relative '../resize'

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # resize コマンドの Samovar 実装
        class ResizeCommand < Samovar::Command
          self.description = '画像をWebPに変換します（標準品質）'

          options do
            option '-f/--force', '既存ファイルも強制再生成', key: :force
            option '--high', '高品質プリセットを使用', key: :high
            option '--low', '軽量品質プリセットを使用', key: :low
          end

          one :dir, '対象ディレクトリ', default: 'images', required: false

          def call
            preset = if options[:high]
                       '高精細'
                     elsif options[:low]
                       '軽量'
                     else
                       '標準'
                     end
            ResizeCommands.execute_resize_with_preset(preset, dir || 'images', merged_options)
          end

          private

          def merged_options
            (parent&.options || {}).merge(options || {})
          end
        end

        class ResizeHighCommand < Samovar::Command
          self.description = '画像を高品質WebPに変換します'

          one :dir, '対象ディレクトリ', default: 'images', required: false

          def call
            ResizeCommands.execute_resize_high(dir || 'images', parent&.options || {})
          end
        end

        class ResizeMediumCommand < Samovar::Command
          self.description = '画像を標準品質WebPに変換します'

          one :dir, '対象ディレクトリ', default: 'images', required: false

          def call
            ResizeCommands.execute_resize_medium(dir || 'images', parent&.options || {})
          end
        end

        class ResizeLowCommand < Samovar::Command
          self.description = '画像を軽量品質WebPに変換します'

          one :dir, '対象ディレクトリ', default: 'images', required: false

          def call
            ResizeCommands.execute_resize_low(dir || 'images', parent&.options || {})
          end
        end
      end
    end
  end
end
