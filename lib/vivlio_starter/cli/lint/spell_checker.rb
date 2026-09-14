# frozen_string_literal: true

require 'did_you_mean'
require_relative '../common'
require_relative 'finding_rows'

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
        # @return [Array<Hash>] { line:, word:, suggestion: } の配列
        def check(path, word_map, check_code_blocks: false)
          content = File.read(path, encoding: 'UTF-8')
          tokens  = Tokenizer.tokenize(content, check_code_blocks: check_code_blocks, path: path)

          tokens.filter_map do |word, line_no|
            next if word_map.key?(word.downcase)

            { line: line_no, word: word, suggestion: find_suggestion(word, word_map) }
          end
        rescue Errno::ENOENT => e
          Common.log_warn("[spellcheck] ファイルを読み込めませんでした: #{path} (#{e.message})")
          []
        end

        # 複数ファイルのエラーを標準出力に表示する。
        # 同じ語の指摘は 1 行に集約し、出現行と件数をまとめて見やすくする。
        # @param errors_by_file [Hash] { path => [{ line:, word:, suggestion: }] }
        # @return [Boolean] エラーがあれば true
        def print_errors(errors_by_file)
          return false if errors_by_file.empty?

          errors_by_file.each do |path, errors|
            Common.log_always "📄 #{path}  (spellcheck)"
            aggregate(errors).each do |row|
              Common.log_always format('  %3d件  %-28s 行: %s', row[:count], row[:label], row[:lines])
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
        def aggregate(errors)
          rows = errors.group_by { |e| e[:word] }.map do |word, items|
            lines = items.map { |e| e[:line] }.uniq
            suggestion = items.first[:suggestion]
            { count: lines.size, label: suggestion ? "#{word} => #{suggestion}" : word, lines: }
          end
          FindingRows.arrange(rows)
        end

        # Levenshtein距離で最良の候補語を返す
        # @param word [String] チェック対象の単語
        # @param word_map [Hash] 辞書
        # @return [String, nil] 候補語、または閾値超過時に nil
        def find_suggestion(word, word_map)
          threshold = threshold_for(word)
          min_len   = [word.length - threshold, 1].max
          max_len   = word.length + threshold
          w_down    = word.downcase

          best_word = nil
          best_dist = threshold + 1

          word_map.each_value do |dict_word|
            next unless dict_word.length.between?(min_len, max_len)

            dist = DidYouMean::Levenshtein.distance(w_down, dict_word.downcase)
            if dist < best_dist
              best_dist = dist
              best_word = dict_word
            end
          end

          best_dist <= threshold ? best_word : nil
        end

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
      end
    end
  end
end
