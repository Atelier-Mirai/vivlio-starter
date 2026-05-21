# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/index/scoring_engine.rb
# ================================================================
# 責務:
#   索引候補語のスコアリングを行う。
#   - 複数の評価軸を統合してスコアを算出
#   - 閾値に基づいて候補をフィルタリング
#
# スコアリング要素:
#   - 出現頻度（TF）
#   - 文書頻度の逆数（IDF）
#   - 定義パターンマッチ（bonus）
#   - 専門用語パターンマッチ（bonus）
#   - 見出し近傍出現（bonus）
# ================================================================

require_relative '../common'

module VivlioStarter
  module CLI
    module IndexCommands
      # スコアリングエンジン
      class ScoringEngine
        # スコアリング係数
        WEIGHTS = {
          tf: 1.0,           # 出現頻度
          idf: 5.0,          # IDF 係数
          definition: 30.0,  # 定義パターンボーナス
          technical: 15.0,   # 専門用語ボーナス
          heading: 20.0,     # 見出し近傍ボーナス
          first_occurrence: 10.0 # 章の冒頭出現ボーナス
        }.freeze

        attr_reader :scores

        def initialize
          @scores = Hash.new { |h, k| h[k] = { total: 0.0, components: {} } }
        end

        # 用語にスコアを追加
        # @param term [String] 用語
        # @param component [Symbol] スコア要素
        # @param value [Float] スコア値
        def add_score(term, component, value)
          weight = WEIGHTS[component] || 1.0
          weighted_value = value * weight

          @scores[term][:components][component] ||= 0.0
          @scores[term][:components][component] += weighted_value
          @scores[term][:total] += weighted_value
        end

        # TF-IDF スコアを計算
        # @param term [String] 用語
        # @param tf [Integer] 出現頻度
        # @param df [Integer] 文書頻度
        # @param doc_count [Integer] 総文書数
        def calculate_tfidf(term, tf, df, doc_count)
          return if tf.zero?

          idf = Math.log((doc_count + 1.0) / (df + 1.0)) + 1.0
          add_score(term, :tf, tf)
          add_score(term, :idf, idf)
        end

        # 閾値以上のスコアを持つ用語を取得
        # @param threshold [Float] 閾値
        # @return [Hash] 用語とスコアのハッシュ
        def filter_by_threshold(threshold)
          @scores.select { _2[:total] >= threshold }
                 .sort_by { -_2[:total] }
                 .to_h
        end

        # スコアをリセット
        def reset!
          @scores.clear
        end

        # デバッグ用: スコアの内訳を表示
        def debug_scores(term)
          data = @scores[term]
          return nil unless data

          {
            term: term,
            total: data[:total].round(2),
            components: data[:components].transform_values { it.round(2) }
          }
        end
      end
    end
  end
end
