# frozen_string_literal: true

# ================================================================
# Test: metrics/readability_test.rb
# ================================================================
# テスト対象:
#   Metrics::Readability（建石・小野・山田 1988 の読みやすさ評価式）
#
# 検証内容:
#   - 特徴量抽出（文長・各文字種の連数/連文字数・句読点数）
#   - RS の手計算一致（係数の正しさ）
#   - 値が大きいほど読みやすい（漢字偏重 < ひらがな偏重）
#   - ラベル判定（バンド下限の境界）
#   - 章をまたいだ特徴量の合算
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/metrics/readability'

module VivlioStarter
  module CLI
    module Metrics
      class ReadabilityTest < Minitest::Test
        # 文字種ごとの連の数・連文字数、文・句読点を正しく数える
        def test_should_extract_character_run_features
          features = Readability.extract_features('ABCあいう漢字カタカ')

          assert_equal 3, features.alpha_char_total
          assert_equal 1, features.alpha_run_count
          assert_equal 3, features.hira_char_total
          assert_equal 1, features.hira_run_count
          assert_equal 2, features.kanji_char_total
          assert_equal 1, features.kanji_run_count
          assert_equal 3, features.kata_char_total
          assert_equal 1, features.kata_run_count
        end

        # 同一文字種が間を空けて現れたら別の連として数える
        def test_should_count_separate_runs_for_repeated_class
          features = Readability.extract_features('漢字あ漢字')

          assert_equal 4, features.kanji_char_total
          assert_equal 2, features.kanji_run_count
        end

        # 長音符（ー）はカタカナ連に含める
        def test_should_treat_prolonged_sound_mark_as_katakana
          features = Readability.extract_features('ルビー')

          assert_equal 3, features.kata_char_total
          assert_equal 1, features.kata_run_count
        end

        # 句点・読点と文の数を数える
        def test_should_count_sentences_and_punctuation
          features = Readability.extract_features('最初の文、続き。次の文。')

          assert_equal 2, features.sentence_count
          assert_equal 2, features.period_count
          assert_equal 1, features.comma_count
        end

        # 建石式の係数どおりに RS を算出する（手計算と一致）
        #   "漢字。" → ls=2, lc=2, 他0, cp=0
        #   RS = 115.79 - 0.12*2 - 23.18*2 = 69.19
        def test_should_compute_score_matching_formula
          features = Readability.extract_features('漢字。')

          assert_in_delta 69.19, Readability.score(features), 0.001
        end

        # 値が大きいほど読みやすい（ひらがな主体 > 漢字主体）
        def test_higher_score_means_easier
          easy = Readability.score(Readability.extract_features('あいうえお かきくけこ さしすせそ。'))
          hard = Readability.score(Readability.extract_features('国際連合安全保障理事会。'))

          assert_operator easy, :>, hard
        end

        # ラベルはバンド下限で判定する（大きいほど易しい）
        def test_label_uses_band_lower_bounds
          thresholds = { easy: 60, standard: 40 }

          assert_equal 'Easy', Readability.label(60.0, thresholds)
          assert_equal 'Standard', Readability.label(59.9, thresholds)
          assert_equal 'Standard', Readability.label(40.0, thresholds)
          assert_equal 'Professional', Readability.label(39.9, thresholds)
        end

        # 章をまたいだ特徴量は単純合算される
        def test_aggregate_sums_all_features
          a = Readability.extract_features('漢字。')
          b = Readability.extract_features('あい、うえ。')

          aggregated = Readability.aggregate([a, b])

          assert_equal a.sentence_count + b.sentence_count, aggregated.sentence_count
          assert_equal a.kanji_char_total + b.kanji_char_total, aggregated.kanji_char_total
          assert_equal a.comma_count + b.comma_count, aggregated.comma_count
        end

        # 空配列の合算はゼロ特徴量を返す（RS は定数項のみ）
        def test_aggregate_of_empty_is_zero
          aggregated = Readability.aggregate([])

          assert_equal 0, aggregated.sentence_count
          assert_in_delta Readability::CONSTANT, Readability.score(aggregated), 0.001
        end
      end
    end
  end
end
