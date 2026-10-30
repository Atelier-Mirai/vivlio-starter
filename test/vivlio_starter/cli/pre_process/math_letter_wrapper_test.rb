# frozen_string_literal: true

# ================================================================
# Test: pre_process/math_letter_wrapper_test.rb
# ================================================================
# 地の文の数学用英数字（`𝔽`・`ℝ`）を `$…$` で包む（MathLetterWrapper・改善案 #130）。
# MathJax は Unicode の数学用英数字をそのまま読む（`$𝔽$` は `$\mathbb{F}$` と同じ形）ので、
# 包むだけでよい。MathJax の書体に無い字（`𝕜`・`𝓐`）は包まない。
# ================================================================

require_relative '../../../test_helper'
require 'vivlio_starter/cli/pre_process/math_letter_wrapper'

class MathLetterWrapperTest < Minitest::Test
  W = VivlioStarter::CLI::PreProcessCommands::MathLetterWrapper

  # 字の並びと、すぐ後ろの上付き・下付きを 1 つの数式に包む
  def test_should_wrap_math_letters_with_following_scripts
    assert_equal '実数全体 $ℝ$ と有限体 $𝔽ₚ$、$ℝ²$ と $ℓᵖ$ 空間、$ℏ$。',
                 W.wrap('実数全体 ℝ と有限体 𝔽ₚ、ℝ² と ℓᵖ 空間、ℏ。')
  end

  # MathJax の書体に無い字は包まない（包んでも数式の画像の中に字のまま残る）。PDF では Gaiji が組む
  def test_should_leave_letters_mathjax_cannot_draw
    assert_equal '体 𝕜 と 𝓐 と 𝛂。$𝔽$𝕜', W.wrap('体 𝕜 と 𝓐 と 𝛂。𝔽𝕜')
  end

  # コード・数式・画像の代替テキスト・リンクの行き先・振り仮名・索引の印・原稿に直に書いた図は包まない
  def test_should_not_wrap_inside_code_math_and_markup
    [
      "コード `ℝ` と\n```\nℝ\n```\n",
      "式 $\\mathbb{R}$ と $ℝ^n$\n",
      "![ℝ の図](images/ℝ.png)\n",
      "{ℝ|じっすう} と [ℝ|じっすう]\n",
      "<svg>\n<text>ℝ</text>\n</svg>\n",
      "---\ntitle: ℝ\n---\n"
    ].each { assert_equal it, W.wrap(it), it }
  end

  # `$` の残る行（金額）は包まない。包むと `$100 … $ℝ$` の切れ目がずれて、別の範囲が数式になる
  def test_should_not_wrap_in_a_line_with_a_stray_dollar
    assert_equal "価格は $100 で ℝ を使う。\n次の行の $ℝ$\n", W.wrap("価格は $100 で ℝ を使う。\n次の行の ℝ\n")
  end

  # リンクの文字は包む（行き先は包まない）
  def test_should_wrap_link_text_but_not_its_destination
    assert_equal '[$ℝ$](https://example.com/ℝ)', W.wrap('[ℝ](https://example.com/ℝ)')
  end

  def test_should_return_content_untouched_without_math_letters
    content = 'ただの本文 x² です。'
    assert_same content, W.wrap(content)
  end
end
