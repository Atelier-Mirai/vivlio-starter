# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/math_text_renderer.rb
# ================================================================
# 責務:
#   単純な LaTeX インライン数式を HTML テキスト（<i>/<sup>/<sub>＋Unicode 記号）へ
#   変換する純粋関数。Kindle(KFX) は画像を本文フォント相対サイズにできず、数式 SVG が
#   フォントサイズ変更に追従しないため、テキスト化して 100% 追従させる（本文テキストは
#   定義上フォントサイズに追従する）。kindle-inline-math-textify-spec.md の実装。
#
# 方針（ホワイトリスト・全体拒否）:
#   §3.1 のサブセット（数字・ラテン文字・上下付き・\frac・記号・ギリシャ・\text 等）を
#   1 トークンずつ消費し、**1 つでも解釈できないトークンがあれば式全体を nil で拒否する**
#   （部分変換はしない）。拒否された式は呼び出し側が SVG のまま残す（px 固定フォールバック）。
#   拒否は異常ではなく正常系——複雑な式（\sqrt/\sum/積分/2 段入れ子等）は SVG で運ぶ。
#
# 純粋性:
#   Nokogiri 非依存・CONFIG 非依存・副作用なし。入力は $…$/\(…\) を剥いだ LaTeX 本文、
#   出力は HTML 文字列 or nil。単体テストで全規則を直接検証する。
# ================================================================

require 'strscan'

module VivlioStarter
  module CLI
    module Build
      # LaTeX 単純サブセット → HTML テキスト変換器（Kindle 数式テキスト化）
      module MathTextRenderer
        # 名前付き記号コマンド（\times 等）→ Unicode。§3.1 の記号行。
        SYMBOLS = {
          'times' => '×', 'cdot' => '⋅', 'pm' => '±', 'mp' => '∓',
          'approx' => '≈', 'neq' => '≠', 'leq' => '≤', 'geq' => '≥',
          'le' => '≤', 'ge' => '≥', 'sim' => '∼', 'propto' => '∝',
          'infty' => '∞', 'll' => '≪', 'gg' => '≫',
          'langle' => '⟨', 'rangle' => '⟩',
          'ldots' => '…', 'cdots' => '…', 'dots' => '…',
          # 大型演算子。直後の `_{…}^{…}` は既存の上下付き処理がそのまま拾うので、
          # `\sum_{i=1}^{n}` は `∑` + `<sub>i=1</sub><sup>n</sup>` になる。
          # SVG 画像より読みやすく、かつ本文のフォントサイズに追従する。
          'sum' => '∑', 'prod' => '∏', 'int' => '∫', 'oint' => '∮'
        }.freeze

        # ギリシャ文字コマンド → Unicode（立体＝イタリックにしない・§3.1）。
        GREEK = {
          'alpha' => 'α', 'beta' => 'β', 'gamma' => 'γ', 'delta' => 'δ',
          'epsilon' => 'ε', 'varepsilon' => 'ε', 'zeta' => 'ζ', 'eta' => 'η',
          'theta' => 'θ', 'vartheta' => 'ϑ', 'iota' => 'ι', 'kappa' => 'κ',
          'lambda' => 'λ', 'mu' => 'μ', 'nu' => 'ν', 'xi' => 'ξ',
          'omicron' => 'ο', 'pi' => 'π', 'varpi' => 'ϖ', 'rho' => 'ρ',
          'varrho' => 'ϱ', 'sigma' => 'σ', 'varsigma' => 'ς', 'tau' => 'τ',
          'upsilon' => 'υ', 'phi' => 'φ', 'varphi' => 'ϕ', 'chi' => 'χ',
          'psi' => 'ψ', 'omega' => 'ω',
          'Gamma' => 'Γ', 'Delta' => 'Δ', 'Theta' => 'Θ', 'Lambda' => 'Λ',
          'Xi' => 'Ξ', 'Pi' => 'Π', 'Sigma' => 'Σ', 'Upsilon' => 'Υ',
          'Phi' => 'Φ', 'Psi' => 'Ψ', 'Omega' => 'Ω'
        }.freeze

        # そのまま通す演算子・区切り（§3.1）。< > & は出力時にエスケープする。
        # `'` は導関数のプライム（`f'(x)`・`f''(0)`）。数式で普通に出る。
        OPERATORS = %r{[+\-=/<>()\[\]|,.:;!']}

        # Unicode で直接書かれた記号・ギリシャ文字・日本語をそのまま通す。
        #
        # **なぜ後から足したか**: この変換器は 2026-07-19 に、LaTeX で書かれた原稿だけを見て
        # 作られた（当時の原稿の数式は全件 `\times` `\pi` の形だった）。素の表記を組む機能が
        # 入ってからは `×` や `θ` が直接届くようになり、受理集合が実態に追いつかなくなった。
        # 上の SYMBOLS / GREEK は「コマンド名 → Unicode」の対応表なので、Unicode をそのまま
        # 受けて出すのは同じ字を返すだけで済む。
        # これを足すと `a^(p-1) mod p` や `sin²θ + cos²θ` が**真の上付き付きの HTML**になり、
        # 原文テキストへ落とさずに済む（Kindle での見栄えが一段良くなる）。
        # 日本語は `ぁ-ゖ` `ァ-ヺ` の範囲だけでは足りない——**長音符 `ー`（U+30FC）が外**にあり、
        # 「ハッシュ値 mod サーバー台数」が丸ごと拒否されていた。文字プロパティで書く。
        PASSTHROUGH = /[×÷±∓⋅・·≈≒≡≠≤≥≦≧∼∝∞…°−→∈]|[α-ωΑ-Ω]|[\p{Hiragana}\p{Katakana}\p{Han}ー々〆]/

        # TeX に対応マクロがある関数名。立体（イタリックにしない）で出す。
        FUNCTIONS = %w[
          arcsin arccos arctan sinh cosh tanh
          sin cos tan sec csc cot log ln exp det gcd max min lim
        ].freeze

        module_function

        # LaTeX（デリミタ除去済み）を HTML テキストへ変換する。
        # @param latex [String] $…$ / \(…\) を剥いだ LaTeX 本文
        # @return [String, nil] HTML 文字列（変換可能時）/ nil（サブセット外・空）
        def render(latex)
          src = latex.to_s
          return nil if src.strip.empty?

          scanner = StringScanner.new(src)
          html = consume_run(scanner, upright: false, allow_script: true, allow_frac: true, stop_at_brace: false)
          return nil if html.nil? || !scanner.eos? # 未消費が残る＝解釈できないトークンがあった

          space_after_big_operators(html)
        end

        # `∑<sub>i=1</sub><sup>n</sup><i>i</i>` は上下限と被演算子が詰まって読みにくい。
        # 数式の空白は TeX 流に落としているので（consume_atom）、ここで細空白を補う。
        BIG_OPERATOR_WITH_LIMITS = %r{([∑∏∫∮](?:<su[bp]>.*?</su[bp]>)*)(?=[^\s])}m

        def space_after_big_operators(html)
          html.gsub(BIG_OPERATOR_WITH_LIMITS) { "#{::Regexp.last_match(1)}\u2009" }
        end

        # トークン列を消費して HTML を組む。stop_at_brace 時はトップレベルの '}' で停止（消費しない）。
        # 1 つでも解釈不能なトークンがあれば nil（＝式全体を拒否）。
        def consume_run(scanner, upright:, allow_script:, allow_frac:, stop_at_brace:)
          buf = +''
          until scanner.eos?
            break if stop_at_brace && scanner.check(/\}/)

            piece = consume_atom(scanner, upright:, allow_script:, allow_frac:)
            return nil if piece.nil?

            buf << piece
          end
          buf
        end

        # 1 アトムを消費して HTML 片を返す（空白は '' か ' '）。未知トークンは nil。
        def consume_atom(scanner, upright:, allow_script:, allow_frac:)
          if scanner.scan(/\s+/)
            upright ? ' ' : '' # 数式空白は無視、\text 等の立体テキスト内は保持
          elsif (letters = scanner.scan(/[A-Za-z]+/))
            upright ? escape_html(letters) : "<i>#{escape_html(letters)}</i>"
          elsif (digits = scanner.scan(/[0-9]+/))
            digits
          elsif scanner.scan(/\^/)
            wrap_script(scanner, 'sup', upright:, allow_script:, allow_frac:)
          elsif scanner.scan(/_/)
            wrap_script(scanner, 'sub', upright:, allow_script:, allow_frac:)
          elsif scanner.check(/\{/)
            consume_brace_group(scanner, upright:, allow_script:, allow_frac:) # 透過グループ
          elsif scanner.scan(/\\/)
            consume_command(scanner, upright:, allow_frac:)
          elsif (op = scanner.scan(OPERATORS))
            escape_html(op)
          elsif (raw = scanner.scan(PASSTHROUGH))
            raw # 記号・ギリシャ・日本語はそのままの字で出す（立体）
          end
        end

        # 上/下付き（<sup>/<sub>）。2 段入れ子は許さない（引数を allow_script: false で読む）。
        def wrap_script(scanner, tag, upright:, allow_script:, allow_frac:)
          return nil unless allow_script

          arg = consume_group_or_token(scanner, upright:, allow_script: false, allow_frac:)
          arg && "<#{tag}>#{arg}</#{tag}>"
        end

        # \command を消費する。\ は消費済みで、続く名前/記号を読む。
        def consume_command(scanner, upright:, allow_frac:)
          if (name = scanner.scan(/[A-Za-z]+/))
            dispatch_named_command(name, scanner, allow_frac:)
          elsif scanner.scan(/,/)      # \,  細空白
            " "
          elsif scanner.scan(/[;:]/)   # \; \:  通常空白
            ' '
          elsif (esc = scanner.scan(/[%&#_{}$]/)) # \% \& \# \_ \{ \} \$  リテラル
            escape_html(esc)
          end
          # \\ やその他の記号は nil（拒否）
        end

        # 英字コマンドの振り分け（\text/\mathrm・\frac・空白語・記号/ギリシャ表）。未知は nil。
        def dispatch_named_command(name, scanner, allow_frac:)
          case name
          when 'text', 'mathrm'
            consume_brace_group(scanner, upright: true, allow_script: false, allow_frac: false)
          when 'frac'
            return nil unless allow_frac

            numer = consume_brace_group(scanner, upright: false, allow_script: true, allow_frac: false)
            denom = numer && consume_brace_group(scanner, upright: false, allow_script: true, allow_frac: false)
            # **括弧が要る。** `\frac{a+b}{2}` を `a+b/2` と書くと `a + (b/2)` に読める
            # ——意味が変わる。`\frac{1}{2}` のような単項なら付けない。
            denom && "#{parenthesize(numer)}/#{parenthesize(denom)}"
          when 'hat'
            # `\hat{p}` → `p̂`（結合アクセント U+0302）。統計の推定値でよく出る。
            # HTML のテキストなので結合文字がそのまま乗る
            base = consume_brace_group(scanner, upright: false, allow_script: false, allow_frac: false)
            base && "#{base}\u0302"
          when 'sqrt'
            # 根号は横線を引けないので `√…` にする。中身が複合式なら括弧で範囲を示す
            # ——`√a+b` は「√a に b を足す」に読めてしまう。
            body = consume_brace_group(scanner, upright: false, allow_script: true, allow_frac: false)
            body && "√#{parenthesize(body)}"
          when 'quad', 'qquad'
            ' '
          when 'bmod'
            ' mod '
          when 'pmod'
            inner = consume_brace_group(scanner, upright: true, allow_script: false, allow_frac: false)
            inner && " (mod #{inner})"
          when *FUNCTIONS
            name # 立体で出す（素のままだと 𝑠𝑖𝑛 と 1 文字ずつ斜体になる）
          else
            SYMBOLS[name] || GREEK[name]
          end
        end

        # 複合式なら括弧で囲む。判定は**描画済み HTML から上下付きの中身を除いた**うえで、
        # 加減算や除算が残るかを見る（`10<sup>-34</sup>` の `-` は指数の符号であって
        # 項の区切りではない）。生成するタグは <i>/<sup>/<sub> だけなので、
        # タグ自体に `+ - /` が現れることはない。
        def parenthesize(html)
          # 上下付きは中身ごと落とす（指数の符号を項の区切りと読まないため）。
          # 残りのタグも落とす——`</i>` の `/` を除算と読まないため。
          bare = html.gsub(%r{<su[bp]>.*?</su[bp]>}m, '').gsub(/<[^>]+>/, '')
          bare.match?(%r{[+\-−/]}) ? "(#{html})" : html
        end

        # 上/下付き・\frac の引数（'{…}' グループ or 単一アトム）。先行空白は読み飛ばす。
        def consume_group_or_token(scanner, upright:, allow_script:, allow_frac:)
          scanner.skip(/\s+/)
          if scanner.check(/\{/)
            consume_brace_group(scanner, upright:, allow_script:, allow_frac:)
          else
            consume_atom(scanner, upright:, allow_script:, allow_frac:)
          end
        end

        # '{ … }' を必須で読み、中身の run を返す（透過）。閉じ '}' が無ければ nil。
        def consume_brace_group(scanner, upright:, allow_script:, allow_frac:)
          scanner.skip(/\s+/)
          return nil unless scanner.scan(/\{/)

          inner = consume_run(scanner, upright:, allow_script:, allow_frac:, stop_at_brace: true)
          return nil if inner.nil? || !scanner.scan(/\}/)

          inner
        end

        # 出力の HTML 予約文字をエスケープする（< > & のみ。" は属性化しないので不要）。
        def escape_html(str) = str.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
      end
    end
  end
end
