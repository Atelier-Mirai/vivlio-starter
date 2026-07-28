# frozen_string_literal: true

# ================================================================
# Test: metrics/kanji_levels_test.rb
# ================================================================
# テスト対象:
#   Metrics::KanjiLevels（漢字レベル判定とルビ候補の集計）
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/metrics/sentence_collector'
require 'vivlio_starter/cli/metrics/kanji_levels'

module VivlioStarter
  module CLI
    module Metrics
      class KanjiLevelsTest < Minitest::Test
        def test_level_of_classifies_by_data_and_jis
          assert_equal :kyoiku, KanjiLevels.level_of('一') # 小1（教育）
          assert_equal :chugaku, KanjiLevels.level_of('換') # 中学で習う常用
          assert_equal :ippan, KanjiLevels.level_of('碍')  # JIS第一水準 ∖ 常用
          assert_equal :senmon, KanjiLevels.level_of('薔')  # JIS第二水準
        end

        def test_grade_of_returns_assigned_school_year
          assert_equal 1, KanjiLevels.grade_of('一')
          assert_equal 4, KanjiLevels.grade_of('城')   # 2017年告示で 6年 → 4年
          assert_equal 6, KanjiLevels.grade_of('胃')   # 2017年告示で 4年 → 6年
          assert_nil KanjiLevels.grade_of('換'), '中学（L1）は学年を持たない'
          assert_nil KanjiLevels.grade_of('碍'), '常用外（L2）は同梱データに無い'
        end

        # 都道府県名の 20 字は 2017年告示（2020年度施行）で中学から小4へ移った。
        # 古い配当表のままだと「小4向け」のルビ付与で本来不要な漢字が候補になる。
        def test_prefecture_kanji_are_assigned_to_grade_four
          '井佐埼奈媛岐岡崎栃梨沖滋潟熊縄茨阜阪香鹿'.each_char do |char|
            assert_equal 4, KanjiLevels.grade_of(char), "#{char} は小4のはず"
          end
        end

        # grade_of と level_of は同じ表の同じ値を見るので、両者の食い違いは起こらない。
        # 「grade_of(1)〜(6) の合計＝level_of が :kyoiku を返す字数」が全字で成り立つ。
        def test_grade_of_and_level_of_agree_over_the_whole_table
          by_grade = Hash.new(0)
          kyoiku = 0

          KanjiLevels.table.each_key do |char|
            grade = KanjiLevels.grade_of(char)
            kyoiku += 1 if KanjiLevels.level_of(char) == :kyoiku
            by_grade[grade] += 1 if grade
          end

          assert_equal KanjiLevels::GRADES.to_a, by_grade.keys.sort
          assert_equal kyoiku, by_grade.values.sum
          # 学年別漢字配当表（2017年3月告示・2020年度施行）の公式字数
          assert_equal({ 1 => 80, 2 => 160, 3 => 200, 4 => 202, 5 => 193, 6 => 191 }, by_grade.sort.to_h)
        end

        def test_build_report_aggregates_levels_lists_and_locations
          sentences = [
            sentence('一の碍', chapter: 1, line: 10),
            sentence('碍と薔', chapter: 2, line: 5)
          ]

          report = KanjiLevels.build_report(sentences)

          assert_equal [['教育', 25], ['一般(L2)', 50], ['専門(L3)', 25]], report.ratios
          assert_equal [['碍', 2]], report.lists[:ippan]
          assert_equal [['薔', 1]], report.lists[:senmon]
          assert_empty report.lists[:chugaku]
        end

        # 並びは初出の章・行順（原稿を頭から開いてルビを書き足せるように）
        def test_locations_are_ordered_by_first_occurrence
          sentences = [
            sentence('碍', chapter: 1, line: 10), sentence('碍', chapter: 2, line: 5),
            sentence('薔', chapter: 3, line: 7)
          ]

          locations = KanjiLevels.build_report(sentences).locations

          assert_equal %w[碍 薔], locations.map { it[0] }
          assert_equal [[1, 10], [2, 5]], locations.first[1]
          assert_equal [[3, 7]], locations.last[1]
        end

        # 挙げる漢字の選抜そのものは「出現の少ない順」。上限（15 字）を超えたら、
        # 章の後ろに 1 度だけ出る漢字が残り、何度も出る漢字のほうが落ちる。
        def test_locations_select_rarest_kanji_when_over_limit
          # 一般・専門漢字 15 字を第 1 章に 2 回ずつ、稀な 1 字を最終章に 1 回だけ置く
          frequent = '碍亘叩坦尖彦棲歪稀罫揃雛梱薔俯'.each_char.flat_map do |char|
            [sentence(char, chapter: 1, line: 10), sentence(char, chapter: 1, line: 20)]
          end
          sentences = frequent + [sentence('閾', chapter: 9, line: 99)]

          locations = KanjiLevels.build_report(sentences).locations

          assert_equal KanjiLevels::LOCATION_CHAR_LIMIT, locations.size
          assert_equal '閾', locations.last[0], '1 度しか出ない漢字は必ず残る（並びは初出順なので末尾）'
          assert_equal 1, locations.count { it[1].size == 1 }, '落ちるのは出現の多い漢字のほう'
        end

        def test_build_report_returns_nil_without_kanji
          assert_nil KanjiLevels.build_report([sentence('あいうえお')])
        end

        private

        def sentence(text, chapter: 1, line: 1)
          LocatedSentence.new(chapter_num: chapter, line:, text:, length: text.length)
        end
      end
    end
  end
end
