# frozen_string_literal: true

# ================================================================
# Module: TermPattern
# ----------------------------------------------------------------
# 責務:
#   辞書エントリ（`term` と任意の `pattern`）を照合用の Regexp にする、
#   索引まわりで**唯一の綴りの解釈**。
#
# なぜ 1 箇所へ集めるか:
#   同じ「スラッシュを剥がして Regexp にする」3 行が TermSpread と
#   IndexCandidateExtractor に重複しており、主要参照の候補算出
#   （MainReferenceSuggester）で 3 箇所目になった。剥がし方がずれると
#   「広さは数えるのに候補は出ない」という噛み合わない挙動になる。
#
# 綴りの約束:
#   辞書の `pattern` は `/\bRuby\b/` のようにスラッシュで囲む。ASCII 語だけ
#   `\b` が付く（UnifiedTermsManager#build_pattern）。この `\b` は Ruby の
#   語境界ではなく **ASCII の語境界** と読む（ascii_word_boundaries）ので、
#   `/\bRuby\b/` は「Rubyの話」にも当たる。
#
#   利用側（本文タグ付け・広さ計測・主要参照の候補）は全員このモジュールを
#   通すこと。ここだけ通さない経路があると、「索引には載るのに候補には出ない」
#   のような噛み合わない挙動になる。
# ================================================================

module VivlioStarter
  module CLI
    module IndexCommands
      # 辞書エントリ → 照合用 Regexp
      module TermPattern
        # 辞書の綴りにある前後の `\b` は、**ASCII の語境界**として読み替える。
        # 日本語は語構成文字に数えないので、和語がくっついた形でも語を拾える。
        ASCII_WORD_BEHIND = '(?<![A-Za-z0-9_])'
        ASCII_WORD_AHEAD = '(?![A-Za-z0-9_])'

        module_function

        # @param entry [Hash] 'term' と任意の 'pattern' を持つ辞書エントリ
        # @return [Regexp]
        def for(entry)
          raw = entry['pattern'].to_s
          return literal(entry) if raw.empty?

          body = raw.start_with?('/') && raw.end_with?('/') ? raw[1...-1] : raw
          Regexp.new(ascii_word_boundaries(body))
        rescue StandardError
          # 壊れた pattern で走査全体を止めない。完全一致へ落として先へ進む
          literal(entry)
        end

        # 前後の `\b` を ASCII 限定の先読み・後読みへ置き換える。
        #
        # Ruby の `\b` は日本語を語構成文字として扱うため、`/\bCMYK\b/` は
        # 「CMYK版」に当たらない（`/\w/` は「あ」に当たらないのに `\b` は当たる、
        # という食い違いがある）。英数字の前後へ空白を置く流儀の原稿でも
        # 「JPEG形式」「YAML形式」のような複合はどう書いても生じるため、方針では
        # 防げない——実測で本書の地の文でも 13 語・39 件を取りこぼしていた。
        # 索引は「その語がここに出てくる」ことを伝えるものなので、和語がくっついた
        # 形でも拾うのが正しい。`CMYK版` の中の `CMYK` を拾えば、読者は `CMYK` を
        # 引いてそのページへ辿り着ける。
        #
        # 英字どうしの食い込み（`MATTR` の中の `TTR`）は従来どおり弾く。
        # 辞書には読みやすさのため `\b` の綴りを残し、意味の解釈だけをここで与える
        # ——このモジュールが綴りの唯一の解釈元なので、既存の辞書を書き換えて回る
        # 必要はない。
        def ascii_word_boundaries(body)
          body.sub(/\A\\b/) { ASCII_WORD_BEHIND }.sub(/\\b\z/) { ASCII_WORD_AHEAD }
        end

        def literal(entry) = Regexp.new(Regexp.escape(entry['term'].to_s))

        # 語の一部とみなす字種（英数字・カタカナ）
        SAME_SCRIPT = [/[A-Za-z0-9]/, /[ァ-ヶー]/].freeze

        # 辞書に綴りのない語（抽出した候補）の照合用 Regexp。英字・カタカナの語は、
        # 同じ字種の語の一部として出る位置に当てない。部分一致だと「ファイ」（ギリシャ文字の
        # 表の 1 回）が「ファイル」の 287 回を、「TeX」（本文 3 回）が「LaTeX」の 21 回を
        # 自分の出現として数えていた（改善案 #99）。
        # @param term [String]
        # @return [Regexp]
        def bounded(term)
          head = SAME_SCRIPT.find { term[0].to_s.match?(it) }
          tail = SAME_SCRIPT.find { term[-1].to_s.match?(it) }
          Regexp.new("#{"(?<!#{head.source})" if head}#{Regexp.escape(term)}#{"(?!#{tail.source})" if tail}")
        end

        # 空白の有無だけを問う照合。語の中の空白と、英数字と和文の境目を `[ \t　]*` にする。
        # 英字どうし・和文どうしの間は問わない（「PD F」「組 版」は揺れではなく誤り）。
        # 問える位置が無い語（「PDF」「数式」）は nil。
        #
        # lint（index-term-spacing）と、綴りを直したときの原稿の書き換えが共有する。
        # 両者が別々に綴りを解釈すると、lint が指摘する箇所と書き換える箇所がずれる。
        # 前後の境目は ASCII_WORD_BEHIND / AHEAD と同じく `_` も語の一部に数える
        # ——コードを伏せた目印（`__VS_CODE_SPAN__0__`）の中に当てないため。
        # @param term [String]
        # @return [Regexp, nil]
        def spacing_insensitive(term)
          chars = term.to_s.strip.chars
          return nil if chars.empty?

          flexible = false
          body = chars.each_with_index.filter_map do |char, i|
            next if char.match?(/\s/)

            prev = chars[i - 1] if i.positive?
            gap = prev && (prev.match?(/\s/) || script_boundary?(chars[i - 2], char, prev))
            flexible ||= gap
            "#{'[ \t　]*' if gap}#{Regexp.escape(char)}"
          end.join
          return nil unless flexible

          head = ASCII_WORD_BEHIND if chars.first.match?(/[A-Za-z0-9]/)
          tail = ASCII_WORD_AHEAD if chars.last.match?(/[A-Za-z0-9]/)
          Regexp.new("#{head}#{body}#{tail}")
        end

        # 英数字と和文の境目か（prev が空白のときは、その前の文字と比べる）
        def script_boundary?(before_space, char, prev)
          left = prev.match?(/\s/) ? before_space : prev
          return false if left.nil?

          ascii = ->(c) { c.match?(/[A-Za-z0-9]/) }
          japanese = ->(c) { c.match?(/[\p{Han}\p{Hiragana}\p{Katakana}ー]/) }
          (ascii.(left) && japanese.(char)) || (japanese.(left) && ascii.(char))
        end
        private_class_method :script_boundary?
      end
    end
  end
end
