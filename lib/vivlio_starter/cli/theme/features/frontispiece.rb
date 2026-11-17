# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/theme/features/frontispiece.rb
# ================================================================
# 責務:
#   組み込みの機能 frontispiece（章扉の扉絵）の宣言と、book-settings.css へ書く値
#   （theme-contract-spec.md §3.4）。
#
# 機能の中身（今のコード）:
#   prepare theme images（ImageOptimizer・ThemeImageResolver）・EPUB と Kindle の見出しの画像
#   （Transforms::Shared::InjectHeadingImages）・check chapter leads（Build::ChapterLeadCheck）。
#   扉絵の @page :nth(1) の規則は vs の stylesheets/pages/chapter.css に置く（機能の骨格）。
#   テーマは --book-frontispiece-* の値で変える。
# ================================================================

require_relative '../option'

module VivlioStarter
  module CLI
    module Theme
      module Features
        # 章扉の扉絵
        module Frontispiece
          NAME = 'frontispiece'

          # 扉絵が効くページの種類。扉絵の @page :nth(1) は章だけが読む stylesheets/pages/chapter.css に
          # あるので、効く場所は vs の CSS の置き場で決まる（テーマは変えられない。theme-contract-spec.md §3.4）
          PAGE_KINDS = %i[chapter].freeze

          # オプションの宣言（theme.frontispiece.*）。値の検査は値を読むコード
          # （FrontmatterGenerator・ThemeValidator）が行う
          OPTIONS = [
            Option.new(path: %i[frontispiece image], type: 'image', default: 'sakura'),
            Option.new(path: %i[frontispiece edge_inset], type: 'length', default: '5mm'),
            Option.new(path: %i[frontispiece heading_offset], type: 'length', default: '15mm'),
            Option.new(path: %i[frontispiece heading_chars], type: 'number', default: 10),
            Option.new(path: %i[frontispiece lead_chars], type: 'number', default: 24),
            # 章扉だけのリードの大きさ。書かなければ theme.lead_size に従う（chapter-lead-size-spec.md §2.2）
            Option.new(path: %i[frontispiece lead_size], type: 'ratio', default_from: 'lead_size', min: 1.0, max: 2.0)
          ].freeze

          module_function

          # book-settings.css の :root に書く宣言。機能が無効（standard の style: simple）なら画像を none にし、
          # 扉絵の余白は書かない（tokens.css の既定が生きる）。見出しの寸法は文字数指定がある時だけ書く。
          # @param settings [Hash] FrontmatterGenerator.parse_theme_settings の結果
          # @param active [Boolean] 機能が有効か
          def declarations(settings, active:, image_prefix:, page_cfg: {})
            bsc = PreProcessCommands::BookSettingsCss
            lines = []
            if active
              lines << "--book-frontispiece-image: #{bsc.css_image_value(settings[:frontispiece_path], image_prefix:)};"
              lines << "--book-frontispiece-edge-inset: #{settings[:edge_inset_value]};"
            else
              lines << '--book-frontispiece-image: none;'
            end
            if settings[:heading_offset_value]
              lines << "--book-frontispiece-heading-offset: #{settings[:heading_offset_value]};"
            end
            lines.concat(metric_declarations(settings, page_cfg))
          end

          # 章題・章リードの幅と、章扉の章リードの大きさ（heading-metrics-spec §1-2）。
          # 著者は book.yml に「1 行の文字数」で書く。判型に追従する CSS の clamp() を calc() の中で
          # 掛け合わせると Vivliostyle が宣言ごと落とすため、換算は生成時に行いリテラルで焼き込む。
          def metric_declarations(settings, page_cfg)
            bsc = PreProcessCommands::BookSettingsCss
            text_mm = bsc.text_area_width_mm(page_cfg)
            scale = bsc.paper_scale_of(page_cfg)
            lines = []

            if (chars = settings[:heading_chars_value])
              advance = bsc.chapter_title_advance_mm(scale)
              lines << "--book-frontispiece-heading-width: #{bsc.format_mm(chars * advance)};"
              bsc.warn_if_wider_than_text_area('theme.frontispiece.heading_chars', chars, advance, text_mm)
            end

            # 章扉のリードの幅は「字数 × 1 字の送り」で、送りは章扉の倍率と字間で決まる。字数が
            # 未指定でも倍率や字間を変えたなら、tokens.css の既定幅（既定の字数 × 1.2 倍）のままでは
            # 字数が合わなくなるので、既定の字数で幅を出し直す。
            lead_size = settings[:frontispiece_lead_size_value] || bsc::DEFAULT_LEAD_SIZE
            lines << "--book-frontispiece-lead-size: #{bsc.format_percent(lead_size)};"
            default_width = lead_size == bsc::DEFAULT_LEAD_SIZE && !bsc.letter_spaced?(page_cfg)
            chars = settings[:lead_chars_value] || (bsc::DEFAULT_LEAD_CHARS unless default_width)
            if chars
              advance_mm = bsc.chapter_lead_advance_mm(page_cfg, lead_size)
              lines << "--book-frontispiece-lead-width: #{bsc.format_mm(chars * advance_mm)};"
              bsc.warn_if_wider_than_text_area('theme.frontispiece.lead_chars', chars, advance_mm, text_mm)
            end

            lines
          end

          # 扉絵の background-position（book-settings.css の @page の規則）。リテラル必須——Vivliostyle は
          # background-position の calc() 内 var() を解さず宣言ごと落とし、背景が左上（0 0）へ偏る
          # （pdf_chapter5 実測）。綴じオフセットを生成時に焼き込み、既定（center center）を上書きする。
          def page_rule(page_cfg, active:)
            return '' unless active

            offset = page_cfg[:frontispiece_binding_offset].to_s.strip
            return '' if offset.empty? || offset == '0mm'

            "@page :nth(1) { background-position: calc(50% + #{offset}) center; }"
          end

          # このページは扉絵の章扉か。機能が有効で、body に扉絵の効くページの種類のクラスがあるとき。
          # テーマのクラス（standard の vs-header-image）は読まない——standard では同じページを選ぶが、
          # テーマごとに違う印を vs のコードが知ることになる（theme-contract-spec.md §3.4）
          # @param body_classes [Array<String>] 組んだ HTML の body のクラス
          # @param active [Boolean] 機能が有効か（BuildPlan.features.frontispiece）
          def page?(body_classes, active:)
            active && PAGE_KINDS.any? { body_classes.include?(it.to_s) }
          end

          # 章扉の保護。page.section_pagebreak: false でも、章の最初の節だけは次のページから始める
          # （BookSettingsCss#section_pagebreak_rule が続けて書く）。
          #
          # 扉絵の章扉は @page :nth(1) の全面背景で成り立つので、最初の節が同じページへ流れ込むと扉絵の
          # 上に本文と節絵が重なる（pdf_h1.png 実測）。扉絵を使うテーマの全部に要る骨格なので、テーマの
          # CSS ではなく機能が書く。settings 層に書くのは、theme 層の break-before: var(…)（値は auto）に
          # PDF で勝つため。
          # - EPUB と Kindle の扉絵は通常のフローの合成 SVG 画像で全面背景ではないので、body.vs-epub
          #   （クリーンと Kindle の共通の印）を除いて PDF に限る。
          # - section.level2:first-of-type は section.level1 の直下の最初の節。h1 と .chapter-lead は
          #   section 要素でないので :first-of-type の数に入らない。
          # - `@pagebreak:recto` の直後で記法の側の改ページに一本化した h2（vs-break-merged）は除く。
          #   一本化の規則は utilities 層にあり、settings 層のこの規則には負けるので、選ぶ対象の側で
          #   外す（css-layer-restructure-spec.md §2.4）。
          def guard_rule(active:)
            return '' unless active

            selectors = PAGE_KINDS.map do
              "body.#{it}:not(.vs-epub) section.level2:first-of-type > .section-topic h2:not(.vs-break-merged)"
            end
            <<~CSS.chomp
              /* 章扉は全面の扉絵で成立するページなので、最初の節だけは次ページから始める。 */
              #{selectors.join(",\n")} {
                break-before: page;
                page-break-before: always;
              }
            CSS
          end
        end
      end
    end
  end
end
