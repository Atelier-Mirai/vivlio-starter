# frozen_string_literal: true

require_relative '../units'

module VivlioStarter
  module CLI
    module Build
      # ================================================================
      # Build::TextGridNotice — 縦書きの本の、版面の字数と行数の案内（novel-vertical-spec.md §4.2）
      # ================================================================
      # 行数と字数のキーは置かず、版面は余白で決める。*_custom で余白を変えた著者が、結果を数で
      # 確かめられるよう、vs build --log と vs preflight の終わりに 1 行で示す（💡「版面: 38 字 × 16 行」）。
      # 字数が整数にならない（端数が 0.2 字以上）ときは、同じ行で天地の余白の直し方を示す。
      #
      # 縦書きでは、字数が天と地の間、行数がノドと小口の間に入る。
      #   字数 ＝（紙の高さ − 天 − 地）÷ 字の大きさ
      #   行数 ＝ ⌊（紙の幅 − ノド − 小口 − 字の大きさ）÷ 行送り⌋ ＋ 1
      # ================================================================
      module TextGridNotice
        # 字数の端数をこれ未満なら整数とみなす（§4.2）
        FRACTION_TOLERANCE = 0.2

        Grid = Data.define(:chars, :lines, :font_mm)

        module_function

        # @param verbose [Boolean] vs build は --log（info 以上）のときだけ示す。vs preflight は常に示す
        def report(page: Common::CONFIG&.page, traits: Common.traits, verbose: true)
          return unless traits.vertical?
          return unless verbose

          grid = resolve(page&.to_h || {}) or return
          Common.log_always("💡 #{message(grid)}")
        end

        # @param page [Hash] Common::CONFIG.page（プリセットを当てた後）
        # @return [Grid, nil] 寸法が読めなければ nil
        def resolve(page)
          width, height = Common.resolve_page_size(page).map { Units.length_to_mm(it) }
          font, advance, top, bottom, inner, outer =
            page.values_at(:base_font_size, :base_line_height, :margin_top, :margin_bottom, :margin_inner, :margin_outer)
                .map { Units.length_to_mm(it) }
          return if [width, height, font, advance, top, bottom, inner, outer].any?(&:nil?)
          return unless font.positive? && advance.positive?

          Grid.new(chars: (height - top - bottom) / font,
                   lines: ((width - inner - outer - font) / advance).floor + 1,
                   font_mm: font)
        end

        # @param grid [Grid]
        def message(grid)
          whole = grid.chars.floor
          fraction = grid.chars - whole
          return "版面: #{grid.chars.round} 字 × #{grid.lines} 行" if fraction < FRACTION_TOLERANCE || fraction > 1 - FRACTION_TOLERANCE

          more = format('%.1f', fraction * grid.font_mm)
          less = format('%.1f', (1 - fraction) * grid.font_mm)
          "版面: #{format('%.1f', grid.chars)} 字 × #{grid.lines} 行（天と地の余白の和を #{more}mm 増やすと #{whole} 字、" \
            "#{less}mm 減らすと #{whole + 1} 字ちょうどになります）"
        end
      end
    end
  end
end
