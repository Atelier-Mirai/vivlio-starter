# frozen_string_literal: true

# ================================================================
# Test: metrics/sentence_collector_test.rb
# ================================================================
# テスト対象:
#   Metrics::SentenceCollector（位置つきの文の収集）
#
# 検証内容:
#   - 文の開始行を正しく記録する
#   - 文が複数行にまたがっても 1 文として開始行を保つ
#   - フェンスドコードブロックの中身は収集しない
#   - 見出し・表などの構造行は文に含めない
#   - 文字数は改行を除いて数える
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/metrics/sentence_collector'

module VivlioStarter
  module CLI
    module Metrics
      class SentenceCollectorTest < Minitest::Test
        def test_records_line_numbers_and_excludes_code
          content = <<~MD
            # 見出し

            最初の文です。
            二番目の文は
            複数行にまたがります。

            ```
            コード。
            ```
            三番目。
          MD

          sentences = SentenceCollector.new.collect(content, 3)

          assert_equal [3, 4, 10], sentences.map(&:line)
          assert_equal ['最初の文です。', '二番目の文は複数行にまたがります。', '三番目。'], sentences.map(&:text)
          assert(sentences.all? { it.chapter_num == 3 })
          refute(sentences.any? { it.text.include?('コード') }, 'コードブロックの中身は収集しない')
        end

        def test_multiline_sentence_length_excludes_newline
          content = "前半は\n後半。\n"

          sentence = SentenceCollector.new.collect(content, 1).first

          assert_equal '前半は後半。', sentence.text
          assert_equal 6, sentence.length
        end

        # リンクは文字だけを数える。URL に括弧があっても、URL の残り（`.jpg)`）を文に含めない
        def test_link_with_parentheses_in_url_counts_only_its_text
          content = "肖像は[Commons](https://commons.wikimedia.org/wiki/File:K_(2008).jpg)から。\n"

          sentence = SentenceCollector.new.collect(content, 1).first

          assert_equal '肖像はCommonsから。', sentence.text
        end

        # 抜粋（display）はインラインコードを残す。文字数・文末の判定（text・length）は
        # これまでどおりコードを除く。コードの中の ! では文を切らない
        def test_should_keep_inline_code_only_in_display
          content = "`--fix!` は `book.yml` を書き換えます。次の文。\n"

          first, second = SentenceCollector.new.collect(content, 1)

          assert_equal '`--fix!` は `book.yml` を書き換えます。', first.display
          assert_equal 'は を書き換えます。', first.text
          assert_equal first.text.length, first.length
          assert_equal '次の文。', second.display
        end

        # 文が確定しないまま段落が終わったときは、その段落のコードを次の文へ持ち越さない
        def test_should_not_carry_inline_code_across_paragraphs
          content = "句点のない `a` の行\n\n本文は `b` です。\n"

          sentence = SentenceCollector.new.collect(content, 1).first

          assert_equal '本文は `b` です。', sentence.display
        end

        def test_skips_structural_lines
          content = "| 見出し | 列 |\n本文の文です。\n"

          sentences = SentenceCollector.new.collect(content, 2)

          assert_equal ['本文の文です。'], sentences.map(&:text)
        end
      end
    end
  end
end
