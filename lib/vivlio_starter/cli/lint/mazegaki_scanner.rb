# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/lint/mazegaki_scanner.rb
# ================================================================
# 責務:
#   交ぜ書き辞書の**第 2 層**——MeCab がある環境でだけ使う語を走査する。
#   仕様: mazegaki-two-tier-spec.md
#
# なぜ層を分けるのか:
#   「き損（毀損）」は後続を `なねじ` で外せば「引き損なう」が消えるので、
#   正規表現だけで足りる（第 1 層 = MazegakiDictionary::ALL）。
#   「う回（迂回）」は外せない——「使う回数」「行なう回数」「という回答」の
#   直前はひらがなにも漢字にもなる。`使う|回数` と形態素が切れることを見るしか
#   区別する手立てがない。**MeCab を前提にしてよい語だけをこちらへ置く。**
#
# 判定は 3 条件の AND（どれか 1 つでも欠けると語をまたぐ誤検出が出る）:
#   1. 開始が形態素の頭  … `細かい書き方`→かい書 を防ぐ
#   2. 終了が形態素の切れ目 … `成果物ごとに`→物乞、`引っかかった`→引っ掻 を防ぐ
#   3. 両端が助詞・助動詞でない … `RS のしきい値`（の＋し）、`呼び出し側が`（側＋が）
#
# 依存:
#   - natto gem + MeCab 本体（無ければ静かに無効化する。案内は YomiInferrer が出す）
#   - lint/data/mazegaki.tsv（SudachiDict 由来・Apache-2.0。`rake mazegaki:build` が生成）
# ================================================================

require_relative '../common'
require_relative 'mazegaki_dictionary'

module VivlioStarter
  module CLI
    module Lint
      # MeCab の形態素境界を使う交ぜ書き走査。
      module MazegakiScanner
        module_function

        # 交ぜ書きの語が助詞で始まったり終わったりすることは、慣用句を除いて無い。
        PARTICLE = %w[助詞 助動詞].freeze

        DATA_PATH = File.expand_path('data/mazegaki.tsv', __dir__)

        # 1 行から [見出し, 漢字表記, 開始, 終了] を拾う。MeCab が無ければ常に空。
        # @param line [String] コードを退避済みの地の文 1 行
        # @return [Array<Array>] 位置の昇順
        def scan(line)
          return [] if line.nil? || line.empty?
          return [] unless available?

          morphemes = morphemes_of(line)
          return [] if morphemes.empty?

          hits = []
          morphemes.each do |start, _finish, _pos|
            found = longest_at(line, start)
            hits << found if found && word?(line, morphemes, found[2], found[3])
          end
          hits
        end

        # MeCab が使えるか。使えない環境では第 2 層を丸ごと諦める——
        # 導入を促す案内は索引機能（YomiInferrer）がすでに出しており、
        # lint でも毎回鳴らすと同じ助言が二重になる。
        def available?
          return @available unless @available.nil?

          @available = begin
            require 'natto'
            @mecab = Natto::MeCab.new
            true
          rescue LoadError, StandardError => e
            Common.log_debug("[lint] 交ぜ書きの第 2 層は無効です（MeCab 不在）: #{e.message}")
            false
          end
        end

        # 辞書。第 2 層のデータと MECAB_ONLY を 1 つの Hash にする。
        def table
          @table ||= MazegakiDictionary::MECAB_ONLY.merge(load_data)
        end

        # 走査の対象になりうる最大の見出し長（Hash を引く回数の上限）
        def max_length = @max_length ||= table.keys.map(&:size).max

        # テストが辞書を差し替えるための入口。
        def reset!
          @table = nil
          @max_length = nil
          @available = nil
          @mecab = nil
        end

        # --- ここから下は内部 -------------------------------------------------

        # 形態素の位置と品詞を、元の文字列の添字つきで返す。
        # **`-Owakati` の出力を文字数で累積してはならない**——MeCab は空白を落とすので、
        # 行に半角空白が 1 つでもあると、それ以降の境界が全部ずれる。
        # 表層形を原文から引き直して添字を取る。
        def morphemes_of(line)
          out = []
          pos = 0
          @mecab.parse(line) do |node|
            surface = node.surface
            next if surface.nil? || surface.empty?

            index = line.index(surface, pos)
            break if index.nil?

            out << [index, index + surface.size, node.feature.split(',').first]
            pos = index + surface.size
          end
          out
        rescue StandardError => e
          Common.log_debug("[lint] 形態素解析に失敗しました: #{e.message}")
          []
        end

        # 形態素の頭から、辞書に載っている最長の語を切り出す。
        # 2,000 語を Regexp.union にすると遅いので、長いほうから Hash を引く。
        def longest_at(line, start)
          [max_length, line.size - start].min.downto(1) do |length|
            word = line[start, length]
            expected = table[word]
            return [word, expected, start, start + length] if expected
          end
          nil
        end

        # マッチが語として成立しているか（判定 3 条件）。
        # 第 2 層の見出しはすべて名詞なので、終了は形態素の切れ目と厳密に一致させる。
        def word?(_line, morphemes, start, finish)
          head = morphemes.find { it[0] == start }
          tail = morphemes.find { it[1] == finish }
          return false if head.nil? || tail.nil?

          !PARTICLE.include?(head[2]) && !PARTICLE.include?(tail[2])
        end

        # 生成物（`rake mazegaki:build`）を読む。壊れていても lint 全体は止めない。
        def load_data
          File.readlines(DATA_PATH, chomp: true).each_with_object({}) do |line, acc|
            next if line.start_with?('#') || line.empty?

            word, expected = line.split("\t", 2)
            acc[word] = expected if word && expected
          end
        rescue SystemCallError => e
          Common.log_warn("[lint] 交ぜ書き辞書を読み込めませんでした: #{DATA_PATH} (#{e.message})")
          {}
        end
      end
    end
  end
end
