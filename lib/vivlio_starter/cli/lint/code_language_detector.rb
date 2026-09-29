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
# ================================================================

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

        # 除外のしるし（仕様 §3.5）。1 つでもあればコードではないとみなす。
        NOT_CODE = /
          ^\s*(?:`{3}|~{3}|:{3})   # 入れ子のフェンス・囲み（記法の説明）
          | [└├│←→⇒↑【】]          # ディレクトリの木・出力の矢印・見出しの括弧
          | [🔴🟡💡✅📄🔍]           # ログの絵文字
          | ^\s*\[[\w:. -]+\]\s    # [pdf:read] のようなログの接頭辞
          | error\[E\d+\]          # コンパイラのエラー出力
        /x

        # 行頭が日本語の行（地の文）。コメントは `#`・`//` で始まるので数えられない。
        JAPANESE_LINE = /\A\s*[^\x00-\x7F]/

        # 言語名のないフェンス 1 つ。line は開始行の行番号（1 始まり）。
        BareFence = Data.define(:line, :body)

        # 1 章の走査結果。languages は著者が明示している言語（SUPPORTED_LANGUAGES の名前）。
        Scan = Data.define(:bare_fences, :languages)

        # 言語名を付けるよう知らせるフェンス 1 つ
        Finding = Data.define(:line, :language)

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
                request = CodeLanguageGuesser::Request.new(id: pending.size, body: fence.body,
                                                           candidates: candidates(chapter.languages, book_languages))
                pending[request.id] = [path, fence.line, request]
              in String => language
                found[path] << Finding.new(line: fence.line, language:)
              end
            end
          end

          # --- Phase: 二段目で言語を見分ける ---
          unguessed = 0
          if pending.any?
            if guesser&.available?
              guesser.guess(pending.values.map(&:last)).each do |id, guess|
                path, line, = pending.fetch(id)
                found[path] << Finding.new(line:, language: guess.language)
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
          Scan.new(bare_fences: bare, languages: languages)
        end

        # フェンスの本文を分ける。
        # @return [:skip, String, :guess] 推定しない / 付ける言語名（shell-session）/ 二段目へ回す
        def classify(body)
          lines = body.lines.map(&:chomp).reject { it.strip.empty? }
          return :skip if lines.empty?
          # 端末の記録は出力の行にログの接頭辞などを含むので、除外のしるしより先に見る
          return SHELL_SESSION if lines.first.match?(SHELL_PROMPT)
          return :skip if body.match?(NOT_CODE)
          return :skip if lines.count { it.match?(JAPANESE_LINE) } * 3 > lines.size
          return :skip if PreProcessCommands::MathSpanDetector.display_math("```\n#{body}```\n")

          :guess
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
