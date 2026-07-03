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

require_relative '../masking'
require_relative 'readability'
require_relative 'content_words'

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

      # 語彙分析結果を保持するイミュータブルデータ。
      # ttr は生の Type-Token Ratio（文書長に依存して低く出る参考値）、
      # mattr は窓付き移動平均 TTR（文書長に頑健な多様性の主指標）。
      VocabularyStats = Data.define(
        :kanji_ratio,
        :avg_word_length,
        :ttr,
        :mattr,
        :total_tokens,
        :unique_tokens,
        :kanji_char_count,
        :hira_char_count,
        :kata_char_count,
        :alpha_char_count,
        :total_char_count,
        :total_word_length,
        :tokens_map
      )

      # 読解難度を保持するイミュータブルデータ。
      # features は全体集計時に章をまたいで合算するための生の特徴量。
      ReadabilityScore = Data.define(:score, :label, :features)

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

        # MATTR（移動平均 TTR）の既定の窓幅。Covington & McFall (2010) 由来で
        # 50〜100 が標準、定番実装 quanteda の既定も 100。設定で上書き可能。
        DEFAULT_MATTR_WINDOW = 100

        def initialize(content, config = {})
          @content = content
          @config = config
          @mecab_available = check_mecab_available
        end

        # 基本統計を算出する。
        # 文字数・行数は「分量」なので生の本文（コード込み）で数えるが、
        # 文・節・読点は文章としての構造なので prose（コード除去後）で数える。
        def basic_stats
          sentences = sentence_segments(prose)
          clauses = clause_segments(prose)

          BasicStats.new(
            chars: content.length,
            chars_no_newline: content.delete("\r\n").length,
            lines: content.empty? ? 0 : content.each_line.count,
            sentences: sentences.size,
            avg_sentence_len: safe_average(sentences.sum(&:length), sentences.size),
            clauses: clauses.size,
            avg_clause_len: safe_average(clauses.sum(&:length), clauses.size),
            commas: prose.count(CLAUSE_DELIMITER)
          )
        end

        # 語彙分析を実行する（コード片は分析対象に含めない）
        def vocabulary_stats
          text = prose
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
            mattr: moving_average_ttr(tokens),
            total_tokens: tokens.size,
            unique_tokens: unique.size,
            kanji_char_count: kanji_count,
            hira_char_count: stripped.scan(/\p{Hiragana}/).size,
            kata_char_count: stripped.scan(/[\p{Katakana}ー]/).size,
            alpha_char_count: stripped.scan(/[A-Za-z]/).size,
            total_char_count: total_chars,
            total_word_length:,
            tokens_map: tokens_map
          )
        end

        # 内容語（名詞・固有名詞・形容動詞・動詞・形容詞）を品詞ラベルつきで返す。
        # MeCab が使えない環境では空配列（D セクションは表示しない）。
        def content_words
          return [] unless mecab_available

          extract_content_words(prose)
        end

        # 読解難度スコア（建石式 RS）を算出する
        def readability
          features = Readability.extract_features(prose)
          score = Readability.score(features)
          label = Readability.label(score, readability_thresholds)

          ReadabilityScore.new(score:, label:, features:)
        end

        private

        attr_reader :content, :config, :mecab_available

        # コード片を除いた解析対象本文（文構造・語彙・読解で共通利用）。
        def prose = @prose ||= extract_prose(content)

        # 文単位に分割する
        def sentence_segments(text)
          text.split(SENTENCE_DELIMITER)
              .map { it.delete("\r\n").strip }
              .reject(&:empty?)
        end

        # 節単位に分割する
        def clause_segments(text)
          text.split(CLAUSE_DELIMITER)
              .map { it.delete("\r\n").strip }
              .reject(&:empty?)
        end

        # 読解難度のしきい値（大きいほど易しい。easy/standard はバンド下限）。
        def readability_thresholds = config[:readability] || { easy: 60, standard: 40 }

        # 漢字比率を算出する
        def calculate_kanji_ratio(kanji_count, total_chars)
          return 0.0 if total_chars.zero?

          (kanji_count.to_f / total_chars) * 100
        end

        def build_token_frequencies(tokens)
          tokens.tally
        end

        # 移動平均 Type-Token Ratio（MATTR）。固定長の窓を 1 語ずつずらし、
        # 各窓の TTR を平均する。生 TTR と違い文書長に依存しないため、
        # 章の長短をまたいで語彙の多様性を比較できる（Covington & McFall 2010）。
        # 窓より短いテキストは窓を作れないので全体の TTR を返す。
        def moving_average_ttr(tokens)
          window = mattr_window
          n = tokens.size
          return safe_average(tokens.uniq.size.to_f, n) if n <= window

          counts = Hash.new(0)
          tokens.first(window).each { counts[it] += 1 }
          ratios = [counts.size.to_f / window]

          (window...n).each do |i|
            left = tokens[i - window]
            counts[left] -= 1
            counts.delete(left) if counts[left].zero?
            counts[tokens[i]] += 1
            ratios << counts.size.to_f / window
          end

          ratios.sum / ratios.size
        end

        def mattr_window = config[:mattr_window] || DEFAULT_MATTR_WINDOW

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

        # MeCab で品詞解析し、内容語だけを ContentWord の配列で返す。
        def extract_content_words(text)
          require 'natto'
          nm = Natto::MeCab.new
          words = []
          nm.parse(text) do |node|
            next if node.is_eos?

            word = ContentWords.classify(node.surface, node.feature.split(','))
            words << word if word
          end
          words
        rescue LoadError, RuntimeError
          []
        end

        # 簡易トークン化（MeCab 非利用時）
        def simple_tokenize(text)
          text.gsub(/[[:punct:]]/, ' ')
              .split(/\s+/)
              .reject(&:empty?)
        end

        # コード片と Markdown 記法を除いた本文を取り出す。
        # 技術書はコード量が多く、コード内の英数字・記号が漢字比率や読解難度を
        # 実態より平易側に歪めるため、文章品質の分析対象からは外す。
        # フェンス／インラインのコード除去は Masking（唯一の実装）に委ねる。
        def extract_prose(text)
          strip_markdown(Masking.strip_code(text))
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
