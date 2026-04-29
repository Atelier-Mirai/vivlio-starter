# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'yaml'

# このコードで可能になったこと
# * ハイブリッドなアクセス:
#     * Common::CONFIG.page.base_font_size （ドット記法でスマートに）
#     * Common::CONFIG[:page][:base_font_size] （変数を使った動的なアクセスもOK）
# * パターンマッチングの継続サポート:
#     * def deconstruct_keys を実装したため、case Common::CONFIG in { page: { size: } } のようなパターンマッチも引き続き機能します。
# * 安全な設定変更:
#     * 著者が book.yml を編集した後に reload_configuration! を呼べば、警告なしで CONFIG の中身が最新の状態に置き換わります。
# * 不変性の保証:
#     * .freeze を適用しているため、ビルド実行中に設定が誤って書き換えられる副作用を防ぎます。

module Vivlio
  module Starter
    module CLI
      module Common
        module_function

        # --- 定数定義 ---
        REQUIRED_YAML_FILES = %w[
          config/book.yml config/catalog.yml config/page_presets.yml config/post_replace_list.yml
        ].freeze

        CONFIG_FILE = 'config/book.yml'
        PAGE_PRESETS_FILE = 'config/page_presets.yml'
        FONT_SIZE_KEYS = %i[base_font_size column_font_size folio_font_size].freeze
        PAGE_PRESET_EXCLUDE_KEYS = %i[preset use preset_name].freeze
        LEVELS = { 'error' => 0, 'warn' => 1, 'info' => 2, 'success' => 2, 'action' => 2, 'debug' => 3 }.freeze

        CONFIG_DIR = 'config'
        CONTENTS_DIR = 'contents'
        STYLESHEETS_DIR = 'stylesheets'
        IMAGES_DIR = 'images'
        CODES_DIR = 'codes'
        TEMPLATES_DIR = 'templates'
        COVERS_DIR = 'covers'
        VFM_COMMAND = 'vfm'
        POST_REPLACE_FILE = 'post_replace_list.yml'
        CACHE_DIR = '.cache/vs'
        VIVLIOSTYLE_CONFIG_FILE = 'vivliostyle.config.js'

        # ================================================================
        # Recursive Data Wrapper (Ruby 4.0 Style)
        # ================================================================

        # Hashを再帰的にDataオブジェクトに変換するヘルパー
        # ドット記法と [] アクセスの両方を提供します
        def wrap_config(input)
          case input
          in Hash
            # キーを動的にDataの属性として定義
            keys = input.keys
            cls = Data.define(*keys) do
              # 従来型の [] アクセスも提供
              def [](key) = respond_to?(key) ? public_send(key) : nil
              # パターンマッチング(deconstruct_keys)への対応
              def deconstruct_keys(keys) = to_h.slice(*keys)

              # dig メソッドの提供（既存コードとの互換性）
              def dig(*keys)
                keys.reduce(self) do |obj, key|
                  return nil unless obj.respond_to?(:[])

                  obj[key]
                end
              end

              # fetch メソッドの提供
              def fetch(key, default = nil)
                val = self[key]
                val.nil? ? default : val
              end
            end
            cls.new(**input.transform_values { wrap_config(it) })
          in Array
            input.map { wrap_config(it) }
          else
            input
          end
        end

        # ================================================================
        # Validation & Loading
        # ================================================================

        def ensure_required_yaml_files!
          REQUIRED_YAML_FILES.each do |path|
            abort_with_error("必須設定ファイルが見つかりません: #{path}") unless File.file?(path)

            case YAML.safe_load(File.read(path, encoding: 'utf-8'), aliases: true, symbolize_names: true)
            in Hash | Array
              # Valid
            else
              abort_with_error("必須設定ファイルの内容が空、または形式が不正です: #{path}")
            end
          rescue StandardError => e
            abort_with_error("必須設定ファイルの解析に失敗しました (#{path}): #{e.message}")
          end
        end

        # book.yml を読み込み、ハードコーディングされた既定値をマージして返す
        def load_config
          YAML.load_file(CONFIG_FILE, aliases: true, symbolize_names: true) => raw_config
          cfg = apply_page_preset(raw_config)
          merge_hardcoded_defaults(cfg)
        end

        # ハードコーディングされた既定値をマージする
        # book.yml に記述がなくても、これらの値は常に利用可能
        def merge_hardcoded_defaults(cfg)
          cfg.merge(
            directories: default_directories.merge(cfg[:directories] || {}),
            cache: default_cache.merge(cfg[:cache] || {}),
            commands: default_commands.merge(cfg[:commands] || {}),
            files: default_files.merge(cfg[:files] || {}),
            vivliostyle: default_vivliostyle.merge(cfg[:vivliostyle] || {}),
            vfm: default_vfm.merge(cfg[:vfm] || {})
          )
        end

        # --- Hardcoded Defaults (Data objects for immutability) ---
        def default_directories
          {
            config: CONFIG_DIR,
            contents: CONTENTS_DIR,
            stylesheets: STYLESHEETS_DIR,
            images: IMAGES_DIR,
            codes: CODES_DIR,
            templates: TEMPLATES_DIR,
            covers: COVERS_DIR
          }
        end

        def default_cache = { dir: CACHE_DIR, enabled: true }
        def default_commands = { vfm: VFM_COMMAND }
        def default_files = { post_replace: POST_REPLACE_FILE }

        def default_vivliostyle
          {
            quiet: true,
            reading_progression: 'ltr',
            entries_file: 'entries.js',
            config_file: VIVLIOSTYLE_CONFIG_FILE
          }
        end

        # VFM (Vivliostyle Flavored Markdown) の既定値設定
        # 日本語文章の直感的な執筆体験を提供するため、hardLineBreaks をデフォルト有効化
        def default_vfm
          {
            hardLineBreaks: true
          }
        end

        def apply_page_preset(cfg)
          case cfg
          in { page: { **page_cfg } }
            preset_name = page_cfg.values_at(*PAGE_PRESET_EXCLUDE_KEYS).find { _1 }
            return cfg if blank?(preset_name)

            presets = load_page_presets
            case presets[preset_name.to_sym]
            in Hash => selected
              overrides = page_cfg.reject { PAGE_PRESET_EXCLUDE_KEYS.include?(it) }
              merged = selected.merge(overrides).merge(page_cfg)
              cfg.merge(page: normalize_page_units(merged))
            else
              cfg
            end
          else
            cfg
          end
        end

        def load_page_presets
          YAML.load_file(PAGE_PRESETS_FILE, aliases: true, symbolize_names: true)
        end

        # ================================================================
        # Normalization (Unit conversion)
        # ================================================================

        def normalize_page_units(pcfg)
          pcfg.merge(
            **normalize_font_sizes(pcfg),
            base_line_height: normalize_line_height(pcfg)
          ).compact
        end

        def normalize_font_sizes(pcfg)
          FONT_SIZE_KEYS.each_with_object({}) do |key, memo|
            case pcfg[key]&.to_s&.strip
            in /q\z/i => s then memo[key] = q_to_pt(s)
            else # Skip
            end
          end
        end

        def normalize_line_height(pcfg)
          case [pcfg[:base_line_height]&.to_s&.strip, pt_value(pcfg[:base_font_size])]
          in [nil | '', _]         then nil
          in [_, nil]              then pcfg[:base_line_height]
          in [/pt\z/i => s, _]     then s
          in [/q\z/i => s, _]      then q_to_pt(s)
          in [/em\z/i => s, f_pt]  then format_pt(f_pt * s.to_f)
          in [/\A[\d.]+\z/ => s, f_pt] then format_pt(f_pt * s.to_f)
          in [other, _] then other
          end
        end

        def q_to_pt(value) = format_pt(value.to_f * 0.709)
        def pt_value(value) = value&.to_s&.match(/\A([\d.]+)pt\z/i)&.[](1)&.to_f
        def format_pt(value) = "#{value.to_f.round(3)}pt"

        # ================================================================
        # Log & UI
        # ================================================================

        # detail 行のインデント幅（半角スペース 8 文字）
        DETAIL_INDENT = '        '

        # --log オプションから現在のログレベルを解決する。
        # error: 0 / warn: 1 / info,success,action: 2 / debug: 3
        def current_log_level
          case ARGV
          in [*, /^--log=(.+)$/, *] then LEVELS[::Regexp.last_match(1).downcase] || 2
          in [*, '--log', level, *] if LEVELS.key?(level) then LEVELS[level]
          in [*, '--log', *] then 2
          else 1
          end
        end

        # 補足情報・処理の詳細（🔵）。--log=info 以上で表示。
        def log_info(msg)
          puts("🔵 #{msg}") if current_log_level >= 2
        end

        # 処理の成功（✅）。--log=info 以上で表示。
        def log_success(msg)
          puts("✅ #{msg}") if current_log_level >= 2
        end

        # 注意・警告（🟡）。--log=warn 以上（既定）で表示。
        def log_warn(msg, detail: nil)
          return unless current_log_level >= 1

          puts("🟡 #{msg}")
          format_detail(detail).each { |line| puts("#{DETAIL_INDENT}#{line}") }
        end

        # エラー（🔴）。ログレベルに関わらず常に表示。
        def log_error(msg, detail: nil)
          puts("🔴 #{msg}")
          format_detail(detail).each { |line| puts("#{DETAIL_INDENT}#{line}") }
        end

        # 処理ステップの開始・進行（🔧）。--log=info 以上で表示。
        def log_action(msg)
          puts("🔧 #{msg}") if current_log_level >= 2
        end

        # デバッグ情報（🧪）。--log=debug のみ表示。
        def log_debug(msg)
          puts("🧪 #{msg}") if current_log_level >= 3
        end

        # 検証結果の集計サマリー（🔍）。ログレベルに関わらず常に表示。
        def log_summary(msg, detail: nil)
          puts "🔍 #{msg}"
          format_detail(detail).each { |line| puts("#{DETAIL_INDENT}#{line}") }
        end

        # 詳細診断情報（🔍）。--log=info 以上で表示。
        def log_inspection(msg)
          puts "🔍 #{msg}" if current_log_level >= 2
        end

        # 処理の最終結果を報告する（✅/❌/📚）。ログレベルに関わらず常に表示。
        # @param status [:success, :failure, :artifact] アイコンの種別
        def log_result(msg, status:)
          icon = case status
                when :success  then "✅"
                when :failure  then "❌"
                when :artifact then "📚"
                end
          puts "#{icon} #{msg}"
        end

        # アイコンなしで常に表示する汎用出力。
        def log_always(msg)
          puts(msg)
        end

        # detail 文字列を行配列に変換する。nil の場合は空配列を返す。
        # log_* からのみ呼ばれる内部ヘルパー。
        def format_detail(detail)
          return [] if detail.nil?

          detail.lines.map(&:chomp)
        end
        private :format_detail

        # ------------------------------------------------------------
        # 外部コマンド可用性チェック
        # ------------------------------------------------------------
        # PATH を走査してコマンドが実行可能か判定する。
        # @param cmd [String] 実行形式コマンド名（絶対パスも可）
        # @return [Boolean]
        def external_command_available?(cmd)
          candidate = cmd.to_s.strip
          return false if candidate.empty?

          if candidate.include?(File::SEPARATOR)
            return File.executable?(candidate) && !File.directory?(candidate)
          end

          ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
            path = File.join(dir, candidate)
            File.executable?(path) && !File.directory?(path)
          end
        end

        # 外部コマンドが見つからない際の案内メッセージを生成する。
        # `vs doctor` / `vs doctor --fix` への誘導を含む。
        # @param cmd [String] 不足しているコマンド名
        # @param purpose [String, nil] 用途の人間向け説明（例: 'カバー画像生成'）
        # @return [String]
        def missing_external_command_message(cmd, purpose: nil)
          header = if purpose && !purpose.to_s.strip.empty?
                     "#{purpose}に必要な外部コマンドが見つかりません: #{cmd}"
                   else
                     "必要な外部コマンドが見つかりません: #{cmd}"
                   end
          <<~MSG.strip
            #{header}
            環境診断と自動セットアップを試すには:
                vs doctor         # 不足しているツールの一覧を表示
                vs doctor --fix   # macOS なら Homebrew で自動インストールを試行
          MSG
        end

        # コマンドが見つからない場合は vs doctor 案内付きで例外を送出する。
        # @param cmd [String] 実行形式コマンド名
        # @param purpose [String, nil] 用途説明
        # @raise [StandardError] コマンドが見つからない場合
        def ensure_external_command!(cmd, purpose: nil)
          return if external_command_available?(cmd)

          raise missing_external_command_message(cmd, purpose: purpose)
        end

        # 外部 SVG 変換コマンド（rsvg-convert / ImageMagick 等）を実行し、
        # 失敗した場合はユーザー向けの整形済みエラーメッセージを出力する。
        #
        # 堅牢性仕様 7-1: 不正な SVG XML 等で外部コマンドが失敗した際に、
        # 従来はサイレントに下流で `No such file` となっていた問題を解消する。
        #
        # @param argv [Array<String>] Kernel#system 相当のコマンド配列
        # @param input_path [String] 入力 SVG パス（エラーメッセージ表示用）
        # @param output_path [String, nil] 期待する出力ファイルのパス
        #   （nil 以外の場合、exit 成功でもファイル未生成なら失敗扱い）
        # @param purpose [String, nil] 用途の人間向け説明（例: 'カバー PDF 変換'）
        # @param env [Hash, nil] 追加の環境変数（例: FONTCONFIG_FILE）
        # @return [Boolean] 成功なら true、失敗なら false
        def run_svg_converter!(argv, input_path:, output_path: nil, purpose: nil, env: nil)
          require 'open3'

          capture_args = env&.any? ? [env, *argv] : argv
          _stdout, stderr, status = Open3.capture3(*capture_args)
          exit_ok   = status.success?
          file_ok   = output_path.nil? || File.exist?(output_path)
          return true if exit_ok && file_ok

          command_name = argv.first
          purpose_hint = purpose && !purpose.to_s.strip.empty? ? "（#{purpose}）" : ''
          reason       = if !exit_ok
                           "終了コード: #{status.exitstatus || 'unknown'}"
                         else
                           '出力ファイルが生成されませんでした'
                         end
          stderr_digest = format_converter_stderr(stderr)
          log_error(<<~MSG.strip)
            SVG 変換に失敗しました#{purpose_hint}: #{input_path}
              実行コマンド: #{command_name}
              #{reason}
              #{stderr_digest}
          MSG
          false
        rescue Errno::ENOENT => e
          log_error("SVG 変換コマンドが見つかりません: #{argv.first} (#{e.message})")
          false
        rescue StandardError => e
          log_error("SVG 変換中に予期せぬ例外が発生しました: #{e.class}: #{e.message} (input=#{input_path})")
          false
        end

        # run_svg_converter! 用に stderr テキストをユーザー向けに整形する。
        # 空のとき / 長すぎるときを吸収する。
        def format_converter_stderr(text)
          trimmed = text.to_s.strip
          return 'stderr: （出力なし）' if trimmed.empty?

          lines = trimmed.lines.map(&:chomp)
          shown = if lines.size > 12
                    head = lines.first(8)
                    tail = lines.last(3)
                    [*head, '  ... (中略) ...', *tail]
                  else
                    lines
                  end
          indented = shown.map { |l| "  #{l}" }.join("\n")
          "stderr:\n#{indented}"
        end

        def verbose?
          current_log_level >= 2
        end

        # ================================================================
        # Helpers
        # ================================================================

        def truthy?(val)
          case val&.to_s&.strip&.downcase
          in true | 'true' | 'yes' | 'on' | '1' then true
          else false
          end
        end

        def blank?(v) = v.nil? || v.to_s.strip.empty?

        # ================================================================
        # Path Utilities
        # ================================================================

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

        def ensure_cache_dir!
          dir = cache_dir
          FileUtils.mkdir_p(dir)
          dir
        end

        # ================================================================
        # Chapter Utilities
        # ================================================================

        def to_roman_lower(n)
          return '' if n.to_i <= 0

          n = n.to_i
          mapping = [
            [1000, 'm'], [900, 'cm'], [500, 'd'], [400, 'cd'],
            [100, 'c'], [90, 'xc'], [50, 'l'], [40, 'xl'],
            [10, 'x'], [9, 'ix'], [5, 'v'], [4, 'iv'], [1, 'i']
          ]
          mapping.each_with_object(String.new) do |(val, sym), res|
            count, n = n.divmod(val)
            res << (sym * count)
          end
        end

        # 付録の章番号をビルド対象の付録の順番に基づいてレター（a〜i）に変換する。
        # entries が渡された場合はその中の付録の順番を使い、
        # 渡されない場合は catalog.yml の付録一覧から順番を取得する。
        # @param num [Integer, String] 付録の章番号（90〜98）
        # @param entries [Array, nil] ビルド対象の Entry 配列（単章ビルド時に渡す）
        def appendix_number_to_letter(num, entries: nil)
          n = num.to_i
          return nil unless n.between?(90, 98)

          # ビルド対象のエントリが渡された場合はその中の付録の順番を使う
          appendix_entries = if entries
                               entries.select { it.kind == :appendix }.sort_by { it.number.to_i }
                             else
                               resolver = TokenResolver::Resolver.new
                               resolver.resolve.select { it.kind == :appendix }.sort_by { it.number.to_i }
                             end

          index = appendix_entries.index { it.number.to_i == n }
          return ('a'..'i').to_a[index] if index

          # 見つからない場合は章番号から直接計算（フォールバック）
          ('a'..'i').to_a[n - 90]
        rescue StandardError
          nil
        end

        # ================================================================
        # Page Size Utilities
        # ================================================================

        PAGE_SIZES = {
          'A4' => { width: '210mm', height: '297mm' },
          'A5' => { width: '148mm', height: '210mm' },
          'B5' => { width: '182mm', height: '257mm' }
        }.freeze

        # ページサイズを解決する（シンボルキー前提）
        def resolve_page_size(page_cfg)
          pcfg = page_cfg.is_a?(Hash) ? page_cfg : {}
          size = pcfg[:size].to_s.strip.upcase
          defaults = PAGE_SIZES[size] || PAGE_SIZES['B5']

          width  = pcfg[:width]&.to_s&.strip
          height = pcfg[:height]&.to_s&.strip

          [
            width.to_s.empty? ? defaults[:width] : width,
            height.to_s.empty? ? defaults[:height] : height
          ]
        end

        def normalize_page_size!(page_cfg)
          return page_cfg unless page_cfg.is_a?(Hash)

          w, h = resolve_page_size(page_cfg)
          page_cfg[:width] = w
          page_cfg[:height] = h
          page_cfg
        end

        # ================================================================
        # Output Filename Generation
        # ================================================================

        def generate_output_filename(target = 'pdf', suffix: nil)
          project = CONFIG[:project]
          project_name = project&.name || 'vivlio_starter'
          project_version = project&.version
          include_version = CONFIG.dig(:output, :filename, :include_version) || false

          filename = project_name.to_s.dup
          filename += '_print' if target == 'print_pdf'
          filename += "_v#{project_version}" if include_version && !blank?(project_version)
          if suffix && !blank?(suffix) && target == 'pdf'
            filename += (suffix.to_s.start_with?('_') ? suffix : "_#{suffix}")
          end

          ext = case target
                when 'pdf', 'print_pdf' then '.pdf'
                when 'epub' then '.epub'
                else '.pdf'
                end
          filename + ext
        end

        def generate_print_pdf_filename = generate_output_filename('print_pdf')
        def generate_epub_filename = generate_output_filename('epub')

        def generate_compressed_pdf_filename(target = 'pdf')
          # 新しい設定構造ではsuffixは"_compressed"に固定
          suffix = 'compressed'
          generate_output_filename(target, suffix: suffix)
        end

        # ================================================================
        # Build Timing & Step Tracking
        # ================================================================

        VIVLIOSTYLE_TIMINGS_KEY = :vivlio_starter_vivliostyle_timings
        VIVLIOSTYLE_CURRENT_STEP_KEY = :vivlio_starter_current_step_label

        def reset_vivliostyle_build_timings
          Thread.current[VIVLIOSTYLE_TIMINGS_KEY] = []
        end

        def record_vivliostyle_build(duration, label = nil)
          timings = Thread.current[VIVLIOSTYLE_TIMINGS_KEY] ||= []
          label_text = label.to_s.empty? ? 'Vivliostyle build' : label.to_s
          timings << { duration: duration.to_f, label: label_text }
        end

        def consume_vivliostyle_build_timings
          timings = Thread.current[VIVLIOSTYLE_TIMINGS_KEY] || []
          Thread.current[VIVLIOSTYLE_TIMINGS_KEY] = []
          timings
        end

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
        # Boolean Utilities
        # ================================================================

        # シンボルキーのみを前提としたブール値取得
        def fetch_bool(obj, keys, default: false)
          cur = obj
          Array(keys).each do |k|
            return default unless cur.respond_to?(:[])

            cur = cur[k.to_sym]
          end
          return default if cur.nil?

          truthy?(cur)
        rescue StandardError
          default
        end

        def abort_with_error(msg)
          log_error(msg)
          log_error('コマンドを中止します')
          exit 1
        end

        # 定数を安全に（警告なしで）再定義する
        # @param silent [Boolean] 初期ロード時はログ出力を抑制
        def reload_configuration!(silent: false)
          ensure_required_yaml_files!

          # load_configの結果をDataオブジェクトにラップしてフリーズ
          raw_config = load_config
          validate_book_config!(raw_config) unless silent
          new_config = wrap_config(raw_config).freeze

          # 定数の再定義（既存なら削除して警告を回避）
          remove_const(:CONFIG) if const_defined?(:CONFIG)
          const_set(:CONFIG, new_config)

          puts("🧪 Configuration reloaded: #{CONFIG_FILE}") if !silent && current_log_level >= 3
        end

        # book.yml の主要キー（book.main_title, book.author, project.name）が
        # 欠落していないかを検査し、欠落があれば警告を出す。
        # 既存の最小構成プロジェクトとの互換性を保つため abort はせず、
        # PDF 生成時にタイトルが空になる等の問題にユーザーが早期に気付けるようにする。
        # @param cfg [Hash] シンボルキー化された book.yml の内容
        def validate_book_config!(cfg)
          missing = []
          missing << 'book.main_title' if blank?(cfg.dig(:book, :main_title))
          missing << 'book.author'     if blank?(cfg.dig(:book, :author))
          missing << 'project.name'    if blank?(cfg.dig(:project, :name))
          return if missing.empty?

          warn "[book.yml] 警告: 以下の推奨キーが未設定です: #{missing.join(', ')}"
          warn "  config/book.yml を編集して値を設定してください。未設定のままでも動作しますが、"
          warn '  PDF のタイトル・著者・出力ファイル名が空欄になります。'
        end

        # 初期ロード実行（モジュール定義時は静かに）
        # プロジェクト外（book.yml なし）でも --version, --help, new, doctor が
        # 動作するよう、設定ファイルが見つからない場合は CONFIG を nil にとどめる。
        if REQUIRED_YAML_FILES.all? { |f| File.file?(f) }
          reload_configuration!(silent: true)
        else
          remove_const(:CONFIG) if const_defined?(:CONFIG)
          const_set(:CONFIG, nil)
        end

        # CONFIG が未ロード（プロジェクト外）の場合に呼び出し元で検査するためのヘルパー
        def configured? = !CONFIG.nil?

        def ensure_configured!
          return if configured?

          abort_with_error('必須設定ファイルが見つかりません: config/book.yml')
        end

        # ================================================================
        # 派生定数（CONFIG から動的に取得）
        # ================================================================

        # ディレクトリ関連
        def config_dir         = CONFIG&.directories&.config || CONFIG_DIR
        def config_dir_path    = resolve_path_from_root(config_dir)
        def contents_dir       = CONFIG&.directories&.contents || CONTENTS_DIR
        def stylesheets_dir    = CONFIG&.directories&.stylesheets || STYLESHEETS_DIR
        def images_dir         = CONFIG&.directories&.images || IMAGES_DIR
        def codes_dir          = CONFIG&.directories&.codes || CODES_DIR
        def templates_dir      = CONFIG&.directories&.templates || TEMPLATES_DIR
        def covers_dir         = CONFIG&.directories&.covers || COVERS_DIR

        def template_path(name)
          File.join(templates_dir, "#{name}.md")
        end

        def chapter_template_path = template_path('chapter')
        def preface_template_path = template_path('preface')
        def appendix_template_path = template_path('appendix')
        def postface_template_path = template_path('postface')

        # キャッシュ関連
        def cache_cfg          = CONFIG&.cache
        def cache_dir          = CONFIG&.cache&.dir || CACHE_DIR
        def cache_enabled?     = CONFIG&.cache&.enabled != false

        # コマンド関連
        def vfm_command        = CONFIG&.commands&.vfm || VFM_COMMAND

        # ファイル関連
        def post_replace_file  = CONFIG&.files&.post_replace || POST_REPLACE_FILE

        def post_replace_file_path
          file = post_replace_file
          return nil if blank?(file)

          pn = Pathname.new(file)
          base = Pathname.new(config_dir)
          pn = base.join(pn) unless pn.absolute?
          pn.cleanpath.to_s
        rescue StandardError
          resolve_path_from_root(file)
        end

        # カバー設定関連
        def cover_theme        = CONFIG.dig('output', 'cover')
        def pdf_combined?      = CONFIG.dig('output', 'pdf', 'combined') == true
        def pdf_compress?      = CONFIG.dig('output', 'pdf', 'compress') == true
        def epub_embed?        = CONFIG.dig('output', 'epub', 'embed') == true

        # カバー設定のバリデーション
        def validate_cover_settings
          theme = cover_theme
          unless theme
            log_error('output.cover 設定が見つかりません')
            return false
          end

          # 標準テーマの場合は有効
          return true if %w[light dark].include?(theme)

          # masterテーマは特別扱い（既存のmaster.pngファイルを使用）
          if theme == 'master'
            front_path = File.join(covers_dir, "frontcover_#{theme}.png")
            back_path  = File.join(covers_dir, "backcover_#{theme}.png")

            unless File.exist?(front_path) && File.exist?(back_path)
              log_error("マスター画像 '#{theme}' のPNGファイルが見つかりません")
              return false
            end
            return true
          end

          # カスタムテーマの場合は命名規則をチェック
          unless theme.match?(/\A[a-z0-9_]+\z/)
            log_error("テーマ名 '#{theme}' は無効な形式です")
            return false
          end

          # カスタムテーマの場合はPNGファイルの存在を確認
          front_path = File.join(covers_dir, "frontcover_#{theme}.png")
          back_path  = File.join(covers_dir, "backcover_#{theme}.png")

          unless File.exist?(front_path) && File.exist?(back_path)
            log_error("カスタム画像 '#{theme}' のPNGファイルが見つかりません")
            return false
          end

          true
        end

        # エンドレスメソッド定義を module_function として明示的に公開
        module_function :abort_with_error, :appendix_number_to_letter, :apply_page_preset, :configured?, :ensure_configured!,
                        :ensure_external_command!, :external_command_available?,
                        :missing_external_command_message, :run_svg_converter!, :format_converter_stderr,
                        :blank?, :cache_cfg, :cache_dir, :cache_enabled?,
                        :stylesheets_dir, :templates_dir, :to_roman_lower,
                        :template_path, :chapter_template_path, :preface_template_path,
                        :appendix_template_path, :postface_template_path,
                        :config_dir_path,
                        :consume_vivliostyle_build_timings, :contents_dir, :covers_dir,
                        :cover_theme, :pdf_combined?, :pdf_compress?, :epub_embed?,
                        :current_log_level, :current_step_label, :default_cache,
                        :default_commands, :default_directories, :default_files,
                        :default_vfm, :default_vivliostyle, :log_always, :ensure_cache_dir!,
                        :ensure_required_yaml_files!, :fetch_bool, :format_pt,
                        :generate_compressed_pdf_filename, :generate_epub_filename,
                        :generate_output_filename, :generate_print_pdf_filename,
                        :images_dir, :load_config, :load_page_presets, :log_action,
                        :log_debug, :log_error, :log_info, :log_success, :log_warn,
                        :merge_hardcoded_defaults, :normalize_font_sizes,
                        :normalize_line_height, :normalize_page_size!,
                        :normalize_page_units, :post_replace_file, :post_replace_file_path,
                        :pt_value, :q_to_pt, :record_vivliostyle_build,
                        :reload_configuration!, :relative_path_from_root, :validate_book_config!,
                        :resolve_page_size, :resolve_path_from_root,
                        :reset_vivliostyle_build_timings, :stylesheets_dir, :to_roman_lower,
                        :truthy?, :vfm_command, :validate_cover_settings, :verbose?, :with_current_step_label,
                        :wrap_config
      end
    end
  end
end
