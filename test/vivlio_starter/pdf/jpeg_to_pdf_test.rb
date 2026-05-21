# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'vivlio_starter/pdf/jpeg_to_pdf'

module VivlioStarter
  module Pdf
    class JpegToPdfTest < Minitest::Test
      # img2pdfの依存排除に伴い、img2pdfコマンド実行チェックテストを削除し、
      # 独自実装 JpegToPdf.convert の画像からPDFへの完全な変換処理を
      # インメモリのダミーJPEGファイルを用いて検証する統合テストを追加しました。
      def test_should_convert_jpegs_to_pdf
        # ダミーJPEGデータのバイナリを構築（幅10, 高さ10, RGB 3ch）
        dummy_jpeg = [
          0xFF, 0xD8,                  # SOI (Start of Image)
          0xFF, 0xC0,                  # SOF0 (Start of Frame 0)
          0x00, 0x11,                  # Segment length (17 bytes)
          0x08,                        # Bits per component (8)
          0x00, 0x0A,                  # Height (10)
          0x00, 0x0A,                  # Width (10)
          0x03,                        # Number of components (3)
          0x01, 0x11, 0x00,            # Component 1
          0x02, 0x11, 0x00,            # Component 2
          0x03, 0x11, 0x00,            # Component 3
          0xFF, 0xD9                   # EOI (End of Image)
        ].pack('C*')

        Dir.mktmpdir do |dir|
          img1 = File.join(dir, 'page1.jpg')
          img2 = File.join(dir, 'page2.jpg')
          File.binwrite(img1, dummy_jpeg)
          File.binwrite(img2, dummy_jpeg)

          output_pdf = File.join(dir, 'output.pdf')

          # 変換実行
          JpegToPdf.convert([img1, img2], output_pdf)

          assert File.exist?(output_pdf)
          pdf_data = File.binread(output_pdf)

          # PDFの基本ヘッダーとフッターを検証
          assert_match(/\A%PDF-1.4/, pdf_data)
          assert_match(/%%EOF\n\z/, pdf_data)

          # 2つの画像が正しく埋め込まれ、サイズが指定されているか検証
          assert_includes pdf_data, '/Width 10 /Height 10'
          assert_includes pdf_data, '/ColorSpace /DeviceRGB /BitsPerComponent 8'
          assert_includes pdf_data, '/Filter /DCTDecode'
        end
      end

      def test_should_reject_empty_image_list
        error = assert_raises(JpegToPdf::Error) do
          JpegToPdf.convert([], 'book.pdf')
        end

        assert_includes error.message, '結合対象の画像がありません'
      end
    end
  end
end
