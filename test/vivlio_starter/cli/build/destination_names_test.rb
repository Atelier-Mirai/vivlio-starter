# frozen_string_literal: true

# ================================================================
# Test: build/destination_names_test.rb
# ================================================================
# 仕上がった PDF のリンク先の名前を短い名前に付け替える（改善案 #81）。
#
# PDF 生成は Prawn、検査は pdf-reader（いずれも MIT・gemspec のランタイム依存）。
# 付け替えの実体は外部コマンド qpdf。
# ================================================================

require_relative '../../../test_helper'
require 'prawn'
require 'pdf/reader'
require 'tmpdir'

require_relative '../../../../lib/vivlio_starter/cli/common'
require_relative '../../../../lib/vivlio_starter/cli/build/destination_names'

class TestDestinationNames < Minitest::Test
  DestinationNames = VivlioStarter::CLI::Build::DestinationNames

  # vivliostyle と同形の名前（ビルド時の URL を丸ごと含む）
  FOOTNOTE = 'viv-id-http:003a:002f:002flocalhost:003a13000:002fvivliostyle:002f:002ecache:002fvs:002fbuild:' \
             '002fpdf:002f44-build:002ehtml:0023fn1'
  HEADING = 'viv-id-http:003a:002f:002flocalhost:003a13000:002fvivliostyle:002f:002ecache:002fvs:002fbuild:' \
            '002fpdf:002f44-build:002ehtml:0023sec-a'

  def setup
    skip 'qpdf が必要です' unless system('qpdf', '--version', out: File::NULL, err: File::NULL)
  end

  # 見出し語と参照（/Dest の名前・/A /D の文字列）が同じ短い名前へそろい、リンクが生きたまま残る
  def test_should_shorten_names_and_keep_links_pointing_to_them
    Dir.mktmpdir do |dir|
      path = create_pdf(dir)

      assert_equal 2, DestinationNames.shorten!(path)

      reader = PDF::Reader.new(path)
      dests = reader.objects.deref(reader.objects.trailer[:Root])[:Dests]
      dests = reader.objects.deref(dests)
      annotations = reader.pages.first.attributes[:Annots].map { reader.objects.deref(it) }

      assert_equal %i[vs1 vs2], dests.keys.sort
      assert_equal :vs2, annotations.first[:Dest], '名前で指すリンク'
      assert_equal 'vs1', reader.objects.deref(annotations.last[:A])[:D], '文字列で指すリンク'
      refute_includes File.binread(path), 'localhost', 'ビルドした場所のパスを残さない'
    end
  end

  # 仕上がった PDF はオブジェクトストリームを持つ。qpdf の JSON 更新はその中の一部を捨てるので、
  # 外してから書き換え、作り直して戻す（全章ビルドで 1,504 件のリンクが元の名前のまま残った）。
  # この小さな PDF では捨てられる現象そのものは再現しない。ここで確かめるのは、
  # オブジェクトストリームのある PDF でも付け替えができ、作り直して戻せること
  def test_should_rename_links_stored_in_object_streams
    Dir.mktmpdir do |dir|
      path = create_pdf(dir)
      packed = File.join(dir, 'packed.pdf')
      system('qpdf', path, packed, '--object-streams=generate', exception: true)

      DestinationNames.shorten!(packed)

      reader = PDF::Reader.new(packed)
      annotations = reader.pages.first.attributes[:Annots].map { reader.objects.deref(it) }
      assert_equal :vs2, annotations.first[:Dest]
      assert_equal 'vs1', reader.objects.deref(annotations.last[:A])[:D]
      assert_includes File.binread(packed), '/ObjStm', 'オブジェクトストリームは作り直して戻す'
    end
  end

  # 付け替え済みの名前（vsN）がある PDF にかけても、続きの番号から振って重ならない
  def test_should_not_reuse_existing_short_names
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'mixed.pdf')
      Prawn::Document.generate(path, margin: 0) do |pdf|
        pdf.text 'page 1'
        pdf.link_annotation([10, 10, 100, 30], Dest: :vs1)
        pdf.link_annotation([10, 40, 100, 60], Dest: FOOTNOTE.to_sym)
        store = pdf.state.store
        page = store[store.object_id_for_page(1)]
        store.root.data[:Dests] = store.ref(vs1: [page, :FitH, 300], FOOTNOTE.to_sym => [page, :FitH, 100])
      end

      DestinationNames.shorten!(path)

      reader = PDF::Reader.new(path)
      annotations = reader.pages.first.attributes[:Annots].map { reader.objects.deref(it) }
      assert_equal %i[vs1 vs2], annotations.map { it[:Dest] }
    end
  end

  # 単章ビルドで組んでいない章へのリンクは、ビルド中のサーバーを開く外部リンクになる。
  # 開けないうえパスが残るので飛び先を外す。ふつうの外部リンクはそのまま
  def test_should_unlink_links_to_the_build_server
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'single.pdf')
      Prawn::Document.generate(path, margin: 0) do |pdf|
        pdf.text 'page 1'
        pdf.link_annotation([10, 10, 100, 30],
                            A: { S: :URI, URI: 'http://localhost:13000/vivliostyle/.cache/vs/build/pdf/41-book-yml.html#ch-book-yml' })
        pdf.link_annotation([10, 40, 100, 60], A: { S: :URI, URI: 'https://example.com/' })
      end

      DestinationNames.shorten!(path)

      reader = PDF::Reader.new(path)
      local, external = reader.pages.first.attributes[:Annots].map { reader.objects.deref(it) }

      assert_nil local[:A], 'ビルド中のサーバーを開くリンクは飛び先を外す'
      assert_equal 'https://example.com/', pdf_text(reader.objects.deref(external[:A])[:URI])
      refute_includes File.binread(path), 'localhost'
    end
  end

  # vivliostyle の名前が無い PDF（付け替え済み・別の道具で作った PDF）には触れない
  def test_should_leave_pdf_without_vivliostyle_names_untouched
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'plain.pdf')
      Prawn::Document.generate(path) { it.text 'plain' }
      before = File.binread(path)

      assert_equal 0, DestinationNames.shorten!(path)
      assert_equal before, File.binread(path)
    end
  end

  private

  # Prawn は文字列を UTF-16（BOM 付き）で書くので、比べる前に UTF-8 へ戻す
  def pdf_text(raw)
    raw.b.start_with?("\xFE\xFF".b) ? raw.b.byteslice(2..).force_encoding('UTF-16BE').encode('UTF-8') : raw
  end

  # 名前で指すリンク（/Dest）と、文字列で指すリンク（/A /S /GoTo /D）を 1 つずつ持つ PDF
  def create_pdf(dir)
    path = File.join(dir, 'source.pdf')

    Prawn::Document.generate(path, margin: 0) do |pdf|
      pdf.text 'page 1'
      pdf.link_annotation([10, 10, 100, 30], Dest: HEADING.to_sym)
      pdf.link_annotation([10, 40, 100, 60], A: { S: :GoTo, D: FOOTNOTE })

      store = pdf.state.store
      page = store[store.object_id_for_page(1)]
      store.root.data[:Dests] = store.ref(
        FOOTNOTE.to_sym => [page, :XYZ, 10, 500, nil],
        HEADING.to_sym => [page, :FitH, 300]
      )
    end
    path
  end
end
