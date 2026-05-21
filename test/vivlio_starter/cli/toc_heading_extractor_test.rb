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
