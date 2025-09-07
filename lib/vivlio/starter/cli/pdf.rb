# frozen_string_literal: true
require 'rbconfig'

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

              # single-doc フラグ（ENV または config.yml の pdf.single_doc）
              single_doc = (ENV['VIVLIO_SINGLE_DOC'] == '1') || (pdf_config['single_doc'] == true)

              # 注意: --single-doc は「単一HTML」を想定する Vivliostyle CLI のモードです。
              # 本プロジェクトは通常 entries.js（配列）を entry に渡すため、そのまま -d を付けると
              # entries.js を HTML と誤解され、"Start tag expected, '<' not found" になることがあります。
              # そこで、entries.js のエントリ数が 1 件のときのみ -d を有効化します。
              enable_single_doc = false
              if single_doc
                begin
                  # vivliostyle.config.js が entries.js を参照している場合は -d 無効
                  begin
                    cfg_path = File.join(Dir.pwd, 'vivliostyle.config.js')
                    if File.exist?(cfg_path)
                      cfg_txt = File.read(cfg_path, encoding: 'utf-8')
                      if cfg_txt.match?(/entries\.(js|mjs)\b/)
                        Common.log_info('[pdf] vivliostyle.config.js が entries.js を参照しているため --single-doc を無効化します')
                        single_doc = false
                      end
                    end
                  rescue => e
                    # 読み取り失敗時は何もしない（後段の entries.js 判定に任せる）
                  end
                  entries_path = File.join(Dir.pwd, 'entries.js')
                  if File.exist?(entries_path)
                    txt = File.read(entries_path, encoding: 'utf-8')
                    # かなり単純だが十分: "path": の出現数で判定
                    paths = txt.scan(/\"path\"\s*:/)
                    if paths.size == 1 && single_doc
                      enable_single_doc = true
                    else
                      Common.log_info("[pdf] entries.js に複数エントリ(#{paths.size})があるため --single-doc は無効化します")
                    end
                  else
                    # entries.js がない場合は安全側で無効化
                    Common.log_info('[pdf] entries.js が見つからないため --single-doc は無効化します')
                  end
                rescue => e
                  Common.log_warn("[pdf] --single-doc 判定に失敗: #{e}。安全側で無効化します")
                end
              end

              # コマンドを実行（quiet の場合は /dev/null へ）
              cmd = 'npx vivliostyle build'
              cmd += ' -d' if enable_single_doc
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

            desc 'pdf_compress', '生成済みPDFを圧縮します (Ghostscript)'
            long_desc <<~DESC
              生成済みのPDFファイルを Ghostscript(pdfwrite) を用いて圧縮します。

              既定の品質プリセットは /ebook（中庸）です。

              オプション:
                -v, --verbose  詳細な処理情報を表示
            DESC
            # ================================================================
            # Command: pdf_compress（PDF圧縮）
            # ------------------------------------------------
            # - 概要: Ghostscript を用いて PDF を圧縮
            # - 入力: config.yml の pdf.output_file（既定: output.pdf）
            # - 出力: config.yml の pdf.output_file_compressed（既定: output_compressed.pdf）
            # - 補足: 既定のプリセットは /ebook。必要に応じてコード変更で調整してください。
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
              
              compressed = false

              run_gs = proc do
                # 透明度保持互換性の改善のため 1.7 を指定
                cmd = [
                  'gs', '-sDEVICE=pdfwrite', '-dCompatibilityLevel=1.7',
                  '-dPDFSETTINGS=/ebook', '-dNOPAUSE', '-dQUIET', '-dBATCH',
                  "-sOutputFile=#{output_pdf}", input_pdf
                ].join(' ')
                system(cmd)
              end

              if has_gs
                compressed = run_gs.call
              else
                Common.log_warn('Ghostscript(gs) が見つかりません。圧縮をスキップします。')
                exit(1)
              end

              if compressed && File.exist?(output_pdf)
                Common.log_success("圧縮したPDFを出力しました: #{File.expand_path(output_pdf)}")
              else
                Common.log_error('PDFの圧縮に失敗しました')
                exit(1)
              end
            end

            desc 'open:pdf [PATH]', '生成されたPDFを開きます（PATH 指定可）'
            long_desc <<~DESC
              生成されたPDFファイルをPreview.appで開きます。

              設定に応じて：
              - 圧縮版PDFが存在すれば優先的に開く
              - 既存のPDFウィンドウを閉じる
              - 指定されたウィンドウ位置に配置

              PATH を与えた場合はそのファイルを開き、同様にウィンドウ位置を適用します。
            DESC
            # ================================================================
            # Command: open:pdf（PDFを開く）
            # ------------------------------------------------
            # - 概要: macOS の Preview.app で PDF を開き、ウィンドウ位置を設定
            # - 入力: 圧縮版が存在すればそれを優先、なければ通常版
            # - 補足: 非 macOS では案内のみ表示
            # ================================================================
            def open_pdf(path = nil)
              ENV['VERBOSE'] = '1' if options[:verbose]
              # PDF設定を取得
              pdf_config = Common::CONFIG['pdf'] || {}
              # 開く対象の決定: 引数優先。未指定時は圧縮版があれば優先、なければ通常版
              pdf_path = nil
              if path && !path.to_s.strip.empty?
                pdf_path = path.to_s
              else
                compressed_path = pdf_config['output_file_compressed'] || 'output_compressed.pdf'
                normal_path     = pdf_config['output_file'] || 'output.pdf'
                pdf_path        = File.exist?(compressed_path) ? compressed_path : normal_path
              end

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
          end
        end
      end
    end
  end
end
