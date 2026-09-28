# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/pdf/pdf_to_jpeg'

module VivlioStarter
  module Pdf
    class PdfToJpegTest < Minitest::Test
      FakeStatus = Data.define(:ok) do
        def success? = ok
      end

      # Open3.capture3 の代わり。4 ページ分の JPEG を置き、stderr を返す
      FakeRunner = Data.define(:calls, :output_dir, :stderr) do
        def initialize(calls:, output_dir:, stderr: '')
          super
        end

        def capture3(*command)
          calls << command
          FileUtils.touch(File.join(output_dir, 'page-1.jpg'))
          FileUtils.touch(File.join(output_dir, 'page-2.jpg'))
          FileUtils.touch(File.join(output_dir, 'page-3.jpg'))
          FileUtils.touch(File.join(output_dir, 'page-4.jpg'))
          ['', stderr, FakeStatus.new(ok: true)]
        end
      end

      def test_should_convert_pdf_to_jpeg_with_expected_command_and_normalized_names
        Dir.mktmpdir do |dir|
          output_dir = File.join(dir, 'book_images')
          runner = FakeRunner.new(calls: [], output_dir:)

          images = PdfToJpeg.convert('book.pdf', output_dir:, dpi: 600, quality: 90, command_runner: runner)

          assert_equal [
            ['pdftoppm', '-jpeg', '-jpegopt', 'quality=90', '-r', '600', 'book.pdf', File.join(output_dir, 'page')]
          ], runner.calls
          assert_equal %w[page-001.jpg page-002.jpg page-003.jpg page-004.jpg], images.map { File.basename(it) }
        end
      end

      def test_should_filter_requested_pages_and_keep_original_page_numbers
        Dir.mktmpdir do |dir|
          output_dir = File.join(dir, 'book_images')
          runner = FakeRunner.new(calls: [], output_dir:)

          images = PdfToJpeg.convert('book.pdf', output_dir:, pages: '1,3-4', command_runner: runner)

          assert_equal %w[page-001.jpg page-003.jpg page-004.jpg], images.map { File.basename(it) }
          assert_equal %w[page-001.jpg page-003.jpg page-004.jpg], Dir.children(output_dir).sort
        end
      end

      # リンク先の名前が長すぎるという poppler の警告は捨て、ほかの警告は表示する（改善案.md #44）
      def test_should_drop_name_token_warnings_and_keep_others
        Dir.mktmpdir do |dir|
          output_dir = File.join(dir, 'book_images')
          stderr = "Syntax Error (26805338): Warning: name token is longer than what the specification says it can be\n" * 3 +
                   "Syntax Error: Invalid page count\n"
          runner = FakeRunner.new(calls: [], output_dir:, stderr:)

          _out, err = capture_io { PdfToJpeg.convert('book.pdf', output_dir:, command_runner: runner) }

          assert_equal "Syntax Error: Invalid page count\n", err
        end
      end

      def test_should_parse_page_spec
        assert_equal [1, 3, 5, 6, 7, 8], PdfToJpeg.parse_page_spec('1,3,5-8')
      end

      def test_should_reject_invalid_page_spec
        error = assert_raises(PdfToJpeg::Error) do
          PdfToJpeg.parse_page_spec('3-1')
        end

        assert_includes error.message, 'ページ範囲が逆順です'
      end
    end
  end
end
