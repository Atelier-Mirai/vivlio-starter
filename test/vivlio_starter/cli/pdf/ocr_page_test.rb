# frozen_string_literal: true

require "tmpdir"

require "test_helper"
require "vivlio_starter/cli/pdf/structure_reader"
require "vivlio_starter/cli/pdf/ocr_page"

module VivlioStarter
  module PDF
    # OCR の語を経路 B の文字にする OcrPage と、OCR の誤認識を直す OcrCorrections
    # （pdf-read-structure-spec.md §6）
    class OcrPageTest < Minitest::Test
      # 語の幅を字数で割って 1 字ずつにする。字の大きさは、行の枠の高さではなく和文の字の幅で見積もる
      def test_should_split_words_into_glyphs_sized_by_wide_characters
        page = OcrPage.new([word('言葉の', x: 100, width: 30, size: 14), word('少年', x: 130, width: 20, size: 14)],
                           page: 2, size: [595.0, 842.0])

        assert_equal(%w[言 葉 の 少 年], page.page_glyphs.map(&:text))
        assert_equal([100.0, 110.0, 120.0, 130.0, 140.0], page.page_glyphs.map(&:x))
        assert(page.page_glyphs.all? { it.size == 10.0 && it.page == 2 })
      end

      # 語の枠が重なっても、OCR が返した順を保つ（左から並べ直すと字が入れ替わる）
      def test_should_keep_ocr_order_when_word_boxes_overlap
        page = OcrPage.new([word('言葉', x: 100, width: 20), word('の遅い', x: 105, width: 30)], page: 0, size: [595.0, 842.0])

        assert_equal('言葉の遅い', page.page_glyphs.sort_by(&:x).map(&:text).join)
      end

      # 確信度の低い語（図や罫線の模様を字と読んだもの）は捨てる
      def test_should_drop_words_with_low_confidence
        page = OcrPage.new([word('本文', x: 100, width: 20), word('~|~', x: 130, width: 10, conf: 5)], page: 0, size: [595.0, 842.0])

        assert_equal('本文', page.page_glyphs.map(&:text).join)
      end

      # 補正表は、コードの囲みの外にだけかける
      def test_should_apply_corrections_outside_code_fences
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'ocr_corrections.yml')
          File.write(path, { 'rules' => [{ 'expected' => '人工知能', 'patterns' => ['入工知能'] }] }.to_yaml)
          markdown = "入工知能の話。\n\n```\nputs '入工知能'\n```\n\n入工知能で終わる。\n"

          corrected = OcrCorrections.apply(markdown, path:)

          assert_equal("人工知能の話。\n\n```\nputs '入工知能'\n```\n\n人工知能で終わる。\n", corrected)
        end
      end

      private

      def word(text, x:, width:, y: 700, size: 12, conf: 90)
        { 'text' => text, 'x' => x, 'y' => y, 'width' => width, 'size' => size, 'conf' => conf }
      end
    end
  end
end
