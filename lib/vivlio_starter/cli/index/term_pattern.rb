# frozen_string_literal: true

# ================================================================
# Module: TermPattern
# ----------------------------------------------------------------
# 責務:
#   辞書エントリ（`term` と任意の `pattern`）を照合用の Regexp にする、
#   索引まわりで**唯一の綴りの解釈**。
#
# なぜ 1 箇所へ集めるか:
#   同じ「スラッシュを剥がして Regexp にする」3 行が TermSpread と
#   IndexCandidateExtractor に重複しており、主要参照の候補算出
#   （MainReferenceSuggester）で 3 箇所目になった。剥がし方がずれると
#   「広さは数えるのに候補は出ない」という噛み合わない挙動になる。
#
# 綴りの約束:
#   辞書の `pattern` は `/\bRuby\b/` のようにスラッシュで囲む。ASCII 語だけ
#   `\b` が付く（UnifiedTermsManager#build_pattern）。Ruby の `\b` は日本語を
#   語構成文字として扱うため `/\bRuby\b/` は「Rubyの話」に**当たらない**が、
#   本文タグ付け（IndexMatchScanner）が同じ解釈で動いている以上、候補算出も
#   同じ側に揃える必要がある——ここだけ緩めると、索引に載らない章を
#   主要参照として勧めることになる。
# ================================================================

module VivlioStarter
  module CLI
    module IndexCommands
      # 辞書エントリ → 照合用 Regexp
      module TermPattern
        module_function

        # @param entry [Hash] 'term' と任意の 'pattern' を持つ辞書エントリ
        # @return [Regexp]
        def for(entry)
          raw = entry['pattern'].to_s
          return literal(entry) if raw.empty?

          body = raw.start_with?('/') && raw.end_with?('/') ? raw[1...-1] : raw
          Regexp.new(body)
        rescue StandardError
          # 壊れた pattern で走査全体を止めない。完全一致へ落として先へ進む
          literal(entry)
        end

        def literal(entry) = Regexp.new(Regexp.escape(entry['term'].to_s))
      end
    end
  end
end
