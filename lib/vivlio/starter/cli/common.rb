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
            cfg_text = File.read(CONFIG_FILE, encoding: 'utf-8')
            cfg = YAML.safe_load(cfg_text, permitted_classes: [], aliases: true)
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

            # ------------------------------------------------------------
            # 多段ロード/マージ: page.preset or page.use を解決
            # - config/page_presets.yml から該当プリセットを読み込み
            # - プリセット値に book.yml の page 値を上書き（ユーザー設定優先）
            # - 未指定/未検出の場合はそのまま
            # ------------------------------------------------------------
            begin
              page_cfg = (cfg['page'].is_a?(Hash) ? cfg['page'] : {})
              preset_name = page_cfg['preset'] || page_cfg['use'] || page_cfg['preset_name']
              if preset_name && !preset_name.to_s.strip.empty?
                presets_path = File.join('config', 'page_presets.yml')
                if File.exist?(presets_path)
                  presets_text = File.read(presets_path, encoding: 'utf-8')
                  presets = YAML.safe_load(presets_text, permitted_classes: [], aliases: true)
                  if presets.is_a?(Hash)
                    selected = presets[preset_name.to_s]
                    if selected.is_a?(Hash)
                      # preset/use/preset_name キーはマージ対象から除外
                      overrides = page_cfg.reject { |k, _| %w[preset use preset_name].include?(k.to_s) }
                      cfg['page'] = selected.merge(overrides)
                      # 単位正規化（pt へ統一）
                      begin
                        normalize_page_units!(cfg['page'])
                      rescue => e
                        puts "⚠️ base_line_height の単位正規化で例外: #{e.class}: #{e.message}"
                      end
                    else
                      puts "⚠️ ページプリセットが見つかりません: #{preset_name} (#{presets_path})"
                    end
                  else
                    puts "⚠️ #{presets_path} の形式が不正です（Hash ではありません）"
                  end
                else
                  puts "⚠️ ページプリセットファイルが見つかりません: #{presets_path}"
                end
              end
            rescue => e
              puts "⚠️ ページプリセットの適用中にエラー: #{e.class}: #{e.message}"
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
        # Utility: normalize_page_units!
        # ------------------------------------------------
        # - 目的: page 設定内の単位を pt に正規化
        # - 対象: base_font_size（Q→pt）, base_line_height（倍率/Em/Q→pt）
        # - 振る舞い: 引数の Hash を破壊的に更新
        # ================================================================
        def normalize_page_units!(pcfg)
          return pcfg unless pcfg.is_a?(Hash)

          to_pt = lambda { |val|
            s = val.to_s.strip
            return nil if s.empty?
            if s =~ /pt\z/i
              s # 既に pt
            elsif s =~ /q\z/i
              # 1Q ≒ 0.709pt
              num = s.sub(/q\z/i, '').to_f
              (num * 0.709).round(3).to_s + 'pt'
            else
              s
            end
          }

          # base_font_size / column_font_size / folio_font_size の Q → pt を一括処理
          %w[base_font_size column_font_size folio_font_size].each do |key|
            v = pcfg[key]
            next unless v && !v.to_s.strip.empty?
            s = v.to_s.strip
            next unless s =~ /q\z/i
            pcfg[key] = to_pt.call(s)
          end

          # 数値の pt 値を Float で取得
          get_pt_value = lambda { |s|
            m = s.to_s.strip.match(/\A([0-9]+(?:\.[0-9]+)?)pt\z/i)
            m ? m[1].to_f : nil
          }

          # line-height を pt に正規化
          blh = pcfg['base_line_height']
          bfs_pt = get_pt_value.call(pcfg['base_font_size'])
          if blh && bfs_pt
            str = blh.to_s.strip
            if str =~ /pt\z/i
              # 既に pt → そのまま
            elsif str =~ /q\z/i
              # Q → pt
              pcfg['base_line_height'] = to_pt.call(str)
            elsif str =~ /em\z/i
              # em はフォントサイズ倍率
              mult = str.sub(/em\z/i, '').to_f
              pcfg['base_line_height'] = (bfs_pt * mult).round(3).to_s + 'pt'
            elsif str =~ /\A[0-9]+(?:\.[0-9]+)?\z/
              # 単位なし（行送り倍率）
              mult = str.to_f
              pcfg['base_line_height'] = (bfs_pt * mult).round(3).to_s + 'pt'
            end
          end

          pcfg
        end

        # ================================================================
        # Utility: ページサイズ解決 resolve_page_size / normalize_page_size!
        # ------------------------------------------------
        # - 入力: page 設定 Hash（size/width/height を想定）
        # - 仕様:
        #   - size が A4/B5/A5 のいずれかなら、その既定寸法を基準にする
        #   - width/height が明示されていれば size より優先
        #   - どれも無ければ B5（182mm x 257mm）
        # - 出力:
        #   - resolve_page_size: [width, height] を返す
        #   - normalize_page_size!: 引数 Hash を破壊的に width/height 付与して返す
        # ================================================================
        def resolve_page_size(page_cfg)
          pcfg = page_cfg.is_a?(Hash) ? page_cfg : {}
          size = (pcfg['size'] || '').to_s.strip.upcase
          case size
          when 'A4'
            default_w, default_h = '210mm', '297mm'
          when 'A5'
            default_w, default_h = '148mm', '210mm'
          else
            # 既定: B5
            default_w, default_h = '182mm', '257mm'
          end

          width  = pcfg['width']
          height = pcfg['height']
          width  = width.to_s.strip unless width.nil?
          height = height.to_s.strip unless height.nil?

          width  = (width && !width.empty?)   ? width  : default_w
          height = (height && !height.empty?) ? height : default_h
          [width, height]
        end

        def normalize_page_size!(page_cfg)
          return page_cfg unless page_cfg.is_a?(Hash)
          w, h = resolve_page_size(page_cfg)
          page_cfg['width']  = w
          page_cfg['height'] = h
          page_cfg
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
        # Logging config: ログレベル/詳細度
        # ------------------------------------------------
        # 制御方法: --log[=level]
        #   --log=error  -> 0
        #   --log=warn   -> 1
        #   --log=info   -> 2  （標準）
        #   --log=success-> 2  （info 同等）
        #   --log=action -> 2  （info 同等）
        #   --log=debug  -> 3
        #   --log        -> 2  （レベル省略時は info 相当）
        # 既定（--log 未指定時）は warn(1)
        # ================================================================
        LEVELS = { 'error' => 0, 'warn' => 1, 'info' => 2, 'success' => 2, 'action' => 2, 'debug' => 3 }.freeze

        def current_log_level
          argv = defined?(ARGV) ? ARGV : []
          log_level_token = nil
          argv.each_with_index do |arg, i|
            next unless arg.start_with?('--log')
            if arg.include?('=')
              log_level_token = arg.split('=', 2)[1].to_s.strip.downcase
            else
              # 次のトークンがレベルなら採用、無ければ省略扱い（=info）
              nxt = argv[i + 1]
              if nxt && !nxt.start_with?('-')
                log_level_token = nxt.to_s.strip.downcase
              else
                log_level_token = ''
              end
            end
            break
          end

          if log_level_token.nil?
            # --log 未指定 → 既定 warn(1)
            return 1
          end

          # --log 指定時
          return 2 if log_level_token.empty? # --log のみ → info 相当
          return LEVELS.fetch(log_level_token, 2)
        rescue
          1
        end

        # 互換: 従来の verbose? は info レベル以上を true とする
        def verbose?
          current_log_level >= 2
        end

        # ================================================================
        # Logging: 共通ログ出力（日本語 + 絵文字）
        # ------------------------------------------------
        # - レベル閾値: error=0, warn=1, info=2, debug=3
        # - 既定 warn(1): warn 以上のみ表示
        # ================================================================
        def log_info(msg)
          puts "ℹ️ #{msg}" if current_log_level >= 2
        end

        def log_success(msg)
          puts "✅ #{msg}" if current_log_level >= 2
        end

        def log_warn(msg)
          puts "⚠️ #{msg}" if current_log_level >= 1
        end

        def log_error(msg)
          puts "❌ #{msg}"
        end

        def log_action(msg)
          puts "🔧 #{msg}" if current_log_level >= 2
        end

        # 追加: デバッグ専用ログ
        def log_debug(msg)
          puts "🧪 #{msg}" if current_log_level >= 3
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
