# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/metrics/content_words.rb
# ================================================================
# 責務:
#   形態素（MeCab/IPADIC の品詞情報）から「内容語」を選び、頻度順に並べる。
#
# 目的:
#   同じ語の使いすぎ（言い換え候補）を見つける。助詞・助動詞などの機能語は
#   除き、名詞・固有名詞・形容動詞・動詞・形容詞といった意味のある語を数える。
#
# 設計:
#   品詞判定（classify）と並べ替え（rank）は MeCab に依存しない純粋関数に保ち、
#   テストしやすくする。実際の形態素解析は Analyzer 側が担い、その素性配列を
#   classify に渡す。
# ================================================================

module VivlioStarter
  module CLI
    module Metrics
      # 内容語 1 語（基本形と表示用の品詞ラベル）。
      ContentWord = Data.define(:word, :pos)
      # 頻度集計後の 1 語。
      RankedWord = Data.define(:word, :pos, :count)

      module ContentWords
        module_function

        # 内容語として採用する名詞の細分類 → 表示ラベル。
        NOUN_LABELS = {
          '固有名詞' => '固有名詞',
          '形容動詞語幹' => '形容動詞',
          'ナイ形容詞語幹' => '形容動詞',
          '一般' => '名詞',
          'サ変接続' => '名詞',
          '副詞可能' => '名詞'
        }.freeze

        # ほぼ機能語として頻出し、内容語の一覧を埋めてしまう一般動詞は除く。
        STOPWORDS = %w[する なる ある いる できる].freeze

        # 表の区切り（|）や記号など、単語文字を含まないトークンを内容語から除く。
        WORD_CHAR = /[\p{Han}\p{Hiragana}\p{Katakana}A-Za-z0-9]/

        # 形態素 1 つを内容語に分類する。内容語でなければ nil。
        # @param features [Array<String>] MeCab の素性（品詞, 細分類1, …, 基本形, …）
        def classify(surface, features)
          pos = features[0]
          sub = features[1]
          word = base_form(surface, features)
          return nil if STOPWORDS.include?(word)
          return nil unless word.match?(WORD_CHAR)

          label = label_for(pos, sub)
          return nil unless label
          # 単漢字の「固有名詞」は MeCab の誤判定が大半（章・全・行 など）。
          # 正当な固有名詞（PDF・Vivliostyle 等）は 2 字以上なので、ここで弾く。
          return nil if label == '固有名詞' && word.length == 1

          ContentWord.new(word:, pos: label)
        end

        # 内容語の配列を頻度順（同数は語の昇順）に上位 limit 件へ集計する。
        def rank(words, limit:)
          words.each_with_object(Hash.new(0)) { |w, tally| tally[[w.word, w.pos]] += 1 }
               .sort_by { |(word, _pos), count| [-count, word] }
               .first(limit)
               .map { |(word, pos), count| RankedWord.new(word:, pos:, count:) }
        end

        # --- 内部ヘルパー ---

        def label_for(pos, sub)
          case pos
          when '名詞' then NOUN_LABELS[sub]
          when '動詞' then sub == '自立' ? '動詞' : nil
          when '形容詞' then sub == '自立' ? '形容詞' : nil
          end
        end

        # 基本形があればそれを、無ければ（固有名詞など）表層形を使う。
        def base_form(surface, features)
          base = features[6]
          base && base != '*' ? base : surface
        end
      end
    end
  end
end
