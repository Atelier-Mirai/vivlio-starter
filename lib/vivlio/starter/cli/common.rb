# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'yaml'
require 'pathname'

# 書籍ビルドシステムの共通モジュール
module Vivlio
  module Starter
    module CLI
      module Common
        module_function

        # ================================================================
        # Config: 必須設定ファイルと定数
        # ================================================================
        # 必須 YAML ファイル（config/ 配下）
        REQUIRED_YAML_FILES = %w[
          config/book.yml
          config/catalog.yml
          config/page_presets.yml
          config/post_replace_list.yml
        ].freeze

        CONFIG_FILE = 'config/book.yml'
        PAGE_PRESETS_FILE = 'config/page_presets.yml'
        FONT_SIZE_KEYS = %w[base_font_size column_font_size folio_font_size].freeze
        PAGE_PRESET_EXCLUDE_KEYS = %w[preset use preset_name].freeze

        # ================================================================
        # Utility: 必須 YAML ファイルの事前検証
        # ------------------------------------------------
        # - CONFIG 構築前に呼び出し、必須ファイルの存在・パースを一括検証
        # - 不足または不正な場合はエラーメッセージを表示して終了
        # ================================================================
        def ensure_required_yaml_files!
          REQUIRED_YAML_FILES.each do |relative_path|
            unless File.file?(relative_path)
              puts "❌ 必須設定ファイルが見つかりません: #{relative_path}"
              puts '❌ コマンドを中止します'
              raise SystemExit, 1
            end

            begin
              yaml_text = File.read(relative_path, encoding: 'utf-8')
              data = YAML.safe_load(yaml_text, permitted_classes: [], aliases: true)

              # パース結果が nil（空ファイルや全コメント）の場合は不正
              # Hash または Array であれば有効とする
              if data.nil?
                puts "❌ 必須設定ファイルの内容が空です: #{relative_path}"
                puts '❌ コマンドを中止します'
                raise SystemExit, 1
              end
            rescue SystemExit
              raise
            rescue StandardError
              puts "❌ 必須設定ファイルの形式が不正です: #{relative_path}"
              puts '❌ コマンドを中止します'
              raise SystemExit, 1
            end
          end
        end

        # ================================================================
        # Utility: 設定読み込み load_config
        # ------------------------------------------------
        # - ensure_required_yaml_files! で事前検証済みの前提
        # - config/book.yml を読み込み、ページプリセットを適用して返す
        # ================================================================
        def load_config
          cfg_text = File.read(CONFIG_FILE, encoding: 'utf-8')
          config = YAML.safe_load(cfg_text, permitted_classes: [], aliases: true)
          apply_page_preset!(config)
          config
        end

        # page プリセット設定を解決し、単位を正規化する
        # config/page_presets.yml は ensure_required_yaml_files! で事前検証済み
        def apply_page_preset!(cfg)
          page_cfg = cfg['page'].is_a?(Hash) ? cfg['page'] : {}
          preset_name = extract_page_preset_name(page_cfg)
          return cfg if blank?(preset_name)

          presets = load_page_presets
          selected = presets[preset_name.to_s]
          return cfg unless selected.is_a?(Hash)

          overrides = page_cfg.reject { |k, _| PAGE_PRESET_EXCLUDE_KEYS.include?(k.to_s) }
          cfg['page'] = selected.merge(overrides)
          normalize_page_units!(cfg['page'])
          cfg
        end

        # page 設定からプリセット名を抽出する
        def extract_page_preset_name(page_cfg)
          return nil unless page_cfg.is_a?(Hash)

          page_cfg['preset'] || page_cfg['use'] || page_cfg['preset_name']
        end

        # ページプリセット定義を読み込む
        # config/page_presets.yml の存在・YAML パースは ensure_core_yaml_files! で
        # 事前に検証済みである前提とし、ここでは単純に読み込んで返す。
        def load_page_presets
          presets_text = File.read(PAGE_PRESETS_FILE, encoding: 'utf-8')
          YAML.safe_load(presets_text, permitted_classes: [], aliases: true)
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

        # 出力ファイル名を生成する
        # @param target [String] ターゲットタイプ ('pdf', 'print_pdf', 'epub')
        # @param suffix [String, nil] 圧縮接尾辞（例: 'compressed'）※省略時は自動判定しない
        # @return [String] 生成されたファイル名
        def generate_output_filename(target = 'pdf', suffix: nil)
          config = CONFIG
          project_name = config.dig('project', 'name') || 'vivlio_starter'
          project_version = config.dig('project', 'version')
          include_version = config.dig('output', 'filename', 'include_version') || false

          # ベース名を構築
          filename = project_name.to_s.dup

          # print_pdf ターゲットの場合は _print 接頭辞を追加
          filename += '_print' if target == 'print_pdf'

          # バージョンを含める場合は _v{version} を追加
          filename += "_v#{project_version}" if include_version && !blank?(project_version)

          # 圧縮接尾辞を追加（pdfターゲットのみ対応、print_pdf/epubは対象外）
          if suffix && !blank?(suffix) && target == 'pdf'
            # suffixが既に _ で始まっている場合はそのまま、そうでなければ _ を追加
            filename += suffix.to_s.start_with?('_') ? suffix : "_#{suffix}"
          end

          # 拡張子を追加
          filename += case target
                      when 'pdf', 'print_pdf'
                        '.pdf'
                      when 'epub'
                        '.epub'
                      else
                        '.pdf' # デフォルトはPDF
                      end

          filename
        end

        # print_pdf ターゲット用のファイル名を生成する
        # @return [String] print_pdf用のファイル名
        def generate_print_pdf_filename
          generate_output_filename('print_pdf')
        end

        # epub ターゲット用のファイル名を生成する
        # @return [String] epub用のファイル名
        def generate_epub_filename
          generate_output_filename('epub')
        end

        # 圧縮PDF用のファイル名を生成する（設定から圧縮接尾辞を自動取得）
        # @param target [String] ターゲットタイプ（'pdf' のみ対応、print_pdf/epubは圧縮対象外）
        # @return [String] 圧縮PDF用のファイル名
        def generate_compressed_pdf_filename(target = 'pdf')
          config = CONFIG
          compress_suffix = config.dig('output', 'pdf', 'compress', 'suffix') || 'compressed'
          generate_output_filename(target, suffix: compress_suffix)
        end

        # blank? 判定の簡易版
        def blank?(value)
          value.nil? || value.to_s.strip.empty?
        end

        def resolve_path_from_root(path)
          return nil if blank?(path)

          pn = Pathname.new(path)
          pn = Pathname.new(Dir.pwd).join(pn) unless pn.absolute?
          pn.cleanpath.to_s
        rescue StandardError
          path
        end

        def relative_path_from_root(path)
          return path if blank?(path)

          Pathname.new(path).relative_path_from(Pathname.new(Dir.pwd)).to_s
        rescue StandardError
          path.to_s
        end

        def config_dir_path
          resolve_path_from_root(CONFIG_DIR)
        end

        def post_replace_file_path
          return nil if blank?(POST_REPLACE_FILE)

          pn = Pathname.new(POST_REPLACE_FILE)
          base = Pathname.new(config_dir_path)
          pn = base.join(pn) unless pn.absolute?
          pn.cleanpath.to_s
        rescue StandardError
          resolve_path_from_root(POST_REPLACE_FILE)
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
        # - reload_configuration! で再初期化可能
        # ================================================================
        CONFIG_RELOADABLE_CONSTANTS = %i[
          CONFIG
          CONFIG_DIR
          CONTENTS_DIR
          STYLESHEETS_DIR
          IMAGES_DIR
          CODES_DIR
          CHAPTER_TEMPLATES_DIR
          VFM_COMMAND
          POST_REPLACE_FILE
          CACHE_CFG
          CACHE_DIR
        ].freeze

        def initialize_configuration_constants!
          CONFIG_RELOADABLE_CONSTANTS.each do |const|
            remove_const(const) if const_defined?(const, false)
          end

          ensure_required_yaml_files!
          config = load_config

          const_set(:CONFIG, config)

          config_dir = begin
            dir = config.dig('directories', 'config')
            dir.nil? || dir.to_s.strip.empty? ? 'config' : dir
          end
          const_set(:CONFIG_DIR, config_dir)

          const_set(:CONTENTS_DIR,          config['directories']['contents'])
          const_set(:STYLESHEETS_DIR,       config['directories']['stylesheets'])
          const_set(:IMAGES_DIR,            config['directories']['images'])
          const_set(:CODES_DIR,             config['directories']['codes'])
          const_set(:CHAPTER_TEMPLATES_DIR, config['directories']['chapter_templates'])

          const_set(:VFM_COMMAND, config['commands']['vfm'])

          post_replace_file = begin
            file = config.dig('files', 'post_replace')
            file.nil? || file.to_s.strip.empty? ? 'post_replace_list.yml' : file
          end
          const_set(:POST_REPLACE_FILE, post_replace_file)

          cache_cfg = (config['cache'].is_a?(Hash) ? config['cache'] : {})
          const_set(:CACHE_CFG, cache_cfg)
          const_set(:CACHE_DIR, cache_cfg['dir'] || '.cache/vs')
        end
        module_function :initialize_configuration_constants!

        def reload_configuration!
          initialize_configuration_constants!
        end
        module_function :reload_configuration!

        initialize_configuration_constants!

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
        # - 特殊ページ（_titlepage 等）も判定可能
        # - デフォルトは 'chapter'
        # ================================================================
        # 章番号レンジ定数（catalog_spec.md 準拠）
        PREFACE_RANGE  = (0..0)
        MAIN_RANGE     = (1..89)
        APPX_RANGE     = (90..98)
        POSTFACE_RANGE = (99..99)

        def get_file_type(filename)
          name = File.basename(filename.to_s)

          # 特殊ページ（内部 basename）の判定
          case name
          when /^_titlepage/
            return 'titlepage'
          when /^_legalpage/
            return 'legalpage'
          when /^_colophon/
            return 'colophon'
          when /^_indexpage/
            return 'indexpage'
          end

          # 章番号から判定
          num = get_chapter_number(name)&.to_i
          return 'chapter' unless num

          case num
          when PREFACE_RANGE
            'preface'
          when MAIN_RANGE
            'chapter'
          when APPX_RANGE
            'appendix'
          when POSTFACE_RANGE
            'postface'
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
