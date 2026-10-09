# frozen_string_literal: true

require "stringio"

require "test_helper"
require "vivlio_starter/cli/pdf/structure_reader"

module VivlioStarter
  module PDF
    # ToUnicode に無い字を書体の符号表で読む（pdf-read-structure-spec.md §2.3）。pLaTeX の英字の書体は ToUnicode に
    # 合字だけを書くので、Prawn では作れない形の PDF を直に書く
    class ToUnicodeFallbackTest < Minitest::Test
      # ToUnicode が合字の 1 字（0x1B → ff）しか持たなくても、ほかの字は符号表から読める。
      # 読まないと「Axum は Tokio の上に作られた」から英字の語が消える
      def test_should_read_codes_missing_from_to_unicode_through_the_encoding
        markdown = layout_markdown("(SCSS e\\033ect) Tj")

        assert_equal("SCSS effect\n", markdown)
      end

      private

      def layout_markdown(operator)
        content = "BT /F1 12 Tf 72 700 Td #{operator} ET"
        cmap = "begincmap\n1 begincodespacerange\n<00> <FF>\nendcodespacerange\n" \
               "1 beginbfchar\n<1B> <FB00>\nendbfchar\nendcmap"
        pdf = minimal_pdf(
          "<< /Type /Catalog /Pages 2 0 R >>",
          "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
          "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
          "<< /Length #{content.bytesize} >>\nstream\n#{content}\nendstream",
          "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding /ToUnicode 6 0 R >>",
          "<< /Length #{cmap.bytesize} >>\nstream\n#{cmap}\nendstream"
        )
        StructureReader.new(::PDF::Reader.new(StringIO.new(pdf))).layout_markdown
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
