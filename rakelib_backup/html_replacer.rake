# HTML置換関連のタスク
require 'json'
require 'pathname'

namespace :html do
  desc "HTMLファイル内の特定パターンを置換します"
  task :replace, [:html_file, :json_file] do |t, args|
    # 引数の処理
    html_file = args[:html_file]
    # プロジェクトルート直下の_postReplaceList.jsonをデフォルトに設定
    project_root = File.expand_path(File.join(File.dirname(__FILE__), '..'))
    json_file = args[:json_file] || File.join(project_root, "_postReplaceList.json")
    
    # HTMLファイルが指定されていない場合はworkspaceディレクトリ内のすべてのHTMLファイルを処理する
    if html_file.nil? || html_file.empty?
      puts "ℹ️ HTMLファイルが指定されていません。workspaceディレクトリ内のすべてのHTMLファイルを処理します..."
      Rake::Task["html:replace_all"].invoke('workspace', json_file)
      return
    end

    # HTMLファイルの存在確認
    unless File.exist?(html_file)
      puts "❌ エラー: HTMLファイル '#{html_file}' が見つかりません"
      exit 1
    end

    # JSONファイルの存在確認
    unless File.exist?(json_file)
      puts "❌ エラー: JSONファイル '#{json_file}' が見つかりません"
      exit 1
    end
    
    begin
      # JSONファイルを読み込み
      json_content = File.read(json_file, encoding: 'utf-8')
      replacement_list = JSON.parse(json_content)
      
      # JSONが配列でない場合はエラー
      unless replacement_list.is_a?(Array)
        puts "❌ エラー: JSONファイルは置換オブジェクトの配列を含む必要があります"
        exit 1
      end
      
      puts "🔄 置換パターンを読み込んでいます: #{json_file}"
      puts "🔄 HTMLファイルを処理しています: #{html_file}"
      
      # HTMLファイルを読み込み
      html_content = File.read(html_file, encoding: 'utf-8')
      original_content = html_content.dup
      
      # 置換処理
      replacement_count = 0
      replacement_list.each_with_index do |item, index|
        unless item.is_a?(Hash) && item.key?('f') && item.key?('r')
          puts "⚠️ 警告: インデックス #{index} の置換項目が無効です、スキップします"
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
            replacement_count += matches_found
            puts "  パターン #{index + 1}: #{matches_found}個の置換が行われました"
          end
          
        rescue RegexpError => e
          puts "⚠️ 警告: インデックス #{index} の正規表現パターンが無効です: #{pattern_str}"
          puts "  エラー: #{e.message}"
        end
      end
      
      # 結果の出力
      if html_content != original_content
        # HTMLファイルを上書き
        File.write(html_file, html_content, encoding: 'utf-8')
        puts ""
        puts "✅ #{html_file} を正常に処理しました"
        puts "   合計置換回数: #{replacement_count}"
      else
        puts ""
        puts "ℹ️  #{html_file} での置換はありませんでした"
      end
      
    rescue JSON::ParserError => e
      puts "❌ エラー: #{json_file} のJSON形式が無効です"
      puts "  #{e.message}"
      exit 1
    rescue => e
      puts "❌ エラー: #{e.message}"
      exit 1
    end
  end
  
  desc "ディレクトリ内のすべてのHTMLファイルに対してパターン置換を実行します"
  task :replace_all, [:directory, :json_file] do |t, args|
    # 引数の処理
    directory = args[:directory] || "workspace"
    # プロジェクトルート直下の_postReplaceList.jsonをデフォルトに設定
    project_root = File.expand_path(File.join(File.dirname(__FILE__), '..'))
    json_file = args[:json_file] || File.join(project_root, "_postReplaceList.json")
    
    # ディレクトリの存在確認
    unless Dir.exist?(directory)
      puts "❌ エラー: ディレクトリ '#{directory}' が見つかりません"
      exit 1
    end
    
    # JSONファイルの存在確認
    unless File.exist?(json_file)
      puts "❌ エラー: JSONファイル '#{json_file}' が見つかりません"
      exit 1
    end
    
    puts "🔍 #{directory} 内のHTMLファイルを検索しています..."
    html_files = Dir.glob(File.join(directory, "*.html"))
    
    if html_files.empty?
      puts "⚠️ 警告: #{directory} 内にHTMLファイルが見つかりません"
      exit 0
    end
    
    puts "🔄 #{html_files.length}個のHTMLファイルを処理します..."
    
    # 各HTMLファイルを処理
    success_count = 0
    html_files.each do |html_file|
      begin
        Rake::Task["html:replace"].reenable
        Rake::Task["html:replace"].invoke(html_file, json_file)
        success_count += 1
      rescue => e
        puts "❌ #{html_file} の処理中にエラーが発生しました: #{e.message}"
      end
    end
    
    puts "\n処理結果:"
    puts "✅ #{success_count}/#{html_files.length}ファイルが正常に処理されました"
  end
end
