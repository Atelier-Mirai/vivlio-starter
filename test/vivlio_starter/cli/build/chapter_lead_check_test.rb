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
require_relative '../../../../lib/vivlio_starter/cli/build/chapter_lead_check'

class TestChapterLeadCheck < Minitest::Test
  ChapterLeadCheck = VivlioStarter::CLI::Build::ChapterLeadCheck
  Estimate = VivlioStarter::CLI::Build::FrontispieceEstimate
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
  LEAD = Lead.new(path: 'contents/10-a.md', title: 'Chapter 1', paragraphs: [LEAD_LINES.join(' ')], chapter: nil)

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

  # 行の途中に数式の画像があると、pdftotext は画像の前と後ろを別の行として出す。高さのそろった行は
  # 1 行として数える（まとめないと、spiral-ruby の 22 章で 22 行の送りを 24 行と言っていた）
  def test_should_join_line_split_by_image
    lines = [[0, 300.2, 250.0, %q(だけずれます。)], [0, 300.0, 200.0, %q(もとの点から)], [0, 320.0, 200.0, %q(次の行)]]

    assert_equal [[0, %q(もとの点からだけずれます。)], [0, %q(次の行)]], ChapterLeadCheck.same_height_joined(lines)
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
      other = Lead.new(path: 'contents/20-b.md', title: 'B', paragraphs: ['this lead text is not in the pdf at all'], chapter: nil)

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

        assert_equal [['contents/10-a.md', '第1部　基礎編', ['最初の段落です。', '二つ目の 段落です。']]],
                     leads.map { [it.path, it.title, it.paragraphs] }
        # 見積もりには、段落の HTML をそのまま渡す（インラインコードや太字で字の幅が変わる）
        assert_equal ['最初の段落です。', "二つ目の\n段落です。"], leads.first.chapter.paragraphs
      end
    end
  end

  # --- 直し方の案 ---
  #
  # 案の選び方（倍率の並べ方・落とし方）を確かめる。収まるかの見積もりは FrontispieceEstimate の
  # 仕事なので、ここでは単純な式に差し替える: 段落ごとに ceil(字数 / 1 行の字数) 行、章扉には
  # 1.2 倍のときの行数 × 1.2 / 倍率 行入る（行の高さは字の大きさに比例する）

  # 段落の字数と、1.2 倍で章扉に入る行数を持つ、見積もり用の章
  FakeChapter = Data.define(:paragraph_chars, :capacity_at_default)

  def overflow_of(paragraph_chars, capacity, path: 'p')
    chapter = FakeChapter.new(paragraph_chars:, capacity_at_default: capacity)
    Overflow.new(lead: Lead.new(path:, title: 't', paragraphs: [], chapter:), fitted: capacity, overflow: 1)
  end

  def fake_layout(chapter, _page, size:, chars:)
    lines = chapter.paragraph_chars.sum { (it.to_f / chars).ceil }
    capacity = ((chapter.capacity_at_default * 1.2 / size) + 1e-9).floor
    Estimate::Layout.new(lines:, capacity:, fitted: [lines, capacity].min)
  end

  def suggest(overflows, size: 1.2, chars: 24)
    Estimate.stub(:layout, method(:fake_layout)) do
      ChapterLeadCheck.suggestions(overflows, size:, chars:, max_chars: ->(_) { 36 }, page: :page)
    end
  end

  # 3 段落 × 164 字・章扉に 18 行。24 字で 7 行 × 3 = 21 行
  #   1.2 倍のまま: 1 段落 6 行以下 → 28 字
  #   1.1 倍:       19 行まで → 1 段落 6 行 → 28 字（字が小さくなるだけなので出さない）
  #   大きさだけ:   21 行入るのは 1.0 倍（18 × 1.2 / 1.05 = 20.6 行）
  def test_should_suggest_least_chars_for_each_size
    assert_equal [[1.2, 28], [1.0, 24]], suggest([overflow_of([164] * 3, 18)])
  end

  # はみ出しが大きく、大きさだけでは収まらないとき（1.0 倍でも 17% しか縮まない）も、
  # 0.1 刻みの倍率ごとに、収まる字数を添えて出す。3 段落 × 164 字・14 字で 39 行、章扉には 24 行
  #   1.2 倍: 1 段落 8 行 → 21 字
  #   1.1 倍: 26 行まで → 1 段落 8 行 → 21 字（減らないので出さない）
  #   1.0 倍: 28 行まで → 1 段落 9 行 → 19 字
  def test_should_suggest_smaller_sizes_with_more_chars_when_size_alone_is_not_enough
    assert_equal [[1.2, 21], [1.0, 19]], suggest([overflow_of([164] * 3, 24)], chars: 14)
  end

  # 字数を変えずに収まる倍率（大きさだけ）より下の倍率は、字を小さくするだけなので出さない。
  # 3 段落 × 188 字・24 字で 24 行、章扉に 21 行 → 1.2 倍のままなら 1 段落 7 行の 27 字、1.05 倍で 24 行入る
  def test_should_stop_at_size_that_fits_without_more_chars
    assert_equal [[1.2, 27], [1.05, 24]], suggest([overflow_of([188] * 3, 21)])
  end

  # 1.0 を下回る倍率・版面を超える字数は出さない。どれも出せなければ縮める案だけになる
  def test_should_not_suggest_below_minimum_size_or_wider_than_text_area
    assert_empty suggest([overflow_of([164] * 3, 10)])
  end

  # 案は、はみ出したすべての章が収まる値（キーは本全体に効くので、章ごとには書けない）
  def test_should_suggest_values_that_fit_every_overflowing_chapter
    mild = overflow_of([164] * 3, 20)
    severe = overflow_of([164] * 3, 18, path: 'q')

    assert_equal suggest([severe]), suggest([mild, severe])
  end

  # 今の倍率では、今の字数を案にしない。build の PDF ではみ出した章を、見積もりが「収まる」と
  # 言っても（見積もりの外れ）、今の組ではみ出したことは分かっている
  def test_should_not_suggest_current_combination
    fits_now = overflow_of([100] * 3, 18) # 24 字で 15 行。見積もりでは収まる

    found = suggest([fits_now])

    refute_includes found, [1.2, 24]
    assert_equal [1.2, 25], found.first
  end

  # --- 知らせ ---

  def test_should_warn_with_cut_chars_and_book_yml_suggestions
    overflow = Overflow.new(lead: Lead.new(path: 'contents/33-net.md', title: '第7部　通信・システム編', paragraphs: [],
                                           chapter: FakeChapter.new(paragraph_chars: [164] * 3, capacity_at_default: 18)),
                            fitted: 18, overflow: 3)
    current = { size: 1.2, chars: 24, size_written: false, chars_written: true, max_chars: ->(_) { 36 } }
    warned = []

    ChapterLeadCheck.stub(:current_metrics, current) do
      Estimate.stub(:layout, method(:fake_layout)) do
        VivlioStarter::CLI::Common.stub(:log_warn, ->(msg, detail: nil) { warned << [msg, detail] }) do
          ChapterLeadCheck.warn_overflows([overflow], page: :page)
        end
      end
    end

    message, detail = warned.first
    assert_equal 'リードが章扉に収まらず、次のページへ送られている章があります（1 章）', message
    assert_equal <<~DETAIL.chomp, detail
      contents/33-net.md（第7部　通信・システム編）: 3 行が次のページへ。リードを 80 字ほど縮める
      book.yml の theme.frontispiece を次の組み合わせのどれかにすると、すべての章が章扉に収まります:
        lead_size: （空欄） のまま・lead_chars: 24 → 28
        lead_size: （空欄） → 1.0・lead_chars: 24 のまま
    DETAIL
  end

  # 書体が見つからず見積もれないときは、直し方の案を添えない（章ごとの縮める字数は出す）
  def test_should_warn_without_suggestions_when_estimate_is_unavailable
    overflow = Overflow.new(lead: Lead.new(path: 'contents/33-net.md', title: 'T', paragraphs: [], chapter: nil),
                            fitted: 18, overflow: 3)
    current = { size: 1.2, chars: 24, size_written: false, chars_written: true, max_chars: ->(_) { 36 } }
    warned = []

    ChapterLeadCheck.stub(:current_metrics, current) do
      VivlioStarter::CLI::Common.stub(:log_warn, ->(msg, detail: nil) { warned << [msg, detail] }) do
        ChapterLeadCheck.warn_overflows([overflow], page: nil)
      end
    end

    assert_equal 'contents/33-net.md（T）: 3 行が次のページへ。リードを 80 字ほど縮める', warned.first.last
  end

  # preflight: 見積もりではみ出す章を、build と同じ形で知らせる
  def test_should_estimate_overflows_without_pdf
    chapter = Estimate::Chapter.new(path: 'contents/10-a.md', title: '第1部　基礎編', numbered: false, segments: [],
                                    paragraphs: [])
    current = { size: 1.2, chars: 24, chars_setting: 24, size_written: true, chars_written: true, max_chars: ->(_) { 36 } }
    over = Estimate::Layout.new(lines: 30, capacity: 26, fitted: 25)
    fits = Estimate::Layout.new(lines: 20, capacity: 26, fitted: 20)
    warned = []

    ChapterLeadCheck.stub(:image_style?, true) do
      Estimate.stub(:current_page, :page) do
        Estimate.stub(:chapters_from_markdown, [chapter]) do
          Estimate.stub(:layout, ->(_c, _p, size:, chars:) { size == 1.2 && chars == 24 ? over : fits }) do
            ChapterLeadCheck.stub(:current_metrics, current) do
              VivlioStarter::CLI::Common.stub(:log_warn, ->(msg, detail: nil) { warned << [msg, detail] }) do
                overflows = ChapterLeadCheck.estimate!([])

                assert_equal [[25, 5]], overflows.map { [it.fitted, it.overflow] }
              end
            end
          end
        end
      end
    end

    assert_includes warned.first.last, 'contents/10-a.md（第1部　基礎編）: 5 行が次のページへ。リードを 120 字ほど縮める'
    # preflight の章別サマリーにも数える
    assert_equal 1, VivlioStarter::CLI::PreProcessCommands::IssueRegistry.summary_by_chapter['10-a'].warns
  ensure
    VivlioStarter::CLI::PreProcessCommands::IssueRegistry.reset!
  end

  # 案が 1 つだけなら「どれか」とは書かない
  def test_should_word_heading_for_single_suggestion
    assert_equal 'book.yml の theme.frontispiece をこう変えると、すべての章が章扉に収まります:',
                 ChapterLeadCheck.suggestion_heading(1)
  end

  # 既定の字数のままなら「20（既定）」と見せる
  def test_should_show_default_chars_when_not_written
    current = { size: 1.1, chars: 20, size_written: true, chars_written: false }

    lines = ChapterLeadCheck.suggestion_lines([[1.1, 22], [1.05, 20]], current)

    assert_equal ['lead_size: 1.1 のまま・lead_chars: 20（既定） → 22', 'lead_size: 1.1 → 1.05・lead_chars: 20（既定） のまま'], lines
  end

  def test_should_format_size_with_one_or_two_decimals
    assert_equal %w[1.0 1.05 1.1 1.15], [1.0, 1.05, 1.1, 1.15].map { ChapterLeadCheck.format_size(it) }
  end
end
