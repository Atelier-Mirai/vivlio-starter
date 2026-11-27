# frozen_string_literal: true

require 'did_you_mean'
require_relative '../common'
require_relative 'finding_rows'
require_relative 'tokenizer'

module VivlioStarter
  module CLI
    module Lint
      # 英語スペルチェックを実行し、結果を出力する
      module SpellChecker
        module_function

        # ファイルのスペルチェックを実行する
        # @param path [String] チェック対象のMarkdownファイルパス
        # @param word_map [Hash] { downcase_word => display_word }
        # @param check_code_blocks [Boolean] コードブロック内もチェックするか
        # @param suggester [Suggester] 綴りの候補を探す索引。原稿をまたいで同じものを渡すと、
        #   同じ未知語の候補を探し直さない（改善案.md #148）
        # @return [Array<Hash>] { line:, word:, suggestion: } の配列
        def check(path, word_map, check_code_blocks: false, suggester: Suggester.new(word_map))
          content = File.read(path, encoding: 'UTF-8')
          tokens  = Tokenizer.tokenize(content, check_code_blocks: check_code_blocks)

          tokens.filter_map do |word, line_no|
            next if word_map.key?(word.downcase)

            { line: line_no, word: word, suggestion: suggester.suggest(word) }
          end
        rescue Errno::ENOENT => e
          Common.log_warn("[spellcheck] ファイルを読み込めませんでした: #{path} (#{e.message})")
          []
        end

        # 複数ファイルのエラーを標準出力に表示する。
        # 同じ語の指摘は 1 行に集約し、出現行と件数をまとめて見やすくする。
        #
        # **出現行を同じ行へ置くのは、ラベルが語だからである。** 日本語校正の表は
        # 指摘が文（`"することもできます"は冗長な表現です。…`）なので横に伸び、
        # 出現行を次の行へ送るしかない（実測: 本書 161 件のラベルは中央 36 桁・最大 164 桁で、
        # 同じ行に置くと 177 桁に達する）。綴りの指摘は `bandle => bundle` のように
        # 語の長さで頭打ちになるため、1 行に収まる。**形をどちらかへ揃えない**——
        # 揃えると、行数が倍になるか、読めない幅になるかのどちらかにしかならない。
        #
        # 揃えるのは表の中の列で、`行:` の位置はその表の最長ラベルに合わせる。
        # 桁数を決め打ちにすると、`notation-implemention-guide => …` のような長い語が
        # 来た行だけ右へずれて列が崩れる（語は綴り誤りなので、長さを見越せない）。
        # @param errors_by_file [Hash] { path => [{ line:, word:, suggestion: }] }
        # @return [Boolean] エラーがあれば true
        def print_errors(errors_by_file)
          return false if errors_by_file.empty?

          errors_by_file.each do |path, errors|
            Common.log_always "📄 #{path}  (スペルチェック)"
            rows  = aggregate(errors, path: path)
            # ラベルは英単語だけで組み立てるため、文字数がそのまま表示幅になる
            width = rows.map { it[:label].length }.max
            rows.each do |row|
              Common.log_always format('  %3d件  %-*s  行: %s', row[:count], width, row[:label], row[:lines])
            end
            Common.log_always ''
          end

          true
        end

        # エラー配列を語ごとに集約し、表示用の行情報へ整える。
        # **件数は語が出た行数で数える**——同じ行に同じ語が 2 回あっても、著者が直しに行く
        # 先は 1 箇所だからである（他の 2 つの検査は指摘の個数で数える）。
        # 並べ替えと出現行の表示は FindingRows に任せる（3 つの検査で揃えるため）。
        # @return [Array<Hash>] { count:, label:, lines: } を件数の多い順で返す
        def aggregate(errors, path: nil)
          rows = errors.group_by { |e| e[:word] }.map do |word, items|
            lines = items.map { |e| e[:line] }.uniq
            suggestion = items.first[:suggestion]
            { count: lines.size, label: suggestion ? "#{word} => #{suggestion}" : word, lines: }
          end
          FindingRows.arrange(rows, path: path)
        end

        # Levenshtein距離で最良の候補語を返す（1 語だけ調べるとき用。原稿を調べるときは
        # check が Suggester を作り、語の表の索引と答えを使い回す）
        # @param word [String] チェック対象の単語
        # @param word_map [Hash] 辞書
        # @return [String, nil] 候補語、または閾値超過時に nil
        def find_suggestion(word, word_map) = Suggester.new(word_map).suggest(word)

        # 単語長に応じた許容Levenshtein距離を返す
        # @param word [String]
        # @return [Integer]
        def threshold_for(word)
          case word.length
          when 1..4 then 1
          when 5..8 then 2
          else           3
          end
        end

        # 綴りの候補を探す索引（改善案.md #148）。
        #
        # 候補は、許容距離（threshold_for）以内で Levenshtein 距離が最も小さい語で、同じ距離なら
        # 語の表で先に出てくる語。以前は未知語が 1 か所出るたびに語の表の全語と距離を計算し、
        # 未知語の多い本（lives-mathematics・3,731 か所）では `vs lint` に 8 分かかっていた。
        # 答えは変えずに、次の 3 つで計算を減らす。
        #
        # - **同じ語の答えを覚える**（`MacTutor` が 1,058 か所あっても 1 回だけ探す）
        # - **語の表を文字の木にする**。距離の表の 1 行は語の頭の 1 文字ごとに決まるので、
        #   頭が同じ語（`inter`・`interface`・`internal`）は、その部分の計算を共有できる。
        #   ある行の最小値が上限を超えたら、その先の語はどれも上限を超えるので、枝ごと見ない。
        #   上限は許容距離から始め、候補が見つかるたびにその距離へ下げる（同じ距離の語は
        #   表の順で比べるので、等しい距離の枝は見る）。
        # - **対角線の近くだけ計算する**。対角線から上限より離れたマスは、必ず上限を超える。
        #
        # 語の木は、初めて候補を探すときに作る（未知語の無い本では作らない）。
        class Suggester
          # 語の木の節。entry は、ここで終わる語の [表の順, 語]。
          # 子の表は、子ができたときに初めて作る。語の終わりの節には子が無く、節ごとに空の
          # Hash を持たせると、size 40 の辞書で約 10 MB 余分に使っていた（52 MB → 42 MB）
          class Node
            NO_CHILDREN = {}.freeze

            attr_accessor :entry

            def initialize
              @children = nil
              @entry = nil
            end

            def children = @children || NO_CHILDREN

            # 文字 cp の子（無ければ作る）
            def child(cp) = (@children ||= {})[cp] ||= Node.new
          end

          # @param word_map [Hash] { downcase_word => display_word }
          def initialize(word_map)
            @word_map = word_map
            @answers = {}
          end

          # @param word [String]
          # @return [String, nil] 候補語。許容距離以内に無ければ nil
          def suggest(word)
            return @answers[word] if @answers.key?(word)

            @answers[word] = search(word)
          end

          private

          # 同じ語（ハイフン抜きの別名など）が表に 2 度あれば、先の順を残す
          def root
            @root ||= Node.new.tap do |top|
              @word_map.each_value.with_index do |dict_word, order|
                node = dict_word.downcase.each_codepoint.reduce(top) { |n, cp| n.child(cp) }
                node.entry ||= [order, dict_word]
              end
            end
          end

          def search(word)
            @limit   = SpellChecker.threshold_for(word)
            @over    = @limit + 1
            # 候補は点検する語と同じく 2 字以上から選ぶ。1 字の語（`y`・`a`）を直す先に出さない（改善案 #171）
            @lengths = [word.length - @limit, Tokenizer::MIN_WORD_LENGTH].max..(word.length + @limit)
            @target  = word.downcase.codepoints
            @best    = nil # [距離, 表の順, 語]

            first_row = (0..@target.size).map { it <= @limit ? it : @over }
            root.children.each { |char, child| walk(child, char, first_row, 1) }
            @best&.last
          end

          # 語の木を 1 文字（depth 文字目の char）進め、距離の表の次の行を作る
          def walk(node, char, prev, depth)
            curr = next_row(prev, char, depth)
            bound = @best ? @best[0] : @limit
            consider(node.entry, curr.last) if node.entry && curr.last <= bound
            return if curr.min > (@best ? @best[0] : @limit)

            node.children.each { |next_char, child| walk(child, next_char, curr, depth + 1) }
          end

          # Levenshtein 距離の表の 1 行（DidYouMean::Levenshtein と同じ定義）。対角線から上限より
          # 離れたマスは計算せず、上限 + 1 のままにする
          def next_row(prev, char, depth)
            m = @target.size
            curr = Array.new(m + 1, @over)
            curr[0] = depth <= @limit ? depth : @over
            j  = [depth - @limit, 1].max
            hi = [depth + @limit, m].min
            while j <= hi
              value = prev[j - 1] + (@target[j - 1] == char ? 0 : 1)
              value = prev[j] + 1 if prev[j] + 1 < value
              value = curr[j - 1] + 1 if curr[j - 1] + 1 < value
              curr[j] = value > @over ? @over : value
              j += 1
            end
            curr
          end

          # 長さの範囲は以前の判定（表の語の長さで見る）に合わせる
          def consider((order, dict_word), dist)
            return unless @lengths.cover?(dict_word.length)
            return if @best && (dist > @best[0] || (dist == @best[0] && order > @best[1]))

            @best = [dist, order, dict_word]
          end
        end
      end
    end
  end
end
