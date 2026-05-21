# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/index/scoring_engine'

module VivlioStarter
  module CLI
    module IndexCommands
      class ScoringEngineTest < Minitest::Test
        # --- phase: setup ---

        def setup
          @engine = ScoringEngine.new
        end

        # --- phase: add_score tests ---

        def test_add_score_applies_weight_and_accumulates
          # 単一のスコア追加
          @engine.add_score('Ruby', :tf, 5.0)

          result = @engine.scores['Ruby']
          assert_equal 5.0, result[:total], 'TF weight is 1.0, so 5.0 * 1.0 = 5.0'
          assert_equal 5.0, result[:components][:tf]
        end

        def test_add_score_with_definition_weight
          # 定義パターンは高い重み（30.0）
          @engine.add_score('JavaScript', :definition, 1.0)

          result = @engine.scores['JavaScript']
          assert_equal 30.0, result[:total]
          assert_equal 30.0, result[:components][:definition]
        end

        def test_add_score_accumulates_multiple_components
          # 複数のコンポーネントを追加
          @engine.add_score('CSS', :tf, 10.0)
          @engine.add_score('CSS', :idf, 2.0)
          @engine.add_score('CSS', :heading, 1.0)

          result = @engine.scores['CSS']
          # tf: 10 * 1.0 = 10, idf: 2 * 5.0 = 10, heading: 1 * 20.0 = 20
          expected_total = 10.0 + 10.0 + 20.0
          assert_equal expected_total, result[:total]
        end

        # --- phase: calculate_tfidf tests ---

        def test_calculate_tfidf_with_valid_values
          @engine.calculate_tfidf('HTML', 5, 2, 10)

          result = @engine.scores['HTML']
          assert result[:total].positive?, 'TF-IDF should produce positive score'
          assert result[:components][:tf].positive?
          assert result[:components][:idf].positive?
        end

        def test_calculate_tfidf_skips_zero_tf
          @engine.calculate_tfidf('Empty', 0, 2, 10)

          assert_empty @engine.scores, 'Zero TF should not create score entry'
        end

        # --- phase: filter_by_threshold tests ---

        def test_filter_by_threshold_returns_sorted_hash
          @engine.add_score('High', :tf, 100.0)
          @engine.add_score('Low', :tf, 10.0)
          @engine.add_score('Medium', :tf, 50.0)

          filtered = @engine.filter_by_threshold(20.0)

          assert_equal 2, filtered.size
          assert_equal %w[High Medium], filtered.keys
        end

        def test_filter_by_threshold_excludes_below_threshold
          @engine.add_score('OnlyOne', :tf, 5.0)

          filtered = @engine.filter_by_threshold(10.0)

          assert_empty filtered
        end

        # --- phase: reset tests ---

        def test_reset_clears_all_scores
          @engine.add_score('Term1', :tf, 10.0)
          @engine.add_score('Term2', :definition, 1.0)

          @engine.reset!

          assert_empty @engine.scores
        end

        # --- phase: debug_scores tests ---

        def test_debug_scores_returns_formatted_data
          @engine.add_score('Debug', :tf, 10.0)
          @engine.add_score('Debug', :idf, 2.0)

          debug = @engine.debug_scores('Debug')

          assert_equal 'Debug', debug[:term]
          assert_kind_of Float, debug[:total]
          assert_kind_of Hash, debug[:components]
        end

        def test_debug_scores_returns_empty_data_for_unknown_term
          result = @engine.debug_scores('Unknown')

          # Hash は default ブロックで初期化されているため、空のデータを返す
          assert_equal 0.0, result[:total]
          assert_empty result[:components]
        end
      end
    end
  end
end
