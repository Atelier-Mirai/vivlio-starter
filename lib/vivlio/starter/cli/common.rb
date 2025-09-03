# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'yaml'

# 書籍ビルドシステムの共通モジュール（Thor CLI用）
module Vivlio
  module Starter
    module CLI
      module Common
        extend self

        # ================================================================
        # Config: 設定ファイルと定数
        # ------------------------------------------------
        # - 対象: ./config/book.yml（プロジェクト設定）
        # - 読み込み関数: load_config（Hash 正常化を含む）
        # - 定数: CONFIG, 各種ディレクトリ/コマンド/ファイル設定
        # ================================================================
        # 設定ファイルを読み込み
        # プロジェクトの設定ファイルのみを対象: ./config/book.yml
        DEFAULT_CONFIG_FILE  = 'config/book.yml'
        CONFIG_FILE = DEFAULT_CONFIG_FILE

        # ================================================================
        # Utility: 設定読み込み load_config
        # ------------------------------------------------
        # - YAML を読み込み、Hash でない場合はデフォルトにフォールバック
        # - 存在しない場合もデフォルトにフォールバック
        # ================================================================
        def load_config
          if File.exist?(CONFIG_FILE)
            cfg = YAML.load_file(CONFIG_FILE)
            unless cfg.is_a?(Hash)
              puts "⚠️ 設定ファイルの内容が不正です（Hash ではありません）: #{CONFIG_FILE}"
              puts "⚠️ デフォルト設定を使用します"
              cfg = {
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
            cfg
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

        # ================================================================
        # Utility: 引数トークンの正規化 normalize_tokens
        # ------------------------------------------------
        # - contents/ プレフィックスや拡張子 .md を除去
        # - 空要素を除去し一意化
        # ================================================================
        def normalize_tokens(files)
          contents_prefix = %r{\A#{Regexp.escape(CONTENTS_DIR)}/}
          Array(files).compact.map { |name|
            n = name.to_s
            n = n.sub(contents_prefix, '')
            n = File.basename(n, '.md')
            n
          }.reject { |n| n.nil? || n.strip.empty? }.uniq
        rescue
          Array(files).compact
        end

        # ================================================================
        # Utility: ローマ数字（小文字）変換 to_roman_lower
        # ------------------------------------------------
        # - 範囲: 1..3999 を想定
        # - 無効値は空文字を返す
        # ================================================================
        def to_roman_lower(n)
          return '' if n.to_i <= 0
          n = n.to_i
          mapping = [
            [1000, 'm'], [900, 'cm'], [500, 'd'], [400, 'cd'],
            [100, 'c'], [90, 'xc'], [50, 'l'], [40, 'xl'],
            [10, 'x'], [9, 'ix'], [5, 'v'], [4, 'iv'], [1, 'i']
          ]
          res = String.new
          mapping.each do |val, sym|
            count, n = n.divmod(val)
            res << sym * count
          end
          res
        end

        # ================================================================
        # Utility: 付録番号(91..97)を appendix-[a..g] の letter に変換
        # ------------------------------------------------
        # - 無効範囲は nil を返す
        # ================================================================
        def appendix_number_to_letter(num)
          n = num.to_i
          return nil unless n.between?(91, 97)
          ("a".."g").to_a[n - 91]
        rescue
          nil
        end

        # ================================================================
        # Config: 設定ロードと派生定数
        # ------------------------------------------------
        # - CONFIG をロードし、各種ディレクトリ/コマンド/ファイルの定数を定義
        # ================================================================
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

        # ================================================================
        # Utility: ファイルタイプ判定 get_file_type
        # ------------------------------------------------
        # - 章番号の接頭辞から種別を返す（titlepage/legalpage/...）
        # - デフォルトは 'chapter'
        # ================================================================
        def get_file_type(filename)
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

        # ================================================================
        # Utility: 章番号抽出 get_chapter_number
        # ------------------------------------------------
        # - 例: 21-history.md → 21（String または nil）
        # ================================================================
        def get_chapter_number(filename)
          chapter_num = filename[/^(\d+)-/, 1]
        end

        # ================================================================
        # Utility: verbose? 判定
        # ------------------------------------------------
        # - ENV['VERBOSE'] または ARGV の -v/--verbose を検査
        # ================================================================
        def verbose?
          return true if %w[1 true yes on].include?((ENV['VERBOSE'] || '').downcase)
          argv = defined?(ARGV) ? ARGV : []
          argv.include?('-v') || argv.include?('--verbose')
        rescue
          false
        end

        # ================================================================
        # Logging: 共通ログ出力（日本語 + 絵文字）
        # ------------------------------------------------
        # - log_info/log_success/log_warn は verbose? 時のみ出力
        # - log_error は常に出力
        # ================================================================
        def log_info(msg)
          puts "ℹ️ #{msg}" if verbose?
        end

        def log_success(msg)
          puts "✅ #{msg}" if verbose?
        end

        def log_warn(msg)
          puts "⚠️ #{msg}" if verbose?
        end

        def log_error(msg)
          puts "❌ #{msg}"
        end

        def log_action(msg)
          puts "🔧 #{msg}" if verbose?
        end

        # ================================================================
        # Logging: 常に表示 echo_always
        # ------------------------------------------------
        # - ラッパー等で標準出力が抑制されても見えるよう STDERR に出力
        # ================================================================
        def echo_always(msg)
          $stderr.puts msg
        end
      end
    end
  end
end
