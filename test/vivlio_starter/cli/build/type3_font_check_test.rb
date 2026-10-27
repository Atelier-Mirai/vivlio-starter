# frozen_string_literal: true

# ================================================================
# Test: build/type3_font_check_test.rb
# ================================================================
# 仕上がった PDF の Type 3 書体を見つけ、ページ・字・しおりの題を返す（Type3FontCheck・改善案 #124）。
#
# Prawn は Type 3 書体を作れないので、Type 3 書体を持つ小さな PDF をここで組む。
# 書体の ToUnicode は、文字コード 1 を「≒」に、0x20〜0x7E を ASCII にそのまま当てる。
#   1 ページ目: Helvetica だけ（Type 3 なし）
#   2 ページ目: Type 3 で「≒」。q/Q で Helvetica に戻ってから描く「abc」は数えない
#   3 ページ目: Form XObject（図）の中で、Type 3 で組めなかった式の TeX「\pi^{a}^{b}」
# しおりは 2 ページ目を指す「Chapter 1」だけ。
# ================================================================

require_relative '../../../test_helper'
require 'prawn'
require 'tmpdir'

require_relative '../../../../lib/vivlio_starter/cli/common'
require_relative '../../../../lib/vivlio_starter/cli/build/type3_font_check'

class TestType3FontCheck < Minitest::Test
  Type3FontCheck = VivlioStarter::CLI::Build::Type3FontCheck
  Finding = Type3FontCheck::Finding

  def setup
    skip 'qpdf が必要です' unless system('qpdf', '--version', out: File::NULL, err: File::NULL)
  end

  def test_should_find_type3_pages_with_drawn_chars_and_outline_heading
    Dir.mktmpdir do |dir|
      pdf = write_type3_pdf(File.join(dir, 'book.pdf'))

      findings = Type3FontCheck.scan(pdf)

      assert_equal [2, 3], findings.map(&:page), 'Type 3 の無い 1 ページ目は拾わず、図の中の Type 3 は拾う'
      assert_equal '≒', findings[0].text, 'Q で Helvetica に戻ってから描いた字は数えない'
      assert_equal 'Chapter 1', findings[0].heading
      assert_equal '\pi^{a}^{b}', findings[1].text
      assert findings[1].math_error?
      refute findings[0].math_error?
    end
  end

  # 仕上がった PDF はオブジェクトストリームを持つ（DestinationNames が作り直す）。外さずに読める
  def test_should_read_pdf_with_object_streams
    Dir.mktmpdir do |dir|
      plain = write_type3_pdf(File.join(dir, 'plain.pdf'))
      packed = File.join(dir, 'packed.pdf')
      system('qpdf', plain, packed, '--object-streams=generate', exception: true)
      assert_includes File.binread(packed), '/ObjStm', '前提: オブジェクトストリームを持つ PDF'
      before = File.binread(packed)

      assert_equal [2, 3], Type3FontCheck.scan(packed).map(&:page)
      assert_equal before, File.binread(packed), '調べるだけで PDF を書き直さない'
    end
  end

  def test_should_find_nothing_in_pdf_without_type3
    Dir.mktmpdir do |dir|
      pdf = File.join(dir, 'plain.pdf')
      Prawn::Document.generate(pdf) { it.text 'plain' }

      assert_empty Type3FontCheck.check!(pdf)
    end
  end

  def test_should_suggest_fix_per_char_and_group_chars_sharing_a_fix
    line = Type3FontCheck.finding_line(Finding.new(page: 662, text: 'xⁿ ᵖ∛', heading: '第3章'))

    assert_equal '662 ページ目（第3章）: x → 本の書体にある字に置き換える ／ ' \
                 'ⁿ ᵖ → 本文は $x^n$・$H_n$ の数式に、図（SVG）は <tspan baseline-shift="super"> で上付き・下付きに ／ ' \
                 '∛ → 本文は $\sqrt[3]{x}$ の数式に、図（SVG）は ³√ のように', line
    assert_equal '43 ページ目: ⌃ → Control・Option・Command・Shift のように言葉で書く',
                 Type3FontCheck.finding_line(Finding.new(page: 43, text: '⌃', heading: nil))
    assert_equal '719 ページ目（じゃんけん）: ✊ ✌️ ✋ → 言葉か画像に置き換える',
                 Type3FontCheck.finding_line(Finding.new(page: 719, text: '✊✌️✋', heading: 'じゃんけん'))
  end

  # 字と同じページで始まる節は、飛び先が字より上にあるときだけ使う（PDF の座標は上ほど大きい）
  def test_should_skip_heading_starting_below_the_char_on_same_page
    headings = [[10, nil, '第2章'], [12, 300.0, '2.3 節'], [12, 150.0, '第3章']]

    assert_equal '2.3 節', Type3FontCheck.heading_at(headings, 12, 200.0), '字の下で始まる第3章は使わない'
    assert_equal '第3章', Type3FontCheck.heading_at(headings, 12, 100.0)
    assert_equal '第2章', Type3FontCheck.heading_at(headings, 12, 400.0)
    assert_equal '第3章', Type3FontCheck.heading_at(headings, 13, 400.0), '後のページなら高さを見ない'
  end

  # 組めなかった式は、字を一つずつ並べず式の TeX のまま見せる
  def test_should_show_math_source_as_is_for_math_error
    line = Type3FontCheck.finding_line(Finding.new(page: 667, text: '(-1)^{jf}^{(j)}(\pi) = f^{(j)}(0)', heading: '第3章'))

    assert_equal '667 ページ目（第3章）: 数式が組めていません: (-1)^{jf}^{(j)}(\pi) = f^{(j)}(0) → 式の書き方を直す（^ や _ の重なりなど）',
                 line
  end

  private

  # Type 3 書体を持つ 3 ページの PDF を書き、パスを返す（ファイル冒頭の説明を参照）
  def write_type3_pdf(path)
    to_unicode = <<~CMAP
      /CIDInit /ProcSet findresource begin
      12 dict begin
      begincmap
      /CMapName /Type3Test def
      /CMapType 2 def
      1 begincodespacerange <00> <FF> endcodespacerange
      1 beginbfchar <01> <2252> endbfchar
      1 beginbfrange <20> <7E> <0020> endbfrange
      endcmap
      CMapName currentdict /CMap defineresource pop
      end
      end
    CMAP
    widths = Array.new(126, 500).join(' ')
    glyph_names = Array.new(95, '/g').join(' ')
    objects = {
      1 => '<< /Type /Catalog /Pages 2 0 R /Outlines 9 0 R >>',
      2 => '<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >>',
      3 => '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /Font << /F1 6 0 R >> >> /Contents 10 0 R >>',
      4 => '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] ' \
           '/Resources << /Font << /F1 6 0 R /F3 7 0 R >> >> /Contents 11 0 R >>',
      5 => '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /XObject << /Fm1 8 0 R >> >> /Contents 14 0 R >>',
      6 => '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
      7 => '<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1000 1000] /FontMatrix [0.001 0 0 0.001 0 0] ' \
           "/CharProcs << /g 15 0 R >> /Encoding << /Type /Encoding /Differences [1 /g 32 #{glyph_names}] >> " \
           "/FirstChar 1 /LastChar 126 /Widths [#{widths}] /ToUnicode 12 0 R >>",
      8 => stream('BT /F3 12 Tf 10 50 Td (\\\\pi^{a}^{b}) Tj ET',
                  '/Type /XObject /Subtype /Form /BBox [0 0 200 200] /Resources << /Font << /F3 7 0 R >> >>'),
      9 => '<< /Type /Outlines /First 13 0 R /Last 13 0 R /Count 1 >>',
      10 => stream('BT /F1 12 Tf 10 100 Td (plain) Tj ET'),
      11 => stream('BT /F1 12 Tf ET q BT /F3 12 Tf 10 100 Td (\\001) Tj ET Q BT 10 80 Td (abc) Tj ET'),
      12 => stream(to_unicode),
      13 => '<< /Title (Chapter 1) /Parent 9 0 R /Dest [4 0 R /XYZ 0 200 0] >>',
      14 => stream('/Fm1 Do'),
      15 => stream('500 0 d0')
    }

    body = +"%PDF-1.7\n"
    offsets = objects.map do |number, object|
      offset = body.bytesize
      body << "#{number} 0 obj\n#{object}\nendobj\n"
      offset
    end
    xref = body.bytesize
    body << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n"
    offsets.each { body << format("%010d 00000 n \n", it) }
    body << "trailer\n<< /Size #{objects.size + 1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"
    File.binwrite(path, body)
    path
  end

  def stream(content, dictionary = '')
    "<< #{dictionary} /Length #{content.bytesize} >>\nstream\n#{content}\nendstream"
  end
end
