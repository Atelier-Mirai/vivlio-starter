# マークダウン変換関連のタスク

desc "Markdown から HTML に変換します"
task :convert => [:preprocess] do
  puts "📝 Markdown を HTML に変換しています..."
  
  # MarkdownをHTMLに変換するタスクを実行
  Rake::Task["md:to_html"].invoke("all")
  
  # 目次生成タスクを実行
  Rake::Task[:generate_toc].invoke
end

desc "HTML ファイルのみを生成します（PDF生成なし）"
task :html_only => [:clean, :convert, :set_body_classes] do
  puts "🌐 HTML ファイルの生成が完了しました"
end
