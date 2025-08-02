require_relative 'common'

# HTML変換関連タスク
desc "MarkdownファイルをHTMLに変換します"
task :convert do |t, args|
  puts "🔄 MarkdownファイルをHTMLに変換しています..."
  
  # コマンドライン引数を取得
  files_arg = BookBuild.process_args
  
  # 処理対象のファイルを決定
  md_files = if files_arg.any?
    puts "  🔍 指定されたファイルのみ処理します: #{files_arg.join(', ')}"
    files_arg.map { |f| "#{f}.md" }.select { |f| File.exist?(f) }
  else
    # 引数がない場合は全Markdownファイルを処理
    Dir.glob("*.md").reject { |f| ['README.md', 'design_policy.md'].include?(f) }
  end
  
  # 各Markdownファイルを処理
  md_files.each do |md_file|
    html_file = md_file.sub(/\.md$/, '.html')
    
    puts "  📄 #{md_file} → #{html_file}"
    
    # vfmコマンドで変換
    system("#{BookBuild::VFM_COMMAND} #{md_file} > #{html_file}")
    
    if $?.success?
      puts "    ✅ 変換完了"
    else
      puts "    ❌ 変換失敗"
    end

    # ファイル名からファイルタイプを取得
    file_type = BookBuild.get_file_type(File.basename(md_file))
    
    # HTMLファイルを読み込み
    content = File.read(html_file, encoding: 'utf-8')
    
    # bodyタグにクラスを追加して保存
    modified_content = content.gsub(/<body>/, "<body class=\"#{file_type}\">")
    File.write(html_file, modified_content, encoding: 'utf-8')
    puts "    ✅ #{html_file} にbodyクラス '#{file_type}' を設定しました"
  end
  
  # ポスト置換処理
  if File.exist?(BookBuild::POST_REPLACE_FILE)
    puts "  🔧 ポスト置換処理を実行中..."
    Rake::Task['post_replace'].invoke
  end
  
  puts "✅ HTML変換完了"
end

# ポスト置換処理
desc "HTMLファイルのポスト置換処理を行います"
task :post_replace do
  return unless File.exist?(BookBuild::POST_REPLACE_FILE)
  
  replace_rules = JSON.parse(File.read(BookBuild::POST_REPLACE_FILE))
  html_files = Dir.glob("*.html")
  
  html_files.each do |html_file|
    content = File.read(html_file, encoding: 'utf-8')
    
    replace_rules.each do |rule|
      if rule['pattern'] && rule['replacement']
        content.gsub!(Regexp.new(rule['pattern']), rule['replacement'])
      end
    end
    
    File.write(html_file, content, encoding: 'utf-8')
  end
  
  puts "    ✅ ポスト置換処理完了"
end
