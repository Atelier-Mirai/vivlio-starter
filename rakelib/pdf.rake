require_relative 'common'

# PDF生成関連タスク
desc "PDFを生成します"
task :pdf do |t, args|
  puts "📖 PDFを生成しています..."
  
  # コマンドライン引数を取得
  files_arg = BookBuild.process_args
  
  # ES Module形式に統一したため、変換処理は不要
  
  # Vivliostyle Build
  puts "  🔧 Vivliostyle Build実行中..."
  
  if files_arg.any?
    # 指定されたファイルのみビルド
    html_files = files_arg.map { |f| "#{f}.html" }.join(' ')
    system("npx vivliostyle build #{html_files}")
    puts "  🔍 指定ファイルのみビルド: #{files_arg.join(', ')}"
  else
    # すべてのファイルをビルド
    system('npx vivliostyle build')
  end
  
  if $?.success?
    puts "  ✅ PDF生成完了"
  else
    puts "  ❌ PDF生成失敗"
  end
end

# PDFを開く
desc "生成された PDF を開きます"
task :open => 'open:pdf'

namespace :open do
  desc "生成された PDF を開きます"
  task :pdf do
    pdf_path = 'output.pdf'
    if File.exist?(pdf_path)
      puts "📘 ビルド成功！PDF を開いています..."
      # 既存のPDFウィンドウを閉じてから開く
      system('osascript -e \'tell application "Preview" to close every window\' 2>/dev/null')
      system("open -a Preview #{pdf_path}")
      
      # Previewウィンドウを画面右側に配置
      system <<~APPLE_SCRIPT
        osascript -e '
          tell application "Preview"
            activate
            set bounds of front window to {3072, 0, 4096, 2160}
          end tell'
      APPLE_SCRIPT
    else
      puts "⚠️ ビルドは完了しましたが、PDF ファイルが見つかりません！"
    end
  end
end
