require_relative 'common'

# PDF生成関連タスク
desc "PDFを生成します"
task :pdf do |t, args|
  BookBuild.log_action("PDFを生成しています...")
  
  # 出力抑制フラグ（ENV または config.yml の pdf.quiet）
  pdf_config = BookBuild::CONFIG['pdf'] || {}
  quiet = (ENV['VIVLIO_QUIET'] == '1') || (pdf_config['quiet'] == true)

  # コマンドを実行（quiet の場合は /dev/null へ）
  cmd = 'npx vivliostyle build'
  if quiet
    system(cmd, out: File::NULL, err: File::NULL)
  else
    system(cmd)
  end

  if $?.success?
    BookBuild.log_success("PDF生成完了")
    
    # 生成されたPDFのパスを表示
    pdf_path = pdf_config['output_file'] || 'output.pdf'
    BookBuild.log_info("出力先: #{File.expand_path(pdf_path)}")
  else
    BookBuild.log_error("PDF生成失敗")
  end
end

# PDF圧縮
namespace :pdf do
  desc "生成済みPDFを圧縮します (gs または qpdf を自動選択)"
  task :compress do
    pdf_config = BookBuild::CONFIG['pdf'] || {}
    input_pdf  = pdf_config['output_file'] || 'output.pdf'
    output_pdf = pdf_config['output_file_compressed'] || 'output_compressed.pdf'

    unless File.exist?(input_pdf)
      BookBuild.log_error("エラー: 入力PDFが見つかりません: #{input_pdf}")
      next
    end

    BookBuild.log_action("PDFを圧縮しています... (入力: #{input_pdf} → 出力: #{output_pdf})")

    # 利用可能なコマンドを検出
    has_gs   = system('which gs >/dev/null 2>&1')
    has_qpdf = system('which qpdf >/dev/null 2>&1')

    compressed = false

    if has_gs
      # Ghostscript を使って強めに圧縮（/ebook はバランス良）
      cmd = [
        'gs', '-sDEVICE=pdfwrite', '-dCompatibilityLevel=1.5',
        '-dPDFSETTINGS=/ebook', '-dNOPAUSE', '-dQUIET', '-dBATCH',
        "-sOutputFile=#{output_pdf}", input_pdf
      ].join(' ')
      compressed = system(cmd)
    elsif has_qpdf
      # qpdf: 線形化・圧縮を期待（実サイズ減少はコンテンツ依存）
      cmd = [
        'qpdf', '--linearize', '--compress-streams=y', '--object-streams=generate',
        input_pdf, output_pdf
      ].join(' ')
      compressed = system(cmd)
    else
      BookBuild.log_warn('gs も qpdf も見つかりません。圧縮をスキップします。')
      next
    end

    if compressed && File.exist?(output_pdf)
      BookBuild.log_success("圧縮PDFを出力しました: #{File.expand_path(output_pdf)}")
    else
      BookBuild.log_error('PDF圧縮に失敗しました')
    end
  end
end

# エイリアス: `rake open` で `open:pdf` を呼び出す
desc "生成された PDF を開きます（エイリアス: open:pdf）"
task :open => 'open:pdf'

# PDFを開く
namespace :open do
  desc "生成された PDF を開きます"
  task :pdf do
    # PDF設定を取得
    pdf_config = BookBuild::CONFIG['pdf'] || {}
    pdf_path = pdf_config['output_file'] || 'output.pdf'
    
    BookBuild.log_action("PDF を開いています...")
    BookBuild.log_info("ファイルパス: #{File.expand_path(pdf_path)}")
    
    unless File.exist?(pdf_path)
      BookBuild.log_error("エラー: PDFファイルが見つかりません: #{pdf_path}")
      next
    end
    
    # PDF表示設定を取得
    close_existing = pdf_config['close_existing_windows'] != false  # デフォルトtrue
    window_bounds = pdf_config['window_bounds'] || '{3072, 0, 4096, 2160}'
    
    # 既存のPDFウィンドウを閉じる（設定で有効な場合）
    if close_existing
      system('osascript -e \'tell application "Preview" to close every window\' 2>/dev/null')
    end
    
    # PDFを開く
    open_cmd = "open -a Preview #{pdf_path}"
    system(open_cmd)
    
    # Previewウィンドウを指定位置に配置
    system <<~APPLE_SCRIPT
      osascript -e '
        tell application "Preview"
          activate
          set bounds of front window to #{window_bounds}
        end tell'
    APPLE_SCRIPT
    
    BookBuild.log_success("PDFを開きました")
  end
end