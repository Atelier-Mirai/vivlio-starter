# frozen_string_literal: true

# ================================================================
# Test: metrics/content_words_test.rb
# ================================================================
# テスト対象:
#   Metrics::ContentWords（品詞による内容語の判定と頻度順集計）
#   ※ 形態素解析（MeCab）には依存せず、素性配列を直接渡して検証する。
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/metrics/content_words'

module VivlioStarter
  module CLI
    module Metrics
      class ContentWordsTest < Minitest::Test
        def test_classify_labels_each_part_of_speech
          assert_equal '固有名詞', classify('Vivliostyle', %w[名詞 固有名詞 一般 * * * *]).pos
          assert_equal '形容動詞', classify('便利', %w[名詞 形容動詞語幹 * * * * 便利]).pos
          assert_equal '名詞', classify('設定', %w[名詞 サ変接続 * * * * 設定]).pos
          assert_equal '動詞', classify('歩い', %w[動詞 自立 * * 五段・カ行 連用タ接続 歩く]).pos
          assert_equal '形容詞', classify('美しい', %w[形容詞 自立 * * 形容詞・イ段 基本形 美しい]).pos
        end

        def test_classify_uses_base_form_or_surface
          assert_equal '歩く', classify('歩い', %w[動詞 自立 * * 五段・カ行 連用タ接続 歩く]).word
          assert_equal 'Vivliostyle', classify('Vivliostyle', %w[名詞 固有名詞 一般 * * * *]).word
        end

        def test_classify_rejects_function_and_noise
          assert_nil classify('は', %w[助詞 係助詞 * * * * は]), '機能語は除外'
          assert_nil classify('こと', %w[名詞 非自立 一般 * * * こと]), '非自立名詞は除外'
          assert_nil classify('する', %w[動詞 自立 * * サ変・スル 基本形 する]), 'ストップワードは除外'
          assert_nil classify('|', %w[名詞 サ変接続 * * * * *]), '記号（単語文字なし）は除外'
        end

        def test_classify_rejects_single_char_proper_noun_misdetection
          # 「章」など単漢字の固有名詞は MeCab の誤判定なので除外する。
          assert_nil classify('章', %w[名詞 固有名詞 一般 * * * 章])
          # 2 文字以上の正当な固有名詞は残る。
          assert_equal '固有名詞', classify('PDF', %w[名詞 固有名詞 組織 * * * *]).pos
        end

        def test_rank_counts_and_orders_by_frequency
          words = ([word('設定', '名詞')] * 3) + ([word('画像', '名詞')] * 5) + [word('便利', '形容動詞')]

          ranked = ContentWords.rank(words, limit: 2)

          assert_equal [['画像', 5], ['設定', 3]], ranked.map { [it.word, it.count] }
          assert_equal '名詞', ranked.first.pos
        end

        private

        def classify(surface, features) = ContentWords.classify(surface, features)
        def word(text, pos) = ContentWord.new(word: text, pos:)
      end
    end
  end
end
