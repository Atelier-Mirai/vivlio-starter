# frozen_string_literal: true

# ================================================================
# Class: MainReferenceSuggester
# ----------------------------------------------------------------
# 責務:
#   主要参照（その語を腰を据えて説明している章）の候補を 1 章だけ算出する。
#
# 決め方:
#   スコア = h1 に含む数 × 3 ＋ h2 に含む数 × 2 ＋ h3 に含む数 × 1 ＋ 章内の出現回数
#   最大の章を選び、同点なら章番号の若い方（実行ごとに順位が揺れると差分が読めない）。
#
# なぜこの式か（実測で決めた）:
#   著者が手で決めた 44 語を正解として突き合わせた結果である。
#
#     見出しヒット数だけ（旧実装）  45%   候補を出せない語 14 語
#     出現回数だけ                61%   0 語
#     出現密度                   56%   0 語
#     h1 優先＋見出し数            43%   14 語
#     **この式**                 **65%**  **0 語**
#
#   旧実装が弱かったのは「見出しに出ない語には候補を出せない」ため。出現回数を
#   足すと全語に候補を出せる——「予め設定しておく」にはこれが前提になる。
#
#   **定義パターンの加点はしない。** 重み 0 / 3 / 8 のいずれでも 65% で変わらず、
#   効かない要素を残すと後から触る人が「効くはず」と誤解する。
#
# なぜ候補どまりなのか:
#   65% は「候補」として十分でも、確定させるには足りない。残り 35% は著者が直す。
#   索引語 153 語のうち「ファイル」は 42 の見出しに当たるといった偏りがあり、
#   主要参照がいちばん必要な頻出語ほど機械には決めにくい。
#
# 仕様: index-main-reference-section-spec.md R5
# ================================================================

require_relative '../common'
require_relative 'code_block_stripper'
require_relative 'term_pattern'

module VivlioStarter
  module CLI
    module IndexCommands
      # 主要参照の候補を算出する
      class MainReferenceSuggester
        # 見出し行（レベルつき）
        HEADING = /^(\#{1,6})[ \t]+(.+)$/

        # 見出しレベル別の重み。h4 以下は重みを持たない（出現回数として数える）
        HEADING_WEIGHTS = { 1 => 3, 2 => 2, 3 => 1 }.freeze

        # 索引に出るページ番号が 1 つしかない語には主要参照が要らない。
        # 太字にしても読者に伝わる情報が増えない（実測で該当は 1 語）。
        MIN_OCCURRENCES = 2

        # 1 章ぶんの素材
        Chapter = Data.define(:basename, :headings, :body) do
          def score(pattern)
            weighted = HEADING_WEIGHTS.sum do |level, weight|
              headings.fetch(level, []).count { it.match?(pattern) } * weight
            end
            weighted + body.scan(pattern).size
          end

          def number = basename[/\A\d+/].to_i
        end

        # @param terms [Array<Hash>] 辞書エントリ（'term' と任意の 'pattern'）
        # @param chapters [Array<String>] 章のベースネームまたはパス
        # @return [Hash{String => String}] 用語 → 章のベースネーム（候補なしの語は含まない）
        def self.suggest(terms, chapters)
          return {} if terms.empty? || chapters.empty?

          new(chapters).suggest(terms)
        end

        def initialize(chapters)
          @chapters = load_chapters(chapters)
        end

        # @return [Hash{String => String}]
        def suggest(terms)
          terms.filter_map do |entry|
            name = entry['term'].to_s
            next if name.empty?

            pattern = TermPattern.for(entry)
            next if total_occurrences(pattern) < MIN_OCCURRENCES

            chapter = best_chapter(pattern)
            [name, chapter] if chapter
          end.to_h
        end

        private

        def load_chapters(chapters)
          chapters.filter_map { resolve_path(it) }
                  .sort_by { File.basename(it, '.md') }
                  .map do |path|
            body = CodeBlockStripper.strip(File.read(path, encoding: 'utf-8'))
            headings = Hash.new { |h, k| h[k] = [] }
            body.scan(HEADING) { |mark, text| headings[mark.size] << text }
            Chapter.new(basename: File.basename(path, '.md'), headings:, body:)
          end
        end

        def total_occurrences(pattern) = @chapters.sum { it.body.scan(pattern).size }

        # スコア最大の章。同点なら章番号の若い方
        def best_chapter(pattern)
          scored = @chapters.filter_map do |chapter|
            score = chapter.score(pattern)
            [chapter, score] if score.positive?
          end
          return nil if scored.empty?

          scored.max_by { |chapter, score| [score, -chapter.number] }.first.basename
        end

        def resolve_path(chapter)
          return chapter if File.exist?(chapter.to_s)

          [File.join(Common::CONTENTS_DIR, "#{chapter}.md"),
           File.join(Common::BUILD_HTML_DIR, "#{chapter}.md")].find { File.exist?(it) }
        end
      end
    end
  end
end
