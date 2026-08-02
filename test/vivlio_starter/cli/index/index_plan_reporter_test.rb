# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/index/index_plan_reporter'
require 'tmpdir'
require 'fileutils'

module VivlioStarter
  module CLI
    module IndexCommands
      class IndexPlanReporterTest < Minitest::Test
        # --- phase: setup ---

        def setup
          @original_dir = Dir.pwd
          @temp_dir = Dir.mktmpdir('index_plan_test')
          Dir.chdir(@temp_dir)
          FileUtils.mkdir_p('contents')
        end

        def teardown
          Dir.chdir(@original_dir)
          FileUtils.rm_rf(@temp_dir)
        end

        def plan(chapters: %w[11-a], prose_chars: 50_000, registered: 100, scores: [])
          IndexPlanReporter::Plan.new(
            chapters:, prose_chars:, registered_terms: registered, candidate_scores: scores
          )
        end

        def render(plan_data, dry_run: false)
          out, = capture_io { IndexPlanReporter.new(plan_data).render(dry_run:) }
          out
        end

        # --- phase: 文字数の計数は Metrics::Analyzer に委ねる（§3.3） ---

        # コードブロックと Markdown 記法は地の文に数えない。
        # 索引語はコードから拾わないので、コード量が目安語数を押し上げてはならない。
        def test_prose_chars_excludes_code_blocks_and_markup
          File.write('contents/11-a.md', <<~MD)
            # 見出し

            これは地の文です。

            ```ruby
            puts 'これはコードなので数えない'
            ```
          MD

          chars = IndexPlanReporter.prose_chars_of(%w[11-a])

          assert_operator chars, :>=, 8, '地の文は数える'
          assert_operator chars, :<, 20, 'コードブロックと見出し記号は数えない'
        end

        def test_prose_chars_is_zero_for_missing_chapter
          assert_equal 0, IndexPlanReporter.prose_chars_of(%w[99-missing])
        end

        # --- phase: 表示の作法（§6.2 / §6.3） ---

        def test_render_shows_volume_registration_and_candidates
          out = render(plan(chapters: %w[11-a 12-b], prose_chars: 128_839, registered: 153, scores: [10, 20, 30]))

          assert_includes out, '2 章'
          assert_includes out, '128,839 字', '3 桁区切りで表示する'
          assert_includes out, '索引語の登録: 153 語'
          assert_includes out, '候補抽出: 3 件'
        end

        # 割合（「上位 60%」）は出さない。決まるのは語数と順位なので、
        # 100 点満点に準えて逆の意味に読まれる表現を持ち込まない（§6.3）。
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
          assert_includes out, '候補抽出: 0 件'
        end

        # --- phase: plan と auto の差は末尾だけ（§6.2） ---

        def test_dry_run_differs_only_in_the_footer
          data = plan(scores: [10, 20, 30])
          plan_out = render(data, dry_run: true)
          auto_out = render(data, dry_run: false)

          assert_includes plan_out, '辞書・レビューファイルは変更していません'
          refute_includes auto_out, '辞書・レビューファイルは変更していません'

          # 末尾の案内を除いた本体は一致すること
          assert_equal plan_out.lines[0..-2], auto_out.lines[0..-2],
                       'plan と auto で本体の表示が変わってはならない'
        end
      end
    end
  end
end
