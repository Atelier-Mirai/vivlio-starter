# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/book_settings_css.rb
# ================================================================
# 責務:
#   config/book.yml のビルド設定を単一の生成ファイル
#   `.cache/vs/book-settings.css` へ「全文書き出し」する。
#
# 設計背景（課題 C / VivlioVerso 基盤整備 P3）:
#   従来は CssUpdater が theme.css / page-settings.css 等のソース CSS を
#   毎ビルド正規表現で in-place 書換していた。これはソース CSS を可変化させ
#   （book.yml を変えると git 差分が出る）、テーマ CSS セットの差し替えを阻む。
#   本生成器は「既存 CSS は不変のまま、後段でカスケードして勝つ 1 枚」を出力し、
#   ソース CSS を読み取り専用のテーマ資産に戻す。
#
#   値の計算ロジックは実証済みの CssUpdater の補助メソッド
#   （calculate_paper_scale / calculate_align_max_width / apply_folio_placement! /
#    format_font_value / normalize_color_value / build_css_variable_mappings 等）を
#   そのまま流用する。変わるのは「差し込み方」だけ。
#
# 出力先とカスケード:
#   章 HTML の link 順は [theme.css, {種別}.css, book-settings.css, custom.css]。
#   book-settings.css は {種別}.css（→ page-settings.css / theme.css を @import）の
#   後に読み込まれるため、同名変数の再宣言が既存 CSS 値に勝つ。
#
# 画像 URL の基準:
#   生成ファイルは `.cache/vs/` 直下に置かれるため、stylesheets/ 基準の相対
#   （例: images/bundled/x.webp）は `../../stylesheets/images/bundled/x.webp` へ
#   組み替える。data:/http(s):/絶対パスは不変（調査報告 §7.3-1）。
# ================================================================

require 'fileutils'
require_relative '../common'
require_relative '../font_manager'
require_relative '../theme_color'
require_relative '../build/vivliostyle_config_writer'
require_relative 'css_updater'
require_relative 'frontmatter_generator'
require_relative 'talk_registry'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # book-settings.css 生成モジュール
      module BookSettingsCss
        module_function

        # 生成ファイルのパス（.cache/vs/book-settings.css）。
        def output_path = File.join(Common::CACHE_DIR, 'book-settings.css')

        # `.cache/vs/` から `stylesheets/` への相対プレフィックス。
        # 生成ファイルは 2 階層深いため、stylesheets/ 基準の相対 URL をこの接頭辞で組み替える。
        CACHE_TO_STYLESHEETS = '../../stylesheets/'

        # book-settings.css を生成し、フォント準備と config.js 同期も行う。
        # プレフライト/フル/単章の全モードで 'prepare theme images' ステップから呼ばれる。
        # @param cfg [Object, nil] 設定オブジェクト（省略時は Common::CONFIG）
        # @return [String, nil] 生成したファイルパス（失敗時 nil）
        def generate!(cfg = nil)
          cfg ||= Common::CONFIG

          # --- Phase: CSS 全文を組み立てて書き出す ---
          css = render(cfg)
          path = output_path
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, css, encoding: 'utf-8')

          # --- Phase: CSS 書換とは独立に必要な副作用（旧 update_all_css_files から引越し）---
          ensure_fonts_available(cfg)

          Common.log_success('[Step 2] book-settings.css を生成しました')
          path
        rescue StandardError => e
          Common.log_warn("[Step 2] book-settings.css の生成に失敗: #{e.message}")
          nil
        end

        # 生成する CSS 全文を組み立てる（副作用なし・テスト対象）。
        # @param cfg [Object] 設定オブジェクト
        # @param image_prefix [String] 画像 URL 組替の接頭辞（EPUB 変種では差し替える）
        # @return [String]
        def render(cfg = Common::CONFIG, image_prefix: CACHE_TO_STYLESHEETS)
          settings = FrontmatterGenerator.parse_theme_settings(cfg)
          page_cfg = build_page_cfg(cfg)
          registry = TalkRegistry.load

          root_lines = []
          root_lines.concat(theme_declarations(settings, image_prefix:))
          root_lines.concat(supplemental_color_declarations(settings, cfg))
          root_lines.concat(marker_declarations(cfg))
          root_lines.concat(page_declarations(page_cfg))
          root_lines.concat(talk_variable_declarations(registry))

          <<~CSS
            #{header_comment}
            #{page_size_rule(page_cfg)}
            #{frontispiece_position_rule(settings, page_cfg)}
            :root {
            #{root_lines.map { "  #{it}" }.join("\n")}
            }
            #{section_page_break_rule(page_cfg)}
            #{kindle_accent_rules(cfg)}
            #{talk_class_rules(registry)}
          CSS
        end

        # 生成ファイル先頭の注意書き。
        def header_comment
          <<~COMMENT.chomp
            /* 自動生成: config/book.yml のビルド設定（手編集しない）
               生成器: VivlioStarter::CLI::PreProcessCommands::BookSettingsCss
               ソース CSS（stylesheets/*.css）は読み取り専用のテーマ資産。
               設定変更は config/book.yml を編集すること。 */
          COMMENT
        end

        # ================================================================
        # theme 系変数（旧 update_theme_css 相当）
        # ================================================================
        # 条件付き宣言のセマンティクスを in-place 版と一致させる（調査報告 §7.3-2）:
        #   - simple スタイル: 画像 2 変数は none、frontispiece-padding は宣言しない
        #   - image スタイル : 画像 2 変数＋padding を宣言
        #   - heading/lead width は値がある時だけ宣言
        def theme_declarations(settings, image_prefix:)
          lines = [
            "--theme-accent: #{settings[:theme_accent_value]};",
            '--color-strong: var(--theme-accent);',
            '--color-em-underline: var(--theme-accent);'
          ]

          if settings[:theme_style] == 'simple'
            lines << '--section-bg-image: none;'
            lines << '--frontispiece-image: none;'
          else
            lines << "--section-bg-image: #{css_image_value(settings[:ornament_path], image_prefix:)};"
            lines << "--frontispiece-image: #{css_image_value(settings[:frontispiece_path], image_prefix:)};"
            lines << "--frontispiece-padding: #{settings[:door_padding_value]};"
          end

          lines << "--frontispiece-heading-width: #{settings[:heading_width_value]};" if settings[:heading_width_value]
          lines << "--frontispiece-lead-width: #{settings[:lead_width_value]};" if settings[:lead_width_value]
          lines
        end

        # appendix / preface のアクセント色（旧 update_appendix_css / update_preface_css 相当）。
        #   - appendix_color 未指定なら宣言しない（appendix.css の既定がカスケードで生きる）
        #   - preface は常に宣言（未指定時は theme accent へフォールバック）
        def supplemental_color_declarations(settings, cfg)
          theme_cfg = cfg.theme
          accent = settings[:theme_accent_value]
          lines = []

          appendix_color = theme_cfg.appendix_color
          unless appendix_color.to_s.strip.empty?
            value = CssUpdater.normalize_color_value(appendix_color, fallback: accent)
            lines << "--appendix-accent-color: #{value};"
          end

          preface_value = CssUpdater.normalize_color_value(theme_cfg.preface_color, fallback: accent)
          lines << "--color-preface-accent: #{preface_value};"
          lines
        end

        # 見出しマーカー（旧 update_chapter_common_css 相当）。未指定時は ♣ / ♦。
        def marker_declarations(cfg)
          markers = FrontmatterGenerator.safe_config_hash(cfg.theme.markers)
          h3 = (markers[:h3] || markers['h3']).to_s
          h4 = (markers[:h4] || markers['h4']).to_s
          h3 = '♣' if h3.strip.empty?
          h4 = '♦' if h4.strip.empty?
          [
            %(--h3-marker: "#{escape_marker(h3)}";),
            %(--h4-marker: "#{escape_marker(h4)}";)
          ]
        end

        # page-settings 系 22 変数（旧 update_page_settings_css 相当）。
        # nil/空値は宣言しない（page-settings.css の既定がカスケードで生きる）。
        def page_declarations(page_cfg)
          CssUpdater.build_css_variable_mappings(page_cfg).filter_map do |name, val, kind|
            next if val.nil? || val.to_s.strip.empty?

            "#{name}: #{CssUpdater.format_font_value(name, val.to_s.strip, kind)};"
          end
        end

        # @page { size } はリテラル必須（var() は @page size で使用不可）。
        # width/height が空なら @page 規則自体を出さない。
        def page_size_rule(page_cfg)
          w = page_cfg[:width].to_s.strip
          h = page_cfg[:height].to_s.strip
          return '' if w.empty? || h.empty?

          "@page { size: #{w} #{h}; }"
        end

        # 扉背景の background-position もリテラル必須——Vivliostyle は background-position の
        # calc() 内 var() を解さず宣言ごと落とし、背景が左上（0 0）へ偏る（pdf_chapter5 実測。
        # background-size の calc()+var() は解すので size 側は image-header.css のままでよい）。
        # 綴じオフセットを生成時に焼き込み、image-header.css の既定（center center）を上書きする。
        def frontispiece_position_rule(settings, page_cfg)
          return '' if settings[:theme_style] == 'simple'

          offset = page_cfg[:frontispiece_binding_offset].to_s.strip
          return '' if offset.empty? || offset == '0mm'

          "@page :nth(1) { background-position: calc(50% + #{offset}) center; }"
        end

        # ================================================================
        # 節（h2）の改ページ（page-break-control-spec.md §2.2）
        # ================================================================
        # 節でページを改める既存ルールの元セレクタ。打ち消しは「元セレクタをそのまま
        # 複製」する必要がある——book-settings.css は後段読込なので同特異度なら後勝ち
        # できるが、セレクタがずれると特異度負けして効かない。
        SECTION_PAGE_BREAK_SELECTORS = [
          'body.vs-header-image .section-topic h2',  # image-header.css（PDF / EPUB）
          'body.vs-header-simple h2',                # simple-header.css（PDF / EPUB）
          'body.vs-header-simple.vs-kindle h2',      # simple-header.css の Kindle 用（legacy 併記）
          'article.vs-section-topic-epub'            # components.css（EPUB の節絵 article）
        ].freeze

        # page.section_page_break: false のときだけ打ち消し規則を出す。
        # true・未設定では何も出さず、テーマ CSS の改ページがそのまま生きる
        # （P3 の「書かない条件では宣言しない」セマンティクス）。
        def section_page_break_rule(page_cfg)
          return '' unless section_page_break_disabled?(page_cfg)

          <<~CSS.chomp
            /* page.section_page_break: false — 節（h2）でページを改めない。
               Kindle KFX 向けの legacy page-break-before も併せて打ち消す。 */
            #{SECTION_PAGE_BREAK_SELECTORS.join(",\n")} {
              break-before: auto;
              page-break-before: auto;
            }
          CSS
        end

        # 明示的に false と書かれたときだけ「節で改ページしない」と解釈する。
        # 未設定・空欄は既定の true（現行挙動）を保つため、truthy? の裏返しではない。
        def section_page_break_disabled?(page_cfg)
          case page_cfg[:section_page_break]&.to_s&.strip&.downcase
          in 'false' | 'no' | 'off' | '0' then true
          else false
          end
        end

        # ================================================================
        # Kindle 用テーマ色リテラル（kindle-theme-color-literalize-spec.md）
        # ================================================================
        # KFX は var()/color-mix()/calc() を解さないため、テーマ色で塗った本文アクセント
        # （strong・下線・見出しマーカー・コラム/注記枠・付録見出し）が Kindle では黒/グレー/
        # くすんだ金へ劣化する。book-settings.css は最後に読まれるので、ここへテーマ色を
        # リテラル hex で焼いた body.vs-kindle 規則を出せば、静的な #888/#b8860b フォールバックを
        # 後勝ちで上書きできる。body.vs-kindle 前置のためクリーン EPUB では不発（無害）。
        def kindle_accent_rules(cfg)
          theme_cfg = cfg.theme
          acc = ThemeColor.to_hex6(theme_cfg.color)
          colbg = ThemeColor.mix_with_white(acc, 0.15)
          apx = appendix_accent_hex6(theme_cfg, acc)

          # 付録色がテーマ色と同一なら付録専用の上書きは不要（既定構成は両方 yellow）。
          lines = base_kindle_accent_rules(acc, colbg)
          lines += appendix_kindle_accent_rules(apx) unless apx == acc
          # 前書き/後書き（preface.css）の accent は preface_color 由来。preface 固有要素のため常に出す。
          lines += preface_kindle_accent_rules(preface_accent_hex6(theme_cfg, acc))

          <<~CSS.chomp
            /* Kindle 用テーマ色リテラル（KFX は var()/color-mix 非対応・最後に読まれ静的フォールバックを上書き） */
            #{lines.join("\n")}
          CSS
        end

        # 付録アクセントのリテラル hex。appendix_color 未指定時は appendix.css の静的既定
        # （--appendix-accent-color: var(--accent-yellow)）に合わせて yellow を返す——PDF/クリーン
        # EPUB の実カスケードと一致させるため（theme.color にはフォールバックしない）。
        def appendix_accent_hex6(theme_cfg, theme_hex)
          raw = theme_cfg.appendix_color
          return ThemeColor::DEFAULT if raw.to_s.strip.empty?

          ThemeColor.to_hex6(raw, fallback: theme_hex)
        end

        # 前書き/後書きアクセントのリテラル hex。preface_color 未指定時はテーマ色へフォールバック
        # （supplemental_color_declarations が --color-preface-accent を常に fallback: accent で宣言する
        # のと一致＝PDF/クリーン EPUB のカスケードと揃える。appendix の yellow 既定とは異なる）。
        def preface_accent_hex6(theme_cfg, theme_hex)
          raw = theme_cfg.preface_color
          return theme_hex if raw.to_s.strip.empty?

          ThemeColor.to_hex6(raw, fallback: theme_hex)
        end

        # 本文・見出しのアクセント規則（テーマ色 ACC / コラム地色 COLBG）。theme.style によらず共通。
        def base_kindle_accent_rules(acc, colbg)
          [
            "body.vs-kindle strong { color: #{acc}; }",
            "body.vs-kindle em { text-decoration-color: #{acc}; }",
            "body.vs-kindle .subsection-marker { color: #{acc}; }",
            "body.vs-kindle .column { border-color: #{acc}; background: #{colbg}; }",
            "body.vs-kindle .tip { border-color: #{acc}; }",
            "body.vs-kindle .memo { border-color: #{acc}; }",
            "body.vs-kindle .note { border-color: #{acc}; }",
            "body.vs-kindle .notice { border-color: #{acc}; }",
            adm_label_rule('body.vs-kindle', acc),
            "body.vs-header-simple.vs-kindle h1 { border-color: #{acc}; }",
            "body.vs-header-simple.vs-kindle h1 .chapter-number { color: #{acc}; }",
            "body.vs-header-simple.vs-kindle h2 { border-color: #{acc}; border-left-color: #{acc}; }",
            "body.vs-header-simple.vs-kindle h2 .section-number { background: #{acc}; }"
          ]
        end

        # 付録は appendix.css が --heading-accent / --color-mark を appendix-accent へ差し替えるため、
        # 見出し・h3 マーカー・ラベルを APX で上書きする（strong/枠は theme-accent のままで base が担う）。
        # .appendix が 1 つ多く特異度で勝つ。
        def appendix_kindle_accent_rules(apx)
          [
            "body.appendix.vs-header-simple.vs-kindle h1 { border-color: #{apx}; }",
            "body.appendix.vs-header-simple.vs-kindle h1 .chapter-number { color: #{apx}; }",
            "body.appendix.vs-header-simple.vs-kindle h2 { border-color: #{apx}; border-left-color: #{apx}; }",
            "body.appendix.vs-header-simple.vs-kindle h2 .section-number { background: #{apx}; }",
            "body.appendix.vs-kindle .subsection-marker { color: #{apx}; }",
            adm_label_rule('body.appendix.vs-kindle', apx)
          ]
        end

        # 実体ラベル【TIP】等（Kindle は ::before を content:none で抑止し vs-adm-label を注入・既定 #444）。
        # .terminal は白ラベル override が特異度で勝つため、.output は PDF にラベル無しのため、含めない。
        def adm_label_rule(prefix, color)
          %w[tip memo column notice note]
            .map { "#{prefix} .#{it} .vs-adm-label" }.join(', ') + " { color: #{color}; }"
        end

        # 前書き（body.preface）/ 後書き（body.postface。postface.css が preface.css を import）の
        # accent 規則。preface.css は h1 下線・h2/引用の左罫・リンク色を var(--color-preface-accent) で
        # 塗るが KFX で全滅する（h1 下線だけ静的 #4f46e5 フォールバックがあるがテーマ非追従）。
        # book-settings.css は全ページ共通のため body.preface / body.postface で必ずスコープする
        # （裸の h1/h2 規則を出すと本文章へ波及する）。論理プロパティは避け物理で書く。
        def preface_kindle_accent_rules(pref)
          scopes = %w[body.preface.vs-kindle body.postface.vs-kindle]
          [
            selector_group(scopes, 'h1') + " { border-bottom-color: #{pref}; }",
            selector_group(scopes, 'h2') + " { border-left: 3px solid #{pref}; }",
            selector_group(scopes, 'blockquote') + " { border-left: 3px solid #{pref}; }",
            selector_group(scopes, 'a') + " { color: #{pref}; border-bottom: 1px dotted #{pref}; }"
          ]
        end

        # 複数スコープ × 要素をカンマ区切りのセレクタ群にする（"a b, c b"）。
        def selector_group(scopes, element) = scopes.map { "#{it} #{element}" }.join(', ')

        # ================================================================
        # 会話文キャラクター色（characters-dialogue-spec.md §2.3-2 / §2.4-2）
        # ================================================================
        # talk.yml の各話者色を book-settings.css へ焼き込む。ソース CSS
        # （components.css）は色を var(--talk-c-<key>) 経由で参照するのみで、色自体は
        # 生成側が持つ（P3「生成 1 枚がカスケードで勝つ」方式）。色未指定・不在なら何も出さない。

        # :root に置く --talk-c-<key> の宣言行。色を明示した話者のみ（未指定はテーマ色を使う）。
        def talk_variable_declarations(registry)
          registry.with_color.map do |char|
            "--talk-c-#{char.key}: #{CssUpdater.normalize_color_value(char.color)};"
          end
        end

        # .talk-c-<key> の --talk-accent 差し替えと、Kindle 用リテラル色。
        # PDF/クリーン EPUB は var() 経由で色を当て、Kindle は KFX が var() を解さないため
        # 具体色（hex）で焼く（テーマ色名→hex は ThemeColor.to_hex6 で解決）。
        #
        # Kindle は会話文を inline 形式（名前＋区切り＋発話の 1 段落）へ組み替えるため
        # （talk-display-options-spec.md §2.5）、焼くのは話者名・区切り・発話内 strong の 3 つ。
        # 吹き出しの枠線は Kindle には存在しないのでリテラル化しない。
        # `strong` は base_kindle_accent_rules の `body.vs-kindle strong`（テーマ色・特異度 0,1,2）
        # に落ちてしまうため話者色で塗り直す。セレクタは (0,2,2) でその既定に勝つ。
        def talk_class_rules(registry)
          chars = registry.with_color
          return '' if chars.empty?

          lines = chars.flat_map do |char|
            hex = ThemeColor.to_hex6(char.color)
            [
              ".talk-c-#{char.key} { --talk-accent: var(--talk-c-#{char.key}); }",
              "body.vs-kindle .talk-c-#{char.key} .talk-name { color: #{hex}; }",
              "body.vs-kindle .talk-c-#{char.key} .talk-sep { color: #{hex}; }",
              "body.vs-kindle .talk-c-#{char.key} strong { color: #{hex}; }"
            ]
          end
          <<~CSS.chomp
            /* 会話文キャラクター色（KFX は var() 不可のため Kindle 用は hex リテラル） */
            #{lines.join("\n")}
          CSS
        end

        # ================================================================
        # 値計算（旧 update_page_settings_css の前処理を移設）
        # ================================================================

        # book.yml の page / typography から、CSS 変数マッピングに渡せる page_cfg を組み立てる。
        # 紙サイズ正規化・用紙スケール・行長・ノンブル配置・綴じオフセットを算出して詰める。
        def build_page_cfg(cfg)
          page_cfg = FrontmatterGenerator.safe_config_hash(cfg.page)
          typo_cfg = FrontmatterGenerator.safe_config_hash(cfg.typography)

          # typography からフォント設定を取り込む
          page_cfg[:main_text_font]   = typo_cfg&.dig(:body, :font)
          page_cfg[:header_font]      = typo_cfg&.dig(:heading, :font)
          page_cfg[:column_font]      = typo_cfg&.dig(:column, :font)
          page_cfg[:code_font]        = typo_cfg&.dig(:code, :font)
          page_cfg[:folio_font]       = typo_cfg&.dig(:folio, :font)
          page_cfg[:column_font_size] = Units.font_size_to_pt(typo_cfg&.dig(:column, :font_size))
          page_cfg[:folio_placement]  = typo_cfg&.dig(:folio, :placement)

          Common.normalize_page_size!(page_cfg)
          page_cfg[:paper_scale] = CssUpdater.calculate_paper_scale(page_cfg[:width], page_cfg[:height])
          page_cfg[:align_max_width] = CssUpdater.calculate_align_max_width(page_cfg[:width])
          CssUpdater.apply_folio_placement!(page_cfg)
          page_cfg[:frontispiece_binding_offset] = CssUpdater.calculate_frontispiece_binding_offset(
            page_cfg[:margin_inner], page_cfg[:margin_outer]
          )
          page_cfg
        end

        # ================================================================
        # URL 組替とエスケープ
        # ================================================================

        # テーマ画像の CSS 値を url("...") 形式で返す。
        # stylesheets/ 基準の相対パスを生成ファイル位置基準へ組み替える（調査報告 §7.3-1）。
        # 既に url(...) 形式ならその内側パスを、素のパスならそのものを対象にする。
        # data:/http(s):/絶対パスは組み替えない。
        def css_image_value(raw, image_prefix:)
          value = raw.to_s.strip
          return 'none' if value.empty? || value.casecmp?('none')

          inner = url_inner(value)
          %(url("#{rebase_relative(inner, image_prefix:)}"))
        end

        # url("...") / url('...') / url(...) の内側を取り出す。url() でなければそのまま返す。
        def url_inner(value)
          if (m = value.match(/\Aurl\(\s*["']?(.*?)["']?\s*\)\z/i))
            m[1]
          else
            value
          end
        end

        # stylesheets/ 基準の相対パスを image_prefix で組み替える。
        # 外部 URL・data URI・絶対パスは対象外。二重組替を避ける冪等ガード付き。
        # theme-images/… は生成バリアントのキャッシュ参照で、既に生成ファイル位置
        # （.cache/vs/）基準のため組み替えない（generated-assets 移設仕様 §3.1）。
        def rebase_relative(path, image_prefix:)
          p = path.to_s.strip
          return p if p.empty?
          return p if p.start_with?('data:', 'http://', 'https://', '/')
          return p if p.start_with?(image_prefix, 'theme-images/')

          "#{image_prefix}#{p}"
        end

        # CSS の "..." 文字列内で安全なマーカー文字にする（" と \ をエスケープ）。
        def escape_marker(mark)
          mark.gsub('\\', '\\\\\\\\').gsub('"', '\\"')
        end

        # ================================================================
        # 副作用（旧 update_all_css_files から引越し・調査報告 §7.3-3 / §7.3-4）
        # ================================================================

        # book.yml の typography が要求するフォントを準備する（CSS 書換とは独立に必要）。
        def ensure_fonts_available(cfg)
          typo_cfg = FrontmatterGenerator.safe_config_hash(cfg.typography)
          font_names = [
            typo_cfg&.dig(:body, :font),
            typo_cfg&.dig(:heading, :font),
            typo_cfg&.dig(:column, :font),
            typo_cfg&.dig(:code, :font),
            typo_cfg&.dig(:folio, :font)
          ]
          FontManager.ensure_fonts_available(font_names)
        end
      end
    end
  end
end
