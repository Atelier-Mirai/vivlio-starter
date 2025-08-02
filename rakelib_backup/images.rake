# 画像ディレクトリ関連のタスク
require 'fileutils'

namespace :images do
  desc "Markdownファイルに対応した画像ディレクトリを作成します"
  task :create_dirs do
    # Markdownファイルの場所を指定
    content_dir = 'content'
    markdown_glob = File.join(content_dir, '*.md')
    image_base_dir = 'images'
    
    puts "🔍 #{content_dir}ディレクトリ内のMarkdownファイルを検索しています..."

    # Markdownファイルの一覧を取得（数値でソート）
    markdown_files = Dir.glob(markdown_glob).sort_by do |filename|
      # ファイル名から数値部分を抽出してソート用のキーを生成
      if match = File.basename(filename).match(/^(\d+)/)
        match[1].to_i
      else
        filename
      end
    end
    
    if markdown_files.empty?
      puts "⚠️ #{content_dir}ディレクトリ内にMarkdownファイルが見つかりません"
      exit 0
    end
    
    # メイン処理
    created_count = 0
    each_dir = []
    
    markdown_files.each do |file|
      # 拡張子を除いたベース名を取得
      base_name = File.basename(file, '.md')
      path = File.join(image_base_dir, base_name)
      
      unless Dir.exist?(path)
        FileUtils.mkdir_p(path)
        created_count += 1
        each_dir << "  - #{path}"
      end
    end
    
    # 結果を表示
    if created_count > 0
      puts "✅ #{created_count}個の画像ディレクトリを作成しました："
      puts each_dir.join("\n")
    else
      puts "ℹ️ 新しいディレクトリは作成されませんでした（既に存在しています）"
    end
  end
  
  desc "画像ディレクトリの状況を確認します"
  task :check_dirs do
    content_dir = 'content'
    markdown_glob = File.join(content_dir, '*.md')
    image_base_dir = 'images'
    
    # Markdownファイルの一覧を取得
    markdown_files = Dir.glob(markdown_glob)
    
    if markdown_files.empty?
      puts "⚠️ #{content_dir}ディレクトリ内にMarkdownファイルが見つかりません"
      exit 0
    end
    
    missing_dirs = []
    existing_dirs = []
    
    markdown_files.each do |file|
      base_name = File.basename(file, '.md')
      path = File.join(image_base_dir, base_name)
      
      if Dir.exist?(path)
        existing_dirs << path
      else
        missing_dirs << path
      end
    end
    
    puts "📊 画像ディレクトリの状況:"
    puts "  - 作成済み: #{existing_dirs.length}個"
    puts "  - 未作成: #{missing_dirs.length}個"
    
    unless missing_dirs.empty?
      puts "\n⚠️ 以下の画像ディレクトリが未作成です:"
      missing_dirs.each { |dir| puts "  - #{dir}" }
      puts "\n画像ディレクトリを作成するには次のコマンドを実行してください:"
      puts "  rake images:create_dirs"
    end
  end
  
  desc "すべてのMarkdownファイルに対応する画像ディレクトリを準備します（作成＋権限設定）"
  task :setup => [:create_dirs] do
    # 権限設定など追加の処理が必要な場合はここに追加
    puts "📁 画像ディレクトリのセットアップが完了しました"
  end
end
