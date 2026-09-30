# frozen_string_literal: true

require 'minitest/autorun'
require 'set'
require_relative '../../../../lib/vivlio_starter/cli/lint/code_language_detector'

module VivlioStarter
  module CLI
    module Lint
      # 言語名のないコードブロックの言語推定（code-language-detection-spec.md）の一段目と、
      # 二段目への依頼のまとめ方。二段目は差し替えて Node なしで走らせる。
      class CodeLanguageDetectorTest < Minitest::Test
        # 依頼を記録し、決めた言語を返す推定器
        class FakeGuesser
          attr_reader :requests

          def initialize(language: 'javascript', available: true)
            @language = language
            @available = available
            @requests = []
          end

          def available? = @available

          def guess(requests)
            @requests.concat(requests)
            requests.to_h { [it.id, CodeLanguageGuesser::Guess.new(language: @language, confidence: 0.9)] }
          end
        end

        def detector = CodeLanguageDetector

        # --- 走査 ------------------------------------------------------------

        def test_should_collect_bare_fences_and_explicit_languages
          text = <<~MD
            # 章

            ```ruby:hello.rb
            puts 1
            ```

            ```
            let a = 1
            ```

            ~~~js {.small}
            let b = 2
            ~~~

            ```text
            出力
            ```
          MD

          scan = detector.scan(text)

          assert_equal [7], scan.bare_fences.map(&:line)
          assert_equal "let a = 1\n", scan.bare_fences.first.body
          assert_equal Set['ruby', 'javascript'], scan.languages
        end

        def test_should_skip_fences_inside_output_terminal_and_diagram_boxes
          text = <<~MD
            :::{.output}
            ```
            let a = 1
            ```
            :::

            :::{.diagram}
            ```
            +---+
            ```
            :::

            ```
            let b = 2
            ```
          MD

          assert_equal [13], detector.scan(text).bare_fences.map(&:line)
        end

        def test_should_ignore_fences_nested_in_a_markdown_example
          text = <<~MD
            ````markdown
            ```
            let a = 1
            ```
            ````
          MD

          scan = detector.scan(text)

          assert_empty scan.bare_fences
          assert_equal Set['markdown'], scan.languages
        end

        # --- 一段目の分け方 ------------------------------------------------------

        def test_should_send_plain_code_to_the_second_stage
          assert_equal :guess, detector.classify("const a = 1\nconsole.log(a)\n")
          assert_equal :guess, detector.classify("# コメントは日本語でもよい\nputs 1\n")
        end

        def test_should_mark_terminal_transcripts_as_shell_session
          body = "$ vs pdf:read three-elements\n[pdf:read] PDF からテキストを抽出します\n"

          assert_equal 'shell-session', detector.classify(body)
          assert_equal 'shell-session', detector.classify("% ls -la\n")
        end

        def test_should_skip_trees_logs_boards_and_compiler_output
          not_code = {
            'ディレクトリの木' => "mybook/\n  contents/   ← 原稿\n",
            '木の罫線' => "lib/\n  └─ cli.rb\n",
            'ログの絵文字' => "🔴 05-references.md:123 - 雛形ファイルが見つかりません\n",
            'ログの接頭辞' => "[Step 11] PDF ブックマークを付与します…\n",
            '見出しの括弧' => "【最短経路】\n  #S**#\n",
            'コンパイラの出力' => "error[E0382]: borrow of moved value: `s1`\n",
            '入れ子のフェンス' => "**タイトル**\n\n```ruby\nputs 1\n```\n"
          }

          not_code.each { |name, body| assert_equal :skip, detector.classify(body), name }
        end

        def test_should_skip_prose_and_display_math
          prose = "このサイトのようなカード型のレイアウトを作りたいです。\n同じ見た目を CSS Grid で作れますか？\n"

          assert_equal :skip, detector.classify(prose)
          assert_equal :skip, detector.classify("E = mc²\n")
          assert_equal :skip, detector.classify("\n  \n")
        end

        # --- 候補の言語 --------------------------------------------------------

        def test_should_prefer_chapter_then_book_then_default_candidates
          assert_equal %w[ruby yaml], detector.candidates(Set['yaml', 'ruby'], Set['css'])
          assert_equal %w[css], detector.candidates(Set.new, Set['css'])
          assert_equal CodeLanguageDetector::SUPPORTED_LANGUAGES.sort, detector.candidates(Set.new, Set.new)
        end

        def test_should_normalize_aliases_and_drop_unsupported_languages
          assert_equal 'javascript', detector.normalize_language('js')
          assert_equal 'bash', detector.normalize_language('zsh:setup.sh')
          assert_equal 'ruby', detector.normalize_language('ruby:foo.rb#L5')
          assert_nil detector.normalize_language('text')
          assert_nil detector.normalize_language('mermaid')
        end

        # --- 結果のまとめ方 ------------------------------------------------------

        def test_should_batch_requests_with_chapter_candidates_and_map_results_back
          texts = {
            'contents/11-a.md' => "```ruby\nputs 1\n```\n\n```\nputs 2\nputs 3\n```\n",
            'contents/12-b.md' => "```\n$ vs build\n```\n\n```\nx = 1\ny = 2\n```\n"
          }
          guesser = FakeGuesser.new(language: 'ruby')

          result = detector.findings(texts, book_languages: Set['ruby', 'css'], guesser:)

          assert_equal [%w[ruby], %w[css ruby]], guesser.requests.map(&:candidates)
          assert_equal [[5, 'ruby']], result.findings['contents/11-a.md'].map { [it.line, it.language] }
          assert_equal [[1, 'shell-session'], [5, 'ruby']],
                       result.findings['contents/12-b.md'].map { [it.line, it.language] }
          assert_equal 0, result.unguessed
        end

        def test_should_not_let_comments_or_other_languages_mislead_the_hints
          # コメントの `=>`・`{|}` は、JavaScript・Ruby のしるしにしない
          c_with_comments = "#include <stdio.h>\n// length => 13\n// {|}\nint main(void) {\n  return 0;\n}\n"
          # switch の `default:` と次の行の文は、CSS の「プロパティ: 値;」ではない
          c_with_switch = "#include <stdio.h>\nint main(void) {\n  switch (n) {\n  default:\n    printf(\"x\");\n  }\n}\n"
          # Java の System.out.printf は、C の printf ではない
          java = "public static void main(String[] args) {\n  System.out.printf(\"%d\", n);\n}\n"

          assert_equal 'c', detector.language_hint(c_with_comments)
          assert_equal 'c', detector.language_hint(c_with_switch)
          assert_equal 'java', detector.language_hint(java)
        end

        def test_should_read_cpp_as_c_when_the_hint_says_c
          # Guesslang は C を C++ と取り違えやすい。stdio.h や printf があれば C とする
          texts = { 'contents/11-a.md' => "```\n#include <stdio.h>\n\nint main(void) {\n  printf(\"hi\");\n}\n```\n" }

          result = detector.findings(texts, book_languages: Set.new, guesser: FakeGuesser.new(language: 'cpp'))

          assert_equal ['c'], result.findings['contents/11-a.md'].map(&:language)
        end

        def test_should_look_for_not_code_marks_outside_strings_and_comments
          # 【】や ↑ は実行結果のしるしだが、本物のコードの文字列やコメントにも現れる
          code = "printf(\"【使い方】\\n\");\n// ここを入れ替える ↑\nint n = 0;\n"
          output = "【最短経路】\n  #S**#\n"

          assert_equal :guess, detector.classify(code)
          assert_equal :skip, detector.classify(output)
        end

        def test_should_report_low_confidence_guesses_only_when_the_hint_agrees
          texts = { 'contents/11-a.md' => "```\nlet height = 50\nconsole.log(height)\n```\n\n" \
                                          "```\nx = 1\ny = 2\nz = 3\nw = 4\n```\n" }
          # 確信度の低い推定（数行のコードでよく起きる）。しるしと一致したほうだけを知らせる
          low = FakeGuesser.new(language: 'javascript')
          def low.guess(requests)
            requests.to_h { [it.id, CodeLanguageGuesser::Guess.new(language: 'javascript', confidence: 0.03)] }
          end

          result = detector.findings(texts, book_languages: Set.new, guesser: low)

          assert_equal [[1, 'javascript']], result.findings['contents/11-a.md'].map { [it.line, it.language] }
        end

        def test_should_add_the_hint_language_only_when_the_book_uses_it
          # 章の言語は css だけ。JavaScript のしるしがあるコードに、本で JavaScript を書いていれば
          # 候補へ javascript を加える。書いていなければ加えない（Java の `var x = …` などの誤り防止）
          texts = { 'contents/11-a.md' => "```css\np { color: red; }\n```\n\n```\nalert(\"こんにちは\")\n```\n" }

          uses_js = FakeGuesser.new
          detector.findings(texts, book_languages: Set['css', 'javascript'], guesser: uses_js)
          no_js = FakeGuesser.new
          detector.findings(texts, book_languages: Set['css'], guesser: no_js)

          assert_equal [%w[css javascript]], uses_js.requests.map(&:candidates)
          assert_equal [%w[css]], no_js.requests.map(&:candidates)
        end

        def test_should_suggest_the_hint_language_when_the_guess_is_not_confirmed
          # しるしは JavaScript だが、Guesslang は低い確信度で css と答えた（短いコードでよく起きる）
          texts = { 'contents/11-a.md' => "```\nlet element = document.getElementById(\"css\")\n```\n" }
          other = FakeGuesser.new
          def other.guess(requests)
            requests.to_h { [it.id, CodeLanguageGuesser::Guess.new(language: 'css', confidence: 0.05)] }
          end

          result = detector.findings(texts, book_languages: Set['css', 'javascript'], guesser: other)

          found = result.findings['contents/11-a.md']
          assert_equal [['javascript', :suggested]], found.map { [it.language, it.certainty] }
        end

        def test_should_suggest_when_the_code_is_too_short_to_guess
          # Guesslang は 20 文字未満を判定しない（結果を返さない）
          texts = { 'contents/11-a.md' => "```\nalert(1)\n```\n" }
          silent = FakeGuesser.new
          def silent.guess(_requests) = {}

          result = detector.findings(texts, book_languages: Set['javascript'], guesser: silent)

          assert_equal [:suggested], result.findings['contents/11-a.md'].map(&:certainty)
        end

        def test_should_not_suggest_a_language_the_book_never_uses
          # Java の本の `var x = 1;` は JavaScript のしるしに当たるが、本で JavaScript を書いていない
          texts = { 'contents/11-a.md' => "```java\nint n;\n```\n\n```\nvar x = 1;\nx += 2;\n```\n" }
          silent = FakeGuesser.new
          def silent.guess(_requests) = {}

          result = detector.findings(texts, book_languages: Set['java'], guesser: silent)

          assert_empty result.findings
        end

        def test_should_find_ruby_only_by_ruby_specific_idioms
          ruby = [
            "scores.each do |score|\n  total += score\n",
            "Date.new(1955, 5, 5).jisx0301   #=> \"S30.05.05\"\n",
            "while n.positive?\n  bits << n % 2\n",
            "label = \"\#{name}さん\"\n",
            "(0...N).max_by { |i| wins[i] }\n"
          ]
          # 他の言語と紛れる書き方は Ruby のしるしにしない（CSS の a:hover、JavaScript の .map）
          not_ruby = ["a:hover {\n  color: red;\n}\n", "const doubled = items.map(x => x * 2)\n"]

          ruby.each { assert_equal 'ruby', detector.language_hint(it), it }
          not_ruby.each { refute_equal 'ruby', detector.language_hint(it), it }
        end

        def test_should_find_a_single_language_hint
          assert_equal 'javascript', detector.language_hint("let a = 1\nconsole.log(a)\n")
          assert_equal 'css', detector.language_hint(".box {\n  color: red;\n}\n")
          assert_equal 'ruby', detector.language_hint("def hello\n  puts 1\nend\n")
          assert_equal 'javascript', detector.language_hint("alert(\"こんにちは\")\n")
          assert_equal 'javascript', detector.language_hint("class Rectangle {\n  constructor(w, h) {\n  }\n}\n")
          assert_equal 'json', detector.language_hint(%({\n  "name": "x"\n}\n))
          # <script> の中の JavaScript にも当たるが、HTML を優先する
          assert_equal 'html', detector.language_hint("<script>\n  const a = 1\n</script>\n")
          assert_nil detector.language_hint("x = 1\ny = 2\n")
        end

        def test_should_count_unguessed_fences_when_the_guesser_is_missing
          texts = { 'contents/11-a.md' => "```\nlet a = 1\n```\n\n```\n$ vs build\n```\n" }

          result = detector.findings(texts, book_languages: Set.new, guesser: FakeGuesser.new(available: false))

          assert_equal 1, result.unguessed
          # 端末の記録は推定器が無くても言語名が決まる
          assert_equal ['shell-session'], result.findings['contents/11-a.md'].map(&:language)
        end

        def test_should_not_call_the_guesser_when_nothing_needs_guessing
          guesser = FakeGuesser.new
          texts = { 'contents/11-a.md' => "```\nmybook/\n  contents/  ← 原稿\n```\n" }

          result = detector.findings(texts, book_languages: Set.new, guesser:)

          assert_empty guesser.requests
          assert_empty result.findings
        end

        # --- 書き込み（--fix） ---------------------------------------------------

        def test_should_write_languages_only_into_bare_opening_lines
          text = "```\nlet a = 1\n```\n\n  ~~~~\nputs 1\n  ~~~~\n\n```ruby\nputs 2\n```\n"

          result = detector.write_languages(text, { 1 => 'javascript', 5 => 'ruby', 9 => 'css' })

          assert_equal "```javascript\nlet a = 1\n```\n\n  ~~~~ruby\nputs 1\n  ~~~~\n\n```ruby\nputs 2\n```\n", result
        end

        def test_should_count_explicit_languages_across_the_book
          texts = ["```ruby\nputs 1\n```\n", "```yml\na: 1\n```\n", "```text\nx\n```\n"]

          assert_equal Set['ruby', 'yaml'], detector.book_languages(texts)
        end
      end
    end
  end
end
