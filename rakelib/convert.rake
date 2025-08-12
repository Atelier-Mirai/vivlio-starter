require_relative 'common'

# HTML変換関連タスク
desc "MarkdownファイルをHTMLに変換します"
task :convert do |t, args|
  # コマンドライン引数を取得
  args = BookBuild.process_args('convert')
  files = args[:files]
  options = args[:options]
  
  BookBuild.log_action("MarkdownファイルをHTMLに変換しています...")
  
  # 処理対象のファイルを決定
  md_files = if files.any?
    BookBuild.log_info("指定されたファイルのみ処理します: #{files.join(', ')}")
    
    # 存在しないファイルをチェック
    missing_files = files.reject { |f| File.exist?("#{f}.md") }
    if missing_files.any?
      BookBuild.log_error("エラー: 次のファイルが存在しません: #{missing_files.join(', ')}")
      BookBuild.log_warn("変換を中止します")
      exit(1)
    end
    
    files.map { |f| "#{f}.md" }
  else
    # 引数がない場合は全Markdownファイルを処理（README.mdとROADMAP.mdを除く）
    Dir.glob("*.md").reject { |f| ['README.md', 'ROADMAP.md'].include?(f) }
  end
  
  # ファイル引数をタスクとして実行されないようにダミータスクを作成
  files.each { |arg| task arg.to_sym do ; end }
  
  # 各Markdownファイルを処理
  md_files.each do |md_file|
    html_file = md_file.sub(/\.md$/, '.html')
    
    BookBuild.log_info("#{md_file} → #{html_file}")
    
    # vfmコマンドで変換
    vfm_cmd = "#{BookBuild::VFM_COMMAND} #{md_file} > #{html_file}"
    system(vfm_cmd)
    
    if $?.success?
      BookBuild.log_success("変換完了")
    else
      BookBuild.log_error("変換失敗")
      next  # 変換に失敗した場合はスキップ
    end

    # ファイル名からファイルタイプを取得
    file_type = BookBuild.get_file_type(md_file)
    
    # HTMLファイルを読み込み
    content = File.read(html_file, encoding: 'utf-8')
    
    # bodyタグにクラスを追加して保存
    modified_content = content.gsub(/<body>/, "<body class=\"#{file_type}\">")
    File.write(html_file, modified_content, encoding: 'utf-8')
    BookBuild.log_success("#{html_file} にbodyクラス '#{file_type}' を設定しました")
  end
  
  # ポスト置換処理
  if File.exist?(BookBuild::POST_REPLACE_FILE)
    BookBuild.log_action("ポスト置換処理を実行中...")
    # 同一プロセス内でタスクを実行して、出力制御や例外伝播を一貫化
    Rake::Task['post_replace'].invoke
  end
  
  # Prism.jsの行番号を追加
  BookBuild.log_action("Prism.js行番号を追加中...")
  # 同一プロセス内でタスクを実行
  Rake::Task['prism:lines_all'].invoke

  BookBuild.log_success("HTML変換完了")
end

# ポスト置換処理 (vivliostyle markdown拡張の:::~:::のフェンス記法などを置換する)
desc "HTMLファイルのポスト置換処理を行います"
task :post_replace do |t, args|
    # コマンドライン引数を取得
  args    = BookBuild.process_args('post_replace')
  options = args[:options]
  return unless File.exist?(BookBuild::POST_REPLACE_FILE)
  
  # JSONファイルを読み込み
  json_content = File.read(BookBuild::POST_REPLACE_FILE, encoding: 'utf-8')
  replace_rules = JSON.parse(json_content)
  
  # JSONが配列でない場合はエラー
  unless replace_rules.is_a?(Array)
    BookBuild.log_error("エラー: JSONファイルは置換オブジェクトの配列を含む必要があります")
    return
  end
  
  html_files = Dir.glob("*.html")
  total_replacements = 0
  
  html_files.each do |html_file|
    BookBuild.log_action("処理中: #{html_file}")
    
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
        BookBuild.log_info("パターン '#{pattern_str}' → #{matches_found}個の置換")
      end
    end
    
    # 結果の出力と保存
    if html_content != original_content
      # HTMLファイルを上書き
      File.write(html_file, html_content, encoding: 'utf-8')
      total_replacements += file_replacements
      BookBuild.log_success("#{file_replacements}個の置換が行われました")
    end
  end
  
  BookBuild.log_success("ポスト置換処理完了 (合計: #{total_replacements}個の置換)")
end
