# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/metrics/analyzer'

module VivlioStarter
  module CLI
    module Metrics
      class AnalyzerTest < Minitest::Test
        def test_basic_stats_counts_characters
          content = "これはテスト文章です。\n二行目です。"
          analyzer = Analyzer.new(content)
          stats = analyzer.basic_stats

          assert_equal content.length, stats.chars
          assert_equal content.delete("\r\n").length, stats.chars_no_newline
          assert_equal 2, stats.lines
        end

        def test_basic_stats_counts_sentences
          content = '一つ目の文。二つ目の文！三つ目の文？'
          analyzer = Analyzer.new(content)
          stats = analyzer.basic_stats

          assert_equal 3, stats.sentences
        end

        def test_basic_stats_counts_clauses_and_commas
          content = '最初の節、二番目の節、三番目の節。'
          analyzer = Analyzer.new(content)
          stats = analyzer.basic_stats

          assert_equal 2, stats.commas
          assert_equal 3, stats.clauses
        end

        def test_vocabulary_stats_calculates_kanji_ratio
          content = '漢字とひらがなの混合文章です'
          analyzer = Analyzer.new(content)
          stats = analyzer.vocabulary_stats

          assert stats.kanji_ratio.positive?
          assert stats.kanji_ratio < 100
        end

        def test_vocabulary_stats_calculates_ttr
          content = '同じ言葉が同じように同じ頻度で出てくる'
          analyzer = Analyzer.new(content)
          stats = analyzer.vocabulary_stats

          assert stats.ttr.positive?
          assert stats.ttr <= 1.0
        end

        def test_readability_returns_label
          content = 'これはテスト用の文章です。'
          analyzer = Analyzer.new(content)
          result = analyzer.readability

          assert_includes %w[Easy Standard Professional], result.label
          assert result.score.is_a?(Float)
        end

        def test_readability_easy_for_simple_content
          content = 'あいうえお かきくけこ さしすせそ'
          analyzer = Analyzer.new(content, readability: { easy: 30, standard: 60 })
          result = analyzer.readability

          assert_equal 'Easy', result.label
        end

        def test_empty_content_returns_zero_stats
          analyzer = Analyzer.new('')
          stats = analyzer.basic_stats

          assert_equal 0, stats.chars
          assert_equal 0, stats.lines
          assert_equal 0, stats.sentences
        end
      end
    end
  end
end
