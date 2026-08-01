# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/index_markup'

module VivlioStarter
  module CLI
    # 索引マークアップの綴りの正典テスト。
    # inline-footnote-index-collision-spec.md §5 の受け入れ基準表に対応する。
    class IndexMarkupTest < Minitest::Test
      # --- phase: 索引マークアップとして拾うもの ---

      def test_should_detect_plain_and_yomi_terms
        terms = '[Ruby]と[標準入出力|ひょうじゅん]。'.scan(IndexMarkup::TERM_PATTERN).flatten

        assert_equal ['Ruby', '標準入出力|ひょうじゅん'], terms
      end

      def test_should_detect_author_marked_symbols_as_terms
        # [!] [&&] [<h1>] は著者が意図的にマークアップした語なので除外しない
        terms = '[!] 注意 [&&] [<h1>]'.scan(IndexMarkup::TERM_PATTERN).flatten

        assert_equal ['!', '&&', '<h1>'], terms
        terms.each { refute IndexMarkup.skip_term?(it), "#{it} は索引語として扱う" }
      end

      # --- phase: 他の記法が自分の構文として持つブラケット（除外対象） ---

      def test_should_not_detect_inline_footnote_as_term
        # ^ はブラケットの外側にあるため、中身を見る skip_term? では区別できない。
        # パターン側の (?<!\^) で弾く必要がある（spec §4.1）
        assert_empty '本文です^[短い補足]。'.scan(IndexMarkup::TERM_PATTERN)
      end

      def test_should_not_detect_consecutive_inline_footnotes_as_terms
        assert_empty 'A^[補足1]とB^[補足2]。'.scan(IndexMarkup::TERM_PATTERN)
      end

      def test_should_not_detect_links_or_images_as_terms
        assert_empty '[公式](https://example.com)と ![図](img.png)'.scan(IndexMarkup::TERM_PATTERN)
      end

      # --- phase: 参照脚注は「中身」で落とす（パターンには一致する） ---

      def test_should_match_but_skip_footnote_reference
        inner = '本文です[^ref1]。'.scan(IndexMarkup::TERM_PATTERN).flatten.first

        assert_equal '^ref1', inner, 'パターンには一致する（外側では見分けられない）'
        assert IndexMarkup.skip_term?(inner), '中身が ^ で始まるので索引語にしない'
      end

      def test_should_skip_blank_terms
        assert IndexMarkup.skip_term?(nil)
        assert IndexMarkup.skip_term?('')
      end

      # --- phase: 辞書登録用の 2 パターン（読み付き / 読みなし） ---

      def test_should_split_term_and_yomi_for_dictionary
        pairs = '[標準入出力|ひょうじゅん]'.scan(IndexMarkup::TERM_WITH_YOMI_PATTERN)

        assert_equal [['標準入出力', 'ひょうじゅん']], pairs
      end

      def test_should_not_register_inline_footnote_containing_pipe
        # ^[A|B] を読み付き索引語 term=A yomi=B として辞書へ書き込んでいた（spec §3.3）
        assert_empty '読み付き^[A|B]。'.scan(IndexMarkup::TERM_WITH_YOMI_PATTERN)
      end

      def test_should_not_register_inline_footnote_as_dictionary_term
        assert_empty '本文^[この 49 ページというずれです]。'.scan(IndexMarkup::TERM_ONLY_PATTERN)
      end

      def test_term_only_pattern_should_not_double_register_yomi_form
        # 辞書登録は 2 パターンを順に当てるため、読みなし側が [用語|読み] にも
        # 一致すると同じ語が二重登録される。汎用の TERM_PATTERN を使えない理由
        assert_empty '[標準入出力|ひょうじゅん]'.scan(IndexMarkup::TERM_ONLY_PATTERN)
        refute_empty '[標準入出力|ひょうじゅん]'.scan(IndexMarkup::TERM_PATTERN)
      end
    end
  end
end
