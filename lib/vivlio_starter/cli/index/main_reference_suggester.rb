# frozen_string_literal: true

# ================================================================
# Class: MainReferenceSuggester
# ----------------------------------------------------------------
# 責務:
#   主要参照（その語を腰を据えて説明している章）の候補を 1 章だけ算出する。
#
# なぜ「候補」どまりなのか:
#   見出し一致で主要参照を決める案を実測した。索引語 153 語のうち 120 語（78%）
#   は何らかの見出しに現れるが、当たり方は偏る——「ファイル」は 42 見出しに
#   当たり、絞り込みの役に立たない。頻出語ほど自動判定が効かないという、
#   主要参照がいちばん要る側で外れる分布だった。
#   よって確定は著者に委ね、ここは提示に徹する
#   （index-main-reference-spec.md §1.2・R2）。
#
# 優先順位:
#   1. その語を含む見出し（h1〜h3）が最も多い章。同数なら章番号の若い方
#   2. 見出しヒットが 0 なら、定義パターンが当たった章
#   3. どちらも無ければ候補なし（レビューファイルに行を出さない）
#
# 仕様: index-main-reference-spec.md R2
# ================================================================

require_relative '../common'
require_relative 'code_block_stripper'
require_relative 'term_pattern'
require_relative 'index_candidate_extractor'

module VivlioStarter
  module CLI
    module IndexCommands
      # 主要参照の候補を算出する
      class MainReferenceSuggester
        # 見出し行（h1〜h3）。`\#` で始めるのは式展開と読み違えないため
        HEADING_PATTERN = /^\#{1,3}[ \t]+(.+)$/

        # 「〜とは」の直前で捕まえた塊がこの語で終わっていれば、その章で
        # 定義されているとみなす。DEFINITION_PATTERNS は語の前後を広めに拾うので、
        # 部分一致にすると「ファイル」が「設定ファイル」の定義に引きずられる。
        DEFINITION_PATTERNS = IndexCandidateExtractor::DEFINITION_PATTERNS

        # @param terms [Array<Hash>] 辞書エントリ（'term' と任意の 'pattern'）
        # @param chapters [Array<String>] 章のベースネームまたはパス
        # @return [Hash{String => String}] 用語 → 章のベースネーム（候補なしの語は含まない）
        def self.suggest(terms, chapters)
          return {} if terms.empty? || chapters.empty?

          new(chapters).suggest(terms)
        end

        def initialize(chapters)
          @headings = {}
          @definitions = {}
          load_chapters(chapters)
        end

        # @return [Hash{String => String}]
        def suggest(terms)
          terms.filter_map do |entry|
            name = entry['term'].to_s
            next if name.empty?

            chapter = by_heading(entry) || by_definition(name)
            [name, chapter] if chapter
          end.to_h
        end

        private

        # 章の本文から「見出し行」と「定義された語の塊」だけを取り出して持つ。
        # 本文そのものは保持しない——判定に要るのはこの 2 つだけで、
        # 全章ぶんの本文を抱えると索引語の数だけ再走査することになる。
        def load_chapters(chapters)
          chapters.sort_by { File.basename(it.to_s, '.md') }.each do |chapter|
            path = resolve_path(chapter)
            next unless path

            body = CodeBlockStripper.strip(File.read(path, encoding: 'utf-8'))
            basename = File.basename(path, '.md')
            @headings[basename] = body.scan(HEADING_PATTERN).flatten
            @definitions[basename] = collect_defined_chunks(body)
          end
        end

        def collect_defined_chunks(body)
          DEFINITION_PATTERNS.flat_map { body.scan(it).flatten }.compact.map(&:strip)
        end

        # 見出しヒットが最多の章。同数なら章番号の若い方（@headings は章順）
        def by_heading(entry)
          pattern = TermPattern.for(entry)
          counts = @headings.transform_values { |lines| lines.count { it.match?(pattern) } }
          best = counts.values.max

          return nil if best.nil? || best.zero?

          counts.find { |_, n| n == best }&.first
        end

        # 見出しに出ない語の受け皿。「〜とは」で説明している章を拾う
        def by_definition(name)
          @definitions.find { |_, chunks| chunks.any? { it.end_with?(name) } }&.first
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
