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

      # --- plain_text（索引タグを付けられないときの素のテキスト表現） -------

      def test_plain_text_drops_yomi
        assert_equal '引数', IndexMarkup.plain_text('引数|ひきすう')
      end

      def test_plain_text_keeps_term_without_yomi
        assert_equal '基本情報技術者', IndexMarkup.plain_text('基本情報技術者')
      end

      # `[<h1>]` を素通しすると生タグとして VFM に渡り、**本物の章見出しになる**。
      # 目次と PDF アウトラインまで汚れた（index-markup-plain-fallback-spec.md §2.2）。
      def test_plain_text_escapes_tag_shaped_term
        assert_equal '&lt;h1&gt;', IndexMarkup.plain_text('<h1>')
        assert_equal '&lt;/h1&gt;', IndexMarkup.plain_text('</h1>')
      end

      # 索引スキャナ（process_term）と同じ規則であること。片方だけ変えると、
      # 索引が有効か無効かで `&` の見え方が変わる
      def test_plain_text_escapes_ampersand_like_the_index_scanner
        assert_equal '&amp;&amp;', IndexMarkup.plain_text('&&')
        assert_equal CGI.escapeHTML('&&'), IndexMarkup.plain_text('&&')
      end

      def test_plain_text_keeps_operator_terms_readable
        assert_equal '!DOCTYPE', IndexMarkup.plain_text('!DOCTYPE')
        assert_equal '404', IndexMarkup.plain_text('404')
      end

      # --- 参照リンクとの共存（markdown-notation-collision-spec.md §3・T-1）------

      def test_link_labels_collects_definitions
        text = "[sample]: https://example.com\n  [Indented Label]: /foo \"title\"\n本文\n"
        assert_equal %w[sample indented\ label], IndexMarkup.link_labels(text)
      end

      # CommonMark はラベルの大文字小文字を区別せず、連続する空白を 1 つに畳む。
      def test_normalize_label_follows_commonmark
        assert_equal 'foo bar', IndexMarkup.normalize_label("  Foo   BAR \n")
      end

      # 脚注定義は綴りが同じだが別の記法。拾うとラベル表が汚れる。
      def test_link_labels_ignores_footnote_definition
        assert_empty IndexMarkup.link_labels("[^1]: 脚注の本体です。\n")
      end

      # 行頭のインデントは 3 つまで。4 つ以上は字下げコードブロックの領域。
      def test_link_labels_ignores_over_indented_definition
        assert_empty IndexMarkup.link_labels("    [deep]: https://example.com\n")
      end

      # `[本文][ref]` は前半も後半も索引語にしない。定義の有無を問わない
      # ——索引語を 2 つ区切りなしで並べる用途が存在しないため。
      def test_reference_link_detects_adjacent_brackets
        line = '参照リンク [完全形][undefined] です。'
        matches = matches_in(line)
        assert_equal 2, matches.size
        assert(matches.all? { IndexMarkup.reference_link?(it, []) })
      end

      # 定義済みラベルの単独形（省略参照）も索引語にしない。
      def test_reference_link_detects_shortcut_form
        match = matches_in('省略形 [sample] です。').first
        assert IndexMarkup.reference_link?(match, ['sample'])
        refute IndexMarkup.reference_link?(match, ['other'])
      end

      # 定義の無い `[基本情報技術者]` は従来どおり索引マークアップ。
      def test_reference_link_keeps_plain_index_markup
        match = matches_in('索引語 [基本情報技術者] は残ります。').first
        refute IndexMarkup.reference_link?(match, ['sample'])
      end

      private

      def matches_in(line)
        line.to_enum(:scan, IndexMarkup::TERM_PATTERN).map { Regexp.last_match }
      end
    end
  end
end
