# frozen_string_literal: true

# ================================================================
# Test: textlint_formatter_test.rb
# ================================================================
# テスト対象:
#   TextlintFormatter（lib/vivlio/starter/cli/textlint_formatter.rb）
#
# 検証内容:
#   - 英語エラーメッセージの日本語変換
#   - 感嘆符・疑問符メッセージの翻訳
#   - 全角・半角文字の適切な処理
# ================================================================

require 'test_helper'
require 'vivlio/starter/cli/textlint_formatter'

module Vivlio
  module Starter
    module CLI
      # TextlintFormatter のユニットテスト
      class TextlintFormatterTest < Minitest::Test
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
      end
    end
  end
end
