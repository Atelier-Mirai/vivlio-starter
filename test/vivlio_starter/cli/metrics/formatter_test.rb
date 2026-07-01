# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/metrics/config_loader'
require 'vivlio_starter/cli/metrics/formatter'
require 'vivlio_starter/cli/metrics/analyzer'
require 'vivlio_starter/cli/metrics/consistency'
require 'vivlio_starter/cli/metrics/sentence_collector'
require 'vivlio_starter/cli/metrics/sentence_endings'
require 'vivlio_starter/cli/metrics/content_words'
require 'vivlio_starter/cli/metrics/kanji_levels'

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

        def test_format_chapter_count_summary_shows_total_and_average
          output = @formatter.format_chapter_count_summary(34, 219_628)

          assert_includes output, '合計 34 章'
          assert_includes output, '平均 6,460 文字'
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
            mattr: 0.62,
            total_tokens: 1000,
            unique_tokens: 650,
            total_char_count: 4_000,
            kanji_char_count: 1_140,
            hira_char_count: 2_000,
            kata_char_count: 400,
            alpha_char_count: 200,
            total_word_length: 2_300,
            tokens_map: { 'Ruby' => 2 }
          )
          readability = ReadabilityScore.new(score: 45.2, label: 'Standard', features: ReadabilityFeatures.zero)

          output = @formatter.format_detailed_analysis(vocab, readability)

          assert_includes output, '📈 詳細分析'
          assert_includes output, '【語彙難度】'
          assert_includes output, '28.5%'
          assert_includes output, '文字種構成: 漢字 28.5% ／ ひらがな 50.0% ／ カタカナ 10.0% ／ 英字 5.0% ／ その他 6.5%'
          assert_includes output, '【語彙多様度】'
          assert_includes output, 'MATTR: 0.62'
          assert_includes output, '650 語（異なり語）'
          assert_includes output, '総語数 1,000 語'
          assert_includes output, '【読解難度】'
          assert_includes output, 'Standard'
        end

        # 既定の閾値では 漢字比率 28.5% / 平均語長 2.3 が「適切」帯に入る
        # （kanji_ratio ideal[25,35] / word_length ideal[2.0,2.5]）
        def test_format_detailed_analysis_uses_default_vocabulary_bands
          vocab = build_vocab(
            kanji_ratio: 28.5, avg_word_length: 2.3, ttr: 0.65, mattr: 0.62,
            total_tokens: 1000, unique_tokens: 650, total_char_count: 4_000,
            kanji_char_count: 1_140, hira_char_count: 2_000, kata_char_count: 400,
            alpha_char_count: 200, total_word_length: 2_300, tokens_map: { 'Ruby' => 2 }
          )
          readability = ReadabilityScore.new(score: 45.2, label: 'Standard', features: ReadabilityFeatures.zero)

          output = @formatter.format_detailed_analysis(vocab, readability)

          assert_includes output, '漢字比率: 適切（28.5%） — 理想的な範囲 25〜35%'
          assert_includes output, '平均語長: 適切（2.3 文字） — 理想的な範囲 2.0〜2.5 文字'
        end

        # book.yml の kanji_ratio / word_length を変えると評価帯と理想範囲が追従する
        # （旧実装ではハードコード帯・固定文言だった回帰テスト）
        def test_format_detailed_analysis_honors_custom_vocabulary_thresholds
          config = ConfigLoader.new(
            'metrics' => {
              'kanji_ratio' => { 'min' => 35, 'ideal' => [40, 50], 'max' => 60 },
              'word_length' => { 'min' => 3.0, 'ideal' => [4.0, 5.0], 'max' => 6.0 }
            }
          )
          formatter = Formatter.new(config)
          vocab = build_vocab(
            kanji_ratio: 28.5, avg_word_length: 2.3, ttr: 0.65, mattr: 0.62,
            total_tokens: 1000, unique_tokens: 650, total_char_count: 4_000,
            kanji_char_count: 1_140, hira_char_count: 2_000, kata_char_count: 400,
            alpha_char_count: 200, total_word_length: 2_300, tokens_map: { 'Ruby' => 2 }
          )
          readability = ReadabilityScore.new(score: 45.2, label: 'Standard', features: ReadabilityFeatures.zero)

          output = formatter.format_detailed_analysis(vocab, readability)

          # 28.5% は min(35) 未満なので「平易」、理想範囲も設定値へ追従
          assert_includes output, '漢字比率: 平易（28.5%） — 理想的な範囲 40〜50%'
          assert_includes output, '平均語長: 平易（2.3 文字） — 理想的な範囲 4.0〜5.0 文字'
        end

        # 語彙多様度が低い（MATTR<0.5）とき、単調バンドの文言は labels.monotonous に由来する
        # 読解難度が難解側（Professional）のとき、その文言は labels.too_complex に由来する
        def test_detailed_analysis_uses_monotonous_and_too_complex_labels
          vocab = build_vocab(
            kanji_ratio: 28.5, avg_word_length: 2.3, ttr: 0.3, mattr: 0.42,
            total_tokens: 1000, unique_tokens: 300, total_char_count: 4_000,
            kanji_char_count: 1_140, hira_char_count: 2_000, kata_char_count: 400,
            alpha_char_count: 200, total_word_length: 2_300, tokens_map: { 'Ruby' => 2 }
          )
          readability = ReadabilityScore.new(score: 30.0, label: 'Professional', features: ReadabilityFeatures.zero)

          output = @formatter.format_detailed_analysis(vocab, readability)

          assert_includes output, '語彙の豊かさ: 表現が単調'   # labels.monotonous の既定
          assert_includes output, 'Professional（やや難解）'    # labels.too_complex の既定
        end

        # labels.monotonous / too_complex を book.yml で変えると詳細分析の文言が追従する
        # （旧実装ではキー定義のみで一切参照されない死蔵だった回帰テスト）
        def test_detailed_analysis_honors_custom_monotonous_and_too_complex_labels
          config = ConfigLoader.new(
            'metrics' => { 'labels' => { 'monotonous' => 'のっぺり', 'too_complex' => '難しめ' } }
          )
          formatter = Formatter.new(config)
          vocab = build_vocab(
            kanji_ratio: 28.5, avg_word_length: 2.3, ttr: 0.3, mattr: 0.42,
            total_tokens: 1000, unique_tokens: 300, total_char_count: 4_000,
            kanji_char_count: 1_140, hira_char_count: 2_000, kata_char_count: 400,
            alpha_char_count: 200, total_word_length: 2_300, tokens_map: { 'Ruby' => 2 }
          )
          readability = ReadabilityScore.new(score: 30.0, label: 'Professional', features: ReadabilityFeatures.zero)

          output = formatter.format_detailed_analysis(vocab, readability)

          assert_includes output, '語彙の豊かさ: のっぺり'
          assert_includes output, 'Professional（難しめ）'
        end

        def test_format_consistency_lists_high_and_low_on_separate_lines
          metric = ConsistencyMetric.new(
            label: '漢字比率', unit: '%', high_label: '高め', low_label: '低め',
            mean: 27.3, stdev: 4.3,
            high: [['第33章', 35.2]], low: [['第12章', 18.9]]
          )

          output = @formatter.format_consistency([metric])

          assert_includes output, '📐 章間のばらつき（本文の章のみ）'
          assert_includes output, '- 漢字比率: 平均 27.3% ／ ばらつき ±4.3'
          assert_includes output, "\n  高め: 第33章 35.2%"
          assert_includes output, "\n  低め: 第12章 18.9%"
        end

        def test_format_long_sentences_right_aligns_columns
          sentences = [
            LocatedSentence.new(chapter_num: 3, line: 274, text: '索引候補の抽出では見出し語とその読みを判定して登録します。', length: 118),
            LocatedSentence.new(chapter_num: 21, line: 88, text: 'Markdown では段落の途中で改行しても整形時に連結されます。', length: 92)
          ]

          output = @formatter.format_long_sentences(sentences)

          assert_includes output, '📝 見直したい長い文（ワースト2）'
          assert_includes output, '1. 第 3章 L274（118字）: '
          assert_includes output, '2. 第21章 L 88（ 92字）: '
        end

        def test_format_sentence_rhythm_lists_worst_runs_aligned
          distribution = { 'です・ます' => 89, '体言止め' => 1, 'だ・である' => 0, 'その他' => 10 }
          runs = [
            SentenceRun.new(chapter_num: 61, line: 538, label: 'ます。', count: 32),
            SentenceRun.new(chapter_num: 3, line: 45, label: '体言止め', count: 5)
          ]

          output = @formatter.format_sentence_rhythm(distribution, runs)

          assert_includes output, '🎶 文末表現のリズム'
          assert_includes output, '- 文末の内訳: です・ます 89%／体言止め 1%／だ・である 0%／その他 10%'
          assert_includes output, "\n    第61章 L538 付近（ます。が32連続）"
          assert_includes output, "\n    第 3章 L 45 付近（体言止めが5連続）"
        end

        def test_format_content_words_lists_ranked_words_with_pos
          words = [
            RankedWord.new(word: '設定', pos: '名詞', count: 173),
            RankedWord.new(word: 'Vivliostyle', pos: '固有名詞', count: 88)
          ]

          output = @formatter.format_content_words(words)

          assert_includes output, '🔤 よく使う言葉（内容語 上位2）'
          assert_includes output, ' 1. 設定'
          assert_includes output, '173回'
          assert_includes output, '固有名詞'
          assert_includes output, '88回'
        end

        def test_format_kanji_levels_shows_breakdown_lists_and_locations
          report = KanjiLevelReport.new(
            ratios: [['教育', 91], ['中学', 9], ['一般(L2)', 0], ['専門(L3)', 0]],
            lists: { chugaku: [['稿', 77]], ippan: [['碍', 3]], senmon: [['閾', 1]] },
            locations: [['閾', [[33, 384]]], ['敲', [[22, 161], [32, 178], [32, 191]]]]
          )

          output = @formatter.format_kanji_levels(report)

          assert_includes output, '🈂 漢字レベル（ルビ候補）'
          assert_includes output, '- レベル内訳: 教育 91% ／ 中学 9% ／ 一般(L2) 0% ／ 専門(L3) 0%'
          assert_includes output, '- 中学漢字（多い順）: 稿(77)'
          assert_includes output, '- 専門漢字(L3)（多い順）: 閾(1)'
          assert_includes output, "\n    閾 → 第33章 L384"
          # 同じ章が続くときは章ラベルを省いて行だけ並べる
          assert_includes output, "\n    敲 → 第22章 L161, 第32章 L178, L191"
        end

        def test_format_sentence_rhythm_without_runs
          output = @formatter.format_sentence_rhythm({ 'です・ます' => 50 }, [])

          assert_includes output, '見当たりません'
        end

        def test_format_consistency_shows_none_when_no_outliers
          metric = ConsistencyMetric.new(
            label: '平均文長', unit: '字', high_label: '長め', low_label: '短め',
            mean: 60.0, stdev: 0.0, high: [], low: []
          )

          output = @formatter.format_consistency([metric])

          assert_includes output, '長め: なし'
          assert_includes output, '短め: なし'
        end

        def test_format_chapter_line_renders_bar
          chapter = ChapterMetrics.new(path: 'contents/01-intro.md', title: 'はじめに',
                                       chapter_num: 1, chars: 5000, sections: [], warning: nil)

          output = @formatter.format_chapter_line(chapter, 5000, false)

          assert_includes output, '第01章'
          assert_includes output, 'はじめに'
          assert_includes output, '[############]'
          assert_includes output, '5,000 文字'
        end

        def test_format_chapter_line_shows_warning
          chapter = ChapterMetrics.new(path: 'contents/01-intro.md', title: 'はじめに',
                                       chapter_num: 1, chars: 500, sections: [], warning: '加筆検討')

          output = @formatter.format_chapter_line(chapter, 5000, false)

          assert_includes output, '🟡 加筆検討'
        end

        private

        def build_vocab(kanji_ratio:, avg_word_length:, ttr:, total_tokens:, unique_tokens:,
                        total_char_count:, kanji_char_count:, total_word_length:, tokens_map:, mattr: 0.0,
                        hira_char_count: 0, kata_char_count: 0, alpha_char_count: 0)
          VocabularyStats.new(
            kanji_ratio:,
            avg_word_length:,
            ttr:,
            mattr:,
            total_tokens:,
            unique_tokens:,
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
