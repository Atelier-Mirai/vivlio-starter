require 'fileutils'
require 'json'
require 'yaml'
require_relative 'options'

# 書籍ビルドシステムの共通モジュール
module BookBuild
  # 設定ファイルを読み込み
  CONFIG_FILE = 'config/book.yml'
  
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
          'templates' => 'templates'
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
  CONTENTS_DIR      = CONFIG['directories']['contents']
  STYLESHEETS_DIR   = CONFIG['directories']['stylesheets']
  IMAGES_DIR        = CONFIG['directories']['images']
  CODES_DIR         = CONFIG['directories']['codes']
  TEMPLATES_DIR     = CONFIG['directories']['templates']
  
  # コマンド設定
  VFM_COMMAND       = CONFIG['commands']['vfm']
  
  # ファイル設定
  POST_REPLACE_FILE = CONFIG['files']['post_replace']
  
  # ファイルタイプを判定
  def self.get_file_type(filename)
    case filename
    when /^00-/
      'titlepage'
    when /^01-/
      'legalpage'
    when /^02-/
      'preface'
    when /^03-/
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
end
