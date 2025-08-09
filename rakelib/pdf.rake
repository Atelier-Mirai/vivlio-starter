require_relative 'common'

# PDF生成関連タスク
desc "PDFを生成します"
task :pdf do |t, args|
  BookBuild.log_action("PDFを生成しています...")
  
  # コマンドを実行
  system('npx vivliostyle build')

  if $?.success?
    BookBuild.log_success("PDF生成完了")
    
    # 生成されたPDFのパスを表示
    pdf_config = BookBuild::CONFIG['pdf'] || {}
    pdf_path = pdf_config['output_file'] || 'output.pdf'
    BookBuild.log_info("出力先: #{File.expand_path(pdf_path)}")
  else
    BookBuild.log_error("PDF生成失敗")
  end
end

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