# frozen_string_literal: true

# ================================================================
# Test: post_process/chapter_numbering_test.rb
# ================================================================
# 章番号を振らない組み方（改善案 #84）。直接ビルドで章が 1 つだけの配布資料に使う。
#   - 章扉に「第N章」を出さない
#   - 節番号は 1, 2, …（1-1 ではなく）
#   - 図表番号は「図 1」（1-1 ではなく）
# 既定（章番号を振る）に戻したあとは、従来どおり番号が付くことも確かめる。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/token_resolver'
require 'vivlio_starter/cli/build'
require 'vivlio_starter/cli/pre_process'
require 'vivlio_starter/cli/post_process'

module VivlioStarter
  module CLI
    module PostProcessCommands
      class ChapterNumberingTest < Minitest::Test
        XR = PreProcessCommands::CrossReferenceProcessor

        def setup
          HeadingProcessor.chapter_tokens_override = ['10-notes']
        end

        def teardown
          HeadingProcessor.chapter_numbering = true
          HeadingProcessor.chapter_tokens_override = nil
        end

        def test_should_omit_chapter_number_and_number_sections_plainly
          HeadingProcessor.chapter_numbering = false

          html = headings_after_numbering

          assert_nil html.at_css('h1 .chapter-number'), '章扉に「第N章」を出さない'
          # 柱の章題は .chapter-title から取る。番号が無くても題の span は付ける
          assert_equal '資料', html.at_css('h1 .chapter-title')&.text
          assert_equal %w[1 2], html.css('h2 .section-number').map(&:text)
        end

        def test_should_number_chapter_and_sections_by_default
          html = headings_after_numbering

          assert_equal '第1章', html.at_css('h1 .chapter-number').text
          assert_equal %w[1-1 1-2], html.css('h2 .section-number').map(&:text)
        end

        def test_should_number_figures_without_chapter_prefix
          content = "# 資料\n\n** 桜 @fig-a **\n![](a.webp)\n"

          HeadingProcessor.chapter_numbering = false
          plain_labels = XR.collect_labels(content, '10-notes.md', '1')[:labels]
          caption = XR.transform_captioned_blocks(content, '10-notes.md',
                                                  XR.build_labels_map_with_duplicates_check(plain_labels)[:labels_map])
          HeadingProcessor.chapter_numbering = true
          numbered = XR.collect_labels(content, '10-notes.md', '1')[:labels].find { it.type == :fig }

          assert_equal '1', plain_labels.find { it.type == :fig }.number
          assert_includes caption, '<figcaption>図 1: 桜</figcaption>'
          assert_equal '1-1', numbered.number
        end

        private

        def headings_after_numbering
          Dir.mktmpdir do |dir|
            path = File.join(dir, '10-notes.html')
            File.write(path, '<html><body><h1>資料</h1><h2>準備</h2><h2>操作</h2></body></html>')
            entry = TokenResolver::Entry.new(number: '10', slug: 'notes', kind: :chapter, label: 'CHAPTERS',
                                             path: 'contents/10-notes.md', exists: true, in_catalog: true, valid: true)

            HeadingProcessor.inject_heading_number_spans!(path, entry)

            Nokogiri::HTML(File.read(path))
          end
        end
      end
    end
  end
end
