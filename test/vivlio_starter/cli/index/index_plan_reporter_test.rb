# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/index/index_plan_reporter'
require 'vivlio_starter/cli/index/term_ranking'

module VivlioStarter
  module CLI
    module IndexCommands
      class IndexPlanReporterTest < Minitest::Test
        # 本書の実測値を既定に使う（仕様書 §6.2 の表示例と揃える）
        BOOK_CHARS = 129_006

        def plan(chapters: %w[11-a], prose_chars: BOOK_CHARS, registered: 153, scores: [],
                 target: 'standard', bands: nil)
          estimator = IndexSizeEstimator.new(prose_chars)
          IndexPlanReporter::Plan.new(
            chapters:, prose_chars:, registered_terms: registered, candidate_scores: scores,
            estimate: estimator.estimate(target), all_estimates: estimator.all_presets, bands:
          )
        end

        # 帯の表示だけを見たいので、順位付けは通さず結果を直接組む
        def bands(recommended: %w[新語A 新語B], general: %w[一般A], review: %w[旧語A], hidden: 0)
          entry = ->(t, reg) { TermRanking::Entry.new(term: t, score: 1.0, registered: reg, manual: false) }
          TermRanking::Bands.new(
            recommended: recommended.map { entry[it, false] },
            general: general.map { entry[it, false] },
            review: review.map { entry[it, true] },
            hidden_count: hidden, target: 357, pool_size: 1071, total: 100 + hidden
          )
        end

        def render(plan_data, dry_run: false)
          out, = capture_io { IndexPlanReporter.new(plan_data).render(dry_run:) }
          out
        end

        # --- phase: 現況の表示 ---

        def test_render_shows_volume_registration_and_candidates
          out = render(plan(chapters: %w[11-a 12-b], scores: [10, 20, 30]))

          assert_includes out, '2 章'
          assert_includes out, '129,006 字', '3 桁区切りで表示する'
          assert_includes out, '索引語の登録: 153 語'
          assert_includes out, '候補: 3 件'
        end

        # --- phase: 操作盤であること（§6.2 の要点） ---

        # 著者の問いは「260 語にしたい。どのキーをいくつにすればよいか」。
        # 現況の羅列では答えにならないので、3 点が揃っていることを固定する。
        def test_render_is_a_control_panel_not_a_report
          out = render(plan)

          assert_includes out, '■ いまの目安', '① いまの設定と、そこから決まる目安'
          assert_includes out, '■ 設定を変えるとこうなります', '② 設定を変えたらどうなるか'
          assert_includes out, 'target_terms:', '③ 書くべき YAML そのもの'
        end

        def test_render_lists_every_preset_with_its_target
          out = render(plan)

          %w[light standard thorough].each { assert_includes out, it }
          assert_includes out, '244〜356 語', 'standard の目安（実測較正）'
          assert_includes out, '132〜183 語', 'light の目安'
          assert_includes out, '458〜468 語', 'thorough の目安'
        end

        def test_render_marks_the_current_preset
          out = render(plan(target: 'light'))
          current = out.lines.find { it.include?('← 現在') }

          assert_includes current.to_s, 'light', '現在の設定に印が付く'
        end

        # 著者は「500 字に 1 語」という密度で考える。設定は語数で持つので、
        # この列が両者をつなぐ橋になる。無くなると操作盤の意味が半減する。
        def test_render_shows_chars_per_term_as_a_bridge
          out = render(plan)

          assert_includes out, '字に 1 語'
          assert_includes out, '約 362〜528 字に 1 語', 'standard の密度'
        end

        def test_render_shows_gap_from_target
          out = render(plan(registered: 153))

          assert_includes out, '下回っています'
          assert_includes out, '91 語', '244 - 153 = 91'
        end

        def test_render_reports_when_registration_exceeds_target
          out = render(plan(registered: 500))

          assert_includes out, '上回っています'
        end

        def test_render_reports_when_registration_is_within_target
          out = render(plan(registered: 300))

          assert_includes out, '範囲内です'
        end

        # 語数を直接指定したときは、幅ではなく 1 点で示す
        def test_integer_target_is_shown_as_single_value
          out = render(plan(target: 260))

          assert_includes out, 'index.target_terms: 260'
          assert_includes out, '260 語 ＝ 約 496 字に 1 語'
        end

        # --- phase: 表示の作法（§6.4） ---

        # 割合（「上位 60%」）は出さない。決まるのは語数と順位なので、
        # 100 点満点に準えて逆の意味に読まれる表現を持ち込まない。
        def test_render_does_not_use_percentage_bands
          out = render(plan(scores: (1..100).to_a))

          refute_match(/上位 \d+%まで/, out)
          refute_match(/\d+%〜\d+%/, out)
        end

        def test_render_shows_five_number_summary
          out = render(plan(scores: [10, 20, 30, 40, 50]))

          assert_includes out, 'スコア分布'
          assert_includes out, '最小 10'
          assert_includes out, '最大 50'
        end

        def test_render_omits_distribution_when_no_candidates
          out = render(plan(scores: []))

          refute_includes out, 'スコア分布', '候補が無いときに空の分布を出さない'
          assert_includes out, '候補: 0 件'
        end

        # --- phase: 帯の表示（§3.4-1 / §6.4） ---

        def test_render_shows_the_three_bands
          out = render(plan(scores: [10, 20], bands: bands))

          assert_includes out, '推奨候補'
          assert_includes out, '一般候補'
          assert_includes out, '見直し候補'
          assert_includes out, '同じ土俵でスコア順に並べた結果'
        end

        def test_render_previews_band_contents
          out = render(plan(scores: [10], bands: bands(recommended: %w[新語A 新語B], review: %w[旧語A])))

          assert_includes out, '推奨候補の例: 新語A / 新語B'
          assert_includes out, '見直し候補の例: 旧語A'
        end

        def test_render_truncates_long_previews_and_says_so
          out = render(plan(scores: [10], bands: bands(recommended: (1..12).map { "語#{it}" })))

          assert_includes out, '…他 7 語', '5 件だけ出して、残りは件数で言う'
        end

        # 提示しなかったぶんは黙らせない（no silent caps）
        def test_render_reports_hidden_candidates
          out = render(plan(scores: [10], bands: bands(hidden: 3_197)))

          assert_includes out, '3,197 件は提示していません'
          assert_includes out, 'candidate_pool'
        end

        def test_render_omits_hidden_notice_when_nothing_was_dropped
          out = render(plan(scores: [10], bands: bands(hidden: 0)))

          refute_includes out, '提示していません'
        end

        def test_render_omits_bands_when_not_available
          out = render(plan(scores: [10], bands: nil))

          refute_includes out, '推奨候補', '候補抽出が無効なときに空の帯を出さない'
        end

        # --- phase: plan と auto の差は末尾だけ（§6.3） ---

        def test_dry_run_differs_only_in_the_footer
          data = plan(scores: [10, 20, 30])
          plan_out = render(data, dry_run: true)
          auto_out = render(data, dry_run: false)

          assert_includes plan_out, '辞書・レビューファイルは変更していません'
          refute_includes auto_out, '辞書・レビューファイルは変更していません'

          assert_equal plan_out.lines[0..-2], auto_out.lines[0..-2],
                       'plan と auto で本体の表示が変わってはならない'
        end
      end
    end
  end
end
