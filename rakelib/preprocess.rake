require_relative 'common'
require 'yaml'

# ファイル拡張子から言語を推定
def detect_language(file_path)
  ext = File.extname(file_path).downcase
  case ext
  when '.js' then 'javascript'
  when '.ts' then 'typescript'
  when '.py' then 'python'
  when '.rb' then 'ruby'
  when '.java' then 'java'
  when '.cpp', '.cc', '.cxx' then 'cpp'
  when '.c' then 'c'
  when '.cs' then 'csharp'
  when '.php' then 'php'
  when '.go' then 'go'
  when '.rs' then 'rust'
  when '.swift' then 'swift'
  when '.kt' then 'kotlin'
  when '.scala' then 'scala'
  when '.sh' then 'bash'
  when '.sql' then 'sql'
  when '.html' then 'html'
  when '.css' then 'css'
  when '.scss' then 'scss'
  when '.json' then 'json'
  when '.yaml', '.yml' then 'yaml'
  when '.xml' then 'xml'
  when '.md' then 'markdown'
  else 'text'
  end
end

# ソースコード読み込み処理
def process_code_include(content)
  matches_found = 0
  
  content.gsub!(/```include:([^:`\s]+)(?::(\d+)-(\d+))?\s*```/) do |match|
    matches_found += 1
    original_path = $1
    start_line = $2&.to_i
    end_line = $3&.to_i
    
    puts "    ⚙️  マッチ発見: #{match.strip}"
    puts "    📁 元のパス: #{original_path}"
    
    # 相対パスの場合、CODES_DIRを補完
    file_path = if original_path.start_with?('/')
                  original_path
                else
                  File.join(BookBuild::CODES_DIR, original_path)
                end
    puts "    📂 解決されたパス: #{file_path}"
    
    if File.exist?(file_path)
      source_content = File.read(file_path)
      lines = source_content.lines
      
      # 行範囲が指定されている場合
      if start_line && end_line
        selected_lines = lines[(start_line-1)..(end_line-1)]
        code_content = selected_lines.join
      else
        code_content = source_content + "\n"
      end
      
      # 言語を推定
      language = detect_language(file_path)
      
      # コードブロックを生成（ファイル名を保持）
      replacement = "```#{language}:#{original_path}\n#{code_content}```"
      puts "    ✅ 置換完了: #{original_path} (#{language})"
      
      replacement
    else
      puts "    ❌ ファイルが見つかりません: #{file_path}"
      match # 元のテキストをそのまま返す
    end
  end
  
  puts "    🔍 #{matches_found}個のinclude記法を処理" if matches_found > 0
  content
end

# 前処理関連タスク
desc "Markdownファイルの前処理を行います"
task :preprocess do
  # ARGV から引数を取得（最初の要素 'preprocess' をスキップ）
  files_arg = ARGV.drop(1)
  
  # 処理対象のファイルを決定
  md_files = if files_arg.any?
    # 存在しないファイルをチェック
    missing_files = files_arg.reject { |f| File.exist?("#{BookBuild::CONTENTS_DIR}/#{f}.md") }
    if missing_files.any?
      puts "  ⚠️ エラー: 次のファイルが存在しません: #{missing_files.join(', ')}"
      puts "  ❗ ビルドを中止します"
      exit(1)
    end
    
    files_arg.map { |f| "#{BookBuild::CONTENTS_DIR}/#{f}.md" }
  else
    # 引数がない場合は全Markdownファイルを処理
    Dir.glob("#{BookBuild::CONTENTS_DIR}/*.md")
  end
  
  # ARGV の残りの引数をタスクとして実行されないようにする
  files_arg.each { |arg| task arg.to_sym do ; end }
  
  # 各Markdownファイルを処理
  puts "📝 Markdownファイルの前処理を行っています..."
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
          puts "    ✅ フロントマター併合"
          puts new_frontmatter_yaml


          # フロントマターを置換
          content = content.sub(/\A---\n.*?\n---\n/m, "#{new_frontmatter_yaml}---\n")

          puts "    ✅ フロントマター更新"
        rescue => e
          puts "    ⚠️ フロントマターのパースに失敗しました: #{e.message}"
        end
      end
    else
      # フロントマターがない場合は追加
      new_frontmatter = BookBuild.generate_frontmatter(file_type, chapter_num)
      new_frontmatter_yaml = YAML.dump(new_frontmatter)

      content = "#{new_frontmatter_yaml}---\n\n#{content}"
      puts "    ✅ フロントマター追加"
      puts new_frontmatter_yaml
    end
    
    # 画像パスを修正
    content = BookBuild.fix_image_paths(content, filename)
    puts "    ✅ 画像パス修正 #{filename}"
    
    # ソースコードを取り込む
    puts "    🔍 ソースコード読み込み記法をスキャン中..."
    content = process_code_include(content)
    puts "    ✅ ソースコード読み込み処理完了"

    # 処理後のファイルを保存
    File.write(output_file, content, encoding: 'utf-8')
    puts "    ✅ 保存完了"
  end
  
  puts "✅ Markdown前処理完了"
end
