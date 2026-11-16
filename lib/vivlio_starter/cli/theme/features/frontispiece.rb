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
        end
      end
    end
  end
end
