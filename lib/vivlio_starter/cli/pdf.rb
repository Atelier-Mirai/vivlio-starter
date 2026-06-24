# frozen_string_literal: true

require 'English'

require 'rbconfig'
require 'fileutils'

require_relative 'entries'
require_relative 'pdf/pdf_to_jpeg'
require_relative 'pdf/jpeg_to_pdf'

module VivlioStarter
  module CLI
    # ================================================================
    # Module: PDF 生成・圧縮・表示ロジック
    # ================================================================
    # 提供機能:
    #   - execute_pdf: Vivliostyle CLI による PDF 生成
    #   - execute_pdf_compress: Ghostscript による PDF 圧縮
    #   - execute_open_pdf: macOS Preview.app で PDF を開く
    #
    # Samovar CLI コマンドから純粋な Hash オプションを受け取る。
    # ================================================================
    module PdfCommands
      module_function

      # PDF 生成を実行する
      #
      # @param options [Hash] オプション
      #   - :verbose [Boolean] 詳細ログ出力
      # @param target_output [String, nil] 出力ファイル名（リネーム先）
      # @return [void]
      def execute_pdf(options, target_output = nil)
        PdfCommandRunner.new(options, target_output).call
      end

      # PDF 圧縮を実行する
      #
      # @param options [Hash] オプション
      #   - :verbose [Boolean] 詳細ログ出力
      # @param input [String, nil] 入力PDFパス
      # @param output [String, nil] 出力PDFパス
      # @return [void]
      def execute_pdf_compress(options, input = nil, output = nil)
        PdfCompressor.new(options, input, output).call
      end

      # PDF をページ単位の JPEG に切り出す
      #
      # @param options [Hash] :dpi, :quality, :pages, :output, :verbose
      # @param input [String, nil] 入力 PDF パス
      # @return [Hash] 生成結果
      def execute_pdf_pages(options, input = nil)
        PdfPagesExporter.new(options, input).call
      end

      # PDF を JPEG 化して再結合し、Type3 フォントを含まないラスタライズ PDF を生成する
      #
      # @param options [Hash] :dpi, :quality, :clean, :verbose
      # @param input [String, nil] 入力 PDF パス
      # @return [Hash] 生成結果
      def execute_pdf_rasterize(options, input = nil)
        PdfRasterizer.new(options, input).call
      end

      # PDF を Preview.app で開く
      #
      # @param options [Hash] オプション
      #   - :verbose [Boolean] 詳細ログ出力
      # @param path [String, nil] 開くPDFパス
      # @return [void]
      def execute_open_pdf(options, path = nil)
        PdfOpener.new(options, path).call
      end

      # 入稿用 PDF を生成する（--crop-marks --bleed 付き）
      #
      # @param options [Hash] オプション
      # @param target_output [String, nil] 出力ファイル名
      # @return [void]
      def execute_print_pdf(options, target_output = nil)
        PrintPdfCommandRunner.new(options, target_output).call
      end

      # npx vivliostyle build をラップして PDF を生成する
      class PdfCommandRunner
        def initialize(options, target_output)
          @options = options || {}
          @target_output = target_output
          @config = Common::CONFIG['pdf'] || {}
          @build_success = false
        end

        def call
          apply_verbose
          Common.log_action('PDFを生成しています…')
          execute_build
          handle_build_result
          build_succeeded?
        end

        # vivliostyle build が成功し、期待する出力ファイルまで生成できたかを返す。
        # 入稿用本文のような最重量レンダリングは Chrome の一過性失敗で空振りする
        # ことがあり、その際 system は非ゼロを返すか出力が生成されない。呼び出し側
        # （パイプライン）がリトライ・中断を判断できるよう、真の成否を返す。
        def build_succeeded?
          return false unless @build_success

          File.exist?(rename_requested? ? target_output : output_path)
        end

        private

        attr_reader :options, :target_output, :config

        def apply_verbose
          ENV['VERBOSE'] = '1' if options[:verbose]
        end

        # Vivliostyle CLI を実行して PDF を生成する
        def execute_build
          ensure_entries_file!
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          @build_success = if quiet_mode?
                             system(build_command, out: File::NULL, err: File::NULL)
                           else
                             system(build_command)
                           end

          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
          Common.log_info(format('[pdf] vivliostyle build 所要時間: %.2fs', elapsed))
          Common.record_vivliostyle_build(elapsed, Common.current_step_label)
        end

        def ensure_entries_file!
          return if File.exist?(entries_file_path)

          Common.log_info('[pdf] entries.js が存在しないため全HTMLから再生成します')
          EntriesCommands.execute_entries({}, [])

          return if File.exist?(entries_file_path)

          raise 'entries.js の再生成に失敗しました'
        rescue StandardError => e
          raise unless e.is_a?(RuntimeError) && e.message == 'entries.js の再生成に失敗しました'

          Common.log_error('[pdf] entries.js の自動生成に失敗したためビルドを中止します')
          raise
        end

        def entries_file_path
          File.join(Dir.pwd, 'entries.js')
        end

        # quiet モードが有効かどうか返す
        def quiet_mode?
          @quiet_mode ||= (ENV['VIVLIO_QUIET'] == '1') || Common.truthy?(vivliostyle_config['quiet'])
        end

        # vivliostyle 設定を返す
        def vivliostyle_config
          @vivliostyle_config ||= Common::CONFIG['vivliostyle'] || {}
        end

        # 実行するビルドコマンド文字列を組み立てる
        def build_command
          cmd = 'npx vivliostyle build'
          cmd += ' -d' if SingleDocDecider.new(config).call
          cmd
        end

        # ビルド結果に応じてログを出す
        def handle_build_result
          if @build_success
            handle_successful_build
          else
            Common.log_error('PDFの生成に失敗しました')
          end
        end

        # 成功時の出力ファイル処理を行う
        def handle_successful_build
          return finalize_default_output unless rename_requested?

          rename_output_file
        end

        # リネーム指定があるかどうか返す
        def rename_requested?
          target_output && !target_output.to_s.strip.empty?
        end

        # 出力ファイルのパスを返す
        def output_path
          config['output_file'] || 'output.pdf'
        end

        # 出力先の絶対パスをログ出力する
        def log_output_location(path)
          Common.log_info("出力先: #{File.expand_path(path)}")
        end

        # 生成された PDF をターゲットにリネームする
        def rename_output_file
          unless File.exist?(output_path)
            Common.log_warn("PDF生成は成功しましたが、出力ファイルが見つかりません: #{output_path}")
            return
          end

          return finalize_default_output if same_target_path?

          perform_rename
        end

        # 出力先をそのまま利用する際の後処理
        def finalize_default_output
          Common.log_success('PDFの生成が完了しました')
          log_output_location(output_path)
        end

        # 出力先とターゲットが同一パスか判定する
        def same_target_path?
          File.expand_path(output_path) == File.expand_path(target_output)
        end

        # 出力 PDF をターゲットへ移動する
        def perform_rename
          FileUtils.rm_f(target_output)
          FileUtils.mv(output_path, target_output)
          Common.log_success("PDFの生成が完了しました（リネーム: #{output_path} → #{target_output}）")
          log_output_location(target_output)
        rescue StandardError => e
          Common.log_warn("PDFのリネームに失敗しました: #{e}")
        end
      end

      # --single-doc オプションの有効化可否を判定する
      class SingleDocDecider
        def initialize(config)
          @config = config
        end

        # single-doc を有効化すべきかどうか返す
        def call
          return false unless requested?
          return false unless config_allows_single_doc?
          return false unless entries_js_allows_single_doc?

          true
        rescue StandardError => e
          Common.log_warn("[pdf] --single-doc 判定に失敗: #{e}。安全側で無効化します")
          false
        end

        private

        attr_reader :config

        # single_doc 設定が要求されているか
        def requested?
          (ENV['VIVLIO_SINGLE_DOC'] == '1') || Common.truthy?(config['single_doc'])
        end

        # vivliostyle.config.js が entries.js を参照していないか
        def config_allows_single_doc?
          path = root_join('vivliostyle.config.js')
          return true unless File.exist?(path)

          text = File.read(path, encoding: 'utf-8')
          return true unless text.match?(/entries\.(js|mjs)\b/)

          Common.log_info('[pdf] vivliostyle.config.js が entries.js を参照しているため --single-doc を無効化します')
          false
        rescue StandardError
          true
        end

        # entries.js のエントリ数が 1 件か判定する
        def entries_js_allows_single_doc?
          path = root_join('entries.js')
          unless File.exist?(path)
            Common.log_info('[pdf] entries.js が見つからないため --single-doc は無効化します')
            return false
          end

          text = File.read(path, encoding: 'utf-8')
          paths = text.scan(/"path"\s*:/)
          return true if paths.size == 1

          Common.log_info("[pdf] entries.js に複数エントリ(#{paths.size})があるため --single-doc は無効化します")
          false
        end

        # プロジェクトルート配下のファイルパスを返す
        def root_join(name)
          File.join(Dir.pwd, name)
        end
      end

      # Ghostscript を利用して PDF を圧縮する
      #
      # 動作モード（options[:pipeline]）:
      #   - false（既定）: vs pdf:compress の単体実行。利用者の明示要求のため、
      #     gs 不在・圧縮失敗は 🔴 エラー + exit 1 で報告する
      #   - true: vs build の Step 12 から呼ばれる。PDF は生成済みのため、
      #     gs 不在・圧縮失敗でもビルドを止めず 🟡 でスキップを案内して続行する
      class PdfCompressor
        def initialize(options, cli_input = nil, cli_output = nil)
          @options = options || {}
          @config = Common::CONFIG['pdf'] || {}
          @cli_input = cli_input
          @cli_output = cli_output
          @input_pdf = nil
          @output_pdf = nil
          @compression_success = false
          @skipped = false
        end

        def call
          apply_verbose
          determine_paths
          ensure_input_exists
          Common.log_action("PDFを圧縮しています…（入力: #{input_pdf} → 出力: #{output_pdf}）")
          compress_pdf
          report_result
        end

        private

        attr_reader :options, :config, :cli_input, :cli_output, :input_pdf, :output_pdf, :compression_success

        # ビルドパイプライン（Step 12）から呼ばれているか
        def pipeline_mode? = !!options[:pipeline]

        def apply_verbose
          ENV['VERBOSE'] = '1' if options[:verbose]
        end

        # 入出力ファイルのパスを決定する
        def determine_paths
          input = normalize_pdf_extension(cli_input)
          output = normalize_pdf_extension(cli_output)

          if input && output
            # vs pdf:compress input.pdf output.pdf
            @input_pdf  = input
            @output_pdf = output
          elsif input
            # vs pdf:compress filename（出力は _compressed を付与）
            @input_pdf  = input
            @output_pdf = default_compressed_name(input)
          else
            # vs pdf:compress（引数なし）
            @input_pdf  = config['output_file'] || 'output.pdf'
            @output_pdf = config['output_file_compressed'] || default_compressed_name(@input_pdf)
          end
        end

        # 拡張子 .pdf が省略されていれば補完する
        def normalize_pdf_extension(path)
          return nil if path.nil? || path.to_s.strip.empty?

          p = path.to_s.strip
          p.end_with?('.pdf') ? p : "#{p}.pdf"
        end

        # 入力ファイル名からデフォルトの圧縮後ファイル名を生成する
        # 例: "output.pdf" -> "output_compressed.pdf"
        def default_compressed_name(path)
          base = File.basename(path)
          dir  = File.dirname(path)

          if base.downcase.end_with?('.pdf')
            stem = base[0...-4]
            File.join(dir, "#{stem}_compressed.pdf")
          else
            File.join(dir, "#{base}_compressed.pdf")
          end
        end

        # 入力 PDF の存在を確認する
        def ensure_input_exists
          return if File.exist?(input_pdf)

          Common.log_error("エラー: 入力PDFが見つかりません: #{input_pdf}")
          exit(1)
        end

        # Ghostscript を実行して PDF を圧縮する。
        # gs 不在時の挙動はモードで分ける（クラスコメント参照。DG-03 で検出された
        # 「スキップしますと警告しつつ exit(1) でビルドごと落ちる」矛盾の解消）
        def compress_pdf
          if ghostscript_available?
            @compression_success = run_ghostscript
          elsif pipeline_mode?
            Common.log_warn('Ghostscript(gs) が見つかりません。圧縮をスキップし、未圧縮のPDFで続行します。',
                            detail: '圧縮を有効にするには vs doctor --fix で Ghostscript を導入してください')
            @skipped = true
          else
            Common.log_error('Ghostscript(gs) が見つかりません。',
                             detail: 'vs doctor --fix で導入できます')
            exit(1)
          end
        end

        # Ghostscript コマンドが利用可能かを判定する
        def ghostscript_available?
          system('which gs >/dev/null 2>&1')
        end

        # Ghostscript を起動し圧縮処理を行う
        def run_ghostscript
          cmd = [
            'gs', '-sDEVICE=pdfwrite', '-dCompatibilityLevel=1.7',
            '-dPDFSETTINGS=/ebook', '-dFastWebView=true', '-dDetectDuplicateImages=true',
            '-dNOPAUSE', '-dQUIET', '-dBATCH',
            "-sOutputFile=#{output_pdf}", input_pdf
          ]
          system(*cmd, out: File::NULL, err: File::NULL)
        end

        # 圧縮結果に応じてログを出す（スキップ時は compress_pdf 側で案内済み）
        def report_result
          return if @skipped

          if compression_success && File.exist?(output_pdf)
            Common.log_success("圧縮したPDFを出力しました: #{File.expand_path(output_pdf)}")
          elsif pipeline_mode?
            # ビルド経路では PDF 生成済みのため、圧縮失敗でビルドを失敗させない
            Common.log_warn('PDFの圧縮に失敗しました。未圧縮のPDFで続行します。')
          else
            Common.log_error('PDFの圧縮に失敗しました')
            exit(1)
          end
        end
      end

      # PDF をページごとの JPEG に切り出す
      class PdfPagesExporter
        def initialize(options, cli_input = nil, pdf_to_jpeg: ::VivlioStarter::Pdf::PdfToJpeg)
          @options = options || {}
          @cli_input = cli_input
          @pdf_to_jpeg = pdf_to_jpeg
        end

        def call
          apply_verbose
          pdf_path = resolve_pdf_path
          ensure_input_exists!(pdf_path)
          ensure_pdf_pages_tools!

          output_dir = output_dir_for(pdf_path)
          Common.log_action("PDFをJPEG画像に切り出しています…（入力: #{pdf_path} → 出力: #{output_dir}/）")

          images = pdf_to_jpeg.convert(
            pdf_path,
            output_dir:,
            dpi: normalized_dpi,
            quality: normalized_quality,
            pages: options[:pages]
          )

          Common.log_success("完了: #{images.size} ページ → #{output_dir}/")
          { pdf_path:, output_dir:, images: }
        end

        private

        attr_reader :options, :cli_input, :pdf_to_jpeg

        def apply_verbose
          ENV['VERBOSE'] = '1' if options[:verbose]
        end

        def resolve_pdf_path
          explicit = normalize_pdf_extension(cli_input)
          return explicit if explicit

          Common.generate_output_filename('pdf')
        end

        def normalize_pdf_extension(path)
          return nil if path.nil? || path.to_s.strip.empty?

          p = path.to_s.strip
          p.downcase.end_with?('.pdf') ? p : "#{p}.pdf"
        end

        def ensure_input_exists!(pdf_path)
          return if File.exist?(pdf_path)

          raise "入力PDFが見つかりません: #{pdf_path}"
        end

        def ensure_pdf_pages_tools!
          Common.ensure_external_command!('pdftoppm', purpose: 'PDFページ画像化')
        end

        def output_dir_for(pdf_path)
          explicit = options[:output].to_s.strip
          return explicit unless explicit.empty?

          "#{File.basename(pdf_path, '.*')}_images"
        end

        def normalized_dpi
          (options[:dpi] || 350).to_i
        end

        def normalized_quality
          (options[:quality] || 95).to_i
        end
      end

      # PDF 全ページを JPEG 経由でラスタライズして再結合する
      class PdfRasterizer
        def initialize(options, cli_input = nil,
                       pdf_to_jpeg: ::VivlioStarter::Pdf::PdfToJpeg,
                       jpeg_to_pdf: ::VivlioStarter::Pdf::JpegToPdf)
          @options = options || {}
          @cli_input = cli_input
          @pdf_to_jpeg = pdf_to_jpeg
          @jpeg_to_pdf = jpeg_to_pdf
        end

        def call
          apply_verbose
          pdf_path = resolve_pdf_path
          ensure_input_exists!(pdf_path)
          ensure_pdf_rasterize_tools!

          base = File.basename(pdf_path, '.*')
          work_dir = "#{base}_images"
          output_pdf = "#{base}_rasterized.pdf"

          Common.log_action("--- Phase 1: PDF → JPEG (#{normalized_dpi}dpi / quality #{normalized_quality}) ---")
          images = pdf_to_jpeg.convert(pdf_path, output_dir: work_dir, dpi: normalized_dpi, quality: normalized_quality)
          Common.log_info("#{images.size} ページを生成しました")

          Common.log_action('--- Phase 2: JPEG → PDF ---')
          jpeg_to_pdf.convert(images, output_pdf)

          Common.log_success("完了: #{output_pdf} (#{output_size_mb(output_pdf)} MB)")
          cleanup_work_dir_if_needed(work_dir)

          { pdf_path:, work_dir:, output_pdf:, images: }
        end

        private

        attr_reader :options, :cli_input, :pdf_to_jpeg, :jpeg_to_pdf

        def apply_verbose
          ENV['VERBOSE'] = '1' if options[:verbose]
        end

        def resolve_pdf_path
          explicit = normalize_pdf_extension(cli_input)
          return explicit if explicit

          Common.generate_output_filename('pdf')
        end

        def normalize_pdf_extension(path)
          return nil if path.nil? || path.to_s.strip.empty?

          p = path.to_s.strip
          p.downcase.end_with?('.pdf') ? p : "#{p}.pdf"
        end

        def ensure_input_exists!(pdf_path)
          return if File.exist?(pdf_path)

          raise "入力PDFが見つかりません: #{pdf_path}"
        end

        # PDFラスタライズ用の外部ツール存在チェック
        # ※ JPEGからPDFへの再結合に独自実装 JpegToPdf を使用するため、img2pdfのチェックを削除しました。
        def ensure_pdf_rasterize_tools!
          Common.ensure_external_command!('pdftoppm', purpose: 'PDFラスタライズ')
        end

        def normalized_dpi
          (options[:dpi] || 350).to_i
        end

        def normalized_quality
          (options[:quality] || 95).to_i
        end

        def output_size_mb(output_pdf)
          return 0.0 unless File.exist?(output_pdf)

          (File.size(output_pdf) / 1024.0 / 1024.0).round(1)
        end

        def cleanup_work_dir_if_needed(work_dir)
          if options[:clean]
            FileUtils.rm_rf(work_dir)
            Common.log_info("中間ファイルを削除しました: #{work_dir}")
          else
            Common.log_info("中間ファイルを保存しました: #{work_dir}/")
          end
        end
      end

      # macOS の Preview.app で PDF を開く
      class PdfOpener
        def initialize(options, path)
          @options = options || {}
          @explicit_path = path
          @pdf_config = Common::CONFIG['pdf'] || {}
          @pdf_preview_config = Common::CONFIG.dig('output', 'pdf_preview') || {}
        end

        def call
          apply_verbose
          pdf_path = resolve_pdf_path
          Common.log_action('PDFを開いています…')
          Common.log_info("ファイルパス: #{File.expand_path(pdf_path)}")

          unless macos?
            inform_unsupported_platform
            return
          end

          ensure_pdf_exists(pdf_path)
          close_existing_windows_if_needed
          open_pdf(pdf_path)
          position_window
          Common.log_success('PDFを開きました')
        end

        private

        attr_reader :options, :explicit_path, :pdf_config, :pdf_preview_config

        def apply_verbose
          ENV['VERBOSE'] = '1' if options[:verbose]
        end

        # 開くべき PDF ファイルのパスを決定する
        def resolve_pdf_path
          return select_preferred_pdf if explicit_path.nil? || explicit_path.to_s.strip.empty?

          resolve_explicit_path(explicit_path.to_s.strip)
        end

        # 明示指定されたファイル名からパスを解決する
        #
        # 探索順:
        #   1. プロジェクトルート直下（拡張子あり/なし）
        #   2. sources/ ディレクトリ配下（拡張子あり/なし）
        def resolve_explicit_path(name)
          # 拡張子を正規化（.pdf がなければ付与）
          with_ext = name.end_with?('.pdf') ? name : "#{name}.pdf"
          without_ext = name.end_with?('.pdf') ? name[0...-4] : name

          candidates = [
            with_ext,
            File.join('sources', with_ext),
            File.join('sources', "#{without_ext}.pdf")
          ].uniq

          found = candidates.find { |p| File.exist?(p) }
          return found if found

          # 見つからなければそのまま渡す（ensure_pdf_exists でエラーになる）
          Common.log_warn("open: 指定されたPDFが見つかりません: #{with_ext}")
          with_ext
        end

        # 既定の PDF を選択する
        def select_preferred_pdf
          # 動的ファイル名を優先、次に固定ファイル名、最後にconfig設定
          compressed_dynamic = Common.generate_compressed_pdf_filename('pdf')
          normal_dynamic = Common.generate_output_filename('pdf')
          compressed_fixed = 'output_compressed.pdf'
          normal_fixed = 'output.pdf'
          compressed_config = pdf_config['output_file_compressed']
          normal_config = pdf_config['output_file']

          # 存在するファイルを優先度順に探す
          compressed = find_existing_file([compressed_dynamic, compressed_fixed, compressed_config].compact)
          normal = find_existing_file([normal_dynamic, normal_fixed, normal_config].compact)

          if compressed && normal
            choose_by_timestamp(compressed, normal)
          elsif compressed
            Common.log_info('open: 圧縮版のみ存在するためこちらを開きます')
            compressed
          elsif normal
            Common.log_info('open: 通常版を開きます')
            normal
          else
            # どちらも見つからない場合はデフォルト
            Common.log_warn('open: PDFファイルが見つかりません')
            normal_dynamic
          end
        end

        # ファイルリストから最初に存在するファイルを返す
        def find_existing_file(paths)
          paths.find { |path| File.exist?(path) }
        end

        # 圧縮版と通常版の更新日時から優先度を決める
        def choose_by_timestamp(compressed, normal)
          c_mtime = safe_mtime(compressed)
          n_mtime = safe_mtime(normal)
          if c_mtime >= n_mtime
            Common.log_info("open: 圧縮版(#{compressed})が新しいためこちらを開きます")
            compressed
          else
            Common.log_info("open: 通常版(#{normal})が新しいためこちらを開きます")
            normal
          end
        rescue StandardError
          compressed
        end

        # mtime 取得に失敗した場合のフォールバックを提供する
        def safe_mtime(path)
          File.mtime(path)
        rescue StandardError
          Time.at(0)
        end

        # macOS 以外であることを案内する
        def inform_unsupported_platform
          Common.log_info('この環境では自動オープンは未対応です（macOS専用機能）。PDFは手動で開いてください。')
        end

        # 指定された PDF の存在を確認する
        def ensure_pdf_exists(path)
          return if File.exist?(path)

          Common.log_error("エラー: PDFファイルが見つかりません: #{path}")
          exit(1)
        end

        # macOS かどうか判定する
        def macos?
          RbConfig::CONFIG['host_os'] =~ /darwin|mac os/i
        end

        # 既存の Preview ウィンドウを閉じる
        def close_existing_windows_if_needed
          return unless close_existing_windows?

          begin
            system('osascript', '-e', 'tell application "Preview" to close every window')
          rescue StandardError
            # 失敗しても処理続行
          end
        end

        # Preview.app で PDF を開く
        def open_pdf(path)
          system("open -a Preview \"#{path}\"")
        end

        # Preview ウィンドウを設定された位置に移動する
        def position_window
          bounds = resolved_window_bounds
          system <<~APPLE_SCRIPT
            osascript -e '
              tell application "Preview"
                activate
                set bounds of front window to #{bounds}
              end tell'
          APPLE_SCRIPT
        end

        def close_existing_windows?
          if pdf_preview_config.key?('close_existing_windows')
            Common.fetch_bool({ 'flag' => pdf_preview_config['close_existing_windows'] }, %w[flag], default: true)
          else
            Common.fetch_bool({ 'flag' => pdf_config['close_existing_windows'] }, %w[flag], default: true)
          end
        rescue StandardError
          true
        end

        def resolved_window_bounds
          bounds = pdf_preview_config['window_bounds']
          bounds = pdf_config['window_bounds'] if bounds.nil? || bounds.to_s.strip.empty?
          bounds = '{3072, 0, 4096, 2160}' if bounds.to_s.strip.empty?
          bounds
        end
      end

      # 入稿用 PDF（トンボ・塗り足し付き）を生成する
      # PdfCommandRunner を継承し、build_command のみ差し替える
      class PrintPdfCommandRunner < PdfCommandRunner
        private

        # トンボ・塗り足しオプションを付加したビルドコマンドを組み立てる
        # book.yml の output.print_pdf.bleed / crop_marks を参照
        def build_command
          cmd = 'npx vivliostyle build'
          cmd += ' -d' if SingleDocDecider.new(config).call

          print_cfg = Common::CONFIG.dig(:output, :print_pdf)
          return cmd unless print_cfg

          bleed = print_cfg[:bleed]&.to_s || '3mm'

          if print_cfg[:crop_marks] != false
            cmd += ' --crop-marks'
            cmd += " --bleed #{bleed}"
          end

          cmd
        end
      end
    end
  end
end
