# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/inline_span_transformer.rb
# ================================================================
# 責務:
#   行内の属性の記法 `[文字]{…}` を `<span …>文字</span>` に、蛍光ペン `==文字==` を
#   `<mark>文字</mark>` にする（inline-color-mark-spec.md。v2 の同じファイルを写し、
#   `color=`・`background=`・`==…==` を足したもの）。
#
# 受ける形:
#   - `{…}` の中は、クラス（`.red`）・字の色（`color=値`）・蛍光ペンの色（`background=値`）を
#     空白で区切って並べたもの。`#id` や知らないキー（`width=40%`）を含むものは読まない
#     （受ける範囲を広げるのは後からできるが、狭めると原稿の意味が変わる）。
#   - 色の値は CSS の色の名前・`#rgb`・`#rrggbb`・本のテーマ色の `theme`。ほかの値は色を付けない
#     （Guards::ContainerClassCheck が 🟡 で直し方を示す）。
#   - `[…]` の中は 1 段まで角かっこを入れ子にできる。`[[用語]]{.red}` は、索引語を赤にする。
#   - 画像（`![…]`）・インライン脚注（`^[…]`）・`\[` で始まるものは読まない。
#   - コードと数式の中は置き換えない（`$a==b==c$` を蛍光ペンにしない）。
#   - 行末の `{.text-right}`・`{.aki}`・`{.small}` などは、段落に付けるクラスの記法（1.x から）なので
#     読まない。`…[用語]{.aki}` は、1.x と同じく段落の下を空ける（PARAGRAPH_CLASSES）。
#   - 蛍光ペンは `==` の内側の両端が空白でないものだけ（`a == b` は読まない）。1 行の中で閉じるもの。
#
# 索引の `[用語]` は `]` の直後に `{.`・`{color=`・`{background=` が続くものを読まない
# （IndexMarkup の除外）。CSS に無いクラス・読めない値は Guards::ContainerClassCheck が 🟡 で示す。
# ================================================================

require 'cgi'
require_relative '../masking'
require_relative '../math_delimiters'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # `[文字]{.class color=… background=…}` を span（蛍光ペンなら mark）にし、`==文字==` を mark にする
      module InlineSpanTransformer
        CLASS_NAME = /[A-Za-z_][\w-]*/
        CLASS_TOKEN = /\.(#{CLASS_NAME})/

        # `{…}` に書けるキー。color は字の色、background は蛍光ペンの色
        KEYS = %w[color background].freeze

        # キーの値。空白と `{` `}` を含まない字の並び（読めるかどうかは normalize_color が決める）
        VALUE = /[^\s{}]+/

        # 変換する項目と、検査が拾う項目（知らないキーも拾い、🟡 で示す）
        ITEM = /\.#{CLASS_NAME}|(?:#{KEYS.join('|')})=#{VALUE}/
        LOOSE_ITEM = /\.#{CLASS_NAME}|[A-Za-z][\w-]*=#{VALUE}/

        # `[文字]{…}`。text は角かっこの中、attributes は `{` と `}` の間
        def self.span_pattern(item)
          /
            (?<![!^\\])
            \[(?<text>(?:[^\[\]\n]|\[[^\[\]\n]*\])+)\]
            \{(?<attributes>[ \t]*(?:#{item})(?:[ \t]+(?:#{item}))*[ \t]*)\}
          /x
        end

        # `==文字==` と、後ろに続けて書いた `{…}`。内側の両端は空白でも `=` でもない
        def self.mark_pattern(item)
          /
            (?<![=\\])==(?=[^\s=])
            (?<text>[^\n]*?[^\s=\\])
            ==(?!=)
            (?:\{(?<attributes>[ \t]*(?:#{item})(?:[ \t]+(?:#{item}))*[ \t]*)\})?
          /x
        end

        PATTERN = span_pattern(ITEM)
        LOOSE_PATTERN = span_pattern(LOOSE_ITEM)
        MARK_PATTERN = mark_pattern(ITEM)
        LOOSE_MARK_PATTERN = mark_pattern(LOOSE_ITEM)

        # 段落の末尾に書いて段落に付けるクラス（1.x からの記法）。寄せは前処理の
        # MarkdownPreprocessor#transform_text_right_inlines!、空き・小さい字・出典は後処理の
        # ReplacementRules::SPACING_CLASS_RULES・PARAGRAPH_CLASS_RULES が読む。`…[用語]{.aki}` の
        # `{.aki}` は段落のクラスなので、行内の属性として読まない
        PARAGRAPH_CLASSES = %w[right text-right text-center text-left aki aki2 small references].freeze
        PARAGRAPH_ATTRIBUTE = /\{\.(?:#{PARAGRAPH_CLASSES.join('|')})\}[ \t]*\z/

        # 本のテーマ色の名前（ThemeColor::PALETTE の 12 色と、book.yml の theme.color に従う theme）。
        # `{.red}` は字の色、蛍光ペンでは塗る色を表す（CSS は chapter-common.css の「文字の色と蛍光ペン」）
        THEME_COLOR_NAMES = %w[
          yellow orange red magenta purple indigo navy blue cyan teal green lime theme
        ].freeze

        # `color=`・`background=` に書ける CSS の色の名前（CSS Color Module Level 4 の 148 個）。
        # `transparent`・`currentcolor` は字の色にも蛍光ペンにも意味が無いので受けない
        CSS_COLOR_NAMES = %w[
          aliceblue antiquewhite aqua aquamarine azure beige bisque black blanchedalmond blue blueviolet
          brown burlywood cadetblue chartreuse chocolate coral cornflowerblue cornsilk crimson cyan
          darkblue darkcyan darkgoldenrod darkgray darkgreen darkgrey darkkhaki darkmagenta darkolivegreen
          darkorange darkorchid darkred darksalmon darkseagreen darkslateblue darkslategray darkslategrey
          darkturquoise darkviolet deeppink deepskyblue dimgray dimgrey dodgerblue firebrick floralwhite
          forestgreen fuchsia gainsboro ghostwhite gold goldenrod gray green greenyellow grey honeydew
          hotpink indianred indigo ivory khaki lavender lavenderblush lawngreen lemonchiffon lightblue
          lightcoral lightcyan lightgoldenrodyellow lightgray lightgreen lightgrey lightpink lightsalmon
          lightseagreen lightskyblue lightslategray lightslategrey lightsteelblue lightyellow lime
          limegreen linen magenta maroon mediumaquamarine mediumblue mediumorchid mediumpurple
          mediumseagreen mediumslateblue mediumspringgreen mediumturquoise mediumvioletred midnightblue
          mintcream mistyrose moccasin navajowhite navy oldlace olive olivedrab orange orangered orchid
          palegoldenrod palegreen paleturquoise palevioletred papayawhip peachpuff peru pink plum
          powderblue purple rebeccapurple red rosybrown royalblue saddlebrown salmon sandybrown seagreen
          seashell sienna silver skyblue slateblue slategray slategrey snow springgreen steelblue tan teal
          thistle tomato turquoise violet wheat white whitesmoke yellow yellowgreen
        ].to_set.freeze

        # 本のテーマ色を表す値（`color=theme`・`background=theme`）。CSS の色の名前に無いので取り違えない
        THEME_VALUE = 'theme'

        # 数式の退避の目印。NUL 区切りで、角かっこも `=` も含まない（どのパターンにも一致しない）
        MATH_PLACEHOLDER = /\u0000VSINLINEMATH(\d+)\u0000/

        # 行内の属性の 1 か所（蛍光ペンの `==…=={…}` も含む）。classes はクラス名の並び、
        # pairs は `[キー, 値]` の並び（書いた順）、attributes は `{` と `}` の間、source は原稿の字面
        Span = Data.define(:text, :classes, :source, :pairs, :attributes) do
          # `{…}` の中の項目 1 つを差し替えた原稿の字面（🟡 の「候補」に使う）
          def with_item(item, replacement)
            items = attributes.split(/[ \t]+/).reject(&:empty?)
            replaced = items.map { it == item ? replacement : it }.join(' ')
            source.delete_suffix("{#{attributes}}") + "{#{replaced}}"
          end
        end

        # 色の項目を読んだ結果。color・background は読めた値（小文字）か nil
        Attributes = Data.define(:classes, :color, :background)

        module_function

        # @param content [String] 章の Markdown
        # @return [String] 行内の属性を span・mark にした Markdown
        def transform(content)
          return content unless content.include?(']{') || content.include?('==')

          protected_text, code_spans = Masking.protect_code(content)
          protected_text, math_spans = protect_math(protected_text)
          converted = transform_marks(transform_spans(protected_text))
          Masking.restore_code(restore_math(converted, math_spans), code_spans)
        end

        # 原稿の 1 行（コードの外）の行内の属性を並べる。知らないキーを書いたものも拾う。
        # 原稿をそのまま読む検査（未知のクラス・読めない色）が使う
        # @param line [String]
        # @return [Array<Span>]
        def each_span(line)
          prose = Masking.strip_inline_code(line.chomp)
          spans = scan_spans(prose, LOOSE_PATTERN)
          marks = scan_spans(prose, LOOSE_MARK_PATTERN).reject { it.attributes.empty? }
          spans + marks
        end

        def classes_of(text) = text.scan(CLASS_TOKEN).flatten

        # `{…}` の中の `キー=値` を書いた順に並べる
        # @return [Array<Array(String, String)>]
        def pairs_of(text)
          text.split(/[ \t]+/).reject { it.empty? || it.start_with?('.') }.map { it.split('=', 2) }
        end

        # 色の値を読む。CSS の色の名前・`#rgb`・`#rrggbb`・`theme` を小文字にして返し、ほかは nil
        # @param value [String]
        # @return [String, nil]
        def normalize_color(value)
          color = value.to_s.downcase
          return color if color == THEME_VALUE || CSS_COLOR_NAMES.include?(color)

          color if color.match?(/\A#(?:\h{3}|\h{6})\z/)
        end

        # まだ受けない色の書き方（`rgb(r,g,b)`・`#rgba`・`#rrggbbaa`）を、受ける `#rrggbb` に直す。
        # 直せないもの（hsl() など）と、受ける値は nil。🟡 の「候補」に使う
        # @param value [String]
        # @return [String, nil]
        def hex_of_unsupported(value)
          case value.to_s.downcase
          when /\A#(\h{3})\h\z/ then "##{::Regexp.last_match(1).chars.map { it * 2 }.join}"
          when /\A#(\h{6})\h{2}\z/ then "##{::Regexp.last_match(1)}"
          when /\Argba?\((\d{1,3}),(\d{1,3}),(\d{1,3})(?:,[\d.]+%?)?\)\z/
            channels = [1, 2, 3].map { ::Regexp.last_match(it).to_i }
            format('#%02x%02x%02x', *channels) if channels.all? { it <= 255 }
          end
        end

        # `{…}` の中を読む。同じキーを 2 回書いたときは後ろの値で組む
        # @param text [String] `{` と `}` の間
        # @return [Attributes]
        def parse_attributes(text)
          values = pairs_of(text).to_h # 後ろの値が勝つ
          Attributes.new(classes: classes_of(text),
                         color: normalize_color(values['color']),
                         background: normalize_color(values['background']))
        end

        # 行末の、段落に付けるクラス（`…[用語]{.aki}` の `{.aki}`）か
        def paragraph_attribute?(match)
          match[0].match?(PARAGRAPH_ATTRIBUTE) && match.post_match[/\A[^\n]*/].strip.empty?
        end

        # --- 変換 -------------------------------------------------------------

        def transform_spans(text)
          text.gsub(PATTERN) do
            match = ::Regexp.last_match
            next match[0] if paragraph_attribute?(match)

            render(match[:text], parse_attributes(match[:attributes]), mark: false)
          end
        end

        # 行末の段落のクラス（`==大事==` に続く `{.aki}`）は段落のものなので、`{…}` を残して mark だけ作る
        def transform_marks(text)
          text.gsub(MARK_PATTERN) do
            match = ::Regexp.last_match
            attributes = match[:attributes]
            next render(match[:text], parse_attributes(''), mark: true) + "{#{attributes}}" if attributes && paragraph_attribute?(match)

            render(match[:text], parse_attributes(attributes.to_s), mark: true)
          end
        end

        # span か mark を組む（inline-color-mark-spec.md §3）。
        # `background=` があれば `[…]` でも mark にする（蛍光ペンの見た目は mark の規則だけが持つ）。
        # `[…]` のクラスは字の色の意味なので、mark にするときは中に span を置いてそこへ付ける
        # （mark に付いたクラスは「ペンの色」と読まれる。`==字=={.red}` と同じになってしまう）。
        def render(text, attrs, mark:)
          highlight = mark || !attrs.background.nil?
          return element('span', text, text_classes(attrs), text_styles(attrs)) unless highlight

          if !mark && !attrs.classes.empty?
            inner = element('span', text, text_classes(attrs), text_styles(attrs))
            return element('mark', inner, mark_classes(attrs), mark_styles(attrs))
          end

          element('mark', text, text_classes(attrs) + mark_classes(attrs), text_styles(attrs) + mark_styles(attrs))
        end

        # 字の色のクラスと style。`color=theme` は目印のクラス、ほかの値は style 属性で書く
        def text_classes(attrs)
          case attrs.color
          when nil then attrs.classes
          when THEME_VALUE then [*attrs.classes, 'vs-text-theme']
          else [*attrs.classes, 'vs-color']
          end
        end

        def text_styles(attrs) = attrs.color.nil? || attrs.color == THEME_VALUE ? [] : ["color: #{attrs.color}"]

        # 蛍光ペンの色。`background=theme` は `.theme`（テーマ色を淡くした色）、ほかの値はそのまま塗る
        def mark_classes(attrs) = attrs.background == THEME_VALUE ? ['theme'] : []

        def mark_styles(attrs)
          attrs.background.nil? || attrs.background == THEME_VALUE ? [] : ["--_mark-color: #{attrs.background}"]
        end

        def element(tag, text, classes, styles)
          attributes = +''
          attributes << %( class="#{CGI.escapeHTML(classes.join(' '))}") unless classes.empty?
          attributes << %( style="#{CGI.escapeHTML(styles.join('; '))}") unless styles.empty?
          "<#{tag}#{attributes}>#{text}</#{tag}>"
        end

        # --- 検査のための走査 -------------------------------------------------

        def scan_spans(prose, pattern)
          prose.to_enum(:scan, pattern).filter_map do
            match = ::Regexp.last_match
            attributes = match[:attributes].to_s
            next if !attributes.empty? && paragraph_attribute?(match)

            Span.new(text: match[:text], classes: classes_of(attributes), source: match[0],
                     pairs: pairs_of(attributes), attributes:)
          end
        end

        # --- 数式の退避 -------------------------------------------------------

        # 数式を目印へ退避する（IndexMarkup.protect_math と同じ区切り。IndexMarkup はこのファイルを
        # 読み込むので、読み込みの循環を避けてここに持つ）。改行は目印の後ろへ残し、行をずらさない
        def protect_math(text)
          spans = []
          protected_text = MathDelimiters::ALL.reduce(text) do |acc, pattern|
            acc.gsub(pattern) do |math|
              spans << math
              "\u0000VSINLINEMATH#{spans.size - 1}\u0000#{"\n" * math.count("\n")}"
            end
          end
          [protected_text, spans]
        end

        def restore_math(text, spans)
          return text if spans.empty?

          text.gsub(/#{MATH_PLACEHOLDER.source}(\n*)/o) do
            math = spans[::Regexp.last_match(1).to_i]
            math + ::Regexp.last_match(2)[math.count("\n")..].to_s
          end
        end
      end
    end
  end
end
