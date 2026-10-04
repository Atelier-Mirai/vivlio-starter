# frozen_string_literal: true

require 'pdf/reader'

module VivlioStarter
  module PDF
    # ページの描画命令を読みながら、マーク付き内容の番号（MCID）ごとに文字と画像の位置を集める。
    #
    # 構造ツリーの要素は本文を MCID で指すだけなので、文字そのものはページの側から拾う
    # （pdf-read-structure-spec.md §3.2）。文字を描く命令の前後で `runs` の数が増えた分を、
    # その時点で開いている MCID へ割り当てる。pdf-reader の内部の変数は読まない（論点 3）。
    class MarkedContentReceiver < ::PDF::Reader::PageTextReceiver
      # 1 文字。座標は pdf-reader の TextRun と同じ（左下が原点・単位は pt）
      Glyph = Data.define(:text, :x, :y, :width, :size, :page) do
        def right = x + width
      end

      # ページに描かれた画像の外接矩形
      ImageBox = Data.define(:page, :left, :bottom, :right, :top)

      # 1 つの MCID に属する文字と画像
      MarkedContent = Data.define(:glyphs, :images)

      # `runs` の絞り込みをすべて外す。受け取った文字の一覧がそのまま返るので、
      # 命令の前後の数の差が、その命令で描かれた文字になる
      ALL_RUNS = { rect: nil, skip_zero_width: false, skip_overlapping: false, merge: false }.freeze

      # @return [Integer] 本文として数える文字の数（Artifact の中の文字を除く）
      attr_reader :body_glyph_count

      # @return [Array<Glyph>] どの MCID にも属さない文字。構造ツリーから外した行番号などがここに入る
      attr_reader :unmarked_glyphs

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
        @body_glyph_count = 0
        @unmarked_glyphs = []
      end

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
        record_image(label) if current_mcid
        super
      end

      private

      def current_mcid = @marks.reverse_each.find { it[1] }&.last

      def inside_artifact? = @marks.any? { it[0] == :Artifact }

      def record_new_glyphs
        before = runs(ALL_RUNS).size
        yield
        added = runs(ALL_RUNS)[before..].map do |run|
          Glyph.new(text: run.text, x: run.x, y: run.y, width: run.width, size: run.font_size, page: @page_number)
        end
        return if added.empty?

        mcid = current_mcid
        @body_glyph_count += added.size unless inside_artifact?
        mcid && !inside_artifact? ? @glyphs_by_mcid[mcid].concat(added) : @unmarked_glyphs.concat(added)
      end

      def record_image(label)
        xobject = @state.find_xobject(label)
        return unless xobject.is_a?(::PDF::Reader::Stream) && xobject.hash[:Subtype] == :Image

        corners = [[0, 0], [1, 0], [0, 1], [1, 1]].map do |x, y|
          @state.ctm_transform_point(::PDF::Reader::Point.new(x, y))
        end
        xs = corners.map(&:x)
        ys = corners.map(&:y)
        @images_by_mcid[current_mcid] << ImageBox.new(page: @page_number, left: xs.min, bottom: ys.min, right: xs.max, top: ys.max)
      end
    end
  end
end
