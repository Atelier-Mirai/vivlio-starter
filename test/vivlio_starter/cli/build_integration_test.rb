# frozen_string_literal: true

# ================================================================
# Test: build_integration_test.rb
# ================================================================
# テスト対象:
#   vs build コマンドの統合テスト
#
# 検証内容:
#   - ビルドパイプラインの各ステップが Entry#kind を正しく使用すること
#   - システムファイル（_toc, _titlepage 等）の処理が正しく動作すること
#   - pre_process / post_process / toc が Entry を正しく受け取ること
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build'
require 'vivlio_starter/cli/pre_process'
require 'vivlio_starter/cli/post_process'
require 'vivlio_starter/cli/toc'
require 'vivlio_starter/cli/token_resolver'

module VivlioStarter
  module CLI
    # TokenResolver のシステムファイル解決テスト
    class TokenResolverSystemFileTest < Minitest::Test
      def test_resolve_toc_file
        resolver = TokenResolver::Resolver.new
        entry = resolver.resolve(['_toc']).first

        assert entry.valid?
        assert_equal :toc, entry.kind
        assert_nil entry.number
        assert_equal '_toc', entry.slug
        assert_equal '_toc', entry.basename
      end

      def test_resolve_titlepage_file
        resolver = TokenResolver::Resolver.new
        entry = resolver.resolve(['_titlepage']).first

        assert entry.valid?
        assert_equal :titlepage, entry.kind
        assert_nil entry.number
        assert_equal '_titlepage', entry.slug
        assert_equal '_titlepage', entry.basename
      end

      def test_resolve_indexpage_file
        resolver = TokenResolver::Resolver.new
        entry = resolver.resolve(['_indexpage']).first

        assert entry.valid?
        assert_equal :indexpage, entry.kind
        assert_nil entry.number
        assert_equal '_indexpage', entry.slug
        assert_equal '_indexpage', entry.basename
      end

      def test_resolve_file_method_for_toc_html
        resolver = TokenResolver::Resolver.new
        entry = resolver.resolve_file('_toc.html')

        assert entry.valid?
        assert_equal :toc, entry.kind
        assert_equal '_toc', entry.basename
      end

      def test_chapter_entry_has_number_and_slug
        resolver = TokenResolver::Resolver.new
        entry = resolver.resolve(['11-sample']).first

        assert entry.valid?
        assert_equal :chapter, entry.kind
        assert_equal '11', entry.number
        assert_equal 'sample', entry.slug
        assert_equal '11-sample', entry.basename
      end
    end

    # PostProcessCommands の Entry 解決テスト
    class PostProcessEntryResolutionTest < Minitest::Test
      def setup
        @tmpdir = Dir.mktmpdir
      end

      def teardown
        FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
      end

      def test_resolve_entry_map_for_toc
        Dir.chdir(@tmpdir) do
          # _toc.html を作成
          File.write('_toc.html', '<html><body><h1 id="toc">目次</h1></body></html>')

          entry_map = PostProcessCommands.resolve_entry_map(['_toc'])

          assert_equal 1, entry_map.size
          html_path, entry = entry_map.first

          assert_equal './_toc.html', html_path
          assert_equal :toc, entry.kind
          assert_equal '_toc', entry.basename
        end
      end

      def test_resolve_entry_map_for_chapter
        Dir.chdir(@tmpdir) do
          File.write('11-sample.html', '<html><body><h1 id="ch1">Chapter 1</h1></body></html>')

          entry_map = PostProcessCommands.resolve_entry_map(['11-sample'])

          assert_equal 1, entry_map.size
          html_path, entry = entry_map.first

          assert_equal './11-sample.html', html_path
          assert_equal :chapter, entry.kind
          assert_equal '11-sample', entry.basename
        end
      end

      def test_resolve_entry_map_for_all_html_files
        Dir.chdir(@tmpdir) do
          File.write('11-sample.html', '<html><body></body></html>')
          File.write('_toc.html', '<html><body></body></html>')

          entry_map = PostProcessCommands.resolve_entry_map([])

          assert_equal 2, entry_map.size

          toc_entry = entry_map['./_toc.html']
          chapter_entry = entry_map['./11-sample.html']

          assert_equal :toc, toc_entry.kind
          assert_equal :chapter, chapter_entry.kind
        end
      end
    end

    # PreProcessCommands の Entry 解決テスト
    class PreProcessEntryResolutionTest < Minitest::Test
      def test_resolve_entries_for_chapter
        entries = [make_entry('11-sample', kind: :chapter)]
        result = PreProcessCommands.resolve_entries(entries)

        assert_equal 1, result.size
        assert_equal :chapter, result.first.kind
      end

      def test_resolve_entries_converts_basename_to_entry
        # basename 文字列が渡された場合、TokenResolver で解決する
        result = PreProcessCommands.resolve_entries(['11-sample'])

        assert_equal 1, result.size
        assert result.first.respond_to?(:kind)
      end

      private

      def make_entry(basename, kind:)
        num = basename[/\A(\d+)/, 1]
        slug = basename.sub(/\A\d+-?/, '')
        TokenResolver::Entry.new(
          number: num,
          slug: slug.empty? ? nil : slug,
          kind: kind,
          label: basename,
          path: "contents/#{basename}.md",
          exists: true,
          in_catalog: true,
          valid: true
        )
      end
    end

    # TocDocumentBuilder の Entry 解決テスト
    class TocDocumentBuilderEntryTest < Minitest::Test
      def setup
        @tmpdir = Dir.mktmpdir
      end

      def teardown
        FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
      end

      def test_toc_builder_uses_entry_kind_for_heading_extraction
        Dir.chdir(@tmpdir) do
          # chapter HTML を作成
          File.write('11-sample.html', <<~HTML)
            <html><body>
              <h1 id="ch1">Chapter Title</h1>
              <h2 id="sec1">Section 1</h2>
              <h3 id="sub1">Subsection 1</h3>
            </body></html>
          HTML

          # appendix HTML を作成
          File.write('91-appendix.html', <<~HTML)
            <html><body>
              <h1 id="app1">Appendix Title</h1>
              <h2 id="sec1">Section 1</h2>
              <h3 id="sub1">Subsection 1</h3>
            </body></html>
          HTML

          entry_map = build_entry_map(['11-sample.html', '91-appendix.html'])

          # HeadingExtractor が entry.kind を正しく使用することを確認
          chapter_entry = entry_map[File.expand_path('11-sample.html')]
          appendix_entry = entry_map[File.expand_path('91-appendix.html')]

          chapter_extractor = TocCommands::HeadingExtractor.new(
            File.expand_path('11-sample.html'),
            chapter_entry
          )
          appendix_extractor = TocCommands::HeadingExtractor.new(
            File.expand_path('91-appendix.html'),
            appendix_entry
          )

          # chapter は h1, h2, h3 を抽出
          assert_equal 3, chapter_extractor.headings.size

          # appendix は h1, h2 のみ抽出
          assert_equal 2, appendix_extractor.headings.size
        end
      end

      private

      def build_entry_map(targets)
        resolver = TokenResolver::Resolver.new
        targets.each_with_object({}) do |target, map|
          entry = resolver.resolve_file(target)
          map[File.expand_path(target)] = entry
        end
      end
    end

    # HeadingProcessor の nil number 対応テスト
    class HeadingProcessorNilNumberTest < Minitest::Test
      def setup
        @tmpdir = Dir.mktmpdir
      end

      def teardown
        FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
      end

      def test_build_heading_context_handles_nil_number
        html_file = File.join(@tmpdir, '_toc.html')
        File.write(html_file, '<html><body><h1 id="toc">目次</h1></body></html>')

        entry = TokenResolver::Entry.new(
          number: nil,
          slug: '_toc',
          kind: :toc,
          label: 'TOC',
          path: 'contents/_toc.md',
          exists: false,
          in_catalog: false,
          valid: true
        )

        context = PostProcessCommands::HeadingProcessor.build_heading_context(html_file, entry)

        assert_equal 'toc', context[:file_type]
        assert_nil context[:chapter_display_number]
        assert_nil context[:appendix_letter]
        refute context[:process_headings]
      end

      def test_build_heading_context_for_chapter
        html_file = File.join(@tmpdir, '11-sample.html')
        File.write(html_file, '<html><body><h1 id="ch1">Chapter</h1></body></html>')

        entry = TokenResolver::Entry.new(
          number: '11',
          slug: 'sample',
          kind: :chapter,
          label: 'sample',
          path: 'contents/11-sample.md',
          exists: true,
          in_catalog: true,
          valid: true
        )

        context = PostProcessCommands::HeadingProcessor.build_heading_context(html_file, entry)

        assert_equal 'chapter', context[:file_type]
        assert context[:process_headings]
      end
    end
  end
end
