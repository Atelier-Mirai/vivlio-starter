# frozen_string_literal: true

require 'nokogiri'
require_relative '../common'
require_relative '../techbook/emoji_replacer'

module VivlioStarter
  module CLI
    module Build
      # ------------------------------------------------
      # FigureEmoji: 図の SVG の絵文字を、twemoji の図形に差し替える（改善案 #127 段階 3）
      # ------------------------------------------------
      # 地の文の絵文字は techbook が twemoji の画像で組む（Techbook::EmojiReplacer）が、図の SVG の
      # 中は字のままで、OS の絵文字の書体（Apple Color Emoji）で描かれて Type 3 になっていた。
      # 色付きの絵文字の書体を埋める方法は採らない。Apple Color Emoji と同じく、色付きの字形は Type 3 で
      # 書き出される見込み（COLR の書体では確かめていない）。
      #
      # 中身が絵文字だけの `<text>` を、同じ位置・大きさの twemoji の `<svg>`（図形）に差し替える。
      # 1 字 = 1em の正方形で、下端を基線から 0.15em 下に置く（EmojiReplacer の `<img>` と同じ）。
      # 文字と絵文字が混ざった `<text>` は、絵文字の位置を組まずには決められないので差し替えない
      # （GlyphCoverageCheck が知らせる）。位置や大きさを読み取れないもの（`dx`・`em` の大きさ・
      # `<style>` の規則で決まる大きさなど）も差し替えない。
      #
      # 著者の図は書き換えない。DerivedSvg が作る派生の中だけで差し替える。
      # ------------------------------------------------
      module FigureEmoji
        # `<text>…</text>` 1 つ（中の `<tspan>` ごと）。Nokogiri が数える `text` 要素と同じ順に並ぶ
        TEXT_ELEMENT = %r{<text\b[^>]*>.*?</text>}m

        # 絵文字の 1 字（書記素）。肌の色・異体字セレクタ・ZWJ でつないだ字も 1 字に数える
        EMOJI_GRAPHEME = /\A\p{Extended_Pictographic}/

        # 位置を読み取れなくなる属性
        UNSUPPORTED_ATTRIBUTES = %w[dx dy rotate textLength lengthAdjust].freeze

        # 字の下端を基線からどれだけ下げるか（EmojiReplacer の vertical-align: -0.15em）
        DESCENT = 0.15

        module_function

        # @param svg [String] 図の SVG
        # @param emoji_dir [String] twemoji の SVG の置き場
        # @return [String] 差し替えた SVG（差し替えるものが無ければ svg そのもの）
        def replace(svg, emoji_dir: File.join(Common.stylesheets_dir, 'twemoji'))
          return svg unless svg.match?(/\p{Extended_Pictographic}/) && Dir.exist?(emoji_dir)

          doc = Nokogiri::XML(svg)
          replacements = doc.css('text').map { replacement_for(it, emoji_dir) }
          return svg if replacements.none?

          index = -1
          svg.gsub(TEXT_ELEMENT) do |element|
            index += 1
            replacements[index] || element
          end
        rescue StandardError => e
          Common.log_debug("[figure-emoji] 絵文字を差し替えられませんでした: #{e.message}")
          svg
        end

        # 1 つの `<text>` の差し替え先。差し替えないものは nil
        def replacement_for(node, emoji_dir)
          # --- Phase: 中身が絵文字だけか ---
          return nil if node.element_children.any?

          graphemes = node.text.strip.scan(/\X/)
          return nil if graphemes.empty? || !graphemes.all? { it.match?(EMOJI_GRAPHEME) }
          return nil if UNSUPPORTED_ATTRIBUTES.any? { node.key?(it) }

          # --- Phase: 位置と大きさ ---
          x = number(node['x'] || '0')
          y = number(node['y'] || '0')
          size = font_size(node)
          return nil unless x && y && size

          shapes = graphemes.map { emoji_shape(it, emoji_dir) }
          return nil if shapes.any?(&:nil?)

          width = size * graphemes.size
          left = case inherited(node, 'text-anchor')
                 when 'middle' then x - (width / 2)
                 when 'end' then x - width
                 else x
                 end
          top = y - (size * (1 - DESCENT))

          # --- Phase: twemoji の図形を並べる ---
          boxes = shapes.each_with_index.map do |(view_box, body), i|
            %(<svg x="#{fmt(left + (size * i))}" y="#{fmt(top)}" width="#{fmt(size)}" height="#{fmt(size)}" ) +
              %(viewBox="#{view_box}">#{body}</svg>)
          end
          transform = node['transform'] ? %( transform="#{node['transform']}") : ''
          %(<g role="img" aria-label="#{graphemes.join}"#{transform}>#{boxes.join}</g>)
        end

        # twemoji の SVG の viewBox と中身。無ければ nil
        def emoji_shape(grapheme, emoji_dir)
          path = File.join(emoji_dir, "#{Techbook::EmojiReplacer.emoji_codepoint(grapheme)}.svg")
          return nil unless File.file?(path)

          source = File.read(path, encoding: 'utf-8')
          view_box = source[/<svg\b[^>]*\bviewBox="([^"]+)"/, 1] || '0 0 36 36'
          body = source[%r{<svg\b[^>]*>(.*)</svg>}m, 1]
          body && [view_box, body]
        end

        # 字の大きさ（px）。属性・style のどちらにも書いてなければ祖先から引き継ぐ。
        # `<style>` の規則が大きさを決めるかもしれない図では、class の付いた字を差し替えない
        def font_size(node)
          styled = node.document.css('style').any? { it.text.include?('font-size') }
          classed = [node, *node.ancestors].any? { it.element? && it.key?('class') }
          return nil if styled && classed

          value = inherited(node, 'font-size') or return 16.0
          value.match?(/\A\s*[\d.]+\s*(?:px)?\s*\z/) ? value.to_f : nil
        end

        # 属性か style に書いた値を、字から祖先へたどって引く
        def inherited(node, name)
          [node, *node.ancestors].each do |element|
            next unless element.element?

            from_style = element['style'].to_s[/(?:\A|;)\s*#{name}\s*:\s*([^;]+)/, 1]
            return from_style.strip if from_style
            return element[name].strip if element.key?(name)
          end
          nil
        end

        def number(value) = value.match?(/\A\s*-?[\d.]+\s*\z/) ? value.to_f : nil

        def fmt(value) = format('%.2f', value).sub(/\.?0+\z/, '')
      end
    end
  end
end
