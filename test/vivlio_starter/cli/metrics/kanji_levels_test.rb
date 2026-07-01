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

        def test_locations_list_rare_kanji_first_with_places
          sentences = [
            sentence('碍', chapter: 1, line: 10), sentence('碍', chapter: 2, line: 5),
            sentence('薔', chapter: 3, line: 7)
          ]

          locations = KanjiLevels.build_report(sentences).locations

          assert_equal '薔', locations.first[0], '出現の少ない漢字を先頭に'
          assert_equal [[3, 7]], locations.first[1]
          assert_equal [[1, 10], [2, 5]], locations.last[1]
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
