# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/index/term_ranking'

module VivlioStarter
  module CLI
    module IndexCommands
      class TermRankingTest < Minitest::Test
        def registered(*names, manual: [])
          names.map { { 'term' => it, 'source' => manual.include?(it) ? 'manual_markup' : 'auto_extracted' } }
        end

        def build(registered:, registered_scores:, candidate_scores:, target: 3, pool: 2.0)
          TermRanking.build(registered:, registered_scores:, candidate_scores:, target:, pool:)
        end

        # --- phase: 語数ではなく重要度で決める（§3.4-1 の要点） ---

        # 「目安に達しているから推奨候補は 0 件」は誤り。登録語より重要な
        # 未登録語があるなら、それは索引に入るべき語である。
        def test_recommends_unregistered_terms_even_when_target_is_met
          bands = build(
            registered: registered('低1', '低2', '低3'),
            registered_scores: { '低1' => 10.0, '低2' => 9.0, '低3' => 8.0 },
            candidate_scores: { '重要' => 100.0 },
            target: 3
          )

          assert_equal ['重要'], bands.recommended.map(&:term),
                       '登録語が目安に達していても、上位に食い込む未登録語は推奨に出る'
        end

        # 枠外へ押し出された登録語は見直し候補になる。
        # 推奨と見直しが同時に出ることで「入れ替え」の視点が得られる。
        def test_registered_terms_pushed_out_of_target_become_review
          bands = build(
            registered: registered('弱い語'),
            registered_scores: { '弱い語' => 1.0 },
            candidate_scores: { 'A' => 100.0, 'B' => 90.0, 'C' => 80.0 },
            target: 3
          )

          assert_equal %w[A B C], bands.recommended.map(&:term)
          assert_equal ['弱い語'], bands.review.map(&:term)
        end

        # 著者が原稿に [用語|読み] と書いた語は機械が「外しては」と言わない。
        def test_manual_markup_terms_are_never_listed_for_review
          bands = build(
            registered: registered('手動語', '自動語', manual: ['手動語']),
            registered_scores: { '手動語' => 1.0, '自動語' => 1.0 },
            candidate_scores: { 'A' => 100.0, 'B' => 90.0, 'C' => 80.0 },
            target: 3
          )

          assert_equal ['自動語'], bands.review.map(&:term)
          refute_includes bands.review.map(&:term), '手動語'
        end

        # --- phase: 帯の範囲 ---

        def test_general_band_covers_target_to_pool_size
          candidates = (1..10).to_h { ["C#{it}", (100 - it).to_f] }
          bands = build(registered: [], registered_scores: {}, candidate_scores: candidates,
                        target: 3, pool: 2.0)

          assert_equal %w[C1 C2 C3], bands.recommended.map(&:term)
          assert_equal %w[C4 C5 C6], bands.general.map(&:term), '4〜6 位（pool_size = 3 × 2）'
          assert_equal 6, bands.pool_size
        end

        # 提示しなかったぶんは黙らせない（no silent caps）
        def test_hidden_count_reports_what_was_not_shown
          candidates = (1..10).to_h { ["C#{it}", (100 - it).to_f] }
          bands = build(registered: [], registered_scores: {}, candidate_scores: candidates,
                        target: 3, pool: 2.0)

          assert_equal 4, bands.hidden_count, '10 件中 6 件を提示、残り 4 件'
          assert_equal 10, bands.total
        end

        def test_pool_never_shrinks_below_target
          bands = build(registered: [], registered_scores: {},
                        candidate_scores: { 'A' => 3.0, 'B' => 2.0, 'C' => 1.0 },
                        target: 3, pool: 0.5)

          assert_equal 3, bands.pool_size, 'pool が 1 未満でも目安ぶんは提示する'
        end

        # --- phase: 決定性 ---

        # 同点の順序が実行ごとに揺れると、前回との差分が読めなくなる。
        def test_ties_are_broken_by_term_name
          scores = { 'ゐ' => 5.0, 'あ' => 5.0, 'か' => 5.0 }
          first = build(registered: [], registered_scores: {}, candidate_scores: scores, target: 3)
          second = build(registered: [], registered_scores: {}, candidate_scores: scores.to_a.reverse.to_h, target: 3)

          assert_equal first.recommended.map(&:term), second.recommended.map(&:term)
        end

        # --- phase: 端の条件 ---

        def test_registered_term_without_score_falls_to_the_bottom
          bands = build(
            registered: registered('死語'),
            registered_scores: {}, # 原稿に出現しない＝スコアが取れない
            candidate_scores: { 'A' => 1.0, 'B' => 0.5, 'C' => 0.1 },
            target: 3
          )

          assert_equal ['死語'], bands.review.map(&:term)
        end

        def test_registered_terms_inside_target_are_not_reviewed
          bands = build(
            registered: registered('強い語'),
            registered_scores: { '強い語' => 100.0 },
            candidate_scores: { 'A' => 1.0 },
            target: 3
          )

          assert_empty bands.review
          assert_equal ['A'], bands.recommended.map(&:term)
        end
      end
    end
  end
end
