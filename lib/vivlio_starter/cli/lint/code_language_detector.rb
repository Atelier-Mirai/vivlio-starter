# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/lint/code_language_detector.rb
# ================================================================
# 責務:
#   言語名のないコードブロックのうち、言語を推定してよいものを選ぶ（一段目）。
#   仕様: code-language-detection-spec.md §3。
#
#   推定は二段構えで、ここは「コードかどうか」を受け持つ。「どの言語か」は
#   二段目（CodeLanguageGuesser・Guesslang）が受け持つ。分けるのは、汎用の推定器が
#   実行結果・ディレクトリの木・盤面を言語と取り違えるためである（仕様 §1.3・§1.4）。
#   確信度で分けようとしても、取り違えた判定のほうが高い値になることがある。
#
# 判定の向き:
#   MathSpanDetector と同じく**除外のしるしを 1 つでも含めば推定しない**。
#   言語名なしのフェンスを「色を付けない」置き場として使う著者がいる（本書・練習帳）ので、
#   迷うものは推定に回さない。
#
# 候補の言語:
#   同じ章で著者が明示している言語 → 本全体で明示している言語 → 既定の 16 言語の順に絞る
#   （仕様 §3.4）。Ruby の章の言語名なしのコードは、まず Ruby である。
#
# 知らせるかどうか:
#   Guesslang の確信度が 0.3 以上のとき、または自前の「言語のしるし」（LANGUAGE_HINTS）と
#   Guesslang の推定が一致したとき（仕様 §8.5）。数行のコードは確信度が上がらないため、
#   独立した二つの手がかりの一致で補う。
# ================================================================

require 'json'
require 'set'
require_relative '../masking'
require_relative '../pre_process/math_span_detector'
require_relative 'code_language_guesser'

module VivlioStarter
  module CLI
    module Lint
      # 言語名のないフェンスを集め、推定にかけてよいものを選ぶ
      module CodeLanguageDetector
        # 推定の候補にできる言語。Guesslang が見分けられて、Prism が色分けできるもの
        # （仕様 §4.3）。候補を明示が無いときの既定値でもある。
        SUPPORTED_LANGUAGES = %w[html css javascript typescript ruby python c cpp java go
                                 rust json yaml sql bash markdown].freeze

        # 原稿の言語名の別名を、SUPPORTED_LANGUAGES の名前へそろえる
        LANGUAGE_ALIASES = {
          'js' => 'javascript', 'ts' => 'typescript', 'rb' => 'ruby', 'py' => 'python',
          'sh' => 'bash', 'zsh' => 'bash', 'shell' => 'bash', 'yml' => 'yaml',
          'md' => 'markdown', 'c++' => 'cpp', 'rs' => 'rust'
        }.freeze

        # 端末の記録（`$ ` の行とその出力）。Guesslang にかけずにこの言語名を付ける（仕様 §3.6）。
        # Prism の shell-session は `$ ` の行だけをコマンドとして色分けし、出力の行はそのまま残す。
        SHELL_SESSION = 'shell-session'
        SHELL_PROMPT = /\A\s*[$%] \S/

        # この囲みの中は、言語名が無くても推定しない（実行結果・端末の転写・テキストの図）
        EXEMPT_CONTAINERS = %w[output terminal diagram].freeze
        CONTAINER_OPEN = /\A\s*:{3,}\s*\{?\s*\.?([\w-]+)/
        CONTAINER_CLOSE = /\A\s*:{3,}\s*\z/

        # ソースコードの取り込み（```include:パス``` と、閉じを次の行に書く形）。
        # Masking のフェンスの判定は `include:` の開始行をフェンスと見ないので、そのままだと
        # 次の行の閉じ ``` を新しいフェンスの開始と読み、以後の組がずれる（仕様 §8.10）。
        INCLUDE_BLOCK = /^[ \t]*```include:([^\s`:]+)[^\n`]*(?:```[ \t]*$|\n[ \t]*```[ \t]*$)/

        # 除外のしるし（仕様 §3.5）。1 つでもあればコードではないとみなす。
        NOT_CODE = /
          ^\s*(?:`{3}|~{3}|:{3})   # 入れ子のフェンス・囲み（記法の説明）
          | [└├│←→⇒↑【】]          # ディレクトリの木・出力の矢印・見出しの括弧
          | [🔴🟡💡✅📄🔍]           # ログの絵文字
          | ^\s*\[[\w:. -]+\]\s    # [pdf:read] のようなログの接頭辞
          | error\[E\d+\]          # コンパイラのエラー出力
        /x

        # 文字列とコメント。除外のしるしは、この外だけで探す。本物のコードにも
        # `printf("【使い方】\n")` や `// ↑` のように同じ字が現れる（仕様 §8.8）。
        # `#` は後ろに空白があるときだけコメントとみなす（盤面の `#S**#` を消さないため）。
        LITERALS = %r{"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'|//[^\n]*|/\*.*?\*/|(?:^|(?<=\s))\#\s[^\n]*}m

        # 行頭が日本語の行（地の文）。コメントは `#`・`//` で始まるので数えられない。
        JAPANESE_LINE = /\A\s*[^\x00-\x7F]/

        # Guesslang の推定をそのまま知らせる確信度。0.3 以上なら、本書と練習帳の実行結果・
        # 木・盤面に 1 件も言語が付かなかった（仕様 §1.5）。0.1〜0.3 は誤りが多い。
        MIN_CONFIDENCE = 0.3

        # Ruby のしるし。Ruby にしか現れない書き方に絞る（仕様 §8.7）。
        # `.map`・`.reduce`（JavaScript にもある）、`.sum`（Rust）、`:name`（CSS の `a:hover`）、
        # `@name`（CSS の `@media`）は、他の言語と紛れるので入れない。
        RUBY_MARKERS = /
          ^\s*(?:puts|require|require_relative)\s
          | \bdo\s*\|[^|]*\| | \{\s*\|[^|]*\|                  # ブロック引数
          | ^\s*end\s*$                                      # end だけの行（def … end を含む）
          | \#\s*=>                                          # 結果を書き添える #=>
          | \.(?:each|each_with_index|each_with_object|each_slice|each_cons|times|upto|downto|
                 sort_by|min_by|max_by|tally|select|reject)\b
          | \#\{                                             # 文字列の式展開
          | \b(?:unless|elsif)\b
          | \battr_(?:reader|accessor|writer)\b | Data\.define | %[wi][(\[{]
          | \.\w+[?!](?=[\s)(,]|$)                           # ? や ! で終わるメソッド
        /x

        # 言語のしるし。Guesslang の推定がこの言語と一致すれば、確信度が低くても知らせる。
        #
        # 数行のコードは、Guesslang の確信度が 0.3 に届かない（`let x = …` や `console.log(x)` は
        # Kotlin・Swift・Dart にも似た形があり、54 言語に確信度が薄く割り振られる）。
        # 一方、候補の中の 1 位なら当たっていることが多い。独立した二つの手がかりが一致したときに
        # 限れば、確信度を問わなくても本書と練習帳の実行結果に言語が付かなかった
        # （ai_web_starter で知らせる数は 107 → 254。仕様 §8.5）。
        # しるしは手がかりが 1 言語だけに当たったときに使う。
        LANGUAGE_HINTS = {
          'html' => lambda { |body, lines|
            lines.first.lstrip.start_with?('<') &&
              body.match?(%r{</[a-zA-Z][\w-]*>|<!DOCTYPE|<(?:link|meta|img|input|br|hr)\b[^>]*>}i)
          },
          # 「プロパティ: 値;」は行頭か `{` の直後から探す（1 行で書いたルール `p { color: blue; }` も拾う）。
          # 値は改行をまたいでよい（`linear-gradient(…)` を複数行に書く）。C の `default:`・`case …:` と
          # C++ の `public:` などは、次の行の文までを 1 つの宣言と見てしまうので除く。
          # `@import "…"` だけのファイルも CSS とする
          'css' => lambda { |body, _lines|
            rule = body.match?(/^[^{}\n]*\{\s*(?:$|[\w-]+\s*:)/) &&
                   body.match?(/(?:^[ \t]*|\{[ \t]*)(?!(?:default|case|public|private|protected)\b)[\w-]+[ \t]*:[^;{}]+;/) &&
                   body.count('{') == body.count('}')
            rule || body.match?(/^\s*@import\s+(?:url\()?["']/)
          },
          # alert・constructor・`class 名前 {` は入門書の短い例に多い（`alert("こんにちは")` の 2 行など）。
          # `class 名前 {` は Java・C# にもあるが、Guesslang の推定との一致を条件にするので区別できる
          'javascript' => lambda { |body, _lines|
            body.match?(/\b(?:const|let|var)\s+\w+\s*=|\bfunction\s*\w*\s*\(|=>\s*[{(\w]|console\.log|
                         document\.\w|addEventListener|\$\(["']|\balert\(|\bconstructor\s*\(|
                         ^\s*class\s+\w+(?:\s+extends\s+\w+)?\s*\{/x)
          },
          'ruby' => ->(body, _lines) { body.match?(RUBY_MARKERS) },
          'python' => ->(body, _lines) { body.match?(/^\s*def \w+\(.*\):\s*$|^\s*(?:import \w+|from \w+ import )/) },
          # C は標準ライブラリで見分ける。`#include` と `int main(` は C++ にもある。
          # printf の前に `.` があるものは Java の System.out.printf なので除く。
          # （x フラグの正規表現では # がコメントになるので \# と書く）
          'c' => lambda { |body, _lines|
            body.match?(/\#include\s*<(?:stdio|stdlib|string|math|time|ctype|stdbool|limits)\.h>|
                         (?<![.\w])(?:printf|scanf|fgets|malloc)\s*\(/x)
          },
          'cpp' => ->(body, _lines) { body.match?(/#include\s*<(?:iostream|vector|string|map)>|\bstd::|\bcout\s*<</) },
          'java' => lambda { |body, _lines|
            body.match?(/\bpublic\s+static\s+void\s+main\b|System\.(?:out|err)\.print|^\s*import\s+java\./)
          },
          'json' => lambda do |body, _lines|
            body.lstrip.start_with?('{', '[') && JSON.parse(body)
          rescue JSON::ParserError
            false
          end
        }.freeze

        # 言語名のないフェンス 1 つ。line は開始行の行番号（1 始まり）。
        BareFence = Data.define(:line, :body)

        # 1 章の走査結果。languages は著者が明示している言語（SUPPORTED_LANGUAGES の名前）。
        Scan = Data.define(:bare_fences, :languages)

        # 言語名を付けるよう知らせるフェンス 1 つ
        # certainty は :estimated（〜と推定。--fix で書き込む）か :suggested（〜らしい。著者への提案だけ）。
        Finding = Data.define(:line, :language, :certainty) do
          def suggested? = certainty == :suggested
        end

        # 検査の結果。unguessed は、二段目の推定器が使えずに推定を見送ったフェンスの数
        # （0 でなければ、推定器を入れるよう案内する）。
        Result = Data.define(:findings, :unguessed)

        module_function

        # 章ごとに、言語名を付けるよう知らせるフェンスを求める。
        # 二段目への依頼は全章ぶんをまとめて 1 回で渡す（推定器の起動が 1 回で済む）。
        # @param texts_by_path [Hash{String => String}] 検査する章の本文
        # @param book_languages [Set<String>] 本全体で明示されている言語（候補の戻り先）
        # @param guesser [CodeLanguageGuesser, nil] 二段目の推定器（テストでは差し替える）
        # @return [Result] findings は { パス => [Finding]（行の昇順） }
        def findings(texts_by_path, book_languages:, guesser:)
          # --- Phase: 一段目で分ける ---
          found = Hash.new { |hash, key| hash[key] = [] }
          pending = {}
          texts_by_path.each do |path, text|
            chapter = scan(text)
            chapter.bare_fences.each do |fence|
              case classify(fence.body)
              in :skip then next
              in :guess
                # 言語のしるしが示す言語は、本のどこかで著者が書いている言語なら候補に加える。
                # 章の言語が css だけでも、JavaScript のしるしがあるコードを JavaScript と見分けられる
                # ように（一致は二段目の推定で確かめる）。本で一度も書いていない言語は加えない——
                # Java の `var x = …` や Rust の `let x = …` も JavaScript のしるしに当たり、
                # 候補に加えると Guesslang が JavaScript を選ぶことがある（仕様 §8.6）。
                hint = language_hint(fence.body)
                extra = [hint].compact & book_languages.to_a
                choices = (candidates(chapter.languages, book_languages) | extra).sort
                request = CodeLanguageGuesser::Request.new(id: pending.size, body: fence.body, candidates: choices)
                pending[request.id] = [path, fence.line, request, hint]
              in String => language
                found[path] << Finding.new(line: fence.line, language:, certainty: :estimated)
              end
            end
          end

          # --- Phase: 二段目で言語を見分ける ---
          unguessed = 0
          if pending.any?
            if guesser&.available?
              guesses = guesser.guess(pending.values.map { it[2] })
              pending.each do |id, (path, line, request, hint)|
                finding = judge(guesses[id], hint, request.candidates, book_languages)
                found[path] << finding.with(line:) if finding
              end
            else
              unguessed = pending.size
            end
          end

          Result.new(findings: found.transform_values { it.sort_by(&:line) }.to_h, unguessed:)
        end

        # 本全体で明示されている言語
        # @param texts [Enumerable<String>] 全章の本文
        # @return [Set<String>]
        def book_languages(texts) = texts.map { scan(it).languages }.reduce(Set.new, :|)

        # 章の本文から、言語名のないフェンスと、明示されている言語を集める。
        # 最上位のフェンスだけを見る（記法の説明として入れ子になったものは本物のコードではない）。
        # @param text [String]
        # @return [Scan]
        def scan(text)
          # 取り込みのブロックは、行数を保ったまま空行にしてから走査する。拡張子の言語
          # （star1/greeting.c なら c）は、著者が明示した言語として数える
          included = Set.new
          text = text.gsub(INCLUDE_BLOCK) do |block|
            language = normalize_language(File.extname(::Regexp.last_match(1)).delete('.'))
            included << language if language
            "\n" * block.count("\n")
          end

          blocks = []
          Masking.replace_top_level_fences(text) do |block, lineno|
            blocks << [lineno, block]
            nil
          end
          containers = containers_at(text, blocks)

          bare = []
          languages = Set.new
          blocks.each do |lineno, block|
            opener, *rest = block.lines
            next if opener.lstrip.start_with?('>') # 引用の中のフェンスは本文が `> ` 付きで推定できない

            info = opener.strip.sub(Masking::FENCE, '').strip
            if info.empty?
              next if containers[lineno].any? { EXEMPT_CONTAINERS.include?(it) }

              bare << BareFence.new(line: lineno, body: rest[0...-1].join)
            else
              language = normalize_language(info)
              languages << language if language
            end
          end
          Scan.new(bare_fences: bare, languages: languages | included)
        end

        # フェンスの本文を分ける。
        # @return [:skip, String, :guess] 推定しない / 付ける言語名（shell-session）/ 二段目へ回す
        def classify(body)
          lines = body.lines.map(&:chomp).reject { it.strip.empty? }
          return :skip if lines.empty?
          # 端末の記録は出力の行にログの接頭辞などを含むので、除外のしるしより先に見る
          return SHELL_SESSION if lines.first.match?(SHELL_PROMPT)
          return :skip if body.gsub(LITERALS, '').match?(NOT_CODE)
          return :skip if lines.count { it.match?(JAPANESE_LINE) } * 3 > lines.size
          return :skip if PreProcessCommands::MathSpanDetector.display_math("```\n#{body}```\n")

          :guess
        end

        # 1 つのフェンスについて、知らせ方を決める（仕様 §8.9）。
        #   〜と推定（:estimated）: 確信度が十分か、しるしと一致した。--fix で書き込む
        #   〜らしい（:suggested）: しるしはあるが確かめきれない（Guesslang が一致しない・短くて判定しない）。
        #                           しるしの言語を本のどこかで著者が書いているときだけ。著者への提案にとどめる
        # しるしの無いものは、確信度が低ければ知らせない（シェルのコマンドを Ruby と見るなど誤りが多い）。
        # 行数では絞らない。短くても、しるしがあれば当たっていた（仕様 §8.9）。
        # @return [Finding, nil] line は呼び出し側が入れる
        def judge(guess, hint, candidates, book_languages)
          guess = adjust_language(guess, hint, candidates) if guess
          return Finding.new(line: nil, language: guess.language, certainty: :estimated) if guess && report?(guess, hint)
          return nil unless hint && book_languages.include?(hint)

          Finding.new(line: nil, language: hint, certainty: :suggested)
        end

        # Guesslang の推定を知らせるか。確信度が十分か、言語のしるしと一致したとき。
        # 食い違うときに確信度が高くても退ける案は採らない。Rust の `let x = …` は JavaScript の
        # しるしに当たるので、正しく Rust と推定したものまで退けてしまう（仕様 §8.8）。
        def report?(guess, hint) = guess.confidence >= MIN_CONFIDENCE || guess.language == hint

        # その言語にしか現れないしるし。これが当たれば、Guesslang の推定より、しるしの言語を採る。
        # Guesslang は C や Java を C++ と取り違えやすい（仕様 §8.8）。JavaScript・Ruby などの
        # しるしは他の言語にも似た形があるので含めない（Rust の `let x = …` は JavaScript のしるしに当たる）。
        DECISIVE_HINTS = %w[c cpp java].freeze

        # 推定した言語を、決め手になるしるしがあればその言語に読み替える。
        # 候補に入っていない言語には読み替えない（候補は著者の明示から決めている）。
        def adjust_language(guess, hint, candidates)
          return guess unless DECISIVE_HINTS.include?(hint) && candidates.include?(hint)

          guess.with(language: hint)
        end

        # 言語のしるし（LANGUAGE_HINTS）が 1 言語だけに当たれば、その言語。
        # HTML は <script>・<style> の中身で JavaScript・CSS にも当たるので、HTML を優先する。
        # @return [String, nil]
        #
        # しるしはコメントを除いてから探す。コメントには別の言語の書き方が入りやすい
        # （C のコメントの `// length => 13` が JavaScript の `=>` に、`{|}` が Ruby のブロック引数に
        # 当たった。仕様 §8.8）。文字列は残す（Ruby の `"#{name}"` は手がかりになる）。
        def language_hint(body)
          code = body.gsub(LITERALS) { |literal| literal.start_with?('"', "'") ? literal : '' }
          lines = code.lines.map(&:chomp).reject { it.strip.empty? }
          return nil if lines.empty?

          hits = LANGUAGE_HINTS.select { |_language, rule| rule.call(code, lines) }.keys
          return 'html' if hits.include?('html')

          hits.one? ? hits.first : nil
        end

        # 推定の候補。同じ章 → 本全体 → 既定の順に、空でない最初のものを使う（仕様 §3.4）。
        # @param chapter_languages [Set<String>]
        # @param book_languages [Set<String>]
        # @return [Array<String>]
        def candidates(chapter_languages, book_languages)
          [chapter_languages, book_languages, SUPPORTED_LANGUAGES].find { !it.empty? }.to_a.sort
        end

        # 言語名のないフェンスの開始行へ言語名を書き込む（vs lint --fix）。
        # 開始行のフェンス記号・字下げはそのまま残し、言語名がすでにある行は書き換えない。
        # @param text [String]
        # @param languages_by_line [Hash{Integer => String}] 開始行の行番号 → 言語名
        # @return [String]
        def write_languages(text, languages_by_line)
          text.each_line.with_index(1).map do |line, lineno|
            language = languages_by_line[lineno]
            next line unless language

            line.sub(/\A(\s*(?:`{3,}|~{3,}))[ \t]*(?=\r?\n|\z)/) { "#{::Regexp.last_match(1)}#{language}" }
          end.join
        end

        # 原稿の言語名（`ruby:foo.rb`・`js {.small}` など）を SUPPORTED_LANGUAGES の名前にする。
        # 対象外の言語（text・mermaid・math など）は nil。
        def normalize_language(info)
          name = info[/\A[^\s:{]+/].to_s.downcase
          name = LANGUAGE_ALIASES.fetch(name, name)
          SUPPORTED_LANGUAGES.include?(name) ? name : nil
        end

        # 各フェンスの開始行で開いている囲みの名前（外側から順）。
        # フェンスの中の `:::` は囲みではないので、フェンスの行は数えない。
        def containers_at(text, blocks)
          ranges = blocks.to_h { |lineno, block| [lineno, lineno + block.lines.size - 1] }
          stack = []
          open_at = {}
          fence_end = 0
          text.each_line.with_index(1) do |line, lineno|
            if (last = ranges[lineno])
              open_at[lineno] = stack.dup
              fence_end = last
            elsif lineno > fence_end
              if line.match?(CONTAINER_CLOSE) then stack.pop
              elsif (match = line.match(CONTAINER_OPEN)) then stack << match[1]
              end
            end
          end
          open_at
        end
      end
    end
  end
end
