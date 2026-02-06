# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'nokogiri'

# BacklinkDeduplicator のテストに必要な最小限のスタブ
module Vivlio
  module Starter
    module CLI
      module Common
        module_function

        def log_info(msg) = nil
        def log_success(msg) = nil
        def log_warn(msg) = nil
        def log_error(msg) = nil
      end
    end
  end
end

require_relative '../lib/vivlio/starter/cli/build/page_mapping_extractor'
require_relative '../lib/vivlio/starter/cli/build/backlink_deduplicator'

class TestBacklinkDeduplicator < Minitest::Test
  # テスト用の PageMapping Data オブジェクトを構築するヘルパー
  MappingEntry = Vivlio::Starter::CLI::Build::PageMappingExtractor::MappingEntry
  BacklinkEntry = Vivlio::Starter::CLI::Build::PageMappingExtractor::BacklinkEntry
  PageMapping = Vivlio::Starter::CLI::Build::PageMappingExtractor::PageMapping
  Deduplicator = Vivlio::Starter::CLI::Build::BacklinkDeduplicator

  # --- 用語集バックリンクの重複排除テスト ---

  def test_should_remove_duplicate_backlinks_for_same_page
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        # Arrange: 用語「ウェブサイト」に対してページ4に2つ、ページ5に1つのバックリンク
        glossary_html = <<~HTML
          <!DOCTYPE html>
          <html lang="ja">
          <head><meta charset="UTF-8"><title>用語集</title></head>
          <body>
            <dl>
              <dt id="gls-ウェブサイト">ウェブサイト</dt>
              <dd>
                <p class="glossary-backlinks"><a href="08-web.html#gls-src-08-web-ウェブサイト-1" class="glossary-backlink"></a> <a href="08-web.html#gls-src-08-web-ウェブサイト-2" class="glossary-backlink"></a> <a href="08-web.html#gls-src-08-web-ウェブサイト-3" class="glossary-backlink"></a></p>
              </dd>
            </dl>
          </body>
          </html>
        HTML
        File.write('_glossarypage.html', glossary_html, encoding: 'utf-8')

        # ページマッピング: anchor-1 と anchor-2 は同じページ(4), anchor-3 はページ5
        page_mapping = build_page_mapping(
          mappings: [
            { anchor_id: 'gls-src-08-web-ウェブサイト-1', href: '_glossarypage.html#gls-ウェブサイト', page_index: 4, spine_index: 0 },
            { anchor_id: 'gls-src-08-web-ウェブサイト-2', href: '_glossarypage.html#gls-ウェブサイト', page_index: 4, spine_index: 0 },
            { anchor_id: 'gls-src-08-web-ウェブサイト-3', href: '_glossarypage.html#gls-ウェブサイト', page_index: 5, spine_index: 0 }
          ]
        )

        # Act
        result = Deduplicator.new(page_mapping).deduplicate!

        # Assert: 1件の重複バックリンクが削除される
        assert_equal 1, result.glossary_removed

        # 残ったバックリンクは2件（ページ4に1件、ページ5に1件）
        doc = Nokogiri::HTML5(File.read('_glossarypage.html'))
        remaining_links = doc.css('a.glossary-backlink')
        assert_equal 2, remaining_links.size

        # anchor-1（ページ4の最初）と anchor-3（ページ5）が残る
        hrefs = remaining_links.map { it['href'] }
        assert_includes hrefs, '08-web.html#gls-src-08-web-ウェブサイト-1'
        assert_includes hrefs, '08-web.html#gls-src-08-web-ウェブサイト-3'
      end
    end
  end

  def test_should_not_remove_backlinks_on_different_pages
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        # Arrange: 各バックリンクが異なるページにある場合
        glossary_html = <<~HTML
          <!DOCTYPE html>
          <html lang="ja">
          <head><meta charset="UTF-8"><title>用語集</title></head>
          <body>
            <dl>
              <dt id="gls-ブラウザ">ブラウザ</dt>
              <dd>
                <p class="glossary-backlinks"><a href="08-web.html#gls-src-08-web-ブラウザ-1" class="glossary-backlink"></a> <a href="08-web.html#gls-src-08-web-ブラウザ-2" class="glossary-backlink"></a></p>
              </dd>
            </dl>
          </body>
          </html>
        HTML
        File.write('_glossarypage.html', glossary_html, encoding: 'utf-8')

        page_mapping = build_page_mapping(
          mappings: [
            { anchor_id: 'gls-src-08-web-ブラウザ-1', href: '_glossarypage.html#gls-ブラウザ', page_index: 3, spine_index: 0 },
            { anchor_id: 'gls-src-08-web-ブラウザ-2', href: '_glossarypage.html#gls-ブラウザ', page_index: 7, spine_index: 0 }
          ]
        )

        # Act
        result = Deduplicator.new(page_mapping).deduplicate!

        # Assert: 重複なし
        assert_equal 0, result.glossary_removed

        doc = Nokogiri::HTML5(File.read('_glossarypage.html'))
        assert_equal 2, doc.css('a.glossary-backlink').size
      end
    end
  end

  def test_should_handle_multiple_duplicates_on_same_page
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        # Arrange: 同じページに3回出現（p.11, 11, 11 → p.11 のみ）
        glossary_html = <<~HTML
          <!DOCTYPE html>
          <html lang="ja">
          <head><meta charset="UTF-8"><title>用語集</title></head>
          <body>
            <dl>
              <dt id="gls-javascript">JavaScript</dt>
              <dd>
                <p class="glossary-backlinks"><a href="08-web.html#gls-src-08-web-javascript-1" class="glossary-backlink"></a> <a href="08-web.html#gls-src-08-web-javascript-2" class="glossary-backlink"></a> <a href="08-web.html#gls-src-08-web-javascript-3" class="glossary-backlink"></a></p>
              </dd>
            </dl>
          </body>
          </html>
        HTML
        File.write('_glossarypage.html', glossary_html, encoding: 'utf-8')

        page_mapping = build_page_mapping(
          mappings: [
            { anchor_id: 'gls-src-08-web-javascript-1', href: '_glossarypage.html#gls-javascript', page_index: 11, spine_index: 0 },
            { anchor_id: 'gls-src-08-web-javascript-2', href: '_glossarypage.html#gls-javascript', page_index: 11, spine_index: 0 },
            { anchor_id: 'gls-src-08-web-javascript-3', href: '_glossarypage.html#gls-javascript', page_index: 11, spine_index: 0 }
          ]
        )

        # Act
        result = Deduplicator.new(page_mapping).deduplicate!

        # Assert: 2件削除、1件残る
        assert_equal 2, result.glossary_removed

        doc = Nokogiri::HTML5(File.read('_glossarypage.html'))
        remaining = doc.css('a.glossary-backlink')
        assert_equal 1, remaining.size
        assert_equal '08-web.html#gls-src-08-web-javascript-1', remaining.first['href']
      end
    end
  end

  # --- 本文 HTML の†重複排除テスト ---

  def test_should_remove_duplicate_dagger_marks_on_same_page
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        # Arrange: 本文に同じ用語が同一ページ内に2回出現
        body_html = <<~HTML
          <!DOCTYPE html>
          <html lang="ja">
          <head><meta charset="UTF-8"><title>08-web</title></head>
          <body>
            <p><span class="index-term">ウェブサイト</span><a id="gls-src-08-web-ウェブサイト-1" class="glossary-link" href="_glossarypage.html#gls-ウェブサイト"><sup>†</sup></a>の説明。</p>
            <p>別の<span class="index-term">ウェブサイト</span><a id="gls-src-08-web-ウェブサイト-2" class="glossary-link" href="_glossarypage.html#gls-ウェブサイト"><sup>†</sup></a>についての記述。</p>
          </body>
          </html>
        HTML
        File.write('08-web.html', body_html, encoding: 'utf-8')

        # 両方とも同じページ（ページ4）に配置
        page_mapping = build_page_mapping(
          mappings: [
            { anchor_id: 'gls-src-08-web-ウェブサイト-1', href: '_glossarypage.html#gls-ウェブサイト', page_index: 4, spine_index: 0 },
            { anchor_id: 'gls-src-08-web-ウェブサイト-2', href: '_glossarypage.html#gls-ウェブサイト', page_index: 4, spine_index: 0 }
          ]
        )

        # Act
        result = Deduplicator.new(page_mapping).deduplicate!

        # Assert: 本文の2件目の†が削除される
        assert_equal 1, result.body_removed

        doc = Nokogiri::HTML5(File.read('08-web.html'))
        remaining = doc.css('a.glossary-link')
        assert_equal 1, remaining.size
        assert_equal 'gls-src-08-web-ウェブサイト-1', remaining.first['id']
      end
    end
  end

  def test_should_keep_dagger_marks_on_different_pages
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        # Arrange: 同じ用語が異なるページに出現
        body_html = <<~HTML
          <!DOCTYPE html>
          <html lang="ja">
          <head><meta charset="UTF-8"><title>08-web</title></head>
          <body>
            <p><span class="index-term">ウェブサイト</span><a id="gls-src-08-web-ウェブサイト-1" class="glossary-link" href="_glossarypage.html#gls-ウェブサイト"><sup>†</sup></a>の説明。</p>
            <p>別の<span class="index-term">ウェブサイト</span><a id="gls-src-08-web-ウェブサイト-2" class="glossary-link" href="_glossarypage.html#gls-ウェブサイト"><sup>†</sup></a>についての記述。</p>
          </body>
          </html>
        HTML
        File.write('08-web.html', body_html, encoding: 'utf-8')

        # 異なるページに配置
        page_mapping = build_page_mapping(
          mappings: [
            { anchor_id: 'gls-src-08-web-ウェブサイト-1', href: '_glossarypage.html#gls-ウェブサイト', page_index: 4, spine_index: 0 },
            { anchor_id: 'gls-src-08-web-ウェブサイト-2', href: '_glossarypage.html#gls-ウェブサイト', page_index: 5, spine_index: 0 }
          ]
        )

        # Act
        result = Deduplicator.new(page_mapping).deduplicate!

        # Assert: 異なるページなので両方残る
        assert_equal 0, result.body_removed

        doc = Nokogiri::HTML5(File.read('08-web.html'))
        assert_equal 2, doc.css('a.glossary-link').size
      end
    end
  end

  def test_should_handle_different_terms_on_same_page
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        # Arrange: 同じページに異なる用語が出現（重複排除されない）
        body_html = <<~HTML
          <!DOCTYPE html>
          <html lang="ja">
          <head><meta charset="UTF-8"><title>08-web</title></head>
          <body>
            <p><span class="index-term">ウェブサイト</span><a id="gls-src-08-web-ウェブサイト-1" class="glossary-link" href="_glossarypage.html#gls-ウェブサイト"><sup>†</sup></a></p>
            <p><span class="index-term">ブラウザ</span><a id="gls-src-08-web-ブラウザ-1" class="glossary-link" href="_glossarypage.html#gls-ブラウザ"><sup>†</sup></a></p>
          </body>
          </html>
        HTML
        File.write('08-web.html', body_html, encoding: 'utf-8')

        page_mapping = build_page_mapping(
          mappings: [
            { anchor_id: 'gls-src-08-web-ウェブサイト-1', href: '_glossarypage.html#gls-ウェブサイト', page_index: 4, spine_index: 0 },
            { anchor_id: 'gls-src-08-web-ブラウザ-1', href: '_glossarypage.html#gls-ブラウザ', page_index: 4, spine_index: 0 }
          ]
        )

        # Act
        result = Deduplicator.new(page_mapping).deduplicate!

        # Assert: 異なる用語なので両方残る
        assert_equal 0, result.body_removed

        doc = Nokogiri::HTML5(File.read('08-web.html'))
        assert_equal 2, doc.css('a.glossary-link').size
      end
    end
  end

  def test_should_return_empty_result_when_no_mapping
    # Arrange: マッピングが空
    page_mapping = build_page_mapping(mappings: [], backlink_mappings: [])

    # Act
    result = Deduplicator.new(page_mapping).deduplicate!

    # Assert
    assert_equal 0, result.glossary_removed
    assert_equal 0, result.body_removed
    assert_empty result.files_modified
  end

  def test_should_respect_spine_index_for_dedup
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        # Arrange: 同じ page_index でも spine_index が異なれば別ページ
        body_html = <<~HTML
          <!DOCTYPE html>
          <html lang="ja">
          <head><meta charset="UTF-8"><title>08-web</title></head>
          <body>
            <p><a id="gls-src-08-web-ウェブサイト-1" class="glossary-link" href="_glossarypage.html#gls-ウェブサイト"><sup>†</sup></a></p>
            <p><a id="gls-src-08-web-ウェブサイト-2" class="glossary-link" href="_glossarypage.html#gls-ウェブサイト"><sup>†</sup></a></p>
          </body>
          </html>
        HTML
        File.write('08-web.html', body_html, encoding: 'utf-8')

        # 同じ page_index=0 でも spine が異なる
        page_mapping = build_page_mapping(
          mappings: [
            { anchor_id: 'gls-src-08-web-ウェブサイト-1', href: '_glossarypage.html#gls-ウェブサイト', page_index: 0, spine_index: 0 },
            { anchor_id: 'gls-src-08-web-ウェブサイト-2', href: '_glossarypage.html#gls-ウェブサイト', page_index: 0, spine_index: 1 }
          ]
        )

        # Act
        result = Deduplicator.new(page_mapping).deduplicate!

        # Assert: spine_index が異なるので両方残る
        assert_equal 0, result.body_removed
      end
    end
  end

  private

  # テスト用 PageMapping を構築するヘルパー
  def build_page_mapping(mappings: [], backlink_mappings: [])
    mapping_entries = mappings.map do |m|
      MappingEntry.new(
        anchor_id: m[:anchor_id],
        href: m[:href],
        page_index: m[:page_index],
        spine_index: m[:spine_index]
      )
    end

    backlink_entries = backlink_mappings.map do |b|
      BacklinkEntry.new(
        href: b[:href],
        page_index: b[:page_index],
        spine_index: b[:spine_index]
      )
    end

    PageMapping.new(
      mappings: mapping_entries,
      backlink_mappings: backlink_entries,
      total_pages: 42,
      extracted_at: Time.now.iso8601
    )
  end
end
