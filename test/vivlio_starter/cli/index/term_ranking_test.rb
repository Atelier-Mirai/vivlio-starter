# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/index/term_ranking'

module VivlioStarter
  module CLI
    module IndexCommands
      class TermRankingTest < Minitest::Test
        def registered(*names) = names.map { { 'term' => it } }

        def build(registered:, registered_scores:, candidate_scores:, target: 3, pool: 2.0)
          TermRanking.build(registered:, registered_scores:, candidate_scores:, target:, pool:)
        end

        # --- phase: 語数ではなく重要度で決める（§3.4-1 の要点） ---

        # 「目安に達しているから推奨する語は 0 件」は誤り。登録語より重要な
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

        # 登録語も目安の枠を占める。枠に入る未登録語は、登録語を除いた残りの枠の分だけ
        def test_registered_terms_take_their_place_in_the_target
          bands = build(
            registered: registered('強い語'),
            registered_scores: { '強い語' => 100.0 },
            candidate_scores: { 'A' => 90.0, 'B' => 80.0, 'C' => 70.0 },
            target: 3
          )

          assert_equal %w[A B], bands.recommended.map(&:term)
          assert_equal %w[C], bands.general.map(&:term)
        end

        # 登録語は帯に出さない。目安の外に出た登録語を「見直し候補」として並べる帯は
        # なくした（index-glossary-registration-spec.md §5.2）
        def test_registered_terms_are_never_listed_in_the_bands
          bands = build(
            registered: registered('弱い語'),
            registered_scores: { '弱い語' => 1.0 },
            candidate_scores: { 'A' => 100.0, 'B' => 90.0, 'C' => 80.0, 'D' => 70.0 },
            target: 3
          )

          refute_includes (bands.recommended + bands.general).map(&:term), '弱い語'
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
      end
    end
  end
end
