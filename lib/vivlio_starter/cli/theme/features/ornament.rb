# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/theme/features/ornament.rb
# ================================================================
# 責務:
#   組み込みの機能 ornament（節見出しの節絵）の宣言と、book-settings.css へ書く値
#   （theme-contract-spec.md §3.4）。
# ================================================================

require_relative '../option'

module VivlioStarter
  module CLI
    module Theme
      module Features
        # 節見出しの節絵
        module Ornament
          NAME = 'ornament'

          OPTIONS = [
            Option.new(path: %i[ornament image], type: 'image', default: 'sakura'),
            Option.new(path: %i[ornament heading_chars], type: 'number', default: 14)
          ].freeze

          module_function

          # book-settings.css の :root に書く宣言。機能が無効なら画像を none にする。
          # 節題は箱幅ではなく字の大きさで 1 行の字数を決める（節絵の帯は版面幅いっぱいで固定）
          def declarations(settings, active:, image_prefix:, page_cfg: {})
            bsc = PreProcessCommands::BookSettingsCss
            image = active ? bsc.css_image_value(settings[:ornament_path], image_prefix:) : 'none'
            ["--book-ornament-image: #{image};", *metric_declarations(settings, page_cfg)]
          end

          # book-settings.css の @page の規則（節絵には無い）
          def page_rule(*) = ''

          # 節題の字の大きさ（文字数指定がある時だけ）
          def metric_declarations(settings, page_cfg)
            chars = settings[:ornament_heading_chars_value]
            return [] unless chars

            bsc = PreProcessCommands::BookSettingsCss
            size = bsc.section_title_font_q(chars, bsc.text_area_width_mm(page_cfg), bsc.paper_scale_of(page_cfg))
            ["--book-ornament-title-font-size: #{size}Q;"]
          end
        end
      end
    end
  end
end
