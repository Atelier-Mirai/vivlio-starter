# frozen_string_literal: true

require 'fileutils'
require 'yaml'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: Thor コマンド群: cover（カバー画像生成）
      # ------------------------------------------------
      # - 目的: マスター画像からカバー画像を生成
      # - 提供コマンド: cover, cover:a4, cover:b5, cover:a5, cover:epub
      # ================================================================
      module CoverCommands
        module_function

        DESCRIPTION = 'カバー画像を生成'
        LONG_DESCRIPTION = <<~DESC
          マスター画像（frontcover_master.png, backcover_master.png）から
          各フォーマット用のカバー画像を生成します。

          使用例:
            vs cover              # 自動判定して一括生成
            vs cover a4           # A4サイズのRGB版PDF生成
            vs cover b5           # B5サイズのCMYK版PDF/X-1a生成
            vs cover a5           # A5サイズのCMYK版PDF/X-1a生成
            vs cover epub         # EPUB用JPEG生成

          必要なツール:
            - ImageMagick (convert コマンド)
            - Ghostscript (gs コマンド)
        DESC

        # マスターファイル名
        FRONTCOVER_MASTER = 'frontcover_master.png'
        BACKCOVER_MASTER = 'backcover_master.png'

        # サイズ定義（350 dpi基準）
        SIZES = {
          a4: { width: 2894, height: 4092, mm: [210, 297] },
          b5: { width: 2591, height: 3626, mm: [188, 263] },  # 塗り足し込み
          a5: { width: 2123, height: 2979, mm: [154, 216] }   # 塗り足し込み
        }.freeze

        # EPUB用サイズ
        EPUB_SIZE = { width: 1600, height: 2560 }.freeze

        # ================================================================
        # コマンド実装
        # ================================================================

        def execute_generate(context = nil)
          Common.log_info '📚 カバー画像の一括生成を開始します'

          # 設定読み込み
          config = Common.load_config
          covers_dir = config.dig('directories', 'covers') || 'covers'
          page_use = config.dig('page', 'use') || 'b5_standard'

          # ページサイズ判定
          page_size = CoverCommands.detect_page_size(page_use)
          Common.log_info "ページサイズ: #{page_size.upcase} (#{page_use})"

          # マスターファイル確認
          unless CoverCommands.check_master_files(covers_dir)
            Common.log_error 'マスターファイルが見つかりません。処理を中断します。'
            return
          end
          generated = []

          # PDF用カバー（RGB版）
          if config.dig('output', 'pdf', 'cover', 'front')
            Common.log_info "\n🎨 PDF用カバー（A4、RGB）を生成中..."
            CoverCommands.generate_rgb_pdf(covers_dir, config)
            generated << 'PDF用（RGB）'
          end

          # 印刷用PDF（CMYK版PDF/X-1a）
          if config.dig('output', 'print_pdf', 'cover', 'front')
            Common.log_info "\n🖨️  印刷用カバー（#{page_size.upcase}、CMYK、PDF/X-1a）を生成中..."
            CoverCommands.generate_cmyk_pdf(covers_dir, page_size, config)
            generated << "印刷用（#{page_size.upcase}、PDF/X-1a）"
          end

          # EPUB用カバー
          if config.dig('output', 'epub', 'cover')
            Common.log_info "\n📱 EPUB用カバー（1600×2560、JPEG）を生成中..."
            CoverCommands.generate_epub_cover(covers_dir, config)
            generated << 'EPUB用（JPEG）'
          end

          if generated.empty?
            Common.log_warn 'book.yml に出力設定が見つかりませんでした'
          else
            Common.log_success "\n✅ カバー画像の生成が完了しました"
            Common.log_info "生成されたカバー: #{generated.join(', ')}"
          end
        end
        module_function :execute_generate

        def execute_a4(context = nil)
          Common.log_info '📚 A4サイズのRGB版PDFを生成します'
          config = Common.load_config
          covers_dir = config.dig('directories', 'covers') || 'covers'

          unless CoverCommands.check_master_files(covers_dir)
            Common.log_error 'マスターファイルが見つかりません'
            return
          end

          CoverCommands.generate_rgb_pdf(covers_dir, config)
          Common.log_success '✅ A4 RGB版PDFの生成が完了しました'
        end
        module_function :execute_a4

        def execute_b5(context = nil)
          Common.log_info '📚 B5サイズのCMYK版PDF/X-1aを生成します'
          config = Common.load_config
          covers_dir = config.dig('directories', 'covers') || 'covers'

          unless CoverCommands.check_master_files(covers_dir)
            Common.log_error 'マスターファイルが見つかりません'
            return
          end

          CoverCommands.generate_cmyk_pdf(covers_dir, :b5, config)
          Common.log_success '✅ B5 CMYK版PDF/X-1aの生成が完了しました'
        end
        module_function :execute_b5

        def execute_a5(context = nil)
          Common.log_info '📚 A5サイズのCMYK版PDF/X-1aを生成します'
          config = Common.load_config
          covers_dir = config.dig('directories', 'covers') || 'covers'

          unless CoverCommands.check_master_files(covers_dir)
            Common.log_error 'マスターファイルが見つかりません'
            return
          end

          CoverCommands.generate_cmyk_pdf(covers_dir, :a5, config)
          Common.log_success '✅ A5 CMYK版PDF/X-1aの生成が完了しました'
        end
        module_function :execute_a5

        def execute_epub(context = nil)
          Common.log_info '📚 EPUB用JPEGを生成します'
          config = Common.load_config
          covers_dir = config.dig('directories', 'covers') || 'covers'

          frontcover_master = File.join(covers_dir, FRONTCOVER_MASTER)
          unless File.exist?(frontcover_master)
            Common.log_error "マスターファイルが見つかりません: #{frontcover_master}"
            return
          end

          CoverCommands.generate_epub_cover(covers_dir, config)
          Common.log_success '✅ EPUB用JPEGの生成が完了しました'
        end
        module_function :execute_epub

        # =========================== Helpers =============================

        # ページサイズを判定
        def self.detect_page_size(page_use)
          case page_use
          when /^b5/i
            :b5
          when /^a5/i
            :a5
          when /^a4/i
            :a4
          else
            :b5  # デフォルト
          end
        end

        # マスターファイルの存在確認
        def self.check_master_files(covers_dir)
          frontcover = File.join(covers_dir, FRONTCOVER_MASTER)
          backcover = File.join(covers_dir, BACKCOVER_MASTER)

          front_exists = File.exist?(frontcover)
          back_exists = File.exist?(backcover)

          Common.log_warn("表紙マスターが見つかりません: #{frontcover}") unless front_exists
          Common.log_warn("裏表紙マスターが見つかりません: #{backcover}") unless back_exists

          front_exists || back_exists
        end

        # RGB版PDF生成（A4サイズ）
        def self.generate_rgb_pdf(covers_dir, config)
          size = SIZES[:a4]
          front_output = config.dig('output', 'pdf', 'cover', 'front')
          back_output = config.dig('output', 'pdf', 'cover', 'back')

          if front_output
            CoverCommands.generate_rgb_pdf_single(
              File.join(covers_dir, FRONTCOVER_MASTER),
              File.join(covers_dir, front_output),
              size
            )
          end

          if back_output
            CoverCommands.generate_rgb_pdf_single(
              File.join(covers_dir, BACKCOVER_MASTER),
              File.join(covers_dir, back_output),
              size
            )
          end
        end

        # RGB版PDF生成（単一ファイル）
        def self.generate_rgb_pdf_single(input_png, output_pdf, size)
          return unless File.exist?(input_png)

          convert_cmd = imagemagick_convert_command
          unless convert_cmd
            Common.log_error 'ImageMagick（magick/convert）が見つかりません'
            return
          end

          Common.log_info "  生成中: #{File.basename(output_pdf)}"

          # ImageMagickでPNG→PDF変換
          cmd = convert_cmd + [
            input_png,
            '-resize', "#{size[:width]}x#{size[:height]}!",
            '-density', '350',
            '-units', 'PixelsPerInch',
            output_pdf
          ]

          unless system(*cmd, out: File::NULL, err: File::NULL)
            Common.log_error "  失敗: #{File.basename(output_pdf)}"
          end
        end

        # CMYK版PDF/X-1a生成
        def self.generate_cmyk_pdf(covers_dir, page_size, config)
          size = SIZES[page_size]
          front_output = config.dig('output', 'print_pdf', 'cover', 'front')
          back_output = config.dig('output', 'print_pdf', 'cover', 'back')

          if front_output
            CoverCommands.generate_pdfx_single(
              File.join(covers_dir, FRONTCOVER_MASTER),
              File.join(covers_dir, front_output),
              size
            )
          end

          if back_output
            CoverCommands.generate_pdfx_single(
              File.join(covers_dir, BACKCOVER_MASTER),
              File.join(covers_dir, back_output),
              size
            )
          end
        end

        # PDF/X-1a生成（単一ファイル）
        def self.generate_pdfx_single(input_png, output_pdf, size)
          return unless File.exist?(input_png)

          convert_cmd = imagemagick_convert_command
          unless convert_cmd
            Common.log_error 'ImageMagick（magick/convert）が見つかりません'
            return
          end

          Common.log_info "  生成中: #{File.basename(output_pdf)}"

          temp_pdf = "#{output_pdf}.temp.pdf"

          begin
            # Step 1: ImageMagickでリサイズ + CMYK変換
            cmd_convert = convert_cmd + [
              input_png,
              '-resize', "#{size[:width]}x#{size[:height]}!",
              '-colorspace', 'CMYK',
              '-density', '350',
              '-units', 'PixelsPerInch',
              temp_pdf
            ]

            unless system(*cmd_convert, out: File::NULL, err: File::NULL)
              Common.log_error "  失敗（変換）: #{File.basename(output_pdf)}"
              return
            end

            # Step 2: GhostscriptでPDF/X-1a変換
            cmd_gs = [
              'gs',
              '-dPDFX',
              '-dBATCH',
              '-dNOPAUSE',
              '-dQUIET',
              '-sDEVICE=pdfwrite',
              '-dCompatibilityLevel=1.4',
              "-sOutputFile=#{output_pdf}",
              temp_pdf
            ]

            unless system(*cmd_gs, out: File::NULL, err: File::NULL)
              Common.log_error "  失敗（PDF/X-1a変換）: #{File.basename(output_pdf)}"
            end
          ensure
            File.delete(temp_pdf) if File.exist?(temp_pdf)
          end
        end

        # EPUB用カバー生成
        def self.generate_epub_cover(covers_dir, config)
          input_png = File.join(covers_dir, FRONTCOVER_MASTER)
          output_jpg = File.join(covers_dir, config.dig('output', 'epub', 'cover'))

          return unless File.exist?(input_png)

          convert_cmd = imagemagick_convert_command
          unless convert_cmd
            Common.log_error 'ImageMagick（magick/convert）が見つかりません'
            return
          end

          Common.log_info "  生成中: #{File.basename(output_jpg)}"

          # ImageMagickでリサイズ + トリミング
          cmd = convert_cmd + [
            input_png,
            '-resize', "x#{EPUB_SIZE[:height]}",
            '-gravity', 'center',
            '-crop', "#{EPUB_SIZE[:width]}x#{EPUB_SIZE[:height]}+0+0",
            '+repage',
            '-quality', '90',
            output_jpg
          ]

          unless system(*cmd, out: File::NULL, err: File::NULL)
            Common.log_error "  失敗: #{File.basename(output_jpg)}"
          end
        end

        def self.imagemagick_convert_command
          return ['magick', 'convert'] if find_executable('magick')
          return ['convert'] if find_executable('convert')
          nil
        end

        def self.find_executable(command)
          return nil if command.to_s.empty?

          ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |dir|
            path = File.join(dir, command)
            return path if File.executable?(path) && !File.directory?(path)
          end

          nil
        end
      end
    end
  end
end
