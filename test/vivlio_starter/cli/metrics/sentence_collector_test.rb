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

        def test_skips_structural_lines
          content = "| 見出し | 列 |\n本文の文です。\n"

          sentences = SentenceCollector.new.collect(content, 2)

          assert_equal ['本文の文です。'], sentences.map(&:text)
        end
      end
    end
  end
end
