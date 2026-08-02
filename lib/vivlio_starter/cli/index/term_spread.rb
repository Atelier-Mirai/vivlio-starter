# frozen_string_literal: true

# ================================================================
# Class: TermSpread
# ----------------------------------------------------------------
# 責務:
#   語が本のどれだけ広い範囲に散らばっているかを測る。
#
# なぜ「広さ」を見るのか:
#   索引語としての価値は「広く出ること」ではなく「特定の箇所で説明されて
#   いること」である。全章にばらまかれた語は、索引から引いても読者が
#   「どこを読めばよいか」を判断できない——「ファイル」で 24 章ぶんの
#   ページ番号が並んでも、それは所在の羅列であって案内ではない。
#
# なぜ比率で判定するのか:
#   絶対章数だと薄い本と厚い本で意味が変わる。5 章の本の「3 章に出る」と
#   50 章の本の「3 章に出る」は性格がまったく違う。
#
# 数え方の約束:
#   - 照合は辞書の pattern（無ければ完全一致）。IndexMatchScanner と同じ綴り
#   - 本文は CodeBlockStripper を通す。コード例の出現で広さを膨らませない
#   - 1 章に何回出ても 1 章と数える（頻度ではなく広がりを見る指標なので）
#
# 仕様: index-term-selection-spec.md §3 R5.1
# ================================================================

require_relative '../common'
require_relative 'code_block_stripper'

module VivlioStarter
  module CLI
    module IndexCommands
      # 語の広がりを測る
      class TermSpread
        # 全章数がこれ未満の本では判定しない。
        # 5 章の本では 3 章に出るだけで比率 0.6 になり、誤検出しかしない。
        MIN_TOTAL_CHAPTERS = 6

        # 出現章数がこれ未満なら、比率がいくつでも一般語としない。
        # 2 章の本で 2 章に出れば比率 1.0 だが、それは「広い」とは言わない。
        MIN_CHAPTER_COUNT = 3

        # 語の広がり。ratio は「出現章数 / 全章数」。
        Entry = Data.define(:term, :chapter_count, :total_chapters) do
          def ratio = total_chapters.zero? ? 0.0 : chapter_count.fdiv(total_chapters)

          def percentage = (ratio * 100).round

          def to_s = "#{chapter_count}/#{total_chapters} 章（#{percentage}%）"
        end

        # 各語の広がりを測る。
        # @param terms [Array<Hash>] 辞書の用語（'term' と任意の 'pattern'）
        # @param chapters [Array<String>] 章のベースネームまたはパス
        # @return [Hash{String => Entry}]
        def self.measure(terms, chapters)
          bodies = load_bodies(chapters)
          total = bodies.size

          terms.to_h do |entry|
            name = entry['term'].to_s
            pattern = term_regexp(entry)
            count = bodies.count { it.match?(pattern) }
            [name, Entry.new(term: name, chapter_count: count, total_chapters: total)]
          end
        end

        # 一般語（＝広く散らばりすぎている語）を選ぶ。
        # 判定できない本（章が少ない）では 1 件も返さない——誤検出は
        # 「機械が余計なことを言う」形で著者の信頼を削る。
        # @param spreads [Hash{String => Entry}]
        # @param ratio [Float] この比率以上を一般語とみなす
        # @return [Array<Entry>] 広い順
        def self.common_terms(spreads, ratio:)
          return [] if spreads.empty?

          total = spreads.values.first.total_chapters
          return [] if total < MIN_TOTAL_CHAPTERS

          spreads.values
                 .select { it.chapter_count >= MIN_CHAPTER_COUNT && it.ratio >= ratio }
                 .sort_by { [-it.chapter_count, it.term] }
        end

        # 章の本文を読み、コードを除いた状態で返す
        def self.load_bodies(chapters)
          chapters.filter_map do |chapter|
            path = resolve_path(chapter)
            next unless path

            CodeBlockStripper.strip(File.read(path, encoding: 'utf-8'))
          end
        end
        private_class_method :load_bodies

        def self.resolve_path(chapter)
          return chapter if File.exist?(chapter.to_s)

          [File.join(Common::CONTENTS_DIR, "#{chapter}.md"),
           File.join(Common::BUILD_HTML_DIR, "#{chapter}.md")].find { File.exist?(it) }
        end
        private_class_method :resolve_path

        # 辞書エントリの照合パターン（IndexMatchScanner と同じ綴りの約束）
        def self.term_regexp(entry)
          raw = entry['pattern'].to_s
          return Regexp.new(Regexp.escape(entry['term'].to_s)) if raw.empty?

          body = raw.start_with?('/') && raw.end_with?('/') ? raw[1...-1] : raw
          Regexp.new(body)
        rescue StandardError
          Regexp.new(Regexp.escape(entry['term'].to_s))
        end
        private_class_method :term_regexp
      end
    end
  end
end
