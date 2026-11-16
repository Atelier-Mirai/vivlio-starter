# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/kindle/textify_simple_math.rb
# ================================================================
# 責務:
#   単純なインライン数式を、字へ直す
# ================================================================

require_relative '../../math_text_renderer'
require_relative '../context'

module VivlioStarter
  module CLI
    module Build
      # 単純なインライン数式を、字へ直す
      module Transforms::Kindle::TextifySimpleMath
        module_function

        # Kindle 用に、単純なインライン数式（img.vs-math-inline）を HTML テキストへ変換する。
        # KFX は画像を本文フォント相対サイズにできず、数式 SVG がフォントサイズ変更に追従しない
        # （KNOWN_ISSUES の 2 件）。alt に保存された元 LaTeX を MathTextRenderer のサブセットで
        # テキスト化できたものだけ <span class="vs-math vs-math-text"> へ置換し、以降フォントに
        # 100% 追従させる（kindle-inline-math-textify-spec.md §2・§4.2）。
        # ディスプレイ数式（figure.vs-math-display）は対象外——行占有で px 固定でも破綻しない。
        # 置換後は img.vs-math-inline が消えるため冪等。
        #
        # **落とし先は 3 段**（plain-math-notation-spec.md §3-2.3）:
        #   1. MathTextRenderer が通る      → HTML（変数が斜体・真の <sup>。いちばん綺麗）
        #   2. 通らない & 素の表記で書かれた → **著者の原文をテキストで**
        #   3. 通らない & LaTeX で書かれた   → SVG のまま（Transforms::Kindle::ConvertMathUnits が px を効かせる）
        #
        # 2 が要るのは、変換器が起こした TeX を MathTextRenderer が受理しきれないため。
        # `sin(x)` は `\sin(x)` になるが `\sin` はあちらのホワイトリストに無い——そこで SVG へ
        # 落とすと、変換器を入れる前より Kindle が悪くなる（実測 34 種）。**素の表記はそのまま
        # 読める形で書かれている**ので、原文を出すのが最も素直で、かつ拒否が起きなくなる
        # （実測: 追従率 20% → 100%）。LaTeX で書かれた式（data-vs-tex が無い）に原文は使えない
        # ——`\sqrt{2}` と出てしまうため。
        #
        # @param doc [Nokogiri::HTML5::Document] 1 ページの HTML（破壊的に書き換える）
        # @param ctx [Transforms::Context]
        def call(doc, ctx)
          nodes = doc.css('img.vs-math-inline')
          return if nodes.empty?

          counts = Hash.new(0)
          nodes.each { |img| counts[textify_inline_math!(img, doc)] += 1 }
          return if counts[:html].zero? && counts[:plain].zero?

          Common.log_info(
            "[EPUB] #{ctx.page_name} のインライン数式 #{counts[:html] + counts[:plain]} 件をテキスト化" \
            "（HTML #{counts[:html]} 件 / 原文 #{counts[:plain]} 件" \
            "#{counts[:svg].positive? ? " / SVG 維持 #{counts[:svg]} 件" : ''}）"
          )
        end

        # <img> 1 つの落とし先を決めて置換する。戻り値は :html / :plain / :svg。
        def textify_inline_math!(img, doc)
          # 素の表記から起こした式は data-vs-tex に TeX が入っている（alt は著者の原文のまま）。
          hint = img['data-vs-tex'].to_s
          source = strip_math_delimiters(img['alt'])
          latex = hint.empty? ? source : hint

          if (html = MathTextRenderer.render(latex))
            img.replace(math_text_span(doc, inner_html: html))
            :html
          elsif !hint.empty? && !source.empty?
            img.replace(math_text_span(doc, text: source))
            :plain
          else
            :svg
          end
        end

        # テキスト化した数式を包む span。text: で渡すと Nokogiri が HTML 予約文字を退避する。
        def math_text_span(doc, inner_html: nil, text: nil)
          span = Nokogiri::XML::Node.new('span', doc)
          span['class'] = text ? 'vs-math vs-math-text vs-math-plain' : 'vs-math vs-math-text'
          text ? span.content = text : span.inner_html = inner_html
          span
        end

        # 数式 alt から $…$ / \(…\) デリミタを剥いで LaTeX 本文を取り出す。
        def strip_math_delimiters(alt)
          s = alt.to_s.strip
          if s.start_with?('\\(') && s.end_with?('\\)')
            s[2...-2].to_s.strip
          elsif s.start_with?('$') && s.end_with?('$')
            s[1...-1].to_s.strip
          else
            s
          end
        end
      end
    end
  end
end
