# frozen_string_literal: true

require 'fileutils'
require_relative 'common'
require_relative 'units'
require_relative 'build/cmyk_converter'
require_relative 'build/crop_marks_overlay'
require_relative 'build/nombre_stamper'
require_relative 'build/print_geometry'
require_relative 'cover/svg_cover'

module VivlioStarter
  module CLI
    # ================================================================
    # Module: CoverCommands（表紙・裏表紙の生成）
    # ================================================================
    # 入口は `vs cover`（execute_generate）と `vs build`（ensure_cover_files_for_build!）の 2 つで、
    # どちらも generate! を通る。判型は book.yml の page.use、作るものは output.targets で決まる。
    #
    # 表と裏はそれぞれソースを決める（resolve_source）:
    #   1. covers/<side>cover_<theme>.png → PNG の経路（このファイル）
    #   2. covers/<side>cover_<theme>.svg → SVG の経路（cover/svg_cover.rb）。文字だけを当てる
    #   3. covers/bundled/<side>cover.svg → 同梱テンプレート。パレットと文字を当てる
    #   master は PNG だけを使うテーマ。
    #
    # 成果物（生成物はキャッシュへ、入稿・KDP へ渡すものは直下へも複製する）:
    #   pdf         → <side>cover_<theme>_<size>_rgb.pdf（閲覧用・仕上がりサイズ）
    #   print_pdf   → <side>cover_<theme>_<size>_cmyk.pdf（入稿用・塗り足し＋トンボ・PDF/X-1a）
    #   epub/kindle → cover_<theme>.jpg（表のみ・1,600 × 2,560 px）
    # ================================================================
    module CoverCommands
      module_function

      # master テーマの元の画像（vs import が書き出す名前でもある）
      FRONTCOVER_MASTER = 'frontcover_master.png'
      BACKCOVER_MASTER = 'backcover_master.png'

      # 判型ごとの仕上がりサイズ（350 dpi の画素数と mm。塗り足しを含まない）
      SIZES = {
        a4: { width: 2894, height: 4091, mm: [210, 297] },
        b5: { width: 2508, height: 3541, mm: [182, 257] },
        a5: { width: 2039, height: 2894, mm: [148, 210] }
      }.freeze

      DPI = 350

      # 印刷に使える実効解像度の下限（PNG の画素数と判型から求める）
      MIN_PRINT_DPI = 300

      # トンボ代（Vivliostyle と同じ）
      CROP_MARK_OFFSET_MM = 13.0

      # 電子書籍用（EPUB・Kindle）の表紙の寸法。KDP の理想の寸法（ebook-cover-jpeg-spec.md §1）。
      EPUB_SIZE = { width: 1600, height: 2560 }.freeze

      # 電子書籍用の表紙の JPEG の品質。KDP は「なるべく圧縮しない」（表示のときに KDP 側でも圧縮する）。
      EBOOK_COVER_QUALITY = 95

      # 電子書籍のターゲット。EPUB と Kindle は同じ 1 枚の JPEG を使う。
      EBOOK_TARGETS = %w[epub kindle].freeze

      # sRGB の色の情報を探す場所（ebook-cover-jpeg-spec.md §3.1）。gem には同梱しない。
      SRGB_PROFILE_CANDIDATES = [
        '/System/Library/ColorSync/Profiles/sRGB Profile.icc', # macOS
        '/usr/share/color/icc/colord/sRGB.icc',                 # Linux（colord）
        '/usr/share/color/icc/sRGB.icc',
        '/usr/share/ghostscript/*/iccprofiles/srgb.icc'         # Linux（Ghostscript）
      ].freeze

      # ================================================================
      # 入口
      # ================================================================

      # vs build から呼ばれる。設定が表紙を作れる状態のときだけ作る。
      def ensure_cover_files_for_build!
        return unless Common.cover_theme
        return unless Common.validate_cover_settings

        generate!
      end

      # vs cover の本体。表紙だけを作り直して確かめる・入稿や KDP へ出し直すときに使う。
      def execute_generate(_context = nil)
        theme = Common.cover_theme
        unless theme
          Common.log_error 'output.cover 設定が見つかりません'
          return
        end

        Common.log_info '📚 カバー画像の生成を開始します'
        targets = target_list(Common::CONFIG)
        unless generate!(targets:)
          Common.log_warn('カバーを作れませんでした（上のメッセージを確かめてください）')
          return
        end

        page_label = book_page_size.to_s.upcase
        labels = { 'pdf' => "PDF用（#{page_label}、RGB）", 'print_pdf' => "印刷用（#{page_label}、PDF/X-1a）" }
                 .filter_map { |target, label| label if targets.include?(target) }
        labels << '電子書籍用（JPEG）' if ebook_target?(targets)
        Common.log_success "\n✅ カバー画像の生成が完了しました"
        Common.log_info "生成されたカバー: #{labels.join(', ')}"
      end

      # 表と裏の表紙を作る。
      # @return [Boolean] 片面でも作れたか
      def generate!(targets: target_list(Common::CONFIG), page_size: book_page_size)
        theme = Common.cover_theme
        return false if theme == 'master' && !check_master_files(Common.covers_dir)

        FileUtils.mkdir_p(Common.cover_cache_dir)
        %w[front back].map do |side|
          case resolve_source(side, theme)
          in { type: :png, path: }
            write_png_outputs!(side, path, theme, page_size, targets)
            true
          in { type: :svg, path:, bundled: }
            SvgCover.write_outputs!(side, path, theme, page_size, targets, bundled:)
            true
          in { type: :missing }
            false
          end
        end.any?
      end

      # 片面の元の画像を、PNG → 著者の SVG → 同梱テンプレートの順に探す（改善案.md #65）。
      # @return [Hash] { type: :png, path: } / { type: :svg, path:, bundled: } / { type: :missing }
      def resolve_source(side, theme)
        covers_dir = Common.covers_dir
        png = File.join(covers_dir, "#{side}cover_#{theme}.png")
        return { type: :png, path: png } if File.exist?(png)
        # master は PNG だけのテーマ。足りない面は check_master_files が知らせている
        return { type: :missing } if theme == 'master'

        svg = File.join(covers_dir, "#{side}cover_#{theme}.svg")
        return { type: :svg, path: svg, bundled: false } if File.exist?(svg)

        bundled = File.join(covers_dir, 'bundled', "#{side}cover.svg")
        if File.exist?(bundled)
          warn_custom_theme_fallback(side, theme, png, svg)
          return { type: :svg, path: bundled, bundled: true }
        end

        Common.log_error("#{side}cover のソースが見つかりません。", detail: "確認先:\n#{[png, svg, bundled].join("\n")}")
        { type: :missing }
      end

      # 独自テーマ（light / dark 以外）の画像が無くて同梱テンプレートで作ったことを知らせる（改善案.md #65）。
      # 黙って同梱のデザインで作ると、`cover: floral` の書き誤りやファイル名の食い違いに気づけない。
      def warn_custom_theme_fallback(side, theme, png_path, svg_path)
        return if %w[light dark].include?(theme)

        Common.log_warn(
          "#{side}cover_#{theme} の画像が見つからないため、同梱のテンプレート（light）で作りました",
          detail: "探した場所: #{png_path}\n          #{svg_path}\n" \
                  "→ book.yml の output.cover のテーマ名と、covers/ に置いたファイル名が合っているか確かめてください"
        )
      end

      # 出力ターゲットの一覧。無指定なら pdf。
      def target_list(config)
        list = case config.dig(:output, :targets)
               in String => s then s.split(',')
               in Array => a then a.map(&:to_s)
               else []
               end
        list = list.map { it.strip.downcase }.reject(&:empty?)
        list.empty? ? ['pdf'] : list
      end

      # 電子書籍（EPUB・Kindle）のターゲットがあるか。あれば表紙の JPEG を作る。
      def ebook_target?(targets) = targets.intersect?(EBOOK_TARGETS)

      # book.yml の判型（page.use）から表紙の判型を決める。
      def book_page_size = detect_page_size(Common::CONFIG.page&.use || 'b5_standard')

      # 判型のプリセット名（a4_custom・b5_standard など）を :a4 / :b5 / :a5 にする。
      def detect_page_size(page_use)
        case page_use.to_s.downcase[0..1]
        in 'a4' then :a4
        in 'a5' then :a5
        else :b5
        end
      end

      # master テーマの元の PNG があるか。足りない面を知らせ、1 枚も無ければ false。
      def check_master_files(covers_dir, theme = 'master')
        frontcover = File.join(covers_dir, "frontcover_#{theme}.png")
        backcover = File.join(covers_dir, "backcover_#{theme}.png")

        front_exists = File.exist?(frontcover)
        back_exists = File.exist?(backcover)

        Common.log_warn("表紙マスターが見つかりません: #{frontcover}") unless front_exists
        Common.log_warn("裏表紙マスターが見つかりません: #{backcover}") unless back_exists

        front_exists || back_exists
      end

      # ================================================================
      # PNG の経路
      # ================================================================

      # 片面の PNG から、targets に応じた成果物を作る（SvgCover.write_outputs! と対になる）。
      def write_png_outputs!(side, png, theme, page_size, targets)
        cache_dir = Common.cover_cache_dir
        size = SIZES.fetch(page_size)

        if targets.include?('pdf')
          generate_rgb_pdf_single(png, File.join(cache_dir, "#{side}cover_#{theme}_#{page_size}_rgb.pdf"), size)
        end

        if targets.include?('print_pdf')
          warn_low_print_resolution(png, page_size)
          write_print_cover!(side, png, theme, page_size)
        end

        return unless side == 'front' && ebook_target?(targets)

        write_ebook_cover!(png, File.join(cache_dir, "cover_#{theme}.jpg"))
      end

      # PNG の画素数が判型に対して足りなければ知らせる。PNG に書かれた dpi の値は見ない
      # （画像ソフトが 72dpi と書くことが多く、画素が足りていても足りなく見えるため）。
      def warn_low_print_resolution(png, page_size)
        width, height = Common.image_size(png)
        return unless width

        trim_w_mm, trim_h_mm = SIZES.fetch(page_size)[:mm]
        dpi = [width / (trim_w_mm / Units::MM_PER_INCH), height / (trim_h_mm / Units::MM_PER_INCH)].min.floor
        return if dpi >= MIN_PRINT_DPI

        # 1 ビルドの中で表紙の生成は何度か走りうるので、同じ画像につき 1 回だけ知らせる
        @warned_low_resolution ||= {}
        return if @warned_low_resolution[png]

        @warned_low_resolution[png] = true
        size = SIZES.fetch(page_size)
        Common.log_warn(
          "#{File.basename(png)} の解像度が印刷には足りません（#{page_size.upcase} で #{dpi}dpi・最低 #{MIN_PRINT_DPI}dpi）",
          detail: "いまの画像: #{width} × #{height} px\n" \
                  "→ #{size[:width]} × #{size[:height]} px 以上の画像に差し替えてください（#{page_size.upcase} を #{DPI}dpi で刷る寸法）"
        )
      end

      # 入稿用（CMYK・塗り足し・トンボ）の表紙を作り、直下へ複製する。
      def write_print_cover!(side, png, theme, page_size)
        cover_bleed = (Common::CONFIG.dig(:output, :print_pdf, :cover_bleed) || 'scale').to_s
        source, fill = resolve_print_cover_input(png, cover_bleed)
        cache_pdf = File.join(Common.cover_cache_dir, "#{side}cover_#{theme}_#{page_size}_cmyk.pdf")
        generate_pdfx_single(source, cache_pdf, SIZES.fetch(page_size),
                             bleed_mm: Build::NombreStamper.bleed_mm_from_config, crop_marks: true, fill:)
        publish_print_cover!(side, cache_pdf)
      end

      # 閲覧用の PDF（RGB・仕上がりサイズ）
      def generate_rgb_pdf_single(input_png, output_pdf, size)
        return unless File.exist?(input_png)

        convert_cmd = imagemagick_convert_command
        unless convert_cmd
          Common.log_error 'ImageMagick（magick/convert）が見つかりません'
          return
        end

        Common.log_info "  生成中: #{File.basename(output_pdf)}"
        cmd = convert_cmd + [
          input_png,
          '-resize', "#{size[:width]}x#{size[:height]}!",
          '-density', DPI.to_s,
          '-units', 'PixelsPerInch',
          output_pdf
        ]
        Common.log_error "  失敗: #{File.basename(output_pdf)}" unless system(*cmd, out: File::NULL, err: File::NULL)
      end

      # 印刷カバー PDF（CMYK）をルート直下へ成果品として複製する（移設仕様 §3.4）。
      # CMYK カバーは入稿物であり、著者が covers/ や .cache を掘らずに最終 print PDF と
      # 同じ場所（ルート）で入稿一式を揃えられるようにする。cache 側は再生成判定と
      # vs cover 再実行の生成場所として残すため move ではなく copy とする。
      #
      # @param side [String] 'front' | 'back'
      # @param cache_pdf_path [String] cache 内の内部名 CMYK PDF
      # @return [String, nil] ルート側の成果品パス（生成元が無ければ nil）
      def publish_print_cover!(side, cache_pdf_path)
        return nil unless File.exist?(cache_pdf_path)

        output = Common.generate_cover_output_filename(side)
        FileUtils.cp(cache_pdf_path, output)
        # 1 ビルド内でカバー生成は複数回走り得る（print フェーズ＋Step 10）ため、
        # 常時表示の log_result は同一成果品につきプロセス内 1 回に抑える
        @published_print_covers ||= {}
        unless @published_print_covers[output]
          @published_print_covers[output] = true
          Common.log_result("入稿用カバー PDF: #{output}", status: :artifact)
        end
        output
      end

      # print 用の入力画像と充填モードを決める。
      #
      # 塗り足し込みの著者画像 `<base>_bleed.png`（例 frontcover_master_bleed.png）があれば
      # 最優先で採用する（実画が塗り足しまで届くのでトリム画像との絵柄差が出ない）。無ければ
      # `output.print_pdf.cover_bleed` 設定で分岐する:
      #   scale（既定）= トリム画像を塗り足しまで拡大して流用（中央拡大・端裁断を許容）
      #   keep         = 拡大しない（塗り足し帯は白。フチが端まで無いデザイン向け）
      #
      # @param png [String] 仕上がりサイズの元の PNG
      # @param cover_bleed [String] 'scale' | 'keep'
      # @return [Array(String, Symbol)] [入力 PNG, 充填モード（:bleed=塗り足し込み / :trim=仕上がりのみ）]
      def resolve_print_cover_input(png, cover_bleed)
        bleed_png = png.sub(/\.png\z/i, '_bleed.png')
        if File.exist?(bleed_png)
          Common.log_info "  塗り足し込み画像を使用: #{File.basename(bleed_png)}"
          return [bleed_png, :bleed]
        end

        cover_bleed == 'keep' ? [png, :trim] : [png, :bleed]
      end

      # CMYK PDF 生成（単一ファイル）
      #
      # crop_marks: false 時（pdf ターゲット）:
      #   PNG → 塗り足し込みサイズ(trim+bleed×2)でリサイズ + CMYK変換 → PDF
      #
      # crop_marks: true 時（print_pdf ターゲット）:
      #   PNG → 充填サイズ(fill=:bleed なら trim+bleed×2 / :trim なら trim)へリサイズ
      #       → トンボ代(offset)帯を白で残して全紙サイズへ中央配置 → 中間 PDF
      #       → add_crop_marks! でトンボを追加
      #       → Build::CmykConverter で Japan Color 2001 Coated → CMYK PDF/X-1a 化（ICC 有時）
      #
      # ICC が使える環境（press-ready 同梱 or 設定指定）ではレイアウトを RGB で作り、
      # gs で ICC ベース CMYK 変換＋PDF/X-1a 出力インテント埋込を行う。ICC 不在時は
      # 従来どおり ImageMagick の素朴 CMYK 変換にフォールバックする。
      #
      # @param input_png  [String]  入力 PNG パス
      # @param output_pdf [String]  出力 PDF パス
      # @param size       [Hash]    仕上がりサイズ { width: px, height: px, mm: [w, h] }
      # @param bleed_mm   [Float]   塗り足し幅（mm）
      # @param crop_marks [Boolean] トンボを付与するか
      # @param fill       [Symbol]  充填モード（:bleed=塗り足し込み / :trim=仕上がりのみ）
      def generate_pdfx_single(input_png, output_pdf, size, bleed_mm:, crop_marks: false, fill: :bleed)
        return unless File.exist?(input_png)

        convert_cmd = imagemagick_convert_command
        unless convert_cmd
          Common.log_error 'ImageMagick（magick/convert）が見つかりません'
          return
        end

        Common.log_info "  生成中: #{File.basename(output_pdf)}"

        trim_w_px = size[:width]
        trim_h_px = size[:height]
        px_per_mm = DPI / Units::MM_PER_INCH

        if crop_marks
          # --- Phase: トンボ付き PDF 生成 ---
          # 画像は塗り足しボックス(trim+bleed×2)または仕上がり(trim)サイズに収め、
          # トンボ代(offset)帯を白で残して全紙サイズへ中央配置する。かつて画像を全紙
          # サイズ(trim+(bleed+offset)×2)へ引き伸ばし約 +15% 拡大していた不具合を是正。

          # ページサイズ = 仕上がり + 塗り足し×2 + オフセット×2
          offset_mm  = CROP_MARK_OFFSET_MM
          bleed_px   = (bleed_mm * px_per_mm).round
          margin_px  = ((bleed_mm + offset_mm) * px_per_mm).round
          total_w_px = trim_w_px + (2 * margin_px)
          total_h_px = trim_h_px + (2 * margin_px)

          content_w_px, content_h_px =
            if fill == :trim
              [trim_w_px, trim_h_px]
            else
              [trim_w_px + (2 * bleed_px), trim_h_px + (2 * bleed_px)]
            end

          temp_pdf = "#{output_pdf}.temp.pdf"

          # ICC ベースの CMYK 変換が可能なら、レイアウトは RGB で作り、後段の gs で
          # Japan Color 2001 Coated → CMYK PDF/X-1a 化する（くすみ解消・出力インテント埋込）。
          # ICC が無い環境では従来どおり magick の素朴 CMYK 変換にフォールバックする。
          use_icc = Build::CmykConverter.available?
          colorspace_args = use_icc ? [] : ['-colorspace', 'CMYK']

          begin
            # Step 1: 画像を充填サイズへリサイズ→白背景の全紙サイズへ中央配置→PDF
            cmd_convert = convert_cmd + [
              input_png,
              '-resize', "#{content_w_px}x#{content_h_px}!",
              '-background', 'white',
              '-gravity', 'center',
              '-extent', "#{total_w_px}x#{total_h_px}",
              *colorspace_args,
              '-density', DPI.to_s,
              '-units', 'PixelsPerInch',
              temp_pdf
            ]
            unless system(*cmd_convert, out: File::NULL, err: File::NULL)
              Common.log_error "  失敗（PDF生成）: #{File.basename(output_pdf)}"
              return
            end

            # Step 2: トンボを重ね、TrimBox / BleedBox を確定する
            add_crop_marks!(temp_pdf, bleed_mm:, crop_offset_mm: offset_mm)

            # Step 2b: ICC ベースの CMYK PDF/X-1a 化（gs で色変換＋出力インテント埋込、
            # qpdf で TrimBox/BleedBox 確定）。失敗時は RGB のまま残す（印刷所側で変換可能）。
            if use_icc
              Build::CmykConverter.to_pdfx!(temp_pdf, bleed_mm:, crop_offset_mm: offset_mm,
                                                      title: File.basename(output_pdf, '.pdf'))
            end

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

      # ================================================================
      # PNG と SVG の両方の経路が使うもの
      # ================================================================

      # 入稿用の表紙にトンボを重ね、TrimBox / BleedBox を確定する。描き方と重ね方は本文の
      # 入稿用 PDF と同じ（CropMarksOverlay・qpdf --overlay）。ボックスは重ねた後に書く——
      # 先に TrimBox があると、qpdf --overlay がトンボを仕上がりの大きさに縮めて置くため。
      # @return [Boolean] 重ねられたか
      def add_crop_marks!(pdf_path, bleed_mm:, crop_offset_mm: CROP_MARK_OFFSET_MM)
        Build::CropMarksOverlay.apply!(pdf_path, bleed_mm:, crop_offset_mm:) &&
          Build::PrintGeometry.finalize_boxes!(pdf_path, bleed_mm:, crop_offset_mm:)
      end

      # 電子書籍用の表紙の JPEG を作る（ebook-cover-jpeg-spec.md §3）。表紙の元が PNG でも SVG でも、
      # 電子書籍用の JPEG はここでだけ作る（SVG は呼び出し側で PNG に焼いてから渡す）。
      #
      # 縦 2,560 px に縮めて中央の横 1,600 px を切り出し、色を sRGB に直して品質 95 で書く。
      # 書けたら、KDP へ上げる成果品としてプロジェクトの直下へも写す。
      #
      # @param source [String] 元の画像（PNG）
      # @param output [String] 書き出す JPEG（生成キャッシュ側。EPUB へ入れる元）
      # @return [Boolean] 書けたか
      def write_ebook_cover!(source, output)
        convert_cmd = imagemagick_convert_command
        unless convert_cmd
          Common.log_error 'ImageMagick（magick/convert）が見つかりません'
          return false
        end

        Common.log_info "  生成中: #{File.basename(output)}"
        cmd = convert_cmd + [
          source, *srgb_profile_args,
          '-resize', "x#{EPUB_SIZE[:height]}",
          '-gravity', 'center',
          '-crop', "#{EPUB_SIZE[:width]}x#{EPUB_SIZE[:height]}+0+0",
          '+repage',
          '-quality', EBOOK_COVER_QUALITY.to_s,
          output
        ]
        unless system(*cmd, out: File::NULL, err: File::NULL)
          Common.log_error "  失敗: #{File.basename(output)}"
          return false
        end

        publish_ebook_cover!(output)
        true
      end

      # 元の色の情報（Display P3 など）から sRGB へ直す ImageMagick の引数。元に色の情報が無ければ
      # sRGB とみなして付けるだけになる。sRGB の色の情報が OS に無ければ直さない
      # （KDP の指定は RGB なので、そのままでも上げられる。§3.1）。
      def srgb_profile_args
        profile = srgb_profile_path
        return ['-profile', profile] if profile

        Common.log_info '  sRGB の色の情報が見つからないため、表紙の色の情報は元の画像のまま書き出します'
        []
      end

      def srgb_profile_path
        SRGB_PROFILE_CANDIDATES.lazy.flat_map { Dir.glob(it) }.find { File.file?(it) }
      end

      # 電子書籍用の表紙の JPEG を、プロジェクトの直下へ成果品として写す。KDP では表紙を本と別に
      # 上げるので、著者が .cache を探さずに済むようにする。名前は入稿用の表紙の PDF とそろえる。
      # キャッシュ側は EPUB へ入れる元なので、move ではなく copy にする。
      #
      # @param cache_jpg_path [String] キャッシュ内の JPEG
      # @return [String] ルート側の成果品のパス
      def publish_ebook_cover!(cache_jpg_path)
        output = Common.generate_cover_output_filename('front', ext: 'jpg')
        FileUtils.cp(cache_jpg_path, output)
        # 1 ビルドの中で表紙の生成は何度か走りうるので、知らせるのは同じ成果品につき 1 回
        @published_ebook_covers ||= {}
        unless @published_ebook_covers[output]
          @published_ebook_covers[output] = true
          Common.log_result("電子書籍用カバー JPEG: #{output}", status: :artifact)
        end
        output
      end

      def imagemagick_convert_command
        return ['magick'] if Common.external_command_available?('magick')
        return ['convert'] if Common.external_command_available?('convert')

        nil
      end
    end
  end
end
