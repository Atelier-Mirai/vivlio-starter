# frozen_string_literal: true
require 'rbconfig'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: Thor コマンド群: pdf / vivliostyle 関連
      # ------------------------------------------------
      # - 目的: Vivliostyle CLI を用いた PDF 生成と周辺ユーティリティ
      # - 提供コマンド: pdf, pdf_compress, open:pdf, config
      # - 主な処理: PDFビルド、圧縮（qpdf/gs）、Previewでの表示、設定JS生成
      # - 関連: 共通処理は `lib/vivlio/starter/cli/common.rb`
      # ================================================================
      module PdfCommands
        extend self
        def included(base)
          base.class_eval do
            desc 'pdf', 'PDFを生成します'
            long_desc <<~DESC
              PDFファイルを生成します。

              Vivliostyle CLIを使用してHTMLファイルからPDFを生成します。
              出力ファイル名は vivliostyle.config.js の設定に従います。
            DESC
            # ================================================================
            # Command: pdf（VivliostyleでPDF生成）
            # ------------------------------------------------
            # - 概要: Vivliostyle CLI で HTML→PDF をビルド
            # - 入力: vivliostyle.config.js の entry 設定に基づく HTML 群
            # - 出力: 設定ファイルの output に指定された PDF
            # - オプション: --verbose（ENV['VIVLIO_QUIET']=1 で出力抑制）
            # ================================================================
            def pdf
              ENV['VERBOSE'] = '1' if options[:verbose]
              Common.log_action("PDFを生成しています…")

              # 出力抑制フラグ（ENV または config.yml の pdf.quiet）
              pdf_config = Common::CONFIG['pdf'] || {}
              quiet = (ENV['VIVLIO_QUIET'] == '1') || (pdf_config['quiet'] == true)

              # コマンドを実行（quiet の場合は /dev/null へ）
              cmd = 'npx vivliostyle build'
              if quiet
                system(cmd, out: File::NULL, err: File::NULL)
              else
                system(cmd)
              end

              if $?.success?
                Common.log_success("PDFの生成が完了しました")

                # 生成されたPDFのパスを表示
                pdf_path = pdf_config['output_file'] || 'output.pdf'
                Common.log_info("出力先: #{File.expand_path(pdf_path)}")
              else
                Common.log_error("PDFの生成に失敗しました")
              end
            end

            desc 'pdf_compress', '生成済みPDFを圧縮します (gs または qpdf を自動選択)'
            long_desc <<~DESC
              生成済みのPDFファイルを圧縮します。

              使用可能なツールを自動検出し、優先順位で選択：
              1. qpdf（品質保持に優れた推奨ツール）
              2. gs（Ghostscript）

              オプション:
                -v, --verbose  詳細な処理情報を表示
            DESC
            # ================================================================
            # Command: pdf_compress（PDF圧縮）
            # ------------------------------------------------
            # - 概要: qpdf または gs を用いて PDF を圧縮
            # - 入力: config.yml の pdf.output_file（既定: output.pdf）
            # - 出力: config.yml の pdf.output_file_compressed（既定: output_compressed.pdf）
            # - 補足: 優先エンジンは ENV/設定に従い qpdf を既定で優先
            # ================================================================
            def pdf_compress
              ENV['VERBOSE'] = '1' if options[:verbose]
              pdf_config = Common::CONFIG['pdf'] || {}
              input_pdf  = pdf_config['output_file'] || 'output.pdf'
              output_pdf = pdf_config['output_file_compressed'] || 'output_compressed.pdf'

              unless File.exist?(input_pdf)
                Common.log_error("エラー: 入力PDFが見つかりません: #{input_pdf}")
                exit(1)
              end

              Common.log_action("PDFを圧縮しています…（入力: #{input_pdf} → 出力: #{output_pdf}）")

              # 利用可能なコマンドを検出
              has_gs   = system('which gs >/dev/null 2>&1')
              has_qpdf = system('which qpdf >/dev/null 2>&1')

              # 圧縮エンジンの優先度（ENV > config.yml）
              # 値: 'qpdf' | 'gs' を想定。未指定時は qpdf を優先し、なければ gs。
              preferred = (ENV['VIVLIO_COMPRESS_ENGINE'] || pdf_config['compress_engine'] || '').downcase

              compressed = false

              run_qpdf = proc do
                cmd = [
                  'qpdf', '--linearize', '--compress-streams=y', '--object-streams=generate',
                  input_pdf, output_pdf
                ].join(' ')
                system(cmd)
              end

              run_gs = proc do
                # 透明度保持互換性の改善のため 1.7 を指定
                cmd = [
                  'gs', '-sDEVICE=pdfwrite', '-dCompatibilityLevel=1.7',
                  '-dPDFSETTINGS=/ebook', '-dNOPAUSE', '-dQUIET', '-dBATCH',
                  "-sOutputFile=#{output_pdf}", input_pdf
                ].join(' ')
                system(cmd)
              end

              if preferred == 'qpdf' && has_qpdf
                compressed = run_qpdf.call
              elsif preferred == 'gs' && has_gs
                compressed = run_gs.call
              elsif has_qpdf
                # 既定: qpdf を優先（描画への影響が小さいため）
                compressed = run_qpdf.call
              elsif has_gs
                compressed = run_gs.call
              else
                Common.log_warn('gs も qpdf も見つかりません。圧縮をスキップします。')
                exit(1)
              end

              if compressed && File.exist?(output_pdf)
                Common.log_success("圧縮したPDFを出力しました: #{File.expand_path(output_pdf)}")
              else
                Common.log_error('PDFの圧縮に失敗しました')
                exit(1)
              end
            end

            desc 'open:pdf', '生成されたPDFを開きます'
            long_desc <<~DESC
              生成されたPDFファイルをPreview.appで開きます。

              設定に応じて：
              - 圧縮版PDFが存在すれば優先的に開く
              - 既存のPDFウィンドウを閉じる
              - 指定されたウィンドウ位置に配置
            DESC
            # ================================================================
            # Command: open:pdf（PDFを開く）
            # ------------------------------------------------
            # - 概要: macOS の Preview.app で PDF を開き、ウィンドウ位置を設定
            # - 入力: 圧縮版が存在すればそれを優先、なければ通常版
            # - 補足: 非 macOS では案内のみ表示
            # ================================================================
            def open_pdf
              ENV['VERBOSE'] = '1' if options[:verbose]
              # PDF設定を取得
              pdf_config = Common::CONFIG['pdf'] || {}
              # 圧縮版があれば優先、なければ通常版
              compressed_path = pdf_config['output_file_compressed'] || 'output_compressed.pdf'
              normal_path     = pdf_config['output_file'] || 'output.pdf'
              pdf_path        = File.exist?(compressed_path) ? compressed_path : normal_path

              Common.log_action("PDFを開いています…")
              Common.log_info("ファイルパス: #{File.expand_path(pdf_path)}")

              # macOS 以外では案内のみ表示して終了
              unless RbConfig::CONFIG['host_os'] =~ /darwin|mac os/i
                Common.log_info('この環境では自動オープンは未対応です（macOS専用機能）。PDFは手動で開いてください。')
                return
              end

              unless File.exist?(pdf_path)
                Common.log_error("エラー: PDFファイルが見つかりません: #{pdf_path}")
                exit(1)
              end

              # PDF表示設定を取得
              close_existing = pdf_config['close_existing_windows'] != false  # デフォルトtrue
              window_bounds = pdf_config['window_bounds'] || '{3072, 0, 4096, 2160}'

              # 既存のPDFウィンドウを閉じる（設定で有効な場合）
              if close_existing
                # Shell 経由のクォート崩れを避けるため、引数配列形式で実行
                begin
                  system("osascript", "-e", 'tell application "Preview" to close every window')
                rescue
                  # 失敗しても致命的ではないため黙って続行
                end
              end

              # PDFを開く
              open_cmd = "open -a Preview \"#{pdf_path}\""
              system(open_cmd)

              # Previewウィンドウを指定位置に配置
              system <<~APPLE_SCRIPT
                osascript -e '
                  tell application "Preview"
                    activate
                    set bounds of front window to #{window_bounds}
                  end tell'
              APPLE_SCRIPT

              Common.log_success("PDFを開きました")
            end

            desc 'config', 'config/book.yml の設定から vivliostyle.config.js を生成します'
            long_desc <<~DESC
              book.yml の設定から vivliostyle.config.js を生成します。

              生成内容:
              - タイトル、著者、言語設定
              - 読み進め方向（ltr/rtl）
              - エントリーファイル（entries.js）
              - 出力PDFファイル名

              既存ファイルは自動バックアップされます。
            DESC
            # ================================================================
            # Command: config（vivliostyle.config.js 生成）
            # ------------------------------------------------
            # - 概要: book.yml 等の設定から vivliostyle.config.js を生成
            # - 入力: config.yml の book/vivliostyle/pdf セクション
            # - 出力: vivliostyle.config.js（既存はバックアップ後に上書き）
            # ================================================================
            def config
              ENV['VERBOSE'] = '1' if options[:verbose]
              Common.log_action("vivliostyle.config.jsを生成しています...")

              # 設定を取得
              config             = Common::CONFIG
              book_config        = config['book'] || {}
              vivliostyle_config = config['vivliostyle'] || {}
              pdf_config         = config['pdf'] || {}

              # JS 文字列に安全に埋め込むための簡易エスケープ
              esc = ->(s) { s.to_s.gsub('\\', '\\\\').gsub("'", "\\'") }

              # 設定値を取得（デフォルト値付き）
              # title が未設定の場合は main_title と subtitle を結合して使う
              combined_title = [book_config['main_title'], book_config['subtitle']].compact.join(' ').strip
              title_raw = book_config['title']
              title = (title_raw && !title_raw.to_s.strip.empty?) ? title_raw : (combined_title.empty? ? '書籍タイトル' : combined_title)
              author              = book_config['author'] || '著者名'
              language            = book_config['language'] || 'ja'
              reading_progression = vivliostyle_config['reading_progression'] || 'ltr'
              entries_file        = vivliostyle_config['entries_file'] || 'entries.js'
              output_file         = pdf_config['output_file'] || 'output.pdf'
              config_file         = vivliostyle_config['config_file'] || 'vivliostyle.config.js'

              # バックアップ処理（最新のみ保持）
              if File.exist?(config_file)
                Dir.glob("#{config_file}.backup_*").each { |f| FileUtils.rm_f(f) }
                timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
                backup_file = "#{config_file}.backup_#{timestamp}"
                FileUtils.cp(config_file, backup_file)
                Common.log_info("既存ファイルをバックアップしました: #{backup_file}")
              end

              # vivliostyle.config.jsの内容を生成
              config_content = <<~JS
                import entries from './#{esc.call(entries_file)}';

                // @ts-check
                /** @type {import('@vivliostyle/cli').VivliostyleConfigSchema} */
                const vivliostyleConfig = {
                  title: '#{esc.call(title)}', // 書籍のタイトル
                  author: '#{esc.call(author)}', // 著者名
                  language: '#{esc.call(language)}', // 言語設定
                  readingProgression: '#{esc.call(reading_progression)}', // 読み進め方向（ltr: 横書き, rtl: 縦書き）
                  entry: entries, // 章立て構成（#{entries_file}から読み込み）
                  output: [ // 出力ファイル設定
                    './#{esc.call(output_file)}' // PDFファイル
                  ]
                };

                export default vivliostyleConfig;
              JS

              # ファイルに書き込み
              File.write(config_file, config_content)

              Common.log_success("#{config_file} を生成しました")
              Common.log_info("タイトル: #{title}")
              Common.log_info("著者: #{author}")
              Common.log_info("言語: #{language}")
              Common.log_info("読み進め方向: #{reading_progression}")
              Common.log_info("出力ファイル: #{output_file}")
            end
          end
        end
      end
    end
  end
end
