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


# ------------------------------
# 前付け生成（titlepage / colophon）
# ------------------------------
module FrontMatterCreator
  module_function

  def extract_title_and_subtitle(config)
    book = (config['book'] || {})
    full  = (book['title'] || '').to_s
    main  = (book['main_title'] || '').to_s
    sub   = (book['subtitle'] || '').to_s

    # 1) 明示的な main_title/subtitle があれば優先
    title = main.empty? ? full : main
    subtitle = sub

    # 2) subtitle が未指定なら、全角波ダッシュでの表記から推測
    if subtitle.empty? && !full.empty?
      # 例: "電気・電子技術への招待 ～古代の叡智から現代AIまで～"
      if full =~ /(.*?)[ \u3000]*[～〜](.+?)[～〜]\s*$/
        title = $1.to_s.strip
        subtitle = $2.to_s.strip
      end
    end

    # タイトルの末尾に残存する装飾を除去（保険）
    title = title.to_s.gsub(/[ \u3000]*[～〜].*$/, '').strip

    [title, subtitle]
  end

  def safe_write(path, content)
    if File.exist?(path) && (ENV['FORCE'].to_s.empty?)
      BookBuild.log_warn("#{path} は既に存在します。上書きするには FORCE=1 を指定してください。")
      return false
    end
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content, encoding: 'utf-8')
    BookBuild.log_success("#{path} を生成しました")
    true
  end
end

namespace :create do
  desc "タイトルページを config/book.yml から生成 (FORCE=1 で上書き)"
  task :titlepage do
    cfg = BookBuild::CONFIG
    title, subtitle = FrontMatterCreator.extract_title_and_subtitle(cfg)
    author   = (cfg.dig('book', 'author') || '').to_s
    series   = (cfg.dig('book', 'series') || '').to_s
    release  = (cfg.dig('book', 'release') || '').to_s

    # 副題の装飾スタイル (wave|bar|none)
    style = (cfg.dig('book', 'subtitle_style') || 'wave').to_s.downcase
    style = 'wave' unless %w[wave bar none].include?(style)
    subtitle_class = "subtitle subtitle--#{style}"

    content = <<~MD
      <h1 class="book-title">#{title}</h1>
      #{subtitle.empty? ? '' : %Q(<p class="#{subtitle_class}">#{subtitle}</p>)}

      #{author.empty? ? '' : %Q(<p class="author"><span>[著]</span> #{author}</p>)}

      #{(series.empty? && release.empty?) ? '' : %Q(<div class="publication-info">)}
      #{series.empty? ? '' : %Q(    <p class="series">#{series}</p>)}
      #{release.empty? ? '' : %Q(    <p class="release-info">#{release}</p>)}
      #{(series.empty? && release.empty?) ? '' : %Q(</div>)}
    MD

    out = File.join(BookBuild::CONTENTS_DIR, '00-titlepage.md')
    FrontMatterCreator.safe_write(out, content)
  end

  desc "奥付を config/book.yml から生成 (FORCE=1 で上書き)"
  task :colophon do
    cfg = BookBuild::CONFIG
    title, subtitle = FrontMatterCreator.extract_title_and_subtitle(cfg)
    author   = (cfg.dig('book', 'author') || '').to_s
    publisher = (cfg.dig('book', 'publisher') || cfg.dig('book', 'publisher_name') || '').to_s
    contact   = (cfg.dig('book', 'contact') || '').to_s
    release   = (cfg.dig('book', 'release') || '').to_s

    # 副題の装飾スタイル (wave|bar|none)
    style = (cfg.dig('book', 'subtitle_style') || 'wave').to_s.downcase
    style = 'wave' unless %w[wave bar none].include?(style)
    subtitle_class = "subtitle subtitle--#{style}"

    # 著作年（和暦: 令和）を決定
    current_year = Time.now.year

    # release から開始年を推定（令和表記または西暦）
    start_year = nil
    if release =~ /令和([一二三四五六七八九十百]+)年/
      kan = $1
      kan_map = { '零'=>0, '一'=>1, '二'=>2, '三'=>3, '四'=>4, '五'=>5, '六'=>6, '七'=>7, '八'=>8, '九'=>9 }
      to_int = lambda do |s|
        # 簡易: 1〜99 の漢数字を数値へ（百は簡略対応）
        total = 0
        if s.include?('百')
          s = s.sub('百','')
          total += 100
        end
        if s.include?('十')
          parts = s.split('十', 2)
          tens = parts[0].empty? ? 1 : kan_map[parts[0]]
          ones = parts[1].to_s.empty? ? 0 : kan_map[parts[1]]
          total += tens.to_i * 10 + ones.to_i
        else
          total += kan_map[s].to_i
        end
        total
      end
      n = to_int.call(kan)
      start_year = 2018 + n # 令和1年=2019年
    elsif release =~ /(\d{4})/
      start_year = $1.to_i
    end

    to_kan = lambda do |n|
      # 1〜99 を漢数字へ
      km = %w(零 一 二 三 四 五 六 七 八 九)
      return '零' if n == 0
      return km[n] if n < 10
      return '十' if n == 10
      tens = n / 10
      ones = n % 10
      s = ''
      s += (tens == 1 ? '' : km[tens]) + '十'
      s += (ones == 0 ? '' : km[ones])
      s
    end

    current_wareki = "令和#{to_kan.call(current_year - 2018)}年"
    copyright_years = if start_year && start_year != current_year && start_year >= 2019
      start_wareki = "令和#{to_kan.call(start_year - 2018)}年"
      "#{start_wareki} #{current_wareki}"
    else
      current_wareki
    end

    content = <<~MD
      <h1 class="book-title">#{title}</h1>
      #{subtitle.empty? ? '' : %Q(<p class="#{subtitle_class}">#{subtitle}</p>)}

      #{release.empty? ? '' : %Q(<p class="publication-info">#{release}</p>)}

      <dl class="info-list">
          #{author.empty? ? '' : %Q(<dt>著者</dt>\n          <dd>#{author}</dd>)}
          #{publisher.empty? ? '' : %Q(<dt>発行者</dt>\n          <dd>#{publisher}</dd>)}
          #{contact.empty? ? '' : %Q(<dt>連絡先</dt>\n          <dd>#{contact}</dd>)}
      </dl>

      <p class="copyright">
          <small>
              &copy; #{copyright_years} #{author.empty? ? '著者' : author} All rights reserved.
          </small>
      </p>

      <p class="powered-by">
          <small>
              (powered by Vivlio Starter)
          </small>
      </p>
    MD

    out = File.join(BookBuild::CONTENTS_DIR, '99-colophon.md')
    FrontMatterCreator.safe_write(out, content)
  end
end

