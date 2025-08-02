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
  
  # サンプルMarkdownファイルの作成
  sample_md = "#{BookBuild::CONTENT_DIR}/00-preface.md"
  unless File.exist?(sample_md)
    File.write(sample_md, <<~MD)
      ---
      title: "電気・電子技術への招待 ～古代の叡智から現代AIまで～"
      author: "著者名"
      ---
      
      # はじめに
      
      本書「電気・電子技術への招待 ～古代の叡智から現代AIまで～」へようこそ。
      
      この本は、電気・電子技術の基本的な概念や歴史的背景を幅広く紹介し、
      読者が興味を持った分野についてさらに深く学ぶきっかけを提供することを目的としています。
      
      専門的な深い知識よりも、親しみやすさと理解しやすさを重視した構成となっています。
      
    MD
    puts "  ✅ #{sample_md} を作成しました"
  end
  
  puts "✅ プロジェクト初期化完了"
end

# 画像ディレクトリ生成
desc "画像ディレクトリを生成します"
task :images do
  puts "🖼️  画像ディレクトリを生成しています..."
  
  # content/以下のMarkdownファイルから必要な画像ディレクトリを抽出
  md_files = Dir.glob("#{BookBuild::CONTENT_DIR}/*.md")
  
  md_files.each do |md_file|
    filename = File.basename(md_file)
    chapter_dir = filename.sub(/\.md$/, '').sub(/^(\d+)-.*/, '\1-\2')
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
  puts "📚 電気・電子技術への招待 - Build System"
  puts "利用可能なタスク:"
  puts "  rake init                   - プロジェクト初期化"
  puts "  rake preprocess              - 前処理（全ファイル）"
  puts "  rake preprocess <files...>   - 前処理（指定ファイル）"
  puts "  rake convert                - HTML変換（全ファイル）"
  puts "  rake convert <files...>      - HTML変換（指定ファイル）"
  puts "  rake css:chapter            - 章ごとのCSS生成"
  puts "  rake toc                    - 目次生成"
  puts "  rake entries                - entries.js生成"
  puts "  rake images                 - 画像ディレクトリ生成"
  puts "  rake build                  - 全ファイルビルド"
  puts "  rake build_files <files...>  - 指定ファイルのみビルド"
  puts "  rake pdf                    - PDF生成"
  puts "  rake open                   - 生成PDFを開く"
  puts "  rake clean                  - クリーンアップ"
end
