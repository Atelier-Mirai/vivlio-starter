# frozen_string_literal: true

require 'pdf/reader'

require_relative 'marked_content_receiver'
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
      def initialize(reader)
        @reader = reader
        @objects = reader.objects
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

        total = receivers.sum(&:body_glyph_count)
        return 0.0 if total.zero?

        covered_glyph_count(root, false).fdiv(total)
      end

      def usable? = coverage >= COVERAGE_THRESHOLD

      # @param images [Array<StructureMarkdown::ImagePlacement>] Enhanced Mode で抜き出した画像
      # @return [String]
      def markdown(images: [])
        StructureMarkdown.new(root, images:, unmarked: receivers.map(&:unmarked_glyphs)).render
      end

      # 経路 B: 構造ツリーを使わず、紙面の文字の大きさ・位置・フォントから構造を推定する（§4）
      # @param text_area [Hash, nil] { top:, bottom:, inner:, outer: }（pt）。指定したときだけ版面の外を除く
      # @return [String]
      def layout_markdown(images: [], text_area: nil)
        StructureMarkdown.new(LayoutStructure.new(receivers, text_area:).root, images:).render
      end

      # ページごとに読み終えた受け手。OCR したページと合わせて経路 B に渡すときに使う
      # @return [Array<MarkedContentReceiver>]
      def page_scans = receivers

      # 文字の層のあるページの割合。スキャンしたページ（文字が 10 字に満たない）を除いて数える
      # @return [Float]
      def text_page_ratio
        return 0.0 if receivers.empty?

        receivers.count { it.page_glyphs.size >= 10 }.fdiv(receivers.size)
      end

      private

      def catalog = @objects.deref_hash(@objects.trailer[:Root]) || {}

      # ページごとに MCID の中身を集める。読めないページは空として扱い、ほかのページを活かす
      def receivers
        @receivers ||= @reader.pages.each_with_index.map do |page, index|
          receiver = MarkedContentReceiver.new(index)
          begin
            page.walk(receiver)
          rescue ::PDF::Reader::MalformedPDFError, ::PDF::Reader::UnsupportedFeatureError
            receiver.page = page
          end
          receiver
        end
      end

      def marked_contents
        @marked_contents ||= receivers.map(&:marked_contents)
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
