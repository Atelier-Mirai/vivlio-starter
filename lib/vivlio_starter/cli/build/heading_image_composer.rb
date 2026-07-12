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

module VivlioStarter
  module CLI
    module Build
      # 扉絵・節絵の合成 SVG を生成するモジュール
      module HeadingImageComposer
        # EPUB 用に埋め込む raster の最大長辺（印刷解像度は不要なので縮小して軽量化）。
        EMBED_MAX_EDGE = 1400

        # ラスタライズ後の出力幅（px）。viewBox 比からの縦は rsvg が自動算出する。
        RENDER_WIDTH = { frontispiece: 1000, ornament: 1400 }.freeze

        module_function

        # 飾り画像＋見出しを焼き込んだ **JPEG 画像（バイト列）** を生成する。
        # 合成 SVG を組み、rsvg-convert + magick でフラット JPEG にラスタライズする。
        # Kindle は SVG 内 base64 を非対応のため、配る実体はラスター画像にする。
        #
        # @param (see #compose)
        # @return [String, nil] JPEG バイト列。画像不読・ツール不在・失敗時は nil（→ simple 縮退）
        def render(image_path:, number:, title:, kind:, font_family:, number_color: '#333333')
          svg = compose(image_path:, number:, title:, kind:, font_family:, number_color:)
          return nil unless svg

          rasterize_to_jpeg(svg, RENDER_WIDTH.fetch(kind, 1000))
        end

        # 飾り画像＋見出しを焼き込んだ合成 SVG（中間表現）を生成する。
        #
        # @param image_path [String] 飾り画像の実ファイルパス（portrait/landscape webp 等）
        # @param number [String] 見出し番号（"第1章" / "1-1" 等。空可）
        # @param title [String] 見出しタイトル
        # @param kind [Symbol] :frontispiece（扉絵・縦）/ :ornament（節絵・横）
        # @param font_family [String] <text> 用フォントスタック（単一引用符で囲んだ名前の羅列）
        # @param number_color [String] 節絵の番号色（CSS 色。既定はダーク）
        # @return [String, nil] SVG 文字列。画像が読めない/寸法不明時は nil（→ simple 縮退）
        def compose(image_path:, number:, title:, kind:, font_family:, number_color: '#333333')
          return nil unless image_path && File.exist?(image_path)

          dims = image_dimensions(image_path)
          data_uri = raster_data_uri(image_path)
          return nil unless dims && data_uri

          width, height = dims
          case kind
          when :frontispiece then frontispiece_svg(width, height, data_uri, number.to_s.strip, title.to_s.strip, font_family)
          when :ornament     then ornament_svg(width, height, data_uri, number.to_s.strip, title.to_s.strip, font_family, number_color)
          end
        end

        # 扉絵（portrait）の合成 SVG。番号を上部に、タイトルを中央に縦並びで重ねる。
        # PDF の image-header.css（番号→下線→タイトル）の意図を SVG 座標で再現する。
        def frontispiece_svg(width, height, data_uri, number, title, font_family)
          number_size = (width * 0.052).round
          # 0.085 だと 1 行 9 字となり「拡張記法リファレンス」級（10 字）が不格好に
          # 折り返すため、11 字まで 1 行に収まる大きさに抑える（epub_h1 実測フィードバック）。
          title_size  = (width * 0.072).round
          halo        = [(title_size * 0.14).round, 1].max

          # --- Phase: タイトルを段組み（CJK 全角想定で 1 行字数を算出） ---
          per_line   = [(width * 0.80 / title_size).floor, 1].max
          lines      = wrap_text(title, per_line)
          line_step  = (title_size * 1.4).round

          # --- Phase: 縦位置（タイトル行ブロックをページ中央やや上に centering） ---
          number_y    = (height * 0.30).round
          underline_y = number_y + (number_size * 0.45).round
          title_mid   = height * 0.50
          first_y     = (title_mid - ((lines.size - 1) * line_step / 2.0) + title_size * 0.34).round

          parts = [image_element(width, height, data_uri)]
          parts << frontispiece_number(number, width, number_y, underline_y, number_size, font_family) unless number.empty?
          parts << frontispiece_title(lines, width, first_y, line_step, title_size, halo, font_family) unless lines.empty?

          svg_wrapper(width, height, [number, title], parts)
        end

        # 節絵の見出しフォント基準（height 比）。kindle_h2 実測フィードバックで確定した
        # 「程よい」大きさ（7-5 トラブルシューティング相当）。全節で共通に使う。
        ORNAMENT_FONT_RATIO = 0.14
        # 節絵タイトルの最大行数。これを超える長さのときだけフォントを縮小する。
        ORNAMENT_MAX_LINES = 2
        # 節絵テキストが使ってよい幅（画像幅比）。
        ORNAMENT_TEXT_WIDTH = 0.88

        # 節絵（landscape 2.39:1）の合成 SVG。番号＋タイトルを中央に重ねる。
        # フォントは全節共通の基準サイズに固定し、1 行に収まらない長い節題は
        # 縮小せず 2 行へ折り返す（2 行でも収まらない例外だけ縮小する）。
        # 旧実装の「幅いっぱいへの拡大＋clamp」は短い節題が巨大化し、その後の
        # 「固定基準＋収まるまで縮小」は長い節題が極端に小さくなった（実測 c/d/e）。
        def ornament_svg(width, height, data_uri, number, title, font_family, number_color)
          font_size, lines = ornament_layout(width, height, number, title)
          halo       = [(font_size * 0.14).round, 1].max
          line_step  = (font_size * 1.35).round
          # 単行時は旧来のベースライン（中央＋0.34em）。複数行は行ブロックごと中央へ寄せる。
          first_base = (height * 0.50 + font_size * 0.34 - (line_step * (lines.size - 1) / 2.0)).round

          texts = lines.each_with_index.map do |line, i|
            tspans = +''
            if line[:number] && !line[:number].empty?
              tspans << %(<tspan fill="#{escape_attr(number_color)}" font-weight="900">#{escape_text(line[:number])}</tspan>)
            end
            unless line[:text].empty?
              dx = tspans.empty? ? '' : %( dx="#{(font_size * 0.5).round}")
              tspans << %(<tspan#{dx}>#{escape_text(line[:text])}</tspan>)
            end
            %(<text x="#{(width / 2.0).round}" y="#{first_base + (line_step * i)}" text-anchor="middle" ) +
              %(font-family="#{font_family}" font-size="#{font_size}" font-weight="800" fill="#1a1a1a" ) +
              %(paint-order="stroke" stroke="#ffffff" stroke-width="#{halo}" stroke-linejoin="round">#{tspans}</text>)
          end

          segments = [number, title].reject(&:empty?)
          svg_wrapper(width, height, segments, [image_element(width, height, data_uri), *texts])
        end

        # 節絵のフォントサイズと行分割を決める。
        # 基準サイズで ORNAMENT_MAX_LINES 行以内に収まるまで（収まらなければ 8% ずつ）縮小する。
        # @return [Array(Integer, Array<Hash>)] [フォントサイズ, {number:, text:} の行配列]
        def ornament_layout(width, height, number, title)
          font_size = (height * ORNAMENT_FONT_RATIO).round
          floor     = (height * 0.09).round
          loop do
            capacity = ORNAMENT_TEXT_WIDTH * width / font_size
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
              return [acc.rstrip, rest.lstrip]
            end
            acc << ch
            used += w
          end
          [acc.rstrip, '']
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

        # SVG ルート要素で包む。aria-label に番号＋タイトルを入れて読み上げに資する。
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

        # テキストを 1 行あたり per_line 文字で折り返す（CJK 全角を 1 文字として数える素朴版）。
        def wrap_text(text, per_line)
          return [] if text.empty?

          text.chars.each_slice(per_line).map(&:join)
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
