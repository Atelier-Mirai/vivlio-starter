# frozen_string_literal: true

# ================================================================
# Test: toc_heading_extractor_test.rb
# ================================================================
# テスト対象:
#   TocCommands::HeadingExtractor（lib/vivlio_starter/cli/toc.rb）
#
# 検証内容:
#   - Entry#kind に基づく見出し抽出の動作確認
#   - chapter/appendix/その他のファイルタイプに応じた見出し選択
#   - css_class_for が Entry#kind を正しく参照すること
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/toc'
require 'vivlio_starter/cli/token_resolver'
require 'vivlio_starter/cli/post_process/replacement_rules'

module VivlioStarter
  module CLI
    class TocHeadingExtractorTest < Minitest::Test
      def setup
        @tmpdir = Dir.mktmpdir
      end

      def teardown
        FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
      end

      # chapter ファイルは h1, h2, h3 を抽出する
      def test_chapter_extracts_h1_h2_h3
        html_file = create_html_file('11-sample.html', <<~HTML)
          <html><body>
            <h1 id="title">Chapter Title</h1>
            <h2 id="sec1">Section 1</h2>
            <h3 id="sub1">Subsection 1</h3>
          </body></html>
        HTML

        entry = make_entry('11-sample', kind: :chapter)
        extractor = TocCommands::HeadingExtractor.new(html_file, entry)
        headings = extractor.headings

        assert_equal 3, headings.size
        assert_equal 'Chapter Title', headings[0].text
        assert_equal 'Section 1', headings[1].text
        assert_equal 'Subsection 1', headings[2].text
      end

      # appendix ファイルは h1, h2 のみ抽出する
      def test_appendix_extracts_h1_h2_only
        html_file = create_html_file('91-appendix.html', <<~HTML)
          <html><body>
            <h1 id="title">Appendix Title</h1>
            <h2 id="sec1">Section 1</h2>
            <h3 id="sub1">Subsection 1</h3>
          </body></html>
        HTML

        entry = make_entry('91-appendix', kind: :appendix)
        extractor = TocCommands::HeadingExtractor.new(html_file, entry)
        headings = extractor.headings

        assert_equal 2, headings.size
        assert_equal 'Appendix Title', headings[0].text
        assert_equal 'Section 1', headings[1].text
      end

      # preface ファイルは h1 のみ抽出する
      def test_preface_extracts_h1_only
        html_file = create_html_file('00-preface.html', <<~HTML)
          <html><body>
            <h1 id="title">Preface Title</h1>
            <h2 id="sec1">Section 1</h2>
            <h3 id="sub1">Subsection 1</h3>
          </body></html>
        HTML

        entry = make_entry('00-preface', kind: :preface)
        extractor = TocCommands::HeadingExtractor.new(html_file, entry)
        headings = extractor.headings

        assert_equal 1, headings.size
        assert_equal 'Preface Title', headings[0].text
      end

      # page.toc_depth: 2 では本文の章も節（h2）までにする。目次が 16 ページあった本書を
      # 節までにして詰めるための設定（改善案 #107）
      def test_should_stop_at_sections_when_depth_is_two
        html_file = create_html_file('11-sample.html', <<~HTML)
          <html><body>
            <h1 id="title">Chapter Title</h1>
            <h2 id="sec1">Section 1</h2>
            <h3 id="sub1">Subsection 1</h3>
          </body></html>
        HTML

        chapter = TocCommands::HeadingExtractor.new(html_file, make_entry('11-sample', kind: :chapter), depth: 2)
        only_h1 = TocCommands::HeadingExtractor.new(html_file, make_entry('11-sample', kind: :chapter), depth: 1)

        assert_equal ['Chapter Title', 'Section 1'], chapter.headings.map(&:text)
        assert_equal ['Chapter Title'], only_h1.headings.map(&:text)
      end

      # 付録は toc_depth: 3 でも節までのまま。深さを上げても項は載らない
      def test_should_keep_appendix_at_sections_even_when_depth_is_three
        html_file = create_html_file('91-appendix.html', <<~HTML)
          <html><body>
            <h1 id="title">Appendix Title</h1>
            <h2 id="sec1">Section 1</h2>
            <h3 id="sub1">Subsection 1</h3>
          </body></html>
        HTML

        appendix = TocCommands::HeadingExtractor.new(html_file, make_entry('91-appendix', kind: :appendix), depth: 3)
        only_h1 = TocCommands::HeadingExtractor.new(html_file, make_entry('91-appendix', kind: :appendix), depth: 1)

        assert_equal ['Appendix Title', 'Section 1'], appendix.headings.map(&:text)
        assert_equal ['Appendix Title'], only_h1.headings.map(&:text)
      end

      # 不正な値は既定の 3 に戻し、直し方を添えて知らせる
      def test_should_fall_back_to_default_depth_with_warning_for_invalid_value
        warnings = []

        depths = Common.stub(:log_warn, ->(msg) { warnings << msg }) do
          [4, 'two', 2, '2', nil].map { TocCommands::HeadingExtractor.configured_depth(it) }
        end

        assert_equal [3, 3, 2, 2, 3], depths
        assert_equal 2, warnings.size, '空欄は既定で黙って通し、4 と two だけ知らせる'
        assert_includes warnings.first, 'after : toc_depth: 3'
      end

      # chapter の h1 は toc-chapter クラスを持つ
      def test_chapter_h1_has_toc_chapter_class
        html_file = create_html_file('11-sample.html', <<~HTML)
          <html><body>
            <h1 id="title">Chapter Title</h1>
          </body></html>
        HTML

        entry = make_entry('11-sample', kind: :chapter)
        extractor = TocCommands::HeadingExtractor.new(html_file, entry)
        headings = extractor.headings

        assert_equal 'toc-chapter', headings[0].css_class
      end

      # appendix の h1 は toc-chapter-appendix クラスを持つ
      def test_appendix_h1_has_toc_chapter_appendix_class
        html_file = create_html_file('91-appendix.html', <<~HTML)
          <html><body>
            <h1 id="title">Appendix Title</h1>
          </body></html>
        HTML

        entry = make_entry('91-appendix', kind: :appendix)
        extractor = TocCommands::HeadingExtractor.new(html_file, entry)
        headings = extractor.headings

        assert_equal 'toc-chapter-appendix', headings[0].css_class
      end

      # preface の h1 は toc-chapter-no-number クラスを持つ
      def test_preface_h1_has_toc_chapter_no_number_class
        html_file = create_html_file('00-preface.html', <<~HTML)
          <html><body>
            <h1 id="title">Preface Title</h1>
          </body></html>
        HTML

        entry = make_entry('00-preface', kind: :preface)
        extractor = TocCommands::HeadingExtractor.new(html_file, entry)
        headings = extractor.headings

        assert_equal 'toc-chapter-no-number', headings[0].css_class
      end

      # システムファイル（_titlepage）も正しく処理される
      def test_system_file_titlepage
        html_file = create_html_file('_titlepage.html', <<~HTML)
          <html><body>
            <h1 id="title">Book Title</h1>
          </body></html>
        HTML

        entry = make_entry('_titlepage', kind: :titlepage)
        extractor = TocCommands::HeadingExtractor.new(html_file, entry)
        headings = extractor.headings

        assert_equal 1, headings.size
        assert_equal 'toc-chapter-no-number', headings[0].css_class
      end

      # 見出しのインラインコードは目次でも <code> のまま載せる。文字だけにすると、目次の HTML を
      # 後処理が通るときに `〘 〙` がキーキャップ（<kbd>）に、`@pagebreak` が改ページの指示に化けた
      # （2026-10-12・本書の目次で発覚。<kbd> の空白だけが OS の等幅 Osaka-Mono で埋め込まれていた）。
      def test_should_keep_inline_code_so_post_processing_leaves_it_alone
        html_file = create_html_file('11-sample.html', <<~HTML)
          <html><body>
            <h1 id="title"><span class="chapter-title">Q&amp;A と &lt;br&gt;</span></h1>
            <h3 id="kbd"><span class="subsection-marker">♣</span><span class="subsection-title"><code>〘 〙</code> — キーを示す</span></h3>
            <h3 id="pb"><span class="subsection-marker">♣</span><span class="subsection-title"><code>@pagebreak</code> — 改ページする</span></h3>
          </body></html>
        HTML
      
        headings = TocCommands::HeadingExtractor.new(html_file, make_entry('11-sample', kind: :chapter)).headings
        toc_file = create_html_file('_toc.html', headings.map(&:list_markup).join("\n"))
        PostProcessCommands::HtmlReplacer.process_html_file(toc_file, PostProcessCommands::ReplacementRules::ALL)
        toc = File.read(toc_file, encoding: 'utf-8')
      
        assert_equal 'Q&amp;A と &lt;br&gt;', headings[0].text, '文字は HTML として逃がす'
        assert_equal '<code>〘 〙</code> — キーを示す', headings[1].text
        assert_equal '<code>@pagebreak</code> — 改ページする', headings[2].text
        refute_includes toc, '<kbd>'
        refute_includes toc, 'vs-break-page'
      end
      
      # 用語集の † リンクは目次に載せない。目次はその語を説明する場所ではなく、記号だけが残る。
      def test_should_drop_glossary_marks_from_toc
        html_file = create_html_file('11-sample.html', <<~HTML)
          <html><body>
            <h1 id="title"><span class="chapter-title">扉絵<a id="g1" class="glossary-link" href="_glossarypage.html#gls-a"><sup>†</sup></a>と装飾画像<a id="g2" class="glossary-link" href="_glossarypage.html#gls-b"><sup>†</sup></a></span></h1>
          </body></html>
        HTML

        headings = TocCommands::HeadingExtractor.new(html_file, make_entry('11-sample', kind: :chapter)).headings

        assert_equal '扉絵と装飾画像', headings[0].text
      end

      private

      def create_html_file(filename, content)
        path = File.join(@tmpdir, filename)
        File.write(path, content, encoding: 'utf-8')
        path
      end

      def make_entry(basename, kind:)
        num = basename[/\A(\d+)/, 1] || '00'
        slug = basename.sub(/\A\d+-?/, '')
        TokenResolver::Entry.new(
          number: num,
          slug: slug.empty? ? basename : slug,
          kind: kind,
          label: basename,
          path: "contents/#{basename}.md",
          exists: true,
          in_catalog: true,
          valid: true
        )
      end
    end
  end
end
