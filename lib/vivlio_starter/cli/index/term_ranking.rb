# frozen_string_literal: true

# ================================================================
# Class: TermRanking
# ----------------------------------------------------------------
# 責務:
#   登録済みの索引語と未登録の候補を**同じ土俵**でスコア順に並べ、
#   推奨候補・一般候補・見直し候補の 3 帯に分ける。
#
# なぜ語数の過不足で決めないか:
#   「目安に達しているから推奨候補は 0 件」は誤りである。語数が足りていても、
#   スコアの高い語が未登録ならそれは索引に入るべき語であり、逆に語数が
#   足りなくても重要でない語を足す意味はない。決めるのは**重要度**である。
#
#   同じ土俵で並べると「入れ替え」の視点が自然に得られる——推奨候補 5 語・
#   見直し候補 5 語なら、語数を変えずに索引の質だけを上げられる。
#
# 手動マークアップの扱い:
#   著者が原稿に [用語|読み] と書いた語は見直し候補へ出さない。著者の明示を
#   最優先する本プロジェクトの流儀に加え、実装上の理由もある——登録語のスコアは
#   定義パターン・名詞連続の性質を判定できないぶん控えめに出るので、
#   機械が「外しては」と言う根拠として弱い（IndexCandidateExtractor#score_terms）。
#
# 仕様: index-term-selection-spec.md §3.4-1
# ================================================================

module VivlioStarter
  module CLI
    module IndexCommands
      # 登録語と候補を一列に並べて帯に分ける
      class TermRanking
        # 順位付けの 1 行
        Entry = Data.define(:term, :score, :registered, :manual) do
          def unregistered? = !registered
        end

        # 帯分けの結果。target は目安語数、pool_size は候補として提示する上限順位。
        Bands = Data.define(:recommended, :general, :review, :hidden_count, :target, :pool_size, :total)

        # @param registered [Array<Hash>] 辞書の索引語（'term' / 'source'）
        # @param registered_scores [Hash{String => Float}] 登録語のスコア
        # @param candidate_scores [Hash{String => Float}] 候補のスコア
        # @param target [Integer] 目安語数（帯の境目）
        # @param pool [Float] 目安語数の何倍までを候補として提示するか
        # @return [Bands]
        def self.build(registered:, registered_scores:, candidate_scores:, target:, pool:)
          manual = registered.select { it['source'].to_s == 'manual_markup' }.map { it['term'] }.to_set
          names = registered.map { it['term'] }.to_set

          entries = registered.map do |entry|
            name = entry['term']
            Entry.new(term: name, score: registered_scores.fetch(name, 0.0),
                      registered: true, manual: manual.include?(name))
          end
          entries += candidate_scores.reject { |term, _| names.include?(term) }
                                     .map { |term, score| Entry.new(term:, score:, registered: false, manual: false) }

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
          inside = @sorted.first(@target)
          outside = @sorted.drop(@target)

          Bands.new(
            recommended: inside.select(&:unregistered?),
            general: outside.first(@pool_size - @target).select(&:unregistered?),
            review: outside.select { it.registered && !it.manual },
            hidden_count: [@sorted.size - @pool_size, 0].max,
            target: @target,
            pool_size: @pool_size,
            total: @sorted.size
          )
        end
      end
    end
  end
end
