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
require 'vivlio_starter/cli/metrics/runner'

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
            code_chars: 4_000,
            notation_chars: 500,
            lines: 100,
            sentences: 50,
            avg_sentence_len: 240.0,
            clauses: 120,
            avg_clause_len: 100.0,
            commas: 119
          )

          output = @formatter.format_basic_info(basic, build_prose_vocab(7_000))

          assert_includes output, '📊 文章統計 — 基本情報'
          assert_includes output, '7,000 文字'
          assert_includes output, '（本文。ほかに コード 4,000 文字、記法 500 文字）'
          assert_includes output, '100 行'
        end

        def test_format_basic_info_omits_breakdown_without_code_or_notation
          basic = BasicStats.new(
            chars: 9_000,
            chars_no_newline: 8_800,
            code_chars: 0,
            notation_chars: 0,
            lines: 80,
            sentences: 40,
            avg_sentence_len: 212.5,
            clauses: 90,
            avg_clause_len: 94.0,
            commas: 89
          )

          output = @formatter.format_basic_info(basic, build_prose_vocab(8_500))

          assert_includes output, '8,500 文字（本文）'
          refute_includes output, 'ほかに'
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
            code_chars: 4_000,
            notation_chars: 500,
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

          assert_includes output, '💡 加筆検討'
        end

        # 分量は 💡、文章の質は 🤔 と系統ごとに記号を分け、「／」で並べる
        def test_format_chapter_line_separates_volume_and_quality_advice
          chapter = ChapterMetrics.new(path: 'contents/21-images.md', title: '画像',
                                       chapter_num: 21, chars: 15_890, sections: [], warning: 'やや長い')

          output = @formatter.format_chapter_line(chapter, 15_890, false, extra_warnings: ['表現が単調'])

          assert_includes output, '💡 やや長い ／ 🤔 表現が単調'
        end

        # 同じ系統が複数あるときは、その系統の中で「・」で連結する
        def test_format_chapter_line_joins_same_kind_of_advice_with_nakaguro
          chapter = ChapterMetrics.new(path: 'contents/35-math.md', title: '数式',
                                       chapter_num: 35, chars: 4_120, sections: [], warning: nil)

          output = @formatter.format_chapter_line(chapter, 15_890, false,
                                                  extra_warnings: %w[表現が単調 やや難解])

          assert_includes output, '🤔 表現が単調・やや難解'
          refute_includes output, '💡'
        end

        # 分量の指摘がない章でも、質の指摘だけで 🤔 が出る
        def test_format_chapter_line_shows_quality_advice_alone
          chapter = ChapterMetrics.new(path: 'contents/35-math.md', title: '数式',
                                       chapter_num: 35, chars: 4_120, sections: [], warning: nil)

          output = @formatter.format_chapter_line(chapter, 15_890, false, extra_warnings: ['やや難解'])

          assert_includes output, '🤔 やや難解'
        end

        # 指摘が何もなければ記号は出ない
        def test_format_chapter_line_without_any_advice
          chapter = ChapterMetrics.new(path: 'contents/10-intro.md', title: 'はじめに',
                                       chapter_num: 10, chars: 8_234, sections: [], warning: nil)

          output = @formatter.format_chapter_line(chapter, 15_890, false, extra_warnings: [])

          refute_includes output, '💡'
          refute_includes output, '🤔'
        end

        # 分量が ideal 帯（standard は 4,800〜8,500）に入ると ✅ が付く
        def test_format_chapter_line_marks_ideal_volume_with_check
          chapter = ChapterMetrics.new(path: 'contents/31-lint.md', title: '文章校正',
                                       chapter_num: 31, chars: 5_481, sections: [], warning: nil)

          output = @formatter.format_chapter_line(chapter, 15_890, false)

          assert_includes output, '✅'
          refute_includes output, '💡'
        end

        # ideal 帯の外（min は超えているが理想ではない）なら記号は付かない
        def test_format_chapter_line_marks_nothing_between_min_and_ideal
          chapter = ChapterMetrics.new(path: 'contents/13-new.md', title: '新規作成',
                                       chapter_num: 13, chars: 4_341, sections: [], warning: nil)

          output = @formatter.format_chapter_line(chapter, 15_890, false)

          refute_includes output, '✅'
          refute_includes output, '💡'
        end

        # 分量判定の対象外の章（前書き・付録・後書き）には ✅ も出さない
        def test_format_chapter_line_omits_check_for_excluded_chapter
          chapter = ChapterMetrics.new(path: 'contents/00-preface.md', title: 'はじめに',
                                       chapter_num: 0, chars: 5_481, sections: [], warning: nil)

          output = @formatter.format_chapter_line(chapter, 15_890, false, excluded: true)

          refute_includes output, '✅'
        end

        # 節も ideal 帯（400 / 1,000〜2,800 / 4,000）で ✅ が付く
        def test_format_chapter_line_marks_ideal_section_with_check
          section = SectionMetrics.new(title: '導入', chars: 1_800, warning: nil)
          chapter = ChapterMetrics.new(path: 'contents/31-lint.md', title: '文章校正',
                                       chapter_num: 31, chars: 5_481, sections: [section], warning: nil)

          output = @formatter.format_chapter_line(chapter, 15_890, true)

          assert_equal 2, output.scan('✅').size, '章と節の両方に付く'
        end

        # 節の指摘は分量だけなので 💡 になる
        def test_format_chapter_line_marks_section_volume_advice_with_bulb
          section = SectionMetrics.new(title: '導入', chars: 120, warning: '加筆検討')
          chapter = ChapterMetrics.new(path: 'contents/10-intro.md', title: 'はじめに',
                                       chapter_num: 10, chars: 8_234, sections: [section], warning: nil)

          output = @formatter.format_chapter_line(chapter, 15_890, true)

          assert_includes output, '💡 加筆検討'
        end

        private

        # 本文字数だけを見る表示テスト用の最小構成
        def build_prose_vocab(total_char_count)
          build_vocab(kanji_ratio: 0.0, avg_word_length: 0.0, ttr: 0.0, total_tokens: 0,
                      unique_tokens: 0, total_char_count:, kanji_char_count: 0,
                      total_word_length: 0, tokens_map: {})
        end

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

        # --- 品質警告（metrics-quality-warnings-spec §1.1） ---

        def test_quality_warnings_flags_monotonous_chapter
          analysis = build_analysis(mattr: 0.45, total_tokens: 500)

          assert_equal ['表現が単調'], @checker.quality_warnings(analysis)
        end

        # 詳細分析のバンドは 0.5 以下が単調帯。境界値も発火する
        def test_quality_warnings_flags_monotonous_at_band_boundary
          analysis = build_analysis(mattr: 0.5, total_tokens: 500)

          assert_equal ['表現が単調'], @checker.quality_warnings(analysis)
        end

        def test_quality_warnings_ignores_rich_vocabulary
          analysis = build_analysis(mattr: 0.55, total_tokens: 500)

          assert_empty @checker.quality_warnings(analysis)
        end

        # 総語数が MATTR の窓幅（既定 100）未満の章は MATTR が不安定なので判定しない
        def test_quality_warnings_skips_monotonous_below_mattr_window
          analysis = build_analysis(mattr: 0.3, total_tokens: 80)

          assert_empty @checker.quality_warnings(analysis)
        end

        def test_quality_warnings_flags_too_complex_chapter
          analysis = build_analysis(readability_label: 'Professional', sentence_count: 30)

          assert_equal ['やや難解'], @checker.quality_warnings(analysis)
        end

        def test_quality_warnings_ignores_standard_readability
          analysis = build_analysis(readability_label: 'Standard', sentence_count: 30)

          assert_empty @checker.quality_warnings(analysis)
        end

        # 数文しかない章の RS は不安定なので判定しない（境界は 10 文）
        def test_quality_warnings_skips_too_complex_below_min_sentences
          analysis = build_analysis(readability_label: 'Professional', sentence_count: 9)

          assert_empty @checker.quality_warnings(analysis)
        end

        def test_quality_warnings_lists_both_labels
          analysis = build_analysis(mattr: 0.4, total_tokens: 500,
                                    readability_label: 'Professional', sentence_count: 30)

          assert_equal ['表現が単調', 'やや難解'], @checker.quality_warnings(analysis)
        end

        # 除外章（既定 00 / 90-98 / 99）は分量警告と同じく品質警告も出さない
        def test_quality_warnings_are_empty_for_excluded_chapters
          analysis = build_analysis(chapter_num: 0, mattr: 0.4, total_tokens: 500,
                                    readability_label: 'Professional', sentence_count: 30)

          assert_empty @checker.quality_warnings(analysis)
        end

        # labels.monotonous / too_complex のカスタム文言が警告にも反映される
        def test_quality_warnings_honor_custom_labels
          config = ConfigLoader.new(
            'metrics' => { 'labels' => { 'monotonous' => 'のっぺり', 'too_complex' => '難しめ' } }
          )
          checker = WarningChecker.new(config)
          analysis = build_analysis(mattr: 0.4, total_tokens: 500,
                                    readability_label: 'Professional', sentence_count: 30)

          assert_equal ['のっぺり', '難しめ'], checker.quality_warnings(analysis)
        end

        # --warn は分量警告のない章でも品質警告があれば残す
        def test_has_warning_returns_true_for_quality_warning_only
          analysis = build_analysis(chars: 5000, mattr: 0.4, total_tokens: 500)

          assert @checker.has_warning?(1, 5000, [], analysis:)
        end

        def test_has_warning_without_analysis_keeps_volume_only_behavior
          analysis = build_analysis(chars: 5000, mattr: 0.4, total_tokens: 500)

          refute @checker.has_warning?(1, 5000, [])
          assert @checker.has_warning?(1, 5000, [], analysis:)
        end

        # 表示（詳細分析）と警告が同じバンド定数を見ていることを固定する回帰ゲート。
        # 片方だけしきい値を動かすと必ず落ちる。
        def test_monotonous_warning_matches_detailed_analysis_band
          formatter = Formatter.new(@config)

          [0.3, 0.45, 0.5, 0.51, 0.6, 0.75].each do |mattr|
            shown_as_monotonous = formatter.send(:mattr_evaluation, mattr) == '表現が単調'
            warned = @checker.quality_warnings(build_analysis(mattr:, total_tokens: 500)).include?('表現が単調')

            assert_equal shown_as_monotonous, warned, "MATTR #{mattr} で表示と警告が食い違う"
          end
        end

        private

        # 品質警告の判定に必要な最小限の ChapterAnalysis を組み立てる。
        # 既定値は「どちらの警告にも該当しない」状態にしてある。
        def build_analysis(chapter_num: 21, chars: 8_000, mattr: 0.65, total_tokens: 500,
                           readability_label: 'Standard', sentence_count: 30)
          chapter = ChapterMetrics.new(path: "contents/#{format('%02d', chapter_num)}-sample.md",
                                       title: 'サンプル', chapter_num:, chars:, sections: [], warning: nil)
          vocab = VocabularyStats.new(
            kanji_ratio: 28.0, avg_word_length: 2.3, ttr: 0.4, mattr:, total_tokens:,
            unique_tokens: 300, kanji_char_count: 0, hira_char_count: 0, kata_char_count: 0,
            alpha_char_count: 0, total_char_count: 1, total_word_length: 1, tokens_map: {}
          )
          readability = ReadabilityScore.new(
            score: 35.0, label: readability_label,
            features: ReadabilityFeatures.zero.with(sentence_count:)
          )
          Runner::ChapterAnalysis.new(chapter:, basic: nil, vocab:, readability:)
        end
      end
    end
  end
end
