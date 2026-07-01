# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/metrics/consistency.rb
# ================================================================
# 責務:
#   章ごとの指標（漢字比率・平均文長など）の「章間のばらつき」を集計し、
#   平均から外れた章（難しすぎ／易しすぎ・長すぎ／短すぎ）を抽出する。
#
# 目的:
#   全体の平均値だけでは「どの章が浮いているか」が分からない。平均±標準偏差
#   を超える章を高め／低めに振り分けて提示し、推敲（書き直し）の手掛かりにする。
# ================================================================

module VivlioStarter
  module CLI
    module Metrics
      # 1 指標分のばらつき結果。high/low は [章ラベル, 値] の配列。
      ConsistencyMetric = Data.define(
        :label, :unit, :high_label, :low_label, :mean, :stdev, :high, :low
      )

      # 章間のばらつきを算出する。
      module Consistency
        module_function

        # 高め／低めとして挙げる章の最大数。
        OUTLIER_LIMIT = 3

        # @param entries [Array<[String, Numeric]>] [章ラベル, 値] の配列
        # @return [ConsistencyMetric]
        def build(metric_label:, unit:, high_label:, low_label:, entries:)
          values = entries.map { it[1] }
          mean = values.sum.to_f / values.size
          stdev = Math.sqrt(values.sum { (it - mean)**2 } / values.size)

          # ばらつきが無い（全章同じ）ときは外れ章なし。threshold が平均と一致して
          # 全章が拾われるのを防ぐ。
          high = stdev.positive? ? outliers(entries, threshold: mean + stdev, order: :desc) : []
          low = stdev.positive? ? outliers(entries, threshold: mean - stdev, order: :asc) : []

          ConsistencyMetric.new(
            label: metric_label, unit:, high_label:, low_label:, mean:, stdev:, high:, low:
          )
        end

        # 平均±標準偏差を超える章を、外れの大きい順に最大 OUTLIER_LIMIT 件返す。
        def outliers(entries, threshold:, order:)
          selected = order == :desc ? entries.select { it[1] >= threshold } : entries.select { it[1] <= threshold }
          sorted = order == :desc ? selected.sort_by { -it[1] } : selected.sort_by { it[1] }
          sorted.first(OUTLIER_LIMIT)
        end
      end
    end
  end
end
