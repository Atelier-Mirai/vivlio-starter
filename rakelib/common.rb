require 'fileutils'
require 'json'
require 'yaml'
require_relative 'options'

# 書籍ビルドシステムの共通モジュール
module BookBuild
  # 設定ファイルを読み込み
  # プロジェクトの設定ファイルのみを対象: ./config/book.yml
  DEFAULT_CONFIG_FILE  = 'config/book.yml'
  CONFIG_FILE = DEFAULT_CONFIG_FILE
  # <prefix>/config/book.yml を検出した場合は <prefix> をプレフィックスとして採用する
  # 例: awesomebook/config/book.yml -> CONFIG_PREFIX = 'awesomebook'
  #     config/book.yml              -> CONFIG_PREFIX = ''
  # 現行の実装では CONFIG_FILE は常に 'config/book.yml' を指すため、
  # プレフィックスの前置は行わない（簡素化）。
  
  def self.load_config
    if File.exist?(CONFIG_FILE)
      YAML.load_file(CONFIG_FILE)
    else
      puts "⚠️ 設定ファイルが見つかりません: #{CONFIG_FILE}"
      puts "⚠️ デフォルト設定を使用します"
      {
        'directories' => {
          'contents' => 'contents',
          'stylesheets' => 'stylesheets',
          'images' => 'images',
          'codes' => 'codes',
          'chapter_templates' => 'chapter_templates'
        },
        'commands' => {
          'vfm' => 'vfm'
        },
        'files' => {
          'post_replace' => '_postReplaceList.json'
        }
      }
    end
  end
  
  # 設定を読み込み
  CONFIG = load_config
  
  # ディレクトリ設定
  CONTENTS_DIR           = CONFIG['directories']['contents']
  STYLESHEETS_DIR        = CONFIG['directories']['stylesheets']
  IMAGES_DIR             = CONFIG['directories']['images']
  CODES_DIR              = CONFIG['directories']['codes']
  CHAPTER_TEMPLATES_DIR  = CONFIG['directories']['chapter_templates']
  
  # コマンド設定
  VFM_COMMAND       = CONFIG['commands']['vfm']
  
  # ファイル設定
  POST_REPLACE_FILE = CONFIG['files']['post_replace']
  
  # ファイルタイプを判定
  def self.get_file_type(filename)
    name = File.basename(filename.to_s)
    case name
    when /^00-/
      'titlepage'
    when /^01-/
      'legalpage'
    when /^02-/
      'preface'
    when /^03-/
      'toc'
    when /^1[0-9]-/, /^[2-8][0-9]-/
      'chapter'
    when /^9[0-7]-/
      'appendix'
    when /^98-/
      'postface'
    when /^99-colophon/
      'colophon'
    else
      'chapter'  # デフォルト
    end
  end

  # 章番号を抽出（例: 21-history.md → 21）
  def self.get_chapter_number(filename)
    chapter_num = filename[/^(\d+)-/, 1]
  end

  def self.verbose?
    return true if %w[1 true yes on].include?((ENV['VERBOSE'] || '').downcase)
    argv = defined?(ARGV) ? ARGV : []
    argv.include?('-v') || argv.include?('--verbose')
  rescue
    false
  end

  # 共通ログ出力（日本語 + 絵文字）
  def self.log_info(msg)
    puts "ℹ️ #{msg}" if verbose?
  end

  def self.log_success(msg)
    puts "✅ #{msg}"
  end

  def self.log_warn(msg)
    puts "⚠️ #{msg}"
  end

  def self.log_error(msg)
    puts "❌ #{msg}"
  end

  def self.log_action(msg)
    puts "🔧 #{msg}"
  end

  # 引数/オプションの共通パース
  # 戻り値: { files: [...], options: { ... } }
  def self.process_args(task_name = nil, argv = ARGV)
    # ARGV を破壊しないよう複製
    argv_copy = argv.dup
    # Options.parse は argv_copy からオプションを取り除き、残りを files として返す
    parsed = Options.parse(argv_copy)
    # files から当該タスク名を除去（例: "rake entries 20-number" で "entries" が混入するのを防止）
    files = (parsed[:files] || []).reject do |f|
      next false unless task_name
      f == task_name || f.start_with?("#{task_name}[") || f.start_with?("#{task_name}:")
    end

    # ファイル指定の正規化
    # - 末尾の拡張子 .md を許容し、除去（例: 98-postface.md -> 98-postface）
    # - 先頭のディレクトリ contents/ を許容し、除去（例: contents/98-postface -> 98-postface）
    begin
      contents_prefix = %r{\A#{Regexp.escape(BookBuild::CONTENTS_DIR)}/}
      files = files.map { |name|
        n = name.to_s
        n = n.sub(contents_prefix, '')
        n = File.basename(n, '.md')
        n
      }.reject { |n| n.nil? || n.strip.empty? }.uniq
    rescue => _e
      # 失敗時は無変換のまま続行
    end

    # Rake が追加のコマンド引数を「タスク名」と誤認して実行後にエラーになるのを防ぐため、
    # ファイル引数らしきトークンに対してダミーの no-op タスクを事前定義する。
    # 例: `rake build 11-gift` の "11-gift" をダミータスク化。
    begin
      if defined?(Rake)
        files.each do |name|
          # コロン付きは明示的な名前空間タスクの可能性があるため除外
          next if name.include?(":")
          # 既に定義済みならスキップ
          next if Rake::Task.task_defined?(name) rescue false
          # 記号的に妥当な "ファイル/スラッグ風" のもののみ対象
          if name =~ /\A[\w\-\.\/~]+\z/
            Rake::Task.define_task(name) {}
          end
        end
      end
    rescue => _e
      # ここで失敗してもビルド自体は続行（ログは冗長化を避けて抑止）
    end
    # 互換のため必ず keys を揃える
    {
      files: files,
      options: parsed[:options] || {}
    }
  end

  # 付録番号を文字(A=91..G=97)に変換
  def self.appendix_number_to_letter(number)
    case number.to_i
    when 91 then 'a'
    when 92 then 'b'
    when 93 then 'c'
    when 94 then 'd'
    when 95 then 'e'
    when 96 then 'f'
    when 97 then 'g'
    else 'x'
    end
  end

  # CSSファイル内の counter-reset とコメントを章番号に合わせて更新
  def self.update_css_counter(css_file, chapter_number)
    return unless File.exist?(css_file)

    content = File.read(css_file, encoding: 'utf-8')
    updated = content.gsub(
      /counter-reset:\s*chapter-counter\s+\d+/, 
      "counter-reset: chapter-counter #{chapter_number - 10}"
    )

    updated = updated.gsub(
      /\* 第\d+章用スタイル \*\//,
      "* 第#{chapter_number - 10}章用スタイル */"
    )

    if content != updated
      File.write(css_file, updated, encoding: 'utf-8')
      BookBuild.log_info("counter-reset を #{chapter_number - 10} に更新")
    end
  end
end
