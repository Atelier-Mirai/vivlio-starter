# frozen_string_literal: true

# ================================================================
# Test: metrics/volume_none_test.rb
# ================================================================
# テスト対象:
#   metrics.use: none（v2-architecture-spec.md §6）
#   - 章・節の分量の判定（💡 加筆検討・やや長い／✅ ちょうどよい）を出さない
#   - 文章の質の指摘と、字数の表示は残る
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/metrics'

module VivlioStarter
  module CLI
    class MetricsVolumeNoneTest < Minitest::Test
      def test_should_judge_volume_unless_use_is_none
        assert_predicate loader('standard'), :judge_volume?
        assert_predicate loader('relative'), :judge_volume?
        refute_predicate loader('none'), :judge_volume?
      end

      def test_should_not_warn_about_volume_when_use_is_none
        checker = Metrics::WarningChecker.new(loader('none'))

        assert_nil checker.chapter_warning(11, 10)
        assert_nil checker.section_warning(10, chapter_num: 11)
        refute checker.has_warning?(11, 10, [])
      end

      def test_should_still_warn_with_a_preset
        checker = Metrics::WarningChecker.new(loader('standard'))

        assert_equal '加筆検討', checker.chapter_warning(11, 10)
      end

      def test_chapter_line_should_keep_the_count_and_drop_the_volume_marks
        chapter = Metrics::ChapterMetrics.new(path: 'contents/11-a.md', title: '始める', chapter_num: 11,
                                              chars: 6000, sections: [], warning: nil)
        none = Metrics::Formatter.new(loader('none')).format_chapter_line(chapter, 6000, false,
                                                                          extra_warnings: ['表現が単調'])
        standard = Metrics::Formatter.new(loader('standard')).format_chapter_line(chapter, 6000, false)

        assert_includes none, '6,000'
        refute_includes none, '✅'
        assert_includes none, '🤔 表現が単調', '文章の質の指摘は残る'
        assert_includes standard, '✅', '基準のある本では ✅ が出る（比べの相手）'
      end

      private

      def loader(use) = Metrics::ConfigLoader.new({ metrics: { use: } })
    end
  end
end
