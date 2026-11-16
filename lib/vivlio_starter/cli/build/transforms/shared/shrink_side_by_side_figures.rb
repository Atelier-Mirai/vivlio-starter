# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/shared/shrink_side_by_side_figures.rb
# ================================================================
# 責務:
#   左右に並べる囲みの中の図を、PDF の片側の幅に抑える
# ================================================================

require_relative '../context'
require_relative '../dom'

module VivlioStarter
  module CLI
    module Build
      # 左右に並べる囲みの中の図を、PDF の片側の幅に抑える
      module Transforms::Shared::ShrinkSideBySideFigures
        module_function

        # side-by-side の片側が本文の幅に占める割合（PDF は左右 2 列）。
        SIDE_BY_SIDE_COLUMN_RATIO = 0.5

        # 左右に並べる囲み（side-by-side）の中の図を、PDF と同じ大きさに抑える（両フレーバ）。
        #
        # EPUB・Kindle は side-by-side を上下に積む（画面の幅が分からず、狭い画面では左右とも
        # 読めなくなる・stylesheets/targets/epub.css）。積むと中の図が本文の幅いっぱいに広がり、PDF では
        # 片側に収まっていた mermaid の図がタブレットの画面を占めていた。図の幅を、書かれた幅
        # （{width=60%} など。無ければ 100%）に片側の割合を掛けた値にして、中央に置く。
        # Kindle は外部 CSS の画像の大きさを無視するので inline で付け、中央寄せは
        # margin-left / margin-right の auto で書く（margin-inline の auto は 0 に解かれる）。
        # ディスプレイ数式は文字の大きさに合わせてあるので触らない。
        #
        # @param doc [Nokogiri::HTML5::Document] 1 ページの HTML（破壊的に書き換える）
        # @param ctx [Transforms::Context]
        def call(doc, ctx)
          figures = doc.css('.side-by-side figure').reject { it['class'].to_s.split.include?('vs-math') || !it.at_css('img') }
          return if figures.empty?

          figures.each do |figure|
            written = figure['style'].to_s[/(?:\A|;)\s*width:\s*([\d.]+)%/, 1]&.to_f || 100.0
            width = (written * SIDE_BY_SIDE_COLUMN_RATIO).round(1)
            style = figure['style'].to_s.gsub(/(?:\A|;)\s*(?:max-)?width:[^;]*/, '').sub(/\A;/, '').strip
            figure['style'] = style
            Transforms::Dom.add_inline_style(figure, "width: #{width}%; max-width: #{width}%; margin-left: auto; margin-right: auto;")
            Transforms::Dom.add_inline_style(figure.at_css('img'), 'width: 100%; height: auto;')
          end
          Common.log_info("[EPUB] #{ctx.page_name} の side-by-side の図 #{figures.size} 枚を片側の幅に抑えました")
        end
      end
    end
  end
end
