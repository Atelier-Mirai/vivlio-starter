# frozen_string_literal: true

# ================================================================
# Class: HeadingOutline
# ----------------------------------------------------------------
# 責務:
#   章の見出し構造を読み、`21#Markdown とは` のような**節の指定**を
#   原稿の行範囲へ解決する。
#
# なぜ必要か:
#   主要参照は章単位では粗すぎる。`main: 21-markdown-tutorial` と書くと
#   章題「Markdown 執筆チュートリアル」が初出になり、索引が章扉のページを
#   指してしまう。著者が指したいのは「## Markdown とは」の節である
#   （index-main-reference-section-spec.md §0.1）。
#
# 照合の約束:
#   - **文言で書く。** 節番号（`4-1`）は組版時に振られるもので原稿に無い
#   - **レベルを問わない**（h2〜h6）。実測で h4 は 56 個、h5 は 3 個ある
#   - **空白を無視して比べる。** 「CSS 組版」と「CSS組版」の揺れを吸収する
#   - 階層は上位から。**中間は省略できる**（祖先のいずれかに一致すればよい）
#
# 仕様: index-main-reference-section-spec.md R2・R3・R4
# ================================================================

require_relative '../masking'

module VivlioStarter
  module CLI
    module IndexCommands
      # 章の見出し構造
      class HeadingOutline
        # 行末は `$`（改行の手前）で止める。`\z` にすると each_prose_line が渡す
        # 改行つきの行にマッチしない。
        HEADING = /\A(\#{1,6})[ \t]+(\S.*?)[ \t]*$/

        # 見出し 1 つ。ancestors は上位の見出し（正規化済み文言）。
        Heading = Data.define(:lineno, :level, :text, :normalized, :ancestors)

        # 解決の結果。ambiguous なら候補が複数あり、著者に絞ってもらう必要がある。
        Located = Data.define(:range, :ambiguous, :candidates)

        attr_reader :headings

        # @param content [String] 章の Markdown 全文
        def self.parse(content)
          headings = []
          stack = []
          Masking.each_prose_line(content) do |line, lineno|
            m = HEADING.match(line) or next
            level = m[1].size
            stack.pop while stack.any? && stack.last.level >= level
            headings << Heading.new(
              lineno:, level:, text: m[2],
              normalized: normalize(m[2]), ancestors: stack.map(&:normalized)
            )
            stack.push(headings.last)
          end
          new(headings, content.lines.size)
        end

        # 見出しの文言を比較用に均す。
        # 見出しには強調・インラインコード・ルビ・索引タグが混ざるうえ、
        # 「CSS 組版」と「CSS組版」のような空白の揺れもある。
        def self.normalize(text)
          text.gsub(/`([^`]*)`/, '\1')
              .gsub(/\*{1,3}([^*]*)\*{1,3}/, '\1')
              .gsub(/\{([^|}]*)\|[^}]*\}/, '\1')
              .gsub(/\[([^\]|]*)(?:\|[^\]]*)?\]/, '\1')
              .gsub(/[[:space:]]+/, '')
        end

        def initialize(headings, total_lines)
          @headings = headings
          @total_lines = total_lines
        end

        # 節の指定を行範囲へ解決する。
        # @param path [Array<String>] 上位から並べた見出しの文言（中間は省略可）
        # @return [Located, nil] 見つからなければ nil
        def locate(path)
          wanted = path.map { self.class.normalize(it) }
          hits = @headings.select { matches?(it, wanted) }
          return nil if hits.empty?

          Located.new(range: range_of(hits.first), ambiguous: hits.size > 1,
                      candidates: hits.map { describe(it) })
        end

        # 警告に添える見出しの一覧（先頭から数件）
        def summary(limit: 6)
          @headings.map(&:text).first(limit)
        end

        # 「近いもの」を 1〜2 件だけ挙げる。候補を並べ立てない
        # （著者が探しているのは正解であって、選択肢の山ではない）。
        def nearest(path, limit: 2)
          wanted = self.class.normalize(path.last.to_s)
          return [] if wanted.empty?

          @headings.map { [it, similarity(it.normalized, wanted)] }
                   .select { |_, score| score >= 0.5 }
                   .max_by(limit) { |_, score| score }
                   .map { |h, _| h.text }
        end

        private

        # 末尾が指定に一致し、その手前の指定がすべて祖先に含まれること。
        # 祖先は順序を問うだけで、間に別の見出しが挟まっていてもよい。
        def matches?(heading, wanted)
          return false unless heading_matches?(heading.normalized, wanted.last)
          return true if wanted.size == 1

          rest = wanted[0..-2]
          ancestors = heading.ancestors.dup
          rest.all? do |want|
            idx = ancestors.index { heading_matches?(it, want) }
            idx && ancestors.slice!(0..idx)
          end
        end

        def heading_matches?(normalized, wanted)
          normalized == wanted || normalized.include?(wanted)
        end

        # その見出しの配下（次の同レベル以上の見出しの直前まで）
        def range_of(heading)
          idx = @headings.index(heading)
          following = @headings[(idx + 1)..].find { it.level <= heading.level }
          heading.lineno..(following ? following.lineno - 1 : @total_lines)
        end

        # 警告に出す候補。**原文で示す**——著者が読んで原稿と突き合わせる文字列なので、
        # 照合用に空白を潰した `normalized` を見せてはいけない。
        def describe(heading)
          idx = @headings.index(heading)
          level = heading.level
          chain = []
          @headings[0...idx].reverse_each do |h|
            next if h.level >= level

            chain.unshift(h.text)
            level = h.level
          end
          (chain + [heading.text]).join('#')
        end

        # 文字の重なり具合。編集距離を持ち込むほどの精度は要らない
        # ——「主な用途」→「さまざまな用途」を拾えれば十分である。
        def similarity(a, b)
          return 0.0 if a.empty? || b.empty?

          shared = a.chars.tally.sum { |ch, n| [n, b.count(ch)].min }
          shared * 2.0 / (a.length + b.length)
        end
      end
    end
  end
end
