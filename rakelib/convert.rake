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
  
  begin
    # JSONファイルを読み込み
    json_content = File.read(BookBuild::POST_REPLACE_FILE, encoding: 'utf-8')
    replace_rules = JSON.parse(json_content)
    
    # JSONが配列でない場合はエラー
    unless replace_rules.is_a?(Array)
      puts "    ❌ エラー: JSONファイルは置換オブジェクトの配列を含む必要があります"
      return
    end
    
    html_files = Dir.glob("*.html")
    total_replacements = 0
    
    html_files.each do |html_file|
      puts "    🔄 処理中: #{html_file}"
      
      # HTMLファイルを読み込み
      html_content = File.read(html_file, encoding: 'utf-8')
      original_content = html_content.dup
      file_replacements = 0
      
      # 置換処理
      replace_rules.each_with_index do |item, index|
        unless item.is_a?(Hash) && item.key?('f') && item.key?('r')
          next
        end
        
        pattern_str = item['f']
        replacement_str = item['r']
        
        begin
          # 正規表現パターンを作成
          pattern = Regexp.new(pattern_str)
          
          # 置換実行（キャプチャグループを考慮）
          matches_found = 0
          html_content.gsub!(pattern) do |match|
            matches_found += 1
            match_data = pattern.match(match)
            result = replacement_str.dup
            
            # キャプチャグループの置換 ($1, $2, etc.)
            if match_data && match_data.captures.length > 0
              match_data.captures.each_with_index do |capture, cap_index|
                result.gsub!("$#{cap_index + 1}", capture.to_s) if capture
              end
            end
            
            result
          end
          
          if matches_found > 0
            file_replacements += matches_found
            puts "      ✅ パターン '#{pattern_str}' → #{matches_found}個の置換"
          end
          
        rescue RegexpError => e
          puts "      ⚠️ 警告: 正規表現パターンが無効です: #{pattern_str}"
        end
      end
      
      # 結果の出力と保存
      if html_content != original_content
        # HTMLファイルを上書き
        File.write(html_file, html_content, encoding: 'utf-8')
        total_replacements += file_replacements
        puts "      ✅ #{file_replacements}個の置換が行われました"
      end
    end
    
    puts "    ✅ ポスト置換処理完了 (合計: #{total_replacements}個の置換)"
    
  rescue JSON::ParserError => e
    puts "    ❌ エラー: #{BookBuild::POST_REPLACE_FILE} のJSON形式が無効です"
    puts "      #{e.message}"
  rescue => e
    puts "    ❌ エラー: #{e.message}"
  end
end
