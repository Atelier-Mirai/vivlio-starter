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
require 'shellwords'

require_relative '../cover'

module Vivlio
  module Starter
    module CLI
      module Import
        # 画像処理モジュール
        module ImageProcessor
          module_function

          MASTER_WIDTH = CoverCommands::SIZES[:a4][:width]
          MASTER_HEIGHT = CoverCommands::SIZES[:a4][:height]

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

          # 表紙 PDF をコピーし、frontcover_master.png を生成する
          #
          # @param starter_dir [String] Starter プロジェクトのディレクトリ
          # @param cover_filename [String] 表紙ファイル名（例: hyoshi.pdf）
          # @return [Boolean] 成功時 true
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

            convert_front_cover_pdf_to_master!(dest_dir, cover_filename)
          end

          # Re:VIEW の PDF を Vivlio マスター PNG へ変換する
          def convert_front_cover_pdf_to_master!(covers_dir, cover_filename)
            pdf_path = File.join(covers_dir, cover_filename)
            unless File.exist?(pdf_path)
              Common.log_warn("  コピー済みの表紙 PDF が見つかりません: #{pdf_path}")
              return false
            end

            convert_cmd = find_imagemagick_convert_command
            unless convert_cmd
              Common.log_warn('  ImageMagick（magick/convert）が見つからないため frontcover_master.png を生成できませんでした')
              return false
            end

            master_path = File.join(covers_dir, CoverCommands::FRONTCOVER_MASTER)
            cmd = convert_cmd + [
              "#{pdf_path}[0]",
              '-density', '350',
              '-resize', "#{MASTER_WIDTH}x#{MASTER_HEIGHT}!",
              '-quality', '100',
              "PNG32:#{master_path}"
            ]

            if run_imagemagick_command(cmd, label: 'frontcover_master.png 生成')
              Common.log_info("  frontcover_master.png を生成しました: #{master_path}")
              true
            else
              FileUtils.rm_f(master_path)
              false
            end
          end

          # ============================== Private ==============================
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

          def find_imagemagick_convert_command
            return %w[magick convert] if command_in_path?('magick')
            return ['convert'] if command_in_path?('convert')

            nil
          end

          def command_in_path?(command)
            return false if command.to_s.empty?

            ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
              path = File.join(dir, command)
              File.executable?(path) && !File.directory?(path)
            end
          end

          def run_imagemagick_command(cmd, label:)
            Common.log_action("  $ #{Shellwords.join(cmd.map(&:to_s))}")
            success = system(*cmd, out: File::NULL, err: File::NULL)
            Common.log_error("  #{label} に失敗しました") unless success
            success
          end
        end
      end
    end
  end
end
