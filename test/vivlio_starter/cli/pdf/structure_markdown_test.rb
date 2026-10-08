# frozen_string_literal: true

require "test_helper"
require "vivlio_starter/cli/pdf/structure_reader"

module VivlioStarter
  module PDF
    # 構造ツリーの要素の木を Markdown へ写す規則（pdf-read-structure-spec.md の経路 A）を、
    # 座標つきの文字を組み立てて確かめる。和文の PDF を Prawn で作るにはフォントが要るので、
    # PDF を通す確認は structure_reader_test.rb で英字だけで行う
    class StructureMarkdownTest < Minitest::Test
      Glyph = MarkedContentReceiver::Glyph
      MarkedContent = MarkedContentReceiver::MarkedContent
      ImageBox = MarkedContentReceiver::ImageBox
      Element = StructureReader::Element
      # コードの字の書体。書体の無い字は OCR の字として扱う（行番号を番号の欄の位置で外す）
      MONO = MarkedContentReceiver::FontInfo.new(name: 'HackGen-Regular', bold: false, mono: true)

      # 両端揃えで広がった字間や和欧間のアキは空白にせず、本物の空白（0.28 字）だけを空白にする
      def test_should_not_turn_justified_spacing_into_spaces
        justified = typeset([['1879', 0], ['年', 2.5], ['3', 2.5], ['月', 2.5], ['14', 2.5], ['日', 2.5], ['と', 2.5]], y: 700)
        spaced = typeset([['は', 0], ['Vivlio Starter', 2.8], ['の', 2.8], ['本', 0]], y: 680)

        markdown = render(element(:P, content(justified)), element(:P, content(spaced)))

        assert_equal("1879年3月14日と\n\nは Vivlio Starter の本\n", markdown)
      end

      # 段落の頭を 1 字下げる組み方では、次のページの頭が下がっていなければ前の段落の続きとみなす。
      # 下がっていれば、前が「」」で終わっていても新しい段落にする
      def test_should_join_paragraph_split_by_page_break_only_when_not_indented
        first = element(:P, content(typeset([['前のページの', 0]], x: 20, y: 100), typeset([['終わり。', 0]], x: 10, y: 80)))
        continued = element(:P, content(typeset([['続きです。', 0]], x: 10, y: 700, page: 1)))
        quoted = element(:P, content(typeset([['「問い」', 0]], x: 20, y: 680, page: 1), typeset([['です', 0]], x: 10, y: 660, page: 1)))
        fresh = element(:P, content(typeset([['新しい', 0]], x: 20, y: 700, page: 2), typeset([['段落。', 0]], x: 10, y: 680, page: 2)))

        markdown = render(first, continued, quoted, fresh)

        assert_equal("前のページの終わり。続きです。\n\n「問い」です\n\n新しい段落。\n", markdown)
      end

      # 小さく持ち上がった数字は、同じ番号の脚注の本文（小さな字で番号から始まる段落）があるときだけ
      # 参照にする。本文は次の見出しの手前に置く
      def test_should_link_raised_digits_to_footnote_body
        body = typeset([['本文です', 0]], y: 700)
        reference = Glyph.new(text: '1', x: body.last.right, y: 703, width: 4, size: 7, page: 0)
        note = typeset([['1.', 0], ['注の文。', 2]], y: 60, size: 8)

        markdown = render(element(:P, content(body + [reference])), content(note), element(:H2, content(typeset([['次の節', 0]], y: 650))))

        assert_equal("本文です[^1]\n\n[^1]: 注の文。\n\n## 次の節\n", markdown)
      end

      # 本文の見つからない持ち上がった数字（上付きの指数など）は、そのまま数字として残す
      def test_should_keep_raised_digit_as_text_without_footnote_body
        body = typeset([['面積はx', 0]], y: 700)
        exponent = Glyph.new(text: '2', x: body.last.right, y: 703, width: 4, size: 7, page: 0)

        assert_equal("面積はx2\n", render(element(:P, content(body + [exponent]))))
      end

      # 数字の直後に持ち上がった数字は指数（10²）で、同じ番号の脚注があっても参照にしない
      def test_should_not_take_exponent_after_digit_for_footnote_reference
        body = typeset([['基数は10', 0]], y: 700)
        exponent = Glyph.new(text: '2', x: body.last.right, y: 703, width: 4, size: 7, page: 0)
        word = typeset([['数', 0]], x: body.last.right + 4, y: 700)
        reference = Glyph.new(text: '2', x: word.last.right, y: 703, width: 4, size: 7, page: 0)
        note = typeset([['2.', 0], ['注の文。', 2]], y: 60, size: 8)

        markdown = render(element(:P, content(body + [exponent] + word + [reference])), content(note))

        assert_equal("基数は102数[^2]\n\n[^2]: 注の文。\n", markdown)
      end

      # 1 ずつ増える行番号は外し、1 以外から始まる抜粋は開始番号を #L で書き戻す。字下げは x 座標から戻す
      def test_should_strip_consecutive_line_numbers_and_keep_start_as_anchor
        code = element(:Code, content(
          monospace('28', x: 10, y: 700), monospace('# bend', x: 30, y: 700),
          monospace('29', x: 10, y: 688), monospace('x = 1', x: 30, y: 688),
          monospace('30', x: 10, y: 676), monospace('y = 2', x: 40, y: 676)
        ))
        figure = element(:Figure, element(:Caption, content(typeset([['lensing.rb', 0]], y: 712))), code)

        assert_equal("```ruby:lensing.rb#L28\n# bend\nx = 1\n  y = 2\n```\n", render(figure))
      end

      # 番号が飛ぶ行頭の数字はコードの一部かもしれないので外さない
      def test_should_keep_numbers_that_are_not_consecutive
        code = element(:Code, content(
          monospace('1 first', x: 10, y: 700), monospace('2 second', x: 10, y: 688), monospace('5 fifth', x: 10, y: 676)
        ))

        assert_equal("```\n1 first\n2 second\n5 fifth\n```\n", render(code))
      end

      # 折り返した行には番号が付かない。前の番号つきの行の続きとしてつなぐ
      def test_should_join_wrapped_code_line_to_previous_numbered_line
        code = element(:Code, content(
          monospace('1', x: 10, y: 700), monospace('puts "long', x: 30, y: 700),
          monospace('text"', x: 30, y: 688),
          monospace('2', x: 10, y: 676), monospace('end', x: 30, y: 676)
        ))

        assert_equal("```\nputs \"longtext\"\nend\n```\n", render(code))
      end

      # 行番号を構造ツリーから外した PDF（vs build は aria-hidden にする）では、コードの左の
      # タグの無い数字を行番号として拾い直す
      def test_should_recover_line_numbers_drawn_outside_the_tree
        code = element(:Code, content(monospace('a = 1', x: 30, y: 700), monospace('b = 2', x: 30, y: 688)))
        figure = element(:Figure, element(:Caption, content(typeset([['calc.rb', 0]], y: 712))), code)
        numbers = monospace('11', x: 10, y: 700) + monospace('12', x: 10, y: 688)

        assert_equal("```ruby:calc.rb#L11\na = 1\nb = 2\n```\n", render(figure, unmarked: [numbers]))
      end

      # ページで分かれた表は 1 つにつなぎ、次のページで繰り返された見出しの行を落とす
      def test_should_merge_table_split_across_pages
        header = -> (page) { element(:TR, element(:TH, cell('Name', page)), element(:TH, cell('Value', page))) }
        first = element(:Table, header.(0), element(:TR, element(:TD, cell('a', 0)), element(:TD, cell('1', 0))))
        second = element(:Table, header.(1), element(:TR, element(:TD, cell('b', 1)), element(:TD, cell('2|3', 1))))

        assert_equal(<<~MARKDOWN, render(first, element(:Aside, cell('42', 0)), second))
          | Name | Value |
          | --- | --- |
          | a | 1 |
          | b | 2\\|3 |
        MARKDOWN
      end

      # 図は Enhanced Mode で抜き出した画像と、描かれた位置の重なりで結ぶ。結べなければ代替テキストを残す
      def test_should_link_figure_to_extracted_image_by_position
        box = ImageBox.new(page: 0, left: 100, bottom: 400, right: 300, top: 600)
        figure = element(:Figure, MarkedContent.new(glyphs: [], images: [box]), alt: '挿絵')
        placement = StructureMarkdown::ImagePlacement.new(page: 0, left: 99, bottom: 401, right: 301, top: 599, path: 'page-001-image-01.webp')

        assert_equal("![挿絵](page-001-image-01.webp)\n", render(figure, images: [placement]))
        assert_equal("<!-- 画像: 挿絵 -->\n", render(figure))
      end

      # 番号のラベルは番号付きリストに、記号のラベルは箇条書きにする
      def test_should_write_numbered_and_bulleted_lists
        numbered = element(:L, item('1.', '光量子', 700), item('2.', 'ブラウン運動', 680))
        bulleted = element(:L, item('•', '相対性原理', 600))

        assert_equal("1. 光量子\n2. ブラウン運動\n\n間の段落\n\n- 相対性原理\n", render(numbered, element(:P, cell('間の段落', 0)), bulleted))
      end

      # ルビは {親文字|ルビ}。中に ``` を含む行内コードは、中に無い長さの `（ここでは 1 つ）で囲み、
      # 端が ` なので空白を挟む
      def test_should_write_ruby_and_inline_code_with_backticks
        ruby = element(:Ruby, content(typeset([['漢字', 0]], y: 700)), element(:RT, content(typeset([['かんじ', 0]], y: 712, size: 5))))
        code = element(:Code, content(typeset([['```ruby', 0]], x: 60, y: 700)))

        assert_equal("{漢字|かんじ}と ` ```ruby `\n", render(element(:P, ruby, content(typeset([['と', 0]], x: 30, y: 700)), code)))
      end

      # H1 が複数ある PDF では、最初の H1 だけを章題にし、ほかの見出しを 1 段下げる
      def test_should_shift_headings_when_pdf_has_several_h1
        headings = [%i[H1 章], %i[H1 節], %i[H2 項]].map { |type, text| element(type, cell(text.to_s, 0)) }

        assert_equal("# 章\n\n## 節\n\n### 項\n", render(*headings))
      end

      # 数式は Alt の TeX を書く。$$…$$ は別行立て、$…$ は段落の中に置く
      def test_should_write_math_from_alt_text
        inline = element(:Figure, alt: '$E=mc^2$')
        display = element(:Figure, alt: '$$ \nu_0 = \frac{\phi}{h} $$')

        markdown = render(element(:P, cell('式', 0), inline, cell('を使う', 0)), display)

        assert_equal("式$E=mc^2$を使う\n\n$$\n\\nu_0 = \\frac{\\phi}{h}\n$$\n", markdown)
      end

      private

      def render(*children, images: [], unmarked: [])
        StructureMarkdown.new(element(:Document, *children), images:, unmarked:).render
      end

      def element(type, *children, alt: nil) = Element.new(type:, children:, alt:, actual_text: nil)

      def content(*glyphs) = MarkedContent.new(glyphs: glyphs.flatten, images: [])

      def cell(text, page) = content(typeset([[text, 0]], y: 700, page:))

      def item(label, text, y)
        element(:LI, element(:Lbl, content(typeset([[label, 0]], y:))), content(typeset([[text, 0]], x: 30, y:)))
      end

      # 文字を左から並べる。各組の数値は、その組の手前に空ける幅（pt）。組の中の空白は文字を置かず、
      # 本物の空白の幅（0.28 字）だけ進める。和文は 1 字、欧文は半字の幅にする
      def typeset(segments, y:, x: 10.0, page: 0, size: 10.0)
        cursor = x
        segments.flat_map do |text, gap|
          cursor += gap
          text.each_char.filter_map do |char|
            next (cursor += size * 0.28) && nil if char == ' '

            width = char.match?(StructureMarkdown::WIDE_CHAR) ? size : size * 0.5
            Glyph.new(text: char, x: cursor, y:, width:, size:, page:).tap { cursor += width }
          end
        end
      end

      # 等幅の字（幅 5pt）。空白は 1 字ぶん進める
      def monospace(text, x:, y:, page: 0)
        text.each_char.with_index.filter_map do |char, index|
          Glyph.new(text: char, x: x + (index * 5.0), y:, width: 5.0, size: 9.0, page:, font: MONO) unless char == ' '
        end
      end
    end
  end
end
