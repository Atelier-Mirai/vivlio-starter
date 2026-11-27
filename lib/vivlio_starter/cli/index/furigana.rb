# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/index/furigana.rb
# ================================================================
# 責務:
#   用語集の見出し語に振るふりがなを、字の種類ごとに決める（改善案 #175）。
#     - 漢字   … 辞書の読み（yomi）から漢字の部分の読みを割り出し、ひらがなで振る
#     - 英字   … 著者が確かめた読み（辞書の furigana:）だけを、カタカナで振る
#     - かな   … 振らない（字面がそのまま読み）
#   あわせて、英字の読みの候補を同梱の読みの辞書から引く。
#
# なぜ語の全体に振らないのか:
#   全体に振ると「ローカルストレージ」の上に「ろーかるすとれーじ」、「JIS 配列」の上に
#   「JIS はいれつ」が付く。読み方が字面から分からない所に振るのが、ふりがなの役目。
#
# なぜ英字は候補どまりなのか:
#   英字の読みは決まりで決まらない。同じ数字でも UTF-8 はエイト、Windows95 はきゅうじゅうご。
#   YAML はヤムルでワイエーエムエルではない。確かめていない読みを刷らないよう、候補は
#   レビューファイルに「?」付きで見せ、著者が「?」を消したものだけを辞書に持つ。
# ================================================================

module VivlioStarter
  module CLI
    module IndexCommands
      module Furigana
        module_function

        DATA_DIR = File.expand_path('data', __dir__)
        SUDACHI_TABLE = File.join(DATA_DIR, 'furigana-sudachi.tsv')
        EXTRA_TABLE = File.join(DATA_DIR, 'furigana-extra.tsv')

        # 漢字（と繰り返し記号・ヶ）
        KANJI_CHAR = /[\p{Han}々〆ヶ]/
        KANJI_RUN = /#{KANJI_CHAR}+/

        # 英字の部分。印字できる ASCII の続きで、英字を含むもの。語の中の半角空白は名前の一部
        # （Ruby on Rails）として続ける。和文の前後の空白（JIS 配列）では切る
        ASCII_RUN = /[!-~]+(?: [!-~]+)*/

        # 本文のふりがなの記法 {親文字|ふりがな}。子行に語の全体の形で書くときに使う
        FULL_FORM = /\{([^{}|]+)\|([^{}]+)\}/

        # 見出し語の一区切り。base は字面、reading はふりがな（振らないなら nil）
        Segment = Data.define(:base, :reading)

        # 見出し語のふりがなの区切り。
        # @param term [String] 見出し語
        # @param yomi [String, nil] 辞書の読み（並べ替え用・語の全体）
        # @param furigana [String, nil] 著者が確かめたふりがな（辞書の furigana:）
        # @return [Array(Array<Segment>, Symbol)] 区切りと、決め方
        #   （:full 全体の形・:parts 字の種類ごと・:whole 割り出せず語の全体・:unreadable 読みが分からず
        #   振らない・:none 振るところが無い）
        def segments(term, yomi, furigana = nil)
          if full_form?(furigana) && (parts = parse_full_form(furigana)) && parts.map(&:base).join == term
            return [parts, :full]
          end

          chunks = chunk(term)
          ascii_reading = plain_reading(term, furigana)
          kanji = chunks.select { it.match?(KANJI_RUN) }
          readings = kanji.empty? ? [] : align(chunks, yomi.to_s)

          # 読みに漢字が残る語（MeCab が読めなかった「遙香姫」→「遙香ひめ」）は、読みが分からない。
          # 漢字の上に漢字を重ねても読み方は伝わらないので振らず、vs index:auto が直し方を示す
          return [[Segment.new(term, nil)], :unreadable] if !kanji.empty? && yomi.to_s.match?(KANJI_CHAR)

          if readings.nil?
            whole = yomi.to_s.empty? || yomi.to_s.casecmp?(term) ? nil : yomi.to_s
            return [[Segment.new(term, whole)], whole ? :whole : :none]
          end

          queue = readings.dup
          parts = chunks.map do |part|
            if part.match?(/\A#{KANJI_RUN}\z/o) then Segment.new(part, queue.shift)
            elsif ascii?(part) && ascii_reading then Segment.new(part, ascii_reading)
            else Segment.new(part, nil)
            end
          end
          [merge_plain(parts), parts.any?(&:reading) ? :parts : :none]
        end

        # 子行の値が、語の全体の形（`{明日|あした}の{予定|よてい}`）か
        def full_form?(value) = value.to_s.match?(FULL_FORM)

        # 語の英字の部分（ASCII_RUN のうち英字を含むもの）
        def ascii_runs(term) = term.to_s.scan(ASCII_RUN).select { it.match?(/[A-Za-z]/) }

        # 読みだけの子行（`ジス`）を振る英字の部分が、一つに決まるか
        def plain_reading(term, furigana)
          value = furigana.to_s.strip
          return nil if value.empty? || full_form?(value) || ascii_runs(term).size != 1

          value
        end

        # 子行の値の誤りを、著者に見せる文で返す（無ければ nil）
        def problem(term, furigana)
          value = furigana.to_s.strip
          return nil if value.empty?

          if full_form?(value)
            bases = parse_full_form(value)&.map(&:base)&.join
            return nil if bases == term

            "ふりがなの親文字をつなぐと「#{bases}」で、見出し語「#{term}」と合いません"
          elsif ascii_runs(term).size != 1
            "英字の部分が #{ascii_runs(term).size} つあり、「#{value}」をどこに振るか決まりません"
          end
        end

        # 全体の形の書き方の例（英字の部分に候補か「よみ」を入れる）
        def full_form_example(term)
          chunk(term).map do |part|
            if ascii?(part) then "{#{part}|#{candidates(part).first || 'ヨミ'}}"
            elsif part.match?(/\A#{KANJI_RUN}\z/o) then "{#{part}|よみ}"
            else part
            end
          end.join
        end

        # 英字の部分の読みの候補（カタカナ）。手で補う表 → SudachiDict → 一字ずつ読んだ形の順。
        # 手で補う表にある綴りは、その表だけを使う（SudachiDict の Java はジャワ）
        # @return [Array<String>]
        def candidates(word)
          extra = lookup(extra_table, word)
          return extra if extra

          found = lookup(sudachi_table, word)
          return found if found

          word.match?(/\A[A-Z]{2,}\z/) ? [spell_out(word)] : []
        end

        # 大文字の略語を一字ずつ読む（HTML → エイチティーエムエル）
        LETTER_NAMES = %w[エー ビー シー ディー イー エフ ジー エイチ アイ ジェー ケー エル エム
                          エヌ オー ピー キュー アール エス ティー ユー ブイ ダブリュー エックス ワイ ゼット].freeze

        def spell_out(word) = word.each_char.map { LETTER_NAMES[it.ord - 'A'.ord] }.join

        # --- 内部 ---------------------------------------------------------------

        # 見出し語を、漢字の続き・英字の部分・それ以外の字に分ける（順序を保つ）
        def chunk(term)
          term.to_s.scan(/#{KANJI_RUN}|#{ASCII_RUN}|[^!-~\p{Han}々〆ヶ]+/o)
        end

        def ascii?(part) = part.match?(/\A#{ASCII_RUN}\z/o) && part.match?(/[A-Za-z]/)

        # 漢字の続きごとの読みを、辞書の読みから割り出す。漢字の続きを「何かの読み」、
        # カタカナをひらがなに直した字、英字をそのまま（大文字・小文字を問わず）として読みに照らす。
        # 空白は両方から外して比べる。割り出しが一通りに決まらなければ nil（語の全体に振る）
        def align(chunks, yomi)
          target = hiragana(yomi).gsub(/\s+/, '')
          pattern_of = lambda do |lazy|
            body = chunks.map do |part|
              if part.match?(/\A#{KANJI_RUN}\z/o) then lazy ? '(.+?)' : '(.+)'
              else Regexp.escape(hiragana(part).gsub(/\s+/, ''))
              end
            end.join
            Regexp.new("\\A#{body}\\z", Regexp::IGNORECASE)
          end
          shortest = target.match(pattern_of.call(true))&.captures
          longest = target.match(pattern_of.call(false))&.captures
          shortest if shortest && shortest == longest
        end

        def hiragana(text) = text.to_s.tr('ァ-ヶ', 'ぁ-ゖ')

        # 振らない区切りが続いたら一つにまとめる（HTML を短くするため）
        def merge_plain(parts)
          parts.each_with_object([]) do |part, merged|
            if part.reading.nil? && merged.last && merged.last.reading.nil?
              merged[-1] = Segment.new(merged.last.base + part.base, nil)
            else
              merged << part
            end
          end
        end

        # `{明日|あした}の{予定|よてい}` を区切りに読む。記法の外の字は振らない区切り
        def parse_full_form(value)
          parts = []
          rest = value.to_s.strip
          until rest.empty?
            if (m = rest.match(/\A#{FULL_FORM}/o))
              parts << Segment.new(m[1], m[2].strip)
              rest = m.post_match
            else
              text = rest[/\A[^{]+/] or return nil
              parts << Segment.new(text, nil)
              rest = rest[text.size..]
            end
          end
          parts
        end

        def lookup(table, word) = table[word] || table[word.downcase]

        def extra_table = @extra_table ||= load_table(EXTRA_TABLE)
        def sudachi_table = @sudachi_table ||= load_table(SUDACHI_TABLE)

        # `綴り<TAB>読み1|読み2` の表。完全な綴りと小文字の綴りの両方で引けるようにする
        # （SudachiDict の Safari は safari、Rust は RUST で載っている）。小文字の綴りは先に出た方を残す
        def load_table(path)
          return {} unless File.exist?(path)

          File.foreach(path, encoding: 'utf-8').each_with_object({}) do |line, table|
            next if line.start_with?('#') || line.strip.empty?

            surface, readings = line.chomp.split("\t", 2)
            list = readings.to_s.split('|')
            table[surface] = list
            table[surface.downcase] ||= list
          end
        end
      end
    end
  end
end
