# frozen_string_literal: true

require "test_helper"
require "vivlio_starter/cli/pdf/structure_reader"

module VivlioStarter
  module PDF
    # タグの無い PDF の紙面から構造を推定する規則（pdf-read-structure-spec.md の経路 B）を、
    # 座標とフォントを持つ文字を組み立てて確かめる
    class LayoutStructureTest < Minitest::Test
      Glyph = MarkedContentReceiver::Glyph
      FontInfo = MarkedContentReceiver::FontInfo
      ImageBox = MarkedContentReceiver::ImageBox
      # 受け手（MarkedContentReceiver）のうち、経路 B が読むところだけを持つ
      Page = Data.define(:page_glyphs, :page_images, :page_dots, :page_size)

      BODY = FontInfo.new(name: 'Mincho-Regular', bold: false, mono: false)
      GOTHIC = FontInfo.new(name: 'Gothic-Bold', bold: true, mono: false)
      MONO = FontInfo.new(name: 'HackGen-Regular', bold: false, mono: true)

      # 本文と違う書体で大きい短い行は見出し。大きさの順に段階を振る。本文と同じ書体で少し大きいだけの
      # 行（本のカードの書名）と、4 行以上続く大きな字（章のリード）は段落にする
      def test_should_find_headings_by_size_and_typeface
        lines = [
          text('章の題', y: 780, size: 24, font: GOTHIC),
          text('大きな字のリードです', y: 740, size: 12), text('二行目のリードです', y: 720, size: 12),
          text('三行目のリードです', y: 700, size: 12), text('四行目で終わります。', y: 680, size: 12),
          text('節の題', y: 640, size: 14, font: GOTHIC),
          text('本の書名', y: 610, size: 13),
          *body_paragraph(y: 580), *body_paragraph(y: 540), *body_paragraph(y: 500)
        ]

        markdown = render([lines])

        assert_equal(<<~MARKDOWN, markdown)
          # 章の題

          大きな字のリードです二行目のリードです三行目のリードです四行目で終わります。

          ## 節の題

          本の書名

          本文の一行目は版面の右端まで届きます続きの行で終わります。

          本文の一行目は版面の右端まで届きます続きの行で終わります。

          本文の一行目は版面の右端まで届きます続きの行で終わります。
        MARKDOWN
      end

      # 柱とノンブルは、ページの上下の端で本文から離れ、同じ高さに何ページも出る行として落とす
      def test_should_drop_running_heads_and_page_numbers
        pages = (1..3).map do |number|
          [text('本の題名', y: 810, size: 7), *body_paragraph(y: 700, page: number - 1), text(number.to_s, y: 30, size: 7)]
        end

        markdown = render(pages)

        refute_includes(markdown, '本の題名')
        refute_match(/^\d$/, markdown)
        assert_equal(3, markdown.scan('本文の一行目').size)
      end

      # 1 字下げた行と、版面の右端より手前で止まった行の後で段落を切る
      def test_should_split_paragraphs_by_indent_and_short_line
        lines = [*body_paragraph(y: 700), *body_paragraph(y: 660, first: '次の段落の一行目も右端まで届きます')]

        assert_equal(<<~MARKDOWN, render([lines]))
          本文の一行目は版面の右端まで届きます続きの行で終わります。

          次の段落の一行目も右端まで届きます続きの行で終わります。
        MARKDOWN
      end

      # 番号の頭（1.）と、行の左に描かれた点（Chrome は • を図形で描く）でリストにする
      def test_should_find_numbered_and_dotted_lists
        lines = [text('1. 一つめ', y: 700), text('2. 二つめ', y: 683), text('点の項目', x: 70, y: 640)]
        dot = ImageBox.new(page: 0, left: 62, bottom: 642, right: 66, top: 646)

        assert_equal("1. 一つめ\n2. 二つめ\n- 点の項目\n", render([lines], dots: [[dot]]))
      end

      # 等幅の書体の行はコード。直前のファイル名だけの行はキャプションにし、字下げは x 座標から戻す
      def test_should_make_code_block_with_file_caption
        lines = [
          text('hello.rb', y: 720, font: GOTHIC),
          text('def hello', y: 705, size: 9, font: MONO),
          text('puts 1', x: 70, y: 692, size: 9, font: MONO),
          text('end', y: 679, size: 9, font: MONO)
        ]

        assert_equal("```ruby:hello.rb\ndef hello\n  puts 1\nend\n```\n", render([lines]))
      end

      # 列のあいだの縦の隙間が 3 行以上そろえば表に仮組みし、確かめるよう促すコメントを添える
      def test_should_infer_table_from_aligned_gaps
        rows = [%w[金属 仕事関数], %w[カリウム 2.2], %w[金 5.1]].each_with_index.flat_map do |(left, right), index|
          [text(left, y: 700 - (index * 18)), text(right, x: 200, y: 700 - (index * 18))]
        end

        assert_equal(<<~MARKDOWN, render([rows]))
          <!-- pdf:read: 列を推定して組んだ表です。列の対応を確かめてください -->

          | 金属 | 仕事関数 |
          | --- | --- |
          | カリウム | 2.2 |
          | 金 | 5.1 |
        MARKDOWN
      end

      # 分子と分母が詰まって並ぶ数式は、隙間がそろっても表にしない
      def test_should_not_take_fraction_lines_for_table
        lines = [%w[1 1], %w[x y], %w[2 3]].each_with_index.flat_map do |(left, right), index|
          [text(left, y: 700 - (index * 8)), text(right, x: 200, y: 700 - (index * 8))]
        end

        refute_includes(render([lines]), '列を推定')
      end

      # 本文の行のすぐ上の小さな仮名の行はルビにする
      def test_should_attach_ruby_to_base_characters
        lines = [text('かんじ', x: 60, y: 711, size: 5), text('漢字を読む', y: 700)]

        assert_equal("{漢字|かんじ}を読む\n", render([lines]))
      end

      # 擬似太字（同じ字を少しずらして 2 度描く）は 1 字にし、版面の外のつめは落とす
      def test_should_drop_overprinted_glyphs_and_margin_labels
        bold = text('2-2-2 節', y: 700, size: 14, font: GOTHIC)
        shifted = bold.map { it.with(x: it.x + 0.3) }
        pages = (0..1).map do |page|
          [*body_paragraph(y: 600, page:), text('つめ', x: 520, y: 583, page:)]
        end
        pages[0] = [*bold, *shifted, *pages[0]]

        markdown = render(pages)

        assert_includes(markdown, "# 2-2-2 節\n")
        refute_includes(markdown, 'つめ')
      end

      # 画像は描かれた高さで読む順に差し込み、画像の上に描かれた文字（図の注釈）は本文から除く
      def test_should_place_images_and_drop_labels_on_them
        image = ImageBox.new(page: 0, left: 100, bottom: 500, right: 300, top: 650)
        lines = [*body_paragraph(y: 700), text('注釈', x: 150, y: 600), *body_paragraph(y: 450)]

        markdown = render([lines], images: [[image]])

        assert_equal(2, markdown.scan('本文の一行目').size)
        assert_match(/終わります。\n\n<!-- 画像 -->\n\n本文の一行目/, markdown)
        refute_includes(markdown, '注釈')
      end

      private

      def render(pages, images: [], dots: [])
        scans = pages.each_with_index.map do |glyphs, index|
          Page.new(page_glyphs: glyphs.flatten.map { it.with(page: index) }, page_images: Array(images[index]),
                   page_dots: Array(dots[index]), page_size: [595.0, 842.0])
        end
        StructureMarkdown.new(LayoutStructure.new(scans).root).render
      end

      # 1 字下げた 1 行目が右端（約 470pt）まで届き、2 行目が手前で止まる段落
      def body_paragraph(y:, page: 0, first: '本文の一行目は版面の右端まで届きます')
        [text(first, x: 70, y:, page:, last_x: 470), text('続きの行で終わります。', y: y - 17, page:)]
      end

      # 文字を左から並べる。和文は 1 字、欧文は半字の幅、空白は 0.28 字ぶん進める。last_x を渡すと
      # 最後の字がそこで終わるよう字間を広げる（両端揃え）
      def text(string, y:, x: 60.0, size: 10.0, font: BODY, page: 0, last_x: nil)
        widths = string.each_char.map { it == ' ' ? size * 0.28 : (it.match?(StructureMarkdown::WIDE_CHAR) ? size : size * 0.5) }
        spacing = last_x ? (last_x - x - widths.sum) / [string.size - 1, 1].max : 0.0
        cursor = x
        string.each_char.zip(widths).filter_map do |char, width|
          glyph = Glyph.new(text: char, x: cursor, y:, width:, size:, page:, font:) unless char == ' '
          cursor += width + spacing
          glyph
        end
      end
    end
  end
end
