# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/cli/common_plain_title_test.rb
#
# 書名・副題を、PDF の文書情報・EPUB の書誌・しおりへ入れる素の文字列にする
# Common.plain_title を確かめる（改善案.md #116）。
# =============================================================================

require 'test_helper'
require 'vivlio_starter/cli/common'

module VivlioStarter
  module CLI
    class CommonPlainTitleTest < Minitest::Test
      # 扉で改行させる <br> は、和文の間なら詰める（PDF の情報に「<br>」が入っていた）
      def test_should_drop_line_breaks_between_japanese_words
        assert_equal '1つのWebサイトで学ぶHTML/CSSグリッドとやさしいJavaScriptの基本',
                     Common.plain_title('1つのWebサイトで学ぶHTML/CSSグリッドと<br>やさしいJavaScriptの基本')
        assert_equal 'Ruby入門', Common.plain_title('Ruby<BR />入門')
      end

      # 英単語の間なら空白にする（くっつけない）
      def test_should_turn_line_breaks_between_english_words_into_a_space
        assert_equal 'A Guide to Ruby', Common.plain_title('A Guide<br/>to Ruby')
        assert_equal 'A Guide to Ruby', Common.plain_title('A Guide <br> to Ruby')
      end

      # ほかのタグは外し、文字参照は文字に戻す
      def test_should_strip_other_tags_and_unescape_entities
        assert_equal 'Tom & Jerry', Common.plain_title('<span class="x">Tom &amp; Jerry</span>')
      end

      def test_should_leave_plain_titles_as_they_are
        assert_equal 'はじめての技術書', Common.plain_title('はじめての技術書')
        assert_equal '', Common.plain_title(nil)
      end
    end
  end
end
