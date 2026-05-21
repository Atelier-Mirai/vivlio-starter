# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/pdf'

module VivlioStarter
  module CLI
    class PdfPagesRasterizeTest < Minitest::Test
      FakePdfToJpeg = Data.define(:calls) do
        def convert(pdf_path, output_dir:, dpi:, quality:, pages: nil)
          calls << { pdf_path:, output_dir:, dpi:, quality:, pages: }
          FileUtils.mkdir_p(output_dir)
          image = File.join(output_dir, 'page-001.jpg')
          FileUtils.touch(image)
          [image]
        end
      end

      FakeJpegToPdf = Data.define(:calls) do
        def convert(images, output_pdf)
          calls << { images:, output_pdf: }
          File.write(output_pdf, 'PDF', mode: 'wb')
        end
      end

      def test_should_export_selected_pdf_pages_to_default_directory
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            FileUtils.touch('book.pdf')
            fake_pdf_to_jpeg = FakePdfToJpeg.new(calls: [])
            exporter = PdfCommands::PdfPagesExporter.new(
              { dpi: 600, quality: 88, pages: '1,3', output: nil },
              'book.pdf',
              pdf_to_jpeg: fake_pdf_to_jpeg
            )

            result = nil
            capture_io do
              exporter.stub(:ensure_pdf_pages_tools!, nil) do
                result = exporter.call
              end
            end

            assert_pattern do
              fake_pdf_to_jpeg.calls.first => {
                pdf_path: 'book.pdf', output_dir: 'book_images', dpi: 600, quality: 88, pages: '1,3'
              }
            end
            assert_equal 'book_images', result[:output_dir]
            assert_equal ['book_images/page-001.jpg'], result[:images]
          end
        end
      end

      def test_should_rasterize_pdf_and_keep_intermediate_images_by_default
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            FileUtils.touch('book.pdf')
            fake_pdf_to_jpeg = FakePdfToJpeg.new(calls: [])
            fake_jpeg_to_pdf = FakeJpegToPdf.new(calls: [])
            rasterizer = PdfCommands::PdfRasterizer.new(
              { dpi: 350, quality: 95, clean: false },
              'book.pdf',
              pdf_to_jpeg: fake_pdf_to_jpeg,
              jpeg_to_pdf: fake_jpeg_to_pdf
            )

            result = nil
            capture_io do
              rasterizer.stub(:ensure_pdf_rasterize_tools!, nil) do
                result = rasterizer.call
              end
            end

            assert_pattern do
              fake_pdf_to_jpeg.calls.first => {
                pdf_path: 'book.pdf', output_dir: 'book_images', dpi: 350, quality: 95, pages: nil
              }
            end
            assert_equal [{ images: ['book_images/page-001.jpg'], output_pdf: 'book_rasterized.pdf' }], fake_jpeg_to_pdf.calls
            assert File.directory?('book_images')
            assert_equal 'book_rasterized.pdf', result[:output_pdf]
          end
        end
      end

      def test_should_rasterize_pdf_and_remove_intermediate_images_when_clean
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            FileUtils.touch('book.pdf')
            fake_pdf_to_jpeg = FakePdfToJpeg.new(calls: [])
            fake_jpeg_to_pdf = FakeJpegToPdf.new(calls: [])
            rasterizer = PdfCommands::PdfRasterizer.new(
              { dpi: 350, quality: 95, clean: true },
              'book.pdf',
              pdf_to_jpeg: fake_pdf_to_jpeg,
              jpeg_to_pdf: fake_jpeg_to_pdf
            )

            capture_io do
              rasterizer.stub(:ensure_pdf_rasterize_tools!, nil) do
                rasterizer.call
              end
            end

            refute File.directory?('book_images')
            assert File.exist?('book_rasterized.pdf')
          end
        end
      end
    end
  end
end
