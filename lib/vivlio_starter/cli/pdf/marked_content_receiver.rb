# frozen_string_literal: true

require 'pdf/reader'
require_relative 'adobe_japan1_unicode'
require_relative 'to_unicode_fallback'
require_relative 'predefined_cmap'

module VivlioStarter
  module PDF
    # ページの描画命令を読みながら、マーク付き内容の番号（MCID）ごとに文字と画像の位置を集める。
    #
    # 構造ツリーの要素は本文を MCID で指すだけなので、文字そのものはページの側から拾う
    # （pdf-read-structure-spec.md §3.2）。文字を描く命令の前後で `runs` の数が増えた分を、
    # その時点で開いている MCID へ割り当てる。pdf-reader の内部の変数は読まない（論点 3）。
    #
    # タグの無い PDF の推定（経路 B・§4）に使えるよう、ページの文字と画像は MCID によらず
    # すべて取っておき、文字にはフォントの太字・等幅の別を持たせる。
    class MarkedContentReceiver < ::PDF::Reader::PageTextReceiver
      # 文字を描いたフォント。見出し（太字）とコード（等幅）の推定に使う
      FontInfo = Data.define(:name, :bold, :mono)

      # 1 文字。座標は pdf-reader の TextRun と同じ（左下が原点・単位は pt）
      # rotated は、字を回して描いたもの（版面の外のつめに縦に並べた「Chapter 1」など）
      Glyph = Data.define(:text, :x, :y, :width, :size, :page, :font, :rotated) do
        def initialize(text:, x:, y:, width:, size:, page:, font: nil, rotated: false) = super

        def right = x + width
        def bold? = font&.bold || false
        # 等幅の印（FixedPitch）は和文のフォント（MS 明朝など）にも付く。全角の字がそろう作りだからで、
        # コードの書体ではない。印だけで等幅とみなすのは英数字の字に限り、和文の字は名前が等幅の
        # フォント（HackGen など）のときだけ等幅とする
        def mono?
          return false unless font&.mono

          !text.match?(WIDE_TEXT) || font.name.match?(MONO_FONT_NAME)
        end
      end

      # 全角の字（和文・全角の記号）
      WIDE_TEXT = /[\p{Han}\p{Hiragana}\p{Katakana}\u3000-\u30FF\uFF00-\uFFEF]/

      # ToUnicode が漢字を康熙部首の字（⾏ U+2F8F など）に、英字の合字を「ﬀ」のような 1 字に当てる PDF がある
      # （`practicaltests-jp-3.pdf` など）。紙面の字としてはふつうの漢字・英字なので、NFKC で戻す（pdf-read-structure-spec.md §2.3）
      COMPATIBILITY_CHARS = /[\u2F00-\u2FD5\uFB00-\uFB06]/
      # TeX の等幅（CMTT・SFTT・ECTT）は、紙面ではまっすぐな「'」「`」を「quoteright」「quoteleft」の名前で持つので、
      # Unicode では「’」「‘」になる。コードの引用符なので、まっすぐな字に戻す（pdf-read-structure-spec.md §4.6）
      TEX_TYPEWRITER_FONT = /CMTT|SFTT|ECTT/
      # 字ではなく模様を描く書体。pLaTeX の ascmac は、網掛けの地を TeX-ascgrp の「A」を敷き詰めて、
      # 囲みの角を TeX-ascmac の字で描く。拾うとコードの字の間に「A」が挟まる（pdf-read-structure-spec.md §4.6）
      DECORATION_FONT_NAME = /\ATeX-asc(?:grp|mac)\z/

      # 名前で見分ける等幅と太字。フォントの記述子に印が無い PDF も多いので、名前でも見る。
      # TeX の等幅は CMTT（OT1）と、T1 符号の SFTT（cm-super）・ECTT（EC）。pLaTeX の本は SFTT が多い
      MONO_FONT_NAME = /Mono|Code|Console|Courier|Consol|Menlo|Monaco|Inconsolata|HackGen|Cica|Ricty|Typewriter|CMTT|SFTT|ECTT|SFMono/i
      BOLD_FONT_NAME = /Bold|Black|Heavy|Semibold|Demi|W[6-9]\b|CMBX/i
      # PDF のフォント記述子の印（FixedPitch は 1 ビット目、ForceBold は 19 ビット目）
      FIXED_PITCH_FLAG = 1
      FORCE_BOLD_FLAG = 1 << 18

      # ページに描かれた画像の外接矩形
      ImageBox = Data.define(:page, :left, :bottom, :right, :top)

      # 描いた図形の外接矩形。curved は曲線を、diagonal は斜めの線を含むもの。線で描いた図（回路図・矢印）を見つける手がかり
      Shape = Data.define(:page, :left, :bottom, :right, :top, :curved, :diagonal, :filled)

      # 1 つの MCID に属する文字と画像
      MarkedContent = Data.define(:glyphs, :images)

      # `runs` の絞り込みをすべて外す。受け取った文字の一覧がそのまま返るので、
      # 命令の前後の数の差が、その命令で描かれた文字になる
      ALL_RUNS = { rect: nil, skip_zero_width: false, skip_overlapping: false, merge: false }.freeze

      # @return [Array<Glyph>] どの MCID にも属さない文字。構造ツリーから外した行番号などがここに入る
      attr_reader :unmarked_glyphs

      # @return [Array<Glyph>] 描いた順のページの文字（Artifact の中の文字を除く）
      attr_reader :page_glyphs

      # @return [Array<ImageBox>] 描いた順のページの画像（Artifact の中の画像を除く）
      attr_reader :page_images

      # @return [Array(Float, Float)] ページの幅と高さ（pt）
      attr_reader :page_size

      # @return [Array<ImageBox>] 小さな塗りつぶしの図形。Chrome は箇条書きの点（•）を文字ではなく
      #   図形で描くので、行の左にあれば箇条書きの頭とみなす手がかりにする
      attr_reader :page_dots

      # @return [Array<ImageBox>] 細い横線（線引きと塗り）。TeX は論理式の否定（Ā）の上の線を線で描くので、
      #   紙面の推定（LayoutStructure）が線の下の字を $\overline{…}$ に戻す手がかりにする
      attr_reader :page_rules

      # @return [Array<Shape>] 描いた図形すべて（Artifact の中を除く）。線で描いた図の範囲を見つける手がかり
      attr_reader :page_shapes

      # 箇条書きの点とみなす図形の大きさ（pt）
      DOT_SIZE = (1.0..8.0)
      # 細い横線とみなす図形の高さの上限と幅の下限（pt）
      RULE_MAX_HEIGHT = 1.2
      RULE_MIN_WIDTH = 2.0
      # 1 本の線にまとめる、上下に接するサブパスの間（pt）。二重の否定の線は 2pt ほど離れる
      RULE_JOIN = 0.6

      # @param page_number [Integer] 0 から数えたページの番号。Glyph に持たせる
      def initialize(page_number)
        super()
        @page_number = page_number
      end

      def page=(page)
        super
        @glyphs_by_mcid = Hash.new { |hash, key| hash[key] = [] }
        @images_by_mcid = Hash.new { |hash, key| hash[key] = [] }
        @marks = []
        @unmarked_glyphs = []
        @page_glyphs = []
        @page_images = []
        @fonts = {}
        @size_scales = {}
        @page_size = [page.width, page.height]
        @page_dots = []
        @page_rules = []
        @page_shapes = []
        @path = []
        @subpath_starts = []
      end

      # --- 図形（箇条書きの点・細い横線・線で描いた図を見つけるために、描いた図形の外接矩形を取る） ---

      def append_rectangle(x, y, width, height)
        @subpath_starts << @path.size
        @path.push(device_point(x, y), device_point(x + width, y + height))
      end

      def begin_new_subpath(x, y)
        @subpath_starts << @path.size
        @path << device_point(x, y)
      end

      def append_line(x, y)
        point = device_point(x, y)
        previous = @path.last
        @path_diagonal = true if previous && (point.x - previous.x).abs > 0.5 && (point.y - previous.y).abs > 0.5
        @path << point
      end

      def append_curved_segment(*coordinates)
        @path_curved = true
        coordinates.each_slice(2) { @path << device_point(*it) }
      end

      alias append_curved_segment_initial_point_replicated append_curved_segment
      alias append_curved_segment_final_point_replicated append_curved_segment

      def fill_path_with_nonzero = record_dot
      def fill_path_with_even_odd = record_dot
      def fill_stroke = record_dot
      def fill_stroke_with_even_odd = record_dot
      def close_fill_stroke = record_dot
      def close_fill_stroke_with_even_odd = record_dot
      def stroke_path = record_rule
      def close_and_stroke_path = record_rule
      def end_path = clear_path

      # 本文として数える文字の数（Artifact の中の文字を除く）
      def body_glyph_count = @page_glyphs.size

      # @return [Hash{Integer => MarkedContent}]
      def marked_contents
        (@glyphs_by_mcid.keys | @images_by_mcid.keys).to_h do |mcid|
          [mcid, MarkedContent.new(glyphs: @glyphs_by_mcid[mcid], images: @images_by_mcid[mcid])]
        end
      end

      # pdf-reader 2.16 はここで ActualText（画像にした文字などに添える代わりの文字）を扱う。
      # super を呼ばずに上書きすると、その対応が壊れる
      def begin_marked_content_with_pl(tag, properties)
        super
        properties = @page.properties[properties] if properties.is_a?(Symbol)
        properties = @page.objects.deref_hash(properties) if properties.is_a?(::PDF::Reader::Reference)
        mcid = properties[:MCID] if properties.is_a?(Hash)
        @marks << [tag, mcid]
      end

      def begin_marked_content(tag)
        super if defined?(super)
        @marks << [tag, nil]
      end

      def end_marked_content
        super
        @marks.pop
      end

      # 「'」と「"」の命令は中で show_text を呼ぶので、包むのはこの 2 つだけでよい。
      # 両方を包むと、同じ文字を 2 度数える
      def show_text(string)
        record_new_glyphs { super }
      end

      def show_text_with_positioning(params)
        record_new_glyphs { super }
      end

      # 画像は MCID の中で描かれる。描いた位置を変換行列から求めて、Figure と画像を結ぶ手がかりにする
      def invoke_xobject(label)
        record_image(label)
        super
      end

      private

      def current_mcid = @marks.reverse_each.find { it[1] }&.last

      def inside_artifact? = @marks.any? { it[0] == :Artifact }

      def record_new_glyphs
        before = runs(ALL_RUNS).size
        yield
        font = font_info(@state.current_font)
        return if font&.name&.match?(DECORATION_FONT_NAME)

        rotated = rotated_text? || @state.current_font.vertical_writing?
        scale = size_scale(@state.current_font)

        added = runs(ALL_RUNS)[before..].map do |run|
          Glyph.new(text: glyph_text(run.text, font), x: run.x, y: run.y, width: run.width, size: run.font_size * scale, page: @page_number, font:,
                    rotated:)
        end
        return if added.empty?

        mcid = current_mcid
        @page_glyphs.concat(added) unless inside_artifact?
        mcid && !inside_artifact? ? @glyphs_by_mcid[mcid].concat(added) : @unmarked_glyphs.concat(added)
      end

      # 字の大きさに掛ける倍率。pdf-reader は字の大きさ（Tf）に書体の行列（FontMatrix）を入れない。dvips がビットマップで
      # 埋め込んだ TeX の Type 3 の書体は、字形をビットマップの単位で描いて Tf を 0.18 ほどにするので、字の大きさが 0.2pt に
      # なり、語の中のわずかな空き（「b」と「o」の 0.36pt）を空白とみなして「b orn」「Lab oratory」と読んでいた（heidelberg）。
      # Type 3 の書体に限り、小文字（無ければ数字）の幅の中央値を字の大きさの半分とみなして大きさを見積もる。見積もりが
      # Tf の 0.5〜2 倍に収まる書体（ふつうの作りの Type 3）は Tf のまま。小文字も数字も無い書体（記号 1 字）は、
      # このページで最後に見積もった倍率を使う
      def size_scale(font)
        return 1.0 unless font&.subtype == :Type3

        @size_scales[font.object_id] ||= begin
          widths = [('a'..'z'), ('0'..'9')].lazy.map do |chars|
            (0..255).filter_map { |code| font.glyph_width_in_text_space(code) if chars.cover?(font.to_utf8(code)) }.select(&:positive?)
          end.find(&:any?)
          estimate = widths && (median(widths) * 2)
          if estimate.nil? then @last_size_scale || 1.0
          elsif estimate.between?(0.5, 2.0) then 1.0
          else @last_size_scale = estimate
          end
        end
      end

      def median(values) = values.sort[values.size / 2]

      # 字の進む向きが横より縦に近いか。字を描く行列で、原点と 1 進んだ点を比べる。縦書きの書体の字は、
      # pdf-reader が横に進めて位置を出すので行列では分からず、書体の印（vertical_writing?）で見る
      def rotated_text?
        origin = @state.trm_transform_point(::PDF::Reader::Point.new(0, 0))
        step = @state.trm_transform_point(::PDF::Reader::Point.new(1, 0))
        (step.y - origin.y).abs > (step.x - origin.x).abs
      end

      def glyph_text(text, font)
        text = text.gsub(COMPATIBILITY_CHARS) { it.unicode_normalize(:nfkc) }
        font&.name&.match?(TEX_TYPEWRITER_FONT) ? text.tr("’‘", "'`") : text
      end

      def font_info(font)
        return nil unless font

        @fonts[font.object_id] ||= begin
          name = font.basefont.to_s.sub(/\A[A-Z]{6}\+/, '') # 埋め込みの部分集合の接頭辞（ABCDEF+）を外す
          descriptor = font.font_descriptor || font.descendantfonts&.first&.font_descriptor
          flags = descriptor&.font_flags.to_i
          FontInfo.new(
            name:,
            bold: name.match?(BOLD_FONT_NAME) || flags.anybits?(FORCE_BOLD_FLAG) || descriptor&.font_weight.to_i >= 600,
            mono: name.match?(MONO_FONT_NAME) || flags.anybits?(FIXED_PITCH_FLAG)
          )
        end
      end

      def device_point(x, y) = @state.ctm_transform_point(::PDF::Reader::Point.new(x, y))

      def record_dot
        unless @path.empty? || inside_artifact?
          xs = @path.map(&:x)
          ys = @path.map(&:y)
          if DOT_SIZE.cover?(xs.max - xs.min) && DOT_SIZE.cover?(ys.max - ys.min)
            @page_dots << ImageBox.new(page: @page_number, left: xs.min, bottom: ys.min, right: xs.max, top: ys.max)
          end
        end
        record_rule(filled: true)
      end

      # 描いた図形のうち、細い横線のサブパスを page_rules に足す。線引きは線の太さを見ず、通った点の外接矩形で
      # 見る。サブパスごとに見るのは、TeX が二重・三重の否定の線を 1 回の線引きにまとめて描くため（まとめた
      # 外接矩形は 2pt ほどの高さになり、細い横線から外れた）。両端がそろい上下に接するサブパスは 1 本にまとめる。
      # dvipdfmx は 1 本の線を、0.1pt ずつずらした 4 本の線で描く
      def record_rule(filled: false)
        unless @path.empty? || inside_artifact?
          record_shape(filled)
          rules = ([0] | @subpath_starts).sort.push(@path.size).each_cons(2).filter_map do |from, to|
            points = @path[from...to]
            next if points.empty?

            xs = points.map(&:x)
            ys = points.map(&:y)
            ImageBox.new(page: @page_number, left: xs.min, bottom: ys.min, right: xs.max, top: ys.max) if ys.max - ys.min <= RULE_MAX_HEIGHT
          end
          @page_rules.concat(merge_rules(rules).select { it.right - it.left >= RULE_MIN_WIDTH && it.top - it.bottom <= RULE_MAX_HEIGHT })
        end
        clear_path
      end

      def merge_rules(rules)
        rules.sort_by(&:bottom).each_with_object([]) do |rule, merged|
          index = merged.index do |other|
            (other.left - rule.left).abs < 0.5 && (other.right - rule.right).abs < 0.5 && rule.bottom - other.top <= RULE_JOIN
          end
          index ? merged[index] = merged[index].with(top: [merged[index].top, rule.top].max) : merged << rule
        end
      end

      def record_shape(filled)
        xs = @path.map(&:x)
        ys = @path.map(&:y)
        @page_shapes << Shape.new(page: @page_number, left: xs.min, bottom: ys.min, right: xs.max, top: ys.max,
                                  curved: @path_curved || false, diagonal: @path_diagonal || false, filled:)
      end

      def clear_path
        @path.clear
        @subpath_starts.clear
        @path_curved = false
        @path_diagonal = false
      end

      def record_image(label)
        xobject = @state.find_xobject(label)
        return unless xobject.is_a?(::PDF::Reader::Stream) && xobject.hash[:Subtype] == :Image

        corners = [[0, 0], [1, 0], [0, 1], [1, 1]].map do |x, y|
          @state.ctm_transform_point(::PDF::Reader::Point.new(x, y))
        end
        xs = corners.map(&:x)
        ys = corners.map(&:y)
        box = ImageBox.new(page: @page_number, left: xs.min, bottom: ys.min, right: xs.max, top: ys.max)
        @page_images << box unless inside_artifact?
        @images_by_mcid[current_mcid] << box if current_mcid
      end
    end
  end
end
