# frozen_string_literal: true

# ================================================================
# Test: metrics/consistency_test.rb
# ================================================================
# テスト対象:
#   Metrics::Consistency（章間のばらつき算出）
#
# 検証内容:
#   - 平均・標準偏差の算出（手計算一致）
#   - 平均±標準偏差を超える章を高め／低めに振り分ける
#   - 高め／低めは最大 OUTLIER_LIMIT 件
#   - 全章同値（ばらつき 0）では外れ章を出さない
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/metrics/consistency'

module VivlioStarter
  module CLI
    module Metrics
      class ConsistencyTest < Minitest::Test
        def test_computes_mean_and_population_stdev
          metric = build([['第01章', 10], ['第02章', 20], ['第03章', 30], ['第04章', 40], ['第05章', 50]])

          assert_in_delta 30.0, metric.mean, 0.001
          assert_in_delta 14.142, metric.stdev, 0.001 # sqrt(200)
        end

        def test_splits_outliers_into_high_and_low
          metric = build([['第01章', 10], ['第02章', 20], ['第03章', 30], ['第04章', 40], ['第05章', 50]])

          assert_equal [['第05章', 50]], metric.high # >= 平均+σ ≒ 44.1
          assert_equal [['第01章', 10]], metric.low  # <= 平均-σ ≒ 15.9
        end

        def test_outliers_are_capped_to_limit
          # 低値 6 章＋高値 5 章。5 章とも平均+σ を超えるが、上限 3 件に絞られる。
          lows = %w[a b c d e f].map { [it, 10] }
          highs = %w[g h i j k].map { [it, 100] }

          metric = build(lows + highs)

          assert_equal 3, metric.high.size, '最大 3 件に制限'
          assert(metric.high.all? { it[1] == 100 }, '高い側の章が選ばれる')
        end

        def test_outliers_are_ordered_by_deviation
          # 低値 10 章で平均を下げ、突出した 3 章（96/98/100）が平均+σ を超える
          lows = %w[a b c d e f g h i j].map { [it, 0] }
          metric = build(lows + [['x', 96], ['y', 98], ['z', 100]])

          # 外れの大きい順（降順）
          assert_equal %w[z y x], metric.high.map { it[0] }
        end

        def test_no_outliers_when_all_values_equal
          metric = build([['第01章', 50], ['第02章', 50], ['第03章', 50]])

          assert_in_delta 0.0, metric.stdev, 0.001
          assert_empty metric.high
          assert_empty metric.low
        end

        private

        def build(entries)
          Consistency.build(metric_label: '漢字比率', unit: '%', high_label: '高め', low_label: '低め',
                            entries:)
        end
      end
    end
  end
end
