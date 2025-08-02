require_relative 'common'

# 前処理関連タスク
desc "Markdownファイルの前処理を行います"
task :preprocess do |t, args|
  puts "📝 Markdownファイルの前処理を行っています..."
  
  # コマンドライン引数を取得
  files_arg = BookBuild.process_args
  
  # 処理対象のファイルを決定
  md_files = if files_arg.any?
    puts "  🔍 指定されたファイルのみ処理します: #{files_arg.join(', ')}"
    files_arg.map { |f| "#{BookBuild::CONTENT_DIR}/#{f}.md" }.select { |f| File.exist?(f) }
  else
    # 引数がない場合は全Markdownファイルを処理
    Dir.glob("#{BookBuild::CONTENT_DIR}/*.md")
  end
  
  # 各Markdownファイルを処理
  md_files.each do |md_file|
    filename = File.basename(md_file)
    output_file = filename  # プロジェクトルートに出力
    
    puts "  📄 #{md_file} → #{output_file}"
    
    # ファイルの内容を読み込み
    content = File.read(md_file, encoding: 'utf-8')
    
    # ファイル名から章番号を抽出
    chapter_num = nil
    if filename =~ /^(\d+)-/
      chapter_num = $1
    end
    
    # ファイルタイプを判定
    file_type = BookBuild.get_file_type(filename)
    
    # フロントマターを処理
    if content.start_with?('---')
      # 既存のフロントマターを抽出
      frontmatter_match = content.match(/\A---\n(.*?)\n---\n/m)
      
      if frontmatter_match
        frontmatter_yaml = frontmatter_match[1]
        begin
          existing_frontmatter = YAML.safe_load(frontmatter_yaml) || {}
          
          # 新しいフロントマターを生成して併合
          merged_frontmatter = BookBuild.generate_frontmatter(file_type, chapter_num, existing_frontmatter)
          
          # YAMLに変換
          new_frontmatter_yaml = YAML.dump(merged_frontmatter)
          
          # フロントマターを置換
          content = content.sub(/\A---\n.*?\n---\n/m, "---\n#{new_frontmatter_yaml}---\n")
          
          puts "    ✅ フロントマター更新"
        rescue => e
          puts "    ⚠️ フロントマターのパースに失敗しました: #{e.message}"
        end
      end
    else
      # フロントマターがない場合は追加
      new_frontmatter = BookBuild.generate_frontmatter(file_type, chapter_num)
      new_frontmatter_yaml = YAML.dump(new_frontmatter)
      content = "---\n#{new_frontmatter_yaml}---\n\n#{content}"
      
      puts "    ✅ フロントマター追加"
    end
    
    # 画像パスを修正
    content = BookBuild.fix_image_paths(content, filename)
    puts "    ✅ 画像パス修正"
    
    # 処理後のファイルを保存
    File.write(output_file, content, encoding: 'utf-8')
    puts "    ✅ 保存完了"
  end
  
  puts "✅ Markdown前処理完了"
end
