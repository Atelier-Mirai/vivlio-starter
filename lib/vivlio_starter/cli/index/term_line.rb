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
# 印の文字の読み方（index-glossary-registration-spec.md §3.4）:
#   i = 索引、g = 用語集（x は i の古い綴り）。**マイナスは直後の 1 文字にだけ掛かる**。
#   文字の順番は問わない。
#     [-ig]・[g-i] … 索引から外し、用語集には残す
#     [i-g]・[-gi] … 用語集から外し、索引には残す
#     [-i-g]・[r]  … 両方から外して棄却する
#   機械が出す印は、いまの登録の文字をすべて含める（一般語の ig の語は [-igm?21]）。
#   `-i` だけを出すと、用語集に載っていることが行から読めなかった。
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

        # 印の 1 文字（マイナス付きを含む）。並びが全部これで書かれているときだけ印として読む
        MARK = /-?[igx]/
        MARKS = /\A(?:-?[igx])+\z/

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

        # 載せる先（マイナスの付かない文字）と、外す先（マイナスの付いた文字）
        def kept = marks.reject { it.start_with?('-') }.map { normalize(it) }.uniq
        def removed = marks.select { it.start_with?('-') }.map { normalize(it) }.uniq

        def index? = kept.include?('i') && !removed.include?('i')
        def glossary? = kept.include?('g') && !removed.include?('g')
        def reject_both? = flags.strip == 'r' || (removed.include?('i') && removed.include?('g'))
        def reject_index? = removed.include?('i') && !reject_both?
        def reject_glossary? = removed.include?('g') && !reject_both?
        # 記録ごと消す（index-glossary-registration-spec.md §3.3.3）。取り返しのつかない
        # 操作なので長い大文字の綴りにしてあるが、読むときは大文字・小文字を区別しない
        def delete? = flags.strip.casecmp?('DELETE')

        # 除外済みリストから拾い上げる対象（セクション 4 で復帰マークが付いた行）
        def unrejecting? = index? || glossary?

        # 載せる先を i・g・ig の形で（棄却した語から戻すときの登録先）
        def kept_flags = [('i' if index?), ('g' if glossary?)].compact.join

        # 保留（`[ ]` や空欄）
        def pending? = flags.strip.empty?

        # 行末から拾えるスコア
        def score = trailer[/- スコア:\s*([\d.]+)/, 1]&.to_f

        private

        def marks
          text = flags.strip
          text.match?(MARKS) ? text.scan(MARK) : []
        end

        def normalize(mark) = mark.delete('-').tr('x', 'i')
      end
    end
  end
end
