# frozen_string_literal: true

# ================================================================
# Class: TermRanking
# ----------------------------------------------------------------
# 責務:
#   登録済みの索引語と未登録の候補を**同じ土俵**でスコア順に並べ、
#   未登録の候補を「推奨する語」（目安の語数の内側）と「残りの語」の 2 帯に分ける。
#
# なぜ語数の過不足で決めないか:
#   「目安に達しているから推奨する語は 0 件」は誤りである。語数が足りていても、
#   スコアの高い語が未登録ならそれは索引に入るべき語であり、逆に語数が
#   足りなくても重要でない語を足す意味はない。決めるのは**重要度**である。
#   登録語も同じ土俵に並べるのは、目安の語数のうち登録語が占める分を除いた枠に、
#   未登録の候補がどれだけ入るかを決めるため。
#
# 登録語を「見直し候補」として出す帯は、なくした。目安の外に出た登録語は、著者が選んだ
# 語のうち機械が当てられなかった語（本書では 4 割）で、外したほうがよい語ではなかった
# （index-glossary-registration-spec.md §5.2）。
#
# 仕様: index-term-selection-spec.md §3.4-1
# ================================================================

module VivlioStarter
  module CLI
    module IndexCommands
      # 登録語と候補を一列に並べて帯に分ける
      class TermRanking
        # 順位付けの 1 行
        Entry = Data.define(:term, :score, :registered) do
          def unregistered? = !registered
        end

        # 帯分けの結果。target は目安語数、pool_size は候補として提示する上限順位。
        Bands = Data.define(:recommended, :general, :target, :pool_size)

        # @param registered [Array<Hash>] 辞書の索引語（'term'）
        # @param registered_scores [Hash{String => Float}] 登録語のスコア
        # @param candidate_scores [Hash{String => Float}] 候補のスコア
        # @param target [Integer] 目安語数（帯の境目）
        # @param pool [Float] 目安語数の何倍までを候補として提示するか
        # @return [Bands]
        def self.build(registered:, registered_scores:, candidate_scores:, target:, pool:)
          names = registered.map { it['term'] }.to_set

          entries = registered.map do |entry|
            Entry.new(term: entry['term'], score: registered_scores.fetch(entry['term'], 0.0), registered: true)
          end
          entries += candidate_scores.reject { |term, _| names.include?(term) }
                                     .map { |term, score| Entry.new(term:, score:, registered: false) }

          # 同点は語名で決める——実行ごとに順位が揺れると差分が読めなくなる
          sorted = entries.sort_by { [-it.score, it.term] }
          pool_size = [(target * pool).round, target].max

          new(sorted, target, pool_size).bands
        end

        def initialize(sorted, target, pool_size)
          @sorted = sorted
          @target = target
          @pool_size = pool_size
        end

        def bands
          Bands.new(
            recommended: @sorted.first(@target).select(&:unregistered?),
            general: @sorted.drop(@target).first(@pool_size - @target).select(&:unregistered?),
            target: @target,
            pool_size: @pool_size
          )
        end
      end
    end
  end
end
