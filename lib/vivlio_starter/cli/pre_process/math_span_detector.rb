# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/math_span_detector.rb
# ================================================================
# 責務:
#   著者がバッククォートで書いた数式を見つけて `$…$` / `$$…$$` へ起こす。
#   仕様: plain-math-notation-spec.md §6。変換（素の表記 → TeX）は別モジュール
#   （PlainMathTranspiler）が担い、こちらは**どれが数式か**だけを決める。
#
# なぜバッククォートなのか:
#   数式記法を知らない著者は、等幅で本文と区別が付くという理由でバッククォートを
#   数式デリミタの代用に使う。実測（workbook・166 ファイル＋problems.yml）:
#     インラインコードスパン 3,422 出現のうち **361 出現（11%）が数式**
#     言語なしフェンス 546 件のうち **70 件がディスプレイ数式**
#   残る 89% は本物のコード（`puts`・`Complex.polar`・`array[i]`）なので、判定が要る。
#
# 判定の向き（重要）:
#   **コードのしるしを 1 つでも含めばコード**（拒否が優先）。そのうえで数式のしるしが
#   あって初めて数式とする。逆向き（数式のしるしがあれば数式）にすると、
#   `array[i] * 2` のようなコードを拾う。
#
# 明示は尊重し、推測は保守的に（仕様 §3.4）:
#   著者が `$…$` と書いた式は日本語を含んでいても組む。一方こちらは**推測**なので、
#   日本語を含む綴りは数式にしない——`攻撃側の戦闘力 = (投入兵士数 × 訓練度)` を
#   数式画像にしても得るものは無く、それを機械が黙って決めてよい判断でもない。
#
# 逃げ道:
#   確実に数式にしたい → `$…$` で明示する / ```math フェンスに置く
#   確実にコードのままにしたい → 言語付きフェンス（```ruby）に置く
#
# ```math は判定を通さない（仕様 §6.1）:
#   GitHub が同じ綴りでディスプレイ数式を表すので、著者にとって学習が要らない。
#   言語を明示した以上これは**宣言**であって推測ではないので、行数・実行結果らしさ・
#   関係演算子・`math?` のいずれも問わずディスプレイ数式にする。
#   `cos = 1 - 2 + 4 - 6` のように数式のしるしを 1 つも持たない綴り——素の判定では
#   コードと区別が付かないもの——を組ませる唯一の手段でもある。
#   Prism の言語名と衝突しない（Prism にあるのは `latex` / 別名 `tex` `context`）。
#   ```latex は「LaTeX のソースを見せる」用途なのでコードのまま扱う。
# ================================================================

require_relative '../common'
require_relative '../masking'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # バッククォートの中の数式を `$…$` / `$$…$$` へ起こす判定器
      module MathSpanDetector
        # --- コードのしるし（1 つでもあれば数式にしない） ---------------------
        # `\.[A-Za-z_]` は小数点を避けるため（`0.99` をメソッド呼び出しと誤認すると
        # 数式を 15 件落とす。仕様 §6.3 で実際に踏んだ）。
        CODE_MARKERS = /
          \.[A-Za-z_] | :: | => | \|\| | &&  | \#\{ | @\w
          | \*\*                                        # Ruby のべき乗・Markdown の太字
          | \[\w*\]                                     # 添字アクセス
          | \{\s*\|                                     # ブロック引数
          | [;{}]\s*\z
          | \b(?:puts|print|def|end|do|nil|true|false|class|module|require|return
              |each|map|select|reject|new|attr_\w+|elsif|then|yield|lambda|proc)\b
        /x

        # --- 数式のしるし ------------------------------------------------------
        # 関数名は前後が英数字だと拾わない（`expression` の `exp` は関数ではない。
        # これも仕様 §6.3 で踏んだ）。
        MATH_FUNCTIONS = %w[arcsin arccos arctan sinh cosh tanh sin cos tan sec csc cot
                            log ln exp det gcd lim].freeze
        # **強いしるし**——これがあれば、日本語を含んでいても式と見てよい。
        # 変数を日本語で書いた式（`平文^e mod n`）は、`^` や `mod` のような
        # 構造を持つしるしがあって初めて式と分かる。
        STRONG_MARKERS = /
          [²³¹⁰⁴-⁹⁺⁻⁼⁽⁾ⁿⁱˣ]                            # Unicode 上付き
          | [₀-₉₊₋₌₍₎ₙₖᵢⱼ]                               # Unicode 下付き
          | [√Σ∑∏∫≡≒≈≠≦≧≤≥] | [α-ωΑ-Ω]
          | (?<![\\[:alnum:]])[[:alnum:])\]]+\s*\^        # べき乗（`圧力^2` のように底が日本語でも拾う）
          | (?<=[[:alnum:])）])\s*\bmod\b\s*[[:alnum:](（]  # 両側に被演算子のある剰余
          | (?<![\\[:alnum:]])(?:#{MATH_FUNCTIONS.join('|')})(?![[:alnum:]])\s*[(θ]
        /x

        # **弱いしるし**——日本語と一緒だと式か地の文か決まらない。
        # `行計 × 列計 ÷ 総計` は式にも読めるが、数式として組んで得るものが無く、
        # それを機械が黙って決めてよい判断でもない（§3.4）。
        WEAK_MARKERS = /[×÷±∓・·°−∞]/

        MATH_MARKERS = Regexp.union(STRONG_MARKERS, WEAK_MARKERS)

        # 日本語（`・` と `〜` は数式の中で使われるので除く）。
        JAPANESE = /[ぁ-ゖァ-ヺ一-鿿]/

        # 実行結果の貼り付け。ディスプレイ候補から弾く（仕様 §6.2）。
        # **`：` を一律に弾いてはならない**——`外接： C(n) = 2n・tanθ` は日本語ラベル付きの
        # 本物の数式で、同じ字を使う。弾く根拠は「見出し行がある」「矢印で結果を書いている」に置く。
        OUTPUT_MARKERS = /【.*】|→|⇒/

        # ディスプレイ候補の上限行数。これを超えるものは実行結果の貼り付けとみなす。
        MAX_DISPLAY_LINES = 8

        # 揃えるための関係演算子（複数行を \\begin{aligned} で組むときの `&` の位置）。
        RELATION = /(?<![<>=!])[=≡≈≒](?![=])/

        # 数式であることを著者が明示したフェンス（```math / ~~~math）。
        FENCE_OPENER = /\A(?:`{3,}|~{3,})[ \t]*/
        EXPLICIT_LANG = /#{FENCE_OPENER.source}math[ \t]*\z/i

        # 著者がすでに TeX の行組みを書いている印。`\begin{aligned}` や `\\` があれば
        # そのまま渡す（こちらで aligned を被せると二重になる）。
        AUTHORED_ROWS = /\\\\|\\begin\{/

        module_function

        # 1 つの綴りが数式か。
        # @param text [String] コードスパン / フェンス 1 行の中身
        # @return [Boolean]
        def math?(text)
          body = text.to_s.strip
          return false if body.include?('$')
          # 1 文字だけの綴りは**記号そのものの説明**であって式ではない
          # （本書 32-metrics.md の「`・` で連結し」で実際に踏んだ）。
          # 実測でこの規則が落とすのはコーパス全体で `λ` 1 種だけ。2 文字以上は
          # `√n` `Σx` `eˣ` `n³` `2²` のように本物の式が並ぶので、境界はここが妥当。
          return false if body.chars.size < 2
          return false if body.match?(CODE_MARKERS)
          return false unless body.match?(MATH_MARKERS)

          # 日本語を含むときは**強いしるしがあるときだけ**式と見る。
          # `平文^e mod n` は変数名が日本語なだけの式なので組む。
          # `行計 × 列計 ÷ 総計` は `×` しか手がかりが無く、式か地の文か決められない。
          body.match?(JAPANESE) ? body.match?(STRONG_MARKERS) : true
        end

        # 本文中のバッククォート数式を `$…$` / `$$…$$` へ起こす。
        # @param content [String] 章の Markdown 本文
        # @return [String] 置換後の本文
        def transform(content)
          return content if content.nil? || content.empty?

          # --- Phase: フェンスを先に処理する（中のコードスパンを拾わないため） ---
          # 数式でないフェンスはプレースホルダへ退避し、インライン走査から隠す。
          stash = {}
          text = Masking.replace_top_level_fences(content) do |block, _lineno|
            display_math(block) || stash_block(block, stash)
          end

          # --- Phase: インラインコードスパンを起こす ---
          text = transform_inline_spans(text)

          # --- Phase: 退避したフェンスを戻す ---
          stash.each { |placeholder, original| text = text.sub(placeholder) { original } }
          text
        end

        # --- ここから下は内部 -------------------------------------------------

        # フェンスブロックがディスプレイ数式なら `$$…$$` を返す。違えば nil。
        #
        # ```math は**宣言**なので判定を通さない。素の言語なしフェンスだけが推測の対象で、
        # そちらには行数・実行結果らしさ・関係演算子・`math?` の 4 条件が掛かる。
        def display_math(block)
          lines = block.lines.map(&:chomp)
          opener = lines.first.to_s.strip
          explicit = opener.match?(EXPLICIT_LANG)
          return nil unless explicit || opener.match?(/#{FENCE_OPENER.source}\z/) # 他の言語付きは常にコード

          body = lines[1..-2].to_a.map(&:rstrip).reject { it.strip.empty? }
          return nil if body.empty?
          return "\n$$\n#{display_body(body)}\n$$\n" if explicit

          return nil if body.size > MAX_DISPLAY_LINES
          return nil if body.any? { it.match?(OUTPUT_MARKERS) }
          return nil unless body.all? { it.match?(RELATION) && math?(it) }

          "\n$$\n#{display_body(body)}\n$$\n"
        end

        # 複数行は `\begin{aligned}` で関係演算子の位置を揃える。
        # 1 行ずつ独立した `$$` にすると、`X = …` に続く `= …` の導出が揃わない。
        # 著者がすでに `\\` や `\begin{…}` を書いているときは、その行組みをそのまま渡す。
        def display_body(body)
          return body.first.strip if body.size == 1
          return body.map(&:strip).join("\n") if body.any? { it.match?(AUTHORED_ROWS) }

          rows = body.map { align_row(it.strip) }
          "\\begin{aligned}\n#{rows.join(" \\\\\n")}\n\\end{aligned}"
        end

        # 最初の関係演算子の前に `&` を置く（`aligned` の揃え位置）。
        def align_row(row) = row.sub(RELATION) { "&#{::Regexp.last_match(0)}" }

        # 数式でないフェンスをプレースホルダへ退避する。
        def stash_block(block, stash)
          placeholder = "\u0000VS_FENCE_#{stash.size}\u0000"
          stash[placeholder] = block
          placeholder
        end

        # インラインコードスパンのうち数式のものを `$…$` にする。
        # 二重バッククォート（``…``）は対象外——記法を説明するために使われる形なので触らない。
        def transform_inline_spans(text)
          text.gsub(/(?<!`)`([^`\n]+)`(?!`)/) do
            body = ::Regexp.last_match(1)
            math?(body) ? "$#{body.strip}$" : ::Regexp.last_match(0)
          end
        end
      end
    end
  end
end
