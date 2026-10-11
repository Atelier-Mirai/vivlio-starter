# frozen_string_literal: true

require 'pdf/reader'

require_relative 'marked_content_receiver'
require_relative 'vector_figures'
require_relative 'structure_markdown'
require_relative 'layout_structure'

module VivlioStarter
  module PDF
    # タグ付き PDF の構造ツリーを読み、要素の木にする（pdf-read-structure-spec.md の経路 A）。
    #
    # 構造ツリーは PDF に必ずあるものではなく、あっても本文を覆っていないことがある
    # （InDesign の論文は表紙の 3 項目だけだった）。そこで「本文の文字のうち、意味のある要素に
    # 属する割合」を `coverage` で出し、呼び出し側が経路 A を使うかを決める（§3.4）。
    class StructureReader
      # 本文の文字のうち、この割合以上を意味のある要素が覆っていれば経路 A を使う（論点 5）
      COVERAGE_THRESHOLD = 0.9

      # 構造要素。type は RoleMap で標準の種類へ読み替えたもの
      Element = Data.define(:type, :children, :alt, :actual_text)

      # 意味を持たない入れ物。中身だけを辿る。ここにしか属さない文字は「覆われていない」と数える
      CONTAINER_TYPES = %i[Document DocumentFragment Part Art Sect Div NonStruct Private Span].freeze

      # PDF 1.7 と 2.0 の標準の構造型。RoleMap はここに着くまで辿る
      STANDARD_TYPES = %i[
        Document DocumentFragment Part Art Sect Div BlockQuote Caption TOC TOCI Index NonStruct Private
        P H H1 H2 H3 H4 H5 H6 L LI Lbl LBody Table TR TH TD THead TBody TFoot
        Span Quote Note Reference BibEntry Code Link Annot Ruby RB RT RP Warichu WT WP
        Figure Formula Form Aside Title FENote Sub Em Strong Artifact
      ].freeze

      # @param reader [PDF::Reader]
      # @param pages [Array<Integer>, nil] 読むページ（0 から数える）。省けば全ページ
      # @param output_pages [Array<Integer>, nil] 原稿に出すページ。pages のうち、ここに無いページは、紙面の推定（経路 B）が
      #   柱やノンブルを見分ける手がかりにだけ使う（vs pdf:read --pages。pdf-read-file-naming-spec.md §10.3）
      def initialize(reader, pages: nil, output_pages: nil)
        @reader = reader
        @objects = reader.objects
        @read_pages = pages&.to_set
        @output_pages = (output_pages || pages)&.to_set
      end

      # 構造ツリーが無ければ nil
      # @return [Element, nil]
      def root
        return @root if defined?(@root)

        tree = @objects.deref_hash(catalog[:StructTreeRoot])
        @root = tree && Element.new(type: :Document, children: children_of(tree[:K], nil, {}), alt: nil, actual_text: nil)
      end

      # 本文の文字のうち、意味のある要素（入れ物以外）に属する文字の割合
      # @return [Float]
      def coverage
        # 構造ツリーの無い PDF では、ページを読む前に返す（500 ページで 50 秒かかる）
        return 0.0 if root.nil?

        total = output_receivers.sum(&:body_glyph_count)
        return 0.0 if total.zero?

        covered_glyph_count(root, false).fdiv(total)
      end

      def usable? = coverage >= COVERAGE_THRESHOLD

      # @param images [Array<StructureMarkdown::ImagePlacement>] Enhanced Mode で抜き出した画像
      # @return [String]
      def markdown(images: [])
        unmarked = receivers.each_with_index.map { |receiver, index| output_page?(index) ? receiver.unmarked_glyphs : [] }
        StructureMarkdown.new(root, images:, unmarked:, read_pages: @output_pages&.to_a).render
      end

      # 経路 B: 構造ツリーを使わず、紙面の文字の大きさ・位置・フォントから構造を推定する（§4）
      # @param text_area [Hash, nil] { top:, bottom:, inner:, outer: }（pt）。指定したときだけ版面の外を除く
      # @return [String]
      def layout_markdown(images: [], text_area: nil)
        numbers = receivers.each_index.select { read_page?(it) }
        layout = LayoutStructure.new(receivers.values_at(*numbers), text_area:, page_numbers: numbers, output_pages: @output_pages&.to_a)
        StructureMarkdown.new(layout.root, images:, read_pages: @output_pages&.to_a).render
      end

      # 線で描いた図の範囲（ページごと・pdf-read-structure-spec.md §4.11）。Enhanced Mode で画像に描き出す
      # @return [Array<Array<MarkedContentReceiver::ImageBox>>]
      def vector_figures = receivers.each_with_index.map { |receiver, index| output_page?(index) ? VectorFigures.find(receiver) : [] }

      # ページごとに読み終えた受け手。OCR したページと合わせて経路 B に渡すときに使う
      # @return [Array<MarkedContentReceiver>]
      def page_scans = receivers

      # 文字の層のあるページの割合。スキャンしたページ（文字が 10 字に満たない）を除いて数える
      # @return [Float]
      def text_page_ratio
        return 0.0 if output_receivers.empty?

        output_receivers.count { it.page_glyphs.size >= 10 }.fdiv(output_receivers.size)
      end

      private

      def catalog = @objects.deref_hash(@objects.trailer[:Root]) || {}

      def read_page?(index) = @read_pages.nil? || @read_pages.include?(index)
      def output_page?(index) = @output_pages.nil? || @output_pages.include?(index)
      def output_receivers = receivers.each_with_index.filter_map { |receiver, index| receiver if output_page?(index) }

      # ページごとに MCID の中身を集める。読めないページは空として扱い、ほかのページを活かす。
      # 読まないページ（pages の外）も、添字をそろえるために空の受け手を置く
      def receivers
        @receivers ||= @reader.pages.each_with_index.map do |page, index|
          receiver = MarkedContentReceiver.new(index)
          next receiver.tap { it.page = page } unless read_page?(index)

          begin
            page.walk(receiver)
          rescue ::PDF::Reader::MalformedPDFError, ::PDF::Reader::UnsupportedFeatureError
            receiver.page = page
          end
          receiver
        end
      end

      def marked_contents
        @marked_contents ||= receivers.each_with_index.map { |receiver, index| output_page?(index) ? receiver.marked_contents : {} }
      end

      def page_index
        @page_index ||= @objects.page_references.each_with_index.to_h
      end

      def role_map
        @role_map ||= begin
          tree = @objects.deref_hash(catalog[:StructTreeRoot]) || {}
          @objects.deref_hash(tree[:RoleMap]) || {}
        end
      end

      # 子の並び（K）を要素と中身の配列にする。Chrome の PDF では子が配列で、
      # InDesign の PDF では参照のまま来るので、どちらも解決してから辿る（§2.2・§3.4）
      def children_of(kids, page, seen)
        kids = @objects.object(kids)
        case kids
        in Array then kids.flat_map { children_of(it, page, seen) }
        in Integer then [page && marked_contents.dig(page, kids)].compact
        in Hash then node_of(kids, page, seen)
        else []
        end
      end

      def node_of(dict, page, seen)
        return [] if seen.key?(dict.object_id)

        seen[dict.object_id] = true
        page = page_index.fetch(dict[:Pg], page) if dict[:Pg]

        case dict[:Type]
        in :MCR then [page && marked_contents.dig(page, @objects.object(dict[:MCID]))].compact
        in :OBJR then []
        else
          [Element.new(type: standard_type(dict[:S]), children: children_of(dict[:K], page, seen),
                       alt: decode(dict[:Alt]), actual_text: decode(dict[:ActualText]))]
        end
      end

      # InDesign などの独自の型名（Story・NormalParagraphStyle）を RoleMap で標準の型へ読み替える
      def standard_type(name)
        type = @objects.object(name)
        8.times do
          break if STANDARD_TYPES.include?(type)

          mapped = @objects.object(role_map[type])
          break unless mapped.is_a?(Symbol)

          type = mapped
        end
        type
      end

      # 構造ツリーの文字列は UTF-16BE（BOM つき）か PDFDocEncoding で入っている
      def decode(value)
        value = @objects.object(value)
        return nil unless value.is_a?(String)

        text = ::PDF::Reader::EncodingUtils.string_to_utf8(value).strip
        text.empty? ? nil : text
      end

      def covered_glyph_count(node, covered)
        case node
        in MarkedContentReceiver::MarkedContent then covered ? node.glyphs.size : 0
        in Element
          inner = covered || !CONTAINER_TYPES.include?(node.type)
          node.children.sum { covered_glyph_count(it, inner) }
        end
      end
    end
  end
end
