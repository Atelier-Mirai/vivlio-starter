# frozen_string_literal: true

# ================================================================
# Test: plain_math_transpiler_test.rb
# ================================================================
# テスト対象:
#   素の表記 → TeX 変換器（lib/vivlio_starter/cli/pre_process/plain_math_transpiler.rb）
#
# 検証内容（仕様: plain-math-notation-spec.md §5・§9）:
#   PT-01 黙って消える表記を起こす（上付き・下付き・全角・中黒）
#   PT-02 別の式として組まれる表記を起こす（^( )・√・Σ・関数名・mod）
#   PT-03 **既存の TeX が 1 文字も変わらない**（いちばん大事。既存原稿の再描画を防ぐ）
#   PT-04 そのままで正しい記号は触らない（ギリシャ・≡ ≒ ≈・∑・·）
#   PT-05 TeX の特殊文字を退避する（% は後ろを飲み込み、# & はエラーになる）
#   PT-06 冪等（二度掛けても変わらない）
#   PT-07 壊れた入力で例外を投げず、原文を失わない
#   PT-08 ゲート（plain?）が既存 TeX に反応しない
#
# 期待値の根拠は MathJax の実測（仕様 §1）。「そのままで正しい」と書いてある記号は、
# 実際に doc.convert() して正しいグリフが出ることを確認したものだけを並べている。
# ================================================================

require_relative '../../../test_helper'
require 'vivlio_starter/cli/pre_process/plain_math_transpiler'

class PlainMathTranspilerTest < Minitest::Test
  T = VivlioStarter::CLI::PreProcessCommands::PlainMathTranspiler

  # 判定器を通ってきた式はゲートを飛ばすので、変換規則の検証は force で行う。
  def tex(src) = T.to_tex(src, force: true)

  # PT-01: MathJax が黙って落とす表記。ビルドも警告も通るので、著者は本を見るまで気づかない。
  def test_should_restore_characters_that_mathjax_silently_drops
    assert_equal 'x^{2}+y^{2}', tex('x²+y²')
    assert_equal '10^{14}',     tex('10¹⁴')
    assert_equal '10^{-34}',    tex('10⁻³⁴')
    assert_equal 'H_{2}O',      tex('H₂O')
    assert_equal 'e^{x}',       tex('eˣ')            # ˣ は U+02E3
    assert_equal 'H_{n} - \\ln(n)', tex('Hₙ - ln(n)') # ₙ は U+2099
    assert_equal 'f^{(n)}(0) = n!×c_{n}', tex('f⁽ⁿ⁾(0) = n!×cₙ')
    assert_equal 'a+b',         tex('ａ＋ｂ')          # 全角は式ごと消える
    assert_equal 'a\\cdot b',   tex('a・b')           # U+30FB は丸ごと消える
  end

  # PT-02: エラーにならないまま別の式として組まれる表記。
  def test_should_fix_notation_that_renders_as_a_different_formula
    assert_equal '2^{1/3}',        tex('2^(1/3)')     # ^ の引数は直後の 1 文字だけだった
    assert_equal 'a^{560} \\bmod 561', tex('a^560 mod 561')
    assert_equal 'a^{p-1} \\bmod p',   tex('a^(p-1) mod p')
    assert_equal '\\sqrt{2}',      tex('√2')          # 根号の横線が無かった
    assert_equal '\\sqrt{GM/R}',   tex('√(GM/R)')
    assert_equal '\\sum x^{2}',    tex('Σx²')         # Σ(U+03A3) は斜体の変数になっていた
    assert_equal '\\sin^{2}θ + \\cos^{2}θ', tex('sin²θ + cos²θ') # 𝑠𝑖𝑛 と 1 文字ずつ斜体だった
    assert_equal 'x^{2} ≡ 1 \\pmod{n}',     tex('x^2 ≡ 1 (mod n)')
    assert_equal 'x\\leq y',       tex('x<=y')
  end

  # PT-02: 素の `^` / `_` の引数は**数字の連なり／英字の連なり**を 1 かたまりと見る。
  # 混ぜて取ると `H_2O` が `H_{2O}` になり O まで添字へ落ちる（実測: 早見表で `H₂ₒ` と出た）。
  # 逆に 1 文字しか取らないと `a^560` が `a^5` の後ろに `60` を並べてしまう。
  def test_should_not_mix_digits_and_letters_in_a_bare_script
    assert_equal 'H_{2}O',  tex('H_2O')
    assert_equal 'x_{1}y',  tex('x_1y')
    assert_equal 'a^{560}', tex('a^560')
    assert_equal 'A_{pub}', tex('A_pub')
    assert_equal '2^{-52}', tex('2^-52'), '符号つきの指数も 1 かたまり'
  end

  # PT-02: `√` は直後の 1 トークンだけに掛かる（仕様 §5.2）。
  # 数は丸ごと 1 トークン——1 文字ずつ取ると `√163` が `\sqrt{1}63` になる。
  def test_should_bind_the_radical_to_a_single_token
    assert_equal '\\sqrt{x}+1',  tex('√x+1')
    assert_equal '\\sqrt{x+1}',  tex('√(x+1)')
    assert_equal 'e^{π\\sqrt{163}}', tex('e^(π√163)')
    assert_equal '\\sqrt{12345}',    tex('√12345')
  end

  # PT-02: TeX の演算子名 38 種。`liminf` を `lim` + `inf` に割らないこと。
  def test_should_convert_all_tex_operator_names
    assert_equal '\\sup(x)',    tex('sup(x)')
    assert_equal '\\inf(A)',    tex('inf(A)')
    assert_equal '\\arg(z)',    tex('arg(z)')
    assert_equal '\\deg(f)',    tex('deg(f)')
    assert_equal '\\Pr(A)',     tex('Pr(A)')
    assert_equal '\\liminf(n)', tex('liminf(n)'), '長い名前を先に見る'
    assert_equal '\\limsup(n)', tex('limsup(n)')
  end

  # PT-02: 著者が考えた上下限の記法（TeX 側に対応が無い）。
  def test_should_convert_author_written_operator_bounds
    assert_equal '\\sum_{k=0}^{∞}',   tex('Σ(k=0 to ∞)')
    assert_equal '\\sum_{n=0}^{N-1}', tex('Σ(n=0 to N-1)')
    assert_equal '\\int_{0}^{π/2}',   tex('∫[0, π/2]')
    assert_equal '\\lim_{n→∞}',       tex('lim(n→∞)')
  end

  # PT-02: `workbook` に実在する式（仕様 §2 の実測から採った）。
  def test_should_convert_real_expressions_from_the_corpus
    assert_equal 'X_{k} = \\sum x_{n}\\cdot e^{-2πikn/N}', tex('X_k = Σ x_n・e^(-2πikn/N)')
    assert_equal '\\sqrt{\\hat{p}(1−\\hat{p}) / n}',        tex('√( p̂(1−p̂) / n )')
    assert_equal 'x_{n+1} = x_{n} − f(x_{n})/f(x_{n})',     tex('x_(n+1) = x_n − f(x_n)/f(x_n)')
    assert_equal '\\log_{2}(1000000) = 19.9',               tex('log₂(1000000) = 19.9')
    assert_equal '10^{(Rb − Ra) / 400}',                    tex('10^((Rb − Ra) / 400)')
    assert_equal '\\det(A − λI) = 0',                       tex('det(A − λI) = 0')
    assert_equal '4\\arctan(1/5) − \\arctan(1/239) = π/4',  tex('4arctan(1/5) − arctan(1/239) = π/4')
    assert_equal 'I(2n) = \\sqrt{I(n)\\cdot C(2n)}',       tex('I(2n) = √(I(n)・C(2n))')
  end

  # PT-03: **いちばん大事なテスト。** 既存 TeX が 1 文字でも変わると、
  # 数式 SVG のキャッシュキーが全部割れて既刊原稿が丸ごと再描画される。
  # 本書 contents/ の現行数式をそのまま並べている。
  def test_should_leave_existing_tex_untouched
    [
      'a^2 + b^2 = c^2',
      'e^{i\\pi} + 1 = 0',
      '\\frac{1}{299{,}792{,}458}',
      'h = 6.626 \\times 10^{-34}\\,\\text{J}\\cdot\\text{s}',
      '\\langle x^2 \\rangle',
      'f^{(n)}(x)',
      '\\gamma \\approx 2.29',
      '\\sqrt{2}',
      '\\sin(x)',
      '10^{14}',
      '\\nu_0'
    ].each { |src| assert_equal src, T.to_tex(src), "既存 TeX が変わった: #{src}" }
  end

  # PT-04: 実測で「そのままで正しい」と分かった記号は触らない。
  # 触らない記号は壊しようがないので、規則を増やさないこと自体が安全側に効く。
  def test_should_not_touch_symbols_that_already_render_correctly
    assert_equal 'π + θ + λ',  tex('π + θ + λ')      # π は \pi と同一の SVG になる
    assert_equal 'a ≡ b ≒ c ≈ d ≠ e ≦ f', tex('a ≡ b ≒ c ≈ d ≠ e ≦ f')
    assert_equal '2 × 3 ÷ 4 ± 5', tex('2 × 3 ÷ 4 ± 5')
    assert_equal 'a·b',        tex('a·b')            # U+00B7 は無事（消えるのは U+30FB）
    assert_equal '∑x + ∞ + 30°', tex('∑x + ∞ + 30°') # ∑(U+2211) は既に総和記号
    assert_equal "f'(x) + n! + 1/2", tex("f'(x) + n! + 1/2")
  end

  # PT-05: TeX の特殊文字。素で書かれると黙って壊れるので必ず退避する。
  #   `50% + 1` → `50`   % から後ろがコメント扱いで消える
  #   `a#b` `a&b`        TeX エラー（merror）になる
  #   `〜` を半角 `~` にすると、TeX の改行しない空白に化けて範囲の意味が消える
  def test_should_escape_characters_that_tex_treats_specially
    assert_equal '50\\% + 1', tex('50% + 1')
    assert_equal '50\\%',     tex('50％')
    assert_equal 'a\\#b',     tex('a#b')
    assert_equal 'a\\&b',     tex('a&b')
    assert_equal 'g^{1}\\sim g^{p-1} \\bmod p', tex('g^1〜g^(p-1) mod p')
    assert_equal '\\% は退避済み', T.to_tex('\\% は退避済み', force: true)
  end

  # PT-05: ただし `\begin{aligned}` の中では `&` は桁揃えの記号として**正しい**。
  # 環境を使う式は LaTeX を知っている著者が書いたものなので、そこは触らない。
  # （本書 96-sample.md の九九の表で実際に踏んだ。仕様 §10-3 の検査が捕まえた退行）
  def test_should_not_escape_the_alignment_character_inside_a_tex_environment
    src = "\\begin{aligned}\n9 \\times 1 &= 9 \\\\\n9 \\times 2 &= 18\n\\end{aligned}"

    assert_equal src, tex(src)
  end

  # PT-06: 二度掛けても変わらない。前処理は再実行されうる。
  def test_should_be_idempotent
    ['x²+y²', '√(GM/R)', 'Σx²', 'a^(p-1) mod p', 'sin²θ', 'H₂O', '2n・tanθ', '50% + 1'].each do |src|
      once = tex(src)

      assert_equal once, tex(once), "冪等でない: #{src}"
    end
  end

  # PT-07: 壊れた入力。式全体を諦めず、原文を失わない（部分変換の原則・仕様 §5.3）。
  def test_should_degrade_without_losing_the_original_text
    assert_equal '√(x', tex('√(x')   # 閉じ括弧が無い
    assert_equal '2^(',  tex('2^(')
    assert_equal '√',    tex('√')
    assert_equal '',     tex('')
    assert_equal '²x',   tex('²x')   # 基底が無い上付きは変換しない
    assert_equal '^2',   T.to_tex('^2')
    assert_nil T.to_tex(nil)
  end

  # PT-08: ゲート。素の表記のしるしが無い式は、走査すらせずそのまま返す。
  # `a^2` は TeX としてそのまま正しいので、しるしにしない（§5.1）。
  def test_gate_should_not_fire_on_existing_tex
    refute T.plain?('a^2 + b^2 = c^2')
    refute T.plain?('e^{i\\pi} + 1 = 0')
    refute T.plain?('\\sqrt{2}')
    refute T.plain?('\\sin(x)')      # \ が前に付いていれば関数名として拾わない
    refute T.plain?('h = 6.626 \\times 10^{-34}\\,\\text{J}\\cdot\\text{s}')

    assert T.plain?('√2')
    assert T.plain?('x²')
    assert T.plain?('a^(p-1)')
    assert T.plain?('a^560')         # 引数が 2 文字以上なら `a^5` + `60` に割れる
    assert T.plain?('Σx')
    assert T.plain?('sin(x)')
    assert T.plain?('50%')
  end
end
