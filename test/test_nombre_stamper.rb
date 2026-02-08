# frozen_string_literal: true

require_relative 'test_helper'
require 'hexapdf'
require 'tmpdir'

# NombreStamper のテストに必要な最小限のモジュールをロード
# Common モジュールのログメソッドをスタブとして定義（単体テスト用）
module Vivlio
  module Starter
    module CLI
      module Common
        module_function

        def log_action(_msg) = nil
        def log_success(_msg) = nil
        def log_warn(_msg) = nil
        def log_error(_msg) = nil
        def log_info(_msg) = nil
        def log_debug(_msg) = nil
      end
    end
  end
end

require_relative '../lib/vivlio/starter/cli/build/nombre_stamper'

class TestNombreStamper < Minitest::Test
  NombreStamper = Vivlio::Starter::CLI::Build::NombreStamper

  # ================================================================
  # parse_bleed_mm: 塗り足し文字列のパース
  # ================================================================

  def test_should_parse_3mm_string
    assert_in_delta 3.0, NombreStamper.parse_bleed_mm('3mm')
  end

  def test_should_parse_5mm_string
    assert_in_delta 5.0, NombreStamper.parse_bleed_mm('5mm')
  end

  def test_should_parse_numeric_value
    assert_in_delta 4.0, NombreStamper.parse_bleed_mm(4)
  end

  def test_should_parse_float_value
    assert_in_delta 2.5, NombreStamper.parse_bleed_mm(2.5)
  end

  def test_should_return_default_for_nil
    assert_in_delta 3.0, NombreStamper.parse_bleed_mm(nil)
  end

  def test_should_return_default_for_empty_string
    assert_in_delta 3.0, NombreStamper.parse_bleed_mm('')
  end

  def test_should_return_default_for_zero_mm
    assert_in_delta 3.0, NombreStamper.parse_bleed_mm('0mm')
  end

  def test_should_handle_uppercase_MM
    assert_in_delta 3.0, NombreStamper.parse_bleed_mm('3MM')
  end

  def test_should_handle_string_with_spaces
    assert_in_delta 3.0, NombreStamper.parse_bleed_mm('  3mm  ')
  end

  # ================================================================
  # stamp!: PDF への隠しノンブル書き込み
  # ================================================================

  def test_should_stamp_nombre_on_all_pages
    Dir.mktmpdir do |dir|
      pdf_path = create_test_pdf(dir, page_count: 4)

      result = NombreStamper.stamp!(pdf_path, bleed_mm: 3)

      assert result, '書き込みが成功すること'
      assert File.exist?(pdf_path), 'PDF が存在すること'

      # 書き込み後もページ数が変わらないことを確認
      doc = HexaPDF::Document.open(pdf_path)
      assert_equal 4, doc.pages.count
    end
  end

  def test_should_return_false_for_missing_pdf
    result = NombreStamper.stamp!('/nonexistent/path.pdf', bleed_mm: 3)

    assert_equal false, result
  end

  def test_should_stamp_single_page_pdf
    Dir.mktmpdir do |dir|
      pdf_path = create_test_pdf(dir, page_count: 1)

      result = NombreStamper.stamp!(pdf_path, bleed_mm: 3)

      assert result
      doc = HexaPDF::Document.open(pdf_path)
      assert_equal 1, doc.pages.count
    end
  end

  def test_should_handle_large_bleed_value
    Dir.mktmpdir do |dir|
      pdf_path = create_test_pdf(dir, page_count: 2)

      # 大きな bleed でもエラーにならない
      result = NombreStamper.stamp!(pdf_path, bleed_mm: 10)

      assert result
    end
  end

  private

  # テスト用の空白 PDF を生成する
  # @param dir [String] 出力ディレクトリ
  # @param page_count [Integer] ページ数
  # @return [String] 生成した PDF のパス
  def create_test_pdf(dir, page_count: 4)
    path = File.join(dir, 'test.pdf')
    doc = HexaPDF::Document.new

    # B5 サイズ + 塗り足し 3mm（188mm x 263mm）
    w_pt = 188.0 * 72.0 / 25.4
    h_pt = 263.0 * 72.0 / 25.4

    page_count.times { doc.pages.add([0, 0, w_pt, h_pt]) }
    doc.write(path, optimize: true)
    path
  end
end
