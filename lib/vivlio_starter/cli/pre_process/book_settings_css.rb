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
require_relative '../build/vivliostyle_config_writer'
require_relative 'css_updater'
require_relative 'frontmatter_generator'

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

          root_lines = []
          root_lines.concat(theme_declarations(settings, image_prefix:))
          root_lines.concat(supplemental_color_declarations(settings, cfg))
          root_lines.concat(marker_declarations(cfg))
          root_lines.concat(page_declarations(page_cfg))

          <<~CSS
            #{header_comment}
            #{page_size_rule(page_cfg)}
            :root {
            #{root_lines.map { "  #{it}" }.join("\n")}
            }
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
