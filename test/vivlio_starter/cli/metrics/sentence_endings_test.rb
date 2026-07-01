# frozen_string_literal: true

# ================================================================
# Test: metrics/sentence_endings_test.rb
# ================================================================
# テスト対象:
#   Metrics::SentenceEndings（文末表現の分類・内訳・連続検出）
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/metrics/sentence_collector'
require 'vivlio_starter/cli/metrics/sentence_endings'

module VivlioStarter
  module CLI
    module Metrics
      class SentenceEndingsTest < Minitest::Test
        def test_classify_recognizes_endings
          assert_equal 'です', SentenceEndings.classify('これは本です。')
          assert_equal 'ます', SentenceEndings.classify('すぐ実行します。')
          assert_equal 'ました', SentenceEndings.classify('処理が完了しました。')
          assert_equal 'である', SentenceEndings.classify('これは事実である。')
          assert_equal '体言止め', SentenceEndings.classify('満開の桜。') # 漢字止め
          assert_equal 'その他', SentenceEndings.classify('とても良い。')  # ひらがな止め
        end

        def test_distribution_groups_into_categories
          sentences = [sentence('本です。'), sentence('します。'), sentence('桜。'), sentence('良い。')]

          dist = SentenceEndings.distribution(sentences)

          assert_equal 50, dist['です・ます'] # です + ます = 2/4
          assert_equal 25, dist['体言止め']
          assert_equal 0, dist['だ・である']
          assert_equal 25, dist['その他']
        end

        def test_monotone_runs_detects_consecutive_same_ending
          sentences = [
            sentence('Aします。', line: 10), sentence('Bします。', line: 11), sentence('Cします。', line: 12),
            sentence('Dです。', line: 13),                                      # 別キーで連続が途切れる
            sentence('Eします。', chapter: 2, line: 5), sentence('Fします。', chapter: 2, line: 6)
          ]

          runs = SentenceEndings.monotone_runs(sentences, min: 3)

          assert_equal 1, runs.size, '3 連続は 1 箇所だけ（別章の 2 連続は対象外）'
          run = runs.first
          assert_equal 1, run.chapter_num
          assert_equal 10, run.line, '連続の先頭行を記録する'
          assert_equal 'ます。', run.label
          assert_equal 3, run.count
        end

        def test_monotone_runs_ignores_other_category
          sentences = [sentence('良い。'), sentence('広い。'), sentence('高い。')] # すべて その他

          assert_empty SentenceEndings.monotone_runs(sentences, min: 3)
        end

        def test_run_label_for_taigen_has_no_period
          sentences = [sentence('桜。'), sentence('梅。'), sentence('菊。')]

          assert_equal '体言止め', SentenceEndings.monotone_runs(sentences, min: 3).first.label
        end

        private

        def sentence(text, chapter: 1, line: 1)
          LocatedSentence.new(chapter_num: chapter, line:, text:, length: text.length)
        end
      end
    end
  end
end
