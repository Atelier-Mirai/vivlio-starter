# frozen_string_literal: true

require "stringio"

require "test_helper"
require "vivlio_starter/cli/pdf/structure_reader"

module VivlioStarter
  module PDF
    # ToUnicode を持たない日本語の書体の字を、Adobe-Japan1 の表で Unicode に戻す（pdf-read-structure-spec.md §2.3）。
    # Prawn は ToUnicode の無い書体を作れないので、PDF を直に書く。字形は埋め込まない（字の読み取りには要らない）
    class AdobeJapan1UnicodeTest < Minitest::Test
      # 「MOSFET」（比例幅の英字）・「一」・「あ」（比例幅の仮名）・「0」（表では異体字セレクタ付き）の CID
      CIDS = %w[002e 0030 0034 0027 0026 0035 0001 04b0 2ff4 00e6].freeze

      # 市販の PDF と同じく Identity-H で CID をそのまま字の番号にした書体は、表で字に戻る。
      # 戻さないと「.04'&5」「Ұ」のように、CID を Unicode とみなした字になる
      def test_should_decode_adobe_japan1_cids_without_to_unicode
        markdown = layout_markdown(ordering: 'Japan1')

        assert_equal("MOSFET 一あ0\n", markdown)
      end

      # Adobe-Japan1 を名乗らない書体（Ordering が Identity のものは CID が字形の番号）には表を当てない
      def test_should_leave_fonts_of_other_orderings_alone
        markdown = layout_markdown(ordering: 'Identity')

        refute_includes(markdown, 'MOSFET')
        refute_includes(markdown, '一')
      end

      # ToUnicode が漢字を康熙部首の字に、英字の合字を 1 字に当てる PDF は、
      # ふつうの漢字と英字に戻す。部首の「⾏」（U+2F8F）は見た目が同じでも検索や辞書に掛からない（CID 2022 は表でも「行」）
      def test_should_normalize_kangxi_radicals_and_ligatures_from_to_unicode
        to_unicode = { "07e6" => "2f8f", "0002" => "fb00" }
        markdown = layout_markdown(ordering: "Japan1", cids: %w[07e6 0002], to_unicode:)

        assert_equal("行ff\n", markdown)
      end

      # ToUnicode が表と違う字を康熙部首に当てるときは表で読む。IPSJ の論文は見出しの頭の「◼」（CID 12238）を「⿎」に
      # 当てていて、NFKC で戻すと「鼓」になった
      def test_should_prefer_table_when_to_unicode_maps_other_glyph_to_kangxi_radical
        markdown = layout_markdown(ordering: "Japan1", cids: %w[2fce 07e6], to_unicode: { "2fce" => "2fce", "07e6" => "884c" })

        assert_equal("◼行\n", markdown)
      end

      private

      def layout_markdown(ordering:, cids: CIDS, to_unicode: nil)
        content = "BT /F1 12 Tf 72 700 Td <#{cids.join}> Tj ET"
        pdf = minimal_pdf(
          "<< /Type /Catalog /Pages 2 0 R >>",
          "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
          "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
          "<< /Length #{content.bytesize} >>\nstream\n#{content}\nendstream",
          "<< /Type /Font /Subtype /Type0 /BaseFont /HiraMinPro-W3-Identity-H /Encoding /Identity-H /DescendantFonts [6 0 R]#{" /ToUnicode 8 0 R" if to_unicode} >>",
          "<< /Type /Font /Subtype /CIDFontType0 /BaseFont /HiraMinPro-W3 /DW 1000 /FontDescriptor 7 0 R " \
          "/CIDSystemInfo << /Registry (Adobe) /Ordering (#{ordering}) /Supplement 5 >> >>",
          "<< /Type /FontDescriptor /FontName /HiraMinPro-W3 /Flags 4 /FontBBox [0 -120 1000 880] /ItalicAngle 0 " \
          "/Ascent 880 /Descent -120 /CapHeight 700 /StemV 80 >>",
          *(to_unicode_cmap(to_unicode) if to_unicode)
        )
        StructureReader.new(::PDF::Reader.new(StringIO.new(pdf))).layout_markdown
      end

      def to_unicode_cmap(mapping)
        chars = mapping.map { |cid, code| "<#{cid}> <#{code}>" }.join("\n")
        cmap = "begincmap\n1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n" \
               "#{mapping.size} beginbfchar\n#{chars}\nendbfchar\nendcmap"
        "<< /Length #{cmap.bytesize} >>\nstream\n#{cmap}\nendstream"
      end

      # 番号 1 から順にオブジェクトを並べ、相互参照表を付ける
      def minimal_pdf(*objects)
        pdf = +"%PDF-1.7\n"
        offsets = objects.each_with_index.map do |object, index|
          pdf.bytesize.tap { pdf << "#{index + 1} 0 obj\n#{object}\nendobj\n" }
        end
        xref = pdf.bytesize
        pdf << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n"
        offsets.each { pdf << format("%010d 00000 n \n", it) }
        pdf << "trailer\n<< /Size #{objects.size + 1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"
      end
    end
  end
end
