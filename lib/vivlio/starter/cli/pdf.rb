# frozen_string_literal: true

require 'English'

require 'rbconfig'
require 'fileutils'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: Thor コマンド群: pdf 関連
      # ------------------------------------------------
      # - 目的: Vivliostyle CLI を用いた PDF 生成と周辺ユーティリティ
      # - 提供コマンド: pdf, pdf_compress, open:pdf
      # - 主な処理: PDFビルド、圧縮（Ghostscript）、Previewでの表示
      # - 関連: 共通処理は `lib/vivlio/starter/cli/common.rb`
      # ================================================================
      module PdfCommands

        PDF_DESC = {
          pdf: {
            short: 'PDFを生成します（OUTPUT 指定時はそのファイル名で出力）',
            long: <<~DESC
              PDFファイルを生成します。

              Vivliostyle CLIを使用してHTMLファイルからPDFを生成します。
              出力ファイル名は vivliostyle.config.js の設定に従います。
              引数 OUTPUT を指定した場合、生成後に設定上の出力ファイル（例: output.pdf）を
              OUTPUT へとリネームします（既存ファイルがあれば上書き）。
            DESC
          },
          compress: {
            short: '生成済みPDFを圧縮します (Ghostscript)',
            long: <<~DESC
              生成済みのPDFファイルを Ghostscript(pdfwrite) を用いて圧縮します。

              既定の品質プリセットは /ebook（中庸）です。

              オプション:
                -v, --verbose  詳細な処理情報を表示
            DESC
          },
          open: {
            short: '生成されたPDFを開きます（PATH 指定可）',
            long: <<~DESC
              生成されたPDFファイルをPreview.appで開きます。

              設定に応じて：
              - 圧縮版PDFが存在すれば優先的に開く
              - 既存のPDFウィンドウを閉じる
              - 指定されたウィンドウ位置に配置

              PATH を与えた場合はそのファイルを開き、同様にウィンドウ位置を適用します。
            DESC
          }
        }.freeze

        def self.included(base)
          base.class_eval do
            desc 'pdf [OUTPUT]', PdfCommands::PDF_DESC[:pdf][:short]
            long_desc PdfCommands::PDF_DESC[:pdf][:long]
            # PDF ビルドコマンドのエントリポイント
            define_method(:pdf) do |target_output = nil|
              PdfCommands::PdfCommandRunner.new(self, target_output).call
            end

            desc 'pdf_compress', PdfCommands::PDF_DESC[:compress][:short]
            long_desc PdfCommands::PDF_DESC[:compress][:long]
            # PDF 圧縮コマンドのエントリポイント
            define_method(:pdf_compress) do
              PdfCommands::PdfCompressor.new(self).call
            end

            desc 'open:pdf [PATH]', PdfCommands::PDF_DESC[:open][:short]
            long_desc PdfCommands::PDF_DESC[:open][:long]
            # PDF を開くコマンドのエントリポイント
            define_method(:open_pdf) do |path = nil|
              PdfCommands::PdfOpener.new(self, path).call
            end

            # コマンドエイリアス定義
            map 'pdf:compress' => :pdf_compress
          end
        end

        # npx vivliostyle build をラップして PDF を生成する
        class PdfCommandRunner
          def initialize(command, target_output)
            @command = command
            @target_output = target_output
            @config = Common::CONFIG['pdf'] || {}
            @build_success = false
          end

          # PDF 生成処理を実行する
          def call
            apply_verbose_option
            Common.log_action('PDFを生成しています…')
            execute_build
            handle_build_result
          end

          private

          attr_reader :command, :target_output, :config

          # Thor の options を取得する
          def options
            command.respond_to?(:options) ? command.options || {} : {}
          end

          # --verbose 指定時に環境変数を設定する
          def apply_verbose_option
            ENV['VERBOSE'] = '1' if options[:verbose]
          end

          # Vivliostyle CLI を実行して PDF を生成する
          def execute_build
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

          # quiet モードが有効かどうか返す
          def quiet_mode?
            @quiet_mode ||= (ENV['VIVLIO_QUIET'] == '1') || Common.truthy?(config['quiet'])
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
        class PdfCompressor
          def initialize(command)
            @command = command
            @config = Common::CONFIG['pdf'] || {}
            @input_pdf = nil
            @output_pdf = nil
            @compression_success = false
          end

          # PDF 圧縮処理を実行する
          def call
            apply_verbose_option
            determine_paths
            ensure_input_exists
            Common.log_action("PDFを圧縮しています…（入力: #{input_pdf} → 出力: #{output_pdf}）")
            compress_pdf
            report_result
          end

          private

          attr_reader :command, :config, :input_pdf, :output_pdf, :compression_success

          # Thor の options を取得する
          def options
            command.respond_to?(:options) ? command.options || {} : {}
          end

          # --verbose 指定時に環境変数を設定する
          def apply_verbose_option
            ENV['VERBOSE'] = '1' if options[:verbose]
          end

          # 入出力ファイルのパスを決定する
          def determine_paths
            @input_pdf  = config['output_file'] || 'output.pdf'
            @output_pdf = config['output_file_compressed'] || 'output_compressed.pdf'
          end

          # 入力 PDF の存在を確認する
          def ensure_input_exists
            return if File.exist?(input_pdf)

            Common.log_error("エラー: 入力PDFが見つかりません: #{input_pdf}")
            exit(1)
          end

          # Ghostscript を実行して PDF を圧縮する
          def compress_pdf
            if ghostscript_available?
              @compression_success = run_ghostscript
            else
              Common.log_warn('Ghostscript(gs) が見つかりません。圧縮をスキップします。')
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

          # 圧縮結果に応じてログを出す
          def report_result
            if compression_success && File.exist?(output_pdf)
              Common.log_success("圧縮したPDFを出力しました: #{File.expand_path(output_pdf)}")
            else
              Common.log_error('PDFの圧縮に失敗しました')
              exit(1)
            end
          end
        end

        # macOS の Preview.app で PDF を開く
        class PdfOpener
          def initialize(command, path)
            @command = command
            @explicit_path = path
            @config = Common::CONFIG['pdf'] || {}
          end

          # PDF を開く処理を実行する
          def call
            apply_verbose_option
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

          attr_reader :command, :explicit_path, :config

          # Thor の options を取得する
          def options
            command.respond_to?(:options) ? command.options || {} : {}
          end

          # --verbose 指定時に環境変数を設定する
          def apply_verbose_option
            ENV['VERBOSE'] = '1' if options[:verbose]
          end

          # 開くべき PDF ファイルのパスを決定する
          def resolve_pdf_path
            return explicit_path.to_s unless explicit_path.nil? || explicit_path.to_s.strip.empty?

            select_preferred_pdf
          end

          # 既定の PDF を選択する
          def select_preferred_pdf
            compressed = config['output_file_compressed'] || 'output_compressed.pdf'
            normal = config['output_file'] || 'output.pdf'

            if File.exist?(compressed) && File.exist?(normal)
              choose_by_timestamp(compressed, normal)
            elsif File.exist?(compressed)
              Common.log_info('open: 圧縮版のみ存在するためこちらを開きます')
              compressed
            else
              Common.log_info('open: 通常版を開きます')
              normal
            end
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
            return unless Common.fetch_bool({ 'flag' => config['close_existing_windows'] }, %w[flag], default: true)

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
            bounds = config['window_bounds'] || '{3072, 0, 4096, 2160}'
            system <<~APPLE_SCRIPT
              osascript -e '
                tell application "Preview"
                  activate
                  set bounds of front window to #{bounds}
                end tell'
            APPLE_SCRIPT
          end
        end
      end
    end
  end
end
