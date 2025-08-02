# 特定の章のビルドに関連するタスク

desc "単一の章をビルドしてPDFを生成します"
task :single_chapter, [:chapter_file] do |t, args|
  chapter_file = args[:chapter_file]
  
  # ファイル指定がない場合はエラー
  if chapter_file.nil? || chapter_file.empty?
    puts "❌ エラー: 章のファイル名を指定してください"
    puts "使用例: rake single_chapter[01-gift]"
    exit 1
  end
  
  # 拡張子を除去し、必要に応じてパスを調整
  chapter_base = chapter_file.sub(/\.md$/, '')
  chapter_base = File.basename(chapter_base) # パスが含まれている場合は取り除く
  
  md_file = "content/#{chapter_base}.md"
  html_file = "workspace/#{chapter_base}.html"
  
  # ファイルの存在確認
  unless File.exist?(md_file)
    puts "❌ エラー: #{md_file} が見つかりません"
    exit 1
  end
  
  puts "🔄 #{chapter_base} の単独ビルドを開始します..."
  
  # クリーンアップ（オプション - ユーザーに確認）
  if ENV['CLEAN'] == 'true'
    puts "🧹 クリーンアップを実行します..."
    Rake::Task["clean"].invoke
  end
  
  # 前処理と変換
  puts "📝 前処理を実行しています..."
  Rake::Task["preprocess"].invoke(md_file)
  
  puts "🔄 HTMLに変換しています..."
  Rake::Task["md:to_html"].reenable
  Rake::Task["md:to_html"].invoke(md_file)
  
  # 変換後のファイル存在確認
  unless File.exist?(html_file)
    puts "❌ エラー: 変換後のHTML #{html_file} が生成されませんでした"
    exit 1
  end
  
  # 専用のentries.js生成
  puts "📄 単一章用のentries.jsを生成しています..."
  
  # 既存のentries.jsをバックアップ
  if File.exist?("entries.js")
    FileUtils.cp("entries.js", "entries.js.bak")
    puts "  ✅ 既存のentries.jsをバックアップしました (entries.js.bak)"
  end
  
  entries_content = <<-JS
// entries.js - 単一章ビルド用
// 生成日時: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}
// 注意: 自動生成されたファイルです。編集しないでください。
module.exports = {
  entryContext: 'workspace',
  entries: [
    "#{File.basename(html_file)}"
  ]
};
  JS
  
  File.write("entries.js", entries_content)
  puts "  ✅ 単一章用のentries.jsを生成しました"
  
  # PDF生成
  puts "📔 PDF生成を開始します..."
  Rake::Task["vivliostyle"].reenable
  Rake::Task["vivliostyle"].invoke
  
  puts "\n✅ #{chapter_base} の単独ビルドが完了しました"
  puts "  📄 HTMLファイル: #{html_file}"
  puts "  📖 PDFファイル: workspace/book.pdf"
  puts "  🔍 PDFを開くには: rake open_pdf"
  puts "  🔄 元のentries.jsを復元するには: mv entries.js.bak entries.js"
end

desc "複数の章をまとめてビルドしてPDFを生成します"
task :build_chapters, [:chapter_list] do |t, args|
  # 引数処理: コマンドライン引数と通常の引数をサポート
  chapters = []
  
  # 環境変数CHAPTERSが設定されていれば使用
  if ENV['CHAPTERS']
    chapters = ENV['CHAPTERS'].split(/\s+/)
  # 引数として章リストが指定されていれば使用
  elsif args[:chapter_list] && !args[:chapter_list].empty?
    # カンマ区切り文字列か確認
    if args[:chapter_list].include?(',')
      chapters = args[:chapter_list].split(',').map(&:strip)
    else
      chapters = [args[:chapter_list]]
    end
  end
  
  # 引数がないか、空の引数しかない場合はエラー
  if chapters.empty?
    puts "❌ エラー: ビルドする章を指定してください"
    puts "使用例: CHAPTERS='00-preface 01-gift 99-colophon' rake build_chapters"
    puts "または:  rake build_chapters[\"00-preface,01-gift,99-colophon\"]"
    puts "または:  rake build_chapters[00-preface]"
    exit 1
  end
  
  # クリーンアップ（オプション）
  if ENV['CLEAN'] == 'true'
    puts "🧹 クリーンアップを実行します..."
    Rake::Task["clean"].invoke
  end
  
  # 前処理と変換
  chapters.each do |chapter|
    chapter_base = chapter.sub(/\.md$/, '')
    md_file = "content/#{chapter_base}.md"
    
    unless File.exist?(md_file)
      puts "⚠️ 警告: #{md_file} が見つかりません。スキップします。"
      next
    end
    
    puts "🔄 #{chapter_base} の処理を開始します..."
    
    Rake::Task["preprocess"].reenable
    Rake::Task["preprocess"].invoke(md_file)
    
    Rake::Task["md:to_html"].reenable
    Rake::Task["md:to_html"].invoke(md_file)
  end
  
  # 専用のentries.js生成
  puts "📄 選択した章用のentries.jsを生成しています..."
  
  # 既存のentries.jsをバックアップ
  if File.exist?("entries.js")
    FileUtils.cp("entries.js", "entries.js.bak")
    puts "  ✅ 既存のentries.jsをバックアップしました (entries.js.bak)"
  end
  
  html_entries = chapters.map do |chapter| 
    chapter_base = chapter.sub(/\.md$/, '')
    "#{chapter_base}.html"
  end
  
  entries_lines = html_entries.map { |entry| "    \"#{entry}\"" }
  
  entries_content = <<-JS
// entries.js - 選択章ビルド用
// 生成日時: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}
// 注意: 自動生成されたファイルです。編集しないでください。
module.exports = {
  entryContext: 'workspace',
  entries: [
#{entries_lines.join(",\n")}
  ]
};
  JS
  
  File.write("entries.js", entries_content)
  puts "  ✅ 選択した章用のentries.jsを生成しました"
  
  # PDF生成
  puts "📔 PDF生成を開始します..."
  Rake::Task["vivliostyle"].reenable
  Rake::Task["vivliostyle"].invoke
  
  puts "\n✅ 選択した章（#{chapters.join(', ')}）のビルドが完了しました"
  puts "  📖 PDFファイル: workspace/book.pdf"
  puts "  🔍 PDFを開くには: rake open_pdf"
  puts "  🔄 元のentries.jsを復元するには: mv entries.js.bak entries.js"
end

desc "標準的な書籍構成（前書き、目次、本文、後書き、奥付け）でビルドします"
task :standard_book do
  # 標準的な章構成を指定
  chapters = ["00-preface", "toc", "01-gift", "02-source", "03-unit", "04-electricity", 
              "05-electronics", "07-ai", "98-postface", "99-colophon"]
  
  # 有効な章のみをフィルタリング
  valid_chapters = chapters.select do |chapter|
    File.exist?("content/#{chapter}.md") || 
    (chapter == "toc" && File.exist?("workspace/toc.html"))
  end
  
  # 章リストを文字列に変換してbuild_chaptersタスクを呼び出し
  Rake::Task["build_chapters"].invoke(valid_chapters.join(','))
end
