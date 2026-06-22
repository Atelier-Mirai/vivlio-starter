# frozen_string_literal: true

require_relative '../../../test_helper'
# MIT 本体のテストは AGPL の HexaPDF に依存しない。PDF 生成は Prawn、検査は
# pdf-reader（いずれも gemspec のランタイム依存）で行う。
require 'prawn'
require 'pdf/reader'
require 'tmpdir'

require_relative '../../../../lib/vivlio_starter/cli/common'
require_relative '../../../../lib/vivlio_starter/cli/build/nombre_stamper'

class TestNombreStamper < Minitest::Test
  NombreStamper = VivlioStarter::CLI::Build::NombreStamper

  # テスト実行中のみ Common のログメソッドを無効化し、
  # teardown で必ず復旧する（他のテストファイルへの汚染防止）。
  LOG_METHODS_TO_SILENCE = %i[log_action log_success log_warn log_error log_info log_debug].freeze

  def setup
    common = VivlioStarter::CLI::Common
    @saved_log_methods = LOG_METHODS_TO_SILENCE.to_h do |name|
      [name, common.method(name)]
    end
    LOG_METHODS_TO_SILENCE.each do |name|
      common.define_singleton_method(name) { |_| }
    end
  end

  def teardown
    common = VivlioStarter::CLI::Common
    @saved_log_methods.each do |name, m|
      common.define_singleton_method(name, m)
    end
  end

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
      assert_equal 4, PDF::Reader.new(pdf_path).page_count
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
      assert_equal 1, PDF::Reader.new(pdf_path).page_count
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

  # FT-02: ノンブルが埋め込み可能フォント（同梱 HackGen35ConsoleNF）で描画され、
  # 非埋め込みの標準 14 フォント（Helvetica）が PDF に残らない（入稿事故防止）。
  # 本リポジトリの StandardProvider（MIT）を直接検証する。実運用で拡張プラグイン
  # （vivlio-starter-pdf / EnhancedProvider）が入っていても、その埋め込みは
  # 当該 gem 側のテストで担保するため、ここではプロバイダ選択に依存させない。
  def test_should_embed_nombre_font_instead_of_helvetica
    require "vivlio_starter/cli/pdf/standard_provider"

    Dir.mktmpdir do |dir|
      pdf_path = create_test_pdf(dir, page_count: 2)

      VivlioStarter::Pdf::StandardProvider.new.stamp_nombre!(pdf_path, bleed_pt: 8.5)

      summary = nombre_font_summary(pdf_path)
      assert summary[:embedded_truetype],
             "ノンブルフォントが TrueType としてサブセット埋め込みされていること（FontFile2）"
      assert(summary[:base_fonts].any? { it.include?("HackGen") },
             "ノンブルが HackGen35ConsoleNF で描画されていること: #{summary[:base_fonts]}")
      refute(summary[:base_fonts].any? { it.include?("Helvetica") },
             "非埋め込み Helvetica が使われていないこと（FT-02 回帰）: #{summary[:base_fonts]}")
    end
  end

  private

  # PDF 内の全オブジェクトを走査し、BaseFont 名の一覧と TrueType 埋め込み
  # （FontFile2）の有無を集計する。object stream / Flate 圧縮に左右されないよう
  # pdf-reader のオブジェクトグラフ（object stream 解決済み）を直接読む。
  def nombre_font_summary(pdf_path)
    objects = PDF::Reader.new(pdf_path).objects
    base_fonts = []
    embedded_truetype = false

    objects.each do |_ref, value|
      next unless value.is_a?(Hash)

      base_fonts << value[:BaseFont].to_s if value[:BaseFont]
      embedded_truetype = true if value.key?(:FontFile2)
    end

    { base_fonts: base_fonts.uniq, embedded_truetype: }
  end

  # テスト用の空白 PDF を生成する（Prawn・MIT）
  # @param dir [String] 出力ディレクトリ
  # @param page_count [Integer] ページ数
  # @return [String] 生成した PDF のパス
  def create_test_pdf(dir, page_count: 4)
    path = File.join(dir, 'test.pdf')

    # B5 サイズ + 塗り足し 3mm（188mm x 263mm）
    w_pt = 188.0 * 72.0 / 25.4
    h_pt = 263.0 * 72.0 / 25.4

    Prawn::Document.generate(path, page_size: [w_pt, h_pt], margin: 0) do |pdf|
      (page_count - 1).times { pdf.start_new_page }
    end
    path
  end
end
