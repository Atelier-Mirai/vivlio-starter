# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/plain_math_transpiler.rb
# ================================================================
# 責務:
#   著者が素で書いた数式（`√n`・`a^(p-1) mod p`・`Σx²`・`H₂O`）を TeX へ起こす。
#   仕様: plain-math-notation-spec.md §5。`MathTextRenderer`（TeX → 素の表記・Kindle 用）と
#   対になる向き。
#
# なぜ要るのか:
#   MathJax の TeX パーサは素の表記を**エラーにしない**まま壊す（仕様 §1 の実測）。
#     x²+y²   → 𝑥+𝑦        上付きが消える
#     H₂O     → 𝐻𝑂          下付きが消える
#     a・b    → 𝑎𝑏          中黒（U+30FB）が消える
#     ａ＋ｂ  → （空）       全角は式ごと消える
#     2^(1/3) → 2 の右肩に ( だけ
#     √2      → 根号の横線が無い
#     Σx      → 𝛴𝑥（斜体の変数。総和記号にならない）
#     tanθ    → 𝑡𝑎𝑛𝜃（1 文字ずつ斜体）
#   ビルドは成功し警告も出ないので、著者は完成した本を見るまで気づかない。
#
# 何を変換しないか（同じくらい重要）:
#   ギリシャ文字・`≡ ≈ ≒ ≠ ≦ ∈ → ° ∞ ... ! −`・`·`(U+00B7)・`∑`(U+2211)・`∫`・`f'(x)` は
#   **そのままで正しく描かれる**ことを実測した。触らない記号は壊しようがないので、
#   表を短く保つこと自体に安全上の意味がある。消えるのは `・`(U+30FB) のほうで、
#   `·`(U+00B7) ではない——この 2 つは見た目が似ているが挙動が違う。
#
# 部分変換であって全体拒否ではない:
#   `MathTextRenderer` は 1 トークンでも解釈できなければ式全体を拒否する（拒否しても
#   SVG という完全な代替経路が残るため）。こちらは逆に、解釈できない字を原文のまま
#   次へ送る。素の表記と TeX は混在しうる（`\frac{1}{2}√2`）ので、全体拒否は
#   「直せるものを直さない」だけになり、安全側にも倒れない。安全性はゲート（plain?）が担う。
#
# 純粋性:
#   Nokogiri 非依存・CONFIG 非依存・副作用なし・例外を投げない。入力はデリミタを剥いだ
#   数式本文、出力は TeX 文字列。閉じ括弧が無い `√(x` のような壊れた入力は、その位置から
#   先を原文のまま通す。
# ================================================================

require 'strscan'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # 素の表記 → TeX 変換器（plain-math-notation-spec.md §5）
      module PlainMathTranspiler
        # Unicode 上付き文字 → 通常文字。`¹²³` だけ Latin-1 に居て他と離れている。
        SUPERSCRIPT = {
          '⁰' => '0', '¹' => '1', '²' => '2', '³' => '3', '⁴' => '4',
          '⁵' => '5', '⁶' => '6', '⁷' => '7', '⁸' => '8', '⁹' => '9',
          '⁺' => '+', '⁻' => '-', '⁼' => '=', '⁽' => '(', '⁾' => ')',
          'ⁿ' => 'n', 'ⁱ' => 'i', 'ˣ' => 'x' # ˣ は U+02E3（`eˣ` で実在）
        }.freeze

        # Unicode 下付き文字 → 通常文字。`Hₙ` の ₙ は U+2099。
        SUBSCRIPT = {
          '₀' => '0', '₁' => '1', '₂' => '2', '₃' => '3', '₄' => '4',
          '₅' => '5', '₆' => '6', '₇' => '7', '₈' => '8', '₉' => '9',
          '₊' => '+', '₋' => '-', '₌' => '=', '₍' => '(', '₎' => ')',
          'ₙ' => 'n', 'ₖ' => 'k', 'ᵢ' => 'i', 'ⱼ' => 'j'
        }.freeze

        SUPERSCRIPT_CHARS = Regexp.union(SUPERSCRIPT.keys).freeze
        SUBSCRIPT_CHARS   = Regexp.union(SUBSCRIPT.keys).freeze
        SUPERSCRIPT_RUN   = /#{SUPERSCRIPT_CHARS}+/o
        SUBSCRIPT_RUN     = /#{SUBSCRIPT_CHARS}+/o

        # TeX に対応するマクロがある関数名。長いものから並べる
        # （`arctan` を `arc` + `tan` に割らないため。Regexp.union は先頭一致優先）。
        FUNCTIONS = %w[
          arcsin arccos arctan sinh cosh tanh
          sin cos tan sec csc cot log ln exp det gcd max min
        ].freeze

        # 関数名の綴り。前後が英数字・バックスラッシュのときは拾わない
        # （`\sin` は変換済み、`expression` の `exp` は関数ではない）。
        FUNCTION_NAMES = /(?<![\\\p{Alnum}])(?:#{FUNCTIONS.join('|')})(?![A-Za-z0-9])/o

        # 素の表記のしるし（ゲート）。仕様 §5.1。
        #
        # **既に正しい TeX を 1 文字も変えないための保険**である。`\sqrt{}` に `√` は無く、
        # `^{2}` に `²` は無く、`f^{(n)}` は `^` の次が `{` であって `(` ではない。
        #
        # `^` `_` の扱いに注意: `a^2` は TeX としてそのまま正しいので、しるしにしない。
        # 壊れるのは**引数が 2 文字以上**のとき（`a^560` は `a^5` の後ろに `60` が並ぶ）と、
        # 丸括弧を引数にしたとき（`a^(p-1)`）だけなので、その形だけを拾う。
        PLAIN_MARKERS = Regexp.union(
          SUPERSCRIPT_CHARS,
          SUBSCRIPT_CHARS,
          /[√Σ・]/,                        # 根号・総和(U+03A3)・中黒(U+30FB)
          /[\u{FF01}-\u{FF5E}\u{3000}]/,    # 全角英数字・全角記号・全角空白
          /[A-Za-z]̂/,                 # 合成アクセント（p̂）
          /[\^_]\(/,                        # 丸括弧を引数にした上下付き
          /[\^_]\w{2,}/,                    # 引数が 2 文字以上の上下付き
          /<=|>=|!=/,
          /(?<!\\)[%#&]/,                  # TeX の特殊文字（素のままだと消える・エラーになる）
          /[〜～]/,
          /(?<!\\)\bmod\b/,
          /∫\s*\[/,                         # 上下限つきの積分
          /(?<!\\)\blim\s*\(/,
          /(?<!\\)\b(?:#{FUNCTIONS.join('|')})\b/o
        ).freeze

        # 上下付きの「基底」になれる文字で終わっているか。
        # `x²` の x や `(a+b)²` の ) は基底になるが、行頭や `+` の直後は基底が無い。
        BASE_TAIL = /[\p{Alnum}\p{Greek})\]}]\z/

        module_function

        # 素の表記のしるしを含むか（ゲート）。
        # @param src [String] デリミタを剥いだ数式本文
        # @return [Boolean]
        def plain?(src) = !src.nil? && src.match?(PLAIN_MARKERS)

        # 素の表記を TeX へ起こす。しるしが無ければ src をそのまま返す。
        # @param src [String] デリミタを剥いだ数式本文（素の表記 / TeX / 混在）
        # @param force [Boolean] ゲートを飛ばす（判定器が数式と決めた式に使う）
        # @return [String] TeX 記法
        def to_tex(src, force: false)
          text = src.to_s
          return src if text.empty?
          return src unless force || plain?(text)

          run(StringScanner.new(text))
        end

        # --- ここから下は内部 -------------------------------------------------

        # トークン列を消費して TeX を組む。`stop` を見つけたら消費せずに戻る。
        def run(scanner, stop: nil)
          out = +''
          out << atom(scanner, out) until scanner.eos? || (stop && scanner.check(stop))
          out
        end

        # 1 トークンを消費して TeX 片を返す。out は「直前に何を出したか」の判定にだけ使う。
        def atom(scanner, out)
          command(scanner) || group(scanner) || script(scanner, out) ||
            radical(scanner) || big_operator(scanner) || limit(scanner) ||
            modulo(scanner) || named_function(scanner) || symbol(scanner) ||
            scanner.getch # 解釈できない字は原文のまま通す
        end

        # `\command` は中身を見ずにそのまま通す（既存 TeX を壊さない）。
        def command(scanner) = scanner.scan(/\\(?:[A-Za-z]+|.)/m)

        # `{…}` は透過。中は再帰する。
        def group(scanner)
          return nil unless scanner.scan(/\{/)

          inner = run(scanner, stop: /\}/)
          "{#{inner}#{scanner.scan(/\}/) || ''}"
        end

        # 上付き・下付き。Unicode の上下付き文字と、`^`/`_` の両方をここで正規化する。
        def script(scanner, out)
          if (raw = scanner.scan(SUPERSCRIPT_RUN))
            return unicode_script(raw, SUPERSCRIPT, '^', out)
          end
          if (raw = scanner.scan(SUBSCRIPT_RUN))
            return unicode_script(raw, SUBSCRIPT, '_', out)
          end
          return nil unless (mark = scanner.scan(/[\^_]/))

          argument = script_argument(scanner)
          # 引数を読めなければ `^` をそのまま通す（`2^(` を `2^{}(` にしない）
          argument.nil? || argument.empty? ? mark : "#{mark}{#{argument}}"
        end

        # 連続する Unicode 上下付き文字を 1 つの `^{…}` / `_{…}` にまとめる。
        # 基底が無いとき（式頭の `²x`）は変換せず原文のまま残す——基底の無い msup になり、
        # 著者の意図と無関係な組版になるため。
        def unicode_script(raw, table, mark, out)
          return raw unless out.match?(BASE_TAIL)

          "#{mark}{#{raw.each_char.map { table[it] }.join}}"
        end

        # `^` / `_` の引数。`(…)` は外して中身を、`{…}` はそのまま、
        # それ以外は 1 かたまり（符号つきの英数字列）を取る。
        def script_argument(scanner)
          return balanced(scanner) if scanner.check(/\(/)
          return run(scanner, stop: /\}/).tap { scanner.scan(/\}/) } if scanner.scan(/\{/)

          scanner.scan(/[-−+]?[\p{Alnum}\p{Greek}]+/) || ''
        end

        # `√` は直後の 1 トークンだけに掛かる。全体に掛けたければ `√(…)` と括る。
        # `√x+1` が `\sqrt{x}+1` になるのはこの規則による（仕様 §5.2）。
        def radical(scanner)
          saved = scanner.pos
          return nil unless scanner.scan(/√/)

          scanner.skip(/[ \t]+/)
          body = if scanner.check(/\(/)
                   balanced(scanner)
                 elsif scanner.scan(/\{/)
                   run(scanner, stop: /\}/).tap { scanner.scan(/\}/) }
                 else
                   # 数は丸ごと 1 トークン。1 文字ずつ取ると `√163` が `\sqrt{1}63` になる
                   scanner.scan(/\d+(?:\.\d+)?|[[:alpha:]]/)
                 end
          return "\\sqrt{#{body.strip}}" if body && !body.strip.empty?

          # 閉じ括弧が無い `√(x` や裸の `√`。原文のまま通し、式全体を諦めない
          scanner.pos = saved
          scanner.getch
        end

        # `Σ`（U+03A3）は斜体の変数として描かれてしまうので `\sum` へ。
        # `Σ(k=0 to ∞)` のような著者が書いた上下限の記法もここで拾う。
        # `∑`（U+2211）は既に総和記号なので触らない。
        def big_operator(scanner)
          if scanner.scan(/Σ/) then bounds(scanner, '\\sum')
          elsif scanner.scan(/∫/) then integral_bounds(scanner)
          end
        end

        # `(k=0 to ∞)` → `_{k=0}^{∞}`。`to` が無ければ上下限なしの演算子だけを返す。
        def bounds(scanner, name)
          saved = scanner.pos
          scanner.skip(/\s*/)
          if scanner.check(/\(/) && (inner = balanced(scanner)) && (parts = inner.split(/\s+to\s+/, 2)).size == 2
            return "#{name}_{#{parts[0].strip}}^{#{parts[1].strip}}"
          end

          scanner.pos = saved
          macro(scanner, name)
        end

        # `∫[0, π/2]` → `\int_{0}^{π/2}`。著者が考えた記法なので TeX 側に対応が無い。
        def integral_bounds(scanner)
          saved = scanner.pos
          scanner.skip(/\s*/)
          if scanner.check(/\[/) && (inner = balanced(scanner, ['[', ']'])) && (parts = inner.split(',', 2)).size == 2
            return "\\int_{#{parts[0].strip}}^{#{parts[1].strip}}"
          end

          scanner.pos = saved
          macro(scanner, '\\int')
        end

        # `lim(n→∞)` → `\lim_{n→∞}`。`→` はそのままで正しく描かれる。
        def limit(scanner)
          return nil unless scanner.scan(/(?<!\\)\blim(?=\s*\()/)

          scanner.skip(/\s*/)
          "\\lim_{#{balanced(scanner).to_s.strip}}"
        end

        # `(mod n)` → `\pmod{n}`、単独の `mod` → `\bmod`。
        # `mod` を素のまま渡すと `𝑚𝑜𝑑` と斜体 3 文字で並ぶ。
        def modulo(scanner)
          saved = scanner.pos
          if scanner.scan(/\(\s*mod\b/)
            inner = run(scanner, stop: /\)/)
            return "\\pmod{#{inner.strip}}" if scanner.scan(/\)/)

            scanner.pos = saved
          end
          scanner.scan(/(?<!\\)\bmod\b/) ? macro(scanner, '\\bmod') : nil
        end

        # `sin(x)` → `\sin(x)`、`tanθ` → `\tan θ`（ギリシャ文字自体は素通し）。
        # 素のままだと `𝑡𝑎𝑛𝜃` と 1 文字ずつ斜体になる。
        # `log₂` の下付きは続く script() が拾う——そのためにここで空白を足してはならない
        # （空白があると基底が無いと判定され、₂ が変換されずに残る）。
        def named_function(scanner)
          (name = scanner.scan(FUNCTION_NAMES)) && macro(scanner, "\\#{name}")
        end

        # マクロの直後が英字・ギリシャ文字だと `\tanθ` のように 1 つの命令として読まれるので、
        # そのときだけ空白を足す。`\sin(x)` や `\sin^{2}θ` には足さない——余計な空きが出るうえ、
        # 上付き・下付きの基底が空白で隠れてしまう。
        def macro(scanner, name) = scanner.check(/[[:alpha:]]/) ? "#{name} " : name

        # TeX が特別な意味を与える字。素で書かれると**黙って壊れる**ので必ず退避する。
        #   `50% + 1` → `50`      % から後ろがコメント扱いで消える
        #   `a#b` `a&b`           TeX エラー（merror）になる
        # 既に `\%` と書いてある場合は command() が先に食うので、ここへは来ない。
        TEX_SPECIAL = /[%#&$]/
        # 波ダッシュ。**半角 `~` にしてはならない**——TeX の `~` は改行しない空白で、
        # 範囲を表す `g^1〜g^(p-1)` が `g^1 g^(p-1)` に化ける。
        WAVE_DASH = /[〜～]/

        # 1 文字の置き換え。全角は半角へ、合成アクセントは `\hat{}` へ、
        # `・`(U+30FB) は `\cdot` へ（消えるのはこちらで、`·`(U+00B7) は無事）。
        def symbol(scanner)
          if (accented = scanner.scan(/[A-Za-z]̂/)) then "\\hat{#{accented[0]}}"
          elsif scanner.scan(/・/) then macro(scanner, '\\cdot')
          elsif scanner.scan(WAVE_DASH) then macro(scanner, '\\sim')
          elsif scanner.scan(/<=/) then macro(scanner, '\\leq')
          elsif scanner.scan(/>=/) then macro(scanner, '\\geq')
          elsif scanner.scan(/!=/) then macro(scanner, '\\neq')
          elsif (special = scanner.scan(TEX_SPECIAL)) then escape_tex(scanner, special)
          elsif (wide = scanner.scan(/[\u{FF01}-\u{FF5D}]/)) then escape_tex(scanner, (wide.ord - 0xFEE0).chr(Encoding::UTF_8))
          elsif scanner.scan(/　/) then ' '
          end
        end

        # TeX の特殊文字なら退避する（`50%` → `50\%`、全角の `％` も同じ）。
        #
        # ただし `\begin{aligned}` のような環境の中では、`&` は桁揃えの記号として、
        # `#` はマクロ引数として**正しい**——環境を使う式は LaTeX を知っている著者が
        # 書いたものなので、そこは触らない（本書 96-sample.md の九九の表で実際に踏んだ）。
        # `%` だけは例外で常に退避する。素のままだと後ろが丸ごとコメントとして消えるため。
        def escape_tex(scanner, char)
          return char unless char.match?(TEX_SPECIAL)
          return char if char != '%' && scanner.string.include?('\\begin{')

          "\\#{char}"
        end

        # 対応する括弧まで読み、中身を再帰変換して返す（括弧自体は含めない）。
        # 閉じ括弧が無ければ位置を戻して nil——壊れた入力で式全体を諦めないため。
        def balanced(scanner, pair = ['(', ')'])
          open, close = pair
          saved = scanner.pos
          return nil unless scanner.scan(/#{Regexp.escape(open)}/)

          out = +''
          depth = 1
          until scanner.eos?
            if scanner.check(/#{Regexp.escape(open)}/)
              depth += 1
            elsif scanner.check(/#{Regexp.escape(close)}/)
              depth -= 1
              break if depth.zero?
            end
            out << atom(scanner, out)
          end
          unless scanner.scan(/#{Regexp.escape(close)}/)
            scanner.pos = saved
            return nil
          end

          out
        end
      end
    end
  end
end
