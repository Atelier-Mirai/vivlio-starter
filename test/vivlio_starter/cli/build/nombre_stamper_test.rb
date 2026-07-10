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
  # ノンブルは Prawn + qpdf の本体実装に一本化されたため、PDF プロバイダの
  # 選択（Standard / Enhanced）に依存せずここで担保できる。
  def test_should_embed_nombre_font_instead_of_helvetica
    Dir.mktmpdir do |dir|
      pdf_path = create_test_pdf(dir, page_count: 2)

      NombreStamper.stamp!(pdf_path, bleed_mm: 3)

      summary = nombre_font_summary(pdf_path)
      assert summary[:embedded_truetype],
             "ノンブルフォントが TrueType としてサブセット埋め込みされていること（FontFile2）"
      assert(summary[:base_fonts].any? { it.include?("HackGen") },
             "ノンブルが HackGen35ConsoleNF で描画されていること: #{summary[:base_fonts]}")
      refute(summary[:base_fonts].any? { it.include?("Helvetica") },
             "非埋め込み Helvetica が使われていないこと（FT-02 回帰）: #{summary[:base_fonts]}")
    end
  end

  # 回帰: CombinePDF 合成は保存時に named destinations（/Dests）を再構築せず全損させ、
  # 入稿用 PDF の目次・索引リンクを無反応にしていた。qpdf --overlay 化でこれを解消する。
  def test_should_preserve_named_destinations_after_stamping
    Dir.mktmpdir do |dir|
      pdf_path = create_test_pdf_with_dests(dir)

      assert NombreStamper.stamp!(pdf_path, bleed_mm: 3)

      objects = PDF::Reader.new(pdf_path).objects
      root = objects.deref(objects.trailer[:Root])
      dests = objects.deref(root[:Dests])

      assert_equal 2, dests.size, "隠しノンブル書き込み後も /Dests が保持されること"
      assert_includes dests.keys.map(&:to_s), "viv-id-a:0023gls-src-01-test-1"
    end
  end

  # 入稿用 PDF は仕上がり線（TrimBox）を持つ。qpdf --overlay は既定で重ねる側を
  # 宛先の TrimBox に収まるよう縮小するため、素朴に重ねるとノド側の裁ち落とし領域に
  # 置いたはずのノンブルが本文の内側へ入り込む（読者に見えてしまう）。
  def test_should_not_scale_nombre_into_trim_box
    Dir.mktmpdir do |dir|
      pdf_path = create_test_pdf(dir, page_count: 2)
      trim_box = [45.0, 45.0, 488.0, 700.0]
      set_trim_box!(pdf_path, trim_box)

      assert NombreStamper.stamp!(pdf_path, bleed_mm: 3)

      page = PDF::Reader.new(pdf_path).pages.first
      refute_match(/0\.\d+ 0 0 0\.\d+ [\d.]+ [\d.]+ cm/, page.raw_content,
                   'ノンブルが TrimBox に合わせて縮小されていないこと')

      restored = page.attributes[:TrimBox].map(&:to_f)
      trim_box.zip(restored).each { |e, a| assert_in_delta e, a, 0.01, 'TrimBox が復帰すること' }
    end
  end

  private

  # 全ページに TrimBox を与える
  def set_trim_box!(path, trim_box)
    qpdf_json = VivlioStarter::CLI::Build::QpdfJson
    header, objects, pages = qpdf_json.read(path)
    updates = pages.to_h do |page|
      key = "obj:#{page['object']}"
      [key, { 'value' => objects[key]['value'].merge('/TrimBox' => trim_box) }]
    end
    qpdf_json.apply!(path, header, updates)
  end

  # named destinations を 2 件持つ 2 ページの PDF を Prawn で生成する。
  # Prawn は既定で /Names 名前ツリーを書くため、vivliostyle と同じ
  # 「文書カタログ直下の /Dests 辞書」を直接差し込む。
  def create_test_pdf_with_dests(dir)
    path = File.join(dir, 'dests.pdf')

    Prawn::Document.generate(path, page_size: [400, 600], margin: 0) do |pdf|
      pdf.text 'page 1'
      pdf.start_new_page
      pdf.text 'page 2'

      store = pdf.state.store
      page1 = store[store.object_id_for_page(1)]
      page2 = store[store.object_id_for_page(2)]
      store.root.data[:Dests] = store.ref(
        :'viv-id-a:0023gls-src-01-test-1' => [page1, :XYZ, 10, 500, nil],
        :'viv-id-b:0023idx-01-test-2' => [page2, :XYZ, 0, 300, nil]
      )
    end
    path
  end

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
