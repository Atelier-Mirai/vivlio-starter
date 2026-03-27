# frozen_string_literal: true

require 'fileutils'
require 'yaml'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: カバー画像生成ロジック
      # ================================================================
      # 提供機能:
      #   - マスター画像から各フォーマット用カバー画像を生成
      #   - A4/B5/A5/EPUB 対応
      # ================================================================
      module CoverCommands
        module_function

        DESCRIPTION = 'カバー画像を生成'
        LONG_DESCRIPTION = <<~DESC
          マスター画像（frontcover_master.png, backcover_master.png）から
          各フォーマット用のカバー画像を生成します。

          使用例:
            vs cover              # 自動判定して一括生成
            vs cover a4           # A4サイズのCMYK版PDF/X-1a生成
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

        # サイズ定義（350 dpi基準、本文サイズ＝塗り足しなし）
        SIZES = {
          a4: { width: 2894, height: 4091, mm: [210, 297] },
          b5: { width: 2508, height: 3541, mm: [182, 257] },
          a5: { width: 2039, height: 2894, mm: [148, 210] }
        }.freeze

        DPI = 350

        # EPUB用サイズ
        EPUB_SIZE = { width: 1600, height: 2560 }.freeze

        # ================================================================
        # コマンド実装
        # ================================================================

        def execute_generate(_context = nil)
          Common.log_info '📚 カバー画像の一括生成を開始します'

          # 設定読み込み（シンボルキー前提）
          config = Common.load_config
          covers_dir = config[:directories][:covers]
          page_cfg = config[:page] || {}
          page_use = page_cfg[:use] || page_cfg[:preset] || page_cfg[:preset_name] || page_cfg[:size] || 'b5_standard'
          targets = target_list(config)

          # ページサイズ判定
          page_size = CoverCommands.detect_page_size(page_use)
          Common.log_info "ページサイズ: #{page_size.upcase} (#{page_use})"

          # マスターファイル確認
          unless CoverCommands.check_master_files(covers_dir)
            Common.log_error 'マスターファイルが見つかりません。処理を中断します。'
            return
          end
          generated = []

          generated += generate_pdf_targets_for_size(covers_dir, page_size, config, targets)

          # EPUB用カバー
          if targets.include?('epub') && config.dig(:output, :epub, :cover)
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

        def execute_for_size(page_size, _context = nil)
          label = page_size.to_s.upcase
          Common.log_info "📚 #{label}サイズのカバーPDFを生成します"
          config = Common.load_config
          covers_dir = config[:directories][:covers]
          targets = target_list(config)

          unless CoverCommands.check_master_files(covers_dir)
            Common.log_error 'マスターファイルが見つかりません'
            return
          end

          generated = generate_pdf_targets_for_size(covers_dir, page_size, config, targets)

          if generated.empty?
            Common.log_warn('生成対象がありませんでした (pdf/print_pdf ターゲットが無効化されている可能性があります)')
          else
            Common.log_success("✅ #{label}カバーPDFの生成が完了しました: #{generated.join(', ')}")
          end
        end
        module_function :execute_for_size

        def execute_epub(_context = nil)
          Common.log_info '📚 EPUB用JPEGを生成します'
          config = Common.load_config
          covers_dir = config[:directories][:covers]

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

        # 出力ターゲット一覧を取得（シンボルキー前提）
        def target_list(config)
          raw = config.dig(:output, :targets)
          list = case raw
                 in String => s
                   s.split(',').map(&:strip)
                 in Array => a
                   a.map { |v| v.to_s.strip }
                 else
                   []
                 end

          list = list.reject(&:empty?).map(&:downcase)
          list = ['pdf'] if list.empty?
          list
        end
        module_function :target_list

        def generate_pdf_targets_for_size(covers_dir, page_size, config, targets)
          generated = []
          label = page_size.to_s.upcase
          pdf_target_enabled = targets.include?('pdf')
          print_target_enabled = targets.include?('print_pdf')

          # 新しい設定構造に対応
          if pdf_target_enabled
            Common.log_info("\n🎨 PDF用カバー（#{label}、RGB）を生成中...")
            CoverCommands.generate_rgb_pdf(covers_dir, page_size, config)
            generated << 'PDF用（RGB）'
          end

          if print_target_enabled
            Common.log_info("\n🖨️  印刷用カバー（#{label}、CMYK、PDF/X-1a）を生成中...")
            CoverCommands.generate_cmyk_pdf(covers_dir, page_size, config)
            generated << "印刷用（#{label}、PDF/X-1a）"
          end

          generated
        end
        module_function :generate_pdf_targets_for_size

        # ページサイズを判定
        def self.detect_page_size(page_use)
          case page_use.to_s.downcase[0..1]
          in "a4" then :a4
          in "a5" then :a5
          else :b5 # デフォルト
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

        # RGB版PDF生成（ページサイズ依存）
        def self.generate_rgb_pdf(covers_dir, page_size, config)
          size = SIZES[page_size] || SIZES[:b5]
          theme = config.dig(:output, :cover) || 'master'
          
          # 新しい命名規則で出力ファイル名を生成
          front_output = "frontcover_#{theme}_#{page_size}_rgb.pdf"
          back_output = "backcover_#{theme}_#{page_size}_rgb.pdf"

          # masterテーマの場合はmaster.pngを、それ以外はテーマ名のPNGを使用
          front_input = theme == 'master' ? FRONTCOVER_MASTER : "frontcover_#{theme}.png"
          back_input = theme == 'master' ? BACKCOVER_MASTER : "backcover_#{theme}.png"

          CoverCommands.generate_rgb_pdf_single(
            File.join(covers_dir, front_input),
            File.join(covers_dir, front_output),
            size
          )

          CoverCommands.generate_rgb_pdf_single(
            File.join(covers_dir, back_input),
            File.join(covers_dir, back_output),
            size
          )
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

          Common.log_error "  失敗: #{File.basename(output_pdf)}" unless system(*cmd, out: File::NULL, err: File::NULL)
        end

        # CMYK版PDF/X-1a生成（bleed 追加）
        def self.generate_cmyk_pdf(covers_dir, page_size, config)
          base_size = SIZES[page_size]
          bleed_mm = parse_bleed_mm(config)
          size = add_bleed_to_size(base_size, bleed_mm)

          Common.log_info "  塗り足し: #{bleed_mm}mm（片側）→ #{size[:mm][0]}×#{size[:mm][1]}mm" if bleed_mm > 0

          theme = config.dig(:output, :cover) || 'master'
          
          # 新しい命名規則で出力ファイル名を生成
          front_output = "frontcover_#{theme}_#{page_size}_cmyk.pdf"
          back_output = "backcover_#{theme}_#{page_size}_cmyk.pdf"

          # masterテーマの場合はmaster.pngを、それ以外はテーマ名のPNGを使用
          front_input = theme == 'master' ? FRONTCOVER_MASTER : "frontcover_#{theme}.png"
          back_input = theme == 'master' ? BACKCOVER_MASTER : "backcover_#{theme}.png"

          CoverCommands.generate_pdfx_single(
            File.join(covers_dir, front_input),
            File.join(covers_dir, front_output),
            size
          )

          CoverCommands.generate_pdfx_single(
            File.join(covers_dir, back_input),
            File.join(covers_dir, back_output),
            size
          )
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
            FileUtils.rm_f(temp_pdf)
          end
        end

        # EPUB用カバー生成
        def self.generate_epub_cover(covers_dir, config)
          input_png = File.join(covers_dir, FRONTCOVER_MASTER)
          # Hash と Data オブジェクト両対応
          epub_cover = if config.respond_to?(:dig)
                         config.dig(:output, :epub, :cover) || config.dig('output', 'epub', 'cover')
                       else
                         config.output&.epub&.cover
                       end
          return unless epub_cover

          # cover がネスト構造（embed + image）の場合は image を取得
          image_name = case epub_cover
                       when Hash then epub_cover[:image] || epub_cover['image'] || 'cover.jpg'
                       when String then epub_cover
                       else
                         epub_cover.respond_to?(:image) ? (epub_cover.image || 'cover.jpg') : 'cover.jpg'
                       end

          output_jpg = File.join(covers_dir, image_name)
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

          Common.log_error "  失敗: #{File.basename(output_jpg)}" unless system(*cmd, out: File::NULL, err: File::NULL)
        end

        def self.imagemagick_convert_command
          return %w[magick convert] if find_executable('magick')

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

        # bleed 値を mm で取得（"3mm" → 3）
        def self.parse_bleed_mm(config)
          bleed_raw = config.dig(:output, :print_pdf, :bleed) || config.dig('output', 'print_pdf', 'bleed')
          return 0 unless bleed_raw

          bleed_raw.to_s.gsub(/mm\z/i, '').to_f
        end

        # サイズに bleed を追加（片側なので幅・高さそれぞれ2倍追加）
        def self.add_bleed_to_size(base_size, bleed_mm)
          return base_size if bleed_mm <= 0

          bleed_px = (bleed_mm * DPI / 25.4).round
          total_bleed_px = bleed_px * 2  # 両側分

          {
            width: base_size[:width] + total_bleed_px,
            height: base_size[:height] + total_bleed_px,
            mm: [base_size[:mm][0] + (bleed_mm * 2), base_size[:mm][1] + (bleed_mm * 2)]
          }
        end
      end
    end
  end
end
