# frozen_string_literal: true

# ================================================================
# Test: build/frontispiece_estimate_test.rb
# ================================================================
# 章扉のリードが章扉に収まるかを、組まずに見積もる（FrontispieceEstimate・chapter-lead-size-spec.md §4.4）。
# 寸法の期待値は、spiral-ruby の版面（A4・天地 20mm・本文 10.5pt・見出しの下げ量 15mm）で組んだ実物から取った。
#   章題 1 行のリードの始まり: 75.36mm（計算 75.4mm）、1.2 倍で章扉に入る行: 26 行
# ================================================================

require_relative '../../../test_helper'
require 'tmpdir'
require_relative '../../../../lib/vivlio_starter/cli/common'
require_relative '../../../../lib/vivlio_starter/cli/pre_process/book_settings_css'
require_relative '../../../../lib/vivlio_starter/cli/pre_process/cross_reference_processor'
require_relative '../../../../lib/vivlio_starter/cli/build/frontispiece_estimate'

class TestFrontispieceEstimate < Minitest::Test
  Estimate = VivlioStarter::CLI::Build::FrontispieceEstimate
  LeadLayout = VivlioStarter::CLI::Build::LeadLayout
  FontMetrics = VivlioStarter::CLI::Build::FontMetrics
  HeadingSegmenter = VivlioStarter::CLI::HeadingSegmenter
  FONTS = File.expand_path('../../../../stylesheets/fonts', __dir__)
  FakeEntry = Data.define(:basename, :path, :kind)

  # spiral-ruby の版面（A4・a4_compact）
  def page
    body = FontMetrics.load("#{FONTS}/Noto_Serif_JP/NotoSerifJP-Regular.ttf")
    Estimate::Page.new(height: 297.0, margin_top: 20.0, margin_bottom: 20.0, scale: 1.0, base_font_mm: 10.5 * 25.4 / 72,
                       base_line_mm: 15.75 * 25.4 / 72, text_width: 162.0, heading_offset: 15.0, heading_width: 129.6,
                       lead_width: ->(size, chars) { (chars * 10.5 * 25.4 / 72 * size).round(2) },
                       fonts: LeadLayout::Fonts.new(body:, bold: nil, code: nil),
                       title_font: FontMetrics.load("#{FONTS}/Noto_Sans_JP/NotoSansJP-Bold.ttf"))
  end

  def chapter(numbered: false, paragraphs: ['あ' * 100])
    Estimate::Chapter.new(path: 'contents/11-a.md', title: '第1部　基礎編', numbered:, segments: %w[第1部 　 基礎 編],
                          paragraphs:)
  end

  # --- 章扉の寸法 ---

  # 天 20 + 下げ量 15 + 内余白 6 + grid の行間 2 + 章題 12 × 1.45 + 章題の下 4 + 内余白 6 + リードの上 5
  def test_should_add_up_frontispiece_heights_to_lead_top
    assert_in_delta 75.4, Estimate.lead_top(chapter, page), 1e-9
  end

  # 章番号の行（上の余白 10 + 行送り 15.75pt + 下の内余白 3）が加わる
  def test_should_add_chapter_number_row
    assert_in_delta 75.4 + 10 + (15.75 * 25.4 / 72) + 3, Estimate.lead_top(chapter(numbered: true), page), 1e-9
  end

  # (297 − 20 − 75.4) / (10.5pt × 1.2 × 1.7) = 26.7 → 26 行
  def test_should_count_lines_that_fit_on_frontispiece
    layout = Estimate.layout(chapter(paragraphs: ['あ' * 100] * 3), page, size: 1.2, chars: 14)

    assert_equal 26, layout.capacity
    assert_equal 24, layout.lines # 1 字下げ込みで 101 字 → 8 行 × 3
    assert layout.fits?
  end

  # --- 章扉に残る行（widows・orphans） ---

  def test_should_keep_two_lines_on_each_side_of_page_break
    assert_equal 20, Estimate.fitted_lines([7, 15, 6], 20) # 2 段落目を 13 行と 2 行に割る
    assert_equal 19, Estimate.fitted_lines([10, 11], 20)   # 次のページへ 1 行だけは送らない
    assert_equal 19, Estimate.fitted_lines([19, 5], 20)    # 章扉に 1 行だけは残さない
    assert_equal 12, Estimate.fitted_lines([12], 20)       # 収まる
  end

  # --- リードの幅 ---

  # BookSettingsCss が CSS に書く値と同じ（小数 2 桁）。字数も倍率も既定なら theme.css の既定の幅
  def test_should_resolve_lead_width_like_book_settings_css
    page_cfg = { base_font_size: '10.5pt' }

    assert_in_delta 62.23, Estimate.lead_width_mm(page_cfg, 1.2, 14), 1e-9
    assert_in_delta 88.9, Estimate.lead_width_mm(page_cfg, 1.2, nil), 1e-9
    assert_in_delta 81.49, Estimate.lead_width_mm(page_cfg, 1.1, nil), 1e-9
  end

  # --- 原稿から取り出す ---

  # 前処理を終えた原稿（html/*.md）から、章題・リードの段落・章番号の有無を取る。
  # 段落の中の改行は空白に、インラインコードは <code> にする（字の幅が変わる）
  def test_should_read_chapter_from_preprocessed_markdown
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        html_dir = VivlioStarter::CLI::Common::BUILD_HTML_DIR
        FileUtils.mkdir_p(html_dir)
        File.write(File.join(html_dir, '11-a.md'), <<~MD)
          # 第1部　<span class="index-term">基礎</span>編 <span id="ch-a" class="vs-sec-anchor"></span>

          :::{.chapter-lead}
          段落の`code`は
          続きます。

          二つ目の**段落**。
          :::

          ## 課題1
        MD
        entries = [FakeEntry.new(basename: '11-a', path: 'contents/11-a.md', kind: :chapter),
                   FakeEntry.new(basename: '90-b', path: 'contents/90-b.md', kind: :appendix)]

        chapters = VivlioStarter::CLI::PreProcessCommands::CrossReferenceProcessor.stub(:chapter_number_text_for, '第1章') do
          HeadingSegmenter.stub(:segment, ->(text) { [text] }) { Estimate.chapters_from_markdown(entries) }
        end

        assert_equal 1, chapters.size
        found = chapters.first
        assert_equal ['contents/11-a.md', '第1部　基礎編', true], [found.path, found.title, found.numbered]
        assert_equal ['段落の<code>code</code>は 続きます。', '二つ目の<strong>段落</strong>。'], found.paragraphs
      end
    end
  end

  def test_should_convert_inline_markdown_that_changes_widths
    assert_equal '<code>a &lt; b</code>・<strong>太</strong>・リンク・漢字・*',
                 Estimate.inline_html('`a < b`・**太**・[リンク](https://example.com)・{漢字|かんじ}・\*')
  end

  # 章題の文節: 文字のかたまりごとに語へ分け、用語集の印は "†"、章題の後ろの目印は除く
  def test_should_segment_title_by_text_runs
    html = '第2部　<span class="index-term">オブジェクト指向</span><a class="glossary-link"><sup>†</sup></a>編 ' \
           '<span class="vs-sec-anchor"></span>'

    segments = HeadingSegmenter.stub(:segment, ->(text) { [text] }) { Estimate.title_segments(html) }

    assert_equal ['第2部　', 'オブジェクト指向', '†', '編 '], segments
  end

  # 組んだ HTML では、HeadingProcessor が付けた .vs-nobr をそのまま文節にする
  def test_should_take_nobr_spans_as_segments_from_built_html
    html = '<span class="vs-nobr">相互</span><span class="vs-nobr">参照</span>（' \
           '<dfn class="index-term"><span class="vs-nobr">クロス</span></dfn>）'

    segments = HeadingSegmenter.stub(:segment, ->(text) { [text] }) { Estimate.title_segments(html) }

    assert_equal %w[相互 参照 （ クロス ）], segments
  end
end
