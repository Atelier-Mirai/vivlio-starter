# frozen_string_literal: true

# ================================================================
# Class: TermLine
# ----------------------------------------------------------------
# 責務:
#   レビューファイル `_index_glossary_review.md` の**用語行**を読み書きする、
#   フラグの綴りの唯一の定義元。
#
#     - [ig] `NEW!` **用語集** (ようごしゅう) - スコア: 353.0
#     - [igm33] **用語集** (ようごしゅう) - スコア: 353.0     ← 主要参照つき
#     - [igm?33] **用語集** (ようごしゅう)                    ← 機械の推測
#     - [igm21,22] **Markdown** (まーくだうん)               ← 複数章
#
# なぜ集約するのか:
#   フラグを読む正規表現が **9 箇所**に散っていた（parse_index_approved /
#   parse_unreject / parse_yomi_changes / term_blocks …）。`m33` を足すと
#   `(?:i|ig|gi|x)` が軒並みマッチしなくなり、9 箇所すべてを直すことになる。
#   フラグの語彙を増やすたびに同じ苦労を繰り返す形だった。
#
# `m` の綴り:
#   フラグ本体に `m` は使われていないので、**最初の `m` で分ける**だけで足りる。
#   値に `m` を含む章名（`21-markdown-tutorial`）が来ても、分割は最初の `m` の
#   位置で決まるため壊れない。
#
# `?` の意味:
#   `m?33` は**機械が推測した候補**、`m33` は**著者が確定した指定**。
#   そのまま `vs index:apply` すればどちらも採用されるが、著者が自分で決めた
#   ものと機械の下書きが見分けられないと、レビューが「全部確認し直す」作業になる。
#
# 仕様: index-main-reference-section-spec.md R6
# ================================================================

module VivlioStarter
  module CLI
    module IndexCommands
      # レビューファイルの用語行
      TermLine = Data.define(:flags, :main, :suggested, :term, :yomi, :label, :trailer) do
        # 用語行の綴り。`[フラグ]`『NEW! ラベル』`**用語** (読み)` と行末。
        # ここを変えると 9 つの読み取りすべてに効く——だからこそ 1 箇所に置く。
        LINE = /^- \[([^\]]*)\](?: `(NEW!|Today)`)? \*\*(.+?)\*\* \(([^)]+)\)(.*)$/

        # フラグ本体と主要参照を分ける。`igm?21,22` → ['ig', ['21','22'], true]
        FLAG_AND_MAIN = /\A([^m]*)m(\?)?(.*)\z/

        INDEX_FLAGS = %w[i ig gi x].freeze
        GLOSSARY_FLAGS = %w[g ig gi].freeze
        REJECT_BOTH_FLAGS = %w[r -ig -gi].freeze

        class << self
          # 1 行を解釈する。用語行でなければ nil
          def parse(line)
            m = LINE.match(line) or return nil

            flags, main, suggested = split_flags(m[1])
            new(flags:, main:, suggested:, term: m[3], yomi: m[4], label: m[2], trailer: m[5].to_s)
          end

          # 文字列に含まれる用語行をすべて拾う
          def scan(content)
            content.to_s.lines.filter_map { parse(it) }
          end

          # フラグ欄を組み立てる。主要参照は章番号だけのときフラグへ収める
          # ——`[igm21#Markdown とは]` は読みにくいので、そういう値は子行に譲る。
          def build(flags, main: [], suggested: false)
            tokens = Array(main)
            return "[#{flags}]" unless in_flag?(tokens)

            "[#{flags}m#{suggested ? '?' : ''}#{tokens.join(',')}]"
          end

          # フラグ欄へ収めてよい値か（章番号だけか）
          def in_flag?(tokens)
            tokens.any? && tokens.all? { it.to_s.match?(/\A\d+\z/) }
          end

          private

          def split_flags(raw)
            m = FLAG_AND_MAIN.match(raw.to_s.strip) or return [raw.to_s.strip, nil, false]

            tokens = m[3].split(/[,、]/).map(&:strip).reject(&:empty?)
            [m[1], tokens.empty? ? nil : tokens, !m[2].nil?]
          end
        end

        def index? = INDEX_FLAGS.include?(flags)
        def glossary? = GLOSSARY_FLAGS.include?(flags)
        def reject_both? = REJECT_BOTH_FLAGS.include?(flags)
        def reject_index? = flags == '-i'
        def reject_glossary? = flags == '-g'

        # 除外済みリストから拾い上げる対象（セクション 4 で復帰マークが付いた行）
        def unrejecting? = (INDEX_FLAGS + GLOSSARY_FLAGS).include?(flags)

        # 保留（`[ ]` や空欄）
        def pending? = flags.strip.empty?

        # 行末から拾えるスコア
        def score = trailer[/- スコア:\s*([\d.]+)/, 1]&.to_f
      end
    end
  end
end
