# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/index/context_snippet.rb
# ================================================================
# 責務:
#   レビューファイルに添える「語の使われ方」の抜粋を、原稿から 1 つ作る。
#
# なぜ文を単位にするか:
#   以前は語の前後 40 字を文字数で切り出していたため、抜粋が次の文の 1 字目
#   （「…自動化します。こ」）や記法（`::: ```b`）で終わり、語の途中から始まった。
#   抜粋は採否を決めるための材料なので、**語を含む 1 文**を記法を外して見せる。
#   文が長いときだけ、語の前後を読点・空白の位置で詰め、詰めた側に「…」を付ける。
#
#   候補の抽出（IndexCandidateExtractor）と登録語の確認（UnifiedIndexManager）の
#   両方がここを通す。経路ごとに切り方が違うと、同じ語でも節によって抜粋の質が変わる。
# ================================================================

require_relative '../masking'
require_relative 'term_pattern'

module VivlioStarter
  module CLI
    module IndexCommands
      # 語を含む 1 文の抜粋
      module ContextSnippet
        # 文の終わり
        SENTENCE_END = /(?<=[。！？])/

        # 長い文を詰めるときの切れ目（読点・空白・かっこ）
        BREAK = /[、，\s「」（）]/

        # 切れ目を探す範囲（詰めた端からこの字数まで）
        BREAK_SEARCH = 15

        ELLIPSIS = '…'

        # 行の種類ごとの優先順。本文の文 → 表の行 → 見出し。見出しは語を並べただけ、
        # 表の行はセルの値の並びで、どちらも語の使われ方が分かりにくい
        LINE_KINDS = %i[body table heading].freeze

        module_function

        # @param content [String] 章の原稿（Markdown）
        # @param term [String] 用語
        # @param width [Integer] 長い文を詰めるとき、語の前後に残す字数の目安
        # @return [String] 抜粋（地の文に語が無ければ空文字）
        def around(content, term, width:)
          # 語の境目を見て照合する（「LaTeX」の文を「TeX」の抜粋にしない）
          pattern = TermPattern.bounded(term)
          sentence = sentence_with(content, term, pattern)
          return '' unless sentence

          shorten(sentence, term, sentence.index(pattern), width)
        end

        # 語を含む最初の文（本文に無ければ表の行、それも無ければ見出し）
        def sentence_with(content, term, pattern)
          found = {}
          Masking.each_prose_line(content) do |line, _lineno|
            next unless line.include?(term)

            text = plain_text(line)
            next unless text.match?(pattern)

            kind = line_kind(line)
            if kind == :body
              sentence = text.split(SENTENCE_END).find { it.match?(pattern) }
              return (sentence || text).strip
            end
            found[kind] ||= text
          end
          found.values_at(*LINE_KINDS).compact.first
        end

        def line_kind(line)
          case line
          when /\A\#{1,6}\s/ then :heading
          when /\A\s*\|/ then :table
          else :body
          end
        end

        # Markdown の 1 行から、読むのに要らない記法を外す
        def plain_text(line)
          return '' if line.match?(/\A\s*(?::::|<!--|\|?\s*:?-{3,})/) # 囲みの区切り・コメント・表の区切り行

          text = line.gsub(/<!--.*?-->/, '')
          text.gsub!('\|', '|')                               # 表の中でエスケープした縦棒（ルビの記法など）
          text.gsub!(/!\[[^\]]*\]\([^)]*\)/, '')              # 画像
          text.gsub!(/\[([^\]|]+)\|[^\]]*\]/, '\1')           # 索引の記法 [語|よみ]
          text.gsub!(/\{([^}|]+)\|[^}]*\}/, '\1')             # ルビの記法 {語|よみ}
          text.gsub!(/\[([^\]]+)\]\([^)]*\)/, '\1')           # リンク
          text.gsub!(/\[([^\]]+)\]/, '\1')                    # 読みなしの索引記法 [語]
          text.gsub!(/\{[^}]*\}/, '')                         # 属性 {.class} {width=50%}
          text.gsub!(/<[^>]+>/, '')                           # HTML タグ
          text.gsub!(/(?<![\w.])@[\w:.-]+/, '')               # 相互参照のラベル
          text.gsub!(/\*\*|__|`/, '')                         # 強調・インラインコードの記号
          text.sub!(/\A\s*(?:\#{1,6}|>|[-*+]|\d+[.)])\s+/, '') # 見出し・引用・箇条の記号
          text = table_cells(text) if text.lstrip.start_with?('|')
          text.gsub(/\s+/, ' ').strip
        end

        # 表の行を「セル | セル」の形にする（行頭・行末の縦棒を外す）
        def table_cells(text)
          text.strip.delete_prefix('|').delete_suffix('|').split('|').map(&:strip).reject(&:empty?).join(' | ')
        end

        # 長い文を、語の前後 width 字ほどに詰める
        def shorten(sentence, term, index, width)
          return sentence if sentence.length <= (width * 2) + term.length

          from = cut_start(sentence, [index - width, 0].max, index)
          to = cut_end(sentence, [index + term.length + width, sentence.length].min, index + term.length)

          head = from.positive? ? ELLIPSIS : ''
          tail = to < sentence.length ? ELLIPSIS : ''
          "#{head}#{sentence[from...to].strip}#{tail}"
        end

        # 詰める頭の位置。目安の位置から後ろへ切れ目を探し、その直後から始める
        def cut_start(sentence, from, limit)
          return 0 if from.zero?

          found = sentence[from...[from + BREAK_SEARCH, limit].min]&.index(BREAK)
          found ? from + found + 1 : from
        end

        # 詰める末尾の位置。目安の位置から前へ切れ目を探し、そこまでにする
        def cut_end(sentence, to, limit)
          return to if to >= sentence.length

          start = [to - BREAK_SEARCH, limit].max
          found = sentence[start...to].rindex(BREAK)
          found ? start + found : to
        end
      end
    end
  end
end
