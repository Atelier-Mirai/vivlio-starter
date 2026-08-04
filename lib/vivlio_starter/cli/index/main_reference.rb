# frozen_string_literal: true

# ================================================================
# Class: MainReference
# ----------------------------------------------------------------
# 責務:
#   辞書 `main:` の 1 要素を「章」と「節のパス」に分ける、綴りの唯一の解釈。
#
#     "33-index-glossary"            → 章だけ
#     "21#Markdown とは"              → 章＋節
#     "23#章の削除（vs delete）#基本的な使い方" → 章＋節（祖先つき・曖昧さの解消）
#
# なぜ `#` か:
#   Markdown の見出し記号がそのまま「その見出しを指す」と読める。URL の
#   フラグメントとも同じ感覚で、著者に説明が要らない。
#
# 仕様: index-main-reference-section-spec.md R2
# ================================================================

module VivlioStarter
  module CLI
    module IndexCommands
      # `main:` の 1 要素
      MainReference = Data.define(:chapter, :path) do
        # @param value [String] 例 "21#Markdown とは"
        def self.parse(value)
          chapter, *path = value.to_s.split('#')
          new(chapter: chapter.to_s.strip, path: path.map(&:strip).reject(&:empty?))
        end

        # 辞書へ書き戻す形（著者が書いたとおりに保つ）
        def to_s = ([chapter] + path).join('#')

        def section? = path.any?
      end
    end
  end
end
