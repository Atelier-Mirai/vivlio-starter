# frozen_string_literal: true

# ================================================================
# Test: guards/chapter_target_check_test.rb
# ================================================================
# テスト対象:
#   Guards::ChapterTargetCheck（lib/vivlio_starter/cli/guards/chapter_target_check.rb）
#
# 検証内容:
#   - 解決できる指定（番号 / 範囲 / ベース名 / スラグ）は合格
#   - 解決できない指定が 1 つでもあれば :error（＝ vs build を止める）
#   - 理由で文面を分ける（原稿が無い／catalog.yml 未登録）
#   - 範囲指定は欠けている番号まで名指しする
#   - 打ち間違いに「もしかして」を 1 件だけ添える（綴り／番号の 2 段構え）
#   - 引数なし（フルビルド）は検査対象外
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/guards'

module VivlioStarter
  module CLI
    class GuardsChapterTargetCheckTest < Minitest::Test
      # 引数なしはフルビルド。検査するものが無い
      def test_should_pass_when_no_targets_given
        with_project do
          assert_empty validate([])
          assert_empty validate([''])
        end
      end

      # 番号・範囲・ベース名・スラグ、どの綴りでも解決できれば合格
      def test_should_pass_for_every_resolvable_spelling
        with_project do
          assert_empty validate(%w[11]), '番号'
          assert_empty validate(%w[11-12]), '範囲'
          assert_empty validate(%w[11-install]), 'ベース名'
          assert_empty validate(%w[install]), 'スラグ'
          assert_empty validate(%w[11-install 12-tutorial]), '複数指定'
        end
      end

      # 実在しない章は :error。打ったとおりの綴りで名指しする
      def test_should_report_error_for_unknown_chapters
        with_project do
          violations = validate(%w[abc 11-nonexistent])

          assert_equal 1, violations.size
          assert_predicate violations.first, :error?
          assert_includes violations.first.message, 'abc'
          assert_includes violations.first.message, '11-nonexistent'
          assert violations.first.detail.any? { it.include?('catalog.yml') }, 'detail に対処を含むべき'
        end
      end

      # 一部だけ解決できても止める。解決できたぶんだけ組むと
      # 「2 章のつもりが 1 章」が成功として終わってしまう
      def test_should_report_error_when_only_some_targets_resolve
        with_project do
          violations = validate(%w[11-install abc])

          assert_equal 1, violations.size
          assert_includes violations.first.message, 'abc'
          refute_includes violations.first.message, '11-install', '解決できた章は責めない'
        end
      end

      # 範囲は欠けている番号まで言う。"11-13" とだけ返すと 11・12 まで無いように読める
      def test_should_name_the_missing_number_inside_a_range
        with_project do
          violations = validate(%w[11-13])

          assert_equal 1, violations.size
          assert_includes violations.first.message, '11-13 のうち第 13 章'
        end
      end

      # 原稿はあるが catalog.yml 未登録なら、直し方は「登録する」であって
      # 「章を探す」ではない。文面を分ける
      def test_should_distinguish_uncataloged_chapter_from_missing_one
        with_project do
          write_content('21-draft') # catalog.yml には書かない

          violations = validate(%w[21-draft])

          assert_equal 1, violations.size
          assert_includes violations.first.message, 'catalog.yml に登録されていません'
          assert violations.first.detail.any? { it.include?('追加してください') }
        end
      end

      # 理由が混在したら、それぞれの対処を別々に出す
      def test_should_split_violations_by_reason
        with_project do
          write_content('21-draft')

          violations = validate(%w[abc 21-draft])

          assert_equal 2, violations.size
          assert(violations.any? { it.message.include?('見つかりません') })
          assert(violations.any? { it.message.include?('登録されていません') })
        end
      end

      # ------------------------------------------------------------
      # もしかして（打ち間違いの候補）
      # ------------------------------------------------------------

      # 綴りが近ければ before → after で打ち直せる形にして返す
      def test_should_suggest_the_nearest_chapter_name
        with_project do
          detail = validate(%w[11-instal]).first.detail

          assert_includes detail, 'もしかして:'
          assert_includes detail, '  11-instal → 11-install'
        end
      end

      # 綴りが遠くても番号が合っていれば、著者はその章を指したかったとみてよい
      def test_should_fall_back_to_the_chapter_with_the_same_number
        with_project do
          detail = validate(%w[11-nonexistent]).first.detail

          assert_includes detail, '  11-nonexistent → 11-install'
        end
      end

      # 手がかりが無ければ黙る。当てずっぽうの候補は catalog.yml を見るより手間が増える
      def test_should_not_guess_when_nothing_is_close
        with_project do
          detail = validate(%w[abc]).first.detail

          refute(detail.any? { it.include?('もしかして') })
        end
      end

      # 候補は 1 件だけ。並べると著者は結局 catalog.yml を見に行く
      def test_should_offer_at_most_one_suggestion_per_target
        with_project do
          detail = validate(%w[11-instal]).first.detail
          suggestions = detail.select { it.start_with?('  11-instal →') }

          assert_equal 1, suggestions.size
        end
      end

      # 範囲指定に章名を差し出しても意味がない
      def test_should_not_suggest_for_a_range
        with_project do
          detail = validate(%w[11-13]).first.detail

          refute(detail.any? { it.include?('もしかして') })
        end
      end

      # catalog.yml 未登録は綴りが合っているので、候補ではなく登録を促す
      def test_should_not_suggest_for_uncataloged_chapter
        with_project do
          write_content('21-draft')

          detail = validate(%w[21-draft]).first.detail

          refute(detail.any? { it.include?('もしかして') })
          assert(detail.any? { it.include?('追加してください') })
        end
      end

      private

      def validate(targets) = Guards::ChapterTargetCheck.new(targets).validate

      def with_project
        Dir.mktmpdir('vs-chapter-target') do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p('config')
            FileUtils.mkdir_p('contents')
            File.write('config/catalog.yml',
                       "PREFACE:\nCHAPTERS:\n  - 11-install\n  - 12-tutorial\nAPPENDICES:\nPOSTFACE:\n")
            %w[11-install 12-tutorial].each { write_content(it) }
            yield
          end
        end
      end

      def write_content(basename)
        File.write("contents/#{basename}.md", "# #{basename}\n")
      end
    end
  end
end
