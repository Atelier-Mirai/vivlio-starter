# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/math_letter_wrapper.rb
# ================================================================
# 責務:
#   地の文に直接書いた数学用英数字（`𝔽`・`𝒜`・`𝐯`）と、数学で使う文字様記号（`ℝ`・`ℕ`・`ℓ`）を
#   `$…$` で包み、数式として組む（改善案 #130）。
#
# なぜ要るのか:
#   これらの字は本の書体にも HackGen にも無く（DejaVu も 996 字中 180 字だけ）、地の文に書くと
#   組む PC の書体で代わりに組まれ、Type 3 になる。数式の中なら MathJax が自分の書体で図形として
#   描くので、書体に左右されない。MathJax は Unicode の数学用英数字の意味を正しく読む
#   （`$𝔽$` は `$\mathbb{F}$`、`$𝒜$` は `$\mathscr{A}$` と同じ形になることを確かめた）ので、
#   `\mathbb{…}` に書き換える対応表は要らない。包むだけでよい。
#
# 包まない字:
#   MathJax の書体に無い字（MATHJAX_MISSING・308 字）は、包んでも図形にならない（数式の画像の中に
#   字のまま残る）。手書き風の小文字 `𝒶`・太字の手書き風 `𝓐`・黒板太字の小文字 `𝕜`・太字の
#   ギリシャ小文字 `𝛂`・黒板太字の数字 `𝟙` など。これらは字のまま残し、PDF では Gaiji が
#   字の形を取って組む（STIX Two Math は 308 字をすべて持つ）。
#
# どこを包まないか:
#   コード・数式・HTML のタグ・リンクの行き先と画像の代替テキスト・索引の印・振り仮名・URL・
#   フロントマターと、`$` が残っている行（金額の `$100` と組み合わさると、数式の切れ目がずれる）。
#
# 上付き・下付き:
#   すぐ後ろの上付き・下付きの字（`𝔽ₙ`・`ℝ²`）も同じ数式に含める。PlainMathTranspiler が
#   `_{n}`・`^{2}` に起こす。
# ================================================================

require_relative '../masking'
require_relative '../math_delimiters'
require_relative 'plain_math_transpiler'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # 地の文の数学用英数字を `$…$` で包む
      module MathLetterWrapper
        # 数学用英数字（U+1D400〜）と、数学で使う文字様記号（ℂ ℊ-ℓ ℕ ℘-ℝ ℤ ℨ ℬ ℭ ℯ-ℱ ℳ ℴ ℼ-ℿ ⅅ-ⅉ）
        MATH_LETTER = /[\u{1D400}-\u{1D7FF}ℂℊ-ℓℕ℘-ℝℤℨℬℭℯ-ℱℳℴℼ-ℿⅅ-ⅉ]/

        # MathJax（mathjax-full の TeX の書体）が描けない字。2026-10-30 に、数学用英数字の全字と
        # 上の文字様記号を 1 字ずつ `$…$` で組み、SVG に字（<text>）が残ったものを集めた
        MATHJAX_MISSING = /[ℊℯℴℼ-ℿⅅ-ⅉ\u{1D4B6}-\u{1D4B9}\u{1D4BB}\u{1D4BD}-\u{1D4C3}\u{1D4C5}-\u{1D503}\u{1D552}-\u{1D56B}\u{1D63C}-\u{1D66F}\u{1D6A4}\u{1D6A5}\u{1D6B9}\u{1D6C2}-\u{1D6E1}\u{1D6F3}\u{1D6FB}\u{1D72D}\u{1D735}\u{1D767}\u{1D76F}-\u{1D7CB}\u{1D7D8}-\u{1D7E1}]/

        DRAWABLE = /(?!#{MATHJAX_MISSING})#{MATH_LETTER}/
        SCRIPTS = Regexp.union(PlainMathTranspiler::SUPERSCRIPT_CHARS, PlainMathTranspiler::SUBSCRIPT_CHARS)
        RUN = /#{DRAWABLE}(?:#{DRAWABLE}|#{SCRIPTS})*/

        # 包まない所（長さを問わず退避して戻す）
        UNTOUCHABLE = [
          /\A---\r?\n.*?^---\r?\n/m,        # フロントマター
          *MathDelimiters::ALL,
          /<[^>\n]*>/,                       # HTML のタグ
          /!\[[^\]\n]*\]\([^()\n]*\)/,      # 画像（代替テキストと行き先）
          /\]\([^()\n]*\)/,                  # リンク・画像の行き先
          /\[[^\[\]\n]*\|[^\[\]\n]*\]/,      # 索引の印 [語|読み]
          /\{[^{}\n]*\}/,                    # 属性・振り仮名
          Masking::URL
        ].freeze

        STASH = "\u0000"

        module_function

        # @param content [String] 原稿
        # @return [String] 包んだ原稿（包むものが無ければ content そのもの）
        def wrap(content)
          return content unless content.match?(DRAWABLE)

          # --- Phase: コードと、包まない所を退避する ---
          masked, spans = Masking.protect_code(content)
          stash = []
          UNTOUCHABLE.each do |pattern|
            masked = masked.gsub(pattern) { stash << it; "#{STASH}#{stash.size - 1}#{STASH}" }
          end

          # --- Phase: 行ごとに包む（<svg> の中と、`$` の残る行は除く） ---
          in_svg = false
          wrapped = masked.each_line.map do |line|
            in_svg = true if line.include?('<svg') || stash_svg_open?(line, stash)
            if in_svg
              in_svg = false if line.include?('</svg>') || stash_svg_close?(line, stash)
              next line
            end
            line.include?('$') ? line : line.gsub(RUN) { "$#{it}$" }
          end.join

          # --- Phase: 戻す ---
          restored = wrapped.gsub(/#{STASH}(\d+)#{STASH}/) { stash[::Regexp.last_match(1).to_i] }
          Masking.restore_code(restored, spans)
        end

        # 退避した HTML のタグに <svg> の開き・閉じがあるか（原稿に直に書いた図）
        def stash_svg_open?(line, stash) = stashed(line, stash).any? { it.start_with?('<svg') }
        def stash_svg_close?(line, stash) = stashed(line, stash).any? { it.start_with?('</svg') }

        def stashed(line, stash) = line.scan(/#{STASH}(\d+)#{STASH}/).flatten.map { stash[it.to_i] }
      end
    end
  end
end
