# frozen_string_literal: true

require 'did_you_mean'
require_relative '../common'

module Vivlio
  module Starter
    module CLI
      module Lint
        # 英語スペルチェックを実行し、結果を出力する
        module SpellChecker
          module_function

          # ファイルのスペルチェックを実行する
          # @param path [String] チェック対象のMarkdownファイルパス
          # @param word_map [Hash] { downcase_word => display_word }
          # @param ignore_words [Array<String>] 無視する単語のリスト（downcase）
          # @param check_code_blocks [Boolean] コードブロック内もチェックするか
          # @return [Array<Hash>] { line:, word:, suggestion: } の配列
          def check(path, word_map, ignore_words: [], check_code_blocks: false)
            content = File.read(path, encoding: 'UTF-8')
            tokens  = Tokenizer.tokenize(content, check_code_blocks: check_code_blocks, path: path)

            tokens.filter_map do |word, line_no|
              next if word_map.key?(word.downcase)
              next if ignore_words.include?(word.downcase)

              { line: line_no, word: word, suggestion: find_suggestion(word, word_map) }
            end
          rescue Errno::ENOENT => e
            Common.log_warn("[spellcheck] ファイルを読み込めませんでした: #{path} (#{e.message})")
            []
          end

          # 複数ファイルのエラーを標準出力に表示する
          # @param errors_by_file [Hash] { path => [{ line:, word:, suggestion: }] }
          # @return [Boolean] エラーがあれば true
          def print_errors(errors_by_file)
            return false if errors_by_file.empty?

            errors_by_file.each do |path, errors|
              puts "📄 #{path}"
              errors.each do |err|
                if err[:suggestion]
                  puts format('  %4d  %s => %s', err[:line], err[:word], err[:suggestion])
                else
                  puts format('  %4d  %s', err[:line], err[:word])
                end
                puts '        綴りが誤っている可能性があります (spellcheck)'
              end
              puts ''
            end

            true
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
end
