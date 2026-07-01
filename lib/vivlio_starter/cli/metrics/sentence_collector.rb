# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/metrics/sentence_collector.rb
# ================================================================
# 責務:
#   章の本文から、文を「出現位置（行番号）つき」で収集する。
#
# 目的:
#   平均文長だけでは「どの文が長すぎるか」が分からない。最長の文を
#   位置つきで提示できるよう、行番号を保ったまま文を切り出す。
#   （メトリクス本体の prose 化は行情報を失うため、別途行単位で走査する）
#
# 方針:
#   - フェンスドコードブロックは中身ごと飛ばす
#   - 見出し・表・コメント・コンテナ・画像・引用などの構造行は文に含めない
#   - 文末（。！？!?）で区切り、文の開始行を記録する（文は複数行にまたがり得る）
# ================================================================

module VivlioStarter
  module CLI
    module Metrics
      # 位置つきの 1 文。length は改行を除いた文字数。
      LocatedSentence = Data.define(:chapter_num, :line, :text, :length)

      # 章本文から位置つきで文を収集する。
      class SentenceCollector
        FENCE = /\A\s*(`{3,}|~{3,})/
        # 文ではない構造行（見出し/表/HTMLコメント/コンテナ/画像/引用）。
        STRUCTURAL = /\A\s*(?:#|\||<!--|:::|!\[|>)/
        SENTENCE_END = /[。！？!?]+/

        # @return [Array<LocatedSentence>]
        def collect(content, chapter_num)
          @results = []
          @buffer = +''
          @start_line = nil
          @open_fence = nil

          content.each_line.with_index(1) do |raw, lineno|
            next if handle_fence(raw)
            next if reset_on_boundary(raw)

            accumulate(raw, lineno, chapter_num)
          end

          @results
        end

        private

        # フェンス行・フェンス内行を処理し、消費したら true を返す。
        def handle_fence(raw)
          marker = raw[FENCE, 1]
          if @open_fence
            @open_fence = nil if marker && closing_fence?(marker, @open_fence)
            true
          elsif marker
            @open_fence = marker
            true
          else
            false
          end
        end

        # 段落境界（空行）や構造行で、未完の文バッファを破棄する。
        def reset_on_boundary(raw)
          return false unless raw.strip.empty? || raw.match?(STRUCTURAL)

          @buffer = +''
          @start_line = nil
          true
        end

        # 1 行を取り込み、文末が現れた分だけ確定して結果へ積む。
        def accumulate(raw, lineno, chapter_num)
          text = clean_line(raw)
          return if text.strip.empty?

          @start_line ||= lineno
          @buffer << text << "\n"

          while (match = @buffer.match(SENTENCE_END))
            @results << build_sentence(chapter_num, @start_line, @buffer[0...match.end(0)])
            @buffer = @buffer[match.end(0)..]
            @start_line = @buffer.strip.empty? ? nil : lineno
          end
        end

        def build_sentence(chapter_num, line, raw_sentence)
          # インラインコード等の除去で生じた空白の連続を 1 つに畳んで読みやすくする。
          text = raw_sentence.delete("\r\n").gsub(/\s+/, ' ').strip
          LocatedSentence.new(chapter_num:, line:, text:, length: text.length)
        end

        # 行内 Markdown を除いて、文章としての長さに近づける。
        def clean_line(line)
          line.gsub(/`[^`\n]*`/, ' ')              # インラインコード
              .gsub(/!\[[^\]]*\]\([^)]*\)/, ' ')   # 画像
              .gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')  # リンク → テキスト
              .gsub(/\A\s*[-*+]\s+/, '')           # 箇条書きの行頭記号
              .gsub(/\A\s*\d+\.\s+/, '')           # 番号付きリストの行頭
              .gsub(/[*_~]/, '')                   # 強調記号
        end

        def closing_fence?(marker, opener) = marker[0] == opener[0] && marker.length >= opener.length
      end
    end
  end
end
