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

        def plan(chapters: %w[11-a], prose_chars: BOOK_CHARS, registered: 153, glossary: 40, rejected: 90,
                 undecided: 0, target: 'standard', bands: nil)
          estimator = IndexSizeEstimator.new(prose_chars)
          registration = IndexPlanReporter::Registration.new(index: registered, glossary:, rejected:, undecided_main: undecided)
          IndexPlanReporter::Plan.new(
            chapters:, prose_chars:, registration:,
            estimate: estimator.estimate(target), all_estimates: estimator.all_presets, bands:
          )
        end

        # 帯の表示だけを見たいので、順位付けは通さず結果を直接組む
        def bands(recommended: %w[新語A 新語B], general: %w[一般A])
          entry = ->(t) { TermRanking::Entry.new(term: t, score: 1.0, registered: false) }
          TermRanking::Bands.new(recommended: recommended.map { entry[it] }, general: general.map { entry[it] },
                                 target: 357, pool_size: 1071)
        end

        def render(plan_data)
          out, = capture_io { IndexPlanReporter.new(plan_data).render }
          out
        end

        # --- phase: 現況の表示 ---

        def test_render_shows_volume_and_registration
          out = render(plan(chapters: %w[11-a 12-b]))

          assert_includes out, '2 章'
          assert_includes out, '129,006 字', '3 桁区切りで表示する'
          assert_includes out, 'いまの登録: 索引 153 語・用語集 40 語・棄却 90 語'
        end

        # 主要参照が決まっていない語は、あるときだけ数を出す（index-glossary-registration-spec.md §5.3）
        def test_render_shows_undecided_main_references_only_when_any
          assert_includes render(plan(undecided: 2)), '主要参照が決まっていない索引語 2 語'
          refute_includes render(plan(undecided: 0)), '主要参照が決まっていない'
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

          %w[light（少なめ） standard（標準） thorough（多め）].each { assert_includes out, it }
          assert_includes out, '244〜356 語', 'standard の目安（実測較正）'
          assert_includes out, '132〜183 語', 'light の目安'
          assert_includes out, '458〜468 語', 'thorough の目安'
        end

        def test_render_marks_the_current_preset
          out = render(plan(target: 'light'))
          current = out.lines.find { it.include?('← 現在') }

          assert_includes current.to_s, 'light（少なめ）', '現在の設定に印が付く'
          assert_includes out, '■ いまの目安（index.target_terms: light ＝ 少なめ）'
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
          out = render(plan(bands: bands))

          refute_match(/上位 \d+%まで/, out)
          refute_match(/\d+%〜\d+%/, out)
        end

        # 著者がスコアで判断する場面は無いので、スコアの分布・候補の総数は出さない（§5.1）
        def test_render_omits_scores_and_candidate_totals
          out = render(plan(bands: bands))

          refute_includes out, 'スコア'
          refute_includes out, '■ 候補'
          refute_includes out, '提示していません'
          refute_includes out, '見直し候補'
        end

        # --- phase: vs index:auto を実行すると（呼び名はレビューファイルの節にそろえる） ---

        def test_render_tells_what_auto_will_list
          out = render(plan(bands: bands))

          assert_includes out, '■ vs index:auto を実行すると'
          assert_includes out, '推奨する語 2 語・残りの語 1 語をレビューファイルに並べます'
          assert_includes out, '推奨する語の例: 新語A / 新語B'
        end

        def test_render_truncates_long_previews_and_says_so
          out = render(plan(bands: bands(recommended: (1..12).map { "語#{it}" })))

          assert_includes out, '…他 7 語', '5 件だけ出して、残りは件数で言う'
        end

        def test_render_explains_when_candidate_extraction_is_off
          out = render(plan(bands: nil))

          assert_includes out, 'index.auto_discovery: false'
          refute_includes out, '推奨する語', '候補抽出が無効なときに空の帯を出さない'
        end

        # --- phase: 末尾の案内（改善案 #99: auto はこの画面を出さず、plan だけが出す） ---

        def test_render_ends_by_saying_nothing_was_written
          out = render(plan)

          assert_equal '※ vs index:plan は下見です。辞書・レビューファイルは変更していません', out.lines.last.chomp
        end
      end
    end
  end
end
