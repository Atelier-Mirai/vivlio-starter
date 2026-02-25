# frozen_string_literal: true

require 'test_helper'
require 'vivlio/starter/pdf/provider'
require 'vivlio/starter/pdf/standard_provider'

module Vivlio
  module Starter
    module Pdf
      class ProviderTest < Minitest::Test
        def setup
          # 標準状態（MITのみ）のプロバイダを取得
          @provider = Vivlio::Starter::Pdf::StandardProvider.new
          @fixtures_dir = File.expand_path('../../fixtures/pdf', __dir__)
          FileUtils.mkdir_p(@fixtures_dir)
        end

        def teardown
          FileUtils.rm_rf(@fixtures_dir)
        end

        def test_should_return_page_count_from_pdf
          # Arrange
          pdf_path = File.join(@fixtures_dir, 'sample.pdf')
          create_dummy_pdf(pdf_path, 3)

          # Act
          count = @provider.page_count(pdf_path)

          # Assert
          assert_equal 3, count
        end

        def test_should_return_nil_for_missing_file_when_getting_page_count
          # Act
          count = @provider.page_count('non_existent.pdf')

          # Assert
          assert_nil count
        end

        def test_should_create_blank_page_pdf_with_specified_dimensions
          # Arrange
          pdf_path = File.join(@fixtures_dir, 'blank.pdf')
          width_pt = 595.28 # A4 width
          height_pt = 841.89 # A4 height

          # Act
          result_path = @provider.ensure_blank_page_pdf(pdf_path, width_pt, height_pt)

          # Assert
          assert_equal pdf_path, result_path
          assert File.exist?(pdf_path)

          reader = PDF::Reader.new(pdf_path)
          assert_equal 1, reader.page_count
          
          # Prawn generates slightly different bbox depending on settings, but should be close
          bbox = reader.pages.first.attributes[:MediaBox]
          assert_in_delta width_pt, bbox[2], 0.1
          assert_in_delta height_pt, bbox[3], 0.1
        end

        def test_should_skip_outline_addition_in_standard_mode
          # Arrange
          pdf_path = File.join(@fixtures_dir, 'sample.pdf')
          create_dummy_pdf(pdf_path, 1)

          # Act & Assert
          logged_warnings = []
          Vivlio::Starter::CLI::Common.stub :log_warn, ->(msg) { logged_warnings << msg } do
            result = @provider.add_outline!(pdf_path, [], max_level: 3)
            refute result
          end

          assert logged_warnings.any? { |msg| msg.include?('PDF アウトライン（しおり）の付与は Standard モード(MIT) ではサポートされていません') },
                 'Standard モードではアウトライン付与スキップの警告を出すこと'
        end

        private

        # テスト用のダミーPDFをPrawnで生成
        def create_dummy_pdf(path, pages)
          require 'prawn'
          Prawn::Document.generate(path) do |pdf|
            (pages - 1).times { pdf.start_new_page }
            pdf.text 'Test PDF'
          end
        end
      end
    end
  end
end
