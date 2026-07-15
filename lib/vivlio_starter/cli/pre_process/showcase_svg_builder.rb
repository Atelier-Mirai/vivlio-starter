# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/showcase_svg_builder.rb
# ================================================================
# 責務:
#   図解注釈記法（:::{.showcase}）の行パースと、注釈を焼き込んだ合成 SVG の生成。
#   外部ツールに一切依存しない純関数の集合で、決定的に単体テストできる
#   （explanatory-diagram-spec.md §7.1）。ツール依存（magick / rsvg-convert）は
#   ShowcaseTransformer 側に隔離する。
#
# 座標系（§5.2〜§5.3）:
#   - rect / pointer の座標・寸法は「crop 適用前の元画像」に対するパーミル
#     （左上 (0,0)〜右下 (1000,1000)）。crop は viewBox の切り出し窓を変えるだけで
#     座標系を動かさないため、crop を後から調整しても全注釈の座標が生き残る。
#   - 著者は実測 px でも書ける（"120px"）。パース時に元画像実寸でパーミルへ正規化する。
#   - font-size / border 太さ等のスタイル寸法だけは「クロップ後の画像幅を 1000 とする
#     正規化単位」で、描画時に u（= クロップ後幅 px / 1000）倍する。読者が見る大きさは
#     表示幅に対する比率で決まるため、この定義なら元画像の解像度が変わっても揃う。
# ================================================================

module VivlioStarter
  module CLI
    module PreProcessCommands
      # showcase 記法のパースと合成 SVG 生成（純関数）
      module ShowcaseSvgBuilder
        # 注釈 1 件。coords は rect => [x, y, w, h] / pointer => [x, y]（パーミル正規化済み）。
        Annotation = Data.define(:type, :number, :coords, :options, :comment)

        # showcase ブロック 1 つ分。crop は [top, right, bottom, left]（パーミル正規化済み）。
        ShowcaseBlock = Data.define(:image_path, :alt, :width, :crop, :annotations)

        # ブロック内の画像行。attributes は {width=… crop=…} を解いた Hash。
        ImageLine = Data.define(:alt, :path, :attributes)

        # --- 行パターン（§7.2） ---
        # 数値トークン: パーミル（無単位）or 元画像の実ピクセル（px 接尾辞）
        NUM          = /-?\d+(?:\.\d+)?(?:px)?/
        IMAGE_LINE   = /^!\[([^\]]*)\]\(([^)]+)\)(?:\{([^}]*)\})?\s*$/
        RECT_LINE    = /^rect(?::(\d+))?\s+(#{NUM})\s*,\s*(#{NUM})\s*,\s*(#{NUM})\s*,\s*(#{NUM})(?:\s+\{([^}]*)\})?(?:\s+(.*))?$/
        POINTER_LINE = /^pointer(?::(\d+))?\s+(#{NUM})\s*,\s*(#{NUM})(?:\s+\{([^}]*)\})?(?:\s+(.*))?$/
        COMMENT_LINE = /^#/
        # {…} オプション。値の空白は二重引用符で保護する（border="3 dashed blue"）。
        OPTION_TOKEN = /([\w-]+)=(?:"([^"]*)"|(\S+))/

        # --- 視覚定数（§7.7・初期値は §5.5。すべて「正規化単位」で描画時に u 倍する） ---
        BADGE_RADIUS              = 26      # rect バッジ（丸数字）の半径
        BADGE_FONT_SIZE           = 28      # rect バッジの番号
        BADGE_STROKE_WIDTH        = 2.5     # rect バッジの外枠
        BADGE_FILL                = 'white'
        BADGE_STROKE_COLOR        = '#333333'
        BADGE_TEXT_COLOR          = '#222222' # 白丸に濃色文字
        RECT_BORDER               = '3 solid #ff3b30'
        RECT_BACKGROUND           = 'transparent'
        RECT_CORNER_RADIUS        = 2
        POINTER_BODY_HEIGHT       = 72      # ホームベース記号の本体高さ
        POINTER_FONT_SIZE         = 30      # pointer ラベル
        POINTER_BACKGROUND        = '#ff3b30'
        POINTER_TEXT_COLOR        = 'white'
        POINTER_BADGE_RADIUS      = 20      # 本体内の白抜き小バッジ
        POINTER_BADGE_FONT_SIZE   = 24
        POINTER_BADGE_STROKE      = 2
        POINTER_CONTENT_GAP       = 8       # 小バッジとラベルの間隔
        POINTER_BODY_PADDING      = 24      # 本体の左右余白
        POINTER_MIN_BODY_RATIO    = 1.2     # 本体長の下限（本体高さ比）
        # 線種 → stroke-dasharray（値は正規化単位）
        DASH_PATTERNS             = { 'dashed' => [8, 5], 'dotted' => [2, 4] }.freeze
        # ▶ の向き → 基準形（右向き）からの回転角。SVG の rotate は時計回り。
        POINTER_ROTATIONS         = { 'right' => 0, 'down' => 90, 'left' => 180, 'up' => 270 }.freeze
        # <text> のベースライン補正（dominant-baseline はレンダラ間で挙動差があるため使わない）
        BASELINE_SHIFT            = 0.34

        module_function

        # ブロック内の最初の画像行を取り出す。
        # parse より前に単独で呼べるのは、元画像の実寸取得（px→パーミル変換に必要）に
        # 画像パスが要るため——寸法なしでは parse が成立しないという順序上の制約による。
        #
        # @param lines [Array<String>] ブロック内部の行
        # @return [ImageLine, nil] 画像行が無ければ nil
        def scan_image(lines)
          match = lines.lazy.filter_map { it.match(IMAGE_LINE) }.first
          return nil unless match

          ImageLine.new(alt: match[1], path: match[2], attributes: parse_options(match[3].to_s))
        end

        # ブロック内の画像行の枚数（2 枚目以降の警告判定用）。
        def image_line_count(lines) = lines.count { it.match?(IMAGE_LINE) }

        # ブロック内部の行を ShowcaseBlock へパースする。
        #
        # @param lines [Array<String>] ブロック内部の行
        # @param orig_w [Integer] 元画像の実幅（px 表記の正規化に使う）
        # @param orig_h [Integer] 元画像の実高さ
        # @param on_warn [#call, nil] 解釈できない行を渡すコールバック（行文字列 1 引数）
        # @return [ShowcaseBlock, nil] 画像行が無ければ nil
        def parse(lines, orig_w:, orig_h:, on_warn: nil)
          image = scan_image(lines)
          return nil unless image

          annotations = lines.filter_map { parse_line(it, orig_w:, orig_h:, on_warn:) }
          ShowcaseBlock.new(
            image_path: image.path,
            alt: image.alt,
            width: image.attributes.fetch('width', '100%'),
            crop: parse_crop(image.attributes['crop'], orig_w:, orig_h:, on_warn:),
            annotations:
          )
        end

        # 1 行を Annotation へ。注釈行でない行（画像・コメント・空行）は nil。
        # rect / pointer のいずれにも照合しない非空行は on_warn へ渡して捨てる
        # （その行だけを捨て、ブロック全体は生かす・§7.2）。
        def parse_line(line, orig_w:, orig_h:, on_warn: nil)
          text = line.chomp
          return nil if text.strip.empty? || text.match?(COMMENT_LINE) || text.match?(IMAGE_LINE)

          if (m = text.match(RECT_LINE))
            coords = [permille(m[2], orig_w), permille(m[3], orig_h),
                      permille(m[4], orig_w), permille(m[5], orig_h)]
            annotation(:rect, m[1], coords, m[6], m[7])
          elsif (m = text.match(POINTER_LINE))
            coords = [permille(m[2], orig_w), permille(m[3], orig_h)]
            annotation(:pointer, m[1], coords, m[4], m[5])
          else
            on_warn&.call(text.strip)
            nil
          end
        end

        def annotation(type, number, coords, options, comment)
          Annotation.new(type:, number: number&.to_i, coords:,
                         options: parse_options(options.to_s), comment: comment.to_s.strip)
        end
        private_class_method :annotation

        # {…} の中身を { key => 値 } へ。引用値が優先、無ければ裸値。
        def parse_options(text)
          text.scan(OPTION_TOKEN).to_h { |key, quoted, bare| [key, quoted || bare] }
        end

        # crop 値（CSS shorthand 準拠で 1/2/4 個）を [top, right, bottom, left]（パーミル）へ。
        def parse_crop(value, orig_w:, orig_h:, on_warn: nil)
          tokens = value.to_s.split
          top, right, bottom, left =
            case tokens.size
            when 0 then return [0.0, 0.0, 0.0, 0.0]
            when 1 then [tokens[0]] * 4
            when 2 then [tokens[0], tokens[1], tokens[0], tokens[1]]
            when 4 then tokens
            else
              on_warn&.call(%(crop="#{value}"))
              return [0.0, 0.0, 0.0, 0.0]
            end

          [permille(top, orig_h), permille(right, orig_w),
           permille(bottom, orig_h), permille(left, orig_w)]
        end

        # 座標トークンをパーミルへ。無単位はそのまま、px 接尾辞は元画像実寸で割る。
        def permille(token, basis)
          value = token.to_f
          return value unless token.end_with?('px')

          basis.positive? ? value / basis * 1000.0 : 0.0
        end

        # crop を差し引いた表示寸法（px）。ラスタライズ幅の算出にも使う。
        # @return [Array(Float, Float)] [幅, 高さ]
        def cropped_size(block, orig_w:, orig_h:)
          top, right, bottom, left = block.crop
          [orig_w * (1000.0 - left - right) / 1000.0, orig_h * (1000.0 - top - bottom) / 1000.0]
        end

        # <img alt> / SVG の aria-label に使う説明文。
        # 番号付きの著者コメントを「① コメント ② コメント…」形式で集約する（§5.6）。
        def alt_text(block)
          segments = block.annotations.filter_map do |a|
            next if a.number.nil? || a.comment.empty?

            "#{circled(a.number)} #{a.comment}"
          end
          base = block.alt.to_s.strip
          return base if segments.empty?

          base.empty? ? segments.join(' ') : "#{base}: #{segments.join(' ')}"
        end

        # 元画像を敷き、注釈をベクタで重ねた合成 SVG を組む。
        #
        # @param block [ShowcaseBlock] パース済みブロック
        # @param orig_w [Integer] 元画像の実幅
        # @param orig_h [Integer] 元画像の実高さ
        # @param data_uri [String] 元画像の base64 data URI（<img> から参照する SVG は
        #   外部リソースを読めないため埋め込みが必須・§6.3）
        # @return [String] SVG 文字列
        def build(block, orig_w:, orig_h:, data_uri:)
          # --- Phase: crop を viewBox の切り出し窓へ換算（画像は無加工のまま） ---
          top, _right, _bottom, left = block.crop
          view_x = orig_w * left / 1000.0
          view_y = orig_h * top / 1000.0
          view_w, view_h = cropped_size(block, orig_w:, orig_h:)

          # スタイル寸法の単位。クロップ後の表示幅に対する比率で見た目を揃える（§7.3）。
          u = view_w / 1000.0

          # --- Phase: 元画像を原寸で敷き、注釈を元画像ピクセル座標で描く（窓外は自動的に不可視） ---
          parts = [image_element(orig_w, orig_h, data_uri)]
          parts.concat(block.annotations.map { render_annotation(it, orig_w:, orig_h:, u:) })

          svg_wrapper(view_x, view_y, view_w, view_h, alt_text(block), parts)
        end

        def render_annotation(annotation, orig_w:, orig_h:, u:)
          case annotation.type
          when :rect    then rect_element(annotation, orig_w:, orig_h:, u:)
          when :pointer then pointer_element(annotation, orig_w:, orig_h:, u:)
          else ''
          end
        end

        # 枠（rect）＋ pos に応じたバッジ。
        def rect_element(annotation, orig_w:, orig_h:, u:)
          x, y, w, h = px_coords(annotation.coords, orig_w, orig_h)
          options = annotation.options
          thickness, dasharray, color = parse_border(options.fetch('border', RECT_BORDER), u)

          shape = %(<rect x="#{fmt(x)}" y="#{fmt(y)}" width="#{fmt(w)}" height="#{fmt(h)}" ) +
                  %(fill="#{escape_attr(options.fetch('background', RECT_BACKGROUND))}" ) +
                  %(stroke="#{escape_attr(color)}" stroke-width="#{fmt(thickness)}"#{dasharray} ) +
                  %(rx="#{fmt(RECT_CORNER_RADIUS * u)}"/>)
          return shape unless annotation.number

          cx, cy = badge_center(options.fetch('pos', 'left'), x, y, w, h)
          shape + badge(cx, cy, annotation.number, options, u)
        end

        # pos → バッジ中心。left/right は枠の辺に跨って載る（§7.5.2）。
        def badge_center(pos, x, y, w, h)
          case pos
          when 'right'  then [x + w, y + (h / 2.0)]
          when 'top'    then [x + (w / 2.0), y]
          when 'bottom' then [x + (w / 2.0), y + h]
          when 'center' then [x + (w / 2.0), y + (h / 2.0)]
          else [x, y + (h / 2.0)]
          end
        end

        # border 値（"3 dashed blue"）をトークンの種別判定で振り分ける（CSS の順序に寛容）。
        # @return [Array(Float, String, String)] [太さ(px), dasharray 属性, 色]
        def parse_border(value, u)
          thickness = 3.0
          style     = 'solid'
          color     = '#ff3b30'
          value.to_s.split.each do |token|
            case token
            when /\A(?:solid|dashed|dotted)\z/    then style = token
            when /\A\d+(?:\.\d+)?(?:px)?\z/       then thickness = token.to_f
            else color = token
            end
          end

          dash = DASH_PATTERNS[style]
          dasharray = dash ? %( stroke-dasharray="#{fmt(dash[0] * u)},#{fmt(dash[1] * u)}") : ''
          [thickness * u, dasharray, color]
        end

        # 白円＋濃色細枠＋番号。Unicode の ① ではなく <circle>+<text> で描くため
        # フォント依存がなく、任意の番号・色・サイズが効く（§5.4）。
        def badge(cx, cy, number, options, u)
          radius = BADGE_RADIUS * u
          font   = style_size(options['font-size'], BADGE_FONT_SIZE) * u
          %(<g><circle cx="#{fmt(cx)}" cy="#{fmt(cy)}" r="#{fmt(radius)}" fill="#{BADGE_FILL}" ) +
            %(stroke="#{BADGE_STROKE_COLOR}" stroke-width="#{fmt(BADGE_STROKE_WIDTH * u)}"/>) +
            text_element(number.to_s, cx, cy + (font * BASELINE_SHIFT), font,
                         options.fetch('color', BADGE_TEXT_COLOR), 'middle') +
            '</g>'
        end

        # ホームベース五角形（§7.6）。<polygon> だけを回転し、文字は本体中心へ水平に置く。
        def pointer_element(annotation, orig_w:, orig_h:, u:)
          tx, ty  = px_coords(annotation.coords, orig_w, orig_h)
          options = annotation.options
          dir     = POINTER_ROTATIONS.key?(options['dir']) ? options['dir'] : 'right'
          label   = options['label'].to_s
          font    = style_size(options['font-size'], POINTER_FONT_SIZE) * u

          height    = POINTER_BODY_HEIGHT * u
          head      = height / 2.0
          content_w = pointer_content_width(annotation.number, label, font, u)
          body      = [height * POINTER_MIN_BODY_RATIO, content_w + (POINTER_BODY_PADDING * u)].max

          bx, by = pointer_body_center(tx, ty, head, body, dir)
          pointer_polygon(tx, ty, head, body, height, dir, options) +
            pointer_content(bx, by, content_w, annotation, label, font, options, u)
        end

        # 本体内容の幅。CJK 全角 1 文字 = 1em の素朴見積り（HeadingImageComposer と同じ割り切り）。
        def pointer_content_width(number, label, font, u)
          badge_w = number ? 2 * POINTER_BADGE_RADIUS * u : 0.0
          gap     = (number && !label.empty?) ? POINTER_CONTENT_GAP * u : 0.0
          badge_w + gap + (display_width(label) * font)
        end

        # dir=right を基準形（先端 (tx,ty)・本体は左へ伸びる）とし、rotate で向きを作る。
        def pointer_polygon(tx, ty, head, body, height, dir, options)
          half = height / 2.0
          points = [[tx, ty], [tx - head, ty - half], [tx - head - body, ty - half],
                    [tx - head - body, ty + half], [tx - head, ty + half]]
          angle = POINTER_ROTATIONS.fetch(dir)
          transform = angle.zero? ? '' : %( transform="rotate(#{angle} #{fmt(tx)} #{fmt(ty)})")

          %(<polygon points="#{points.map { |px, py| "#{fmt(px)},#{fmt(py)}" }.join(' ')}" ) +
            %(fill="#{escape_attr(options.fetch('background', POINTER_BACKGROUND))}"#{transform}/>)
        end

        # 先端から dir の逆方向へ hd + bl/2 進んだ点（＝本体の中心）。
        def pointer_body_center(tx, ty, head, body, dir)
          offset = head + (body / 2.0)
          case dir
          when 'left' then [tx + offset, ty]
          when 'up'   then [tx, ty + offset]
          when 'down' then [tx, ty - offset]
          else [tx - offset, ty]
          end
        end

        # 本体内のレイアウト（番号のみ／ラベルのみ／両方の 3 態）。
        # 本体が縦向き（dir=up/down）でも文字は水平のまま本体中心に置く。
        def pointer_content(bx, by, content_w, annotation, label, font, options, u)
          color = options.fetch('color', POINTER_TEXT_COLOR)
          start = bx - (content_w / 2.0)
          parts = +''

          if annotation.number
            radius = POINTER_BADGE_RADIUS * u
            badge_font = style_size(options['font-size'], POINTER_BADGE_FONT_SIZE) * u
            parts << %(<circle cx="#{fmt(start + radius)}" cy="#{fmt(by)}" r="#{fmt(radius)}" fill="none" ) +
                     %(stroke="#{escape_attr(color)}" stroke-width="#{fmt(POINTER_BADGE_STROKE * u)}"/>)
            parts << text_element(annotation.number.to_s, start + radius,
                                  by + (badge_font * BASELINE_SHIFT), badge_font, color, 'middle')
            start += (2 * radius) + (POINTER_CONTENT_GAP * u)
          end

          parts << text_element(label, start, by + (font * BASELINE_SHIFT), font, color, 'start') unless label.empty?
          parts
        end

        def text_element(content, x, y, font, color, anchor)
          %(<text x="#{fmt(x)}" y="#{fmt(y)}" text-anchor="#{anchor}" font-family="sans-serif" ) +
            %(font-size="#{fmt(font)}" font-weight="700" fill="#{escape_attr(color)}">#{escape_text(content)}</text>)
        end

        # 元画像を原寸で敷く。旧リーダー互換のため xlink:href を用いる。
        def image_element(width, height, data_uri)
          %(<image xlink:href="#{data_uri}" x="0" y="0" width="#{width}" height="#{height}"/>)
        end

        # ルートに width/height（クロップ後実寸）を明示する——viewBox だけだと <img> で
        # 参照したときに固有アスペクト比を確定できないレンダラがあるため。
        def svg_wrapper(view_x, view_y, view_w, view_h, label, parts)
          %(<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" ) +
            %(viewBox="#{fmt(view_x)} #{fmt(view_y)} #{fmt(view_w)} #{fmt(view_h)}" ) +
            %(width="#{fmt(view_w)}" height="#{fmt(view_h)}" role="img" aria-label="#{escape_attr(label)}">) +
            parts.join +
            '</svg>'
        end

        # パーミル座標を元画像ピクセルへ戻す（X 系は幅・Y 系は高さ基準で交互に並ぶ）。
        def px_coords(coords, orig_w, orig_h)
          coords.each_with_index.map { |value, i| value / 1000.0 * (i.even? ? orig_w : orig_h) }
        end

        # スタイル寸法（正規化単位）。px 接尾辞は許容するが同じ意味（§5.3）。
        def style_size(value, fallback) = value.nil? ? fallback.to_f : value.to_f

        def display_width(str) = str.each_char.sum { it.ascii_only? ? 0.55 : 1.0 }

        # 丸数字（alt 用）。Unicode に無い番号は素朴な括弧表記へ落とす。
        def circled(number) = (1..20).cover?(number) ? [0x245F + number].pack('U') : "(#{number})"

        # 小数の見た目を整える（座標がすべて "190.0" 形式になるのを避ける）。
        def fmt(value)
          rounded = value.round(2)
          rounded == rounded.to_i ? rounded.to_i.to_s : rounded.to_s
        end

        def escape_text(str) = str.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
        def escape_attr(str) = escape_text(str).gsub('"', '&quot;')
      end
    end
  end
end
