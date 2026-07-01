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
                              kanji_char_count: 40, tokens_map: { 'Ruby' => 2, 'コード' => 2 }, mattr: 0.5),
            build_vocab_stats(total_tokens: 6, total_word_length: 18, total_char_count: 150,
                              kanji_char_count: 30, tokens_map: { 'Ruby' => 1, '文章' => 5 }, mattr: 0.6)
          ]

          aggregated = @runner.send(:aggregate_vocabulary_stats, vocabularies)

          assert_equal 10, aggregated.total_tokens
          assert_in_delta 2.6, aggregated.avg_word_length, 0.01
          assert_in_delta 20.0, aggregated.kanji_ratio, 0.01
          assert_in_delta 0.3, aggregated.ttr, 0.01
          # MATTR は語数加重平均: (4*0.5 + 6*0.6) / 10 = 0.56
          assert_in_delta 0.56, aggregated.mattr, 0.001
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
          readability = Metrics::ReadabilityScore.new(score: 25.0, label: 'Easy',
                                                      features: Metrics::ReadabilityFeatures.zero)
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

        # 読解難度は章ごとの特徴量を合算してから一度だけ算出する
        def test_aggregate_readability_sums_features_then_scores
          analyses = [
            build_analysis(readability_features: build_features(kanji_char_total: 10, kanji_run_count: 5)),
            build_analysis(readability_features: build_features(kanji_char_total: 6, kanji_run_count: 1))
          ]

          result = @runner.send(:aggregate_readability, analyses)

          expected = Metrics::Readability.score(
            Metrics::ReadabilityFeatures.zero.with(kanji_char_total: 16, kanji_run_count: 6)
          )
          assert_in_delta expected, result.score, 0.001
          assert_includes %w[Easy Standard Professional], result.label
        end

        # キャッシュ往復で読解難度の特徴量が保持される
        def test_cache_roundtrip_preserves_readability_features
          features = build_features(sentence_count: 3, sentence_char_total: 90, kanji_char_total: 12, kanji_run_count: 4)
          analysis = build_analysis(readability_features: features)

          hash = @runner.send(:analysis_to_cache_hash, analysis)
          restored = @runner.send(:rebuild_analysis_from_cache, hash)

          assert_equal features, restored.readability.features
        end

        # スキーマ版が一致しない（旧形式）キャッシュは破棄して再解析させる
        def test_rebuild_rejects_stale_schema_version
          analysis = build_analysis(readability_features: build_features)
          hash = @runner.send(:analysis_to_cache_hash, analysis).merge('schema_version' => 0)

          assert_nil @runner.send(:rebuild_analysis_from_cache, hash)
        end

        private

        def build_analysis(readability_features:)
          chapter = Metrics::ChapterMetrics.new(path: 'contents/01-intro.md', title: 'Intro',
                                                chapter_num: 1, chars: 1_200, sections: [], warning: nil)
          readability = Metrics::ReadabilityScore.new(
            score: Metrics::Readability.score(readability_features),
            label: 'Standard',
            features: readability_features
          )
          Runner::ChapterAnalysis.new(chapter:, basic: build_basic_stats_default, vocab: build_vocab_stats,
                                      readability:)
        end

        def build_features(**overrides)
          Metrics::ReadabilityFeatures.zero.with(**overrides)
        end

        def build_basic_stats_default
          build_basic_stats(chars: 1_200, chars_no_newline: 1_100, lines: 12, sentences: 4,
                            avg_sentence_len: 300.0, clauses: 6, avg_clause_len: 180.0, commas: 3)
        end

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
                               kanji_char_count: 0, tokens_map: {}, mattr: 0.0,
                               hira_char_count: 0, kata_char_count: 0, alpha_char_count: 0)
          Metrics::VocabularyStats.new(
            kanji_ratio: 0.0,
            avg_word_length: 0.0,
            ttr: 0.0,
            mattr:,
            total_tokens:,
            unique_tokens: tokens_map.size,
            kanji_char_count:,
            hira_char_count:,
            kata_char_count:,
            alpha_char_count:,
            total_char_count:,
            total_word_length:,
            tokens_map:
          )
        end
      end
    end
  end
end
