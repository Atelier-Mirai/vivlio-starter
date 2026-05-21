# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/metrics/runner'

module VivlioStarter
  module CLI
    module Metrics
      class RunnerTest < Minitest::Test
        def setup
          @runner = Runner.new([], {})
        end

        def test_aggregate_basic_stats_sums_values
          basics = [
            build_basic_stats(chars: 1_000, chars_no_newline: 900, lines: 10, sentences: 5,
                               avg_sentence_len: 200.0, clauses: 8, avg_clause_len: 120.0, commas: 3),
            build_basic_stats(chars: 2_000, chars_no_newline: 1_800, lines: 20, sentences: 10,
                               avg_sentence_len: 150.0, clauses: 12, avg_clause_len: 80.0, commas: 5)
          ]

          aggregated = @runner.send(:aggregate_basic_stats, basics)

          assert_equal 3_000, aggregated.chars
          assert_equal 2_700, aggregated.chars_no_newline
          assert_equal 30, aggregated.lines
          assert_equal 15, aggregated.sentences
          assert_in_delta 166.6, aggregated.avg_sentence_len, 0.1
          assert_equal 20, aggregated.clauses
          assert_in_delta 96.0, aggregated.avg_clause_len, 0.1
          assert_equal 8, aggregated.commas
        end

        def test_aggregate_vocabulary_stats_merges_token_maps
          vocabularies = [
            build_vocab_stats(total_tokens: 4, total_word_length: 8, total_char_count: 200,
                              kanji_char_count: 40, tokens_map: { 'Ruby' => 2, 'コード' => 2 }),
            build_vocab_stats(total_tokens: 6, total_word_length: 18, total_char_count: 150,
                              kanji_char_count: 30, tokens_map: { 'Ruby' => 1, '文章' => 5 })
          ]

          aggregated = @runner.send(:aggregate_vocabulary_stats, vocabularies)

          assert_equal 10, aggregated.total_tokens
          assert_in_delta 2.6, aggregated.avg_word_length, 0.01
          assert_in_delta 20.0, aggregated.kanji_ratio, 0.01
          assert_in_delta 0.3, aggregated.ttr, 0.01
          assert_equal({ 'Ruby' => 3, 'コード' => 2, '文章' => 5 }, aggregated.tokens_map)
        end

        def test_analysis_to_stat_hash_includes_chapter_path
          chapter = Metrics::ChapterMetrics.new(
            path: 'contents/01-intro.md',
            title: 'Intro',
            chapter_num: 1,
            chars: 1_200,
            sections: [],
            warning: nil
          )
          basic = build_basic_stats(chars: 1_200, chars_no_newline: 1_100, lines: 12,
                                     sentences: 4, avg_sentence_len: 300.0,
                                     clauses: 6, avg_clause_len: 180.0, commas: 3)
          vocab = build_vocab_stats
          readability = Metrics::ReadabilityScore.new(score: 25.0, label: 'Easy')
          analysis = Runner::ChapterAnalysis.new(chapter:, basic:, vocab:, readability:)

          result = @runner.send(:analysis_to_stat_hash, analysis)

          assert_equal 'contents/01-intro.md', result['path']
          assert_equal 1_200, result['chars']
          assert_equal 4, result['sentences']
        end

        def test_basic_stats_to_structured_hash_flattens_fields
          basic = build_basic_stats(chars: 500, chars_no_newline: 480, lines: 8,
                                    sentences: 2, avg_sentence_len: 250.0,
                                    clauses: 3, avg_clause_len: 160.0, commas: 1)

          result = @runner.send(:basic_stats_to_structured_hash, basic)

          expected = {
            'lines' => 8,
            'chars' => 500,
            'chars_without_newline' => 480,
            'sentences' => 2,
            'avg_sentence_chars' => 250.0,
            'commas' => 1,
            'clauses' => 3,
            'avg_clause_chars' => 160.0
          }
          assert_equal expected, result
        end

        private

        def build_basic_stats(chars:, chars_no_newline:, lines:, sentences:, avg_sentence_len:,
                              clauses:, avg_clause_len:, commas:)
          Metrics::BasicStats.new(
            chars:,
            chars_no_newline:,
            lines:,
            sentences:,
            avg_sentence_len:,
            clauses:,
            avg_clause_len:,
            commas:
          )
        end

        def build_vocab_stats(total_tokens: 1, total_word_length: 1, total_char_count: 1,
                               kanji_char_count: 0, tokens_map: {})
          Metrics::VocabularyStats.new(
            kanji_ratio: 0.0,
            avg_word_length: 0.0,
            ttr: 0.0,
            total_tokens:,
            unique_tokens: tokens_map.size,
            kanji_char_count:,
            total_char_count:,
            total_word_length:,
            tokens_map:
          )
        end
      end
    end
  end
end
