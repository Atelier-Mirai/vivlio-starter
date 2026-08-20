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
  # 素の表記から起こした TeX を受理する（plain-math-notation-spec.md §3-2.3）。
  # この変換器は LaTeX で書かれた原稿だけを見て作られたので、素の表記が入ってからは
  # `×` や `θ`・関数マクロ・`\bmod` が届くようになった。受理しないと Kindle で
  # 原文テキストへ落ちてしまい、真の上付きが出ない。
  def test_should_render_tex_produced_from_plain_notation
    assert_equal '<i>a</i><sup><i>p</i>-1</sup> mod <i>p</i>',
                 MathTextRenderer.render('a^{p-1} \bmod p')
    assert_equal 'sin<sup>2</sup>θ+cos<sup>2</sup>θ',
                 MathTextRenderer.render('\sin^{2}θ + \cos^{2}θ')
    assert_equal '<i>x</i><sup>2</sup>≡1 (mod n)',
                 MathTextRenderer.render('x^{2} ≡ 1 \pmod{n}')
    assert_equal '6.626×10<sup>-34</sup>', MathTextRenderer.render('6.626×10^{-34}')
    assert_equal 'λ<sup>2</sup>−1', MathTextRenderer.render('λ^{2} − 1')
  end

  # Unicode で直接書かれた記号・ギリシャ文字・日本語をそのまま通す。
  def test_should_pass_through_unicode_symbols_greek_and_japanese
    assert_equal '<i>a</i>×<i>b</i>÷<i>c</i>', MathTextRenderer.render('a × b ÷ c')
    assert_equal 'π+θ+λ', MathTextRenderer.render('π + θ + λ')
    assert_equal '平文<sup><i>e</i></sup> mod <i>n</i>', MathTextRenderer.render('平文^{e} \bmod n')
  end

  # 関数名は立体で出す（素のままだと 1 文字ずつ斜体になる）。
  def test_should_render_function_names_upright
    assert_equal 'ln(<i>n</i>)', MathTextRenderer.render('\ln(n)')
    assert_equal 'arctan(1/5)', MathTextRenderer.render('\arctan(1/5)')
  end

  # 複雑な式は今までどおり拒否する（SVG か原文テキストへ委ねる）。
  def test_should_still_reject_complex_constructs
    ['\sqrt{2}', '\sum x^{2}', '\int_{0}^{1} x dx', '\lim_{n→∞} x'].each do |src|
      assert_nil MathTextRenderer.render(src), "拒否されるべき: #{src}"
    end
  end

end
