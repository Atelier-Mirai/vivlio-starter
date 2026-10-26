# frozen_string_literal: true

# ================================================================
# Test: build/outline_extractor_test.rb
# ================================================================
# テスト対象:
#   OutlineExtractor.detect_front_matter_spans
#   注釈対象の結合 PDF から前付（preface）・目次（toc）のページ数を
#   テキスト検出で算出するロジック（_toc.pdf / 00-preface.pdf 非依存化）。
#   print_pdf 単独ビルドでしおりが目次へ集中する不具合の恒久対策。
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/build'
require 'vivlio_starter/cli/build/outline_extractor'

module VivlioStarter
  module CLI
    module Build
      class OutlineExtractorTest < Minitest::Test
        Extractor = OutlineExtractor

        # term ごとに「ページ先頭で見つかるページ」を返す擬似 find_page_by_first_line を作る。
        # （'目次' → toc ページ、それ以外 → 章ページ。nil 指定で「見つからない」を表現）
        def search_helpers(toc_page:, chapter_page:)
          finder = lambda do |term, from, _to|
            page = term.to_s.include?('目次') ? toc_page : chapter_page
            page if page && page >= from
          end
          { find_page_by_first_line: finder }
        end

        def markers(first_bn)
          { first_bn => ['第1章執筆ワークフロー概観'] }
        end

        # 前書きあり: preface=toc_start-front_start, toc=first_chapter-toc_start
        def test_should_compute_spans_when_preface_present
          helpers = search_helpers(toc_page: 7, chapter_page: 23)
          preface_pages, toc_pages = Extractor.detect_front_matter_spans(
            markers('11-workflow'), helpers, 1, 378, '11-workflow'
          )

          assert_equal 4, preface_pages, '前付 = 目次開始(7) - front_start(3)'
          assert_equal 16, toc_pages, '目次 = 最初の本文章(23) - 目次開始(7)'
        end

        # 前書き無し: 目次が front_start に来る → preface=0
        def test_should_treat_preface_as_zero_when_absent
          helpers = search_helpers(toc_page: 3, chapter_page: 19)
          preface_pages, toc_pages = Extractor.detect_front_matter_spans(
            markers('11-workflow'), helpers, 1, 378, '11-workflow'
          )

          assert_equal 0, preface_pages, '前書きが無ければ preface=0'
          assert_equal 16, toc_pages, '目次 = 最初の本文章(19) - 目次開始(3)'
        end

        # 目次が検出できない場合は [0, 0]（破綻せず素直に縮退）
        def test_should_return_zeros_when_toc_not_found
          helpers = search_helpers(toc_page: nil, chapter_page: 23)
          spans = Extractor.detect_front_matter_spans(
            markers('11-workflow'), helpers, 1, 378, '11-workflow'
          )

          assert_equal [0, 0], spans
        end

        # 章扉では「第1章」だけがページ先頭に出てフルタイトルは後続の柱に現れる。
        # マーカー一致ページの最小値（最も早い章開始ページ）を採ること。
        def test_should_pick_earliest_chapter_marker_page
          # 'フルタイトル' → 25（柱）, '第1章' → 23（章扉）。最小の 23 を採る。
          finder = lambda do |term, from, _to|
            page = if term.include?('目次') then 7
                   elsif term == '第1章執筆ワークフロー概観' then 25
                   elsif term == '第1章' then 23
                   end
            page if page && page >= from
          end
          helpers = { find_page_by_first_line: finder }
          markers = { '11-workflow' => ['第1章執筆ワークフロー概観', '第1章'] }

          _preface, toc_pages = Extractor.detect_front_matter_spans(
            markers, helpers, 1, 378, '11-workflow'
          )

          assert_equal 16, toc_pages, '最も早い章開始 23 を採用 → toc=23-7=16（柱の 25 ではない）'
        end

        # 最初の本文章が検出できない場合、目次は最低 1 ページとして扱う
        def test_should_default_toc_to_one_page_when_chapter_not_found
          helpers = search_helpers(toc_page: 7, chapter_page: nil)
          _preface, toc_pages = Extractor.detect_front_matter_spans(
            markers('11-workflow'), helpers, 1, 378, '11-workflow'
          )

          assert_equal 1, toc_pages
        end

        # 前書きが 2 本以上あっても、目次は見出しで見つけたページから始まる。先頭の前書きの範囲は 2 本目の
        # 前書き（6 ページ）の手前で切られるが、そこから数えると目次が 6 ページからになり、本当の目次（10〜25）の
        # 途中で終わる。章のしおりは目次の後ろから探すので、目次ページに載った章題へ吸い寄せられていた
        def test_should_start_toc_at_found_page_even_with_several_prefaces
          ctx = { from_base: 1, total_pages: 378, preface_pages: 7, toc_pages: 16,
                  preface_bn: '00-about', chapter_ranges: { '00-about' => [3, 5], '01-volume-1' => [6, 9] } }

          assert_equal [10, 25], Extractor.page_range_toc(ctx), '前付の始まり(3) + 前付(7) = 目次の見出しのページ(10)'
        end

        # 章の始まりは、ページ先頭の見出しとして現れる最も早いページ。章扉に「第2章」を出さない本で、目印を
        # 全文で順に試すと、本文の奥の「第2章」という見出し（1014 ページ）に先に一致していた
        def test_should_prefer_heading_at_page_top_for_chapter_start
          first_line = ->(term, from, _to) { 206 if term == '第2部　オブジェクト指向編' && from <= 206 }
          full_text = ->(markers, _from, _to) { 1014 if markers.include?('第2章') }
          ctx = { from_base: 1, total_pages: 1388, chapter_starts: { '11-basics' => 40 },
                  chapter_markers: { '12-object-oriented' => ['第2章', '第2部　オブジェクト指向編'] },
                  find_page_by_first_line: first_line, search_markers: full_text }

          assert_equal [206, 1388], Extractor.page_range_default('12-object-oriented', ctx, '11-basics')
        end

        # 全ページを pdftotext 1 回で読んで分けても、白紙を挟んだページの番号がずれないこと
        def test_should_find_pages_from_single_pdftotext_run
          skip 'pdftotext が無い' unless Common.external_command_available?('pdftotext')
          require 'prawn'

          Dir.mktmpdir do |dir|
            path = File.join(dir, 'book.pdf')
            Prawn::Document.generate(path) do |pdf|
              pdf.text 'Contents'
              pdf.start_new_page # 白紙
              pdf.start_new_page
              pdf.text 'Chapter One'
              pdf.text 'Second line'
            end

            texts = Extractor.read_page_texts(path)
            assert_equal 3, texts.size
            assert(texts.all? { it.end_with?("\f") }, '各ページの文字は \f で終わる')

            helpers = Extractor.build_search_helpers(path, 3)
            assert_equal 3, helpers[:search_markers].call(['Second line'], 1, 3)
            assert_equal 3, helpers[:find_page_by_first_line].call('Chapter One', 1, 3)
            assert_nil helpers[:find_page_by_first_line].call('Second line', 1, 2)
          end
        end

        # 章扉の章題に用語集の印（†）が付いていても、印の無い見出しの文字で見つかること。見つからないと
        # 最初のページから探し直し、目次ページに載った章題（印が無い）へしおりが飛んでいた
        def test_should_find_heading_marked_with_glossary_indicator
          skip 'pdftotext が無い' unless Common.external_command_available?('pdftotext')
          require 'prawn'

          Dir.mktmpdir do |dir|
            path = File.join(dir, 'book.pdf')
            Prawn::Document.generate(path) do |pdf|
              pdf.text 'Contents'
              pdf.text 'Object Oriented Part'
              pdf.start_new_page
              pdf.text 'Object Oriented † Part'
            end

            helpers = Extractor.build_search_helpers(path, 2)
            assert_equal 2, helpers[:search_markers].call(['Object Oriented Part'], 2, 2)
            assert_equal 2, helpers[:find_page_by_first_line].call('Object Oriented Part', 2, 2)
          end
        end
      end
    end
  end
end
