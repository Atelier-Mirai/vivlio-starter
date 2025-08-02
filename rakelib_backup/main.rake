require 'fileutils'
require 'json'
require 'yaml'

# 設定
CONTENT_DIR = 'content'
STYLESHEETS_DIR = 'stylesheets'
IMAGES_DIR = 'images'
WORKSPACE_DIR = 'workspace'  # 削除予定
VFM_COMMAND = 'vfm'
POST_REPLACE_FILE = '_postReplaceList.json'

# ファイルタイプ別のスタイルシート設定
FRONTMATTER_CONFIG = {
  'preface' => ['matter.css'],
  'postface' => ['matter.css'],
  'toc' => ['toc.css'],
  'chapter' => ['body.css'],
  'appendix' => ['appendix.css'],
  'colophon' => ['colophon.css']
}

# ファイルタイプを判定
def get_file_type(filename)
  case filename
  when /^00-/, /^98-/
    'preface'
  when /^01-toc/
    'toc'
  when /^1[1-9]-/, /^[2-8][0-9]-/
    'chapter'
  when /^9[1-7]-/
    'appendix'
  when /^99-colophon/
    'colophon'
  else
    'chapter'  # デフォルト
  end
end

# フロントマターを生成
def generate_frontmatter(file_type, chapter_num = nil)
  stylesheets = FRONTMATTER_CONFIG[file_type].dup
  
  # チャプター固有のCSSを追加
  if file_type == 'chapter' && chapter_num
    stylesheets << "#{chapter_num}.css"
  end
  
  frontmatter = {
    'link' => stylesheets.map { |css| 
      { 'rel' => 'stylesheet', 'href' => "stylesheets/#{css}" }
    },
    'lang' => 'ja'
  }
  
  "---\n#{frontmatter.to_yaml.sub(/^---\n/, '')}---\n\n"
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
  
  # workspaceディレクトリを削除（設計方針に従い）
  if Dir.exist?(WORKSPACE_DIR)
    puts "  🗑️  #{WORKSPACE_DIR}/ ディレクトリを削除しています..."
    FileUtils.rm_rf(WORKSPACE_DIR)
  end
  
  puts "✅ プロジェクト初期化完了"
end

# 前処理タスク
desc "Markdownファイルの前処理を行います"
task :preprocess, [:files] do |t, args|
  files = if args[:files]
    args[:files].split(' ').map { |f| "#{CONTENT_DIR}/#{f}.md" }
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
    
    # 既存のフロントマターを削除
    content = content.sub(/^---\n.*?\n---\n\n/m, '')
    
    # 画像パスを修正
    content = fix_image_paths(content, filename)
    
    # 章番号を抽出（チャプター用CSS）
    chapter_num = filename.match(/^(\d+)-/) ? $1 : nil
    
    # フロントマターを追加
    frontmatter = generate_frontmatter(file_type, chapter_num)
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
task :convert, [:files] do |t, args|
  files = if args[:files]
    args[:files].split(' ').map { |f| "#{f}.md" }
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

# TOC生成
desc "目次HTMLを生成します"
task :toc do
  puts "📚 目次を生成しています..."
  
  # 既存のtoc.rakeの機能を統合
  # ここに目次生成ロジックを実装
  
  puts "✅ 目次生成完了"
end

# entries.js生成
desc "entries.jsを自動生成します"
task :entries do
  puts "📋 entries.jsを生成しています..."
  
  html_files = Dir.glob("*.html").sort
  entries = []
  
  html_files.each do |html_file|
    next if html_file == 'index.html'
    
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
  
  puts "✅ entries.js生成完了"
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
task :build, [:files] do |t, args|
  puts "📖 PDFを生成しています..."
  
  # 前処理→変換→entries.js生成→PDF生成の流れ
  Rake::Task['preprocess'].invoke(args[:files])
  Rake::Task['convert'].invoke(args[:files])
  Rake::Task['entries'].invoke
  
  # Vivliostyle Build
  puts "  🔧 Vivliostyle Build実行中..."
  system('vivliostyle build')
  
  if $?.success?
    puts "✅ PDF生成完了"
  else
    puts "❌ PDF生成失敗"
  end
end

# クリーンアップ
desc "不要ファイルを削除します"
task :clean do
  puts "🧹 クリーンアップを実行しています..."
  
  # PDF以外の生成ファイルを削除
  cleanup_patterns = [
    '*.html',
    '*.md',
    'entries.js'
  ]
  
  # README.mdとdesign_policy.mdは保持
  keep_files = ['README.md', 'design_policy.md']
  
  cleanup_patterns.each do |pattern|
    Dir.glob(pattern).each do |file|
      next if keep_files.include?(file)
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
puts "  rake init              - プロジェクト初期化"
puts "  rake preprocess        - 前処理（全ファイル）"
puts "  rake preprocess[files] - 前処理（指定ファイル）"
puts "  rake convert           - HTML変換（全ファイル）"
puts "  rake convert[files]    - HTML変換（指定ファイル）"
puts "  rake toc               - 目次生成"
puts "  rake entries           - entries.js生成"
puts "  rake images            - 画像ディレクトリ生成"
puts "  rake build             - PDF生成（全ファイル）"
puts "  rake build[files]      - PDF生成（指定ファイル）"
puts "  rake clean             - クリーンアップ"
puts ""
