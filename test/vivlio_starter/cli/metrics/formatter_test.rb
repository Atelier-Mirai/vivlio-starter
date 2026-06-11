# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/metrics/config_loader'
require 'vivlio_starter/cli/metrics/formatter'
require 'vivlio_starter/cli/metrics/analyzer'

module VivlioStarter
  module CLI
    module Metrics
      class FormatterTest < Minitest::Test
        def setup
          @config = ConfigLoader.new({})
          @formatter = Formatter.new(@config)
        end

        def test_format_basic_info_includes_char_count
          basic = BasicStats.new(
            chars: 12_345,
            chars_no_newline: 12_000,
            lines: 100,
            sentences: 50,
            avg_sentence_len: 240.0,
            clauses: 120,
            avg_clause_len: 100.0,
            commas: 119
          )

          output = @formatter.format_basic_info(basic)

          assert_includes output, '📊 文章統計 — 基本情報'
          assert_includes output, '12,000 文字'
          assert_includes output, '100 行'
        end

        def test_format_sentence_structure_includes_counts
          basic = BasicStats.new(
            chars: 12_345,
            chars_no_newline: 12_000,
            lines: 100,
            sentences: 50,
            avg_sentence_len: 240.0,
            clauses: 120,
            avg_clause_len: 100.0,
            commas: 119
          )

          output = @formatter.format_sentence_structure(basic)

          assert_includes output, '📊 文章統計 — 文構造'
          assert_includes output, '50 文'
          assert_includes output, '120 節'
          assert_includes output, '119 個'
        end

        def test_format_detailed_analysis_includes_vocabulary
          vocab = build_vocab(
            kanji_ratio: 28.5,
            avg_word_length: 2.3,
            ttr: 0.65,
            total_tokens: 1000,
            unique_tokens: 650,
            total_char_count: 4_000,
            kanji_char_count: 1_140,
            total_word_length: 2_300,
            tokens_map: { 'Ruby' => 2 }
          )
          readability = ReadabilityScore.new(score: 45.2, label: 'Standard')

          output = @formatter.format_detailed_analysis(vocab, readability)

          assert_includes output, '📈 詳細分析'
          assert_includes output, '【語彙難度】'
          assert_includes output, '28.5%'
          assert_includes output, '【語彙多様度】'
          assert_includes output, 'TTR: 0.65'
          assert_includes output, '【読解難度】'
          assert_includes output, 'Standard'
        end

        def test_format_chapters_renders_bar_graph
          chapters = [
            ChapterMetrics.new(
              path: 'contents/01-intro.md',
              title: 'はじめに',
              chapter_num: 1,
              chars: 5000,
              sections: [],
              warning: nil
            )
          ]

          output = @formatter.format_chapters(chapters, show_sections: false)

          assert_includes output, '📚 章別の分量'
          assert_includes output, '第01章'
          assert_includes output, 'はじめに'
          assert_includes output, '[############]'
          assert_includes output, '5,000 文字'
        end

        def test_format_chapters_shows_warning
          chapters = [
            ChapterMetrics.new(
              path: 'contents/01-intro.md',
              title: 'はじめに',
              chapter_num: 1,
              chars: 500,
              sections: [],
              warning: '加筆検討'
            )
          ]

          output = @formatter.format_chapters(chapters, show_sections: false)

          assert_includes output, '🟡 加筆検討'
        end

        private

        def build_vocab(kanji_ratio:, avg_word_length:, ttr:, total_tokens:, unique_tokens:,
                        total_char_count:, kanji_char_count:, total_word_length:, tokens_map:)
          VocabularyStats.new(
            kanji_ratio:,
            avg_word_length:,
            ttr:,
            total_tokens:,
            unique_tokens:,
            kanji_char_count:,
            total_char_count:,
            total_word_length:,
            tokens_map:
          )
        end
      end

      class WarningCheckerTest < Minitest::Test
        def setup
          @config = ConfigLoader.new({})
          @checker = WarningChecker.new(@config)
        end

        def test_chapter_warning_returns_nil_for_normal_volume
          warning = @checker.chapter_warning(1, 5000)

          assert_nil warning
        end

        def test_chapter_warning_returns_too_short_for_small_chapters
          warning = @checker.chapter_warning(1, 1000)

          assert_equal '加筆検討', warning
        end

        def test_chapter_warning_returns_too_long_for_large_chapters
          warning = @checker.chapter_warning(1, 20_000)

          assert_equal 'やや長い', warning
        end

        def test_chapter_warning_returns_nil_for_excluded_chapters
          warning = @checker.chapter_warning(0, 100)

          assert_nil warning
        end

        def test_section_warning_returns_too_short
          warning = @checker.section_warning(100)

          assert_equal '加筆検討', warning
        end

        def test_has_warning_returns_true_for_chapter_warning
          result = @checker.has_warning?(1, 1000, [])

          assert result
        end

        def test_has_warning_returns_true_for_section_warning
          sections = [SectionMetrics.new(title: 'Test', chars: 100, warning: '加筆検討')]
          result = @checker.has_warning?(1, 5000, sections)

          assert result
        end
      end
    end
  end
end
