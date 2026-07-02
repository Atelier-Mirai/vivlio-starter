# frozen_string_literal: true

require 'fileutils'
require 'yaml'

module VivlioStarter
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

      # トンボオフセット（Vivliostyle 準拠）
      CROP_MARK_OFFSET_MM = 13.0

      # EPUB用サイズ
      EPUB_SIZE = { width: 1600, height: 2560 }.freeze

      # 標準テーマかどうかを判定
      STANDARD_THEMES = %w[light dark].freeze

      # ================================================================
      # ビルドパイプライン用統合エントリポイント
      # ================================================================

      # テーマに応じたカバーファイルを確実に生成する
      #
      # - light/dark: SVGテンプレートから生成し PDF/JPG に変換
      # - master/カスタム: 既存PNGから PDF/JPG に変換
      #
      # @return [void]
      def self.ensure_cover_files_for_build!
        theme = Common.cover_theme
        return unless theme
        return unless Common.validate_cover_settings

        if STANDARD_THEMES.include?(theme)
          require_relative 'create' unless defined?(CreateCommands)
          CreateCommands.execute_cover({})
        else
          config = Common::CONFIG
          page_use = config.page.use || 'b5_standard'
          size = detect_page_size(page_use)
          # PDF カバー（RGB/CMYK）は pdf/print_pdf ターゲットがある場合のみ生成する。
          # epub/kindle のみのビルドでは不要で、無条件に呼ぶと execute_for_size が
          # 「生成対象がありません」と誤警告するため、ターゲットで分岐する。
          targets = target_list(config)
          execute_for_size(size, nil) if targets.intersect?(%w[pdf print_pdf])
          # EPUB/Kindle 表紙の元になる JPG は常に生成する。
          generate_epub_cover(config.directories.covers, config)
        end
      end

      # ================================================================
      # コマンド実装
      # ================================================================

      def execute_generate(_context = nil)
        Common.log_info '📚 カバー画像の一括生成を開始します'

        config = Common::CONFIG
        theme = config.output.cover

        unless theme
          Common.log_error 'output.cover 設定が見つかりません'
          return
        end

        # light/dark テーマ: SVGテンプレートから一括生成
        if STANDARD_THEMES.include?(theme)
          require_relative 'create' unless defined?(CreateCommands)
          CreateCommands.execute_cover({})
          return
        end

        # master/カスタム テーマ: PNGから生成
        covers_dir = config.directories.covers
        page_cfg = config.page
        page_use = page_cfg[:use] || page_cfg[:preset] || page_cfg[:preset_name] || page_cfg[:size] || 'b5_standard'
        targets = target_list(config)
        page_size = CoverCommands.detect_page_size(page_use)
        Common.log_info "ページサイズ: #{page_size.upcase} (#{page_use})"

        unless CoverCommands.check_master_files(covers_dir)
          Common.log_error 'マスターファイルが見つかりません。処理を中断します。'
          return
        end
        generated = []

        generated += generate_pdf_targets_for_size(covers_dir, page_size, config, targets)

        # EPUB用カバー
        if targets.include?('epub')
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
        config = Common::CONFIG
        theme = config.output.cover || 'master'

        # light/dark テーマ: SVGテンプレートから生成
        if STANDARD_THEMES.include?(theme)
          require_relative 'create' unless defined?(CreateCommands)
          CreateCommands.execute_cover({})
          return
        end

        # master/カスタム テーマ: PNGから生成
        covers_dir = config.directories.covers
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
        config = Common::CONFIG
        theme = config.output.cover

        unless theme
          Common.log_error 'output.cover 設定が見つかりません'
          return
        end

        # light/dark テーマ: SVGテンプレートから生成（SVG→JPG変換含む）
        if STANDARD_THEMES.include?(theme)
          require_relative 'create' unless defined?(CreateCommands)
          CreateCommands.execute_cover({})
          Common.log_success '✅ EPUB用JPEGの生成が完了しました'
          return
        end

        # master/カスタム テーマ: PNGから生成
        covers_dir = config.directories.covers
        input_file = CoverCommands.resolve_epub_cover_input(covers_dir, theme)
        unless input_file
          Common.log_error "カバー入力画像が見つかりません（テーマ: #{theme}）"
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
        in 'a4' then :a4
        in 'a5' then :a5
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

      # 印刷用 CMYK PDF 生成（print_pdf ターゲット用）
      #
      # - size は常に仕上がりサイズ（base_size）を渡す
      # - 塗り足し・トンボオフセットの加算は generate_pdfx_single 内で行う
      # - crop_marks: true を渡すことでトンボ付き PDF を生成する
      def self.generate_cmyk_pdf(covers_dir, page_size, config)
        base_size = SIZES[page_size] # 仕上がりサイズ（塗り足しなし）
        bleed_mm  = parse_bleed_mm(config)

        Common.log_info "  塗り足し: #{bleed_mm}mm（片側）" if bleed_mm.positive?

        theme = config.dig(:output, :cover) || 'master'

        front_output = "frontcover_#{theme}_#{page_size}_cmyk.pdf"
        back_output  = "backcover_#{theme}_#{page_size}_cmyk.pdf"

        front_input = theme == 'master' ? FRONTCOVER_MASTER : "frontcover_#{theme}.png"
        back_input  = theme == 'master' ? BACKCOVER_MASTER  : "backcover_#{theme}.png"

        # print_pdf ターゲットは常にトンボ付きで生成する
        CoverCommands.generate_pdfx_single(
          File.join(covers_dir, front_input),
          File.join(covers_dir, front_output),
          base_size,
          bleed_mm: bleed_mm,
          crop_marks: true
        )

        CoverCommands.generate_pdfx_single(
          File.join(covers_dir, back_input),
          File.join(covers_dir, back_output),
          base_size,
          bleed_mm: bleed_mm,
          crop_marks: true
        )
      end

      # CMYK PDF 生成（単一ファイル）
      #
      # crop_marks: false 時（pdf ターゲット）:
      #   PNG → 塗り足し込みサイズでリサイズ + CMYK変換 → PDF
      #
      # crop_marks: true 時（print_pdf ターゲット）:
      #   PNG → 塗り足し込みサイズでリサイズ + CMYK変換 → 中間 PDF
      #       → add_crop_marks_overlay でトンボを追加 → 最終 PDF
      #
      # Ghostscript による PDF/X-1a 変換は省略し、ImageMagick のみで処理する。
      # PDF/X-1a 対応が必要な場合は将来のオプション機能として追加する。
      #
      # @param input_png  [String]  入力 PNG パス
      # @param output_pdf [String]  出力 PDF パス
      # @param size       [Hash]    仕上がりサイズ { width: px, height: px, mm: [w, h] }
      # @param bleed_mm   [Float]   塗り足し幅（mm）
      # @param crop_marks [Boolean] トンボを付与するか
      def self.generate_pdfx_single(input_png, output_pdf, size, bleed_mm:, crop_marks: false)
        return unless File.exist?(input_png)

        convert_cmd = imagemagick_convert_command
        unless convert_cmd
          Common.log_error 'ImageMagick（magick/convert）が見つかりません'
          return
        end

        Common.log_info "  生成中: #{File.basename(output_pdf)}"

        trim_w_px = size[:width]
        trim_h_px = size[:height]
        trim_w_mm = size[:mm][0]
        trim_h_mm = size[:mm][1]
        px_per_mm = DPI / 25.4

        if crop_marks
          # --- Phase: トンボ付き PDF 生成 ---
          # CreateCommands モジュールの add_crop_marks_overlay を使用
          require_relative 'create' unless defined?(CreateCommands)

          # ページサイズ = 仕上がり + 塗り足し×2 + オフセット×2
          offset_mm  = CROP_MARK_OFFSET_MM
          margin_mm  = bleed_mm + offset_mm
          (bleed_mm * px_per_mm).round
          margin_px  = (margin_mm * px_per_mm).round
          total_w_px = trim_w_px + (2 * margin_px)
          total_h_px = trim_h_px + (2 * margin_px)

          temp_pdf = "#{output_pdf}.temp.pdf"

          begin
            # Step 1: 塗り足し込みサイズでPDFを生成（トンボなし、背景色のみ）
            # ページサイズは仕上がり + 2 × (bleed + crop_offset) に設定
            cmd_convert = convert_cmd + [
              input_png,
              '-resize', "#{total_w_px}x#{total_h_px}!",
              '-colorspace', 'CMYK',
              '-density', DPI.to_s,
              '-units', 'PixelsPerInch',
              temp_pdf
            ]
            unless system(*cmd_convert, out: File::NULL, err: File::NULL)
              Common.log_error "  失敗（PDF生成）: #{File.basename(output_pdf)}"
              return
            end

            # Step 2: add_crop_marks_overlay でトンボを追加
            CreateCommands.add_crop_marks_overlay(temp_pdf, trim_w_mm, trim_h_mm, bleed_mm, offset_mm)

            # Step 3: 中間PDFを最終PDFにリネーム
            FileUtils.mv(temp_pdf, output_pdf)
          rescue StandardError => e
            Common.log_error "  失敗（トンボ付きPDF生成）: #{File.basename(output_pdf)} - #{e.message}"
            FileUtils.rm_f(temp_pdf) if temp_pdf && File.exist?(temp_pdf)
          end

        else
          # --- Phase: トンボなし PDF 生成（pdf ターゲット）---
          # 塗り足し込みサイズでリサイズして PDF 変換（既存動作を維持）
          bleed_px   = (bleed_mm * px_per_mm).round
          bleed_w_px = trim_w_px + (2 * bleed_px)
          bleed_h_px = trim_h_px + (2 * bleed_px)

          cmd_convert = convert_cmd + [
            input_png,
            '-resize', "#{bleed_w_px}x#{bleed_h_px}!",
            '-colorspace', 'CMYK',
            '-density', DPI.to_s,
            '-units', 'PixelsPerInch',
            output_pdf
          ]

          unless system(*cmd_convert, out: File::NULL, err: File::NULL)
            Common.log_error "  失敗（変換）: #{File.basename(output_pdf)}"
          end
        end
      end

      # EPUB用カバー生成（テーマベース）
      #
      # output.cover テーマに応じて入力画像を選択し cover_{theme}.jpg を生成する
      #   - light/dark: SVGから変換済みの frontcover_{theme}.png、なければSVG直接
      #   - master:     frontcover_master.png
      #   - カスタム:   frontcover_{theme}.png
      #
      # @param covers_dir [String] カバーディレクトリ
      # @param config [Hash] シンボルキーの設定ハッシュ
      def self.generate_epub_cover(covers_dir, config)
        theme = config.dig(:output, :cover) || config.dig('output', 'cover')
        return unless theme

        output_jpg = File.join(covers_dir, "cover_#{theme}.jpg")

        # 入力画像を解決（PNG優先、SVGフォールバック）
        input_file = resolve_epub_cover_input(covers_dir, theme)
        unless input_file
          Common.log_warn("EPUB用カバーの入力画像が見つかりません（テーマ: #{theme}）")
          return
        end

        convert_cmd = imagemagick_convert_command
        unless convert_cmd
          Common.log_error 'ImageMagick（magick/convert）が見つかりません'
          return
        end

        Common.log_info "  生成中: #{File.basename(output_jpg)}"

        cmd = convert_cmd + [
          input_file,
          '-resize', "x#{EPUB_SIZE[:height]}",
          '-gravity', 'center',
          '-crop', "#{EPUB_SIZE[:width]}x#{EPUB_SIZE[:height]}+0+0",
          '+repage',
          '-quality', '90',
          output_jpg
        ]

        Common.log_error "  失敗: #{File.basename(output_jpg)}" unless system(*cmd, out: File::NULL, err: File::NULL)
      end

      # EPUB カバー用の入力画像パスを解決する
      #
      # @param covers_dir [String] カバーディレクトリ
      # @param theme [String] テーマ名
      # @return [String, nil] 入力画像の絶対パス
      def self.resolve_epub_cover_input(covers_dir, theme)
        # master テーマ → frontcover_master.png
        if theme == 'master'
          path = File.join(covers_dir, FRONTCOVER_MASTER)
          return path if File.exist?(path)

          return nil
        end

        # light/dark/カスタム → frontcover_{theme}.png 優先
        png_path = File.join(covers_dir, "frontcover_#{theme}.png")
        return png_path if File.exist?(png_path)

        # light/dark のSVGフォールバック
        svg_path = File.join(covers_dir, "frontcover_#{theme}.svg")
        return svg_path if File.exist?(svg_path)

        nil
      end

      def self.imagemagick_convert_command
        return ['magick'] if find_executable('magick')

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

    end
  end
end
