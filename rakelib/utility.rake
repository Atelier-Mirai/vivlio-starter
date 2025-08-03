require_relative 'common'

# プロジェクト初期化
desc "プロジェクトを初期化します"
task :init do
  puts "🔧 プロジェクトを初期化しています..."
  
  # 必要なディレクトリを作成
  [BookBuild::CONTENT_DIR, BookBuild::STYLESHEETS_DIR, BookBuild::IMAGES_DIR].each do |dir|
    unless Dir.exist?(dir)
      FileUtils.mkdir_p(dir)
      puts "  📂 #{dir}/ ディレクトリを作成しました"
    end
  end
  
  # スタイルシートの作成
  file_types = ['preface', 'toc', 'chapter', 'appendix', 'postface', 'colophon']
  file_types.each do |type|
    css_file = "#{BookBuild::STYLESHEETS_DIR}/#{type}.css"
    unless File.exist?(css_file)
      File.write(css_file, <<~CSS)
        @charset "utf-8";
        
        /* #{type}用スタイル */
        
      CSS
      puts "  ✅ #{css_file} を作成しました"
    end
  end
  
  # サンプルMarkdownファイル生成
  # Rake::Task['sample'].invoke
  system("rake new:md 11-sample")
  
  puts "✅ プロジェクト初期化完了"
end

# 新しいMarkdownファイル生成
namespace :new do
  desc "新しいMarkdownファイルを生成します (例: rake new:md 21-history)"
  task :md do |t|
    # コマンドライン引数を取得
    filename = ARGV[1]
    if filename.nil? || filename.empty?
      puts "❌ ファイル名を指定してください (例: rake new:md 21-history)"
      next
    end
    
    # ファイル名に拡張子がなければ追加
    filename = "#{filename}.md" unless filename.end_with?('.md')
    
    # ファイルパスを生成
    file_path = "#{BookBuild::CONTENT_DIR}/#{filename}"
    
    # ファイルが既に存在するか確認
    if File.exist?(file_path)
      puts "⚠️ #{file_path} は既に存在します"
      next
    end
    
    # ファイルタイプを判定
    file_type = BookBuild.get_file_type(filename)
    
    # チャプター番号を抽出（例: 21-history → 21）
    chapter_num = filename.match(/^(\d+)-/)[1] rescue nil
    
    # タイトルを生成（ハイフンをスペースに変換し、先頭を大文字に）
    title = filename.gsub(/^\d+-/, '').gsub('.md', '').gsub('-', ' ').capitalize
    
    # ファイルを生成
    File.write(file_path, <<~MD)
      # #{title}

      :::{.chapter-lead}
      各章の冒頭に置かれる短い導入文を記述します。この章で扱うテーマや内容の概要を読者に伝える文章を書いてください。
      :::

      ここに#{title}の内容を記述します。

      ## 見出し

      :::{.section-lead}
      章の中の各セクション（節）の冒頭に置かれる導入文を記述します。
      ・このセクションで扱うトピックの簡潔な紹介
      ・読者の興味を引きつける導入部
      ・セクションの内容に関する背景情報の提供
      ・セクションの重要性や他の内容との関連性の説明
      などを記述してください。
      :::

      <!-- 画像は以下のように記述します -->
      ![](Einstein.png){width=40% .float-right}
    MD

    # images ディレクトリを生成
    # ファイル名全体を使用してディレクトリを生成
    base_filename = filename.gsub(/\.md$/, '')
    image_dir = "#{BookBuild::IMAGES_DIR}/#{base_filename}"
    FileUtils.mkdir_p(image_dir)
    puts "  ✅ 画像ディレクトリ #{image_dir} を生成しました"

    # css ファイルを生成
    if file_type == 'chapter'
      puts "ℹ️ 対応するCSSファイルを生成します..."
      system("rake new:css #{filename}")
      puts "✅ #{file_path} を作成しました"
    end
    
    # 追加の引数を処理しないようにする
    if filename && !filename.empty?
      exit 0
    end
  end
end

# 画像ディレクトリ生成
desc "画像ディレクトリを生成します"
task :images do
  puts "🖼️  画像ディレクトリを生成しています..."
  
  # content/以下のMarkdownファイルから必要な画像ディレクトリを抽出
  md_files = Dir.glob("#{BookBuild::CONTENT_DIR}/*.md")
  
  md_files.each do |md_file|
    filename = File.basename(md_file)
    chapter_dir = filename.sub(/\.md$/, '')
    image_dir = "#{BookBuild::IMAGES_DIR}/#{chapter_dir}"
    
    unless Dir.exist?(image_dir)
      FileUtils.mkdir_p(image_dir)
      puts "  ✅ #{image_dir}/ を作成しました"
    end
  end
  
  puts "✅ 画像ディレクトリ生成完了"
end

# クリーンアップ
desc "不要ファイルを削除します"
task :clean do
  puts "🧹 クリーンアップを実行しています..."
  
  # .vivliostyle ディレクトリを削除
  puts "  🗑️ .vivliostyle ディレクトリを削除中..."
  FileUtils.rm_rf('.vivliostyle')
  
  # 生成されたPDF以外のファイルを削除
  puts "  🗑️ 生成ファイルを削除中..."
  
  # プロジェクトルートの一時ファイルを削除
  cleanup_patterns = [
    '*.html',     # HTMLファイル
    '01-toc.md',  # 生成された目次MD
  ]
  
  # content/からコピーされたMDファイルを削除
  # README.mdとdesign_policy.mdは保持
  keep_files = ['README.md', 'design_policy.md']
  Dir.glob('*.md').each do |file|
    next if keep_files.include?(file)
    cleanup_patterns << file
  end
  
  cleanup_patterns.each do |pattern|
    Dir.glob(pattern).each do |file|
      next if File.directory?(file)
      
      FileUtils.rm(file)
      puts "  🗑️  #{file} を削除しました"
    end
  end
  
  puts "✅ クリーンアップ完了"
end

# ヘルプ表示
desc "タスクの使い方を表示します"
task :help do
  puts "📚 Vivliostyle - Build System"
  puts "利用可能なタスク:"
  puts "  rake init                   - プロジェクト初期化"
  puts "  rake preprocess             - 前処理（全ファイル）"
  puts "  rake preprocess <files...>  - 前処理（指定ファイル）"
  puts "  rake convert                - HTML変換（全ファイル）"
  puts "  rake convert <files...>     - HTML変換（指定ファイル）"
  puts "  rake css:chapter            - 章ごとのCSS生成"
  puts "  rake toc                    - 目次生成"
  puts "  rake entries                - entries.js生成"
  puts "  rake images                 - 画像ディレクトリ生成"
  puts "  rake build                  - 全ファイルビルド"
  puts "  rake build <files...>       - 指定ファイルのみビルド"
  puts "  rake pdf                    - PDF生成"
  puts "  rake open                   - 生成PDFを開く"
  puts "  rake clean                  - クリーンアップ"
end
