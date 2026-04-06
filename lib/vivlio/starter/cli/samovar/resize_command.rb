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
            option '--delete-originals', '変換後に元の PNG/JPG ファイルを削除（確認あり）', default: false, key: :delete_originals
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
            ResizeCommands.execute_resize_with_preset(preset, resolve_dir, merged_options)
          end

          private

          def resolve_dir
            d = dir || 'images'
            # "01-intro" のように images/ プレフィックスなしで指定された場合に補完する
            return d if d == 'images' || d.start_with?('images/') || File.directory?(d)

            with_prefix = File.join('images', d)
            File.directory?(with_prefix) ? with_prefix : d
          end

          def merged_options
            (parent&.options || {}).merge(options || {})
          end
        end

      end
    end
  end
end
