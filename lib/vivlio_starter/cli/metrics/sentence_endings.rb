# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/metrics/sentence_endings.rb
# ================================================================
# 責務:
#   文末表現を分類し、その内訳と「同じ文末の連続」を集計する。
#
# 目的:
#   「〜です。〜です。〜です。」のように同じ文末が続くと文章が単調になる。
#   文末の内訳（です・ます／体言止め／だ・である／その他）と、同一文末が
#   3 つ以上連続する箇所を示し、リズムを整える手掛かりにする。
#
# 方針:
#   形態素解析に頼らずパターンで分類する（です・ます／だ・である は確実、
#   体言止めは「文末がひらがな以外＝名詞止め」とみなす近似）。連続は文末の
#   細かいキー（です／ます/…）単位で数え、最初の出現位置を記録する。
# ================================================================

module VivlioStarter
  module CLI
    module Metrics
      # 同一文末が連続した箇所。line は連続の先頭（最初の出現）の行。
      SentenceRun = Data.define(:chapter_num, :line, :label, :count)

      module SentenceEndings
        module_function

        # 連続とみなす最小本数。です・ます中心の和文では 3〜4 連続は普通のため、
        # 「気になるほどの単調さ」の目安として 5 連続以上を拾う。
        MIN_RUN = 5
        # 長い順（最長一致）に判定する丁寧体・常体の語尾。
        POLITE = %w[ませんでした でしょう ましょう ですか ますか でした ました ません ます です].freeze
        PLAIN = %w[であった である だった だ].freeze
        # 内訳で示す大分類（表示順）。
        CATEGORIES = ['です・ます', '体言止め', 'だ・である', 'その他'].freeze

        # 文末の細かいキー（連続判定・ラベル用）を返す。
        def classify(text)
          body = text.sub(/[。．！？!?]+\z/, '').rstrip
          return 'その他' if body.empty?

          POLITE.each { |suffix| return suffix if body.end_with?(suffix) }
          PLAIN.each { |suffix| return suffix if body.end_with?(suffix) }
          return '体言止め' if taigen?(body[-1])

          'その他'
        end

        # 細かいキーを内訳の大分類へ畳む。
        def category(key)
          return 'です・ます' if POLITE.include?(key)
          return 'だ・である' if PLAIN.include?(key)
          return '体言止め' if key == '体言止め'

          'その他'
        end

        # 大分類ごとの割合（％、四捨五入）を表示順のハッシュで返す。
        def distribution(sentences)
          return CATEGORIES.to_h { [it, 0] } if sentences.empty?

          counts = sentences.each_with_object(Hash.new(0)) { |s, acc| acc[category(classify(s.text))] += 1 }
          total = sentences.size.to_f
          CATEGORIES.to_h { [it, (counts[it] / total * 100).round] }
        end

        # 同一文末が MIN_RUN 以上連続する箇所を、章ごとに検出する。
        def monotone_runs(sentences, min: MIN_RUN)
          sentences.group_by(&:chapter_num).flat_map { |_num, group| chapter_runs(group, min) }
        end

        # --- 内部ヘルパー ---

        def chapter_runs(sentences, min)
          keys = sentences.map { classify(it.text) }
          runs = []
          start = 0
          while start < sentences.size
            stop = start
            stop += 1 while stop < sentences.size && keys[stop] == keys[start]
            length = stop - start
            runs << build_run(sentences[start], keys[start], length) if length >= min && keys[start] != 'その他'
            start = stop
          end
          runs
        end

        def build_run(first, key, length)
          SentenceRun.new(chapter_num: first.chapter_num, line: first.line, label: run_label(key), count: length)
        end

        # 語尾語は「です。」のように句点付き、体言止めはそのまま。
        def run_label(key) = key == '体言止め' ? key : "#{key}。"

        # 文末の最後の 1 文字がひらがな以外（漢字・カタカナ・英数）なら名詞止めとみなす。
        def taigen?(char) = char&.match?(/[\p{Han}\p{Katakana}A-Za-z0-9ー]/) || false
      end
    end
  end
end
