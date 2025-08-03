require_relative 'common'

# ビルド関連タスク
desc "書籍をビルドします (引数を指定するとそのファイルのみをビルド)"
task :build do |t, args|
  puts "📚 書籍をビルドしています..."
  
  # コマンドライン引数を取得
  files_arg = BookBuild.process_args
  
  # 引数の有無で処理を分岐
  if files_arg.any?
    # 指定されたファイルのみ処理
    puts "  🔍 指定されたファイルのみ処理します: #{files_arg.join(', ')}"
    # 前処理
    Rake::Task['preprocess'].invoke(*files_arg)
    # 変換処理
    Rake::Task['convert'].invoke(*files_arg)
    # entries.js生成
    Rake::Task['entries'].invoke(*files_arg)
    # PDF生成
    Rake::Task['pdf'].invoke
    # クリーンアップ
    # Rake::Task['clean'].invoke
    # PDFを開く
    Rake::Task['open:pdf'].invoke
    puts "  ✅ 指定ファイルのビルド完了"
  else
    # 引数がない場合は全ファイルを処理
    puts "  ℹ️ 全ファイルをビルドします"
    # 前処理
    Rake::Task['preprocess'].invoke
    # 変換処理
    Rake::Task['convert'].invoke
    # 目次生成
    Rake::Task['toc'].invoke
    # entries.js生成
    Rake::Task['entries'].invoke
    # PDF生成
    Rake::Task['pdf'].invoke
    # クリーンアップ
    # Rake::Task['clean'].invoke
    # PDFを開く
    Rake::Task['open:pdf'].invoke
    puts "  ✅ 全ファイルのビルド完了"
  end
end

# 全体ビルド（デフォルトタスク）
desc "全体ビルドを実行します（前処理→変換→目次生成→entries.js生成→PDF生成→クリーンアップ→PDFを開く）"
task :default => [:build]
