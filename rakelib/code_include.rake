# ソースコード読み込み機能
# 記法: ```include:path/to/file.js```
# 記法: ```include:path/to/file.js:10-20``` (行範囲指定)

require_relative 'common'

namespace :code do
  desc "Markdownファイル内の外部ソースコード読み込み記法を処理"
  task :include do
    puts "📝 外部ソースコード読み込み処理を開始..."
    
    # 処理対象のMarkdownファイルを取得（CONTENTS_DIR傘下）
    md_files = Dir.glob("#{BookBuild::CONTENTS_DIR}/*.md")
    
    md_files.each do |file|
      puts "  📄 処理中: #{file}"
      content = File.read(file)
      
      # ```include:path``` パターンを検索・置換
      puts "    🔍 ファイル内容をスキャン中..."
      
      # より柔軟な正規表現パターンを使用
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
            code_content = source_content
          end
          
          # ファイル拡張子から言語を推定
          language = detect_language(file_path)
          
          # コードブロックとして整形（ファイル名を含む）
          filename = File.basename(original_path)
          "```#{language}:#{filename}\n#{code_content}```"
        else
          puts "    ⚠️  ファイルが見つかりません: #{file_path}"
          match # 元のまま
        end
      end
      
      puts "    📊 マッチ数: #{matches_found}件"
      
      # ファイルに書き戻し（プロジェクトルートに出力）
      output_file = File.basename(file)
      File.write(output_file, content)
      puts "    ✅ 処理完了"
    end
    
    puts "✅ 外部ソースコード読み込み処理完了"
  end
end

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

# メインビルドタスクに組み込み
task :preprocess => 'code:include'
