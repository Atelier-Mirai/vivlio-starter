require_relative 'common'
require 'yaml'

# 拡張子→言語の対応表
EXT_TO_LANG = {
  'c'    => 'c',
  'cc'   => 'cpp',
  'cpp'  => 'cpp',
  'cs'   => 'csharp',
  'css'  => 'css',
  'cxx'  => 'cpp',
  'go'   => 'go',
  'html' => 'html',
  'java' => 'java',
  'js'   => 'javascript',
  'json' => 'json',
  'kt'   => 'kotlin',
  'md'   => 'markdown',
  'php'  => 'php',
  'py'   => 'python',
  'rb'   => 'ruby',
  'rs'   => 'rust',
  'scala'=> 'scala',
  'scss' => 'scss',
  'sh'   => 'bash',
  'sql'  => 'sql',
  'swift'=> 'swift',
  'ts'   => 'typescript',
  'xml'  => 'xml',
  'yaml' => 'yaml',
  'yml'  => 'yaml'
}.freeze

# ファイル拡張子から言語を推定
def detect_language(file_path)
  ext = File.extname(file_path).downcase.delete_prefix('.')
  EXT_TO_LANG.fetch(ext, 'text')
end

# フロントマターを生成
def generate_frontmatter(file_type, chapter_num = nil, existing_frontmatter = {})
  # ファイルタイプに対応する基本スタイルシート
  stylesheets = ["#{file_type}.css"]

  # チャプター固有のCSSを追加
  if file_type == 'chapter' && chapter_num
    stylesheets << "#{chapter_num}.css"
  end
  
  # 新しいフロントマターのベースを作成
  new_frontmatter = {
    'link' => stylesheets.map { |css| 
      { 'rel' => 'stylesheet', 'href' => "stylesheets/#{css}" }
    },
    'lang' => 'ja'
  }
  
  # 既存のフロントマターと新しいフロントマターを併合
  merged_frontmatter = {}
  
  # 既存のフロントマターをベースにする
  merged_frontmatter = existing_frontmatter.dup
  
  # 新しいフロントマターを適用
  new_frontmatter.each do |key, value|
    if key == 'link' && merged_frontmatter['link']
      # linkは配列なので特別処理
      # 既存のリンクを保持しつつ、新しいリンクを追加
      existing_links = merged_frontmatter['link']
      new_links = value
      
      # 重複しないようにマージ
      merged_frontmatter['link'] = existing_links + new_links.reject { |new_link|
        existing_links.any? { |existing_link|
          existing_link['href'] == new_link['href']
        }
      }
    else
      # その他のキーは上書き
      merged_frontmatter[key] = value
    end
  end
  
  merged_frontmatter
end

# 画像パスを修正
def fix_image_paths(content, filename)
  chapter_dir = filename.sub(/\.md$/, '')
  
  # ![alt](image.jpg) → ![alt](images/11-chapter/image.jpg)
  content.gsub(/!\[(.*?)\]\((?!https?:\/\/)(.*?)\)/) do
    alt_text = $1
    image_path = $2
    
    # 既に images/ で始まる場合はそのまま
    if image_path.start_with?('images/')
      "![#{alt_text}](#{image_path})"
    else
      "![#{alt_text}](images/#{chapter_dir}/#{image_path})"
    end
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
    
    BookBuild.log_action("マッチ発見: #{match.strip}")
    BookBuild.log_info("元のパス: #{original_path}")
    
    # 相対パスの場合、CODES_DIRを補完
    file_path = if original_path.start_with?('/')
                  original_path
                else
                  File.join(BookBuild::CODES_DIR, original_path)
                end
    BookBuild.log_info("解決されたパス: #{file_path}")
    
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
      BookBuild.log_success("置換完了: #{original_path} (#{language})")
      
      replacement
    else
      BookBuild.log_error("ファイルが見つかりません: #{file_path}")
      match # 元のテキストをそのまま返す
    end
  end
  
  BookBuild.log_info("#{matches_found}個のinclude記法を処理") if matches_found > 0
  content
end

# 前処理関連タスク
desc "Markdownファイルの前処理を行います"
task :preprocess do |t, args|
  # コマンドライン引数を取得
  args = BookBuild.process_args('preprocess')
  files = args[:files]
  options = args[:options]
  
  # 処理対象のファイルを決定
  md_files = if files.any?
    # 存在しないファイルをチェック
    missing_files = files.reject { |f| File.exist?("#{BookBuild::CONTENTS_DIR}/#{f}.md") }
    if missing_files.any?
      BookBuild.log_error("エラー: 次のファイルが存在しません: #{missing_files.join(', ')}")
      BookBuild.log_warn("前処理を中止します")
      exit(1)
    end
    
    files.map { |f| "#{BookBuild::CONTENTS_DIR}/#{f}.md" }
  else
    # 引数がない場合は全Markdownファイルを処理
    Dir.glob("#{BookBuild::CONTENTS_DIR}/*.md")
  end
  
  # ファイル引数をタスクとして実行されないようにダミータスクを作成
  files.each { |arg| task arg.to_sym do ; end }
  
  # 各Markdownファイルを処理
  BookBuild.log_action("Markdownファイルの前処理を行っています...")
  md_files.each do |md_file|
    filename = File.basename(md_file)
    output_file = filename  # プロジェクトルートに出力
    
    BookBuild.log_info("#{md_file} → #{output_file}")
    
    # ファイルの内容を読み込み
    content = File.read(md_file, encoding: 'utf-8')
    
    # ファイルタイプを判定
    file_type = BookBuild.get_file_type(filename)
    # ファイル名から章番号を抽出
    chapter_num = BookBuild.get_chapter_number(filename)
    
    # フロントマターを処理
    if content.start_with?('---')
      # 既存のフロントマターを抽出
      frontmatter_match = content.match(/\A---\n(.*?)\n---\n/m)
      
      if frontmatter_match
        frontmatter_yaml = frontmatter_match[1]
        begin
          existing_frontmatter = YAML.safe_load(frontmatter_yaml) || {}
          
          # 新しいフロントマターを生成して併合
          merged_frontmatter = generate_frontmatter(file_type, chapter_num, existing_frontmatter)
          
          # YAMLに変換
          new_frontmatter_yaml = YAML.dump(merged_frontmatter)
          BookBuild.log_success("フロントマター併合")

          # フロントマターを置換
          content = content.sub(/\A---\n.*?\n---\n/m, "#{new_frontmatter_yaml}---\n")

          BookBuild.log_success("フロントマター更新")
        rescue => e
          # 行・列情報を取得（Psych::SyntaxError は line/column を持つ）
          line = (e.respond_to?(:line) && e.line) ? e.line.to_i : (e.message[/line (\d+)/i, 1]&.to_i)
          column = (e.respond_to?(:column) && e.column) ? e.column.to_i : (e.message[/column (\d+)/i, 1]&.to_i)

          if line && line > 0
            BookBuild.log_warn("フロントマター（--- ～ ---）の記述に誤りがあります（位置: 行#{line} 列#{column && column > 0 ? column : '?'}）。内容を見直してください。")
          else
            BookBuild.log_warn("フロントマター（--- ～ ---）の記述に誤りがあります。内容を見直してください。")
          end

          # 問題箇所の抜粋とキャレット表示
          begin
            fm_lines = frontmatter_yaml.to_s.lines
            if line && line > 0 && line <= fm_lines.length
              idx = line - 1
              start = [idx - 2, 0].max
              finish = [idx + 2, fm_lines.length - 1].min
              snippet = fm_lines[start..finish].each_with_index.map { |l, i2| "#{start + i2 + 1}: #{l.chomp}" }.join("\n")
              err_line_text = fm_lines[idx].to_s.chomp
              caret_line = (column && column > 0) ? (" " * (column - 1) + "^") : ""
              BookBuild.log_info("問題のフロントマター（抜粋）:\n---\n#{snippet}\n---\n該当行:\n#{err_line_text}\n#{caret_line}")
            else
              BookBuild.log_info("問題のフロントマター（抜粋）:\n---\n#{frontmatter_yaml}\n---")
            end
          rescue => _ignore
            BookBuild.log_info("問題のフロントマター（抜粋）:\n---\n#{frontmatter_yaml}\n---")
          end
        end
      end
    else
      # フロントマターがない場合は追加
      new_frontmatter = generate_frontmatter(file_type, chapter_num)
      new_frontmatter_yaml = YAML.dump(new_frontmatter)

      content = "#{new_frontmatter_yaml}---\n\n#{content}"
      BookBuild.log_success("フロントマター追加")
    end
    
    # 画像パスを修正
    content = fix_image_paths(content, filename)
    BookBuild.log_success("画像パス修正 #{filename}")
    
    # ソースコードを取り込む
    BookBuild.log_action("ソースコード読み込み記法をスキャン中...")
    content = process_code_include(content)
    BookBuild.log_success("ソースコード読み込み処理完了")

    # 処理後のファイルを保存
    File.write(output_file, content, encoding: 'utf-8')
    BookBuild.log_success("保存完了")
  end
  
  BookBuild.log_success("Markdown前処理完了")
end
