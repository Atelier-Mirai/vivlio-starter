require 'fileutils'
require 'json'
require 'yaml'

# 設定
CONTENT_DIR       = 'content'
STYLESHEETS_DIR   = 'stylesheets'
IMAGES_DIR        = 'images'
VFM_COMMAND       = 'vfm'
POST_REPLACE_FILE = '_postReplaceList.json'

# ファイルタイプを判定
def get_file_type(filename)
  case filename
  when /^00-/
    'preface'
  when /^01-toc/
    'toc'
  when /^1[1-9]-/, /^[2-8][0-9]-/
    'chapter'
  when /^9[1-7]-/
    'appendix'
  when /^98-/
    'postface'
  when /^99-colophon/
    'colophon'
  else
    'chapter'  # デフォルト
  end
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
      new_links.each do |new_link|
        unless existing_links.any? { |el| el['href'] == new_link['href'] }
          existing_links << new_link
        end
      end
    else
      # それ以外のプロパティは上書き
      merged_frontmatter[key] = value
    end
  end
  
  "---\n#{merged_frontmatter.to_yaml.sub(/^---\n/, '')}---\n\n"
end

# 画像パスを修正
def fix_image_paths(content, filename)
  # ファイル名から章番号を抽出
  chapter_dir = filename.sub(/\.md$/, '').sub(/^(\d+)-.*/, '\1-\2')
  
  # ![](image.png) -> ![](images/chapter/image.png) に変換
  content.gsub(/!\[\]\(([^)]+)\)/) do |match|
    image_file = $1
    next match if image_file.start_with?('http') || image_file.start_with?('images/')
    "![](images/#{chapter_dir}/#{image_file})"
  end
end

# プロジェクト初期化
desc "プロジェクトを初期化します"
task :init do
  puts "🔧 プロジェクトを初期化しています..."
  
  # 必要なディレクトリを作成
  [CONTENT_DIR, STYLESHEETS_DIR, IMAGES_DIR].each do |dir|
    FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
    puts "  ✅ #{dir}/ ディレクトリを確認しました"
  end
  
  # ルートの一時ファイルを削除
  ["*.html", "*.md"].each do |pattern|
    Dir.glob(pattern).each do |file|
      next if file == 'README.md' || file == 'design_policy.md'
      FileUtils.rm(file)
      puts "  🗑️  #{file} を削除しました"
    end
  end
  
  puts "✅ プロジェクト初期化完了"
end

# 前処理タスク
desc "Markdownファイルの前処理を行います"
task :preprocess do |t, args|
  # コマンドライン引数を取得
  files_arg = ARGV[1..-1]
  
  # タスク実行後に引数をクリアして他のタスクに影響しないようにする
  files_arg.each { |arg| task arg.to_sym do ; end }
  
  files = if files_arg.any?
    files_arg.map { |f| "#{CONTENT_DIR}/#{f}.md" }
  else
    Dir.glob("#{CONTENT_DIR}/*.md")
  end
  
  puts "🔄 前処理を開始しています..."
  
  files.each do |file_path|
    next unless File.exist?(file_path)
    
    filename = File.basename(file_path)
    base_name = filename.sub(/\.md$/, '')
    file_type = get_file_type(filename)
    
    puts "  📝 #{filename} を処理中..."
    
    # ファイル内容を読み込み
    content = File.read(file_path, encoding: 'utf-8')
    
    # 既存のフロントマターを抽出し、併合する
    existing_frontmatter = {}
    content_without_frontmatter = content
    
    if content =~ /^---\n(.*?)\n---\n\n/m
      frontmatter_yaml = $1
      begin
        existing_frontmatter = YAML.load(frontmatter_yaml) || {}
        puts "    🔍 既存のフロントマターを登録: #{existing_frontmatter.keys.join(', ')}"
        content_without_frontmatter = content.sub(/^---\n.*?\n---\n\n/m, '')
      rescue => e
        puts "    ⚠️ フロントマターのパースに失敗しました: #{e.message}"
      end
    end
    
    content = content_without_frontmatter
    
    # 画像パスを修正
    content = fix_image_paths(content, filename)
    
    # 章番号を抽出（チャプター用CSS）
    chapter_num = filename.match(/^(\d+)-/) ? $1 : nil
    
    # フロントマターを追加（既存のフロントマターと併合）
    frontmatter = generate_frontmatter(file_type, chapter_num, existing_frontmatter)
    processed_content = frontmatter + content
    
    # プロジェクトルートに出力
    output_path = filename
    File.write(output_path, processed_content, encoding: 'utf-8')
    
    puts "    ✅ #{output_path} に出力しました"
  end
  
  puts "✅ 前処理完了"
end

# Markdown→HTML変換
desc "MarkdownファイルをHTMLに変換します"
task :convert do |t, args|
  # コマンドライン引数を取得
  files_arg = ARGV[1..-1]
  
  # タスク実行後に引数をクリアして他のタスクに影響しないようにする
  files_arg.each { |arg| task arg.to_sym do ; end }
  
  files = if files_arg.any?
    files_arg.map { |f| "#{f}.md" }
  else
    Dir.glob("*.md").reject { |f| f == 'README.md' || f == 'design_policy.md' }
  end
  
  puts "🔄 Markdown→HTML変換を開始しています..."
  
  files.each do |md_file|
    next unless File.exist?(md_file)
    
    html_file = md_file.sub(/\.md$/, '.html')
    
    puts "  📄 #{md_file} → #{html_file}"
    
    # vfmコマンドで変換
    system("#{VFM_COMMAND} #{md_file} > #{html_file}")
    
    if $?.success?
      puts "    ✅ 変換完了"
    else
      puts "    ❌ 変換失敗"
    end

    # ファイル名からファイルタイプを取得
    file_type = get_file_type(File.basename(md_file))
    
    # HTMLファイルを読み込み
    content = File.read(html_file, encoding: 'utf-8')
    
    # bodyタグにクラスを追加して保存
    modified_content = content.gsub(/<body>/, "<body class=\"#{file_type}\">")
    File.write(html_file, modified_content, encoding: 'utf-8')
    puts "    ✅ #{html_file} にbodyクラス '#{file_type}' を設定しました"
  end
  
  # ポスト置換処理
  if File.exist?(POST_REPLACE_FILE)
    puts "  🔧 ポスト置換処理を実行中..."
    Rake::Task['post_replace'].invoke
  end
  
  puts "✅ HTML変換完了"
end

# ポスト置換処理
desc "HTMLファイルのポスト置換処理を行います"
task :post_replace do
  return unless File.exist?(POST_REPLACE_FILE)
  
  replace_rules = JSON.parse(File.read(POST_REPLACE_FILE))
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

# CSS関連タスク
namespace :css do
  desc "章ごとのCSSファイルを生成します"
  task :chapter do |t, args|
  puts "🎨 章ごとのCSSファイルを生成しています..."
  
  # Markdownファイルの一覧を取得
  md_files = Dir.glob("#{CONTENT_DIR}/*.md")
  
  # 章タイプのファイルを抜き出し、章番号を取得
  chapter_numbers = md_files.map do |file_path|
    filename = File.basename(file_path)
    file_type = get_file_type(filename)
    
    if file_type == 'chapter'
      filename =~ /^(\d+)-/ ? $1 : nil
    else
      nil
    end
  end.compact.uniq
  
  # CSSディレクトリが存在するか確認
  unless Dir.exist?(STYLESHEETS_DIR)
    FileUtils.mkdir_p(STYLESHEETS_DIR)
    puts "  📂 #{STYLESHEETS_DIR} ディレクトリを作成しました"
  end
  
  # 章ごとのCSSファイルを生成
  chapter_numbers.each do |chapter_num|
    css_filename = "#{STYLESHEETS_DIR}/#{chapter_num}.css"
    
    # 既存のファイルがない場合のみ生成
    unless File.exist?(css_filename)
      css_content = <<~CSS
        @charset "utf-8";
        
        /* 第#{chapter_num.to_i - 10}章用スタイル */
        
        /* 章番号を設定 */
        :root {
          counter-reset: chapter-counter #{chapter_num.to_i - 10};
        }
        
        /* 章固有のスタイルをここに追加 */
        
      CSS
      
      File.write(css_filename, css_content, encoding: 'utf-8')
      puts "  ✅ #{css_filename} を生成しました"
    else
      puts "  ℹ️ #{css_filename} は既に存在します"
    end
  end
  
  puts "✅ 章ごとのCSSファイル生成完了"
  end
end

# TOC生成
desc "目次HTMLを生成します"
task :toc do
  puts "📚 目次を生成しています..."
  
  require 'nokogiri'
  
  result = <<~MD
          ---
          link: 
            - rel: "stylesheet"
              href: "stylesheets/toc.css"
          lang: 'ja'
          ---

          ## 目次
          <nav id="toc" role="doc-toc">

  MD

  # プロジェクトルート内の「01-toc.html以外の.htmlファイル」を列挙
  Dir.glob('*.html').reject { |file| file == '01-toc.html' }.sort.each do |target|
    content = File.read(target, encoding: 'utf-8')
    doc     = Nokogiri::HTML(content)
    
    # 本文なら、h1, h2, h3を取得
    if get_file_type(target) == 'chapter'
      elems = doc.css('h1, h2, h3')
    else
      elems = doc.css('h1')
    end
    
    elems.each do |elem|
      id = elem['id']
      text = elem.text.strip
      
      case elem.name
      when 'h1'
        result += %{- <a class="toc-chapter" href="#{target}##{id}">}
        result += text + "</a>\n"
      when 'h2'
        result += '  '  # 2スペース
        result += %{- <a class="toc-section" href="#{target}##{id}">}
        result += text + "</a>\n"
      when 'h3'
        result += '    '  # 4スペース
        result += %{- <a class="toc-subsection" href="#{target}##{id}">}
        result += text + "</a>\n"
      end
    end
  end

  result += "\n</nav>"
  
  # Markdownファイルとして保存
  File.write('01-toc.md', result, encoding: 'utf-8')
  
  # VFMで変換
  system("#{VFM_COMMAND} 01-toc.md > 01-toc.html")
  
  puts "✅ 目次生成完了"
end

# entries.js生成
desc "entries.jsを自動生成します"
task :entries do |t, args|
  puts "📋 entries.jsを生成しています..."
  
  # コマンドライン引数を取得
  files_arg = ARGV[1..-1]
  
  # 引数が指定された場合は、それらのファイルのみを処理
  html_files = if files_arg.any?
    puts "  🔍 指定されたファイルのみ処理します: #{files_arg.join(', ')}"
    files_arg.map { |f| "#{f}.html" }.select { |f| File.exist?(f) }
  else
    # 引数がない場合は全HTMLファイルを処理
    Dir.glob("*.html").sort
  end
  
  puts "  📄 処理対象ファイル: #{html_files.join(', ')}"
  entries = []
  
  html_files.each do |html_file|
    # HTMLファイルからタイトルを抽出
    content = File.read(html_file, encoding: 'utf-8')
    title_match = content.match(/<title>(.*?)<\/title>/i) || 
                  content.match(/<h1[^>]*>(.*?)<\/h1>/i)
    
    title = title_match ? title_match[1].strip : File.basename(html_file, '.html')
    
    entries << {
      'path' => html_file,
      'title' => title
    }
  end
  
  entries_content = "export default #{JSON.pretty_generate(entries)};\n"
  File.write('entries.js', entries_content, encoding: 'utf-8')
  
  puts "✅ entries.js生成完了: #{entries.size}件のエントリを登録"
end

# 画像ディレクトリ生成
desc "画像ディレクトリを生成します"
task :images do
  puts "🖼️  画像ディレクトリを生成しています..."
  
  # content/以下のMarkdownファイルから必要な画像ディレクトリを抽出
  md_files = Dir.glob("#{CONTENT_DIR}/*.md")
  
  md_files.each do |md_file|
    filename = File.basename(md_file)
    chapter_dir = filename.sub(/\.md$/, '').sub(/^(\d+)-.*/, '\1-\2')
    image_dir = "#{IMAGES_DIR}/#{chapter_dir}"
    
    unless Dir.exist?(image_dir)
      FileUtils.mkdir_p(image_dir)
      puts "  ✅ #{image_dir}/ を作成しました"
    end
  end
  
  puts "✅ 画像ディレクトリ生成完了"
end

# PDF生成
desc "PDFを生成します"
task :pdf do |t, args|
  puts "📖 PDFを生成しています..."
  
  # コマンドライン引数を取得
  files_arg = ARGV[1..-1]
  
  # タスク実行後に引数をクリアして他のタスクに影響しないようにする
  files_arg.each { |arg| task arg.to_sym do ; end }
  
  # Vivliostyle Build
  puts "  🔧 Vivliostyle Build実行中..."
  
  if files_arg.any?
    # 指定されたファイルのみビルド
    html_files = files_arg.map { |f| "#{f}.html" }.join(' ')
    system("npx vivliostyle build #{html_files}")
    puts "  🔍 指定ファイルのみビルド: #{files_arg.join(', ')}"
  else
    # すべてのファイルをビルド
    system('npx vivliostyle build')
  end
  
  if $?.success?
    puts "  ✅ PDF生成完了"
  else
    puts "  ❌ PDF生成失敗"
  end
end

# ビルドタスク
desc "書籍をビルドします"
task :build => [:preprocess, :convert, 'css:chapter', :toc, :entries, :pdf] do
  puts "✅ ビルド完了"
end

# 単体ビルドタスク
desc "指定されたファイルのみをビルドします"
task :build_files do |t, args|
  puts "📚 指定ファイルをビルドしています..."
  
  # コマンドライン引数を取得
  files_arg = ARGV[1..-1]
  
  # タスク実行後に引数をクリアして他のタスクに影響しないようにする
  files_arg.each { |arg| task arg.to_sym do ; end }
  
  # 前処理→変換→章ごとCSS生成→目次生成→entries.js生成→PDF生成の流れ
  if files_arg.any?
    # 指定されたファイルのみ処理
    puts "  🔍 指定されたファイルのみ処理します: #{files_arg.join(', ')}"
    Rake::Task['preprocess'].invoke(*files_arg)
    Rake::Task['convert'].invoke(*files_arg)
    
    # 章ファイルの場合は章ごとのCSSも生成
    chapter_files = files_arg.select do |f|
      file_type = get_file_type("#{f}.md")
      file_type == 'chapter'
    end
    
    if chapter_files.any?
      Rake::Task['css:chapter'].invoke
    end
    
    # entries.jsを更新
    Rake::Task['entries'].invoke(*files_arg)
    
    # PDF生成
    Rake::Task['pdf'].invoke
    
    puts "  ✅ 指定ファイルのビルド完了"
  else
    # 引数がない場合は通常のビルドタスクを実行
    puts "  ℹ️ 引数が指定されていません。通常のビルドを実行します。"
    Rake::Task['build'].invoke
  end
end

# PDFを開く
desc "生成された PDF を開きます"
task :open => 'open:pdf'

namespace :open do
  desc "生成された PDF を開きます"
  task :pdf do
    pdf_path = 'output.pdf'
    if File.exist?(pdf_path)
      puts "📘 ビルド成功！PDF を開いています..."
      # 既存のPDFウィンドウを閉じてから開く
      system('osascript -e \'tell application "Preview" to close every window\' 2>/dev/null')
      system("open -a Preview #{pdf_path}")
      
      # Previewウィンドウを画面右側に配置
      system <<~APPLE_SCRIPT
        osascript -e '
          tell application "Preview"
            activate
            set bounds of front window to {3072, 0, 4096, 2160}
          end tell'
      APPLE_SCRIPT
    else
      puts "⚠️ ビルドは完了しましたが、PDF ファイルが見つかりません！"
    end
  end
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

# 全体ビルド（デフォルトタスク）
desc "全体ビルドを実行します（前処理→変換→PDF生成→クリーンアップ）"
task :default => [:build]

puts "📚 電気・電子技術への招待 - Build System"
puts "利用可能なタスク:"
puts "  rake init                   - プロジェクト初期化"
puts "  rake preprocess              - 前処理（全ファイル）"
puts "  rake preprocess <files...>   - 前処理（指定ファイル）"
puts "  rake convert                - HTML変換（全ファイル）"
puts "  rake convert <files...>      - HTML変換（指定ファイル）"
puts "  rake toc                    - 目次生成"
puts "  rake entries                - entries.js生成"
puts "  rake images                 - 画像ディレクトリ生成"
puts "  rake copy_resources         - リソースコピー"
puts "  rake build                  - PDF生成（全ファイル）"
puts "  rake build <files...>        - PDF生成（指定ファイル）"
puts "  rake clean                  - クリーンアップ"
puts ""
