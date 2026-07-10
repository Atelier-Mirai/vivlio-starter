# frozen_string_literal: true

# ================================================================
# Test: build/crop_marks_overlay_test.rb
# ================================================================
# トンボ PDF の生成と、qpdf --overlay による全ページ重畳の検証。
# 「重畳してもリンク（アノテーション・/Dests）が壊れない」ことが要点。
# ================================================================

require_relative '../../../test_helper'
require 'prawn'
require 'pdf/reader'
require 'tmpdir'

require_relative '../../../../lib/vivlio_starter/cli/common'
require_relative '../../../../lib/vivlio_starter/cli/build/crop_marks_overlay'

class TestCropMarksOverlay < Minitest::Test
  CropMarksOverlay = VivlioStarter::CLI::Build::CropMarksOverlay

  BLEED_MM = 3.0
  CROP_OFFSET_MM = 13.0
  MARGIN_PT = (BLEED_MM + CROP_OFFSET_MM) * 72 / 25.4
  TRIM_W = 400.0
  TRIM_H = 600.0

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

  def test_should_generate_single_page_marks_pdf_sized_to_trim_plus_margins
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'marks.pdf')

      CropMarksOverlay.generate!(path, trim_w_pt: TRIM_W, trim_h_pt: TRIM_H,
                                       bleed_pt: BLEED_MM * 72 / 25.4,
                                       crop_offset_pt: CROP_OFFSET_MM * 72 / 25.4)

      reader = PDF::Reader.new(path)
      assert_equal 1, reader.page_count, '全ページへ --repeat するので 1 ページで足りる'

      box = reader.pages.first.attributes[:MediaBox].map(&:to_f)
      assert_in_delta TRIM_W + (2 * MARGIN_PT), box[2] - box[0], 0.01
      assert_in_delta TRIM_H + (2 * MARGIN_PT), box[3] - box[1], 0.01
    end
  end

  # トンボを重ねても本文の内容・リンク部品が失われないこと（CombinePDF 合成の回帰）
  def test_should_overlay_marks_on_all_pages_preserving_links
    Dir.mktmpdir do |dir|
      pdf_path = create_print_sized_pdf(dir)

      assert CropMarksOverlay.apply!(pdf_path, bleed_mm: BLEED_MM, crop_offset_mm: CROP_OFFSET_MM)

      reader = PDF::Reader.new(pdf_path)
      assert_equal 2, reader.page_count

      objects = reader.objects
      root = objects.deref(objects.trailer[:Root])
      assert_equal 1, objects.deref(root[:Dests]).size, '/Dests が保持されること'
      assert_equal 1, Array(objects.deref(reader.pages.first.attributes[:Annots])).size

      # 各ページに本文とトンボの両方が載る（qpdf は重畳内容を Form XObject にする）
      reader.pages.each do |page|
        assert_match(/\/Fx\d+ Do.*\/Fx\d+ Do/m, page.raw_content, 'トンボの内容が各ページへ重畳されること')
      end
    end
  end

  # qpdf --overlay は既定で「重ねる側を宛先の TrimBox に収まるよう縮小・センタリング」する。
  # トンボは仕上がり線の外側に描く図形なので、縮小されると本文の内側へ入り込む。
  # QpdfOverlay がボックスを退避して等倍で重ねること、かつ退避したボックスを戻すことを確認する。
  def test_should_overlay_at_original_scale_and_restore_trim_box
    Dir.mktmpdir do |dir|
      pdf_path = create_print_sized_pdf(dir)
      trim_box = [MARGIN_PT, MARGIN_PT, MARGIN_PT + TRIM_W, MARGIN_PT + TRIM_H]
      set_trim_box!(pdf_path, trim_box)

      assert CropMarksOverlay.apply!(pdf_path, bleed_mm: BLEED_MM, crop_offset_mm: CROP_OFFSET_MM)

      page = PDF::Reader.new(pdf_path).pages.first
      # 縮小されていれば `0.815… 0 0 0.815… … cm` が現れる。等倍なら 1 0 0 1 のみ。
      refute_match(/0\.\d+ 0 0 0\.\d+ [\d.]+ [\d.]+ cm/, page.raw_content,
                   'トンボが TrimBox に合わせて縮小されていないこと')

      restored = page.attributes[:TrimBox].map(&:to_f)
      trim_box.zip(restored).each { |e, a| assert_in_delta e, a, 0.01, 'TrimBox が復帰すること' }
    end
  end

  def test_should_return_false_for_missing_pdf
    refute CropMarksOverlay.apply!(File.join(Dir.tmpdir, 'no-such.pdf'),
                                   bleed_mm: BLEED_MM, crop_offset_mm: CROP_OFFSET_MM)
  end

  private

  # PrintGeometry 適用後を模した「仕上がり ＋ 余白 ×2」サイズの 2 ページ PDF
  # 既定のボックス類は落とし、テストが必要とするものだけを後から与える。
  def create_print_sized_pdf(dir)
    path = File.join(dir, 'print.pdf')
    page_size = [TRIM_W + (2 * MARGIN_PT), TRIM_H + (2 * MARGIN_PT)]

    Prawn::Document.generate(path, page_size:, margin: 0) do |pdf|
      pdf.text 'page 1'
      pdf.link_annotation([10, 10, 100, 30], Dest: 'viv-id-a:0023gls-src-01-test-1')
      pdf.start_new_page
      pdf.text 'page 2'

      pdf.page_count.times do |i|
        pdf.go_to_page(i + 1)
        %i[TrimBox BleedBox CropBox ArtBox].each { pdf.state.page.dictionary.data.delete(it) }
      end

      store = pdf.state.store
      store.root.data[:Dests] = store.ref(
        :'viv-id-a:0023gls-src-01-test-1' => [store[store.object_id_for_page(1)], :XYZ, 10, 500, nil]
      )
    end
    path
  end

  # 全ページに TrimBox を与える（qpdf --overlay の縮小挙動を誘発させる）
  def set_trim_box!(path, trim_box)
    header, objects, pages = VivlioStarter::CLI::Build::QpdfJson.read(path)
    updates = pages.to_h do |page|
      key = "obj:#{page['object']}"
      ["obj:#{page['object']}", { 'value' => objects[key]['value'].merge('/TrimBox' => trim_box) }]
    end
    VivlioStarter::CLI::Build::QpdfJson.apply!(path, header, updates)
  end
end
