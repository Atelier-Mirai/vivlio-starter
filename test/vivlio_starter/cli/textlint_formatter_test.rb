# frozen_string_literal: true

# ================================================================
# Test: textlint_formatter_test.rb
# ================================================================
# テスト対象:
#   TextlintFormatter（lib/vivlio_starter/cli/textlint_formatter.rb）
#
# 検証内容:
#   - translate_output: 英語エラーメッセージの日本語変換
#   - reformat_output: stylish 出力の構造的再整形
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/textlint_formatter'

module VivlioStarter
  module CLI
    # TextlintFormatter のユニットテスト
    class TextlintFormatterTest < Minitest::Test
      # ================================================================
      # translate_output テスト（既存）
      # ================================================================

      # 英語の感嘆符エラーメッセージが日本語に変換されることを確認
      def test_translate_english_exclamation_messages
        english_output = '  20:25   error  Disallow to use "！"  ja-technical-writing/no-exclamation-question-mark'
        expected_output = '  20:25   error  感嘆符「！」は使用しないでください  ja-technical-writing/no-exclamation-question-mark'

        result = TextlintFormatter.translate_output(english_output)
        assert_equal expected_output, result
      end

      def test_translate_english_question_messages
        english_output = '  28:26   error  Disallow to use "？"  ja-technical-writing/no-exclamation-question-mark'
        expected_output = '  28:26   error  疑問符「？」は使用しないでください  ja-technical-writing/no-exclamation-question-mark'

        result = TextlintFormatter.translate_output(english_output)
        assert_equal expected_output, result
      end

      def test_translate_half_width_exclamation
        english_output = 'Disallow to use "!"'
        expected_output = '感嘆符「!」は使用しないでください'

        result = TextlintFormatter.translate_output(english_output)
        assert_equal expected_output, result
      end

      def test_translate_half_width_question
        english_output = 'Disallow to use "?"'
        expected_output = '疑問符「?」は使用しないでください'

        result = TextlintFormatter.translate_output(english_output)
        assert_equal expected_output, result
      end

      def test_translate_multiple_messages
        english_output = <<~OUTPUT
          20:25   error  Disallow to use "！"
          28:26   error  Disallow to use "？"
        OUTPUT

        result = TextlintFormatter.translate_output(english_output)

        assert_includes result, '感嘆符「！」は使用しないでください'
        assert_includes result, '疑問符「？」は使用しないでください'
        refute_includes result, 'Disallow to use'
      end

      def test_translate_preserves_japanese_messages
        japanese_output = '文末が"。"で終わっていません。'

        result = TextlintFormatter.translate_output(japanese_output)
        assert_equal japanese_output, result
      end

      def test_translate_handles_nil_input
        result = TextlintFormatter.translate_output(nil)
        assert_nil result
      end

      def test_translate_handles_empty_input
        result = TextlintFormatter.translate_output('')
        assert_equal '', result
      end

      # ================================================================
      # reformat_output テスト
      # ================================================================

      # --- 4.1 単純な置換提案（prh）: 列番号除去・ラベル除去・ルール名括弧化 ---
      def test_reformat_simple_prh_replacement
        input = <<~INPUT
          /Users/mirai/projects/vivlio-starter/contents/08-web.md
              5:4     ✓ error  サーバ => サーバー                                                                                              prh
        INPUT

        result = TextlintFormatter.reformat_output(input)

        assert_includes result, '    5  サーバ => サーバー (prh)'
        refute_includes result, '5:4'
        refute_includes result, '✓ error'
      end

      # --- 4.2 置換提案＋補足説明（prh 複数行） ---
      def test_reformat_prh_with_detail_lines
        input = <<~INPUT
          /Users/mirai/projects/vivlio-starter/contents/08-web.md
             12:81    ✓ error  コンピュータ => コンピューター
          語尾が -er, -or, -ar で終わる語彙には長音を付けます（外来語カタカナ表記）                                       prh
        INPUT

        result = TextlintFormatter.reformat_output(input)

        lines = result.lines.map(&:chomp)
        # 主メッセージ: 行番号のみ
        assert(lines.any? { it.include?('12  コンピュータ => コンピューター') })
        # 補足行: インデント付き + ルール名
        assert(lines.any? { it.include?('語尾が -er, -or, -ar で終わる語彙には長音を付けます（外来語カタカナ表記） (prh)') })
      end

      # --- 4.3 助詞重複（no-doubled-joshi）: 冗長部分除去・1行結合 ---
      def test_reformat_doubled_joshi
        input = <<~INPUT
          /Users/mirai/projects/vivlio-starter/contents/08-web.md
             14:87    error    一文に二回以上利用されている助詞 "により" がみつかりました。

          次の助詞が連続しているため、文を読みにくくしています。

          - "により"
          - "により"

          同じ助詞を連続して利用しない、文の中で順番を入れ替える、文を分割するなどを検討してください。
                              ja-technical-writing/no-doubled-joshi
        INPUT

        result = TextlintFormatter.reformat_output(input)

        lines = result.lines.map(&:chomp)
        # 主メッセージが含まれる
        assert(lines.any? { it.include?('14  一文に二回以上利用されている助詞 "により" がみつかりました。') })
        # 改善提案がインデントで含まれる
        assert(lines.any? { it.include?('同じ助詞を連続して利用しない') })
        # ルール名が括弧付き
        assert(lines.any? { it.include?('(ja-technical-writing/no-doubled-joshi)') })
        # 冗長な中間部分が除去されている
        refute_includes result, '次の助詞が連続しているため'
        refute_includes result, '- "により"'
      end

      # --- 4.4 文長超過（sentence-length）: 英語→日本語翻訳 ---
      def test_reformat_sentence_length
        input = <<~INPUT
          /Users/mirai/projects/vivlio-starter/contents/08-web.md
             23:630   error    Line 23 sentence length(127) exceeds the maximum sentence length of 100.
          Over 27 characters                                        japanese/sentence-length
        INPUT

        result = TextlintFormatter.reformat_output(input)

        # 日本語に翻訳されている
        assert_includes result, '文の長さ (127) が最大文長の 100 を超えています。'
        assert_includes result, '(japanese/sentence-length)'
        # Over N characters が除去されている
        refute_includes result, 'Over 27 characters'
        # 英語メッセージが除去されている
        refute_includes result, 'Line 23 sentence length'
      end

      # --- 4.5 読点過多（max-ten）---
      def test_reformat_max_ten
        input = <<~INPUT
          /Users/mirai/projects/vivlio-starter/contents/08-web.md
             52:155   error    一つの文で"、"を4つ以上使用しています                                                                           ja-technical-writing/max-ten
        INPUT

        result = TextlintFormatter.reformat_output(input)

        assert_includes result, '52  一つの文で"、"を4つ以上使用しています (ja-technical-writing/max-ten)'
        refute_includes result, '52:155'
        refute_includes result, 'error'
      end

      # --- 4.6 文体混在（no-mix-dearu-desumasu）: Total ブロック除去 ---
      def test_reformat_no_mix_dearu_desumasu
        input = <<~INPUT
          /Users/mirai/projects/vivlio-starter/contents/08-web.md
            115:55    error    本文: "である"調 と "ですます"調 が混在
          => "ですます"調 の文体に、次の "である"調 の箇所があります: "である。"
          Total:
          である  : 2
          ですます: 47
                                                    japanese/no-mix-dearu-desumasu
        INPUT

        result = TextlintFormatter.reformat_output(input)

        assert_includes result, '115  本文: "である"調 と "ですます"調 が混在'
        assert_includes result, '(japanese/no-mix-dearu-desumasu)'
        # Total ブロックが除去されている
        refute_includes result, 'Total:'
        refute_includes result, 'である  : 2'
        refute_includes result, 'ですます: 47'
        # => 行が除去されている
        refute_includes result, '=> "ですます"調'
      end

      # --- 4.7 冗長表現（ja-no-redundant-expression）: 【dictN】と URL 除去 ---
      def test_reformat_redundant_expression
        input = <<~INPUT
          /Users/mirai/projects/vivlio-starter/contents/08-web.md
             63:26    error    【dict5】 "記述を行う"は冗長な表現です。"記述する"など簡潔な表現にすると文章が明瞭になります。
          解説: https://github.com/textlint-ja/textlint-rule-ja-no-redundant-expression#dict5                  ja-technical-writing/ja-no-redundant-expression
        INPUT

        result = TextlintFormatter.reformat_output(input)

        assert_includes result, '"記述を行う"は冗長な表現です。"記述する"など簡潔な表現にすると文章が明瞭になります。'
        assert_includes result, '(ja-technical-writing/ja-no-redundant-expression)'
        # 【dict5】 が除去されている
        refute_includes result, '【dict5】'
        # 解説 URL が除去されている
        refute_includes result, '解説: https://'
      end

      # --- 4.8 スペーシング系（ja-spacing）---
      def test_reformat_spacing
        input = <<~INPUT
          /Users/mirai/projects/vivlio-starter/contents/08-web.md
              5:34    ✓ error  原則として、全角文字と半角文字の間にスペースを入れません。                                                      ja-spacing/ja-space-between-half-and-full-width
        INPUT

        result = TextlintFormatter.reformat_output(input)

        assert_includes result, '    5  原則として、全角文字と半角文字の間にスペースを入れません。 (ja-spacing/ja-space-between-half-and-full-width)'
      end

      # --- 4.9 ファイルパスヘッダー: 相対パス化 + アイコン ---
      def test_reformat_file_header_to_relative_path
        input = <<~INPUT
          /Users/mirai/projects/vivlio-starter/contents/08-web.md
              5:4     ✓ error  サーバ => サーバー                                                                                              prh
        INPUT

        result = TextlintFormatter.reformat_output(input)

        assert_includes result, '📄 contents/08-web.md'
        refute_includes result, '/Users/mirai/projects/vivlio-starter/contents/08-web.md'
      end

      # --- 半角カッコ→全角カッコ（prh 置換＋補足）---
      def test_reformat_parentheses_replacement_with_detail
        input = <<~INPUT
          /Users/mirai/projects/vivlio-starter/contents/08-web.md
             14:116   ✓ error  (Firefoxの前身) => （Firefoxの前身）
          半角カッコの代わりに全角カッコを使うこと。文字のバランスが崩れるためです                                        prh
        INPUT

        result = TextlintFormatter.reformat_output(input)
        lines = result.lines.map(&:chomp)

        assert(lines.any? { it.include?('14  (Firefoxの前身) => （Firefoxの前身）') })
        assert(lines.any? { it.include?('半角カッコの代わりに全角カッコを使うこと。文字のバランスが崩れるためです (prh)') })
      end

      # --- nil / 空文字入力 ---
      def test_reformat_handles_nil_input
        assert_nil TextlintFormatter.reformat_output(nil)
      end

      def test_reformat_handles_empty_input
        assert_equal '', TextlintFormatter.reformat_output('')
      end

      # --- 統合テスト: 複数エラーを含む実際の textlint 出力 ---
      def test_reformat_full_integration
        input = <<~INPUT
          /Users/mirai/projects/vivlio-starter/contents/08-web.md
              5:4     ✓ error  サーバ => サーバー                                                                                              prh
              5:29    ✓ error  三つ => 3つ
          数量を表現し、数を数えられるものは算用数字を使用します。任意の数に置き換えても通用する語句がこれに該当します。  ja-technical-writing/arabic-kanji-numbers
             23:630   error    Line 23 sentence length(127) exceeds the maximum sentence length of 100.
          Over 27 characters                                        japanese/sentence-length
             52:155   error    一つの文で"、"を4つ以上使用しています                                                                           ja-technical-writing/max-ten
        INPUT

        result = TextlintFormatter.reformat_output(input)

        # ファイルヘッダー
        assert_includes result, '📄 contents/08-web.md'
        # 単純 prh
        assert_includes result, '    5  サーバ => サーバー (prh)'
        # prh + 補足
        assert_includes result, '    5  三つ => 3つ'
        assert_includes result, '(ja-technical-writing/arabic-kanji-numbers)'
        # sentence-length 日本語化
        assert_includes result, '文の長さ (127) が最大文長の 100 を超えています。 (japanese/sentence-length)'
        # max-ten
        assert_includes result, '   52  一つの文で"、"を4つ以上使用しています (ja-technical-writing/max-ten)'

        # 除去されていること
        refute_includes result, '✓ error'
        refute_includes result, 'Over 27 characters'
        refute_includes result, '5:4'
      end

      # --- LintEntry の Data.define 構造テスト ---
      def test_lint_entry_attributes
        entry = TextlintFormatter::LintEntry.new(
          line: 5, fixable: true, message: 'サーバ => サーバー', details: [], rule: 'prh'
        )

        assert_equal 5, entry.line
        assert entry.fixable
        assert_equal 'サーバ => サーバー', entry.message
        assert_empty entry.details
        assert_equal 'prh', entry.rule
      end

      # --- ひらく漢字（prh 補足付き）---
      def test_reformat_hiraku_kanji
        input = <<~INPUT
          /Users/mirai/projects/vivlio-starter/contents/08-web.md
             40:59    ✓ error  例えば => たとえば
          ひらがなで書くと読みやすくなります（ひらく漢字）                                                                prh
        INPUT

        result = TextlintFormatter.reformat_output(input)
        lines = result.lines.map(&:chomp)

        assert(lines.any? { it.include?('40  例えば => たとえば') })
        assert(lines.any? { it.include?('ひらがなで書くと読みやすくなります（ひらく漢字） (prh)') })
      end

      # --- spellcheck-tech-word ---
      def test_reformat_spellcheck_tech_word
        input = <<~INPUT
          /Users/mirai/projects/vivlio-starter/contents/08-web.md
             63:38    ✓ error  パソコン => PC                                                                                                  spellcheck-tech-word
        INPUT

        result = TextlintFormatter.reformat_output(input)

        assert_includes result, '   63  パソコン => PC (spellcheck-tech-word)'
      end

      # --- サマリ行がルール抽出を妨害しない ---
      def test_reformat_last_entry_with_summary_lines
        input = <<~INPUT
          /Users/mirai/projects/vivlio-starter/contents/99-postface.md
             37:5     ✓ error  素晴らしい => すばらしい                                                                                                   prh
             37:20    ✓ error  素晴らしい => すばらしい                                                                                                   prh

          ✖ 2 problems (2 errors, 0 warnings)
          ✓ 2 fixable problems.
          Try to run: $ textlint --fix [file]
        INPUT

        result = TextlintFormatter.reformat_output(input)

        lines = result.lines.map(&:chomp)
        # 両方のエントリにルール名が付いている
        prh_lines = lines.select { it.include?('素晴らしい => すばらしい (prh)') }
        assert_equal 2, prh_lines.size, "両エントリに (prh) が付くべき"
        # サマリ行が除去されている
        refute_includes result, '✖ 2 problems'
        refute_includes result, 'fixable problems'
        refute_includes result, 'Try to run'
      end

      # --- ファイルヘッダー前の空行 ---
      def test_reformat_blank_line_before_second_file_header
        input = <<~INPUT
          /Users/mirai/projects/vivlio-starter/contents/00-preface.md
             79:22    ✓ error  良い => よい
          良し悪しを評価する表現は"良い"、しなくていい、など評価でない表現は"よい"を使います                              prh
          /Users/mirai/projects/vivlio-starter/contents/01-life.md
              5:4     ✓ error  サーバ => サーバー                                                                                              prh
        INPUT

        result = TextlintFormatter.reformat_output(input)
        lines = result.lines.map(&:chomp)

        # 最初のヘッダー前には空行なし
        assert_equal '📄 contents/00-preface.md', lines[0]
        # 2つ目のヘッダー前に空行がある
        life_idx = lines.index('📄 contents/01-life.md')
        assert life_idx, '01-life.md ヘッダーが存在すること'
        assert_equal '', lines[life_idx - 1], '2つ目のファイルヘッダー前に空行があること'
      end

      # --- unmatched-pair 英語→日本語翻訳 + 1行結合 ---
      def test_reformat_unmatched_pair_translation
        input = <<~INPUT
          /Users/mirai/projects/vivlio-starter/contents/24-test.md
            569:10    error    Cannot find a pairing character for {.
          You should close this sentence with }.
          This pair of marks is called curly brace{}                                        ja-technical-writing/no-unmatched-pair
        INPUT

        result = TextlintFormatter.reformat_output(input)

        # 日本語に翻訳されて1行に結合
        assert_includes result, '{ のペアとなる文字が見つかりません。} で閉じてください。'
        assert_includes result, '(ja-technical-writing/no-unmatched-pair)'
        # 英語メッセージが除去
        refute_includes result, 'Cannot find a pairing character'
        refute_includes result, 'You should close this sentence'
        refute_includes result, 'This pair of marks is called'
      end

      # --- unmatched-pair 角カッコ ---
      def test_reformat_unmatched_pair_square_bracket
        input = <<~INPUT
          /Users/mirai/projects/vivlio-starter/contents/24-test.md
            100:5     error    Cannot find a pairing character for [.
          You should close this sentence with ].
          This pair of marks is called square bracket[]                                     ja-technical-writing/no-unmatched-pair
        INPUT

        result = TextlintFormatter.reformat_output(input)

        assert_includes result, '[ のペアとなる文字が見つかりません。] で閉じてください。'
        refute_includes result, 'square bracket'
      end
    end
  end
end
