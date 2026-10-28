# frozen_string_literal: true

# ================================================================
# Test: build/chapter_lead_check_test.rb
# ================================================================
# 章扉に収まらず次のページへ送られたリードを、組んだ PDF から見つけ、直し方の案を出す
# （ChapterLeadCheck・chapter-lead-size-spec.md §4）。
#
# PDF は Prawn（MIT）で組み、pdftotext（poppler）で読む。リードは ASCII の語にする
# （Prawn の既定の書体は日本語を持たない。照合は空白を除いた字の並びなので、語でも同じ）。
#   1 ページ目: 章題「Chapter 1」と、リードの 1〜3 行目
#   2 ページ目: 柱「Part One」、リードの 4 行目、本文、ノンブル「2」
# ================================================================

require_relative '../../../test_helper'
require 'prawn'
require 'tmpdir'

require_relative '../../../../lib/vivlio_starter/cli/common'
require_relative '../../../../lib/vivlio_starter/cli/pre_process/frontmatter_generator'
require_relative '../../../../lib/vivlio_starter/cli/build/heading_image_composer'
require_relative '../../../../lib/vivlio_starter/cli/build/chapter_lead_check'

class TestChapterLeadCheck < Minitest::Test
  ChapterLeadCheck = VivlioStarter::CLI::Build::ChapterLeadCheck
  Lead = ChapterLeadCheck::Lead
  Overflow = ChapterLeadCheck::Overflow
  # 章の代わり（basename と path だけを使う）
  FakeEntry = Data.define(:basename, :path)

  LEAD_LINES = [
    'alpha bravo charlie delta echo foxtrot',
    'golf hotel india juliet kilo lima',
    'mike november oscar papa quebec romeo',
    'sierra tango uniform victor whiskey xray yankee zulu'
  ].freeze
  LEAD = Lead.new(path: 'contents/10-a.md', title: 'Chapter 1', paragraphs: [LEAD_LINES.join(' ')])

  # 1 ページ目に収める行数を変えて、章扉の PDF を組む
  def write_pdf(path, on_first_page:)
    Prawn::Document.generate(path, page_size: 'A5', margin: 40) do |pdf|
      pdf.draw_text 'Chapter 1', at: [0, 500], size: 20
      LEAD_LINES.first(on_first_page).each_with_index { |line, i| pdf.draw_text line, at: [0, 440 - (i * 20)] }
      pdf.start_new_page
      pdf.draw_text 'Part One', at: [0, 520], size: 8
      LEAD_LINES.drop(on_first_page).each_with_index { |line, i| pdf.draw_text line, at: [0, 480 - (i * 20)] }
      pdf.draw_text 'The body starts here.', at: [0, 400]
      pdf.draw_text '2', at: [150, 0], size: 8
    end
    path
  end

  def require_pdftotext
    skip 'pdftotext が必要です' unless system('pdftotext', '-v', out: File::NULL, err: File::NULL)
  end

  # --- PDF を調べる ---

  # 尾が次のページへ送られたリードを見つけ、章扉のページと次のページの行数を数える。
  # 柱とノンブルと本文の行は、リードの字の並びに無いので数えない
  def test_should_count_lines_on_frontispiece_and_next_page
    require_pdftotext
    Dir.mktmpdir do |dir|
      pdf = write_pdf(File.join(dir, 'book.pdf'), on_first_page: 3)

      overflows = ChapterLeadCheck.scan(pdf, [LEAD])

      assert_equal 1, overflows.size
      assert_equal [3, 1], [overflows.first.fitted, overflows.first.overflow]
    end
  end

  # リードの頭の字の並びが前のページにも出る（前の部の終わりで次の部を案内する文）。
  # 最初に見つかったページで照合をあきらめず、章扉のページを探し当てる
  def test_should_find_frontispiece_when_lead_head_also_appears_earlier
    require_pdftotext
    Dir.mktmpdir do |dir|
      pdf = File.join(dir, 'book.pdf')
      Prawn::Document.generate(pdf, page_size: 'A5', margin: 40) do |doc|
        doc.draw_text 'The previous part ends. Next:', at: [0, 480]
        doc.draw_text LEAD_LINES[0], at: [0, 460]
        doc.start_new_page
        doc.draw_text 'Chapter 1', at: [0, 500], size: 20
        LEAD_LINES.first(3).each_with_index { |line, i| doc.draw_text line, at: [0, 440 - (i * 20)] }
        doc.start_new_page
        doc.draw_text LEAD_LINES[3], at: [0, 480]
      end

      overflows = ChapterLeadCheck.scan(pdf, [LEAD])

      assert_equal [[3, 1]], overflows.map { [it.fitted, it.overflow] }
    end
  end

  def test_should_find_nothing_when_lead_fits_on_frontispiece
    require_pdftotext
    Dir.mktmpdir do |dir|
      pdf = write_pdf(File.join(dir, 'book.pdf'), on_first_page: 4)

      assert_empty ChapterLeadCheck.scan(pdf, [LEAD])
    end
  end

  # リードの文が PDF の文字と合わない章は、誤った警告を出さないよう黙って飛ばす（§4.2）
  def test_should_skip_lead_not_found_in_pdf
    require_pdftotext
    Dir.mktmpdir do |dir|
      pdf = write_pdf(File.join(dir, 'book.pdf'), on_first_page: 3)
      other = Lead.new(path: 'contents/20-b.md', title: 'B', paragraphs: ['this lead text is not in the pdf at all'])

      assert_empty ChapterLeadCheck.scan(pdf, [other])
    end
  end

  # --- 組んだ HTML からリードを取る ---

  # 章扉のある章（vs-header-image）だけ。付録（vs-header-simple）とリードの無い章は取らない
  def test_should_collect_leads_only_from_chapters_with_frontispiece
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        html_dir = VivlioStarter::CLI::Common::BUILD_HTML_DIR
        FileUtils.mkdir_p(html_dir)
        File.write(File.join(html_dir, '10-a.html'), <<~HTML)
          <html><body class="chapter vs-header-image"><h1 data-chapter-title="第1部　基礎編">x</h1>
          <div class="chapter-lead"><p>最初の段落です。</p><p>二つ目の
          段落です。</p></div></body></html>
        HTML
        File.write(File.join(html_dir, '90-b.html'), <<~HTML)
          <html><body class="chapter vs-header-simple"><h1>付録</h1><div class="chapter-lead"><p>付録のリード。</p></div></body></html>
        HTML
        File.write(File.join(html_dir, '20-c.html'), '<html><body class="chapter vs-header-image"><h1>C</h1><p>本文</p></body></html>')

        entries = %w[10-a 90-b 20-c 30-missing].map { FakeEntry.new(basename: it, path: "contents/#{it}.md") }
        leads = ChapterLeadCheck.collect_leads(entries)

        assert_equal [Lead.new(path: 'contents/10-a.md', title: '第1部　基礎編', paragraphs: ['最初の段落です。', '二つ目の 段落です。'])],
                     leads
      end
    end
  end

  # --- 直し方の案 ---

  # 3 段落 × 164 字（頭の字下げ込み）。1 行は字数より 0.5 字少なく見積もるので、24 字で 164 / 23.5
  # → 7 行 × 3 = 21 行。章扉には 18 行しか入らない。
  #   大きさだけ: 21 行 × 倍率 / 1.2 ≤ 18 → 1.028 → 0.05 刻みで 1.0
  #   字数だけ:   1 段落 6 行以下（164 / 27.5 = 5.96）→ 28 字
  #   組:         1.05 倍・28 字（幅はそのまま）で 6 行 × 3 = 18 行、高さは 1.05 / 1.2
  def test_should_suggest_size_chars_and_pair_that_fit
    overflow = Overflow.new(lead: Lead.new(path: 'p', title: 't', paragraphs: ['あ' * 163] * 3), fitted: 18, overflow: 3)

    found = ChapterLeadCheck.suggestions([overflow], size: 1.2, chars: 24, max_chars: ->(_) { 36 })

    assert_equal({ size: 1.0, chars: 28, pair: [1.05, 28] }, found)
  end

  # 段落の最後の行がぎりぎり満杯になる字数は、行が空く分を見込んで 1 行多く数える。
  # 満杯で数えた 25 字・248 字（9.92 行 → 10 行）の案は、組むと 11 行になった（spiral-ruby の 33 章）
  def test_should_count_line_loss_from_line_breaking_rules
    assert_equal 11, ChapterLeadCheck.estimated_lines(['あ' * 247], 25)
  end

  # 組が大きさだけの案より小さくならないなら、組は出さない（大きさだけで足りる）
  def test_should_drop_pair_that_needs_no_larger_size_than_size_alone
    overflow = Overflow.new(lead: Lead.new(path: 'p', title: 't', paragraphs: ['あ' * 187] * 3), fitted: 21, overflow: 3)

    found = ChapterLeadCheck.suggestions([overflow], size: 1.2, chars: 24, max_chars: ->(_) { 36 })

    assert_equal({ size: 1.05, chars: 28, pair: nil }, found)
  end

  # 1.0 を下回る倍率・版面を超える字数は出さない。どれも出せなければ縮める案だけになる
  def test_should_not_suggest_below_minimum_size_or_wider_than_text_area
    overflow = Overflow.new(lead: Lead.new(path: 'p', title: 't', paragraphs: ['あ' * 163] * 3), fitted: 10, overflow: 11)

    found = ChapterLeadCheck.suggestions([overflow], size: 1.2, chars: 24, max_chars: ->(_) { 36 })

    assert_equal({ size: nil, chars: nil, pair: nil }, found)
  end

  # 案は、はみ出したすべての章が収まる値（キーは本全体に効くので、章ごとには書けない）
  def test_should_suggest_values_that_fit_every_overflowing_chapter
    mild = Overflow.new(lead: Lead.new(path: 'p', title: 't', paragraphs: ['あ' * 163] * 3), fitted: 20, overflow: 1)
    severe = Overflow.new(lead: Lead.new(path: 'q', title: 'u', paragraphs: ['あ' * 163] * 3), fitted: 18, overflow: 3)

    found = ChapterLeadCheck.suggestions([mild, severe], size: 1.2, chars: 24, max_chars: ->(_) { 36 })

    assert_equal ChapterLeadCheck.suggestions([severe], size: 1.2, chars: 24, max_chars: ->(_) { 36 }), found
  end

  # 実際の行数が見積もり（24 字で 24 行）より多いとき（禁則・半角の字）は、その比で案を厳しくする。
  # 25 行なら大きさは 1.2 × 21 / 25 = 1.008 → 1.0、字数は見積もりが 25 / 24 倍されるので 1 段落 6 行（32 字）まで要る
  def test_should_scale_estimate_by_actual_line_count
    estimated = Overflow.new(lead: Lead.new(path: 'p', title: 't', paragraphs: ['あ' * 187] * 3), fitted: 21, overflow: 3)
    longer = Overflow.new(lead: Lead.new(path: 'p', title: 't', paragraphs: ['あ' * 187] * 3), fitted: 21, overflow: 4)

    as_estimated = ChapterLeadCheck.suggestions([estimated], size: 1.2, chars: 24, max_chars: ->(_) { 36 })
    as_longer = ChapterLeadCheck.suggestions([longer], size: 1.2, chars: 24, max_chars: ->(_) { 36 })

    assert_equal [1.05, 28], [as_estimated[:size], as_estimated[:chars]]
    assert_equal [1.0, 32], [as_longer[:size], as_longer[:chars]]
  end

  # --- 知らせ ---

  def test_should_warn_with_cut_chars_and_book_yml_suggestions
    overflow = Overflow.new(lead: Lead.new(path: 'contents/33-net.md', title: '第7部　通信・システム編',
                                           paragraphs: ['あ' * 163] * 3), fitted: 18, overflow: 3)
    current = { size: 1.2, chars: 24, size_written: false, chars_written: true, max_chars: ->(_) { 36 } }
    warned = []

    ChapterLeadCheck.stub(:current_metrics, current) do
      VivlioStarter::CLI::Common.stub(:log_warn, ->(msg, detail: nil) { warned << [msg, detail] }) do
        ChapterLeadCheck.warn_overflows([overflow])
      end
    end

    message, detail = warned.first
    assert_equal 'リードが章扉に収まらず、次のページへ送られている章があります（1 章）', message
    assert_equal <<~DETAIL.chomp, detail
      contents/33-net.md（第7部　通信・システム編）: 3 行が次のページへ。リードを 80 字ほど縮める
      book.yml で直すなら、次のどれか 1 つ:
        theme.frontispiece.lead_size: （空欄） → 1.0
        theme.frontispiece.lead_chars: 24 → 28
        theme.frontispiece.lead_size: （空欄） → 1.05 と lead_chars: 24 → 28（リードの幅はそのまま）
    DETAIL
  end

  # 既定の字数のままなら「20（既定）」と見せる
  def test_should_show_default_chars_when_not_written
    current = { size: 1.1, chars: 20, size_written: true, chars_written: false }

    lines = ChapterLeadCheck.suggestion_lines({ size: 1.05, chars: 22, pair: nil }, current)

    assert_equal ['theme.frontispiece.lead_size: 1.1 → 1.05', 'theme.frontispiece.lead_chars: 20（既定） → 22'], lines
  end

  def test_should_format_size_with_one_or_two_decimals
    assert_equal %w[1.0 1.05 1.1 1.15], [1.0, 1.05, 1.1, 1.15].map { ChapterLeadCheck.format_size(it) }
  end
end
