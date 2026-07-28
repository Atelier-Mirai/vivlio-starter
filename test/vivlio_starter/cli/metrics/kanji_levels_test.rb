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
