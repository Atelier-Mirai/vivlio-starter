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
#   ページの入口の CSS（Css::EntryWriter）が book-settings.css を settings 層で読む。
#   settings 層は vs の CSS の層（base・tokens・parts・pages・utilities）より上なので、
#   同名変数の再宣言が既存 CSS 値に勝つ（css-layer-restructure-spec.md §2.1）。
#   予備の書体の @font-face だけは book-fonts.css へ分けて書き、入口が層の外で読む
#   （@font-face を層に入れない。同 §2.2）。
#   Kindle にだけ当てる規則は書かない。Kindle の規則は stylesheets/targets/kindle*.css が変数で書き、
#   Kindle 用の平らな CSS を作るときに Css::LiteralResolver が値に解く（css-layer-restructure-spec.md §4.4）。
#   ここで変数を定義すれば、テーマ色も設定も Kindle に届く。
#
# 画像 URL の基準:
#   生成ファイルは `.cache/vs/` 直下に置かれるため、stylesheets/ 基準の相対
#   （例: images/x.webp）は `../../stylesheets/images/x.webp` へ、本のルートを指す
#   `../themes/standard/images/x.webp` は `../../themes/standard/images/x.webp` へ
#   組み替える。data:/http(s):/絶対パスは不変（調査報告 §7.3-1）。
# ================================================================

require 'fileutils'
require 'pathname'
require_relative '../common'
require_relative '../font_manager'
require_relative '../theme_color'
require_relative '../theme'
require_relative '../build/vivliostyle_config_writer'
require_relative '../css/legacy_tokens'
require_relative 'css_updater'
require_relative '../post_process/heading_processor'
require_relative 'frontmatter_generator'
require_relative 'talk_registry'
require_relative 'svg_font_embedder'
require_relative 'book_setting_warning'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # book-settings.css 生成モジュール
      module BookSettingsCss
        module_function

        # 生成ファイルのパス（.cache/vs/book-settings.css）。
        def output_path = File.join(Common::CACHE_DIR, 'book-settings.css')

        # 予備の書体の @font-face を書くファイル（.cache/vs/book-fonts.css）。入口が層の外で読む。
        def fonts_output_path = File.join(Common::CACHE_DIR, 'book-fonts.css')

        # `.cache/vs/` から `stylesheets/` への相対プレフィックス。
        # 生成ファイルは 2 階層深いため、stylesheets/ 基準の相対 URL をこの接頭辞で組み替える。
        CACHE_TO_STYLESHEETS = '../../stylesheets/'

        # book-settings.css を生成し、フォント準備と config.js 同期も行う。
        # プレフライト/フル/単章の全モードで 'prepare theme images' ステップから呼ばれる。
        # @param cfg [Object, nil] 設定オブジェクト（省略時は Common::CONFIG）
        # @return [String, nil] 生成したファイルパス（失敗時 nil）
        def generate!(cfg = nil)
          cfg ||= Common::CONFIG

          # --- Phase: book.yml が要求するフォントを準備する ---
          # CSS を組み立てる前に取得する。render は取得済みの太字の有無で強調の書体を決める
          # （font_synthesis_rules）ため、後に回すと Google Fonts の書体を初めて使うビルドで
          # 太字があるのに「無い」と判定され、強調だけがゴシックで組まれる。
          ensure_fonts_available(cfg)

          # --- Phase: CSS 全文を組み立てて書き出す ---
          css = render(cfg)
          path = output_path
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, css, encoding: 'utf-8')
          File.write(fonts_output_path, render_fonts, encoding: 'utf-8')
          suggest_new_token_names

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
          theme = Theme.declared(cfg)

          root_lines = []
          root_lines.concat(option_declarations(cfg, theme))
          root_lines.concat(feature_declarations(settings, cfg, image_prefix:, page_cfg:, theme:))
          root_lines.concat(page_declarations(page_cfg))
          root_lines.concat(talk_variable_declarations(registry))
          root_lines.concat(Css::LegacyTokens.settings_declarations(custom_css))

          <<~CSS
            #{header_comment}
            #{page_size_rule(page_cfg)}
            #{feature_page_rules(cfg, page_cfg, theme:)}
            :root {
            #{root_lines.map { "  #{it}" }.join("\n")}
            }
            #{section_pagebreak_rule(page_cfg, frontispiece: frontispiece_active?(cfg, theme))}
            #{chapter_pagebreak_rule(page_cfg)}
            #{heading_numbering_rule(page_cfg)}
            #{section_lead_width_rule(page_cfg)}
            #{font_synthesis_rules(cfg)}
            #{talk_class_rules(registry)}
          CSS
        end

        # ================================================================
        # 疑似太字（faux-bold）の抑止 — Type 3 フォント対策
        # ================================================================
        # Bold 字面を持たない書体に太字を要求すると、Chromium は字を太らせて
        # 合成し、それを **Type 3 フォント**として PDF へ埋め込む。Type 3 は
        # 技術書典等の入稿で不可（実測 2026-08-07: Noto Sans JP 指定の 1 章
        # ビルドで Type 3 が 195 件）。
        #
        # 対策は 2 段:
        #   1. `font-synthesis-weight: none` で合成そのものを止める。実 Bold が
        #      ある書体には影響しない——実体があるとき合成は起きないため。
        #   2. それだけだと本文の **強調** が標準の太さになって埋もれるので、
        #      本文書体に太字が無いときに限り `strong`/`b` を見出し書体（ゴシック）へ
        #      振る。明朝の強調にゴシックを当てるのは和文組版の作法でもある。
        #
        # 同梱書体は Regular/Bold 両字面を持つため 2 は発動せず、見た目は変わらない。
        # 詳細は `type3-font-embedding-notes.md`。
        def font_synthesis_rules(cfg)
          typo = FrontmatterGenerator.safe_config_hash(cfg&.typography) || {}
          rules = ['/* faux-bold を禁止して Type 3 フォントの混入を断つ */',
                   'body, body *, body *::before, body *::after { font-synthesis-weight: none; }']
          rules.concat(emphasis_fallback_rules) unless FontManager.bold_available?(typo.dig(:body, :font))
          rules.join("\n")
        end

        # book-fonts.css の全文（予備の書体の面）。book-settings.css と同じ .cache/vs/ に置くので、
        # 書体のファイルへの相対も同じ接頭辞で組み替える。
        def render_fonts = "#{header_comment}\n#{fallback_font_rules(image_prefix: CACHE_TO_STYLESHEETS)}\n"

        # 本の書体にも HackGen にも無い字（⟹・⌃・ₙ など）を、DejaVu で組む（改善案 #127 段階 2）。
        #
        # HackGen と同じ書体名の面を足し、unicode-range を HackGen に無い字に絞る。同じ名前の面が重なる
        # 字は後の面が優先されるので、HackGen を並びに含む本文・見出し・コラム・コード・ノンブルの
        # すべてで、HackGen の次に DejaVu が探される。雛形の base/page.css の並びを書き換えないので、
        # vs upgrade で CSS を上げなくても効く（書体のファイルは雛形と一緒に届く）。
        # 書体のファイルが無いプロジェクトでは何も出さない。EPUB は @font-face を取り除く（Css::TargetFilter）。
        def fallback_font_rules(image_prefix:)
          family = SvgFontEmbedder::DEFAULT_CODE_FONT
          { 400 => :regular, 700 => :bold }.flat_map do |weight, face|
            SvgFontEmbedder.html_fallback_faces(face).map do |name, path, codepoints|
              src = rebase_relative(path.delete_prefix("#{Common.stylesheets_dir}/"), image_prefix:)
              %(@font-face { /* #{name} */ font-family: "#{family}"; font-style: normal; font-weight: #{weight}; ) +
                %(unicode-range: #{unicode_ranges(codepoints)}; src: url("#{src}") format("truetype"); })
            end
          end.join("\n")
        rescue StandardError => e
          Common.log_debug("[book-settings] 予備の書体の面を出せませんでした: #{e.message}")
          ''
        end

        # コードポイントの並びを、続いた所をまとめた unicode-range の値にする（U+2190-21FF, U+2303）
        def unicode_ranges(codepoints)
          codepoints.sort.slice_when { |a, b| b != a + 1 }.map do |run|
            run.size == 1 ? format('U+%04X', run.first) : format('U+%04X-%04X', run.first, run.last)
          end.join(', ')
        end

        # 本文書体に太字が無いときの強調（ゴシック代用）。
        def emphasis_fallback_rules
          ['/* 本文書体に太字が無いため、強調は見出し書体（ゴシック）で表す */',
           'strong, b { font-family: var(--book-font-heading); }']
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
        # 選ばれたテーマの宣言から書く（theme-contract-spec.md §3.3・§3.4）。並びは options: のうち token: の
        # あるもの → 機能（features: の順）。テーマに固有の名前（オプションの名前・機能の変数）はここに書かない。
        #   - 強調の色（--book-color-strong・--book-color-em-underline）は書かない。tokens.css の既定が
        #     var(--book-color-accent) で、ここ（settings 層）で書き直すと、付録の色の割り当て
        #     （pages/appendix.css・改善案 #132）やテーマの指定を打ち消すため
        # @param theme [Theme::Resolved, nil]
        def option_declarations(cfg, theme = Theme.declared(cfg))
          return [] unless theme

          theme_cfg = cfg&.dig(:theme)
          theme.options.select(&:token).map do |option|
            "--book-#{option.token}: #{Theme::Values.css(option, Theme::Values.effective(option, theme_cfg, theme.all_options))};"
          end
        end

        # 組み込みの機能の変数。テーマが使う機能だけを書く（使わない機能の画像は tokens.css の既定 none）。
        # 使うが今の設定で無効な機能（standard の style: simple）は、機能の側が画像を none にする
        # @param settings [Hash] FrontmatterGenerator.parse_theme_settings の結果
        def feature_declarations(settings, cfg, image_prefix:, page_cfg: {}, theme: Theme.declared(cfg))
          return [] unless theme

          active = theme.active_features(cfg)
          theme.features.flat_map do |name|
            Theme::Features[name].declarations(settings, active: active.include?(name), image_prefix:, page_cfg:)
          end
        end

        # 組み込みの機能の @page の規則（扉絵の位置）
        def feature_page_rules(cfg, page_cfg, theme: Theme.declared(cfg))
          return '' unless theme

          active = theme.active_features(cfg)
          theme.features.map { Theme::Features[it].page_rule(page_cfg, active: active.include?(it)) }
               .reject(&:empty?).join("\n")
        end

        # 扉絵の機能が有効か（章扉の保護を書くかの判定。active_features はテーマの features: に絞った後の値）
        def frontispiece_active?(cfg, theme)
          return false unless theme

          theme.active_features(cfg).include?(Theme::Features::Frontispiece::NAME)
        end

        # ================================================================
        # 見出しの寸法（heading-metrics-spec §1-2）— 組み込みの機能が値を書くときの計算
        # ================================================================
        # 著者は book.yml に「1 行の文字数」で書く。判型に追従する CSS の
        # clamp() を calc() の中で掛け合わせると Vivliostyle が宣言ごと落とすため、
        # 換算は生成時に行いリテラルで焼き込む（@page size・綴じオフセットと同型）。
        #
        # 章題・章リードは「箱幅」を、節題は「フォントサイズ」を決める——節絵の帯は
        # 版面幅いっぱいで固定なので、箱を広げる余地が無く字送りで調整するしかない。
        # 変数へ書くのは Theme::Features::Frontispiece・Ornament。

        # tokens.css が持つ既定の文字数（未指定時の値と一致させる）。
        # Transforms::Shared::InjectHeadingImages も同じ既定でリード幅比を導くため公開している（§5-1）。
        DEFAULT_HEADING_CHARS = 8
        DEFAULT_LEAD_CHARS = 20
        DEFAULT_ORNAMENT_HEADING_CHARS = 14

        # 章リードの倍率の既定（stylesheets/tokens.css の --book-chapter-lead-size と、同梱の standard の
        # theme.lead_size の default: と同じ。book_settings_css_test.rb が突き合わせる）。
        # 扉絵のリードの既定の幅（tokens.css の --book-frontispiece-lead-width）は、この倍率で決めてある
        DEFAULT_LEAD_SIZE = 1.2

        # 章題 1 字の送り（mm）。image-header.css の .chapter-title の
        # `font-size: clamp(34Q, calc(var(--book-paper-scale) * 48Q), 50Q)` と
        # `letter-spacing: 0.08em` を再現する。CSS 側を変えたらここも直すこと
        # （回帰テストで両者の一致を固定してある）。
        def chapter_title_advance_mm(scale)
          chapter_title_font_q(scale) * 0.25 * 1.08
        end

        # 章題の字の大きさ（Q）。Transforms::Shared::InjectHeadingImages も、PDF の章題と節題の比を取るのに使う。
        def chapter_title_font_q(scale) = (scale * 48).clamp(34, 50)

        # 章リード 1 字の送り（mm）。リードは本文の基準の大きさ（page プリセットの
        # base_font_size）の lead_size 倍で、本文と同じ字間（letter_spacing）が付く。
        # 字間を広げても lead_chars の字数が 1 行に入るよう、送りに字間を含める。
        def chapter_lead_advance_mm(page_cfg, lead_size = DEFAULT_LEAD_SIZE)
          base_mm = Units.length_to_mm(page_cfg[:base_font_size]) || (10.5 * 25.4 / 72.0)
          font_mm = base_mm * lead_size
          font_mm + letter_spacing_mm(page_cfg, font_mm)
        end

        # 本文の字間（page プリセットの letter_spacing）を、大きさ font_mm の字に付けたときの mm。
        # em は字の大きさに対する比（CSS の var() の em は、使う要素の字の大きさで解ける）。
        # mm・pt などはそのままの長さ。読めない値は 0（CSS 側でも効かない）。
        def letter_spacing_mm(page_cfg, font_mm)
          value = page_cfg[:letter_spacing].to_s.strip
          return value.to_f * font_mm if value.match?(/\A-?[\d.]+\s*em\z/i)

          Units.length_to_mm(value) || 0.0
        end

        # 字間が付いているか（既定の幅のままでは字数が合わなくなるか）
        def letter_spaced?(page_cfg) = !letter_spacing_mm(page_cfg, 1.0).zero?

        # 節リードの幅（parts/heading.css の .section-lead の inline-size: 32em）。字数で決めた幅ではなく、
        # 版面より一回り狭く見せるための見た目の幅で、字間 0 なら 1 行 32 字になる
        SECTION_LEAD_CHARS = 32

        # 節リードの幅は max(32em, 32 字と字間のぶん)。字間を広げたときだけ書き出し、
        # 32 字が入らなくならないよう幅を広げる（版面より広くはしない: parts/heading.css の
        # max-inline-size）。字間を詰めたときは 32em のまま、詰めたぶん多くの字を入れる——
        # 32 字に合わせて縮めると、本文が版面いっぱいに組まれる横で節リードだけが細くなる。
        #
        # 字間 0 以下では何も出さず、parts/heading.css の 32em に任せる。CSS 側で
        # calc(32em + 32 * var(--book-letter-spacing)) と書くと、字間 0 でも節リードの字の位置が
        # わずかにずれた（vivliostyle-css-pitfalls-notes.md §2.18）。
        # EPUB・Kindle は targets/epub.css の inline-size: auto が勝つ（target 層・特異度 0,2,1）。
        def section_lead_width_rule(page_cfg)
          return '' unless letter_spacing_mm(page_cfg, 1.0).positive?

          value = page_cfg[:letter_spacing].to_s.strip
          width = if value.match?(/\A-?[\d.]+\s*em\z/i)
                    "#{format_number(SECTION_LEAD_CHARS * (1 + value.to_f))}em"
                  else
                    "calc(#{SECTION_LEAD_CHARS}em + #{format_mm(SECTION_LEAD_CHARS * Units.length_to_mm(value))})"
                  end
          "/* 節リードの幅（32 字と字間。page プリセットの letter_spacing） */\nbody .section-lead { inline-size: #{width}; }"
        end

        # 節題の基準フォントサイズ（Q）。節絵の帯は版面幅から左右の飾り避け（padding-inline）を
        # 引いた幅が使える。字数を増やすほど小さく、減らすほど大きくなる。
        # 極端な指定で本文と階層が崩れないよう 20〜48Q に収める。
        SECTION_TITLE_FONT_Q_RANGE = (20.0..48.0)

        # 節絵の飾り避け（image-header.css の padding-inline）。左右それぞれ
        # `clamp(下限, --book-paper-scale × 基準, 基準)` で用紙比に応じて縮む。
        SECTION_TITLE_PADDING_LEFT_MM = { min: 11.0, base: 16.0 }.freeze
        SECTION_TITLE_PADDING_RIGHT_MM = { min: 12.0, base: 18.0 }.freeze

        # 行あふれの余裕。節番号（`6-3`）の幅・英数字の字幅の揺れ・禁則処理で
        # わずかにはみ出しても、指定した字数で折り返せるようにする。
        SECTION_TITLE_HEADROOM = 0.96

        # 飾り避けの合計（mm）。CSS と同じ式で求める。
        #
        # かつては 34.0mm の固定値だった——`padding-inline` の基準値 16 + 18 で、
        # これは **A4（--book-paper-scale が 1.0）のときの値**。CSS 側は用紙比で縮むため、
        # B5 では実際 29.4mm しか使われず、Ruby が 4.6mm 広く見積もることで
        # 字送りが小さくなり、1 行に 14.6 字入る余裕が**偶然**生まれていた。
        # A4 では見積もりが一致して余裕ゼロになり、25 字の節題が 2 行に収まらず
        # 3 行へ落ちた（実測 2026-08-10）。「判型が大きいほど溢れやすい」という
        # 直感に反する挙動の正体がこれ。
        def section_title_ornament_padding_mm(scale)
          [SECTION_TITLE_PADDING_LEFT_MM, SECTION_TITLE_PADDING_RIGHT_MM].sum do
            (scale * it[:base]).clamp(it[:min], it[:base])
          end
        end

        def section_title_font_q(chars, text_mm, scale)
          avail = text_mm - section_title_ornament_padding_mm(scale)
          return 36 unless avail.positive?

          q = (avail * SECTION_TITLE_HEADROOM / chars) / 0.25
          format_number(q.clamp(SECTION_TITLE_FONT_Q_RANGE.begin, SECTION_TITLE_FONT_Q_RANGE.end))
        end

        # 版面幅（mm）= 紙幅 − ノド − 小口。導けないときは A4 標準相当へ。
        def text_area_width_mm(page_cfg)
          width = Units.length_to_mm(page_cfg[:width])
          inner = Units.length_to_mm(page_cfg[:margin_inner])
          outer = Units.length_to_mm(page_cfg[:margin_outer])
          return 162.0 unless width&.positive? && inner && outer

          [width - inner - outer, 1.0].max
        end

        # build_page_cfg が算出済みの値を使う（同じ計算を 2 度しない）
        def paper_scale_of(page_cfg)
          (page_cfg[:paper_scale] || 1.0).to_f
        end

        # 版面に収まらない文字数指定は 🟡 で具体的な上限を示す（warning-messages の方針）。
        def warn_if_wider_than_text_area(label, chars, advance_mm, text_mm)
          return if advance_mm <= 0 || chars * advance_mm <= text_mm

          fits = (text_mm / advance_mm).floor
          BookSettingWarning.report(
            "#{label}: #{chars} は版面幅 #{format_mm(text_mm)} に収まりません（最大 #{fits} 文字）",
            detail: "#{label.split('.').last}: #{fits} をお試しください"
          )
        end

        def format_mm(value) = "#{format_number(value)}mm"

        # 倍率を百分率で書く（1.2 → 120%）。字の大きさの倍率を em で書くと、Vivliostyle が px に直すときに
        # 丸め、両端揃えの字の位置がずれる（% と larger はずれない。vivliostyle-css-pitfalls-notes.md §2.18）
        def format_percent(ratio) = "#{format_number(ratio * 100)}%"

        # 末尾の 0 を落とす（103.68 → 103.68 / 36.0 → 36）
        def format_number(value)
          rounded = value.round(2)
          rounded == rounded.to_i ? rounded.to_i.to_s : rounded.to_s
        end

        # page-settings 系 22 変数（旧 update_page_settings_css 相当）。
        # nil/空値は宣言しない（base/page.css の既定がカスケードで生きる）。
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

        # ================================================================
        # 節（h2）の改ページ（page-break-control-spec.md §2.2）
        # ================================================================
        # テーマの節見出しの改ページは、公開する変数 --book-section-break-before・
        # --book-section-page-break-before で書かれている（theme-contract-spec.md §3.5）。ここでは変数の値だけを
        # 書き、テーマの選択子を知らない（テーマを替えても、設定がそのまま効く）。
        #
        # vs 自身の部品の改ページだけは、規則で打ち消す。vs が自分の選択子を知っているのは契約の内側で、
        # 打ち消しは「元の選択子をそのまま写す」必要がある——平らな CSS（EPUB・Kindle）では詳細度で
        # 勝ち負けが決まり、settings 層は後に読まれるので同じ詳細度なら勝てるが、ずれると負ける。
        SECTION_PAGEBREAK_SELECTORS = [
          'article.vs-section-topic-epub' # parts/epub-reflow.css（EPUB の節絵 article）
        ].freeze

        # page.section_pagebreak: false のときだけ書く。
        # true・未設定では何も書かず、tokens.css の既定（page・always）がそのまま生きる
        # （P3 の「書かない条件では宣言しない」セマンティクス）。
        # 打ち消しだけでは章扉に最初の節が流れ込むため、扉絵の機能が有効なら章扉の保護を続けて書く
        # （Theme::Features::Frontispiece.guard_rule。扉絵を使うテーマ全部に要る機能の骨格）。
        #
        # かつては「節絵の箱が固定 150px 行からはみ出して直前の本文に重なる」是正も
        # ここで出していたが、heading-metrics-spec §3・§4 で image-header.css 側の
        # 行を実寸（auto）にしたため不要になった（はみ出し自体が消えた）。
        # @param frontispiece [Boolean] 扉絵の機能が有効か
        def section_pagebreak_rule(page_cfg, frontispiece: false)
          return '' unless section_pagebreak_disabled?(page_cfg)

          <<~CSS.chomp
            /* page.section_pagebreak: false — 節（h2）でページを改めない。
               Kindle KFX 向けの legacy page-break-before も併せて打ち消す。 */
            :root {
              --book-section-break-before: auto;
              --book-section-page-break-before: auto;
            }
            #{SECTION_PAGEBREAK_SELECTORS.join(",\n")} {
              break-before: auto;
              page-break-before: auto;
            }
            #{Theme::Features::Frontispiece.guard_rule(active: frontispiece)}
          CSS
        end

        # 明示的に false と書かれたときだけ「節で改ページしない」と解釈する。
        # 未設定・空欄は既定の true（現行挙動）を保つため、truthy? の裏返しではない。
        def section_pagebreak_disabled?(page_cfg)
          case page_cfg[:section_pagebreak]&.to_s&.strip&.downcase
          in 'false' | 'no' | 'off' | '0' then true
          else false
          end
        end

        # ================================================================
        # 章の改丁（chapter-pagebreak-spec.md §2.2）
        # ================================================================
        # 章・目次・部扉・付録・用語集・後書き・索引を右ページ始まりにする vs 自身のルールの
        # 元セレクタ。6 ファイルに散っているが、chapter-common / glossary / index /
        # postface の 4 つはいずれも素の body なので、相異なるセレクタは 4 つで足りる。
        # 打ち消しは「元セレクタをそのまま複製」する必要がある——book-settings.css は
        # 後段読込なので同特異度なら後勝ちできるが、ずれると特異度負けして効かない。
        # テーマの章見出しの改丁は、公開する変数 --book-chapter-break-before で書かれているので、
        # 変数の値を書くだけでよい（theme-contract-spec.md §3.5）。
        CHAPTER_PAGEBREAK_SELECTORS = [
          'body',           # parts/heading.css / pages/glossary.css / pages/index.css / pages/postface.css
          'body.toc',       # toc.css
          'body.whole_toc', # toc.css（分冊の全巻目次）
          '.part-title'     # part-title.css
        ].freeze

        # 素の body の改丁から外すページ（スパインの末尾に相乗りし、改ページが要らない）
        CHAPTER_PAGEBREAK_EXEMPT_SELECTORS = %w[body.titlepage body.legalpage body.colophon].freeze

        # page.chapter_pagebreak が取りうる値。@pagebreak 記法（裸 / :recto / :verso）と
        # ちょうど 1 対 1 に対応させてある（裸の @pagebreak ＝ any）。
        CHAPTER_PAGEBREAK_VALUES = %w[recto verso any].freeze
        DEFAULT_CHAPTER_PAGEBREAK = 'recto'

        # 既定（recto）では何も出さず、テーマ CSS の break-before: recto をそのまま生かす
        # （P3 の「書かない条件では宣言しない」セマンティクス）。
        #
        # any の置換先を auto ではなく page にするのは、.part-title と
        # テーマの章見出し（standard の body.vs-header-simple h1）が**文書内の要素**であり、auto にすると直前の内容へ
        # 流れ込んでしまうため。body への page は分割フローの先頭なので実害が無い。
        # verso には legacy page-break-before の対応値が無いので併記しない
        # （KFX はいずれにせよ recto/verso を解さない）。
        def chapter_pagebreak_rule(page_cfg)
          warn_unknown_chapter_pagebreak!(page_cfg)

          case chapter_pagebreak_value(page_cfg)
          when 'any'
            chapter_pagebreak_css('page', legacy: 'always',
                                          note: 'どちら側の面からでも始める（白紙を挿入しない）')
          when 'verso'
            chapter_pagebreak_css('verso', note: '左ページ（偶数）始まりにする')
          else
            ''
          end
        end

        def chapter_pagebreak_css(value, legacy: nil, note: '')
          declarations = ["break-before: #{value};"]
          declarations << "page-break-before: #{legacy};" if legacy

          <<~CSS.chomp
            /* page.chapter_pagebreak — 章・目次・部扉・付録・用語集・後書き・索引を#{note}。
               原稿中の @pagebreak:recto / :verso（.vs-break-*）はここでは触らないため、
               局所の明示指定が本設定より優先される。 */
            :root {
              --book-chapter-break-before: #{value};
            }
            #{CHAPTER_PAGEBREAK_SELECTORS.join(",\n")} {
              #{declarations.join("\n  ")}
            }
            /* 本扉・権利ページ・奥付は本文のスパインの末尾に相乗りするページで、白紙を挟むと結合時の
               切り出し位置がずれる（front-back-matter-single-render-spec.md §3.3）。上の素の body の規則から外す。
               打ち消しをページの CSS（pages 層）に置くと settings 層のこの規則に負けるので、同じ層の後に置く。 */
            #{CHAPTER_PAGEBREAK_EXEMPT_SELECTORS.join(",\n")} {
              break-before: auto;
              page-break-before: auto;
            }
          CSS
        end

        # 設定値の正規化。不正値・未設定は既定（recto）へ倒す。**警告は出さない**
        # ——PdfMerger も同じ判定を借りるため、ここで鳴らすと 1 ビルドで二度警告が出る。
        def chapter_pagebreak_value(page_cfg)
          raw = page_cfg[:chapter_pagebreak].to_s.strip.downcase
          CHAPTER_PAGEBREAK_VALUES.include?(raw) ? raw : DEFAULT_CHAPTER_PAGEBREAK
        end

        # 綴り間違いが黙って既定へ戻ると著者は気づけないので知らせる。鳴らすのは CSS
        # 生成の 1 回だけ（generate! はビルド Step 2 で必ず通る唯一の接続先）。
        def warn_unknown_chapter_pagebreak!(page_cfg)
          raw = page_cfg[:chapter_pagebreak].to_s.strip
          return if raw.empty? || CHAPTER_PAGEBREAK_VALUES.include?(raw.downcase)

          BookSettingWarning.report(
            "config/book.yml の page.chapter_pagebreak の値が不正です（#{raw}）\n" \
            "   使える値: #{CHAPTER_PAGEBREAK_VALUES.join(' / ')}\n" \
            "   before: chapter_pagebreak: #{raw}\n" \
            "   after : chapter_pagebreak: #{DEFAULT_CHAPTER_PAGEBREAK}\n" \
            "   今回は既定の #{DEFAULT_CHAPTER_PAGEBREAK} で処理しました。"
          )
        end

        # ================================================================
        # 見出しの番号（heading-numbering-spec.md R3）
        # ================================================================
        # 目次の番号は HTML ではなく toc.css の CSS カウンタで振っている。toc.css は著者の本へ
        # 写す雛形なので、そこで切ると vs upgrade するまで効かない。番号を切る規則はビルドのたびに
        # 作るこのファイルに出す。セレクタに #toc を前置するのは、toc.css の付録の節の規則
        # （li.toc-chapter-appendix > ul .toc-section::before）にも特異度で勝つため。
        # 項（###）の番号「3-2-1」は節の番号を含むので、節と一緒に切る。
        TOC_SECTION_NUMBER_SELECTORS = ['#toc .toc-section::before', '#toc .toc-subsection::before'].freeze
        TOC_CHAPTER_NUMBER_SELECTORS = ['#toc .toc-chapter::before', '#toc .toc-chapter-appendix::before'].freeze

        # 既定（chapter_and_section）では何も出さず、toc.css の番号をそのまま生かす
        def heading_numbering_rule(page_cfg)
          warn_unknown_heading_numbering!(page_cfg)

          selectors, spacing = case PostProcessCommands::HeadingProcessor.normalize_heading_numbering(page_cfg[:heading_numbering])
                               when 'chapter' then [TOC_SECTION_NUMBER_SELECTORS, nil]
                               when 'none' then [TOC_CHAPTER_NUMBER_SELECTORS + TOC_SECTION_NUMBER_SELECTORS,
                                                 TOC_CHAPTER_SPACING_RULE]
                               else return ''
                               end

          rule = <<~CSS.chomp
            /* page.heading_numbering — 目次の番号を出さない（章扉・節の見出しには番号の要素を作らない） */
            #{selectors.join(",\n")} {
              content: none;
            }
          CSS
          [rule, spacing].compact.join("\n")
        end

        # 章の番号の行（「第 N 章」の ::before）は上に余白を持ち、前の項目との区切りになっていた。
        # 行を消すと余白も消え、前書きの最後の項目と最初の章が詰まる（spiral-ruby で実測）。
        # 番号の無い章（toc.css の li.toc-chapter-no-number）と同じ前の余白を置く。章と章の間は
        # 下の余白（6mm）と重なって大きい方になるので変わらない
        TOC_CHAPTER_SPACING_RULE = <<~CSS.chomp
          #toc > ul > li.toc-chapter {
            margin-block-start: clamp(3.5mm, calc(var(--book-paper-scale) * 5mm), 5mm);
          }
        CSS

        # 綴り間違いが黙って既定へ戻ると著者は気づけないので知らせる。鳴らすのは CSS 生成の 1 回だけ
        # （HeadingProcessor.heading_numbering は章ごとに呼ばれるので、そちらでは鳴らさない）
        def warn_unknown_heading_numbering!(page_cfg)
          raw = page_cfg[:heading_numbering].to_s.strip
          values = PostProcessCommands::HeadingProcessor::HEADING_NUMBERING_VALUES
          return if raw.empty? || values.include?(raw.downcase)

          default = PostProcessCommands::HeadingProcessor::DEFAULT_HEADING_NUMBERING
          BookSettingWarning.report(
            "config/book.yml の page.heading_numbering の値が不正です（#{raw}）\n" \
            "   使える値: #{values.join(' / ')}\n" \
            "   before: heading_numbering: #{raw}\n" \
            "   after : heading_numbering: #{default}\n" \
            "   今回は既定の #{default} で処理しました。"
          )
        end

        # ================================================================
        # 1.x の変数の名前（css-layer-restructure-spec.md §7.2）
        # ================================================================
        # custom.css が 1.x の名前に値を入れていれば（:root { --color-link: #1a73e8; }）、
        # Css::LegacyTokens.settings_declarations が新しい名前へ渡す宣言を作り、:root の最後に書く
        # （同じ :root の先の行が書いたテーマ色などに勝つため）。

        # custom.css の全文。無ければ空
        def custom_css
          path = File.join(Common::STYLESHEETS_DIR, 'custom.css')
          File.exist?(path) ? File.read(path, encoding: 'utf-8') : ''
        end

        # custom.css が 1.x の名前を使っていれば、vs upgrade で置き換えられることを 💡 で示す。
        # 今の名前のままでも効くので 🟡 にしない。原稿の場所を指す指摘でもない（terminal-output-notes.md）
        def suggest_new_token_names
          names = Css::LegacyTokens.legacy_names_in(custom_css)
          return if names.empty?

          pairs = names.first(2).map { "#{it} → #{Css::LegacyTokens::MAP.fetch(it)}" }.join('、')
          rest = names.size > 2 ? " ほか #{names.size - 2} 個" : ''
          Common.log_always("💡 custom.css の 1.x の変数の名前は、vs upgrade で新しい名前に置き換えられます（#{pairs}#{rest}）")
        end

        # ================================================================
        # 会話文キャラクター色（characters-dialogue-spec.md §2.3-2 / §2.4-2）
        # ================================================================
        # talk.yml の各話者色を book-settings.css へ焼き込む。ソース CSS
        # （parts/talk.css）は色を var(--talk-c-<key>) 経由で参照するのみで、色自体は
        # 生成側が持つ（P3「生成 1 枚がカスケードで勝つ」方式）。色未指定・不在なら何も出さない。

        # :root に置く --talk-c-<key> の宣言行。色を明示した話者のみ（未指定はテーマ色を使う）。
        # display.avatar_size があれば、アバターの直径 --book-talk-icon-size と、名前を積む列の幅
        # --book-talk-speaker-size（直径＋TALK_SPEAKER_EXTRA_MM）も置く（talk-avatar-initial-spec.md §7.3）。
        # 列の幅を CSS の calc(var() + 2mm) にしないのは、Vivliostyle が calc と var の組み合わせを
        # 宣言ごと捨てることがあるため。無ければ出さず、parts/talk.css の var() の既定に任せる。
        def talk_variable_declarations(registry)
          colors = registry.with_color.map do |char|
            "--talk-c-#{char.key}: #{CssUpdater.normalize_color_value(char.color)};"
          end
          size = registry.display.avatar_size
          return colors unless size

          colors + talk_size_declarations(size)
        end

        # アバターの直径と、名前を積む列の幅（直径＋TALK_SPEAKER_EXTRA_MM）の宣言 2 行。
        def talk_size_declarations(size)
          ["--book-talk-icon-size: #{format_mm(size)};",
           "--book-talk-speaker-size: #{format_mm(size + TALK_SPEAKER_EXTRA_MM)};"]
        end

        # 名前を積む列をアバターより広くする幅。parts/talk.css の既定（12mm と 14mm）の差と同じ。
        TALK_SPEAKER_EXTRA_MM = 2

        # .talk-c-<key> の --book-talk-accent 差し替え。PDF/クリーン EPUB は var() 経由で色を当てる。
        #
        # 名前・区切り・発話の中の strong には、話者の色を :root の --talk-c-<key> で直接当てる。
        # --book-talk-accent は話者の要素の上で定義する変数なので、Kindle 用の CSS では値に解けない
        # （Css::LiteralResolver。要素ごとに値が違う変数は解かない）。:root の変数なら解ける。
        # PDF とクリーン EPUB では parts/talk.css の var(--book-talk-accent) と同じ色になる。
        # strong は targets/kindle.css などの `body.vs-kindle strong`（0,1,2）に勝つよう (0,2,1) にする。
        #
        # 話者の avatar_size は、同じ .talk-c-<key> に --book-talk-icon-size と --book-talk-speaker-size を
        # 置いて :root（display.avatar_size）の値を覆う（talk-avatar-initial-spec.md §7.3）。
        # Kindle はアバターを出さないので、大きさは解けなくてよい。
        def talk_class_rules(registry)
          color_lines = registry.with_color.flat_map do |char|
            key = char.key
            [".talk-c-#{key} { --book-talk-accent: var(--talk-c-#{key}); }",
             ".talk-c-#{key} .talk-name, .talk-c-#{key} .talk-sep, .talk-item.talk-c-#{key} strong " \
             "{ color: var(--talk-c-#{key}); }"]
          end
          size_lines = registry.with_avatar_size.map do |char|
            ".talk-c-#{char.key} { #{talk_size_declarations(char.avatar_size).join(' ')} }"
          end
          [
            ("/* 会話文キャラクター色 */\n#{color_lines.join("\n")}" if color_lines.any?),
            ("/* 会話文キャラクターのアバターの直径 */\n#{size_lines.join("\n")}" if size_lines.any?)
          ].compact.join("\n")
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
        # ../ で stylesheets/ の外（テーマの images/ など）を指すものは、つないだ後の ../ を畳む
        def rebase_relative(path, image_prefix:)
          p = path.to_s.strip
          return p if p.empty?
          return p if p.start_with?('data:', 'http://', 'https://', '/')
          return p if p.start_with?(image_prefix, "#{File.dirname(image_prefix)}/", 'theme-images/')
          return Pathname("#{image_prefix}#{p}").cleanpath.to_s if p.start_with?('../')

          "#{image_prefix}#{p}"
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
