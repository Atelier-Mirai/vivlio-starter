require_relative 'common'

module ChapterCreator
  # 引数を検証し、正規化する
  def self.ensure_filename(filename)
    name = filename.to_s.strip
    if name.empty?
      BookBuild.log_error("ファイル名を指定してください (例: rake create 21-history)")
      return nil
    end

    # 拡張子付与
    name << '.md' unless name.end_with?('.md')

    # 既存チェック
    file_path = "#{BookBuild::CONTENTS_DIR}/#{name}"
    if File.exist?(file_path)
      BookBuild.log_warn("#{file_path} は既に存在します")
      return nil
    end

    name
  end
  
  # タイトルを生成する
  def self.generate_title(filename)
    filename.gsub(/^\d+-/, '').gsub('.md', '').gsub('-', ' ').capitalize
  end
  
  # テンプレートからコンテンツを生成する
  def self.generate_content_from_template(title)
    template_path = "#{BookBuild::TEMPLATES_DIR}/chapter_template.md"
    
    if File.exist?(template_path)
      template_content = File.read(template_path)
      template_content.gsub('{{TITLE}}', title)
    else
      BookBuild.log_warn("テンプレートファイルが見つかりません: #{template_path}")
      BookBuild.log_warn("デフォルトテンプレートを使用します")
      <<~MD
        # #{title}

        ここに#{title}の内容を記述します。
      MD
    end
  end
  
  # Markdownファイルを作成する
  def self.create_markdown_file(filename, content)
    file_path = "#{BookBuild::CONTENTS_DIR}/#{filename}"
    File.write(file_path, content)
    file_path
  end
  
  # 画像ディレクトリを作成する
  def self.create_image_directory(filename, options)
    base_filename = filename.gsub(/\.md$/, '')
    image_dir = "#{BookBuild::IMAGES_DIR}/#{base_filename}"
    FileUtils.mkdir_p(image_dir)
    BookBuild.log_success("画像ディレクトリ #{image_dir} を生成しました")
    image_dir
  end
  
  # CSSファイルを作成する（章の場合のみ）
  def self.create_css_file_if_chapter(filename)
    file_type = BookBuild.get_file_type(filename)
    
    return false unless file_type == 'chapter'
    
    # 章番号を抽出（例: 21-history.md → 21）
    chapter_num = BookBuild.get_chapter_number(filename)
    
    if chapter_num.nil?
      BookBuild.log_warn("有効な章番号が指定されていません: #{filename}")
      return false
    end
    
    # CSSディレクトリが存在するか確認
    unless Dir.exist?(BookBuild::STYLESHEETS_DIR)
      FileUtils.mkdir_p(BookBuild::STYLESHEETS_DIR)
      BookBuild.log_info("#{BookBuild::STYLESHEETS_DIR} ディレクトリを作成しました")
    end
    
    css_filename = "#{BookBuild::STYLESHEETS_DIR}/#{chapter_num}.css"
    
    # 既存のファイルがある場合はスキップ
    if File.exist?(css_filename)
      BookBuild.log_info("#{css_filename} は既に存在します")
      return true
    end
    
    # CSSコンテンツを生成
    css_content = <<~CSS
      @charset "utf-8";
      
      /* 第#{chapter_num.to_i - 10}章用スタイル */
      
      /* 章番号を設定 */
      :root {
        counter-reset: chapter-counter #{chapter_num.to_i - 10};
      }
      
      /* 章固有のスタイルをここに追加 */
      
    CSS
    
    # CSSファイルを作成
    File.write(css_filename, css_content, encoding: 'utf-8')
    BookBuild.log_success("#{css_filename} を生成しました")
    
    true
  end
end

# 新しいMarkdownファイル生成
desc "新しい章を作成します (例: rake create 21-history)"
task :create do |t, args|
  # コマンドライン引数を取得
  args = BookBuild.process_args('create')
  files   = args[:files]
  options = args[:options]
  
  # 1. 引数を検証・正規化
  if files.empty?
    BookBuild.log_error("エラー: 作成する章のファイル名を指定してください (例: rake create 21-history)")
    exit 1
  end
  
  filename = ChapterCreator.ensure_filename(files.first)
  unless filename
    BookBuild.log_error("エラー: 無効なファイル名です")
    exit 1
  end
  
  # デバッグ用にオプションを表示
  BookBuild.log_info("オプション: #{options.inspect}")
  BookBuild.log_info("作成するファイル: #{filename}.md")
  
  # 2. タイトルを生成
  title = ChapterCreator.generate_title(filename)
  
  # 3. テンプレートからコンテンツを生成
  content = ChapterCreator.generate_content_from_template(title)
  
  # 4. Markdownファイルを作成
  file_path = ChapterCreator.create_markdown_file(filename, content)
  
  # 5. 画像ディレクトリを作成
  ChapterCreator.create_image_directory(filename, options)
  
  # 6. CSSファイルを作成（章の場合のみ）
  css_created = ChapterCreator.create_css_file_if_chapter(filename)
  
  # 7. 完了メッセージ
  BookBuild.log_success("#{file_path} を作成しました")
end


