# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/index/scoring_engine'

module VivlioStarter
  module CLI
    module IndexCommands
      class ScoringEngineTest < Minitest::Test
        def setup
          @engine = ScoringEngine.new
        end

        # --- phase: 性質ボーナスは語ごと 1 回（R1） ---

        def test_mark_applies_the_trait_weight
          @engine.mark('Ruby', :definition)

          assert_in_delta ScoringEngine::TRAIT_WEIGHTS[:definition], @engine.score('Ruby'), 0.001
        end

        # 旧実装は出現ごとに加算しており、頻出語ほど高スコアになる原因だった。
        # 何度記録しても 1 回ぶんにしかならないことを固定する。
        def test_marking_the_same_trait_repeatedly_counts_once
          5.times { @engine.mark('ファイル', :technical) }

          assert_in_delta ScoringEngine::TRAIT_WEIGHTS[:technical], @engine.score('ファイル'), 0.001
        end

        def test_different_traits_accumulate
          @engine.mark('Ruby', :definition)
          @engine.mark('Ruby', :technical)

          expected = ScoringEngine::TRAIT_WEIGHTS.values_at(:definition, :technical).sum

          assert_in_delta expected, @engine.score('Ruby'), 0.001
        end

        def test_unknown_trait_is_ignored
          @engine.mark('Ruby', :unknown_trait)

          assert_in_delta 0.0, @engine.score('Ruby'), 0.001
        end

        # --- phase: TF-IDF は対数 TF（R2） ---

        def test_observe_adds_tfidf
          @engine.observe('Ruby', tf: 10, df: 2, doc_count: 10)

          assert_operator @engine.score('Ruby'), :>, 0
        end

        def test_observe_skips_zero_tf
          @engine.observe('Ruby', tf: 0, df: 0, doc_count: 10)

          assert_in_delta 0.0, @engine.score('Ruby'), 0.001
          refute_includes @engine.terms, 'Ruby'
        end

        # TF が線形だとスコアが分量の写しになる。10 倍の出現でも
        # スコアは 10 倍にならないことを固定する。
        def test_tf_contributes_logarithmically
          @engine.observe('少', tf: 10, df: 1, doc_count: 10)
          @engine.observe('多', tf: 100, df: 1, doc_count: 10)

          ratio = @engine.score('多') / @engine.score('少')

          assert_operator ratio, :>, 1.0, '出現が多いほうが高いこと'
          assert_operator ratio, :<, 2.0, '10 倍の出現でスコアが 10 倍になってはならない'
        end

        # 索引語として価値があるのは「稀だが特定の章に集中する語」。
        # 出現章数が少ないほうが高くなることを固定する（IDF が効いている証拠）。
        def test_idf_favors_terms_concentrated_in_few_documents
          @engine.observe('専門語', tf: 50, df: 2, doc_count: 27)
          @engine.observe('一般語', tf: 50, df: 25, doc_count: 27)

          assert_operator @engine.score('専門語'), :>, @engine.score('一般語')
        end

        # 実データで起きていた逆転（頻出の一般語が上位を占める）が
        # 直っていることを、仕様書 §1.2 の実例に近い値で確認する。
        def test_frequent_generic_term_scores_below_rare_specific_term
          # 「ファイル」相当: 全 27 章中 24 章に 371 回
          @engine.mark('ファイル', :technical)
          @engine.observe('ファイル', tf: 371, df: 24, doc_count: 27)
          # 「アインシュタイン」相当: 4 章に 70 回
          @engine.mark('アインシュタイン', :technical)
          @engine.observe('アインシュタイン', tf: 70, df: 4, doc_count: 27)

          assert_operator @engine.score('アインシュタイン'), :>, @engine.score('ファイル'),
                          '稀で集中する語が、頻出の一般語より上に来ること'
        end

        # --- phase: 集計 API ---

        def test_terms_includes_marked_and_observed
          @engine.mark('A', :definition)
          @engine.observe('B', tf: 5, df: 1, doc_count: 5)

          assert_equal %w[A B], @engine.terms.sort
        end

        def test_scores_returns_every_term
          @engine.mark('A', :definition)
          @engine.observe('B', tf: 5, df: 1, doc_count: 5)

          assert_equal %w[A B], @engine.scores.keys.sort
        end

        def test_reset_clears_all_scores
          @engine.mark('Ruby', :definition)
          @engine.observe('Ruby', tf: 5, df: 1, doc_count: 5)

          @engine.reset!

          assert_empty @engine.terms
          assert_in_delta 0.0, @engine.score('Ruby'), 0.001
        end

        def test_breakdown_returns_components
          @engine.mark('Ruby', :definition)
          @engine.observe('Ruby', tf: 5, df: 1, doc_count: 5)

          result = @engine.breakdown('Ruby')

          assert_equal 'Ruby', result[:term]
          assert_equal [:definition], result[:traits]
          assert_operator result[:tfidf], :>, 0
          assert_in_delta ScoringEngine::TRAIT_WEIGHTS[:definition], result[:trait_bonus], 0.001
        end

        def test_breakdown_returns_nil_for_unknown_term
          assert_nil @engine.breakdown('未登録')
        end
      end
    end
  end
end
