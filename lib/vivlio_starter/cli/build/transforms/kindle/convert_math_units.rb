# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/kindle/convert_math_units.rb
# ================================================================
# 責務:
#   数式の画像の寸法を、ex から em・px へ直す
# ================================================================

require_relative '../context'

module VivlioStarter
  module CLI
    module Build
      # 数式の画像の寸法を、ex から em・px へ直す
      module Transforms::Kindle::ConvertMathUnits
        module_function

        # ex→em の換算係数。CSS 慣用の 1ex ≈ 0.5em（MathJax SVG の ex/em 比の近似）。
        # 端末フォント非依存の近似で、EPUB の本文サイズに収めるには十分（§3-2）。
        EX_TO_EM = 0.5

        # 表セル内の数式（単位記号など）の最低高さ（em）。Kindle は多列の表を縮小しがちで、
        # ×0.5 だと単位記号が読めなくなるため、表内に限り最低この高さを確保し等比拡大する。
        MIN_TABLE_MATH_EM = 1.0

        # EPUB の基準フォント px（1em の近似）。数式 SVG は固有寸法を持たないため、Kindle が
        # inline の em/ex を無視すると img 既定の 300×150px で巨大表示される。これを防ぐため
        # em 値 × この係数を width/height の HTML 属性（px）として与え、Kindle でも本文相当に固定する。
        EPUB_BASE_FONT_PX = 16

        # inline 数式（img.vs-math-inline）・display 数式画像の inline style の ex 値を em へ変換し、
        # さらに px の width/height 属性をフォールバックとして付与する。
        # CSS を解す閲覧アプリは em（style）で本文連動、Kindle は em を無視して px 属性で本文相当に固定する。
        # 固有寸法のない数式 SVG は px 属性が無いと 300px 既定で巨大表示されるため（§3）。
        #
        # @param doc [Nokogiri::HTML5::Document] 1 ページの HTML（破壊的に書き換える）
        # @param ctx [Transforms::Context]
        def call(doc, ctx)
          nodes = doc.css('img.vs-math-inline, figure.vs-math-display img')
          return if nodes.empty?

          nodes.each do |img|
            style = img['style']
            next if style.nil? || style.empty?

            converted = convert_math_style(style, in_table: math_in_table?(img))
            img['style'] = converted unless converted == style
            apply_math_px_fallback!(img, converted)
          end
          Common.log_info("[EPUB] #{ctx.page_name} の数式寸法を em＋px 属性へ整えました")
        end

        # style の em 値から px を算出し、width/height の HTML 属性へ反映する（Kindle 用フォールバック）。
        def apply_math_px_fallback!(img, style)
          w = style[/width:\s*(-?\d*\.?\d+)em/, 1]&.to_f
          h = style[/height:\s*(-?\d*\.?\d+)em/, 1]&.to_f
          img['width'] = (w * EPUB_BASE_FONT_PX).round.to_s if w&.positive?
          img['height'] = (h * EPUB_BASE_FONT_PX).round.to_s if h&.positive?
        end

        # 数式画像が表セル（td/th）内にあるか。
        def math_in_table?(img) = img.ancestors('td, th').any?

        # style 文字列の `<数値>ex` を em へ換算する。基本は ×0.5。表セル内で換算後の
        # height が MIN_TABLE_MATH_EM 未満になる場合は、height がその値になるよう全寸法を
        # 等比拡大する（縦横比・ベースラインを保ったまま単位記号を読める大きさにする）。
        def convert_math_style(style, in_table:)
          factor = EX_TO_EM
          if in_table
            height_ex = style[/height:\s*(-?\d*\.?\d+)ex/, 1]&.to_f
            if height_ex&.positive? && height_ex * EX_TO_EM < MIN_TABLE_MATH_EM
              factor = MIN_TABLE_MATH_EM / height_ex
            end
          end

          style.gsub(/(-?\d*\.?\d+)ex\b/) do
            "#{(::Regexp.last_match(1).to_f * factor).round(4)}em"
          end
        end
      end
    end
  end
end
