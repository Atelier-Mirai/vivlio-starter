# PDF生成関連のタスク
require 'fileutils'

desc "Vivliostyle を使用して PDF を生成します"
task :vivliostyle do
  puts "📖 Vivliostyle で PDF を生成しています..."
  system('vivliostyle build') or abort("❌ Vivliostyle ビルドに失敗しました")
  
  # PDFファイルをworkspaceディレクトリに移動（生成されていれば）
  if File.exist?('hobbytech.pdf') && !File.exist?('workspace/hobbytech.pdf')
    FileUtils.mv('hobbytech.pdf', 'workspace/hobbytech.pdf')
  end
end

desc "生成された PDF を開きます"
task :open_pdf do
  pdf_path = 'workspace/hobbytech.pdf'
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

desc "EPUB 形式で出力します（実験的機能）"
task :epub => [:clean, :convert, :set_body_classes] do
  puts "📚 EPUB を生成しています..."
  # EPUB 用の設定ファイルを使用
  # 現在は実装されていないため、将来的な拡張用のプレースホルダー
  abort("❌ EPUB 出力機能は現在実装中です")
end
