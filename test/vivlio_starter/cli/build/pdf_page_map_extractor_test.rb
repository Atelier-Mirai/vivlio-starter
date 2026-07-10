# frozen_string_literal: true

# ================================================================
# Test: build/pdf_page_map_extractor_test.rb
# ================================================================
# 生成済み PDF の named destinations（/Dests）から「アンカー ID → 通しページ番号」を
# 取り出す抽出器の検証。PDF 生成は Prawn（MIT）、検査は本体実装（pdf-reader）で行う。
# ================================================================

require_relative '../../../test_helper'
require 'prawn'
require 'tmpdir'

require_relative '../../../../lib/vivlio_starter/cli/common'
require_relative '../../../../lib/vivlio_starter/cli/build/pdf_page_map_extractor'

class TestPdfPageMapExtractor < Minitest::Test
  Extractor = VivlioStarter::CLI::Build::PdfPageMapExtractor

  LOG_METHODS_TO_SILENCE = %i[log_action log_success log_warn log_error log_info log_debug].freeze

  def setup
    common = VivlioStarter::CLI::Common
    @saved_log_methods = LOG_METHODS_TO_SILENCE.to_h { [it, common.method(it)] }
    LOG_METHODS_TO_SILENCE.each { |name| common.define_singleton_method(name) { |_| } }
  end

  def teardown
    common = VivlioStarter::CLI::Common
    @saved_log_methods.each { |name, m| common.define_singleton_method(name, m) }
  end

  # ================================================================
  # decode_destination_name: vivliostyle の :XXXX エスケープ復号
  # ================================================================

  def test_should_decode_ascii_escapes
    encoded = 'viv-id-http:003a:002f:002flocalhost:003a13000:002f00-preface:002ehtml:0023gls-src-1'
    assert_equal 'viv-id-http://localhost:13000/00-preface.html#gls-src-1',
                 Extractor.decode_destination_name(encoded)
  end

  def test_should_decode_japanese_code_units
    # ウェブサイト = U+30A6 U+30A7 U+30D6 U+30B5 U+30A4 U+30C8
    encoded = 'a:0023gls-src-08-web-:30a6:30a7:30d6:30b5:30a4:30c8-4'
    assert_equal 'a#gls-src-08-web-ウェブサイト-4', Extractor.decode_destination_name(encoded)
  end

  def test_should_pass_through_names_without_escapes
    assert_equal 'plain-name', Extractor.decode_destination_name(:'plain-name')
  end

  # `:` の後ろが 4 桁 hex でなければエスケープではない（そのまま 1 文字として扱う）
  def test_should_treat_invalid_escape_as_literal_colon
    assert_equal 'a:zz11b', Extractor.decode_destination_name('a:zz11b')
  end

  def test_should_handle_empty_name
    assert_equal '', Extractor.decode_destination_name('')
  end

  # ================================================================
  # extract!: /Dests → anchor → page
  # ================================================================

  def test_should_extract_glossary_and_index_anchors_with_page_numbers
    Dir.mktmpdir do |dir|
      pdf_path = create_pdf_with_dests(dir)

      mapping = Extractor.new(pdf_path).extract!

      assert_equal 3, mapping.total_pages
      assert_equal 2, mapping.mappings.size
      assert_equal 1, mapping.index_mappings.size

      glossary = mapping.mappings.to_h { [it.anchor_id, it.page_index] }
      assert_equal({ 'gls-src-00-preface-1' => 1, 'gls-src-08-web-ウェブサイト-4' => 3 }, glossary)

      index_entry = mapping.index_mappings.first
      assert_equal 'idx-08-web-2', index_entry.anchor_id
      assert_equal 2, index_entry.page_index
      assert_equal 0, index_entry.spine_index
    end
  end

  # `#` を含まない名前（アンカー ID を持たない destination）は無視する
  def test_should_ignore_destinations_without_fragment
    Dir.mktmpdir do |dir|
      pdf_path = create_pdf_with_dests(dir, extra_plain_dest: true)

      mapping = Extractor.new(pdf_path).extract!

      assert_equal 2, mapping.mappings.size
      assert_equal 1, mapping.index_mappings.size
    end
  end

  # vivliostyle の /Dests 出力仕様が変わったら検知したい（Step 8 は警告してスキップする）
  def test_should_raise_when_no_named_destinations
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'plain.pdf')
      Prawn::Document.generate(path, page_size: [400, 600]) { it.text 'no dests' }

      error = assert_raises(RuntimeError) { Extractor.new(path).extract! }
      assert_match(/named destinations/, error.message)
    end
  end

  def test_should_raise_when_pdf_is_missing
    error = assert_raises(RuntimeError) { Extractor.new('/nonexistent/sections.pdf').extract! }
    assert_match(/本文 PDF が見つかりません/, error.message)
  end

  private

  # vivliostyle と同形の PDF を作る:
  # 文書カタログ直下の /Dests 辞書に、`:XXXX` エスケープ済みの名前と明示 destination 配列を持つ。
  def create_pdf_with_dests(dir, extra_plain_dest: false)
    path = File.join(dir, 'sections.pdf')

    Prawn::Document.generate(path, page_size: [400, 600], margin: 0) do |pdf|
      pdf.text 'page 1'
      2.times { pdf.start_new_page }

      store = pdf.state.store
      pages = (1..3).map { store[store.object_id_for_page(it)] }

      dests = {
        :'viv-id-http:003a:002f:002fx:002f00-preface:002ehtml:0023gls-src-00-preface-1' =>
          [pages[0], :XYZ, 0, 500, nil],
        :'viv-id-http:003a:002f:002fx:002f08-web:002ehtml:0023idx-08-web-2' =>
          [pages[1], :XYZ, 0, 400, nil],
        :'viv-id-http:003a:002f:002fx:002f08-web:002ehtml:0023gls-src-08-web-:30a6:30a7:30d6:30b5:30a4:30c8-4' =>
          [pages[2], :XYZ, 0, 300, nil]
      }
      dests[:'viv-id-no-fragment'] = [pages[0], :Fit] if extra_plain_dest

      store.root.data[:Dests] = store.ref(dests)
    end
    path
  end
end
