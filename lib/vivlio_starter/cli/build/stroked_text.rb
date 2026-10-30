# frozen_string_literal: true

require 'cgi'
require 'nokogiri'
require_relative '../pre_process/svg_font_embedder'
require_relative 'figure_emoji'
require_relative 'font_metrics'
require_relative 'glyph_outline'

module VivlioStarter
  module CLI
    module Build
      # ------------------------------------------------
      # StrokedText: 図の SVG の縁取りした字を、Type 3 にならない形へ組み替える（改善案 #129）
      # ------------------------------------------------
      # 字に `stroke` を掛けると、書体を埋めた図でも、Chromium はその字を Type 3 で書き出す。
      # 地の線や塗りの上でラベルを読めるようにする白い縁取りで、lives-mathematics の 10 枚に使われている。
      #
      # 縁を、字の輪郭（GlyphOutline）の `<path>` に stroke を掛けた図形にし、字の本体は塗りだけの
      # `<text>` のまま残す。縁の形は stroke そのものなので元と変わらず、PDF の字も 1 回だけになる
      # （元の図は字が 2 回ずつ抜き出される。字を 16 方向へずらして重ねる形は 4 回で、縁も波打つ）。
      #
      # 図に埋める書体の部分集合（TTFunk）は GPOS を持たないので、図の字に kern は当たらない。
      # 字の送りを足すだけで、Chromium が組む位置と一致する。
      #
      # PDF の派生の中だけで組み替える（DerivedSvg.prepare_for_pdf）。Type 3 は PDF だけの問題で、
      # Kindle は図を OS の書体で焼くので、本の書体の輪郭の縁では字とずれることがある。
      #
      # 字の位置を読み取れないもの（`<tspan>`・`dy`・`letter-spacing`・`dominant-baseline` など）は
      # 組み替えない。残った字は `remaining` が返し、preflight と build が図の名前を添えて知らせる。
      # ------------------------------------------------
      module StrokedText
        Embedder = PreProcessCommands::SvgFontEmbedder

        # 字の位置・形を変えるので、字の送りを足すだけでは組めなくなる性質
        LAYOUT_PROPERTIES = %w[
          letter-spacing word-spacing font-style font-variant font-stretch
          dominant-baseline alignment-baseline baseline-shift writing-mode direction
        ].freeze
        PLAIN_VALUES = %w[normal auto 0 baseline ltr horizontal-tb].freeze

        # 縁の図形へ、そのまま写す性質
        COPIED_PROPERTIES = %w[stroke stroke-opacity stroke-linejoin stroke-linecap stroke-miterlimit].freeze

        NO_STROKE = %w[none transparent].freeze

        # `<style>` の規則・字の style・属性を、CSS の強さの順に引く。
        # 規則どうしは書いた順だけを見る（詳細度は見ない）。図の中で詳細度に頼る書き方は見ていない
        class Cascade
          CSS_RULE = /([^{}]+)\{([^{}]*)\}/
          # 図に埋めた書体（巨大な base64）は規則として読まない
          FONT_FACE = /@font-face\s*\{[^}]*\}/
          COMMENT = %r{/\*.*?\*/}m

          def initialize(doc)
            @rules = Hash.new { |table, id| table[id] = {} }
            css = doc.css('style').map(&:text).join("\n").gsub(COMMENT, '').gsub(FONT_FACE, '')
            css.scan(CSS_RULE) do |selector, body|
              found = matching(doc, selector.strip)
              found.each { @rules[it.pointer_id].merge!(declarations(body)) }
            end
          end

          # 字から祖先へたどって引く。無ければ nil
          def value(node, name)
            [node, *node.ancestors].each do |element|
              next unless element.element?

              found = own(element, name)
              return found if found
            end
            nil
          end

          # 要素そのものに書いた値（継承しない性質に使う）
          def own(element, name)
            declarations(element['style'].to_s)[name] || @rules[element.pointer_id][name] || element[name]&.strip
          end

          private

          def matching(doc, selector)
            doc.css(selector).to_a
          rescue Nokogiri::SyntaxError
            [] # 疑似クラスなど、Nokogiri が読めないセレクタは静止した図に効かない
          end

          def declarations(body)
            body.split(';').filter_map { |declaration|
              name, value = declaration.split(':', 2)
              [name.strip.downcase, value.strip] if value
            }.to_h
          end
        end

        module_function

        # @param svg [String] 図の SVG
        # @return [String] 組み替えた SVG（組み替えるものが無ければ svg そのもの）
        def outline(svg)
          return svg unless svg.include?('stroke')

          doc = Nokogiri::XML(svg)
          cascade = Cascade.new(doc)
          texts = doc.css('text')
          # 正規表現で数えた字と 1 対 1 に並ばない図（`<text/>` など）は、取り違えるので組み替えない
          return svg unless svg.scan(FigureEmoji::TEXT_ELEMENT).size == texts.size

          replacements = texts.map { replacement_for(it, cascade) }
          return svg if replacements.none?

          index = -1
          svg.gsub(FigureEmoji::TEXT_ELEMENT) do |element|
            index += 1
            replacements[index] || element
          end
        rescue StandardError => e
          Common.log_debug("[stroked-text] 縁取りの字を組み替えられませんでした: #{e.message}")
          svg
        end

        # 組み替えられない縁取りの字（知らせる側が使う）。
        # @param svg [String] 書体を寄せた図の SVG（DerivedSvg.resolve_families の結果）
        # @return [Array<String>] 字の並び
        def remaining(svg)
          doc = Nokogiri::XML(outline(svg))
          cascade = Cascade.new(doc)
          doc.css('text').select { |text| [text, *text.css('tspan')].any? { stroked?(it, cascade) } }
             .map { plain_text(it) }.reject(&:empty?).uniq
        end

        # 1 つの `<text>` の差し替え先。組み替えないものは nil
        def replacement_for(node, cascade)
          return nil unless stroked?(node, cascade)

          halo = halo_for(node, cascade) or return nil
          order = cascade.value(node, 'paint-order').to_s.split.reject { it == 'markers' }
          # 字の style は `<style>` の規則より強い。祖先の stroke も、属性でなくここで止める
          node['style'] = [node['style'], 'stroke:none'].compact.join(';')
          text = node.to_xml(encoding: 'UTF-8')
          order.first == 'stroke' ? "#{halo}#{text}" : "#{text}#{halo}"
        end

        def stroked?(node, cascade)
          paint = cascade.value(node, 'stroke')
          return false if paint.nil? || NO_STROKE.include?(paint.downcase)

          width = cascade.value(node, 'stroke-width')
          width.nil? || width.to_f.positive?
        end

        # 縁の図形。読み取れないものがあれば nil
        def halo_for(node, cascade)
          # --- Phase: 位置・大きさを読み取れるか ---
          return nil if node.element_children.any? || FigureEmoji::UNSUPPORTED_ATTRIBUTES.any? { node.key?(it) }
          return nil if LAYOUT_PROPERTIES.any? { !PLAIN_VALUES.include?(cascade.value(node, it) || 'normal') }
          return nil unless (cascade.value(node, 'stroke-dasharray') || 'none') == 'none'

          x = FigureEmoji.number(node['x'] || '0')
          y = FigureEmoji.number(node['y'] || '0')
          size = pixels(cascade.value(node, 'font-size') || '16')
          stroke_width = pixels(cascade.value(node, 'stroke-width') || '1')
          return nil unless x && y && size && stroke_width

          # --- Phase: 字の輪郭を並べる ---
          fonts = fonts_for(node, cascade) or return nil
          pen = 0.0
          paths = plain_text(node).each_char.map do |char|
            font = font_of(char, fonts) or return nil
            shape = font.outline(char)
            return nil if shape.nil? && !char.match?(/[[:space:]]/)

            path = shape && %(<path transform="translate(#{FigureEmoji.fmt(pen)} 0)" d="#{shape.d}"/>)
            pen += font.advance(char) * GlyphOutline::EM
            path
          end.compact
          return nil if paths.empty?

          # --- Phase: 字と同じ位置へ置く ---
          scale = size / GlyphOutline::EM
          left = case cascade.value(node, 'text-anchor')
                 when 'middle' then x - (pen * scale / 2)
                 when 'end' then x - (pen * scale)
                 else x
                 end
          transform = [node['transform'], "translate(#{FigureEmoji.fmt(left)} #{FigureEmoji.fmt(y)})", "scale(#{scale.round(5)})"]
          copied = COPIED_PROPERTIES.filter_map { |name|
            value = cascade.value(node, name)
            %(#{name}="#{CGI.escapeHTML(value)}") if value
          }
          opacity = cascade.own(node, 'opacity')
          copied << %(opacity="#{CGI.escapeHTML(opacity)}") if opacity
          %(<g transform="#{transform.compact.join(' ')}" fill="none" #{copied.join(' ')} ) +
            %(stroke-width="#{FigureEmoji.fmt(stroke_width / scale)}">#{paths.join}</g>)
        end

        # 字を探す書体の並び（FontMetrics）。先頭は図の書体で、見つからなければ nil。
        # 後ろは、図に埋める予備の書体（SvgFontEmbedder#fallback_face_rules と同じ順）
        def fonts_for(node, cascade)
          family = cascade.value(node, 'font-family').to_s.split(',').first.to_s.strip.delete(%q("'))
          family = Embedder.configured_heading_font if family.empty?
          weight = heavy?(cascade.value(node, 'font-weight')) ? :bold : :regular

          primary = load_font(family, weight) or return nil
          fallbacks = Embedder::FALLBACK_FONTS.reject { Embedder.comparable(it) == Embedder.comparable(family) }
          [primary, *fallbacks.filter_map { load_font(it, weight) }]
        end

        def load_font(name, weight)
          path = Embedder.font_path(name, weight:)
          path && File.file?(path) ? FontMetrics.load(path) : nil
        end

        def font_of(char, fonts)
          primary, *fallbacks = fonts
          return primary if primary.glyph?(char)
          return nil if char.match?(Embedder::FALLBACK_EXCLUDED)

          fallbacks.find { it.glyph?(char) }
        end

        def heavy?(weight) = %w[bold bolder].include?(weight) || weight.to_i >= 600

        # `13` と `13px` だけを読む（`em` や `%` は周りの文脈が要る）
        def pixels(value) = value[/\A\s*([\d.]+)\s*(?:px)?\s*\z/, 1]&.to_f

        # 組み上がりの字。SVG の既定では、字の前後の空白を落とし、続く空白を 1 つにまとめる
        def plain_text(node) = node.text.strip.gsub(/\s+/, ' ')
      end
    end
  end
end
