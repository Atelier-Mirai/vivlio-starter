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

# 簡易Markdown→HTML 変換（Kramdownがあれば使用、なければ最小限の置換）
def render_markdown_to_html(md_text)
  # まずはKramdownを試す
  begin
    require 'kramdown'
    return Kramdown::Document.new(md_text).to_html
  rescue LoadError
    # フォールバック: 最小限のMarkdownをHTMLへ（画像/太字/番号リスト/段落）
    lines = md_text.to_s.split(/\r?\n/)
    html_parts = []
    in_ol = false
    buffer_p = []

    flush_p = lambda do
      unless buffer_p.empty?
        paragraph = buffer_p.join(" ").strip
        html_parts << "<p>#{paragraph}</p>" unless paragraph.empty?
        buffer_p.clear
      end
    end

    lines.each do |line|
      if line.strip.empty?
        flush_p.call
        next
      end

      # 画像: ![](path)
      if m = line.match(/^\s*!\[[^\]]*\]\(([^)]+)\)\s*$/)
        flush_p.call
        src = m[1]
        html_parts << "<img src=\"#{src}\">"
        next
      end

      # 見出し相当の太字行: **Title**
      if m = line.match(/^\s*\*\*(.+?)\*\*\s*$/)
        flush_p.call
        html_parts << "<p><strong>#{m[1]}</strong></p>"
        next
      end

      # 番号リスト: 1. text
      if m = line.match(/^\s*(\d+)\.\s+(.*)$/)
        flush_p.call
        html_parts << "<ol>" unless in_ol
        in_ol = true
        html_parts << "<li>#{m[2]}</li>"
        next
      else
        if in_ol
          html_parts << "</ol>"
          in_ol = false
        end
      end

      # 既存の <br> はそのまま許容
      buffer_p << line
    end

    flush_p.call
    html_parts << "</ol>" if in_ol
    html_parts.join("\n")
  end
end

# book-card 内のMarkdownを事前整形（画像行/太字行の直後に空行を補う）
def normalize_book_card_md(md_text)
  lines = md_text.to_s.split(/\r?\n/, -1) # 末尾の空行も保持
  out = []
  lines.each_with_index do |line, i|
    out << line
    next_line = lines[i + 1]

    # 画像のみの行の直後に空行を補う
    if line.match(/^\s*!\[[^\]]*\]\([^)]+\)\s*$/)
      if next_line && next_line.strip != ""
        out << ""
      end
    # 太字のみの行の直後に空行を補う
    elsif line.match(/^\s*\*\*[^*].*\*\*\s*$/)
      if next_line && next_line.strip != ""
        out << ""
      end
    end
  end
  out.join("\n")
end

# <div class="book-card"> ... </div> の内側MarkdownをHTMLへ
def convert_book_card_inner_markdown(content)
  content.gsub(/<div class=\"book-card\">\n(.*?)\n<\/div>/m) do
    inner = $1
    normalized = normalize_book_card_md(inner)
    html = render_markdown_to_html(normalized)
    formatted = format_book_card_inner_html(html)
    "<div class=\"book-card\">\n#{formatted}\n</div>"
  end
end

# book-card の中身を、カード表示しやすいよう整形 (画像、タイトル、説明文)
# components.css参照
def format_book_card_inner_html(inner_html)
  html = inner_html.to_s.strip

  # 1) 画像タグを抽出 (<p>で囲まれていてもOK)
  img_match = html.match(/<img[^>]*>/i)
  return inner_html unless img_match
  img_tag = img_match[0]

  # <img ... /> を <img ...> に寄せる（置換例に合わせる）
  img_tag = img_tag.gsub(/\s*\/?>/i) { |m| '>' }

  # 画像のみの<p>ラッパーを除去、それが無ければ素の<img>を除去
  if html.sub!(/<p>\s*#{Regexp.escape(img_match[0])}\s*<\/p>/i, '')
    # removed wrapped <p> with img
  else
    html.sub!(img_match[0], '')
  end

  # 2) タイトル (<p><strong>...</strong></p>) を抽出
  title_match = html.match(/<p>\s*<strong>(.*?)<\/strong>\s*<\/p>/im)
  return inner_html unless title_match
  title_text = title_match[1].strip
  html.sub!(title_match[0], '')

  # 3) 残りを説明HTMLとする
  description_html = html.strip

  # 4) 目標の構造で出力
  parts = []
  parts << "  #{img_tag}"
  parts << "  <div class=\"book-info\">"
  parts << "    <p class=\"book-title\">#{title_text}</p>"
  parts << "    <div class=\"book-description\">"
  parts << "      #{description_html}"
  parts << "    </div>"
  parts << "  </div>"
  parts.join("\n")
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

  # 画像参照を統一
  # 1) 相対参照は images/<chapter>/ を前置
  # 2) 拡張子 .png/.jpg/.jpeg は .webp に変換
  content.gsub(/!\[(.*?)\]\((?!https?:\/\/)([^)]+)\)/) do
    alt_text  = $1
    image_path = $2

    # 章ディレクトリの付与（既に images/ 始まりならそのまま）
    normalized = if image_path.start_with?('images/')
                   image_path
                 else
                   "images/#{chapter_dir}/#{image_path}"
                 end

    # 拡張子を .webp へ
    normalized = normalized.sub(/\.(png|jpe?g)\z/i, '.webp')

    "![#{alt_text}](#{normalized})"
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
task :pre_process do |t, args|
  # コマンドライン引数を取得
  args = BookBuild.process_args('pre_process')
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

    # .book-card マークダウンブロックのみを事前にHTMLの<div>に変換（行走査・状態管理）
    # 注意: HTMLブロック内ではMarkdownは解釈されません。意図通りの仕様です。
    BookBuild.log_action("book-cardブロックをHTMLのdivに変換中...")
    in_book_card = false
    opened_count = 0
    closed_count = 0
    converted_lines = content.lines.map do |line|
      if line.match(/^\s*:::\{\.book-card\}\s*$/)
        in_book_card = true
        opened_count += 1
        "<div class=\"book-card\">\n"
      elsif in_book_card && line.match(/^\s*:::\s*$/)
        in_book_card = false
        closed_count += 1
        "</div>\n"
      else
        line
      end
    end
    content = converted_lines.join
    BookBuild.log_success("book-cardブロックの事前変換 完了 開始:#{opened_count} 終了:#{closed_count}")

    # book-card の内側に残る素のMarkdownをHTMLへ変換
    BookBuild.log_action("book-card内のMarkdownをHTMLへ変換中...")
    content = convert_book_card_inner_markdown(content)
    BookBuild.log_success("book-card内MarkdownのHTML化 完了")

    # 処理後のファイルを保存
    File.write(output_file, content, encoding: 'utf-8')
    BookBuild.log_success("保存完了")
  end
  
  BookBuild.log_success("Markdown前処理完了")
end
