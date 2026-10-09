# frozen_string_literal: true

require "test_helper"
require "vivlio_starter/cli/pdf/structure_reader"

module VivlioStarter
  module PDF
    # 線で描いた図の範囲を、ページに描いた図形から見つける（pdf-read-structure-spec.md §4.11）
    class VectorFiguresTest < Minitest::Test
      Glyph = MarkedContentReceiver::Glyph
      Shape = MarkedContentReceiver::Shape
      FontInfo = MarkedContentReceiver::FontInfo
      BODY = FontInfo.new(name: 'Mincho-Regular', bold: false, mono: false)
      # 受け手（MarkedContentReceiver）のうち、図を探すのと経路 B が読むところだけを持つ
      Page = Data.define(:page_glyphs, :page_images, :page_dots, :page_size, :page_rules, :page_shapes)

      # トランジスタの図（円・端子の線・矢印）。近くの短いラベルを範囲に入れ、下のキャプションと本文は入れない
      def test_should_find_line_drawing_with_its_labels
        boxes = VectorFigures.find(page(transistor + text("S：ソース", x: 190, y: 640) + text("（a）", x: 195, y: 520) +
                                        text("図1：トランジスタ", x: 150, y: 495) + body_line(y: 470)))

        assert_equal(1, boxes.size)
        assert_operator(boxes.first.top, :>=, 650, "上のラベルが入る")
        assert_operator(boxes.first.bottom, :<=, 520, "下のラベルが入る")
        assert_operator(boxes.first.bottom, :>, 505, "キャプションは入らない")
      end

      # 図のすぐ上の本文の行は、式の周りの空きで短い切れ端に分かれても、ラベルとして範囲に入れない（入れると本文から消える）
      def test_should_not_take_body_line_next_to_figure_as_label
        line = text("本文の行は式を挟む", x: 60, y: 655) + text("直線と軸で囲まれた", x: 166, y: 655) + text("図形の面積を求める", x: 272, y: 655)
        boxes = VectorFigures.find(page(transistor + text("S：ソース", x: 190, y: 640) + line))

        assert_equal(1, boxes.size)
        assert_operator(boxes.first.top, :<, 655)
      end

      # 表の罫線（縦横の線だけ）は図にしない
      def test_should_not_take_table_rules_for_figure
        rules = (0..4).map { shape(100, 600 - (it * 20), 400, 600 - (it * 20)) } + [shape(100, 520, 100, 600), shape(250, 520, 250, 600)]

        assert_empty(VectorFigures.find(page(rules + text("項目", x: 110, y: 585) + text("説明", x: 260, y: 585))))
      end

      # 文を囲む角の丸い枠（コードの囲み・吹き出し）は図にしない
      def test_should_not_take_rounded_box_around_text_for_figure
        corners = [[100, 600], [390, 600], [100, 690], [390, 690]].map { |x, y| shape(x, y, x + 10, y + 10, curved: true) }
        edges = [shape(110, 600, 390, 600), shape(110, 700, 390, 700), shape(100, 610, 100, 690), shape(400, 610, 400, 690)]

        assert_empty(VectorFigures.find(page(corners + edges + body_line(y: 650))))
      end

      # 紙面の推定では、図の範囲の上のラベルを本文から除き、図を描かれた高さに置く
      def test_should_place_line_drawing_as_image_and_drop_its_labels
        glyphs = text("前の段落の文です。", x: 60, y: 700) + transistor + text("S：ソース", x: 190, y: 640) + text("後の段落の文です。", x: 60, y: 480)
        markdown = StructureMarkdown.new(LayoutStructure.new([page(glyphs)]).root).render

        assert_equal("前の段落の文です。\n\n<!-- 画像 -->\n\n後の段落の文です。\n", markdown)
      end

      private

      # 円（曲線）・3 本の端子の線・円の右の矢印（線と斜めの線の頭）
      def transistor
        [shape(160, 560, 220, 620, curved: true), shape(190, 620, 190, 640), shape(190, 530, 190, 560), shape(120, 590, 160, 590),
         shape(225, 590, 260, 590), shape(225, 585, 231, 595, diagonal: true, filled: true)]
      end

      def shape(left, bottom, right, top, curved: false, diagonal: false, filled: false)
        Shape.new(page: 0, left:, bottom:, right:, top:, curved:, diagonal:, filled:)
      end

      # 文字を左から並べる（和文は 1 字、欧文は半字の幅）
      def text(string, x:, y:, size: 10.0)
        cursor = x
        string.each_char.map do |char|
          width = char.match?(StructureMarkdown::WIDE_CHAR) ? size : size * 0.5
          Glyph.new(text: char, x: cursor, y:, width:, size:, page: 0, font: BODY).tap { cursor += width }
        end
      end

      def body_line(y:) = text("本文の行は版面の端から端まで届く長い文で、図のラベルとは違います。", x: 60, y:)

      def page(items)
        glyphs, shapes = items.partition { it.is_a?(Glyph) }
        Page.new(page_glyphs: glyphs, page_images: [], page_dots: [], page_size: [595.0, 842.0], page_rules: [], page_shapes: shapes)
      end
    end
  end
end
