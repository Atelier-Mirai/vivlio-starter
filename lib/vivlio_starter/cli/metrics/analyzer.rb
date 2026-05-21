# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/metrics/analyzer.rb
# ================================================================
# 責務:
#   Markdown コンテンツの文章品質メトリクスを解析する。
#
# 機能:
#   - 基本統計（文字数、行数、文数、節数）
#   - 語彙難度（漢字比率、平均語長）
#   - 語彙多様度（TTR）
#   - 読解難度スコア
#   - 章・節単位の分量可視化
#
# Ruby 4.0+ 構文:
#   - Data.define によるイミュータブルデータ
#   - パターンマッチング
#   - it パラメータ
#   - エンドレスメソッド
# ================================================================

module VivlioStarter
  module CLI
    module Metrics
      # 基本統計情報を保持するイミュータブルデータ
      BasicStats = Data.define(
        :chars,
        :chars_no_newline,
        :lines,
        :sentences,
        :avg_sentence_len,
        :clauses,
        :avg_clause_len,
        :commas
      )

      # 語彙分析結果を保持するイミュータブルデータ
      VocabularyStats = Data.define(
        :kanji_ratio,
        :avg_word_length,
        :ttr,
        :total_tokens,
        :unique_tokens,
        :kanji_char_count,
        :total_char_count,
        :total_word_length,
        :tokens_map
      )

      # 読解難度を保持するイミュータブルデータ
      ReadabilityScore = Data.define(:score, :label)

      # 章の分析結果を保持するイミュータブルデータ
      ChapterMetrics = Data.define(
        :path,
        :title,
        :chapter_num,
        :chars,
        :sections,
        :warning
      )

      # 節の分析結果を保持するイミュータブルデータ
      SectionMetrics = Data.define(:title, :chars, :warning)

      # Markdown コンテンツを解析してメトリクスを算出する
      class Analyzer
        SENTENCE_DELIMITER = /[。！？!?]+/
        CLAUSE_DELIMITER = '、'
        KANJI_PATTERN = /\p{Han}/

        def initialize(content, config = {})
          @content = content
          @config = config
          @mecab_available = check_mecab_available
        end

        # 基本統計を算出する
        def basic_stats
          sentences = sentence_segments
          clauses = clause_segments

          BasicStats.new(
            chars: content.length,
            chars_no_newline: content.delete("\r\n").length,
            lines: content.empty? ? 0 : content.each_line.count,
            sentences: sentences.size,
            avg_sentence_len: safe_average(sentences.sum(&:length), sentences.size),
            clauses: clauses.size,
            avg_clause_len: safe_average(clauses.sum(&:length), clauses.size),
            commas: content.count(CLAUSE_DELIMITER)
          )
        end

        # 語彙分析を実行する
        def vocabulary_stats
          text = strip_markdown(content)
          tokens = tokenize(text)
          unique = tokens.uniq
          tokens_map = build_token_frequencies(tokens)
          stripped = text.gsub(/\s/, '')
          total_chars = stripped.length
          kanji_count = stripped.scan(KANJI_PATTERN).size
          total_word_length = tokens.sum(&:length)

          VocabularyStats.new(
            kanji_ratio: calculate_kanji_ratio(kanji_count, total_chars),
            avg_word_length: safe_average(total_word_length, tokens.size),
            ttr: safe_average(unique.size.to_f, tokens.size),
            total_tokens: tokens.size,
            unique_tokens: unique.size,
            kanji_char_count: kanji_count,
            total_char_count: total_chars,
            total_word_length:,
            tokens_map: tokens_map
          )
        end

        # 読解難度スコアを算出する
        def readability
          vocab = vocabulary_stats
          basic = basic_stats

          score = (basic.avg_sentence_len * 0.5) + (vocab.kanji_ratio * 0.5)
          label = readability_label(score)

          ReadabilityScore.new(score:, label:)
        end

        private

        attr_reader :content, :config, :mecab_available

        # 文単位に分割する
        def sentence_segments
          content.split(SENTENCE_DELIMITER)
                 .map { it.delete("\r\n").strip }
                 .reject(&:empty?)
        end

        # 節単位に分割する
        def clause_segments
          content.split(CLAUSE_DELIMITER)
                 .map { it.delete("\r\n").strip }
                 .reject(&:empty?)
        end

        # 漢字比率を算出する
        def calculate_kanji_ratio(kanji_count, total_chars)
          return 0.0 if total_chars.zero?

          (kanji_count.to_f / total_chars) * 100
        end

        def build_token_frequencies(tokens)
          tokens.tally
        end

        # MeCab でトークン化する（利用不可の場合は簡易分割）
        def tokenize(text)
          return simple_tokenize(text) unless mecab_available

          mecab_tokenize(text)
        end

        # MeCab による形態素解析
        def mecab_tokenize(text)
          require 'natto'
          nm = Natto::MeCab.new
          tokens = []
          nm.parse(text) do |node|
            next if node.is_eos?

            features = node.feature.split(',')
            base_form = features[6] == '*' ? node.surface : features[6]
            tokens << base_form
          end
          tokens
        rescue LoadError, RuntimeError
          simple_tokenize(text)
        end

        # 簡易トークン化（MeCab 非利用時）
        def simple_tokenize(text)
          text.gsub(/[[:punct:]]/, ' ')
              .split(/\s+/)
              .reject(&:empty?)
        end

        # Markdown 記法を除去する
        def strip_markdown(text)
          text.gsub(/^#+\s*/, '')
              .gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')
              .gsub(/[*_`~]/, '')
              .gsub(/^>\s*/, '')
              .gsub(/^-\s*/, '')
              .gsub(/^\d+\.\s*/, '')
              .gsub(/:::\{[^}]*\}/, '')
              .gsub(':::', '')
        end

        # 読解難度ラベルを判定する
        def readability_label(score)
          thresholds = config[:readability] || { easy: 30, standard: 60 }
          easy_max = thresholds[:easy] || 30
          standard_max = thresholds[:standard] || 60

          if score <= easy_max
            'Easy'
          elsif score <= standard_max
            'Standard'
          else
            'Professional'
          end
        end

        # MeCab が利用可能か確認する
        def check_mecab_available
          require 'natto'
          Natto::MeCab.new
          true
        rescue LoadError, RuntimeError
          false
        end

        # 安全な平均計算
        def safe_average(sum, count) = count.positive? ? sum.to_f / count : 0.0
      end
    end
  end
end
