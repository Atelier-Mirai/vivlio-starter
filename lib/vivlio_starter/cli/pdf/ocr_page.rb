# frozen_string_literal: true

require_relative 'marked_content_receiver'
require_relative 'structure_markdown'

module VivlioStarter
  module PDF
    # OCR で読んだ 1 ページ。プラグイン（vivlio-starter-pdf）が返す語を 1 字ずつの文字に割り、
    # 紙面の推定（経路 B・LayoutStructure）が文字の層のあるページと同じように読める形にする
    # （pdf-read-structure-spec.md §6）。
    #
    # 語のあいだの空白は文字の隙間から戻すので、OCR が和文の字のあいだに入れる空白も、
    # 文字の層のある PDF と同じ規則で詰まる。
    class OcrPage
      Glyph = MarkedContentReceiver::Glyph
      ImageBox = MarkedContentReceiver::ImageBox

      # 確信度（0〜100）がこれ未満の語は捨てる。図や罫線の模様を字と読んだものがほとんどで、
      # 本文の語はまず下回らない
      MIN_CONFIDENCE = 20

      attr_reader :page_glyphs, :page_images, :page_size

      # @param words [Array<Hash>] プラグインの page_words の 1 ページ分（text・x・y・width・size・conf）
      # @param page [Integer] 0 から数えたページの番号
      # @param size [Array(Float, Float)] ページの幅と高さ（pt）
      # @param images [Array<ImageBox>] このページから抜き出した画像の位置
      def initialize(words, page:, size:, images: [])
        kept = words.reject { it['text'].to_s.strip.empty? || it['conf'].to_f < MIN_CONFIDENCE }
        @page_glyphs = kept.group_by { [it['y'].to_f.round(1), it['size'].to_f.round(1)] }.values.flat_map { line_glyphs(it, page) }
        @page_images = images
        @page_size = size
      end

      # OCR のページには、箇条書きの点や否定の線（図形）の手がかりが無い
      def page_dots = []
      def page_rules = []

      private

      # 1 行の語を字に割る。語の幅は字数で等しく割る（OCR は字ごとの位置を返さない）。
      # 語の枠は重なることがあり、そのまま左から並べ直すと「言葉の遅い」が「言の遅葉い」になるので、
      # OCR が返した順を保つよう、前の字の右端より左へは戻さない。
      # 押し出した字が語の枠の右端を越えたら、行を枠の範囲へ縮めて並べ直す。Tesseract は語の枠を横に
      # 大きく取ることがあり（「重い」2 字に 70pt）、後ろの字が 47pt 右へ押し出されて、行の右の図の枠に
      # 入って消えた
      def line_glyphs(words, page)
        size = line_size(words)
        cursor = -Float::INFINITY
        glyphs = words.flat_map do |word|
          chars = word['text'].to_s.grapheme_clusters
          width = word['width'].to_f / chars.size
          start = [word['x'].to_f, cursor].max
          chars.each_with_index.map do |char, index|
            Glyph.new(text: char, x: start + (index * width), y: word['y'].to_f, width:, size:, page:).tap { cursor = it.right }
          end
        end
        widen_wide_glyphs(fit_line(glyphs, words.map { it['x'].to_f + it['width'].to_f }.max), size)
      end

      # 全角の字を、字の大きさいっぱいの幅に広げる。Tesseract の語の枠は字の形にぴったりで、
      # 「、」「。」「」」や小さな仮名の前後に 4〜8pt の隙間ができる。升目に並ぶ和文ではその隙間が
      # 縦にそろい、本文を表の列と取り違えた（97 章のスキャンで誤った表 6 つ）。字の間では余計な
      # 空白にもなった（「経過 した と き」）。広げるのは隣も全角の字である側だけにする（英字との
      # あいだの空白「が Ruby を」を残す）。左端は前の字の左端を越えない（行の字は左端の順に
      # 並べ直されるので、越えると「キログラム」が「ロキグラム」になった）
      def widen_wide_glyphs(glyphs, size)
        wide = glyphs.map { it.text.match?(StructureMarkdown::WIDE_CHAR) }
        previous_x = -Float::INFINITY
        glyphs.each_with_index.map do |glyph, index|
          extra = size - glyph.width
          widened = if wide[index] && extra.positive?
                      left = index.positive? && wide[index - 1] ? extra / 2 : 0.0
                      right = wide[index + 1] ? extra / 2 : 0.0
                      x = [glyph.x - left, previous_x + 0.01].max
                      glyph.with(x:, width: glyph.right + right - x)
                    else
                      glyph
                    end
          widened.tap { previous_x = it.x }
        end
      end

      # 字の並びを、行の左端から right までに縮める（はみ出していなければそのまま）
      def fit_line(glyphs, right)
        left = glyphs.first.x
        scale = (right - left) / (glyphs.last.right - left)
        return glyphs if scale >= 1.0 || !scale.positive?

        glyphs.map { it.with(x: left + ((it.x - left) * scale), width: it.width * scale) }
      end

      # 字の大きさ。行の枠の高さは括弧・ルビ・下に伸びる字で揺れるので、和文の字（ほぼ正方形）の
      # 幅の中央値で見積もる。和文が 3 字に満たない行は、枠の高さの 8 割とする
      def line_size(words)
        widths = words.flat_map do |word|
          chars = word['text'].to_s.grapheme_clusters
          wide = chars.all? { it.match?(StructureMarkdown::WIDE_CHAR) }
          wide ? Array.new(chars.size, word['width'].to_f / chars.size) : []
        end.sort
        widths.size >= 3 ? widths[widths.size / 2] : words.first['size'].to_f * 0.8
      end
    end

  end
end
