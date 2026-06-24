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
      end
    end
  end
end
