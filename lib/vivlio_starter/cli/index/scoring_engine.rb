# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/index/scoring_engine.rb
# ================================================================
# 責務:
#   索引候補語のスコアを算出する。重み・係数の**唯一の定義元**。
#
# スコアの構成:
#   スコア = TF-IDF ＋ 性質ボーナス
#     TF-IDF     … 出現の偏りを見る。TF は対数化する
#     性質ボーナス … 定義パターン・専門用語・名詞連続。**語ごとに 1 回だけ**
#
# なぜ TF を対数化するか:
#   線形だとスコアが分量の写しになり、「ファイル」「コード」のような頻出語が
#   際限なく上位へ来る。索引語としての価値と逆相関する状態だった（実測で
#   スコア上位が PDF 7728 / ファイル 5269 / ビルド 3301 …）。索引語は分量に
#   比例せず逓減する（Heaps 則）ので、TF も対数で効かせる。
#
# なぜボーナスを語ごと 1 回にするか:
#   旧実装は 3 経路すべてが出現ごとの加算だった（定義パターン +30 / 専門用語
#   +15 / 名詞連続 +10 を scan のマッチごとに）。カタカナ 3 文字以上は専門用語
#   パターンに当たるので、「ファイル」は 371 回 × 15 = 5,565 点をここだけで得て
#   いた。TF が三重に計上され、頻出語ほど高スコアになる構造だった。
#
# 仕様: index-term-selection-spec.md §3（R1・R2）
# ================================================================

require_relative '../common'

module VivlioStarter
  module CLI
    module IndexCommands
      # スコアリングエンジン
      class ScoringEngine
        # 語が持つ性質のボーナス。**語ごとに 1 回だけ**効く（出現数では増えない）。
        TRAIT_WEIGHTS = {
          definition: 30.0,    # 「〜とは」など定義パターンに現れた
          technical: 15.0,     # カタカナ語・英字語などの専門用語らしさ
          noun_sequence: 10.0, # MeCab が拾った名詞連続
          heading: 20.0        # 見出しに現れた（現時点では未使用・主要参照仕様で使う）
        }.freeze

        # TF-IDF のスケール係数。閾値との突き合わせではなく順位付けに使うので、
        # 値そのものに意味はない（単調変換は順位を変えない）。
        TFIDF_SCALE = 30.0

        # default_proc は使わない——読むだけでキーが生まれ、スコアを問い合わせた
        # だけの語が terms に混ざる。登録は mark / observe でしか起きない形にする。
        def initialize
          @traits = {}
          @tfidf = {}
        end

        # 語に性質を記録する。同じ性質を何度記録しても 1 回ぶんにしかならない。
        # @param term [String] 用語
        # @param trait [Symbol] TRAIT_WEIGHTS のキー
        def mark(term, trait)
          Common.log_debug("未知の性質を無視します: #{trait}") unless TRAIT_WEIGHTS.key?(trait)
          (@traits[term] ||= Set[]) << trait if TRAIT_WEIGHTS.key?(trait)
        end

        # 出現統計から TF-IDF を与える（語につき 1 回呼ぶ）。
        # @param term [String] 用語
        # @param tf [Integer] 全文書での延べ出現数
        # @param df [Integer] その語が現れた文書数
        # @param doc_count [Integer] 総文書数
        def observe(term, tf:, df:, doc_count:)
          return if tf.to_i.zero?

          idf = Math.log((doc_count + 1.0) / (df + 1.0)) + 1.0
          @tfidf[term] = (1 + Math.log(tf)) * idf * TFIDF_SCALE
        end

        # 記録済みの全用語
        def terms = (@traits.keys + @tfidf.keys).uniq

        # 1 語のスコア
        def score(term) = @tfidf.fetch(term, 0.0) + trait_bonus(term)

        # 用語 → スコアのハッシュ
        def scores = terms.to_h { [it, score(it)] }

        # 閾値以上のスコアを持つ用語を降順で取得
        # @param threshold [Float] 閾値
        # @return [Hash] 用語とスコアのハッシュ
        def filter_by_threshold(threshold)
          scores.select { |_, v| v >= threshold }.sort_by { -_2 }.to_h
        end

        # スコアをリセット
        def reset!
          @traits.clear
          @tfidf.clear
        end

        # デバッグ用: スコアの内訳
        # @return [Hash, nil] 記録の無い語なら nil
        def breakdown(term)
          return nil unless terms.include?(term)

          {
            term:,
            total: score(term).round(2),
            tfidf: @tfidf.fetch(term, 0.0).round(2),
            traits: @traits.fetch(term, []).to_a.sort,
            trait_bonus: trait_bonus(term).round(2)
          }
        end

        private

        def trait_bonus(term) = @traits.fetch(term, []).sum { TRAIT_WEIGHTS.fetch(it) }
      end
    end
  end
end
