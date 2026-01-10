# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/import/image_processor.rb
# ================================================================
# 責務:
#   Re:VIEW Starter から vivlio-starter への画像移行処理を担当。
#
# 処理内容:
#   - 画像ファイルのコピー
#   - WebP 変換（ResizeCommands 使用）
#   - 元画像（png/jpg/gif）の削除
#   - 表紙 PDF のコピー
#
# 依存:
#   - ResizeCommands: 画像最適化
#   - Common: ログ出力
#   - FileUtils: ファイル操作
# ================================================================

require 'fileutils'

module Vivlio
  module Starter
    module CLI
      module Import
        # 画像処理モジュール
        module ImageProcessor
          module_function

          # 画像を WebP に変換してコピーする
          #
          # @param starter_dir [String] Starter プロジェクトのディレクトリ
          # @return [void]
          def convert_to_webp!(starter_dir)
            Common.log_action('[Step 3] 画像を WebP に変換します')

            starter_images = File.join(starter_dir, 'images')
            unless Dir.exist?(starter_images)
              Common.log_warn("  images/ ディレクトリが見つかりません: #{starter_images}")
              return
            end

            files = copy_images_to_local(starter_images)
            return if files.empty?

            Common.log_info("  #{files.size} 個の画像をコピーしました")

            # ResizeCommands で WebP 変換
            ResizeCommands.execute_resize_medium('images')
            remove_original_files!
          end

          # 元画像（png/jpg/gif）を削除する
          #
          # @return [void]
          def remove_original_files!
            removed = 0
            Dir.glob(File.join('images', '**', '*')).each do |path|
              next unless File.file?(path)
              next unless path.match?(/\.(png|jpe?g|gif)$/i)

              FileUtils.rm_f(path)
              removed += 1
            end

            if removed.positive?
              Common.log_info("  旧画像 (png/jpg/gif) を #{removed} 個削除しました")
            else
              Common.log_info('  削除対象の旧画像はありませんでした')
            end
          end

          # 表紙 PDF をコピーする
          #
          # @param starter_dir [String] Starter プロジェクトのディレクトリ
          # @param cover_filename [String] 表紙ファイル名（例: hyoshi.pdf）
          # @return [Boolean] コピー成功時 true
          def copy_front_cover!(starter_dir, cover_filename)
            return false unless cover_filename
            return false unless cover_filename.downcase.end_with?('.pdf')

            src = File.join(starter_dir, 'images', cover_filename)
            unless File.exist?(src)
              Common.log_warn("  表紙 PDF が見つかりません: #{src}")
              return false
            end

            dest_dir = 'covers'
            FileUtils.mkdir_p(dest_dir)

            dest = File.join(dest_dir, cover_filename)
            FileUtils.cp(src, dest)
            Common.log_info("  表紙 PDF をコピーしました: #{cover_filename} → covers/")
            true
          end

          private

          module_function

          # 画像ファイルをローカルにコピーする
          #
          # @param starter_images [String] Starter の images ディレクトリパス
          # @return [Array<String>] コピーしたファイルのリスト
          def copy_images_to_local(starter_images)
            patterns = %w[png jpg jpeg gif PNG JPG JPEG GIF]
            files = patterns.flat_map { |ext| Dir.glob(File.join(starter_images, "**/*.#{ext}")) }

            if files.empty?
              Common.log_info('  変換対象の画像がありません')
              return []
            end

            files.each do |src|
              relative = src.sub("#{starter_images}/", '')
              dest_dir = File.join('images', File.dirname(relative))
              FileUtils.mkdir_p(dest_dir)
              FileUtils.cp(src, File.join(dest_dir, File.basename(src)))
            end

            files
          end
        end
      end
    end
  end
end
