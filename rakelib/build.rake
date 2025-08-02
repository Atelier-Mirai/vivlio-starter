require_relative 'common'

# ビルド関連タスク
desc "書籍をビルドします"
task :build => [:preprocess, :convert, 'css:chapter', :toc, :entries, :pdf] do
  puts "✅ ビルド完了"
end

# 単体ビルドタスク
desc "指定されたファイルのみをビルドします"
task :build_files do |t, args|
  puts "📚 指定ファイルをビルドしています..."
  
  # コマンドライン引数を取得
  files_arg = BookBuild.process_args
  
  # 前処理→変換→章ごとCSS生成→目次生成→entries.js生成→PDF生成の流れ
  if files_arg.any?
    # 指定されたファイルのみ処理
    puts "  🔍 指定されたファイルのみ処理します: #{files_arg.join(', ')}"
    Rake::Task['preprocess'].invoke(*files_arg)
    Rake::Task['convert'].invoke(*files_arg)
    
    # 章ファイルの場合は章ごとのCSSも生成
    chapter_files = files_arg.select do |f|
      file_type = BookBuild.get_file_type("#{f}.md")
      file_type == 'chapter'
    end
    
    if chapter_files.any?
      Rake::Task['css:chapter'].invoke
    end
    
    # entries.jsを更新
    Rake::Task['entries'].invoke(*files_arg)
    
    # PDF生成
    Rake::Task['pdf'].invoke
    
    puts "  ✅ 指定ファイルのビルド完了"
  else
    # 引数がない場合は通常のビルドタスクを実行
    puts "  ℹ️ 引数が指定されていません。通常のビルドを実行します。"
    Rake::Task['build'].invoke
  end
end

# 全体ビルド（デフォルトタスク）
desc "全体ビルドを実行します（前処理→変換→PDF生成→クリーンアップ）"
task :default => [:build]
