# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'yaml'
require_relative 'units'

# Common::CONFIG — book.yml の再帰的 Data ラッパー
# 正規記法（The One Way）は docs/specs/config-access-unification-spec.md §2 を参照。
# * 静的キーはドット記法:   Common::CONFIG.book.main_title
# * 動的キーはシンボル:     Common::CONFIG[section] / CONFIG.dig(:a, :b)（Symbol のみ。String は不可）
# * パターンマッチ対応:     case Common::CONFIG in { page: { size: } } ...
# * 安全な設定変更:         著者が book.yml を編集した後は reload_configuration! で最新化
# * 不変性の保証:           .freeze により、ビルド実行中の誤った書き換えを防止
# * 存在保証:               default_config_schema が全セクション・既知キーを保証（未設定は nil）

module VivlioStarter
  module CLI
    module Common
      module_function

      # --- 定数定義 ---
      REQUIRED_YAML_FILES = %w[
        config/book.yml config/catalog.yml config/page_presets.yml
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
      DATA_DIR = 'data'
      CODES_DIR = 'codes'
      TEMPLATES_DIR = 'templates'
      COVERS_DIR = 'covers'
      VFM_COMMAND = 'vfm'
      CACHE_DIR = '.cache/vs'
      # 旧バージョン（撤去済み手動フロー）のルート config 名。
      # doctor の旧プロジェクト検出マーカーとしてのみ参照する。
      VIVLIOSTYLE_CONFIG_FILE = 'vivliostyle.config.js'

      # ------------------------------------------------------------
      # ビルドワークスペース（P4: 中間生成物の分離場所）
      # ------------------------------------------------------------
      # 中間 md/HTML/中間 PDF/EPUB 作業物はルートではなくこの配下に閉じる。
      # 4 消費者 dir は同一深度（ルートから 4 階層）にすることが仕様の要:
      # 資産への相対プレフィックスが全消費者で共通になり、html/ から
      # 消費者 dir へのコピーが無加工（バイト同一）で成立する（P4 §3.1）。
      BUILD_DIR        = "#{CACHE_DIR}/build"
      BUILD_HTML_DIR   = "#{BUILD_DIR}/html"
      BUILD_PDF_DIR    = "#{BUILD_DIR}/pdf"
      BUILD_EPUB_DIR   = "#{BUILD_DIR}/epub"
      BUILD_KINDLE_DIR = "#{BUILD_DIR}/kindle"

      # 索引スキャン結果の中間 YAML（書き手 IndexMatchScanner・読み手 UnifiedPageBuilder）。
      # ルートではなくワークスペース直下へ置き、ルート無汚染を保つ（P4b §2.5）。
      INDEX_MATCHES_FILE = "#{BUILD_DIR}/_index_matches.yml"

      # ------------------------------------------------------------
      # 再生成コストの高い生成資産のキャッシュ（generated-assets 移設仕様 §2）
      # ------------------------------------------------------------
      # BUILD_DIR の外に置くのが要点: final clean（rm_rf BUILD_DIR）を生き延び、
      # waifu2x を伴う高コストなバリアント生成や covers の毎ビルド再生成を避ける。
      # 前処理の生成資産（mermaid / showcase / math）も同方針で CACHE_DIR 配下に置く
      # （PreProcessCommands::GeneratedAssetCache が .cache/vs/<種別>/ を管理する）。
      COVER_CACHE_DIR        = "#{CACHE_DIR}/covers"
      THEME_IMAGES_CACHE_DIR = "#{CACHE_DIR}/theme-images"

      # 中間 HTML/md から著者資産（stylesheets/ images/ 等）への相対プレフィックス。
      # 生成時に正しいプレフィックスで書く（コピー時 gsub はしない）が P4 §3.3 の方針。
      # 資産参照を生成する choke point（FrontmatterGenerator / ImagePathNormalizer /
      # MathTransformer / Techbook::Processor / TocGenerator / UnifiedPageBuilder）は
      # 必ずこの値を参照すること。
      # ワークスペース（ルートから 4 階層）からルート資産への上方参照。
      ASSET_PREFIX = '../../../../'

      # ================================================================
      # Recursive Data Wrapper (Ruby 4.0 Style)
      # ================================================================

      # Data の既存メソッドと衝突すると [] やドット記法が member を返せなくなるため、
      # ロード時に警告する（dig は wrap_config が後付けするメソッド）
      RESERVED_CONFIG_KEYS = (Data.instance_methods | %i[dig]).freeze

      # Hashを再帰的にDataオブジェクトに変換するヘルパー
      # ドット記法と [] アクセスの両方を提供します
      # 正規記法は docs/specs/config-access-unification-spec.md §2 を参照
      def wrap_config(input)
        case input
        in Hash
          # キーを動的にDataの属性として定義
          keys = input.keys
          warn_reserved_config_keys(keys)
          cls = Data.define(*keys) do
            # 動的キー用の [] アクセス（Symbol 限定・member 限定）。
            # respond_to? ベースだと to_h 等のメソッド戻り値が漏れるため member 限定とし、
            # String キーは記法混在の再発を防ぐため即座にエラーにする（The One Way）。
            def [](key)
              raise ArgumentError, "CONFIG のキーは Symbol で指定してください（String は不可）: #{key.inspect}" if key.is_a?(String)

              members.include?(key) ? public_send(key) : nil
            end

            # パターンマッチング(deconstruct_keys)への対応。
            # keys が nil のとき全体を返すのは Ruby の規約（`in { **rest }` で全キーを束縛可能にする）
            def deconstruct_keys(keys) = keys.nil? ? to_h : to_h.slice(*keys)

            # 動的な多段アクセス用の dig（Symbol キーのみ。配列添字の Integer は可）
            def dig(*keys)
              keys.reduce(self) do |obj, key|
                return nil unless obj.respond_to?(:[])

                obj[key]
              end
            end
          end
          cls.new(**input.transform_values { wrap_config(it) })
        in Array
          input.map { wrap_config(it) }
        else
          input
        end
      end

      # book.yml のキーが Data の予約メソッド名と衝突していないかを検査する。
      # 衝突すると member 定義がメソッドを上書き（またはその逆）して静かに誤動作するため、
      # ロード時に著者へ改名を促す。
      def warn_reserved_config_keys(keys)
        reserved = keys.map { it.respond_to?(:to_sym) ? it.to_sym : it } & RESERVED_CONFIG_KEYS
        return if reserved.empty?

        log_warn("book.yml のキー名 #{reserved.join(', ')} は予約名のため正しく参照できません。別名への変更を推奨します（例: hash → hash_value）")
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
            abort_with_error("必須設定ファイルの内容が空、または形式が不正です: #{path}\n        修復するには vs doctor --fix を実行してください（破損ファイルはバックアップを取得します）")
          end
        rescue StandardError => e
          abort_with_error("必須設定ファイルの解析に失敗しました (#{path}): #{e.message}\n        修復するには vs doctor --fix を実行してください（破損ファイルはバックアップを取得します）")
        end
      end

      # 必須 YAML がすべて存在し、かつ解析可能かを abort せずに判定する。
      # モジュール初期ロードで使用（破損時に起動ごと止めてしまうと、修復手段で
      # ある vs doctor --fix 自体が実行できなくなるため）
      def required_yaml_files_loadable?
        REQUIRED_YAML_FILES.all? do |path|
          File.file?(path) &&
            (YAML.safe_load(File.read(path, encoding: 'utf-8'), aliases: true, symbolize_names: true) in Hash | Array)
        rescue StandardError
          false
        end
      end

      # book.yml を読み込み、ハードコーディングされた既定値をマージして返す
      def load_config
        YAML.load_file(CONFIG_FILE, aliases: true, symbolize_names: true) => raw_config
        cfg = apply_page_preset(raw_config)
        merge_hardcoded_defaults(cfg)
      end

      # ハードコーディングされた既定値スキーマをマージする
      # book.yml に記述がなくても全セクション・既知キーが常に存在し、
      # CONFIG.lint.config のようなドット記法が安全になる（値未設定なら nil）。
      # 仕様: docs/specs/config-access-unification-spec.md §2.2
      def merge_hardcoded_defaults(cfg)
        default_config_schema.merge(cfg) { |_key, default_val, user_val| deep_merge_config(default_val, user_val) }
      end

      # 既定値と book.yml の値を再帰的にマージする。
      # 著者が「キーだけ書いて値を空欄」にした場合（nil）は既定値を採用する。
      # false は明示的な設定として尊重する（nil のみ既定値扱い）。
      def deep_merge_config(default, user)
        case [default, user]
        in [Hash => d, Hash => u] then d.merge(u) { |_k, dv, uv| deep_merge_config(dv, uv) }
        in [_, nil] then default
        else user
        end
      end

      # book.yml の全セクションの既定値スキーマ。
      # コードが参照する既知キーを列挙し、未設定時のドット記法アクセスを保証する。
      # nil は「既定値なし（未設定）」を表し、実際の既定値は従来どおり参照側が決める。
      def default_config_schema
        {
          book: { main_title: nil, subtitle: nil, subtitle_style: nil, title: nil, series: nil,
                  release: nil, publisher: nil, contact: nil, author: nil, language: nil, isbn: nil },
          project: { name: nil, version: nil },
          theme: { style: nil, color: nil, preface_color: nil, appendix_color: nil,
                   frontispiece: nil, ornament: nil, markers: { h3: nil, h4: nil } },
          # page の版面キー（size/width/margin_* 等）は page_presets 由来のため列挙しない
          page: { use: nil },
          typography: { body: { font: nil }, heading: { font: nil },
                        column: { font: nil, font_size: nil }, code: { font: nil },
                        folio: { font: nil, placement: nil } },
          legal: { disclaimer: nil, trademark: nil, twemoji: nil },
          output: { targets: nil, cover: nil,
                    filename: { include_version: nil },
                    pdf_preview: { close_existing_windows: nil, window_bounds: nil },
                    pdf: { combined: nil, compress: nil, techbook: nil },
                    print_pdf: { bleed: nil, crop_marks: nil, full_bleed: nil },
                    epub: { embed: nil, layout: nil },
                    kindle: { embed: nil, layout: nil } },
          build: { verify: { images: nil, bare_urls: nil, external_links: nil,
                             timeout: nil, max_concurrency: nil } },
          index_glossary: { enabled: nil, use_mecab: nil, timezone: nil,
                            context_width: nil, smart_context_cutting: nil,
                            library: nil },
          index: { auto_discovery: nil, title: nil, auto_approve_threshold: nil,
                   review_threshold: nil, high_candidates_ratio: nil, backlink_dedup: nil },
          glossary: { title: nil, require_definition: nil, max_definition_length: nil,
                      backlink_dedup: nil },
          # ビルド対象章の絞り込み（例: "54-56" / [11, 12]）。未指定はフルビルド
          chapters: nil,
          metrics: { use: nil, exclude_chapters: nil, kanji_ratio: nil, word_length: nil,
                     ttr: nil, mattr_window: nil, sentence_length: nil, clause_length: nil,
                     readability: nil, labels: nil },
          lint: { config: nil, disabled_rules: nil, disabled_terms: nil, sentence_length_max: nil,
                  trim_long_vowel: nil, allow_space_around_code: nil, allow_space_between_ja_en: nil },
          spellcheck: { extra_dictionaries: nil, extra_words: nil, ignore_words: nil,
                        check_code_blocks: nil },
          pdf_read: { text_area: { top_margin: nil, bottom_margin: nil,
                                   inner_margin: nil, outer_margin: nil },
                      page_separator: nil,
                      ocr: { mode: nil, languages: nil, dpi: nil, psm: nil, inline_image_text: nil } },
          directories: default_directories,
          cache: default_cache,
          commands: default_commands,
          vivliostyle: default_vivliostyle,
          vfm: default_vfm
        }
      end

      # --- Hardcoded Defaults (Data objects for immutability) ---
      def default_directories
        {
          config: CONFIG_DIR,
          contents: CONTENTS_DIR,
          stylesheets: STYLESHEETS_DIR,
          images: IMAGES_DIR,
          data: DATA_DIR,
          codes: CODES_DIR,
          templates: TEMPLATES_DIR,
          covers: COVERS_DIR,
          # pdf:read の入力 PDF 置き場（任意設定・既定なし）
          sources: nil
        }
      end

      def default_cache = { dir: CACHE_DIR, enabled: true }
      def default_commands = { vfm: VFM_COMMAND }

      def default_vivliostyle
        {
          quiet: true,
          reading_progression: 'ltr'
        }
      end

      # VFM (Vivliostyle Flavored Markdown) の既定値設定
      # 日本語文章の直感的な執筆体験を提供するため、hard_line_breaks をデフォルト有効化
      # （book.yml では snake_case。VFM 自体のフロントマターキーは camelCase の hardLineBreaks）
      def default_vfm
        {
          hard_line_breaks: true
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
            # プリセット既定 < 著者インライン値（page_cfg）。page_cfg は use 等の選択子キーも
            # 含むが、選択子は既に消費済みで害はない（仕様 §3.6）。
            cfg.merge(page: normalize_page_units(selected.merge(page_cfg)))
          else
            cfg
          end
        else
          cfg
        end
      end

      # safe_load_file に統一（ensure_required_yaml_files! の検証経路と同一ポリシー）。
      # aliases はプリセットの差分定義（<<: *a5_std）に必須のため許可する。
      def load_page_presets
        YAML.safe_load_file(PAGE_PRESETS_FILE, aliases: true, symbolize_names: true)
      end

      # ================================================================
      # Normalization (Unit conversion)
      # ================================================================

      # page 設定の単位を正規化する（仕様: docs/specs/page-unit-conversion-spec.md §3.3）。
      # 文字サイズを先に pt 化し、その結果を基準に行送り（倍率/em）を絶対 pt へ解決する。
      # 行送りを倍率のまま CSS へ渡さないのは、参照箇所ごとの font-size に依存させず
      # 版面の行グリッドを揃えるため（同 §1.3）。
      def normalize_page_units(pcfg)
        sized = pcfg.merge(**normalize_font_sizes(pcfg))
        sized.merge(base_line_height: normalize_line_height(sized)).compact
      end

      def normalize_font_sizes(pcfg)
        FONT_SIZE_KEYS.each_with_object({}) do |key, memo|
          normalized = Units.font_size_to_pt(pcfg[key])
          memo[key] = normalized if normalized
        end
      end

      def normalize_line_height(pcfg)
        case [pcfg[:base_line_height]&.to_s&.strip, Units.pt_value(pcfg[:base_font_size])]
        in [nil | '', _]             then nil
        in [/pt\z/i => s, _]         then s
        in [/q\z/i => s, _]          then Units.format_pt(s.to_f * Units::PT_PER_Q)
        in [_, nil]                  then pcfg[:base_line_height]
        in [/em\z/i => s, f_pt]      then Units.format_pt(f_pt * s.to_f)
        in [/\A[\d.]+\z/ => s, f_pt] then Units.format_pt(f_pt * s.to_f)
        in [other, _]                then other
        end
      end

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

        # ビルド対象のエントリ（付録を含む非空配列）が渡された場合のみ、その並びを使う。
        # 空配列は「指定なし」として扱い catalog 全体から付録順を取り直す。
        # （フルビルドでは本文章のみの override が渡され、付録抽出後に空配列となるため、
        #   ここで全体 resolve に委ねないと末尾フォールバックに落ちて採番がずれる）
        appendix_entries = if entries && !entries.empty?
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
        # 'B5' は技術書慣習により JIS 寸法（182×257）の別名。ISO B5（176×250）は非サポート。
        'B5' => { width: '182mm', height: '257mm' },
        'JIS-B5' => { width: '182mm', height: '257mm' }
      }.freeze

      # ページサイズを解決する（シンボルキーの Hash 前提）
      # CONFIG.page（Data）を渡す場合は呼び出し側の境界で .to_h してから渡す（spec §2.4）
      def resolve_page_size(pcfg)
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
        project = CONFIG&.project
        project_name = project&.name || 'vivlio_starter'
        project_version = project&.version
        include_version = CONFIG&.output&.filename&.include_version || false

        filename = project_name.to_s.dup
        filename += '_print' if target == 'print_pdf'
        filename += "_v#{project_version}" if include_version && !blank?(project_version)
        if suffix && !blank?(suffix) && target == 'pdf'
          filename += (suffix.to_s.start_with?('_') ? suffix : "_#{suffix}")
        end

        ext = case target
              when 'pdf', 'print_pdf' then '.pdf'
              when 'epub' then '.epub'
              when 'kindle' then '.kpf'
              else '.pdf'
              end
        filename + ext
      end

      def generate_print_pdf_filename = generate_output_filename('print_pdf')

      # 印刷カバー PDF のルート成果品名（generated-assets 移設仕様 §3.4）。
      # generate_output_filename と同じ include_version 規則に従う。
      # 例: vivlio_starter_frontcover_v1.0.0.pdf
      # @param side [String, Symbol] 'front' | 'back'
      # @return [String]
      def generate_cover_output_filename(side)
        project = CONFIG&.project
        include_version = CONFIG&.output&.filename&.include_version || false

        filename = "#{project&.name || 'vivlio_starter'}_#{side}cover"
        filename += "_v#{project&.version}" if include_version && !blank?(project&.version)
        "#{filename}.pdf"
      end
      def generate_epub_filename = generate_output_filename('epub')
      # Kindle の最終成果物（KPF・ルート直下）。例: vivlio_starter_v1.0.0.kpf
      def generate_kpf_filename = generate_output_filename('kindle')
      # Kindle 用の中間 EPUB（kindlepreviewer の入力）。KPF 生成後は削除される（§1-4）。
      # 例: vivlio_starter_v1.0.0-kindle.epub
      def generate_kindle_epub_filename = generate_kpf_filename.sub(/\.kpf\z/, '-kindle.epub')

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
      # 破損（YAML 解析不能）の場合も同様に nil とする。ロード時に abort すると
      # 修復手段である vs doctor --fix 自体が起動できなくなるため、検出・報告は
      # 各コマンドの ensure_configured! と doctor の診断に委ねる（Phase 5）。
      if required_yaml_files_loadable?
        reload_configuration!(silent: true)
      else
        remove_const(:CONFIG) if const_defined?(:CONFIG)
        const_set(:CONFIG, nil)
      end

      # CONFIG が未ロード（プロジェクト外）の場合に呼び出し元で検査するためのヘルパー
      def configured? = !CONFIG.nil?

      def ensure_configured!
        return if configured?

        # 欠落と破損で正確な理由を出し分けるため、ファイル単位の検証に委ねて abort する
        # （破損時は vs doctor --fix による修復導線も案内される）
        ensure_required_yaml_files!
        abort_with_error('設定ファイルの読み込みに失敗しました: config/book.yml')
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
      def data_dir           = CONFIG&.directories&.data || DATA_DIR
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

      # 生成資産キャッシュ（covers 生成物・テーマ画像バリアント）。
      # cache.dir 設定で cache_dir が変わっても追従するようヘルパ経由で参照する。
      def cover_cache_dir        = File.join(cache_dir, 'covers')
      def theme_images_cache_dir = File.join(cache_dir, 'theme-images')

      # ワークスペース関連（P4）
      def asset_prefix       = ASSET_PREFIX
      def build_dir          = BUILD_DIR
      def build_html_dir     = BUILD_HTML_DIR
      def build_pdf_dir      = BUILD_PDF_DIR
      def index_matches_file = INDEX_MATCHES_FILE

      # 4 消費者 dir を作成してワークスペースを準備する
      def ensure_build_workspace!
        [BUILD_HTML_DIR, BUILD_PDF_DIR, BUILD_EPUB_DIR, BUILD_KINDLE_DIR].each { FileUtils.mkdir_p(it) }
        BUILD_DIR
      end

      # コマンド関連
      def vfm_command        = CONFIG&.commands&.vfm || VFM_COMMAND

      # カバー設定関連（CONFIG&. は CONFIG 未ロード（プロジェクト外）を吸収する。
      # 各セクションは既定値スキーマで存在保証されるため、以降はドットで辿れる）
      def cover_theme        = CONFIG&.output&.cover
      def pdf_combined?      = CONFIG&.output&.pdf&.combined == true
      def pdf_compress?      = CONFIG&.output&.pdf&.compress == true
      def epub_embed?        = CONFIG&.output&.epub&.embed == true
      # Kindle 表紙の埋め込み。未設定時は false（二重表紙回避・§1-6）。
      def kindle_embed?      = CONFIG&.output&.kindle&.embed == true
      # 本文にフチなし（塗り足しまで届く）要素があるか。true の本は閲覧用 PDF から
      # 塗り足しを復元できないため、入稿用 PDF を個別レンダリングする（既定 false = 導出）。
      def print_pdf_full_bleed? = truthy?(CONFIG&.output&.print_pdf&.full_bleed)

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
                      :cover_cache_dir, :theme_images_cache_dir, :generate_cover_output_filename,
                      :asset_prefix, :build_dir, :build_html_dir, :build_pdf_dir,
                      :index_matches_file, :ensure_build_workspace!,
                      :stylesheets_dir, :templates_dir, :to_roman_lower,
                      :template_path, :chapter_template_path, :preface_template_path,
                      :appendix_template_path, :postface_template_path,
                      :config_dir_path,
                      :consume_vivliostyle_build_timings, :contents_dir, :covers_dir,
                      :cover_theme, :pdf_combined?, :pdf_compress?, :epub_embed?, :kindle_embed?,
                      :print_pdf_full_bleed?,
                      :current_log_level, :current_step_label, :deep_merge_config, :default_cache,
                      :default_commands, :default_config_schema, :default_directories,
                      :default_vfm, :default_vivliostyle, :log_always, :ensure_cache_dir!,
                      :ensure_required_yaml_files!, :required_yaml_files_loadable?,
                      :generate_compressed_pdf_filename, :generate_epub_filename,
                      :generate_kpf_filename, :generate_kindle_epub_filename,
                      :generate_output_filename, :generate_print_pdf_filename,
                      :images_dir, :data_dir, :load_config, :load_page_presets, :log_action,
                      :log_debug, :log_error, :log_info, :log_success, :log_warn,
                      :merge_hardcoded_defaults, :normalize_font_sizes,
                      :normalize_line_height, :normalize_page_size!,
                      :normalize_page_units,
                      :record_vivliostyle_build,
                      :reload_configuration!, :relative_path_from_root, :validate_book_config!,
                      :resolve_page_size, :resolve_path_from_root,
                      :reset_vivliostyle_build_timings, :stylesheets_dir, :to_roman_lower,
                      :truthy?, :vfm_command, :validate_cover_settings, :verbose?, :warn_reserved_config_keys,
                      :with_current_step_label, :wrap_config
    end
  end
end
