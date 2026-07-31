# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/heading_image_composer.rb
# ================================================================
# 責務:
#   扉絵（h1 frontispiece）・節絵（h2 ornament）を「飾り画像＋見出しを
#   1 枚に焼き込んだ合成 SVG」として生成する（EPUB 専用）。
#
# なぜ合成 SVG なのか（math-frontispiece-svg-spec.md §B-2）:
#   扉絵は PDF では @page 背景＋固定寸法で全面描画されるが、リフロー型 EPUB は
#   背景・固定寸法・position 重ね合わせのいずれも（特に Kindle で）不安定で
#   描画されない（③-a）。絵の上に見出しを重ねた状態を全リーダーで確実に出すには、
#   重ね合わせを SVG の中で完結させ単一画像として配置するのが現実解。
#
# 出力（重要・2026-06-15 改訂）:
#   合成結果は **平坦な JPEG ラスター画像**として出力する。Kindle は「SVG 内に base64
#   data URI で埋め込んだ画像」を非対応（変換時にブロッキングエラー）のため、SVG を
#   そのまま <img src=".svg"> で配るのではなく、ビルド時に SVG をラスタライズして JPEG 化
#   する。フラット JPEG は Kindle を含む全リーダーで確実に表示される。
#
# 合成の中間表現（SVG）:
#   レイアウト（画像＋見出し <text> の重ね）は SVG で宣言的に組み、rsvg-convert で
#   ラスタライズする（CJK 含め高品質）。SVG は中間生成物で EPUB には含めない。
#     <svg viewBox="0 0 W H">
#       <image xlink:href="data:image/jpeg;base64,…"/>  ← 飾り画像（rsvg がロード）
#       <text>第1章</text> <text>タイトル</text>         ← 見出しを <text> で重ねる
#   ・見出しはフォント非埋め込み（リーダー標準ではなくビルド機のフォントで焼き込む）。字形差は許容（§B-7）。
#
# 目次（nav）について:
#   EPUB の目次タイトルは各章 HTML の <title>（entries.epub.js）から生成され、h1 の
#   テキスト内容には依存しない。よって見出しを画像 <img> に置換しても目次は壊れない。
#   見出しテキストは <img alt> に格納し、読み上げ・検索・画像非表示時のフォールバックに資する。
#
# フォールバック（§B-5）:
#   画像が読めない／rsvg-convert・magick が無い／合成失敗時は nil を返し、呼び出し側
#   （EpubBuilder）が注入をスキップして通常の見出しテキスト（simple 相当）へ自然縮退する。
#
# 依存:
#   - ImageMagick（magick）: 飾り画像の寸法取得・JPEG 変換。
#   - librsvg（rsvg-convert）: 合成 SVG のラスタライズ。
#     いずれも未導入・失敗時は nil（→ simple 縮退）。vs doctor が任意ツールとして案内。
# ================================================================

require 'open3'
require_relative '../common'
require_relative '../heading_segmenter'

module VivlioStarter
  module CLI
    module Build
      # 扉絵・節絵の合成 SVG を生成するモジュール
      module HeadingImageComposer
        # EPUB 用に埋め込む raster の最大長辺（印刷解像度は不要なので縮小して軽量化）。
        EMBED_MAX_EDGE = 1400

        # ラスタライズ後の出力幅（px）。viewBox 比からの縦は rsvg が自動算出する。
        # 扉絵はリード文字を焼き込むため 1400 に引き上げる（Kindle 端末幅 1072px 以上での可読性）。
        RENDER_WIDTH = { frontispiece: 1400, ornament: 1400 }.freeze

        # 合成レイアウトの版数。座標・方式を変えたら +1 する（EpubBuilder が生成キャッシュのキーに混ぜる）。
        # v2: 上下分割（62% 帯＋裾飾り）を廃止し、リード文まで焼き込む縦長ファクシミリ 1 枚へ。
        # v3: 寸法を book.yml の文字数指定（heading_chars / lead_chars / ornament.heading_chars）から
        #     導き、節絵を左右並びのコンパクト帯へ（heading-metrics-spec §5-2・§5-3）。
        # v4: リード列の左寄せ（右下飾り回避）を廃し、左右中央へ。
        LAYOUT_VERSION = 4

        # 文字数指定の既定。theme.css の既定と BookSettingsCss::DEFAULT_*_CHARS に一致させる
        # （EpubBuilder が book.yml の値を渡すので、ここが使われるのは直接呼び出し時だけ）。
        DEFAULT_METRICS = { heading_chars: 8, lead_chars: 20, ornament_chars: 14,
                            heading_offset_ratio: 0.0 }.freeze

        # リード焼き込みの規格（画像 width / height 比・モック実証値）。
        # 基準フォントは lead_chars から導くため LEAD_FONT_RATIO は廃止した。
        # 下限は「合成画像を端末幅で見たときに読める大きさ」で決まる。字数指定が多いと
        # 字面がいくらでも小さくなるため、ここで止める（epub_h1.png 実測で 0.018 では
        # 読めなかった。Kindle 端末幅 1072px 換算でおよそ 8pt 相当を確保する）。
        LEAD_FONT_FLOOR   = 0.026  # 縮小の下限（画像幅比）
        LEAD_LINE_HEIGHT  = 1.70   # 行送り（フォントサイズ比）
        LEAD_BOTTOM_RATIO = 0.88   # リード最終行ベースラインの上限（height 比）。右下飾りとの干渉回避

        # 章番号のベースライン（height 比）。ここから章番号 → 章題 → リードを下へ積む。
        # PDF の章扉と同じく**ページ上部から**始める。中ほどから始めると、リードが長い章で
        # 下の飾りへ食い込む余地が無くなる（epub_h1_chapter6.png 実測）。
        FRONTISPIECE_TOP_RATIO = 0.17

        # 扉絵タイトルが使ってよい幅（画像幅比）。この幅を heading_chars で割って字面を決める。
        FRONTISPIECE_TITLE_WIDTH = 0.80
        # 字面サイズの安全域（画像幅比）。極端な字数指定でも番号・リードとの階層を壊さない。
        FRONTISPIECE_TITLE_SIZE_RANGE = (0.045..0.115)

        module_function

        # 飾り画像＋見出しを焼き込んだ **JPEG 画像（バイト列）** を生成する。
        # 合成 SVG を組み、rsvg-convert + magick でフラット JPEG にラスタライズする。
        # Kindle は SVG 内 base64 を非対応のため、配る実体はラスター画像にする。
        #
        # @param (see #compose)
        # @return [String, nil] JPEG バイト列。画像不読・ツール不在・失敗時は nil（→ simple 縮退）
        def render(image_path:, number:, title:, kind:, font_family:,
                   lead: '', lead_font_family: nil, lead_ratio: 0.60, number_color: '#333333',
                   metrics: DEFAULT_METRICS)
          svg = compose(image_path:, number:, title:, kind:, font_family:,
                        lead:, lead_font_family:, lead_ratio:, number_color:, metrics:)
          return nil unless svg

          rasterize_to_jpeg(svg, RENDER_WIDTH.fetch(kind, 1000))
        end

        # 飾り画像＋見出しを焼き込んだ合成 SVG（中間表現）を生成する。
        #
        # @param image_path [String] 飾り画像の実ファイルパス（portrait/landscape webp 等）
        # @param number [String] 見出し番号（"第1章" / "1-1" 等。空可）
        # @param title [String] 見出しタイトル
        # @param kind [Symbol] :frontispiece（扉絵・縦。リード込み）/ :ornament（節絵・横）
        # @param font_family [String] <text> 用フォントスタック（単一引用符で囲んだ名前の羅列）
        # @param lead [String] 章リード文（:frontispiece のみ。段落は "\n" 区切り。空可）
        # @param lead_font_family [String, nil] リード用フォント（nil なら font_family で代用）
        # @param lead_ratio [Float] リード焼き込み幅の画像幅比（判型 lead_width÷page.width 由来）
        # @param number_color [String] 節絵の番号色（CSS 色。既定はダーク）
        # @return [String, nil] SVG 文字列。画像が読めない/寸法不明時は nil（→ simple 縮退）
        # @param metrics [Hash] book.yml の文字数指定（heading_chars / lead_chars / ornament_chars）。
        #   PDF 側（BookSettingsCss）と同じ値を渡すことで、同じ原稿の扉・節絵が両ターゲットで
        #   同じ字数に組まれる（heading-metrics-spec §5-2）。
        def compose(image_path:, number:, title:, kind:, font_family:,
                    lead: '', lead_font_family: nil, lead_ratio: 0.60, number_color: '#333333',
                    metrics: DEFAULT_METRICS)
          return nil unless image_path && File.exist?(image_path)

          dims = image_dimensions(image_path)
          data_uri = raster_data_uri(image_path)
          return nil unless dims && data_uri

          m = DEFAULT_METRICS.merge(metrics || {})
          width, height = dims
          case kind
          when :frontispiece
            frontispiece_svg(width, height, data_uri, number.to_s.strip, title.to_s.strip,
                             lead.to_s, font_family, lead_font_family, lead_ratio, m)
          when :ornament
            ornament_svg(width, height, data_uri, number.to_s.strip, title.to_s.strip,
                         font_family, number_color, m[:ornament_chars])
          end
        end

        # 扉絵（portrait）全面の合成 SVG。PDF の縦長章扉（左上飾り→番号→タイトル→リード→
        # 右下飾り）を 1 枚に焼き込む。番号を上部・タイトルを中央・リードをその下へ縦に重ね、
        # 原画の下側（右下飾り）まで含めて全高で出す。リフローでも千切れない完全な章扉ページを
        # 実現するため、旧実装の上下分割（62% 帯＋裾飾り注入）は廃止した（facsimile 仕様）。
        def frontispiece_svg(width, height, data_uri, number, title, lead, font_family, lead_font_family,
                             lead_ratio, metrics)
          number_size = (width * 0.052).round
          # 字面は「タイトル領域の幅 ÷ heading_chars」で決める。以前は 0.072 固定
          # （= 1 行 11 字）というマジックナンバーで、PDF の箱幅とは無関係だった。
          title_size  = frontispiece_title_size(width, metrics[:heading_chars])
          halo        = [(title_size * 0.14).round, 1].max

          # --- Phase: タイトルを段組み（表示幅ベース・半角 0.55 換算） ---
          lines      = wrap_text_by_width(title, width * FRONTISPIECE_TITLE_WIDTH / title_size)
          line_step  = (title_size * 1.4).round

          # --- Phase: 縦位置 ---
          # 章番号と章題は同じ見出しなので近づけ、章題とリードの間を空ける（近接の原則）。
          # 全体の下げ量は book.yml の theme.frontispiece.heading_offset（判型比）で追い込める。
          # 章番号 → 章題 → リードを**上から順に積む**（PDF の章扉と同じ流れ）。
          # 以前は章題を height の一定比に centering していたため、長い章題（4 行）が
          # 上へ伸びて章番号と重なっていた（epub_h1_kasanari.png 実測）。
          # 積み上げ方式なら行数がいくつでも重ならず、下へ伸びるだけになる。
          offset      = height * metrics[:heading_offset_ratio].to_f
          number_y    = (height * FRONTISPIECE_TOP_RATIO + offset).round
          underline_y = number_y + (number_size * 0.45).round
          # 章番号と章題は同じ見出しの一部なので近づける（近接の原則）
          first_y     = (underline_y + (title_size * 1.05)).round
          title_last_y = first_y + ((lines.size - 1) * line_step)
          # 章題とリードの間は空ける
          lead_top     = title_last_y + (title_size * 1.30)

          parts = [image_element(width, height, data_uri)]
          parts << frontispiece_number(number, width, number_y, underline_y, number_size, font_family) unless number.empty?
          parts << frontispiece_title(lines, width, first_y, line_step, title_size, halo, font_family) unless lines.empty?
          unless lead.empty?
            parts << frontispiece_lead(lead, width, height, lead_font_family || font_family,
                                       lead_ratio, metrics[:lead_chars], lead_top)
          end

          svg_wrapper(width, height, [number, title, lead], parts)
        end

        # 扉絵タイトルの字面（px）。「タイトル領域の幅 ÷ 字数」を安全域に収める。
        def frontispiece_title_size(width, chars)
          chars = chars.to_i
          chars = DEFAULT_METRICS[:heading_chars] unless chars.positive?
          raw = (width * FRONTISPIECE_TITLE_WIDTH) / chars
          raw.clamp(width * FRONTISPIECE_TITLE_SIZE_RANGE.begin, width * FRONTISPIECE_TITLE_SIZE_RANGE.end).round
        end

        # リード段落の焼き込み。段落は "\n" 区切りで受け、各段落の先頭を全角 1 字下げする。
        # 基準フォントで LEAD_BOTTOM_RATIO に収まらない長文だけ 8% ずつ縮小する（下限 LEAD_FONT_FLOOR）。
        def frontispiece_lead(lead, width, height, font_family, lead_ratio, lead_chars, lead_top = nil)
          first_y   = (lead_top || (height * 0.62)).round
          font_size, lines = lead_layout(width, height, lead, lead_ratio, lead_chars, first_y)
          halo      = [(font_size * 0.14).round, 1].max
          step      = (font_size * LEAD_LINE_HEIGHT).round
          # リード列は左右中央に置く。以前は右下の飾りを避けて左寄せ（余白の 45%）にして
          # いたが、扉を上部起点へ改めた（FRONTISPIECE_TOP_RATIO）ことでリードが飾りの高さ
          # まで下りてこなくなり、避ける必要が無くなった。左寄せのままだと右に 3 字ぶんの
          # 余白が残り、PDF の章扉（margin-inline: auto で中央）と揃わない（epub_h1_justify.png）。
          left_x    = (width * (1.0 - lead_ratio) * 0.5).round

          tspans = lines.each_with_index.map do |line, i|
            %(<tspan x="#{left_x}" y="#{first_y + (i * step)}">#{escape_text(line)}</tspan>)
          end.join
          %(<text text-anchor="start" font-family="#{font_family}" font-size="#{font_size}" ) +
            %(font-weight="400" fill="#1a1a1a" paint-order="stroke" stroke="#ffffff" ) +
            %(stroke-width="#{halo}" stroke-linejoin="round">#{tspans}</text>)
        end

        # リードのフォントサイズと行分割。折返しは既存 wrap_text_by_width（半角 0.55 換算・
        # Latin 語は空白で折る——"--add-missing" 等の語中折れを防ぐ）を必ず使う。
        #
        # 基準の字面は「リード領域の幅 ÷ lead_chars」——リード幅比（lead_ratio）自体が
        # lead_chars × 1 字の送り ÷ 判型幅なので、これで PDF と同じ字面比になる。
        # 縦に収まらない長文だけ 8% ずつ縮める（幅は一定なので 1 行の字数が増えて行数が減る）。
        # @return [Array(Integer, Array<String>)] [フォントサイズ, 折り返し済み行の配列]
        def lead_layout(width, height, lead, lead_ratio, lead_chars, top_y = nil)
          paragraphs = lead.split("\n")
          chars = lead_chars.to_i
          chars = DEFAULT_METRICS[:lead_chars] unless chars.positive?
          top       = top_y || (height * 0.62)
          floor     = (width * LEAD_FONT_FLOOR).round
          font_size = [((width * lead_ratio) / chars).round, floor].max
          loop do
            capacity = (width * lead_ratio) / font_size
            lines = paragraphs.flat_map { |p| wrap_text_by_width("　#{p}", capacity) }
            bottom = top + ((lines.size - 1) * font_size * LEAD_LINE_HEIGHT)
            return [font_size, lines] if bottom <= height * LEAD_BOTTOM_RATIO || font_size <= floor

            font_size = [(font_size * 0.92).round, floor].max
          end
        end

        # 節絵タイトルの最大行数。これを超える長さのときだけフォントを縮小する。
        ORNAMENT_MAX_LINES = 2

        # --- コンパクト帯の規格（PDF の image-header.css と同じ比率・§5-3）---
        # 帯の縦横比。h2 の aspect-ratio: 480 / 100 に対応する。
        ORNAMENT_BAND_ASPECT = 4.8
        # 各層に敷く飾り画像の幅（帯幅比）。CSS の background-size: 150% × 半幅 と等価。
        ORNAMENT_LAYER_IMAGE_WIDTH = 0.75
        # 左右の飾り避け（帯幅比）。CSS の padding-inline 16mm / 18mm ÷ A4 版面 162mm。
        ORNAMENT_PAD_START = 16.0 / 162.0
        ORNAMENT_PAD_END   = 18.0 / 162.0
        # 節題が使ってよい幅（帯幅比）。この幅を字数で割って字面を決める。
        ORNAMENT_TEXT_WIDTH = 1.0 - ORNAMENT_PAD_START - ORNAMENT_PAD_END
        # 字面の下限（帯幅比）。長い節題でも本文と見分けが付く大きさを保つ。
        ORNAMENT_FONT_FLOOR = 0.030

        # 節絵の合成 SVG。飾りを左右に並べたコンパクト帯（PDF と同じ 4.8:1）へ、
        # 番号＋節題を左寄せで重ねる。字面は ornament.heading_chars から導く。
        # 元アセットは左上と右下に飾りを持つ 2.39:1 の 1 枚なので、clipPath で
        # 左半分／右半分を切り出して同じ行に置き直す（CSS の 2 層スプライトの SVG 版）。
        def ornament_svg(width, source_height, data_uri, number, title, font_family, number_color, chars)
          band_h = (width / ORNAMENT_BAND_ASPECT).round
          font_size, lines = ornament_layout(width, number, title, chars)
          halo       = [(font_size * 0.14).round, 1].max
          line_step  = (font_size * 1.35).round
          # 単行時は旧来のベースライン（中央＋0.34em）。複数行は行ブロックごと中央へ寄せる。
          first_base = (band_h * 0.50 + font_size * 0.34 - (line_step * (lines.size - 1) / 2.0)).round
          text_x     = (width * ORNAMENT_PAD_START).round

          # 2 行目以降は節番号のぶんだけ字下げして、番号の右で節題が上下に揃うようにする
          # （PDF の flex レイアウトと同じ見え方。揃えないと 2 行目が番号の下に潜り込む）。
          number_indent = ornament_number_indent(lines, font_size)

          texts = lines.each_with_index.map do |line, i|
            tspans = +''
            if line[:number] && !line[:number].empty?
              tspans << %(<tspan fill="#{escape_attr(number_color)}" font-weight="900">#{escape_text(line[:number])}</tspan>)
            end
            unless line[:text].empty?
              dx = tspans.empty? ? '' : %( dx="#{(font_size * 0.5).round}")
              tspans << %(<tspan#{dx}>#{escape_text(line[:text])}</tspan>)
            end
            x = i.zero? ? text_x : text_x + number_indent
            %(<text x="#{x}" y="#{first_base + (line_step * i)}" text-anchor="start" ) +
              %(font-family="#{font_family}" font-size="#{font_size}" font-weight="800" fill="#1a1a1a" ) +
              %(paint-order="stroke" stroke="#ffffff" stroke-width="#{halo}" stroke-linejoin="round">#{tspans}</text>)
          end

          segments = [number, title].reject(&:empty?)
          layers = ornament_layers(width, band_h, source_height, data_uri)
          svg_wrapper(width, band_h, segments, [*layers, *texts])
        end

        # 2 行目以降の字下げ量（px）。1 行目の節番号＋区切りアキと同じ幅。
        # 節番号は font-weight 900 の 1.0em 相当で組むため、表示幅換算で概算する。
        def ornament_number_indent(lines, font_size)
          number = lines.first&.dig(:number).to_s
          return 0 if number.empty?

          ((display_width(number) + 0.5) * font_size).round
        end

        # 飾りを左右に並べる 2 層。左は元画像の左上（＝左上の飾り）、右は右下（＝右下の飾り）を
        # 見せる。帯は飾り 1 つ分より少し高いので、左が上寄せ・右が下寄せになる差分が
        # そのまま右飾りの下がり量になる（CSS の left top / right bottom と同じ）。
        def ornament_layers(width, band_h, source_height, data_uri)
          img_w = (width * ORNAMENT_LAYER_IMAGE_WIDTH).round
          img_h = (img_w * source_height.to_f / width).round
          half  = (width / 2.0).round

          [
            %(<clipPath id="vs-orn-l"><rect x="0" y="0" width="#{half}" height="#{band_h}"/></clipPath>),
            %(<clipPath id="vs-orn-r"><rect x="#{half}" y="0" width="#{width - half}" height="#{band_h}"/></clipPath>),
            ornament_layer(data_uri, 0, 0, img_w, img_h, 'vs-orn-l'),
            ornament_layer(data_uri, width - img_w, band_h - img_h, img_w, img_h, 'vs-orn-r')
          ]
        end

        # 飾り 1 層。旧リーダー互換のため xlink:href を用いる（image_element と同じ理由）。
        # width/height は元画像の縦横比どおりに与えるので meet でも歪まない。
        def ornament_layer(data_uri, x, y, w, h, clip_id)
          %(<image xlink:href="#{data_uri}" x="#{x}" y="#{y}" width="#{w}" height="#{h}" ) +
            %(clip-path="url(##{clip_id})" preserveAspectRatio="xMidYMid meet"/>)
        end

        # 節絵のフォントサイズと行分割を決める。
        # 字面は「節題領域の幅 ÷ 字数」。ORNAMENT_MAX_LINES 行に収まらない長い節題だけ
        # 8% ずつ縮める（幅は一定なので 1 行の字数が増えて行数が減る）。
        # @return [Array(Integer, Array<Hash>)] [フォントサイズ, {number:, text:} の行配列]
        def ornament_layout(width, number, title, chars)
          count = chars.to_i
          count = DEFAULT_METRICS[:ornament_chars] unless count.positive?
          avail = width * ORNAMENT_TEXT_WIDTH
          floor = (width * ORNAMENT_FONT_FLOOR).round
          font_size = [(avail / count).round, floor].max
          loop do
            capacity = avail / font_size
            lines = wrap_ornament_lines(number, title, capacity)
            return [font_size, lines] if lines.size <= ORNAMENT_MAX_LINES || font_size <= floor

            font_size = [(font_size * 0.92).round, floor].max
          end
        end

        # 番号＋タイトルを表示幅ベースで行へ割り付ける。1 行目に番号（＋区切り 0.5em）を置き、
        # タイトルは収まる位置で折り返す。半角文字は全角の約半分として数える（display_width）。
        def wrap_ornament_lines(number, title, capacity)
          first_avail = capacity - (number.empty? ? 0 : display_width(number) + 0.5)
          lines = []
          rest = title
          loop do
            avail = lines.empty? ? [first_avail, 1.0].max : capacity
            head, rest = split_by_display_width(rest, avail)
            lines << { number: lines.empty? ? number : nil, text: head }
            break if rest.empty?
          end
          lines
        end

        # 表示幅（全角=1.0・半角=0.55）で先頭 chunk を切り出す。半角語の途中で切れる場合は、
        # 直近の空白があればそこで折り返す（Latin 語の分断を避ける）。
        # @return [Array(String, String)] [切り出した行, 残り]
        def split_by_display_width(text, avail)
          acc = +''
          used = 0.0
          text.each_char.with_index do |ch, i|
            w = char_display_width(ch)
            if used + w > avail && !acc.empty?
              rest = text[i..]
              # 半角語の途中なら、行内の最後の空白で折り返す
              if ch.match?(/[!-~]/) && acc[-1]&.match?(/[!-~]/) && (sp = acc.rindex(' '))
                rest = acc[(sp + 1)..] + rest
                acc = acc[0...sp]
              end
              return refine_break(acc, rest, avail)
            end
            acc << ch
            used += w
          end
          [acc.rstrip, '']
        end

        # 折返し位置の追い込み。表示幅だけで切ると読みにくい位置で割れるため、2 点だけ直す。
        #   1. 語の境界（空白）が行の後半にあるならそこで折る
        #      「Markdown 執筆チュ／ートリアル」→「Markdown／執筆チュートリアル」
        #   2. 残りが 1 文字だけになるなら 1 文字手前で折る（泣き別れ回避。PDF 側の
        #      WORD JOINER と同じ意図で、こちらは Ruby が行分割を持つため直接調整する）
        # @return [Array(String, String)] [確定した行, 残り]
        # 語の境界で折るかを決める閾値（行の使用率）。低すぎると 1 語だけの短い行が増え、
        # 高すぎると「Markdown 執筆チュー／トリアル」のような語中折れが残る（epub_h1.png 実測）。
        WORD_BREAK_MIN_FILL = 0.35

        # 行頭に来てはいけない文字（行頭禁則）。小書き仮名・長音・約物・閉じ括弧。
        NO_LINE_START = /\A[ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮヵヶーゝゞヽヾ々‐–—、。，．・：；？！゛゜）］｝」』〉》】〕〙〗”’]/
        # 行末に来てはいけない文字（行末禁則）。開き括弧。
        NO_LINE_END = /[（［｛「『〈《【〔〘〖“‘]\z/

        def refine_break(head, rest, avail)
          if (sp = head.rstrip.rindex(' ')) && display_width(head[0...sp]) >= avail * WORD_BREAK_MIN_FILL
            rest = head[(sp + 1)..].to_s + rest
            head = head[0...sp]
          elsif rest.strip.length == 1 && head.strip.length >= 2
            # 末尾 1 文字の泣き別れ回避（PDF 側の .vs-nobr と同じ意図）
            rest = head[-1] + rest
            head = head[0..-2]
          end

          # 禁則。1 文字ずつ次行へ送る（送りすぎないよう 2 回まで）。
          2.times do
            break unless head.strip.length >= 2 && (rest.match?(NO_LINE_START) || head.match?(NO_LINE_END))

            rest = head[-1] + rest
            head = head[0..-2]
          end

          # 半角語（英数字の連なり）の途中では折らない。空白を持たない語（ID・API 名など）は
          # 語の先頭まで戻す（「手動I／D・」のような分断を防ぐ。戻しすぎないよう 8 文字まで）。
          # 禁則の後に置くのは、禁則の送りが語を割ることがあるため（「・」は行頭禁則なので
          # 1 文字送られ、その 1 文字が ID の D だった、という並びが実際に起きる）。
          if head[-1]&.match?(/[0-9A-Za-z]/) && rest[0]&.match?(/[0-9A-Za-z]/)
            8.times do
              break unless head.strip.length >= 2 && head[-1]&.match?(/[0-9A-Za-z]/)

              rest = head[-1] + rest
              head = head[0..-2]
            end
          end

          [head.rstrip, rest.lstrip]
        end

        # 文字列の表示幅（全角=1.0・半角=0.55 の概算）。
        def display_width(str) = str.each_char.sum { char_display_width(it) }

        # 1 文字の表示幅。ASCII（半角）は約 0.55 全角相当として概算する。
        def char_display_width(char) = char.ascii_only? ? 0.55 : 1.0

        # 飾り画像を全面に敷く <image> 要素。
        # 旧リーダー互換のため xlink:href を用いる（href 単独だと描画しない端末がある）。
        def image_element(width, height, data_uri)
          %(<image xlink:href="#{data_uri}" x="0" y="0" width="#{width}" height="#{height}" ) +
            %(preserveAspectRatio="xMidYMid slice"/>)
        end

        # 扉絵の番号（中央寄せ＋下線）。
        def frontispiece_number(number, width, number_y, underline_y, size, font_family)
          cx = (width / 2.0).round
          line_w = (width * 0.30).round
          %(<text x="#{cx}" y="#{number_y}" text-anchor="middle" font-family="#{font_family}" ) +
            %(font-size="#{size}" font-weight="600" letter-spacing="#{(size * 0.2).round}" fill="#333333">#{escape_text(number)}</text>) +
            %(<line x1="#{cx - line_w}" y1="#{underline_y}" x2="#{cx + line_w}" y2="#{underline_y}" ) +
            %(stroke="#000000" stroke-opacity="0.35" stroke-width="#{[(size * 0.05).round, 1].max}" stroke-linecap="round"/>)
        end

        # 扉絵のタイトル（複数行・中央寄せ・白ハロー付き）。
        def frontispiece_title(lines, width, first_y, line_step, size, halo, font_family)
          cx = (width / 2.0).round
          tspans = lines.each_with_index.map do |line, i|
            y = first_y + i * line_step
            %(<tspan x="#{cx}" y="#{y}">#{escape_text(line)}</tspan>)
          end.join
          %(<text text-anchor="middle" font-family="#{font_family}" font-size="#{size}" font-weight="800" ) +
            %(fill="#111111" paint-order="stroke" stroke="#ffffff" stroke-width="#{halo}" stroke-linejoin="round">#{tspans}</text>)
        end

        # SVG ルート要素で包む。aria-label に番号＋タイトル（＋リード）を入れて読み上げに資する。
        # width/height 属性（intrinsic size）を明示する——viewBox だけだと <img> で参照した
        # ときに一部リーダーが縦横比を確定できず、レイアウト箱と描画サイズがずれて
        # 後続コンテンツへのはみ出し（epub_h2 実測）を誘発する。
        def svg_wrapper(width, height, label_segments, parts)
          aria = escape_attr(label_segments.reject(&:empty?).join(' '))
          %(<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" ) +
            %(width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}" ) +
            %(preserveAspectRatio="xMidYMid meet" role="img" aria-label="#{aria}">) +
            parts.join +
            '</svg>'
        end

        # テキストを表示幅（全角換算 capacity）で折り返す。半角は 0.55 換算で数え、
        # Latin 語の途中では直近の空白で折る（split_by_display_width と同じ規則）。
        # 語の境界が取れるなら語単位で詰める（PDF 側の .vs-nobr と同じ規則）。
        # 取れない環境では従来どおり表示幅で切り、禁則等は refine_break が追い込む。
        def wrap_text_by_width(text, capacity)
          return [] if text.empty?

          words = HeadingSegmenter.segment(text)
          words.size < 2 ? wrap_by_display_width(text, capacity) : pack_words(words, capacity)
        end

        def wrap_by_display_width(text, capacity)
          lines = []
          rest = text
          until rest.empty?
            head, rest = split_by_display_width(rest, capacity)
            lines << head
          end
          lines
        end

        # 語を順に詰め、入らなければ改行する。1 語で幅を超える語だけ表示幅で割る。
        def pack_words(words, capacity)
          lines = []
          current = +''
          words.each do |word|
            if current.empty? && display_width(word) > capacity
              wrap_by_display_width(word, capacity).each { lines << it }
              current = lines.pop.to_s
            elsif display_width(current + word) > capacity && !current.empty?
              lines << current.rstrip
              current = +word.dup
            else
              current << word
            end
          end
          lines << current.rstrip unless current.strip.empty?
          lines
        end

        # 合成 SVG をフラット JPEG（バイト列）へラスタライズする。
        # rsvg-convert で PNG 化 → magick で白フラット JPEG 化。ツール不在・失敗時は nil。
        def rasterize_to_jpeg(svg, width)
          return nil unless rsvg_available?

          png, s1 = Open3.capture2('rsvg-convert', '-w', width.to_s, '-f', 'png',
                                   stdin_data: svg, binmode: true)
          return nil unless s1.success? && !png.empty?

          jpg, s2 = Open3.capture2('magick', 'png:-', '-background', 'white', '-flatten',
                                   '-quality', '85', 'jpg:-', stdin_data: png, binmode: true)
          return nil unless s2.success? && !jpg.empty?

          jpg
        rescue StandardError
          nil
        end

        # rsvg-convert（librsvg）が使えるか。
        def rsvg_available?
          return @rsvg_available unless @rsvg_available.nil?

          @rsvg_available = system('rsvg-convert', '--version', out: File::NULL, err: File::NULL) || false
        end

        # 飾り画像の寸法を取得する（magick identify）。失敗時は nil。
        def image_dimensions(path)
          out, status = Open3.capture2('magick', 'identify', '-format', '%w %h', path)
          return nil unless status.success?

          tokens = out.split
          w = tokens[0].to_i
          h = tokens[1].to_i
          (w.positive? && h.positive?) ? [w, h] : nil
        rescue StandardError
          nil
        end

        # 飾り画像を縮小 JPEG へ変換し base64 data URI を返す（埋め込み用）。失敗時は nil。
        # webp 等の互換性懸念を避けるため JPEG に揃え、EMBED_MAX_EDGE まで縮小して軽量化する。
        # 透過部分は白でフラット化する（JPEG は透過非対応。黒潰れを防ぎ、リーダーの白ページや
        # PDF の白ページ表示と馴染ませる）。同一画像（章で共通）は使い回すためパスでメモ化する。
        def raster_data_uri(path)
          @data_uri_cache ||= {}
          return @data_uri_cache[path] if @data_uri_cache.key?(path)

          @data_uri_cache[path] = build_raster_data_uri(path)
        end

        def build_raster_data_uri(path)
          jpg, status = Open3.capture2(
            'magick', path, '-background', 'white', '-flatten',
            '-resize', "#{EMBED_MAX_EDGE}x#{EMBED_MAX_EDGE}>", '-quality', '80', 'jpg:-',
            binmode: true
          )
          return nil unless status.success? && !jpg.empty?

          # base64 は Ruby 3.4+ で default gem 外のため Array#pack('m0')（改行なし base64）で代替
          "data:image/jpeg;base64,#{[jpg].pack('m0')}"
        rescue StandardError
          nil
        end

        def escape_text(str) = str.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
        def escape_attr(str) = escape_text(str).gsub('"', '&quot;')
      end
    end
  end
end
