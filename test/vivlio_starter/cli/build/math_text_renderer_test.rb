# frozen_string_literal: true

# ================================================================
# Test: math_text_renderer_test.rb
# ================================================================
# テスト対象:
#   Build::MathTextRenderer
#   （lib/vivlio_starter/cli/build/math_text_renderer.rb）
#
# 検証内容:
#   - §3.1 サブセットの変換規則（ラテン文字イタリック・上下付き・\frac・記号・ギリシャ・\text）
#   - 原稿に実在する式が正しくテキスト化されること
#   - §3.2 拒否規則（サブセット外は式全体を nil＝SVG 維持へ委ねる）
#   - HTML 予約文字のエスケープ
# ================================================================

require_relative '../../../test_helper'
require_relative '../../../../lib/vivlio_starter/cli/build/math_text_renderer'

module VivlioStarter
  module CLI
    module Build
      class MathTextRendererTest < Minitest::Test
        R = MathTextRenderer

        # 原稿に実在する式（仕様 §5-1）を正しくテキスト化する
        def test_should_render_manuscript_formulas
          assert_equal '<i>E</i>=<i>mc</i><sup>2</sup>', R.render('E=mc^2')
          assert_equal '1/299,792,458', R.render('\frac{1}{299{,}792{,}458}')
          assert_equal 'γ≈2.29', R.render('\gamma \approx 2.29')
          assert_equal '⟨<i>x</i><sup>2</sup>⟩', R.render('\langle x^2 \rangle')
          assert_equal '<i>e</i><sup><i>i</i>π</sup>+1=0', R.render('e^{i\pi} + 1 = 0')
          assert_equal 'ν<sub>0</sub>', R.render('\nu_0')
          assert_equal 'φ', R.render('\phi')
        end

        # \text は立体（イタリックなし）、\, は細空白、\cdot は Unicode で単位式を組む
        def test_should_render_unit_expression_with_upright_text
          got = R.render('h = 6.626 \times 10^{-34}\,\text{J}\cdot\text{s}')

          assert_equal "<i>h</i>=6.626×10<sup>-34</sup> J⋅s", got
          refute_includes got, '<i>J</i>', '\text 内の単位はイタリックにしない'
        end

        # ラテン文字はイタリック・ギリシャは立体
        def test_should_italicize_latin_but_not_greek
          assert_equal '<i>x</i>', R.render('x')
          assert_equal 'α', R.render('\alpha')
          assert_equal '<i>ab</i>', R.render('ab'), '連続ラテン文字は 1 つの <i> にまとめる'
        end

        # 上下付きの引数はグループ・単一トークンどちらも取れる
        def test_should_accept_braced_and_single_script_arguments
          assert_equal '<i>x</i><sup>2</sup>', R.render('x^2')
          assert_equal '<i>x</i><sup>10</sup>', R.render('x^{10}')
          assert_equal '<i>a</i><sub>0</sub>', R.render('a_0')
          assert_equal '<i>a</i><sub><i>ij</i></sub>', R.render('a_{ij}'), '下付きの変数もイタリック'
        end

        # サブセット外は式全体を nil（＝SVG 維持）。部分変換はしない
        def test_should_reject_out_of_subset_formulas
          assert_nil R.render('\sqrt{2}'), '\sqrt は非対応'
          assert_nil R.render('\sum_{i=1}^n'), '\sum は非対応'
          assert_nil R.render('x^{y^z}'), 'sup の 2 段入れ子は拒否'
          assert_nil R.render('\frac{\frac{1}{2}}{3}'), 'frac の入れ子は拒否'
          assert_nil R.render('\vec{v}'), '未知コマンドは拒否'
          assert_nil R.render('a \\ b'), 'バックスラッシュ改行は拒否'
          assert_nil R.render('a & b'), 'アライメント & は拒否'
        end

        # 空・空白のみは nil（img を空 span へ置換しない）
        def test_should_return_nil_for_blank
          assert_nil R.render('')
          assert_nil R.render('   ')
          assert_nil R.render(nil)
        end

        # 出力の HTML 予約文字はエスケープする
        def test_should_escape_html_reserved_characters
          assert_equal '<i>a</i>&lt;<i>b</i>', R.render('a < b')
          assert_equal '<i>a</i>&gt;<i>b</i>', R.render('a > b')
        end

        # グループ {…} は透過（区切りとして働くが出力には残さない）
        def test_should_treat_braces_as_transparent_grouping
          assert_equal '299,792', R.render('299{,}792')
          assert_equal '10<sup>-34</sup>', R.render('10^{-34}')
        end
      end
    end
  end
end
