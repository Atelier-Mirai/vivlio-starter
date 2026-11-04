# frozen_string_literal: true

# ================================================================
# Test: metrics/chapter_parser_test.rb
# ================================================================
# テスト対象:
#   Metrics::ChapterParser（章・節の題と分量の解析）
#
# 検証内容:
#   - 章題・節題から、手で書いた見出しラベル（@label）を外す
#   - 章扉で改行させる <br> を、書名と同じ扱いで詰める
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/metrics/config_loader'
require 'vivlio_starter/cli/metrics/formatter'
require 'vivlio_starter/cli/metrics/chapter_parser'

module VivlioStarter
  module CLI
    module Metrics
      class ChapterParserTest < Minitest::Test
        def test_should_show_titles_without_labels_and_tags
          content = <<~MD
            # 挑戦することの<br>贈り物 @ch-gift

            ## 推敲用の参考資料 @metrics-advice

            本文です。

            ## Ruby<br>Guide

            本文です。
          MD
          parser = ChapterParser.new(WarningChecker.new(ConfigLoader.new({})))

          chapter = parser.parse_content('contents/95-gift.md', content)

          assert_equal '挑戦することの贈り物', chapter.title
          assert_equal ['推敲用の参考資料', 'Ruby Guide'], chapter.sections.map(&:title)
        end
      end
    end
  end
end
