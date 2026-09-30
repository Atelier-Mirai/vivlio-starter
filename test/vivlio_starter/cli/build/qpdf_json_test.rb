# frozen_string_literal: true

# ================================================================
# Test: build/qpdf_json_test.rb
# ================================================================
# qpdf の JSON で PDF を読み、差分更新する（QpdfJson）。
#
# qpdf の --update-from-json は、オブジェクトストリームの中のオブジェクトの差し替えを
# 成功を返したまま捨てることがある（改善案 #95）。起きるのは vivliostyle（Chrome）が
# 書き出した PDF のような、ストリームを末尾に置いて前の番号をまとめる形で、qpdf 自身が
# 作るストリームでは再現しない。ここでは、read が読む前にストリームを外すこと、
# そのうえで更新が反映されることを確かめる。
# ================================================================

require_relative '../../../test_helper'
require 'prawn'
require 'pdf/reader'
require 'tmpdir'

require_relative '../../../../lib/vivlio_starter/cli/common'
require_relative '../../../../lib/vivlio_starter/cli/build/qpdf_json'

class TestQpdfJson < Minitest::Test
  QpdfJson = VivlioStarter::CLI::Build::QpdfJson

  def setup
    skip 'qpdf が必要です' unless system('qpdf', '--version', out: File::NULL, err: File::NULL)
  end

  def test_should_unpack_object_streams_before_reading_so_updates_stick
    Dir.mktmpdir do |dir|
      plain = File.join(dir, 'plain.pdf')
      packed = File.join(dir, 'packed.pdf')
      Prawn::Document.generate(plain, margin: 0) do |pdf|
        pdf.text 'page 1'
        pdf.link_annotation([10, 10, 100, 30], Dest: :before)
      end
      system('qpdf', plain, packed, '--object-streams=generate', exception: true)
      assert_includes File.binread(packed), '/ObjStm', '前提: オブジェクトストリームを持つ PDF'

      header, objects, = QpdfJson.read(packed)

      refute_includes File.binread(packed), '/ObjStm', 'read の前にオブジェクトストリームを外す'
      key, link = objects.find { |_, object| object.is_a?(Hash) && object.dig('value', '/Subtype') == '/Link' }
      assert QpdfJson.apply!(packed, header, key => { 'value' => link['value'].merge('/Dest' => '/after') })

      reader = PDF::Reader.new(packed)
      assert_equal :after, reader.objects.deref(reader.pages.first.attributes[:Annots].first)[:Dest]
    end
  end

  # オブジェクトストリームの無い PDF は書き直さない（読むだけで中間ファイルを変えない）
  def test_should_leave_pdf_without_object_streams_as_is
    Dir.mktmpdir do |dir|
      plain = File.join(dir, 'plain.pdf')
      Prawn::Document.generate(plain) { it.text 'plain' }
      before = File.binread(plain)

      refute_nil QpdfJson.read(plain)
      assert_equal before, File.binread(plain)
    end
  end
end
