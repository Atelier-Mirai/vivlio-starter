# frozen_string_literal: true

# ================================================================
# Test: build/print_geometry_test.rb
# ================================================================
# 閲覧用（トリムサイズ）PDF → 入稿用（塗り足し＋トンボ代）ジオメトリ変換の検証。
#
# PDF 生成は Prawn、検査は pdf-reader（いずれも MIT・gemspec のランタイム依存）で行い、
# AGPL の HexaPDF には依存しない。変換の実体は外部コマンド qpdf。
# ================================================================

require_relative '../../../test_helper'
require 'prawn'
require 'pdf/reader'
require 'tmpdir'

require_relative '../../../../lib/vivlio_starter/cli/common'
require_relative '../../../../lib/vivlio_starter/cli/build/print_geometry'

class TestPrintGeometry < Minitest::Test
  PrintGeometry = VivlioStarter::CLI::Build::PrintGeometry

  BLEED_MM = 3.0
  CROP_OFFSET_MM = 13.0
  # 塗り足し 3mm ＋ トンボ代 13mm = 16mm ≒ 45.3543pt
  MARGIN_PT = (BLEED_MM + CROP_OFFSET_MM) * 72 / 25.4
  BLEED_PT = BLEED_MM * 72 / 25.4

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

  # ================================================================
  # ページボックス（expand! → finalize_boxes! の 2 段）
  # ================================================================

  def test_should_expand_media_box_and_finalize_trim_and_bleed_boxes
    Dir.mktmpdir do |dir|
      path = create_source_pdf(dir)

      assert expand!(path), 'ジオメトリ拡張が成功すること'
      assert finalize_boxes!(path), 'ボックス確定が成功すること'

      page = PDF::Reader.new(path).pages.first
      media = page.attributes[:MediaBox].map(&:to_f)
      trim  = page.attributes[:TrimBox].map(&:to_f)
      bleed = page.attributes[:BleedBox].map(&:to_f)

      assert_close [0, 0, TRIM_W + (2 * MARGIN_PT), TRIM_H + (2 * MARGIN_PT)], media
      assert_close [MARGIN_PT, MARGIN_PT, MARGIN_PT + TRIM_W, MARGIN_PT + TRIM_H], trim
      assert_close [MARGIN_PT - BLEED_PT, MARGIN_PT - BLEED_PT,
                    MARGIN_PT + TRIM_W + BLEED_PT, MARGIN_PT + TRIM_H + BLEED_PT], bleed
    end
  end

  # qpdf --overlay は宛先の TrimBox（無ければ CropBox）に合わせて重ねる側を縮小配置する。
  # トンボ・ノンブルを等倍で重ねるため、expand! の段階では TrimBox / BleedBox を
  # 書かず、古い CropBox / ArtBox も残さない（§3.8 の順序保証の要）。
  def test_expand_should_leave_no_scaling_boxes_before_overlay
    Dir.mktmpdir do |dir|
      path = create_source_pdf(dir)

      expand!(path)

      attributes = PDF::Reader.new(path).pages.first.attributes
      %i[TrimBox BleedBox CropBox ArtBox].each do |key|
        refute attributes.key?(key), "#{key} は overlay 前に存在しないこと"
      end
    end
  end

  # Chrome 出力の MediaBox 原点には ±0.3pt のジッタがある。原点ぶんを織り込んで
  # シフトしないと、ページごとに仕上がり位置がずれる。
  def test_should_compensate_media_box_origin_jitter
    Dir.mktmpdir do |dir|
      path = create_source_pdf(dir)
      shift_media_box_origin!(path, 0.0, 0.28)

      expand!(path)
      finalize_boxes!(path)

      trim = PDF::Reader.new(path).pages.first.attributes[:TrimBox].map(&:to_f)
      # 原点が 0.28 ずれていても、仕上がり線は常に (m, m) に来る
      assert_close [MARGIN_PT, MARGIN_PT, MARGIN_PT + TRIM_W, MARGIN_PT + TRIM_H], trim
    end
  end

  # ================================================================
  # リンク（アノテーション ＋ named destinations）
  # ================================================================

  def test_should_shift_annotation_rects
    Dir.mktmpdir do |dir|
      path = create_source_pdf(dir)

      expand!(path)

      reader = PDF::Reader.new(path)
      objects = reader.objects
      rects = Array(objects.deref(reader.pages.first.attributes[:Annots]))
              .map { objects.deref(it)[:Rect].map(&:to_f) }

      assert_equal 1, rects.size, 'アノテーションの件数は変わらないこと'
      assert_close [10 + MARGIN_PT, 10 + MARGIN_PT, 100 + MARGIN_PT, 30 + MARGIN_PT], rects.first
    end
  end

  def test_should_preserve_and_shift_named_destinations
    Dir.mktmpdir do |dir|
      path = create_source_pdf(dir)

      expand!(path)

      objects = PDF::Reader.new(path).objects
      dests = objects.deref(objects.deref(objects.trailer[:Root])[:Dests])

      assert_equal 2, dests.size, '/Dests が保持されること（CombinePDF は全損させる）'

      xyz = objects.deref(dests[:'viv-id-a:0023gls-src-01-test-1'])
      assert_equal :XYZ, xyz[1]
      assert_in_delta 10 + MARGIN_PT, xyz[2].to_f, 0.01
      assert_in_delta 500 + MARGIN_PT, xyz[3].to_f, 0.01
      assert_nil xyz[4], 'zoom の null はシフトせず残ること'

      fit_h = objects.deref(dests[:'viv-id-b:0023idx-01-test-2'])
      assert_equal :FitH, fit_h[1]
      assert_in_delta 300 + MARGIN_PT, fit_h[2].to_f, 0.01
    end
  end

  # ================================================================
  # 内容の平行移動
  # ================================================================

  def test_should_wrap_contents_with_translation_streams
    Dir.mktmpdir do |dir|
      path = create_source_pdf(dir)

      expand!(path)

      reader = PDF::Reader.new(path)
      contents = Array(reader.pages.first.attributes[:Contents])
      assert_equal 3, contents.size, '前後に平行移動ストリームが挟まること'

      objects = reader.objects
      assert_match(/\Aq 1 0 0 1 [\d.]+ [\d.]+ cm/, objects.deref(contents.first).unfiltered_data)
      assert_equal "\nQ", objects.deref(contents.last).unfiltered_data
    end
  end

  # ================================================================
  # 変換可否のガード
  # ================================================================

  def test_should_refuse_rotated_pages
    Dir.mktmpdir do |dir|
      path = create_source_pdf(dir)
      set_page_rotation!(path, 90)
      before = File.binread(path)

      refute expand!(path), '/Rotate が 0 でないページは変換を拒否すること'
      assert_equal before, File.binread(path), '拒否時は PDF を書き換えないこと'
    end
  end

  def test_should_refuse_already_converted_pdf
    Dir.mktmpdir do |dir|
      path = create_source_pdf(dir)
      assert expand!(path)
      assert finalize_boxes!(path)
      before = File.binread(path)

      refute expand!(path), '変換済み（塗り足し付き TrimBox を持つ）PDF は二重適用しないこと'
      assert_equal before, File.binread(path)
    end
  end

  def test_should_return_false_for_missing_pdf
    refute expand!(File.join(Dir.tmpdir, 'no-such-file.pdf'))
  end

  # ================================================================
  # 導出フローの順序契約（3a → トンボ → ノンブル → 3b）
  # ================================================================

  # qpdf --overlay は宛先の TrimBox に合わせて重ねる側を縮小配置するため、
  # ボックス確定（3b）を overlay より先に行うとトンボ・ノンブルが仕上がり線の
  # 内側へ入り込む（仕様 §3.8）。正順ならすべて等倍で重なることを通しで確認する。
  def test_derivation_order_keeps_overlays_at_original_scale
    require_relative '../../../../lib/vivlio_starter/cli/build/crop_marks_overlay'
    require_relative '../../../../lib/vivlio_starter/cli/build/nombre_stamper'

    Dir.mktmpdir do |dir|
      path = create_source_pdf(dir)

      assert expand!(path)                                             # 3a
      assert VivlioStarter::CLI::Build::CropMarksOverlay.apply!(       # 4
        path, bleed_mm: BLEED_MM, crop_offset_mm: CROP_OFFSET_MM
      )
      assert VivlioStarter::CLI::Build::NombreStamper.stamp!(path, bleed_mm: BLEED_MM) # 5
      assert finalize_boxes!(path)                                     # 3b

      reader = PDF::Reader.new(path)
      reader.pages.each_with_index do |page, index|
        refute_match(/0\.\d+ 0 0 0\.\d+ [\d.]+ [\d.]+ cm/, page.raw_content,
                     "p#{index + 1}: トンボ・ノンブルが縮小配置されていないこと")
      end

      trim = reader.pages.first.attributes[:TrimBox].map(&:to_f)
      assert_close [MARGIN_PT, MARGIN_PT, MARGIN_PT + TRIM_W, MARGIN_PT + TRIM_H], trim

      objects = reader.objects
      dests = objects.deref(objects.deref(objects.trailer[:Root])[:Dests])
      assert_equal 2, dests.size, '通しで /Dests が生き残ること'
    end
  end

  # ================================================================
  # 復号系ヘルパー
  # ================================================================

  private

  def expand!(path)
    PrintGeometry.expand!(path, bleed_mm: BLEED_MM, crop_offset_mm: CROP_OFFSET_MM)
  end

  def finalize_boxes!(path)
    PrintGeometry.finalize_boxes!(path, bleed_mm: BLEED_MM, crop_offset_mm: CROP_OFFSET_MM)
  end

  def assert_close(expected, actual, delta: 0.01)
    expected.zip(actual).each_with_index do |(e, a), i|
      assert_in_delta e, a, delta, "要素 #{i} が一致しません（expected=#{expected}, actual=#{actual}）"
    end
  end

  # 検証用の閲覧用 PDF 相当を作る。
  # リンクのクリック領域（Link アノテーション）と、vivliostyle と同形の
  # 文書カタログ直下 /Dests 辞書（XYZ と FitH の 2 種）を持たせる。
  # Prawn は既定で TrimBox / BleedBox も書くが、閲覧用（Chrome 出力）は
  # MediaBox / CropBox しか持たないため、それらは落として実物に寄せる。
  def create_source_pdf(dir)
    path = File.join(dir, 'source.pdf')

    Prawn::Document.generate(path, page_size: [TRIM_W, TRIM_H], margin: 0) do |pdf|
      pdf.text 'page 1'
      pdf.link_annotation([10, 10, 100, 30], Dest: 'viv-id-a:0023gls-src-01-test-1')
      pdf.start_new_page
      pdf.text 'page 2'

      pdf.page_count.times do |i|
        pdf.go_to_page(i + 1)
        %i[TrimBox BleedBox].each { pdf.state.page.dictionary.data.delete(it) }
      end

      store = pdf.state.store
      page1 = store[store.object_id_for_page(1)]
      page2 = store[store.object_id_for_page(2)]
      store.root.data[:Dests] = store.ref(
        :'viv-id-a:0023gls-src-01-test-1' => [page1, :XYZ, 10, 500, nil],
        :'viv-id-b:0023idx-01-test-2' => [page2, :FitH, 300]
      )
    end
    path
  end

  # 1 ページ目の MediaBox 原点をずらす（Chrome 出力のジッタを再現）
  def shift_media_box_origin!(path, ox, oy)
    rewrite_first_page!(path) do |page_json|
      box = page_json['/MediaBox']
      page_json['/MediaBox'] = [ox, oy, ox + TRIM_W, oy + TRIM_H]
      box
    end
  end

  def set_page_rotation!(path, degrees)
    rewrite_first_page!(path) { |page_json| page_json['/Rotate'] = degrees }
  end

  # qpdf --update-from-json でテスト用 PDF の 1 ページ目辞書を書き換える
  def rewrite_first_page!(path)
    require 'json'
    require 'open3'

    out, = Open3.capture2('qpdf', path, '--json=2', '--json-key=qpdf', '--json-key=pages',
                          '--json-stream-data=none')
    document = JSON.parse(out)
    header, objects = document['qpdf']
    key = "obj:#{document['pages'].first['object']}"
    value = objects[key]['value'].dup
    yield(value)

    Tempfile.create(['update', '.json']) do |json|
      json.write(JSON.generate({ 'version' => 2, 'qpdf' => [header, { key => { 'value' => value } }] }))
      json.flush
      tmp = "#{path}.tmp.pdf"
      system('qpdf', path, tmp, "--update-from-json=#{json.path}", out: File::NULL, err: File::NULL)
      FileUtils.mv(tmp, path)
    end
  end
end
