# frozen_string_literal: true

# ================================================================
# Test: math_span_detector_test.rb
# ================================================================
# テスト対象:
#   バッククォート数式の判定器（lib/vivlio_starter/cli/pre_process/math_span_detector.rb）
#
# 検証内容（仕様: plain-math-notation-spec.md §6・§9）:
#   MD-01 数式のコードスパンを `$…$` へ起こす
#   MD-02 **コードは起こさない**（拒否が優先。いちばん大事）
#   MD-03 日本語を含む綴りは数式にしない（明示は尊重し、推測は保守的に・§3.4）
#   MD-04 言語なしフェンスをディスプレイ数式へ起こす／複数行は aligned で揃える
#   MD-05 言語付きフェンスは常にコード
#   MD-06 実行結果の貼り付けを弾く（`【…】` 見出し・矢印）
#   MD-07 `$` を含む綴りは触らない（デリミタが壊れる）
#   MD-08 フェンスの中のコードスパンを拾わない
#   MD-09 冪等
#
# 期待値は `workbook` コーパス（166 ファイル＋problems.yml）の実測から採っている。
# ================================================================

require_relative '../../../test_helper'
require 'vivlio_starter/cli/pre_process/math_span_detector'

class MathSpanDetectorTest < Minitest::Test
  D = VivlioStarter::CLI::PreProcessCommands::MathSpanDetector

  # MD-01: 数式のコードスパン。すべてコーパスに実在する綴り。
  def test_should_detect_math_code_spans
    [
      '√n', 'a^(p-1) mod p', 'Σx²', 'π/4', 'x^2 ≡ 1 (mod n)', 'v = √(GM/R)',
      'X_k = Σ x_n・e^(-2πikn/N)', 'ax² + bx + c = 0', '10⁻¹⁶', 'eˣ',
      'λ² − 1', 'a × b ÷ c', 'sin(x)', 'det(A)', 'Hₙ', '4×41−1=163'
    ].each { |src| assert D.math?(src), "数式と判定されるべき: #{src}" }
  end

  # MD-02: **いちばん大事。** コードのしるしがあれば数式にしない（拒否が優先）。
  # 逆向き（数式のしるしがあれば数式）にすると `array[i] * 2` を拾う。
  def test_should_not_detect_code_as_math
    [
      'puts', 'Complex.polar', 'array[i]', 'height_m**2', 'z**3',
      'divisor * divisor <= limit', 'Math.log(n)', 'broken[position / 8]',
      'a.map { |x| x * 2 }', 'Hash.new(0)', 'def foo', 'x = nil',
      'obj&.value', 'Foo::Bar', '{ a: 1 }', '#{name}'
    ].each { |src| refute D.math?(src), "コードと判定されるべき: #{src}" }
  end

  # MD-02 の要: 小数点をメソッド呼び出しと誤認しないこと。
  # `\.\w` にすると `0.99¹⁰⁰ ≒ 0.366` のような式を 15 件落とす（§6.3 で実際に踏んだ）。
  def test_should_not_mistake_a_decimal_point_for_a_method_call
    assert D.math?('0.99¹⁰⁰ ≒ 0.366')
    assert D.math?('2⁻⁵⁰ ≈ 8.88×10⁻¹⁶')
    refute D.math?('Math.log(n)'), 'メソッド呼び出しは弾く'
  end

  # MD-02 の要: `expression` の中の `exp` を関数名と誤認しないこと（§6.3）。
  def test_should_not_mistake_a_substring_for_a_function_name
    refute D.math?('expression')
    refute D.math?('branch(take, term, expression)')
    assert D.math?('exp(x)')
  end

  # MD-03: 推測で拾う経路では日本語を数式にしない。数式画像にしても得るものが無く、
  # 機械が黙って決めてよい判断でもない（§3.4）。明示的な `$…$` は別（そちらは組む）。
  def test_should_not_detect_spans_containing_japanese
    [
      '距離 × tan(仰角)', '行計 × 列計 ÷ 総計', 'ハッシュ値 mod サーバー台数',
      '(実測−期待)² ÷ 期待', 'λ² − (トレース)λ + (行列式) = 0'
    ].each { |src| refute D.math?(src), "日本語を含むので数式にしない: #{src}" }
  end

  # MD-01: 本文中のコードスパンが `$…$` になる。コードはそのまま。
  def test_should_transform_math_spans_and_leave_code_alone
    md = "約数は `√n` 以下です。`Complex.polar` を使います。\n"

    assert_equal "約数は $√n$ 以下です。`Complex.polar` を使います。\n", D.transform(md)
  end

  # MD-04: 言語なしフェンスがディスプレイ数式になる。
  def test_should_transform_a_language_less_fence_into_display_math
    md = "次の式です。\n\n```\nπ(n) ≈ n / ln(n)\n```\n\n以上。\n"

    assert_includes D.transform(md), "$$\nπ(n) ≈ n / ln(n)\n$$"
  end

  # MD-04: 複数行は aligned で関係演算子の位置を揃える。1 行ずつ独立した `$$` にすると、
  # `X = …` に続く `= …` の導出が揃わない。
  def test_should_align_multi_line_display_math
    md = "```\nX_(N-k) = Σ x_n・e^(-2πi(N-k)n/N)\n= Σ x_n・e^(2πikn/N)\n```\n"
    out = D.transform(md)

    assert_includes out, '\\begin{aligned}'
    assert_includes out, 'X_(N-k) &= Σ x_n・e^(-2πi(N-k)n/N) \\\\'
    assert_includes out, '&= Σ x_n・e^(2πikn/N)'
    assert_includes out, '\\end{aligned}'
  end

  # MD-05: 言語付きフェンスは常にコード（著者が言語を明示している）。
  def test_should_never_touch_a_fence_with_a_language
    md = "```ruby\nx = Σ_value ** 2\n```\n"

    assert_equal md, D.transform(md)
  end

  # MD-06: 実行結果の貼り付けを弾く。言語なしフェンスの多く（546 件中 476 件）は
  # プログラムの出力であって数式ではない。
  def test_should_reject_program_output_pasted_into_a_fence
    [
      "```\n【課題93の結果】\n341: 合成数 = true\n```\n",
      "```\n341: base=2だけで判定 → 合成数と判定（正しい）\n```\n",
      "```\n選んだ品物: 黄金の仮面\n価値の合計: 69\n```\n"
    ].each { |md| assert_equal md, D.transform(md), "実行結果は数式にしない:\n#{md}" }
  end

  # MD-02 の要: 1 文字だけの綴りは記号そのものの説明であって式ではない。
  # 本書 32-metrics.md の「`・` で連結し」で実際に踏んだ。
  def test_should_not_detect_a_lone_symbol_as_math
    ['・', '×', '÷', 'π', 'λ', '^', '²'].each { |src| refute D.math?(src), "記号の説明: #{src}" }

    ['√n', 'Σx', 'eˣ', 'n³', '2²', 'Hₙ'].each { |src| assert D.math?(src), "2 文字以上は式: #{src}" }
  end

  # MD-07: `$` を含む綴りは触らない。起こすとデリミタが壊れる。
  def test_should_leave_spans_containing_a_dollar_sign_alone
    refute D.math?('$HOME/√x')
    md = "正規表現の `^` と `$` があります。\n"

    assert_equal md, D.transform(md)
  end

  # MD-08: フェンスの中のコードスパンを拾わない（フェンスを先に処理して隠す）。
  def test_should_not_transform_code_spans_inside_a_fence
    md = "```ruby\n# `√n` は綴りの説明\nputs 1\n```\n\n地の文の `√n` は数式です。\n"
    out = D.transform(md)

    assert_includes out, '# `√n` は綴りの説明', 'フェンスの中は無傷'
    assert_includes out, '地の文の $√n$ は数式です。'
  end

  # MD-09: 冪等。前処理は再実行されうる。
  def test_should_be_idempotent
    md = "約数は `√n` 以下。\n\n```\nπ(n) ≈ n / ln(n)\n```\n"
    once = D.transform(md)

    assert_equal once, D.transform(once)
  end
end
