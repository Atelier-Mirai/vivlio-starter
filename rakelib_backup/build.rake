# ビルド関連のタスク（コマンドライン引数をサポート）

desc "コマンドライン引数で指定した複数の章をビルドします"
task :build do
  # ARGV[1]以降がタスク名の後の引数
  chapters = ARGV[1..-1]
  
  # もしARGVが空（rake buildのみ）なら処理中止
  if ARGV.length <= 1
    puts "❌ エラー: ビルドする章を指定してください"
    puts "使用例: rake build 00-preface 01-gift 99-colophon"
    exit 1
  end
  
  # タスクの引数でない引数を処理するために、以降の引数を無視するようRakeに指示
  ARGV[1..-1].each { |a| task a.to_sym do ; end }
  
  puts "🔄 選択された章をビルドします: #{chapters.join(', ')}"
  
  # クリーンアップ（オプション）
  if ENV['CLEAN'] == 'true'
    puts "🧹 クリーンアップを実行します..."
    Rake::Task["clean"].invoke
  end
  
  # 前処理と変換
  chapters.each do |chapter|
    chapter_base = chapter.sub(/\.md$/, '')
    md_file      = "content/#{chapter_base}.md"
    html_file    = "content/#{chapter_base}.html"
    
    # マークダウンからHTMLへの変換が必要な場合
    if File.exist?(md_file)
      puts "🔄 #{chapter_base} の処理を開始します..."
      
      # 前処理タスクを実行
      begin
        Rake::Task["preprocess"].reenable
        Rake::Task["preprocess"].invoke(md_file)
      rescue => e
        puts "❌ #{md_file} の前処理中にエラーが発生しました: #{e.message}"
      end
      
      # HTML変換タスクを実行
      begin
        Rake::Task["md:to_html"].reenable
        Rake::Task["md:to_html"].invoke(md_file)
      rescue => e
        puts "❌ #{md_file} のHTML変換中にエラーが発生しました: #{e.message}"
      end
    # 直接HTMLファイルがある場合（奈付など）
    elsif File.exist?(html_file)
      puts "🔄 HTMLファイル #{chapter_base}.html をworkspaceにコピーします..."
      
      # workspaceディレクトリにコピーし、パス参照を修正
      begin
        # HTMLファイルを読み込む
        html_content = File.read(html_file, encoding: 'utf-8')
        
        # パス参照を修正 (../stylesheets/ → /stylesheets/, ../images/ → /images/)
        html_content.gsub!(/href="\.\.\/(stylesheets\/[^"]+)"/, 'href="/\1"')
        html_content.gsub!(/src="\.\.\/(images\/[^"]+)"/, 'src="/\1"')
        
        # 修正したHTMLを書き込む
        File.write("workspace/#{chapter_base}.html", html_content, encoding: 'utf-8')
        puts "  ✅ #{chapter_base}.htmlをパス修正してworkspaceディレクトリに保存しました"
      rescue => e
        puts "❌ #{html_file} の処理中にエラーが発生しました: #{e.message}"
      end
    else
      puts "⚠️ 警告: #{chapter_base} のソースファイルが見つかりません。スキップします。"
      next
    end
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
  
  entries_objects = html_entries.map do |entry|
    base_name = entry.sub(/\.html$/, '')
    # タイトルの設定（単純な変換）
    title = case base_name
            when '00-preface' then '序文'
            when '00-toc' then '目次'
            when '01-gift' then '贈り物'
            when '99-colophon' then '奥付'
            else base_name.sub(/^\d+-/, '') # 数字プレフィックスを削除
            end
    
    "  {\n    path: \"#{entry}\",\n    title: \"#{title}\"\n  }"
  end
  
  entries_content = <<-JS
// entries.js - 選択章ビルド用
// 生成日時: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}
// 注意: 自動生成されたファイルです。編集しないでください。
module.exports = [
#{entries_objects.join(",\n")}
];
  JS
  
  File.write("entries.js", entries_content)
  puts "  ✅ 選択した章用のentries.jsを生成しました"
  
  # PDF生成
  puts "📔 PDF生成を開始します..."
  begin
    Rake::Task["vivliostyle"].reenable
    Rake::Task["vivliostyle"].invoke
  rescue => e
    puts "❌ PDF生成中にエラーが発生しました: #{e.message}"
    exit 1
  end
  
  puts "\n✅ 選択した章（#{chapters.join(', ')}）のビルドが完了しました"
  puts "  📖 PDFファイル: workspace/book.pdf"
  puts "  🔍 PDFを開くには: rake open_pdf"
  puts "  🔄 元のentries.jsを復元するには: mv entries.js.bak entries.js"
end
