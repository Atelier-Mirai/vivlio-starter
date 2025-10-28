# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'yaml'

# 書籍ビルドシステムの共通モジュール（Thor CLI用）
module Vivlio
  module Starter
    module CLI
      module Common
        module_function

        # ================================================================
        # Config: 設定ファイルと定数
        # ------------------------------------------------
        # - 対象: ./config/book.yml（プロジェクト設定）
        # - 読み込み関数: load_config（Hash 正常化を含む）
        # - 定数: CONFIG, 各種ディレクトリ/コマンド/ファイル設定
        # ================================================================
        # 設定ファイルを読み込み
        # プロジェクトの設定ファイルのみを対象: ./config/book.yml
        DEFAULT_CONFIG_FILE = 'config/book.yml'
        CONFIG_FILE = DEFAULT_CONFIG_FILE
        FONT_SIZE_KEYS = %w[base_font_size column_font_size folio_font_size].freeze
        DEFAULT_CONFIG_TEMPLATE = {
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
        }.freeze
        PAGE_PRESETS_FILE = File.join('config', 'page_presets.yml')
        PAGE_PRESET_EXCLUDE_KEYS = %w[preset use preset_name].freeze

        # ================================================================
        # Utility: 設定読み込み load_config
        # ------------------------------------------------
        # - YAML を読み込み、Hash でない場合はデフォルトにフォールバック
        # - 存在しない場合もデフォルトにフォールバック
        # ================================================================
        # config/book.yml を読み込み、必要に応じてプリセットを適用した設定を返す
        def load_config
          if File.exist?(CONFIG_FILE)
            config = load_config_from_file
            apply_page_preset!(config)
            config
          else
            warn_missing_config_file
            default_config
          end
        end

        # config/book.yml を読み込み Hash を返す（異常時はデフォルト設定）
        def load_config_from_file
          cfg_text = File.read(CONFIG_FILE, encoding: 'utf-8')
          cfg = YAML.safe_load(cfg_text, permitted_classes: [], aliases: true)
          return cfg if cfg.is_a?(Hash)

          warn_invalid_config_structure
          default_config
        rescue StandardError => e
          warn_config_load_error(e)
          default_config
        end

        # DEFAULT_CONFIG_TEMPLATE のディープコピーを返す
        def default_config
          Marshal.load(Marshal.dump(DEFAULT_CONFIG_TEMPLATE))
        end

        # 設定ファイルが存在しない場合の警告を出力
        def warn_missing_config_file
          puts "⚠️ 設定ファイルが見つかりません: #{CONFIG_FILE}"
          puts '⚠️ デフォルト設定を使用します'
        end

        # 設定ファイルが異常な構造だった場合の警告を出力
        def warn_invalid_config_structure
          puts "⚠️ 設定ファイルの内容が不正です（Hash ではありません）: #{CONFIG_FILE}"
          puts '⚠️ デフォルト設定を使用します'
        end

        # 読み込み時の例外を通知する
        def warn_config_load_error(error)
          puts "⚠️ 設定ファイルの読み込みに失敗しました: #{CONFIG_FILE} (#{error.class}: #{error.message})"
          puts '⚠️ デフォルト設定を使用します'
        end

        # page プリセット設定を解決し、単位を正規化する
        def apply_page_preset!(cfg)
          page_cfg = cfg['page'].is_a?(Hash) ? cfg['page'] : {}
          preset_name = extract_page_preset_name(page_cfg)
          return cfg if blank?(preset_name)

          presets = load_page_presets
          return cfg unless presets.is_a?(Hash)

          selected = presets[preset_name.to_s]
          unless selected.is_a?(Hash)
            puts "⚠️ ページプリセットが見つかりません: #{preset_name} (#{PAGE_PRESETS_FILE})"
            return cfg
          end

          overrides = page_cfg.reject { |k, _| PAGE_PRESET_EXCLUDE_KEYS.include?(k.to_s) }
          cfg['page'] = selected.merge(overrides)

          begin
            normalize_page_units!(cfg['page'])
          rescue StandardError => e
            puts "⚠️ base_line_height の単位正規化で例外: #{e.class}: #{e.message}"
          end

          cfg
        rescue StandardError => e
          puts "⚠️ ページプリセットの適用中にエラー: #{e.class}: #{e.message}"
          cfg
        end

        # page 設定からプリセット名を抽出する
        def extract_page_preset_name(page_cfg)
          return nil unless page_cfg.is_a?(Hash)

          page_cfg['preset'] || page_cfg['use'] || page_cfg['preset_name']
        end

        # ページプリセット定義を読み込む
        def load_page_presets
          unless File.exist?(PAGE_PRESETS_FILE)
            puts "⚠️ ページプリセットファイルが見つかりません: #{PAGE_PRESETS_FILE}"
            return nil
          end

          presets_text = File.read(PAGE_PRESETS_FILE, encoding: 'utf-8')
          presets = YAML.safe_load(presets_text, permitted_classes: [], aliases: true)
          return presets if presets.is_a?(Hash)

          puts "⚠️ #{PAGE_PRESETS_FILE} の形式が不正です（Hash ではありません）"
          nil
        rescue StandardError => e
          puts "⚠️ ページプリセットの読み込みに失敗しました: #{PAGE_PRESETS_FILE} (#{e.class}: #{e.message})"
          nil
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

          normalize_font_sizes!(pcfg)
          normalize_base_line_height!(pcfg)

          pcfg
        end

        # base_font_size 等の Q 単位を pt へ揃える
        def normalize_font_sizes!(pcfg)
          FONT_SIZE_KEYS.each do |key|
            value = pcfg[key]
            next if blank?(value)

            str = normalized_string(value)
            next unless str =~ /q\z/i

            pcfg[key] = q_to_pt(str)
          end
        end

        # base_line_height をフォントサイズ基準で pt 化する
        # base_line_height の値は、フォントサイズの倍率、Em 単位、Q 単位のいずれかを想定
        # これらの値を pt 単位に正規化する
        def normalize_base_line_height!(pcfg)
          line_height = pcfg['base_line_height']
          return if blank?(line_height)

          font_size_pt = pt_value(pcfg['base_font_size'])
          return unless font_size_pt

          pcfg['base_line_height'] = line_height_to_pt(normalized_string(line_height), font_size_pt)
        end

        # 文字列化された行送り値を pt に変換する
        # 行送り値は pt 単位、Q 単位、Em 単位、または倍率のいずれかを想定
        # これらの値を pt 単位に正規化する
        def line_height_to_pt(str, font_size_pt)
          case str
          when /pt\z/i
            str
          when /q\z/i
            q_to_pt(str)
          when /em\z/i
            format_pt(font_size_pt * str.sub(/em\z/i, '').to_f)
          when /\A[0-9]+(?:\.[0-9]+)?\z/
            format_pt(font_size_pt * str.to_f)
          else
            str
          end
        end

        # Q 単位の値を pt に変換する
        def q_to_pt(value)
          str = normalized_string(value)
          return str unless str =~ /q\z/i

          num = str.sub(/q\z/i, '').to_f
          format_pt(num * 0.709)
        end

        # pt 表記の数値部分を Float で返す
        def pt_value(value)
          str = normalized_string(value)
          match = str.match(/\A([0-9]+(?:\.[0-9]+)?)pt\z/i)
          match ? match[1].to_f : nil
        end

        # pt 値を小数第3位で丸めて文字列化する
        def format_pt(value)
          "#{value.round(3)}pt"
        end

        # 値を文字列化し前後空白を除去する
        def normalized_string(value)
          value.to_s.strip
        end

        # blank? 判定の簡易版
        def blank?(value)
          value.nil? || value.to_s.strip.empty?
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
            default_w = '210mm'
            default_h = '297mm'
          when 'A5'
            default_w = '148mm'
            default_h = '210mm'
          else
            # 既定: B5
            default_w = '182mm'
            default_h = '257mm'
          end

          width  = pcfg['width']
          height = pcfg['height']
          width  = width.to_s.strip unless width.nil?
          height = height.to_s.strip unless height.nil?

          width  = default_w unless width && !width.empty?
          height = default_h unless height && !height.empty?
          [width, height]
        end

        # ページ設定に width/height を補完する
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
          Array(files).compact.map do |name|
            n = name.to_s
            n = n.sub(contents_prefix, '')
            n = File.basename(n, '.md')
            n
          end.reject { |n| n.nil? || n.strip.empty? }.uniq
        rescue StandardError
          Array(files).compact
        end

        VIVLIOSTYLE_TIMINGS_KEY = :vivlio_starter_vivliostyle_timings

        def reset_vivliostyle_build_timings
          Thread.current[VIVLIOSTYLE_TIMINGS_KEY] = []
        end

        def record_vivliostyle_build(duration, label = nil)
          timings = Thread.current[VIVLIOSTYLE_TIMINGS_KEY] ||= []
          label_text = label.to_s
          label_text = 'Vivliostyle build' if label_text.empty?
          timings << { duration: duration.to_f, label: label_text }
        end

        def consume_vivliostyle_build_timings
          timings = Thread.current[VIVLIOSTYLE_TIMINGS_KEY] || []
          Thread.current[VIVLIOSTYLE_TIMINGS_KEY] = []
          timings
        end

        VIVLIOSTYLE_CURRENT_STEP_KEY = :vivlio_starter_current_step_label

        def with_current_step_label(label)
          previous = Thread.current[VIVLIOSTYLE_CURRENT_STEP_KEY]
          Thread.current[VIVLIOSTYLE_CURRENT_STEP_KEY] = label.to_s
          yield
        ensure
          Thread.current[VIVLIOSTYLE_CURRENT_STEP_KEY] = previous
        end

        def current_step_label
          Thread.current[VIVLIOSTYLE_CURRENT_STEP_KEY]
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
            res << (sym * count)
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

          ('a'..'g').to_a[n - 91]
        rescue StandardError
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
        # Cache settings
        # ------------------------------------------------
        # - 既定: 有効(enabled=true)、ディレクトリ: .cache/vs
        # - 用途: front/colophon など再利用可能な生成物の保存先
        # ================================================================
        CACHE_CFG  = (CONFIG['cache'].is_a?(Hash) ? CONFIG['cache'] : {})
        CACHE_DIR  = CACHE_CFG['dir'] || '.cache/vs'

        def cache_enabled?
          fetch_bool(CACHE_CFG, %w[enabled], default: true)
        rescue StandardError
          true
        end

        def cache_dir
          CACHE_DIR
        end

        def ensure_cache_dir!
          FileUtils.mkdir_p(CACHE_DIR)
          CACHE_DIR
        end

        # ================================================================
        # Utility: truthy?/falsey?（柔軟な真偽値解釈）
        # ------------------------------------------------
        # - true/false に加えて 'true'/'false', 'yes'/'no', 'on'/'off', '1'/'0' を解釈
        # ================================================================
        def truthy?(val)
          case val
          when true then true
          when false, nil then false
          else
            s = val.to_s.strip.downcase
            %w[true yes on 1].include?(s)
          end
        rescue StandardError
          false
        end

        def falsey?(val)
          !truthy?(val)
        end

        # ================================================================
        # Utility: fetch_bool（ネストしたキーから柔軟に真偽値を取得）
        # ------------------------------------------------
        # - keys: ['pdf', 'quiet'] のように配列で渡す
        # - default: 値が未設定/不正な場合の既定
        # - 例: fetch_bool(CONFIG, %w[pdf quiet], false)
        # ================================================================
        def fetch_bool(obj, keys, default: false)
          cur = obj
          Array(keys).each do |k|
            return default unless cur.is_a?(Hash)

            cur = cur[k]
          end
          return default if cur.nil?

          truthy?(cur)
        rescue StandardError
          default
        end

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
          when /^[1-8][0-9]-/
            'chapter'
          when /^9[0-7]-/
            'appendix'
          when /^98-/
            'postface'
          when /^99-colophon/
            'colophon'
          else
            'chapter' # デフォルト
          end
        end

        # ================================================================
        # Utility: 章番号抽出 get_chapter_number
        # ------------------------------------------------
        # - 例: 21-history.md → 21（String または nil）
        # ================================================================
        def get_chapter_number(filename)
          filename[/^(\d+)-/, 1]
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
              log_level_token = if nxt && !nxt.start_with?('-')
                                  nxt.to_s.strip.downcase
                                else
                                  ''
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

          LEVELS.fetch(log_level_token, 2)
        rescue StandardError
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
          puts msg
        end
      end
    end
  end
end
