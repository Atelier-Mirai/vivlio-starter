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

require_relative '../masking'

module VivlioStarter
  module CLI
    module Metrics
      # 位置つきの 1 文。text と length はインラインコードを除いた本文（文字数・文末・漢字の判定に使う）、
      # display はインラインコードを残した文（抜粋として著者に見せる）。コードを除いたまま見せると
      # 「には の と同じ色名」のように語が抜けて、どの文か分からなくなる。
      LocatedSentence = Data.define(:chapter_num, :line, :text, :length, :display) do
        def initialize(chapter_num:, line:, text:, length:, display: text) = super
      end

      # 章本文から位置つきで文を収集する。
      class SentenceCollector
        # 文ではない構造行（見出し/表/HTMLコメント/コンテナ/画像/引用）。
        STRUCTURAL = /\A\s*(?:#|\||<!--|:::|!\[|>)/
        SENTENCE_END = /[。！？!?]+/
        # 文のバッファでインラインコードがあった位置の目印（私用領域の字なので原稿には現れない）。
        # コードの中身は文末の判定に混ぜず（`--fix!` の ! で文が切れないように）、文が確定したら戻す。
        CODE_MARK = "\u{E000}"

        # @return [Array<LocatedSentence>]
        def collect(content, chapter_num)
          @results = []
          @buffer = +''
          @codes = []
          @start_line = nil

          # コード（フェンス区切り行・内容行）とみなす行番号を Masking で判定する。
          # 行番号を保ったまま、可変長フェンス・入れ子・~~~ に一貫して追従する。
          code_lines = Masking.code_lines(content)

          content.each_line.with_index(1) do |raw, lineno|
            next if code_lines.include?(lineno)
            next if reset_on_boundary(raw)

            accumulate(raw, lineno, chapter_num)
          end

          @results
        end

        private

        # 段落境界（空行）や構造行で、未完の文バッファを破棄する。
        def reset_on_boundary(raw)
          return false unless raw.strip.empty? || raw.match?(STRUCTURAL)

          @buffer = +''
          @codes = []
          @start_line = nil
          true
        end

        # 1 行を取り込み、文末が現れた分だけ確定して結果へ積む。
        def accumulate(raw, lineno, chapter_num)
          codes = []
          text = clean_line(raw, codes)
          return if text.delete(CODE_MARK).strip.empty?

          @start_line ||= lineno
          @buffer << text << "\n"
          @codes.concat(codes)

          while (match = @buffer.match(SENTENCE_END))
            @results << build_sentence(chapter_num, @start_line, @buffer[0...match.end(0)])
            @buffer = @buffer[match.end(0)..]
            @start_line = @buffer.strip.empty? ? nil : lineno
          end
        end

        # バッファの目印は文の順に並ぶので、この文の目印の数だけコードを先頭から取り出して戻す。
        def build_sentence(chapter_num, line, raw_sentence)
          codes = @codes.shift(raw_sentence.count(CODE_MARK))
          text = squeeze(raw_sentence.gsub(CODE_MARK, ' '))
          display = squeeze(raw_sentence.gsub(CODE_MARK) { "`#{codes.shift}`" })
          LocatedSentence.new(chapter_num:, line:, text:, length: text.length, display:)
        end

        # 改行を除き、記法の除去で生じた空白の連続を 1 つに畳む。
        def squeeze(sentence) = sentence.delete("\r\n").gsub(/\s+/, ' ').strip

        # 行内 Markdown を除いて、文章としての長さに近づける。
        # インラインコードは目印に置き換え、中身は codes へ順に積む（抜粋で戻すため）。
        def clean_line(line, codes)
          line.gsub(/`([^`\n]*)`/) { codes << ::Regexp.last_match(1); CODE_MARK }
              .gsub(/!\[[^\]]*\]\(#{Masking::LINK_DESTINATION}\)/, ' ')   # 画像
              .gsub(/\[([^\]]+)\]\(#{Masking::LINK_DESTINATION}\)/, '\1') # リンク → テキスト
              .gsub(/\A\s*[-*+]\s+/, '')           # 箇条書きの行頭記号
              .gsub(/\A\s*\d+\.\s+/, '')           # 番号付きリストの行頭
              .gsub(/[*_~]/, '')                   # 強調記号
        end
      end
    end
  end
end
