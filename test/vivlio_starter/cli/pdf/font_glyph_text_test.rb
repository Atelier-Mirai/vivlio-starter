# frozen_string_literal: true

require "stringio"

require "test_helper"
require "vivlio_starter/cli/pdf/structure_reader"

module VivlioStarter
  module PDF
    # pdf-reader が字を Unicode に戻せない書体と、TeX の書体の字の扱い（pdf-read-structure-spec.md §2.3）。
    # pLaTeX の PDF の書体は Prawn では作れない形なので、PDF を直に書く。字形は埋め込まない（字の読み取りには要らない）
    class FontGlyphTextTest < Minitest::Test
      # ToUnicode が合字の 1 字（0x1B → ff）しか持たなくても、ほかの字は符号表から読める。
      # 読まないと「Axum は Tokio の上に作られた」から英字の語が消える
      def test_should_read_codes_missing_from_to_unicode_through_the_encoding
        cmap = "begincmap\n1 begincodespacerange\n<00> <FF>\nendcodespacerange\n" \
               "1 beginbfchar\n<1B> <FB00>\nendbfchar\nendcmap"
        markdown = layout_markdown(
          "BT /F1 12 Tf 72 700 Td (SCSS e\\033ect) Tj ET",
          fonts: ["<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding /ToUnicode 6 0 R >>"],
          others: ["<< /Length #{cmap.bytesize} >>\nstream\n#{cmap}\nendstream"]
        )

        assert_equal("SCSS effect\n", markdown)
      end

      # Differences の接尾辞付きの名前（「zero.a」）は「zero」として読み、後ろの字の番号もずらさない。
      # pdf-reader のままでは 30 番に後ろの「space」が入り、行番号の「0」が空白に、31 番の空白が「▯」になった
      def test_should_read_differences_with_suffixed_glyph_names
        markdown = layout_markdown(
          "BT /F1 10 Tf 72 700 Td <1E321F7075626C6963> Tj ET",
          fonts: ["<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica " \
                  "/FirstChar 30 /LastChar 117 /Widths [#{Array.new(88, 600).join(' ')}] " \
                  "/Encoding << /BaseEncoding /WinAnsiEncoding /Differences [30 /zero.a /space] >> >>"]
        )

        assert_equal("02 public\n", markdown)
      end

      # 符号表も ToUnicode も持たない TeX の記号の書体（CMSY）の箇条書きの点（15 番）は「•」として読み、
      # 箇条書きになる。pdf-reader のままでは名前の分からない字「▯」になり、点と本文が表の 2 列に分かれた
      def test_should_read_bullets_of_tex_symbol_font
        items = %w[first second third].each_with_index.map do |word, index|
          y = 700 - (index * 14)
          "BT /F1 10 Tf 72 #{y} Td <0F> Tj ET BT /F2 10 Tf 84 #{y} Td (#{word} item) Tj ET"
        end
        markdown = layout_markdown(
          items.join(" "),
          fonts: ["<< /Type /Font /Subtype /Type1 /BaseFont /ABCDEF+CMSY10 >>",
                  "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"]
        )

        assert_equal("- first item\n- second item\n- third item\n", markdown)
      end

      # TeX の等幅（SFTT）は等幅として読み、まっすぐな引用符を「’」の名前で持つので「'」に戻す。
      # ascmac の網掛け（TeX-ascgrp の「A」を敷き詰めた地）は字として拾わない
      def test_should_read_tex_typewriter_and_skip_ascmac_shading
        lines = ["(require 'nkf') Tj", "(puts 'ok') Tj"].each_with_index.map do |code, index|
          y = 700 - (index * 12)
          "BT /F2 10 Tf 70 #{y} Td (AAAAAAAAAAAA) Tj ET BT /F1 9 Tf 72 #{y} Td #{code} ET"
        end
        markdown = layout_markdown(
          lines.join(" "),
          fonts: ["<< /Type /Font /Subtype /Type1 /BaseFont /ABCDEF+SFTT0900 >>",
                  "<< /Type /Font /Subtype /Type1 /BaseFont /ABCDEF+TeX-ascgrp >>"]
        )

        assert_equal("```\nrequire 'nkf'\nputs 'ok'\n```\n", markdown)
      end

      private

      # 書体を F1・F2…（5 番から）として持ち、その後ろに others（ToUnicode など）を置いた 1 ページの PDF を読む
      def layout_markdown(content, fonts:, others: [])
        resources = fonts.each_index.map { "/F#{it + 1} #{it + 5} 0 R" }.join(" ")
        pdf = minimal_pdf(
          "<< /Type /Catalog /Pages 2 0 R >>",
          "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
          "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << #{resources} >> >> /Contents 4 0 R >>",
          "<< /Length #{content.bytesize} >>\nstream\n#{content}\nendstream",
          *fonts, *others
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
