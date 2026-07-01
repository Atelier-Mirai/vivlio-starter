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

        # 文字種ごとの文字数を数える（その他＝数字・記号は別計上）
        def test_vocabulary_counts_character_types
          stats = Analyzer.new('漢字ひらがなカタカナABC123').vocabulary_stats

          assert_equal 2, stats.kanji_char_count       # 漢字
          assert_equal 4, stats.hira_char_count        # ひらがな
          assert_equal 4, stats.kata_char_count        # カタカナ
          assert_equal 3, stats.alpha_char_count       # ABC
          assert_equal 16, stats.total_char_count      # 123 は「その他」だが総数には含む
        end

        # 長音符（ー）はカタカナとして数える
        def test_vocabulary_counts_prolonged_sound_as_katakana
          stats = Analyzer.new('ルビー').vocabulary_stats

          assert_equal 3, stats.kata_char_count
        end

        # MeCab がある環境では内容語を品詞ラベルつきで抽出する（無ければ skip）
        def test_content_words_extracts_labeled_words
          words = Analyzer.new('設定を設定します。便利な機能です。').content_words
          skip 'MeCab 未導入のため内容語抽出をスキップ' if words.empty?

          assert(words.any? { it.word == '設定' && it.pos == '名詞' })
          assert(words.any? { it.pos == '形容動詞' }, '便利＝形容動詞を捕捉')
          refute(words.any? { it.word == 'する' }, 'ストップワードは除外')
        end

        # MATTR は窓より短いテキストでは全体 TTR にフォールバックする
        def test_mattr_falls_back_to_ttr_for_short_text
          analyzer = Analyzer.new('赤 青 黄 赤 青', mattr_window: 100)
          stats = analyzer.vocabulary_stats

          assert_in_delta stats.ttr, stats.mattr, 0.0001
        end

        # MATTR は文書長に頑健：同じ文を繰り返して長くしても安定する。
        # 一方、生 TTR は長くなるほど必ず下がる（これが MATTR 導入の理由）。
        def test_mattr_is_robust_to_document_length
          unit = '赤い 花 が 咲く 青い 空 に 鳥 が 飛ぶ '
          short = Analyzer.new(unit * 20, mattr_window: 50).vocabulary_stats
          long = Analyzer.new(unit * 200, mattr_window: 50).vocabulary_stats

          assert_in_delta short.mattr, long.mattr, 0.02, 'MATTR は長さにほぼ依存しない'
          assert_operator long.ttr, :<, short.ttr, '生 TTR は長いほど下がる'
        end

        # 窓内の異なり語率の平均になっている（手計算と一致）
        #   tokens=[a,a,b,a], window=2 → 窓 [a,a]=1/2, [a,b]=2/2, [b,a]=2/2 → 平均 0.8333
        def test_mattr_averages_window_type_token_ratios
          analyzer = Analyzer.new('', mattr_window: 2)
          mattr = analyzer.send(:moving_average_ttr, %w[a a b a])

          assert_in_delta 0.8333, mattr, 0.0001
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

        def test_vocabulary_excludes_fenced_code_block
          content = <<~MD
            日本語の本文です。
            ```ruby
            puts "HelloWorld"
            ```
            続きの本文です。
          MD
          analyzer = Analyzer.new(content)
          stats = analyzer.vocabulary_stats

          refute_includes stats.tokens_map.keys, 'puts'
          refute_includes stats.tokens_map.keys, 'HelloWorld'
        end

        def test_vocabulary_excludes_inline_code
          analyzer = Analyzer.new('設定は `super_secret_flag` を使います。')
          stats = analyzer.vocabulary_stats

          refute_includes stats.tokens_map.keys, 'super_secret_flag'
        end

        # 文字数（分量）はコードを含むが、文構造はコードを除外して数える
        def test_basic_stats_count_volume_with_code_but_structure_without
          content = <<~MD
            一文目です。二文目です。
            ```text
            no sentence here
            ```
          MD
          stats = Analyzer.new(content).basic_stats

          assert_equal content.length, stats.chars
          assert_equal 2, stats.sentences
        end

        def test_readability_carries_features_for_aggregation
          result = Analyzer.new('日本語の本文です。').readability

          assert_instance_of ReadabilityFeatures, result.features
          assert_operator result.features.sentence_count, :>, 0
        end

        # ラベルのしきい値（config[:readability]）が反映される
        def test_readability_label_respects_thresholds
          content = '一般的な日本語の文章です。'

          assert_equal 'Easy', Analyzer.new(content, readability: { easy: 0, standard: 0 }).readability.label
          assert_equal 'Professional',
                       Analyzer.new(content, readability: { easy: 999, standard: 999 }).readability.label
        end
      end
    end
  end
end
