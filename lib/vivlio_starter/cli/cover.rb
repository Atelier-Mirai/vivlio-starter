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
    # どちらも validate_cover_settings で設定を検査してから generate! を通る。判型は book.yml の page.use、
    # 作るものは output.targets で決まる。
    #
    # 表と裏はそれぞれソースを決める（resolve_source）:
    #   1. covers/<side>cover_<theme>.png（.jpg・.jpeg・.webp）→ 画像の経路（このファイル）
    #   2. covers/<side>cover_<theme>.svg → SVG の経路（cover/svg_cover.rb）。文字だけを当てる
    #   3. covers/bundled/<side>cover.svg → 同梱テンプレート（light / dark だけ）。パレットと文字を当てる
    #   master は片面だけでも組むテーマ（vs import の取り込み先。裏表紙の無い本が多い）。
    #
    # 成果物（生成物はキャッシュへ、入稿・KDP へ渡すものは直下へも複製する）:
    #   pdf         → <side>cover_<theme>_<size>_rgb.pdf（閲覧用・仕上がりサイズ）
    #   print_pdf   → <side>cover_<theme>_<size>_cmyk.pdf（入稿用・塗り足し＋トンボ・PDF/X-1a）
    #   epub/kindle → cover_<theme>.jpg（表のみ・1,600 × 2,560 px）
    # ================================================================
    module CoverCommands
      module_function

      # vs import が書き出す master テーマの元の画像（表紙の元は JPEG・WebP でもよい）
      FRONTCOVER_MASTER = 'frontcover_master.png'
      BACKCOVER_MASTER = 'backcover_master.png'

      DPI = 350

      # 表紙の仕上がりの寸法（塗り足しを含まない。cover-size-independence-spec.md §2.1）。
      #   width_mm・height_mm … 仕上がりの mm（整数で割り切れるときは Integer。rsvg-convert へ渡す字面を変えないため）
      #   width・height       … 350dpi の画素数
      #   name                … 生成物のファイル名の判型の部分（a4・b5・120x180）
      #   label               … 著者向けの文面に出す判型の名前（A4・B5）
      TrimSize = Data.define(:width_mm, :height_mm, :width, :height, :name, :label) do
        def mm = [width_mm, height_mm]
      end

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
      # vs build と同じ検査を通す。独自のテーマの画像が無ければ 🔴 で報告して作らない
      # （同梱のデザインで代わりに作ると、テーマ名やファイル名の書き誤りが表紙の見た目に紛れる）。
      # @return [Boolean] 表紙を作れたか
      def execute_generate(_context = nil)
        unless Common.cover_theme
          Common.log_error 'book.cover 設定が見つかりません'
          return false
        end
        return false unless Common.validate_cover_settings

        Common.log_info '📚 カバー画像の生成を開始します'
        targets = target_list(Common::CONFIG)
        trim = book_trim_size
        unless trim && generate!(targets:, trim:)
          Common.log_warn('カバーを作れませんでした（上のメッセージを確かめてください）')
          return false
        end

        # 閲覧用だけのときは成果品の行（📚）が出ないので、作ったものを既定のログでも 1 行で報告する
        labels = { 'pdf' => "閲覧用 PDF（#{trim.label}・RGB）", 'print_pdf' => "入稿用 PDF（#{trim.label}・CMYK）" }
                 .filter_map { |target, label| label if targets.include?(target) }
        labels << '電子書籍用 JPEG' if ebook_target?(targets)
        Common.log_result("表紙を生成しました: #{labels.join('、')}", status: :success)
        true
      end

      # 表と裏の表紙を作る。
      # @return [Boolean] 片面でも作れたか
      # @param trim [TrimSize, nil] 表紙の寸法（既定は本の判型。決まらなければ作らない）
      def generate!(targets: target_list(Common::CONFIG), trim: book_trim_size)
        return false unless trim

        theme = Common.cover_theme
        return false if theme == 'master' && !check_master_files(Common.covers_dir)

        FileUtils.mkdir_p(Common.cover_cache_dir)
        %w[front back].map do |side|
          case resolve_source(side, theme)
          in { type: :raster, path: }
            write_raster_outputs!(side, path, theme, trim, targets)
            true
          in { type: :svg, path:, bundled: }
            SvgCover.write_outputs!(side, path, theme, trim, targets, bundled:)
            true
          in { type: :missing }
            false
          end
        end.any?
      end

      # 片面の元の画像を、画像（PNG・JPEG・WebP）→ 著者の SVG → 同梱テンプレートの順に探す（改善案.md #65）。
      # @return [Hash] { type: :raster, path: } / { type: :svg, path:, bundled: } / { type: :missing }
      def resolve_source(side, theme)
        covers_dir = Common.covers_dir
        raster = Common.cover_raster_path("#{side}cover_#{theme}")
        return { type: :raster, path: raster } if raster

        svg = File.join(covers_dir, "#{side}cover_#{theme}.svg")
        return { type: :svg, path: svg, bundled: false } if File.exist?(svg)
        # master の足りない面は check_master_files が 🟡 で知らせている
        return { type: :missing } if theme == 'master'

        # 同梱のテンプレートを使うのは light / dark だけ。独自のテーマの画像が無いことは
        # validate_cover_settings が先に 🔴 で報告する
        bundled = File.join(covers_dir, 'bundled', "#{side}cover.svg")
        candidates = [File.join(covers_dir, "#{side}cover_#{theme}.png（.jpg・.webp も可）"), svg]
        if %w[light dark].include?(theme)
          return { type: :svg, path: bundled, bundled: true } if File.exist?(bundled)

          candidates << bundled
        end

        Common.log_error("#{side}cover のソースが見つかりません。", detail: "確認先:\n#{candidates.join("\n")}")
        { type: :missing }
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

      # 表紙の仕上がりの寸法を、本文の @page と同じ出どころ（判型のプリセットの size: と
      # page.width・page.height）から求める。表紙の側に判型の表を持たないのは、判型を足したときに
      # 表紙だけが取り残されて別の寸法で組まれるのを防ぐため（cover-size-independence-spec.md §2）。
      # @param page [Hash] 判型のプリセットを当てた後の page の設定（シンボルのキー）
      # @return [TrimSize, nil] 寸法が決まらない（size: が表に無く、幅と高さも無い）ときは nil
      def trim_size(page = Common::CONFIG&.page.to_h)
        size = page[:size].to_s.strip.upcase
        preset = Common::PAGE_SIZES[size]
        width_mm, height_mm = %i[width height].map do |key|
          mm = Units.length_to_mm(page[key]) || Units.length_to_mm(preset&.fetch(key))
          mm && (mm == mm.round ? mm.round : mm)
        end
        return nil unless width_mm&.positive? && height_mm&.positive?

        # プリセットの寸法のままなら判型の名前、幅と高さを直接書いて違えば「幅x高さ」（§2.2）
        if preset && [width_mm, height_mm] == %i[width height].map { Units.length_to_mm(preset[it]) }
          name = size.downcase.delete_prefix('jis-').delete('-')
          label = preset[:label]
        else
          name = "#{width_mm.round}x#{height_mm.round}"
          label = "#{format_mm(width_mm)} × #{format_mm(height_mm)} mm"
        end
        TrimSize.new(width_mm:, height_mm:, name:, label:,
                     width: (width_mm / Units::MM_PER_INCH * DPI).round,
                     height: (height_mm / Units::MM_PER_INCH * DPI).round)
      end

      # 本の判型の表紙の寸法。決まらなければ 🔴 で知らせて nil（今までの「黙って B5 で組む」はしない）。
      def book_trim_size
        trim_size || begin
          Common.log_error('表紙の寸法が決まりません。config/book.yml の page.use を確かめてください',
                           detail: "→ 判型のプリセットの size: に #{Common::PAGE_SIZES.keys.join('・')} のどれかを書くか、" \
                                   'page.width と page.height を書いてください')
          nil
        end
      end

      # master テーマの元（画像か SVG）があるか。足りない面を知らせ、1 枚も無ければ false。
      def check_master_files(covers_dir, theme = 'master')
        frontcover = File.join(covers_dir, "frontcover_#{theme}.png（.jpg・.webp・.svg も可）")
        backcover = File.join(covers_dir, "backcover_#{theme}.png（.jpg・.webp・.svg も可）")

        front_exists = Common.cover_source?("frontcover_#{theme}", dir: covers_dir)
        back_exists = Common.cover_source?("backcover_#{theme}", dir: covers_dir)

        guidance = Common.master_cover_guidance
        Common.log_warn("表紙マスターが見つかりません: #{frontcover}", detail: guidance) unless front_exists
        Common.log_warn("裏表紙マスターが見つかりません: #{backcover}", detail: guidance) unless back_exists

        front_exists || back_exists
      end

      # ================================================================
      # 画像（PNG・JPEG・WebP）の経路
      # ================================================================

      # 片面の画像（PNG・JPEG・WebP）から、targets に応じた成果物を作る（SvgCover.write_outputs! と対になる）。
      def write_raster_outputs!(side, image, theme, trim, targets)
        cache_dir = Common.cover_cache_dir

        if targets.include?('pdf')
          crop = crop_to_fit?(image, trim.width_mm, trim.height_mm, trim)
          generate_rgb_pdf_single(image, File.join(cache_dir, "#{side}cover_#{theme}_#{trim.name}_rgb.pdf"), trim, crop:)
        end

        if targets.include?('print_pdf')
          warn_low_print_resolution(image, trim)
          write_print_cover!(side, image, theme, trim)
        end

        return unless side == 'front' && ebook_target?(targets)

        write_ebook_cover!(image, File.join(cache_dir, "cover_#{theme}.jpg"), trim:)
      end

      # 画像の縦横比を「違う」とみなす差（cover-size-independence-spec.md §3.1）。A 列の絵を B 列の本に
      # 使う（差 0.2%）ような小さな違いは、今までどおり判型の画素数へ合わせる。
      ASPECT_TOLERANCE = 0.01

      # 画像を、合わせる先（w_mm × h_mm）へ引き伸ばさずに中央で切るか。比の差が ASPECT_TOLERANCE を
      # 超えれば切る。引き伸ばすと絵が歪み、著者が気づかないまま入稿されるため（§3.1）。
      # @param bleed [Boolean] 合わせる先が塗り足しを含む寸法か（*_bleed の画像）
      def crop_to_fit?(image, w_mm, h_mm, trim, bleed: false)
        iw, ih = Common.image_size(image)
        return false unless iw&.positive? && ih&.positive?

        image_ratio = ih.to_f / iw
        return false if ((image_ratio / (h_mm.to_f / w_mm)) - 1).abs <= ASPECT_TOLERANCE

        warn_aspect_mismatch(image, image_ratio, w_mm, h_mm, trim, bleed:)
        true
      end

      # 切る向きと量、切らずに使える画素数を 🟡 で知らせる。閲覧用と入稿用で同じ画像を 2 回測るので、1 回だけ。
      def warn_aspect_mismatch(image, image_ratio, w_mm, h_mm, trim, bleed:)
        @warned_aspect ||= {}
        return if @warned_aspect[image]

        @warned_aspect[image] = true
        # 覆うように縮めたとき、はみ出す向きの片側の量
        cut = if image_ratio > h_mm.to_f / w_mm
                "上下を #{format_mm(((w_mm * image_ratio) - h_mm) / 2)}mm ずつ"
              else
                "左右を #{format_mm(((h_mm / image_ratio) - w_mm) / 2)}mm ずつ"
              end
        target = "判型（#{trim_description(trim)}）"
        target += "に塗り足しを足した寸法（#{format_mm(w_mm)} × #{format_mm(h_mm)} mm）" if bleed
        px = [w_mm, h_mm].map { (it / Units::MM_PER_INCH * DPI).round }
        Common.log_warn(
          "#{image} の縦横比が、#{target}と違います",
          detail: "#{cut}切り落として使いました\n" \
                  "→ #{px.join(' × ')} px の画像に差し替えると、切らずに使えます" \
                  "（#{bleed ? '塗り足しを含めて' : ''}#{trim.label} を #{DPI}dpi で刷る寸法）"
        )
      end

      # 文面の判型の書き方（「新書・103 × 182 mm」）。幅と高さを直接書いた本は寸法だけ。
      def trim_description(trim)
        dims = "#{format_mm(trim.width_mm)} × #{format_mm(trim.height_mm)} mm"
        trim.label == dims ? dims : "#{trim.label}・#{dims}"
      end

      # mm の値を文面へ（小数 1 桁。整数なら小数点を付けない）
      def format_mm(value)
        rounded = value.to_f.round(1)
        rounded == rounded.round ? rounded.round.to_s : rounded.to_s
      end

      # 画像を w_px × h_px へ合わせる ImageMagick の引数。crop なら覆うように縮めて中央で切り、
      # でなければ比の小さな違いを引き伸ばして合わせる。
      def fit_args(w_px, h_px, crop:)
        return ['-resize', "#{w_px}x#{h_px}!"] unless crop

        ['-resize', "#{w_px}x#{h_px}^", '-gravity', 'center', '-extent', "#{w_px}x#{h_px}"]
      end

      # PNG の画素数が判型に対して足りなければ知らせる。PNG に書かれた dpi の値は見ない
      # （画像ソフトが 72dpi と書くことが多く、画素が足りていても足りなく見えるため）。
      def warn_low_print_resolution(png, trim)
        width, height = Common.image_size(png)
        return unless width

        dpi = [width / (trim.width_mm / Units::MM_PER_INCH), height / (trim.height_mm / Units::MM_PER_INCH)].min.floor
        return if dpi >= MIN_PRINT_DPI

        # 1 ビルドの中で表紙の生成は何度か走りうるので、同じ画像につき 1 回だけ知らせる
        @warned_low_resolution ||= {}
        return if @warned_low_resolution[png]

        @warned_low_resolution[png] = true
        Common.log_warn(
          "#{File.basename(png)} の解像度が印刷には足りません（#{trim.label} で #{dpi}dpi・最低 #{MIN_PRINT_DPI}dpi）",
          detail: "いまの画像: #{width} × #{height} px\n" \
                  "→ #{trim.width} × #{trim.height} px 以上の画像に差し替えてください（#{trim.label} を #{DPI}dpi で刷る寸法）"
        )
      end

      # 入稿用（CMYK・塗り足し・トンボ）の表紙を作り、直下へ複製する。
      def write_print_cover!(side, png, theme, trim)
        cover_bleed = (Common::CONFIG.dig(:output, :print_pdf, :cover_bleed) || 'scale').to_s
        source, fill = resolve_print_cover_input(png, cover_bleed)
        bleed_mm = Build::NombreStamper.bleed_mm_from_config
        # 塗り足し込みの画像（*_bleed）は「仕上がり＋塗り足し」の比と比べる（§3.1）
        crop = if source == png
                 crop_to_fit?(png, trim.width_mm, trim.height_mm, trim)
               else
                 crop_to_fit?(source, trim.width_mm + (2 * bleed_mm), trim.height_mm + (2 * bleed_mm), trim, bleed: true)
               end
        cache_pdf = File.join(Common.cover_cache_dir, "#{side}cover_#{theme}_#{trim.name}_cmyk.pdf")
        generate_pdfx_single(source, cache_pdf, trim, bleed_mm:, crop_marks: true, fill:, crop:)
        publish_print_cover!(side, cache_pdf)
      end

      # 閲覧用の PDF（RGB・仕上がりサイズ）
      # @param crop [Boolean] 比の違う画像を引き伸ばさずに中央で切るか（crop_to_fit?）
      def generate_rgb_pdf_single(input_png, output_pdf, trim, crop: false)
        return unless File.exist?(input_png)

        convert_cmd = imagemagick_convert_command
        unless convert_cmd
          Common.log_error 'ImageMagick（magick/convert）が見つかりません'
          return
        end

        Common.log_info "  生成中: #{File.basename(output_pdf)}"
        cmd = convert_cmd + [
          input_png,
          *fit_args(trim.width, trim.height, crop:),
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
      # 塗り足し込みの著者画像 `<base>_bleed.png`（例 frontcover_master_bleed.png。.jpg・.jpeg・.webp も可）があれば
      # 最優先で採用する（実画が塗り足しまで届くのでトリム画像との絵柄差が出ない）。無ければ
      # `output.print_pdf.cover_bleed` 設定で分岐する:
      #   scale（既定）= トリム画像を塗り足しまで拡大して流用（中央拡大・端裁断を許容）
      #   keep         = 拡大しない（塗り足し帯は白。フチが端まで無いデザイン向け）
      #
      # @param image [String] 仕上がりサイズの元の画像
      # @param cover_bleed [String] 'scale' | 'keep'
      # @return [Array(String, Symbol)] [入力画像, 充填モード（:bleed=塗り足し込み / :trim=仕上がりのみ）]
      def resolve_print_cover_input(image, cover_bleed)
        # 元の画像と塗り足し込みの画像は、形式が違ってもよい（frontcover_master.png と frontcover_master_bleed.jpg）
        bleed_image = Common.cover_raster_path("#{File.basename(image, '.*')}_bleed", dir: File.dirname(image))
        if bleed_image
          Common.log_info "  塗り足し込み画像を使用: #{File.basename(bleed_image)}"
          return [bleed_image, :bleed]
        end

        cover_bleed == 'keep' ? [image, :trim] : [image, :bleed]
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
      # @param trim       [TrimSize] 仕上がりの寸法（trim_size）
      # @param bleed_mm   [Float]   塗り足し幅（mm）
      # @param crop_marks [Boolean] トンボを付与するか
      # @param fill       [Symbol]  充填モード（:bleed=塗り足し込み / :trim=仕上がりのみ）
      # @param crop       [Boolean] 比の違う画像を引き伸ばさずに中央で切るか（crop_to_fit?）
      def generate_pdfx_single(input_png, output_pdf, trim, bleed_mm:, crop_marks: false, fill: :bleed, crop: false)
        return unless File.exist?(input_png)

        convert_cmd = imagemagick_convert_command
        unless convert_cmd
          Common.log_error 'ImageMagick（magick/convert）が見つかりません'
          return
        end

        Common.log_info "  生成中: #{File.basename(output_pdf)}"

        trim_w_px = trim.width
        trim_h_px = trim.height
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
              *fit_args(content_w_px, content_h_px, crop:),
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
            *fit_args(bleed_w_px, bleed_h_px, crop:),
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
      # 縦長の判型は、縦 2,560 px に縮めて中央の横 1,600 px を切り出す。横長・正方形の判型は、
      # 判型の比のまま横 2,560 px にする（cover-size-independence-spec.md §3.3）。色を sRGB に直して
      # 品質 95 で書き、KDP へ上げる成果品としてプロジェクトの直下へも写す。
      #
      # @param source [String] 元の画像（PNG）
      # @param output [String] 書き出す JPEG（生成キャッシュ側。EPUB へ入れる元）
      # @param trim [TrimSize, nil] 本の判型（nil は縦長として扱う）
      # @return [Boolean] 書けたか
      def write_ebook_cover!(source, output, trim: nil)
        convert_cmd = imagemagick_convert_command
        unless convert_cmd
          Common.log_error 'ImageMagick（magick/convert）が見つかりません'
          return false
        end

        geometry = if trim.nil? || trim.height_mm > trim.width_mm
                     ['-resize', "x#{EPUB_SIZE[:height]}", '-gravity', 'center',
                      '-crop', "#{EPUB_SIZE[:width]}x#{EPUB_SIZE[:height]}+0+0", '+repage']
                   else
                     long = EPUB_SIZE[:height]
                     fit_args(long, (long * trim.height_mm / trim.width_mm.to_f).round, crop: true)
                   end
        Common.log_info "  生成中: #{File.basename(output)}"
        # 透明な所は白で塗る（JPEG は透明を持てず、塗らないと黒になる。PDF の表紙では紙の白に見える所）
        cmd = convert_cmd + [
          source, *srgb_profile_args,
          '-background', 'white', '-alpha', 'remove', '-alpha', 'off',
          *geometry,
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
