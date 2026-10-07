# frozen_string_literal: true

module VivlioStarter
  module PDF
    # タグの無い PDF の紙面から、見出し・段落・リスト・コード・表を推定して要素の木を組む
    # （pdf-read-structure-spec.md の経路 B・§4）。
    #
    # 組んだ木は経路 A と同じ StructureMarkdown が Markdown へ写す。語のあいだの空白・行番号・
    # 脚注・ページをまたぐ段落の扱いは、両経路で同じになる。ここで決めるのは「どの行が何の
    # かたまりか」だけである。
    #
    # 描いた順は読む順ではない（Chrome は囲みや見出しを本文の後に描く）。行は座標で並べ直す。
    class LayoutStructure
      MarkedContent = MarkedContentReceiver::MarkedContent

      # 1 行。文字は左から並ぶ。rubies は [親文字の文字, ルビの文字] の組
      Line = Data.define(:glyphs, :page, :x, :right, :baseline, :size, :text, :rubies) do
        def top = baseline + size
        def with_rubies(list) = with(rubies: list)
      end

      # 推定したかたまり。kind は :heading・:paragraph・:list_item・:code・:table・:image
      Block = Data.define(:kind, :lines, :top, :page, :data)

      # 箇条書きと番号付きリストの頭
      LIST_MARKER = /\A(?:[・•●○■□◆◇▪‣◦]|[-–*]|\d{1,3}[.．)）]|[(（]\d{1,3}[)）])/
      # 本文の 1.15 倍以上で、本文と違うフォント（太字・ゴシック）なら見出しの候補にする。
      # フォントが本文と同じなら 1.4 倍以上を求める（本のカードの書名のような、大きいだけの字を除く）
      HEADING_RATIO = 1.15
      PLAIN_HEADING_RATIO = 1.4
      # 表の列のあいだとみなす隙間（pt）。和文の両端揃えの字間は 2.5pt、欧文の空白は 3pt ほど
      COLUMN_GAP = 4.0
      # 数式に使うフォント
      MATH_FONT_NAME = /\ACM(?:MI|SY|EX)|Symbol|Math|MSAM|MSBM|rsfs|esint/i
      # OCR の字で、同じ段落とみなす字の大きさの差（大きいほうに対する割合）。97 章のスキャンで、段落の途中の
      # 切れ目が 139 から 53 に減った。15〜35% のどこでも文字の一致は変わらない
      OCR_SIZE_TOLERANCE = 0.25
      # 文末とみなす OCR の行末（wrapped_mid_sentence?）
      OCR_SENTENCE_END = /[。．.!?！？」』）):：]\z/
      # 目次の項目の行末。点線のリーダー（. . . ・ ……）とページ番号で終わる
      TOC_ENTRY_END = /(?:[.．・…‥]\s*){3,}\d+\z/

      # @param pages [Array<MarkedContentReceiver>] ページごとに読み終えた受け手
      # @param text_area [Hash, nil] { top:, bottom:, inner:, outer: }（pt）。指定したときだけ版面の外を除く
      def initialize(pages, text_area: nil)
        @pages = pages
        @text_area = text_area
      end

      # @return [StructureReader::Element]
      def root
        page_lines = @pages.each_with_index.map { |page, index| build_lines(visible_glyphs(page, index) - figure_labels(page)) }
        all_lines = page_lines.flatten
        @body_size = dominant(all_lines.flat_map(&:glyphs).map { it.size.round(1) }) || 10.0
        @body_font = dominant(all_lines.flat_map(&:glyphs).select { (it.size - @body_size).abs < 0.2 }.map { it.font&.name })
        @pitch = line_pitch(page_lines)
        @right_edges = right_edges(page_lines)

        page_lines = drop_running_heads(drop_margin_labels(page_lines))
        blocks = page_lines.each_with_index.flat_map do |lines, index|
          place_images(page_blocks(attach_rubies(lines)), @pages[index].page_images)
        end
        element(:Document, elements(blocks))
      end

      private

      # --- Phase: 行を組む ---

      # text_area を指定したときだけ、版面の外の文字を除く（論点 6）。奇数ページは左が綴じ側
      def visible_glyphs(page, index)
        glyphs = drop_overprinted(page.page_glyphs.reject { it.text.strip.empty? || it.text.match?(/\A[[:cntrl:]]+\z/) })
        return glyphs unless @text_area

        width, height = page.page_size
        inner, outer = @text_area.values_at(:inner, :outer)
        left, right = index.even? ? [inner, width - outer] : [outer, width - inner]
        glyphs.select { it.x.between?(left, right) && it.y.between?(@text_area[:bottom], height - @text_area[:top]) }
      end

      # 擬似太字（同じ字を少しずらして 2 度描く）は 1 字にまとめる。そのままだと「2-2-2」が
      # 「22--22--22」になる
      # 2 度目は描く順が離れていることがあるので、字と高さで引いて比べる
      def drop_overprinted(glyphs)
        seen = Hash.new { |hash, key| hash[key] = [] }
        glyphs.reject do |glyph|
          row = glyph.y.round
          duplicate = (row - 1..row + 1).any? do |key|
            seen[[glyph.text, key]].any? { (it.x - glyph.x).abs < glyph.width * 0.3 && (it.y - glyph.y).abs < glyph.size * 0.1 }
          end
          seen[[glyph.text, row]] << glyph unless duplicate
          duplicate
        end
      end

      # 図の上に描かれた文字（図解の番号や注釈）は図の一部なので、本文から除く。ページを覆う画像
      # （背景・スキャン）の上の文字は本文として残す
      def figure_labels(page)
        width, height = page.page_size
        figures = page.page_images.select { (it.right - it.left) * (it.top - it.bottom) < width * height * 0.6 }
        return [] if figures.empty?

        page.page_glyphs.select do |glyph|
          center = glyph.x + (glyph.width / 2)
          figures.any? { center.between?(it.left, it.right) && glyph.y.between?(it.bottom, it.top) }
        end
      end

      # 上から順に、ベースラインがそろう文字を 1 行にまとめる。脚注の参照のような小さく持ち上がった
      # 字は、本文の字の半分の高さまでなら同じ行に入れる（ルビは高さが離れていて別の行になる）
      def build_lines(glyphs)
        rows = []
        glyphs.sort_by { [-it.y, it.x] }.each do |glyph|
          row = rows.last(2).find { |candidate| same_row?(candidate.max_by(&:size), glyph) }
          row ? row << glyph : rows << [glyph]
        end
        rows.map { make_line(it.sort_by(&:x)) }.sort_by { -it.baseline }
      end

      # ベースラインがそろうか、小さな字が大きな字の 0.6 倍以内に持ち上がっている（上付きの番号）。
      # TeX の脚注の番号は本文の 0.45 倍ほど持ち上がる。ルビは 1 字ぶん以上離れているので入らない
      def same_row?(base, glyph)
        return true if (base.y - glyph.y).abs <= [base.size, glyph.size].min * 0.5

        small, large = [base, glyph].sort_by(&:size)
        rise = small.y - large.y
        small.size < large.size * 0.9 && rise.positive? && rise <= large.size * 0.6
      end

      def make_line(glyphs, rubies: [])
        base = glyphs.max_by(&:size)
        size = dominant(glyphs.map { it.size.round(1) })
        Line.new(glyphs:, page: glyphs.first.page, x: glyphs.first.x, right: glyphs.map(&:right).max,
                 baseline: glyphs.select { (it.size.round(1) - size).abs < 0.05 }.map(&:y).min || base.y,
                 size:, text: glyphs.map(&:text).join, rubies:)
      end

      # 本文の行のすぐ上の小さな字の行はルビ。親文字（ルビの範囲に中心が入る字）に結び付ける
      def attach_rubies(lines)
        rubies = {}
        lines.each_with_index do |line, index|
          below = lines[index + 1]
          next unless below && ruby_line?(line, below)

          groups = line.glyphs.chunk_while { |a, b| b.x - a.right < line.size * 0.8 }
          rubies[index + 1] = Array(rubies[index + 1]) + groups.filter_map do |ruby|
            base = below.glyphs.select { (it.x + it.right) / 2 >= ruby.first.x - 1 && (it.x + it.right) / 2 <= ruby.last.right + 1 }
            [base, ruby] unless base.empty?
          end
          rubies[index] = :ruby
        end
        lines.each_with_index.filter_map do |line, index|
          next if rubies[index] == :ruby

          rubies[index] ? line.with_rubies(rubies[index]) : line
        end
      end

      # ルビは仮名で振る。英字の小さな飾り（見出しの上の「Section」）をルビにしないため
      def ruby_line?(line, below)
        line.text.match?(/\A[\p{Hiragana}\p{Katakana}ー・＝=\s]+\z/) &&
          line.size <= below.size * 0.65 && line.baseline - below.baseline <= below.size * 1.5 &&
          line.x >= below.x - below.size && line.right <= below.right + below.size
      end

      # --- Phase: 文書全体の手がかり ---

      # 柱とノンブル。ページの最上行・最下行で、次の行から大きく離れ、同じ高さに同じ文字列（数字は
      # 無視）が何ページも出る行を落とす。数字だけの行（ノンブル）は文字列が違っても落とす
      def drop_running_heads(page_lines)
        candidates = page_lines.flat_map { margin_lines(it) }
        repeats = candidates.group_by { [it.baseline.round, normalize_running(it.text)] }.transform_values(&:size)
        heights = candidates.group_by { it.baseline.round }.transform_values(&:size)
        needed = [2, (page_lines.count(&:any?) * 0.25).ceil].max

        page_lines.map do |lines|
          margins = margin_lines(lines)
          lines.reject do |line|
            next false unless margins.include?(line)

            key = line.baseline.round
            heights.fetch(key, 0) >= needed &&
              (line.text.match?(/\A[\divxlcdm\-–— ]+\z/i) || repeats[[key, normalize_running(line.text)]].to_i >= 2)
          end
        end
      end

      # 版面の左右の外に置いた柱・ノンブル・つめ（章の見出しを縦に並べた印）は、本文と同じ高さに
      # 並ぶと行に混ざる。版面の外にあり、数字だけか、同じ文字列が同じ位置に何ページも出るまとまりを落とす
      def drop_margin_labels(page_lines)
        columns = page_lines.each_with_index.map { |lines, page| body_column(lines, @pages[page].page_size.first) }
        segments = page_lines.each_with_index.flat_map do |lines, page|
          lines.flat_map { |line| outside_segments(line, columns[page]) }.map { [page, it] }
        end
        counts = segments.group_by { |_page, run| [(run.first.x / 10).round, normalize_running(run.map(&:text).join)] }
                         .transform_values { it.map(&:first).uniq.size }
        dropped = segments.select do |_page, run|
          text = run.map(&:text).join
          text.match?(/\A\d+\z/) || counts[[(run.first.x / 10).round, normalize_running(text)]] >= 2
        end.flat_map(&:last)
        return page_lines if dropped.empty?

        dropped = dropped.to_h { [it, true] }
        page_lines.map do |lines|
          lines.filter_map do |line|
            kept = line.glyphs.reject { dropped[it] }
            next line if kept.size == line.glyphs.size
            next nil if kept.empty?

            make_line(kept, rubies: line.rubies)
          end
        end
      end

      # 版面の左右。ページ幅の 4 割を超える本文の行で、いちばん多い行頭と行末の位置。幅で絞らないと、
      # 表やコードの多いページで表の行頭を版面の左と取り違える。最大で測ると、つめの混ざった行で右が伸びる
      def body_column(lines, page_width)
        wide = lines.select { body_sized?(it) && it.right - it.x > page_width * 0.4 }
        return nil if wide.empty?

        [dominant(wide.map { it.x.round }), dominant(wide.map { it.right.round })]
      end

      # 行のうち、1 字を超える隙間で区切ったまとまりが版面の外にあるもの（本文の字間が 1 字を超えることはまず無い）
      def outside_segments(line, column)
        return [] unless column

        left, right = column
        line.glyphs.chunk_while { |a, b| b.x - a.right <= line.size }.select do |run|
          # 等幅の字（コードの行番号）は落とさない
          !run.all?(&:mono?) && (run.map(&:right).max < left - line.size || run.first.x > right + line.size)
        end
      end

      def margin_lines(lines)
        return lines if lines.size <= 1

        top = lines.first.baseline - lines[1].baseline > @pitch * 1.8 ? [lines.first] : []
        bottom = lines[-2].baseline - lines.last.baseline > @pitch * 1.8 ? [lines.last] : []
        top + bottom
      end

      def normalize_running(text) = text.gsub(/\s+/, '').gsub(/\d+/, '#')

      # 本文の行送り。本文の大きさの行どうしの間隔の中央値
      def line_pitch(page_lines)
        steps = page_lines.flat_map do |lines|
          lines.select { body_sized?(it) }.each_cons(2).filter_map do |a, b|
            gap = a.baseline - b.baseline
            gap if gap.positive? && gap < a.size * 3
          end
        end.sort
        steps.empty? ? @body_size * 1.6 : steps[steps.size / 2]
      end

      # ページごとの本文の右端（本文の大きさの行の右端で、いちばん多い位置）
      def right_edges(page_lines)
        page_lines.each_with_index.to_h do |lines, page|
          [page, dominant(lines.select { body_sized?(it) }.map { it.right.round })]
        end.compact
      end

      # --- Phase: かたまりに分ける ---

      def page_blocks(lines)
        @numbered_neighbors ||= {}
        @numbered_neighbors[lines.first&.page] = lines
        blocks = []
        index = 0
        while index < lines.size
          line = lines[index]
          kind, length = if code_line?(line) then [:code, run_length(lines, index) { code_line?(it) }]
                         elsif heading_candidate?(line) then heading_or_paragraph(lines, index)
                         elsif list_start?(line) then [:list_item, list_item_length(lines, index)]
                         elsif (rows = table_length(lines, index)).positive? then [:table, rows]
                         else [:paragraph, paragraph_length(lines, index)]
                         end
          blocks << block(kind, lines[index, length])
          index += length
        end
        attach_code_captions(blocks)
      end

      def block(kind, lines, data = nil)
        Block.new(kind:, lines:, top: lines.first.top, page: lines.first.page, data:)
      end

      # 条件を満たす行が、行送りの 2.5 倍より離れずに続く数
      def run_length(lines, start)
        length = 1
        length += 1 while (following = lines[start + length]) && yield(following) &&
                          lines[start + length - 1].baseline - following.baseline <= following.size * 2.5
        length
      end

      # 見出しの候補が 3 行以内で終われば見出し。4 行以上続くなら、大きな字の段落（章のリードなど）
      def heading_or_paragraph(lines, start)
        length = 1
        length += 1 while (following = lines[start + length]) && heading_candidate?(following) &&
                          lines[start + length - 1].baseline - following.baseline <= [following.size, lines[start].size].max * 2.2
        length <= 3 ? [:heading, length] : [:paragraph, paragraph_length(lines, start, large: true)]
      end

      def heading_candidate?(line)
        ratio = line.size / @body_size
        return false if ratio < HEADING_RATIO || line.text.match?(/[。．]\z/)

        ratio >= PLAIN_HEADING_RATIO || line.glyphs.count(&:bold?) * 2 > line.glyphs.size ||
          dominant(line.glyphs.map { it.font&.name }) != @body_font
      end

      # 段落は、次のどれかで切る: 字の大きさが変わる・行間が空く・前の行が版面の右まで届かずに終わる・
      # 次の行の頭が下がる・次の行がリストやコードや見出しになる
      # large は、見出しの候補が 4 行以上続いた大きな字の段落。見出しの候補でも切らない
      def paragraph_length(lines, start, large: false)
        length = 1
        while (following = lines[start + length])
          break if paragraph_break?(lines[start, length], following, lines[start + length + 1, 2].to_a, large:)

          length += 1
        end
        length
      end

      # paragraph はここまでの段落の行、ahead は次の行の先の 2 行
      def paragraph_break?(paragraph, following, ahead, large: false)
        previous = paragraph.last
        # 目次の項目は、リーダーが版面の右端まで届くので、下の右端の比べ方では次の項目とつながる
        return true if previous.text.match?(TOC_ENTRY_END)
        return true if code_line?(following) || (!large && heading_candidate?(following)) || list_start?(following)
        wide_gap = previous.baseline - following.baseline > following.size * (@pitch / @body_size) * 1.35
        return footnote_start?(following) || wide_gap if wrapped_mid_sentence?(previous)
        return true if (previous.size - following.size).abs > size_tolerance(previous, following) || footnote_start?(following)
        return true if wide_gap

        # 右端と左端は、この段落の行と次の行で測る。左端には、次の行と右端がそろい、左へ 1.5 字以内に
        # ある先の行（字下げした 1 行目の続き）も使う。先の段落の幅の広い行（囲みの外・画像の下）まで
        # 含めると、狭い段落が 1 行ずつ切れる
        size = following.size
        right = (paragraph + [following]).map(&:right).max
        return true if previous.right < right - (size * 2)
        # 次の行も短い（中央に置いた引用・ファイル名）と上の比べ方では切れないので、文末で終わり
        # ページの本文の右端より手前で止まった行の後でも切る
        return true if previous.text.match?(/[。．.!?！？」』]\z/) && previous.right < @right_edges.fetch(previous.page, right) - (size * 2)

        column = paragraph + [following] + ahead.select { (it.right - following.right).abs <= 1 && it.x >= following.x - (size * 1.5) }
        following.x - column.map(&:x).min > size * 0.5
      end

      # 文の途中で折り返した OCR の行か。版面の右端まで届き、文末（「。」や閉じ括弧）で終わらない行は、
      # 次の行と同じ段落とみなし、字の大きさ・右端・字下げの比べ方では切らない。OCR の行は字の大きさも
      # 行頭の位置も揺れるので、それらの比べ方だけでは「1903年に結婚／します。」のように切れた。
      # 右端まで届くことを求めるのは、文末で終わらない題・札・コードの行（短い）を巻き込まないため。
      # 文字の層のある PDF の字には当てない
      def wrapped_mid_sentence?(line)
        line.glyphs.first.font.nil? && !line.text.match?(OCR_SENTENCE_END) &&
          line.right >= @right_edges.fetch(line.page, line.right) - line.size
      end

      # 段落を切る字の大きさの差。文字の層のある PDF では字の大きさが正確なので 0.5pt。OCR の字（書体の
      # 情報が無い）は、行の和文の字の幅から大きさを見積もるので、仮名の多い行は小さく出て、同じ段落の
      # 行どうしでも 1〜2pt 揺れる（「乗客／にとっては」が 7.8pt と 6.2pt）。OCR の字では 25% まで許す
      def size_tolerance(previous, following)
        return 0.5 if previous.glyphs.first.font

        [previous.size, following.size].max * OCR_SIZE_TOLERANCE
      end

      # 脚注の本文の頭。本文より小さい字の行が、持ち上げた番号（TeX の「¹本テキストの…」）か
      # 「1.」で始まる。同じページの脚注が 1 つの段落につながらないよう、この行の前で切る
      def footnote_start?(line)
        return false if line.size >= @body_size * 0.92

        digits = line.glyphs.take_while { it.text.match?(/\A\d\z/) }
        following = line.glyphs[digits.size]
        return false if digits.empty? || digits.size > 3 || following.nil?

        digits.last.y - following.y >= following.size * 0.15 || following.text.match?(/\A[.．)）]\z/)
      end

      # リストの頭（・や 1.）のあとに少し隙間がある行。本文より小さい字（脚注の「1.」）は除く
      def list_start?(line)
        return false if line.size < @body_size * 0.92
        return true if dot_before?(line)

        marker = list_marker_glyphs(line)
        following = line.glyphs[marker.size]
        !marker.empty? && following && (marker.last.text.match?(/[・•●○■□◆◇▪‣◦]/) || following.x - marker.last.right >= line.size * 0.2)
      end

      # 行の頭の左に、箇条書きの点（小さな塗りつぶしの図形）があるか
      def dot_before?(line)
        @pages[line.page].page_dots.any? do |dot|
          center = (dot.bottom + dot.top) / 2
          dot.right <= line.x + 0.5 && line.x - dot.right <= line.size * 2.5 &&
            center.between?(line.baseline - (line.size * 0.2), line.baseline + (line.size * 0.8))
        end
      end

      def list_marker_glyphs(line)
        text = line.text[LIST_MARKER].to_s
        count = 0
        glyphs = line.glyphs.take_while { (count += it.text.length) <= text.length }
        glyphs.map(&:text).join == text ? glyphs : []
      end

      # 項目の続きの行は、頭の記号の後ろの文字の位置にそろう
      def list_item_length(lines, start)
        text_x = lines[start].glyphs[list_marker_glyphs(lines[start]).size].x
        length = 1
        while (following = lines[start + length])
          previous = lines[start + length - 1]
          break if list_start?(following) || code_line?(following) || heading_candidate?(following)
          break if (following.x - text_x).abs > following.size * 0.6 || (previous.size - following.size).abs > 0.5
          # 版面の右端より手前で止まった行で、項目は終わる
          break if previous.right < @right_edges.fetch(previous.page, previous.right) - (following.size * 2)
          break if previous.baseline - following.baseline > following.size * (@pitch / @body_size) * 1.35

          length += 1
        end
        length
      end

      # 等幅の字が 9 割を占める行はコード。行内のコードが多い本文の行（8 割台）と分ける。
      # 書体の分からない行（OCR）は、行頭の番号が前後の行と 1 ずつ続くこと（コードの行番号）で見る
      def code_line?(line)
        visible = line.glyphs.reject { it.text.tr("\u00A0", ' ').strip.empty? }
        return false if visible.empty?
        return numbered_code_line?(line) if visible.none?(&:font)

        visible.count(&:mono?) >= visible.size * 0.9
      end

      def numbered_code_line?(line)
        number = line_number(line)
        return false unless number

        lines = @numbered_neighbors.fetch(line.page, [])
        index = lines.index(line)
        index && [lines[index - 1], lines[index + 1]].compact.any? { (line_number(it).to_i - number).abs == 1 } &&
          (index.positive? || lines.size > 1)
      end

      # 行頭の数字のあとに 0.5 字以上の隙間がある行の、その数字
      def line_number(line)
        digits = line.glyphs.take_while { it.text.match?(/\A\d\z/) }
        following = line.glyphs[digits.size]
        return nil if digits.empty? || digits.size > 4 || (following && following.x - digits.last.right < line.size * 0.5)

        digits.map(&:text).join.to_i
      end

      # コードの直前のファイル名だけの 1 行は、コードのキャプションにする
      def attach_code_captions(blocks)
        blocks.each_with_index.filter_map do |current, index|
          following = blocks[index + 1]
          if caption_for?(current, following)
            nil
          elsif current.kind == :code && index.positive? && caption_for?(blocks[index - 1], current)
            current.with(data: blocks[index - 1].lines.first)
          else
            current
          end
        end
      end

      def caption_for?(candidate, code)
        candidate.kind == :paragraph && code&.kind == :code && candidate.lines.size == 1 &&
          candidate.lines.first.text.match?(/\A[\w.\-\/]+\.\w+\z/) &&
          candidate.lines.first.baseline - code.lines.first.baseline <= code.lines.first.size * 3
      end

      # --- Phase: 表 ---

      # 列のあいだの縦の隙間が 3 行以上そろって続けば表（§7.2）。隙間は 1 字ずつの位置で探す
      def table_length(lines, start)
        length = 0
        (start...lines.size).each do |stop|
          window = lines[start..stop]
          # 表の行は字の 1.1 倍以上空く。分数を含む数式（分子と分母が詰まって並ぶ）を表にしないため
          break unless table_row?(window.last) &&
                       (stop == start || (window[-2].baseline - window.last.baseline).between?(window.last.size * 1.1, window.last.size * 3))
          break if column_gaps(window).empty?

          length = window.size
        end
        length >= 3 ? length : 0
      end

      # 目次の項目は、ページ番号の前の隙間が縦にそろうが、表にはしない
      def table_row?(line)
        !code_line?(line) && !list_start?(line) && !heading_candidate?(line) && !math_line?(line) && !line.text.match?(TOC_ENTRY_END) &&
          (line.size - @body_size).abs <= @body_size * 0.15 && segments(line).size >= 2
      end

      # 数式のフォント（TeX の CMMI・CMSY など）の字が 3 割を超える行
      def math_line?(line)
        line.glyphs.count { it.font&.name.to_s.match?(MATH_FONT_NAME) } > line.glyphs.size * 0.3
      end

      # 行の文字を、COLUMN_GAP より広い隙間で区切ったまとまり（[左端, 右端]）
      def segments(line)
        line.glyphs.chunk_while { |a, b| b.x - a.right < COLUMN_GAP }.map { [it.first.x, it.map(&:right).max] }
      end

      # どの行にも文字が無い縦の隙間。各行が 2 列以上に分かれていることも求める
      def column_gaps(window)
        spans = window.flat_map { segments(it) }.sort
        merged = spans.each_with_object([]) do |(left, right), acc|
          acc.last && left <= acc.last[1] + 0.5 ? acc.last[1] = [acc.last[1], right].max : acc << [left, right]
        end
        gaps = merged.each_cons(2).filter_map { |a, b| [a[1], b[0]] if b[0] - a[1] >= COLUMN_GAP }
        # 中央揃えの見出しの行だけが作る隙間は、列の境目ではない。半分以上の行を左右に分ける隙間に限る
        gaps.select! do |gap|
          window.count { |line| line.glyphs.any? { it.right <= gap[0] + 0.5 } && line.glyphs.any? { it.x >= gap[1] - 0.5 } } * 2 >= window.size
        end
        return [] if gaps.empty?

        window.all? { |line| columns_of(line, gaps).count(&:any?) >= 2 } ? gaps : []
      end

      def columns_of(line, gaps)
        bounds = gaps.map { (it[0] + it[1]) / 2 }
        line.glyphs.group_by { |glyph| bounds.count { glyph.x > it } }.then do |groups|
          Array.new(bounds.size + 1) { groups.fetch(it, []) }
        end
      end

      # --- Phase: 画像 ---

      # 画像は、描かれた上端の高さで読む順に差し込む
      def place_images(blocks, images)
        return blocks if images.empty?

        image_blocks = images.map do |box|
          Block.new(kind: :image, lines: [], top: box.top, page: box.page, data: box)
        end
        (blocks + image_blocks).sort_by.with_index { |item, order| [-item.top, order] }
      end

      # --- Phase: 要素の木にする ---

      def elements(blocks)
        levels = heading_levels(blocks.select { it.kind == :heading })
        blocks.chunk_while { |a, b| a.kind == :list_item && b.kind == :list_item }.map do |group|
          group.first.kind == :list_item ? list_element(group) : block_element(group.first, levels)
        end
      end

      def block_element(block, levels)
        case block.kind
        in :heading then element(:"H#{levels.fetch(heading_size(block))}", heading_children(block.lines))
        in :paragraph then element(:P, inline_children(block.lines))
        in :code then code_element(block)
        in :table then table_element(block)
        in :image then element(:Figure, [MarkedContent.new(glyphs: [], images: [block.data])])
        end
      end

      # StructureReader は本ファイルを読み込んでから定義されるので、要素の型は使うときに引く
      def element(type, children) = StructureReader::Element.new(type:, children:, alt: nil, actual_text: nil)

      # 見出しの大きさを大きい順に並べ、10% 以内の差は同じ段階にまとめて # から振る。OCR では字の大きさが
      # 行ごとに揺れるので、細かく分けると段階が増えすぎる（文字の層のある PDF の段階は 3 割以上離れている）
      #
      # 見出しが 1 つしかない段階は、いちばん上（章題）を除いてすぐ下の段階にまとめる。図の中の字を
      # 読んだ OCR の大きな字が段階を作り、本物の節や項を下へ押し下げるため
      def heading_levels(headings)
        all_sizes = headings.map { heading_size(it) }
        classes = all_sizes.uniq.sort.reverse.slice_when { |a, b| (a - b) > a * 0.1 }.to_a
        counts = classes.map { |group| all_sizes.count { group.include?(it) } }
        merged = classes.each_with_index.each_with_object([]) do |(group, index), acc|
          lonely = index.positive? && counts[index] == 1 && index < classes.size - 1
          lonely ? (classes[index + 1] = group + classes[index + 1]) : acc << group
        end
        merged.each_with_index.flat_map { |group, index| group.map { [it, [index + 1, 6].min] } }.to_h
      end

      # 見出しの大きさは、いちばん大きい字で見る。番号（A-12）と題の字数が同じだと、多い方の大きさが揺れる
      def heading_size(block) = block.lines.flat_map(&:glyphs).map { it.size.round(1) }.max

      # 見出しの横に添えた番号（「A-13」）は、題より上に来ても先に読む
      def heading_children(lines)
        labels, titles = lines.partition { |line| lines.any? { it != line && line.right <= it.x } }
        inline_children(labels + titles)
      end

      # 1 行のコードも囲みにするため、いつも Figure で包む（P の外の 1 行の Code は行内のコードとして写される）
      def code_element(block)
        code = element(:Code, [MarkedContent.new(glyphs: block.lines.flat_map(&:glyphs), images: [])])
        caption = block.data && element(:Caption, [MarkedContent.new(glyphs: block.data.glyphs, images: [])])
        element(:Figure, [caption, code].compact)
      end

      def list_element(items)
        element(:L, items.map do |item|
          marker = list_marker_glyphs(item.lines.first)
          first = item.lines.first
          rest = first.with(glyphs: first.glyphs.drop(marker.size))
          element(:LI, [element(:Lbl, [MarkedContent.new(glyphs: marker, images: [])]),
                        *inline_children([rest, *item.lines.drop(1)])])
        end)
      end

      # 推定した表は :InferredTable にする。写すときに、確かめるよう促すコメントを添える
      def table_element(block)
        gaps = column_gaps(block.lines)
        rows = block.lines.map do |line|
          cell_type = line.glyphs.all?(&:bold?) ? :TH : :TD
          element(:TR, columns_of(line, gaps).map { element(cell_type, inline_children([it])) })
        end
        element(:InferredTable, rows)
      end

      # 行の文字を、行内のコード（等幅）・強調（太字）・ルビに分ける。2 行以上の段落がまるごと
      # 太字なら、強調ではなく段落の書体（リード文など）とみなして印を付けない
      def inline_children(lines)
        lines = lines.filter_map { it.is_a?(Line) ? it : (make_line(it) unless it.empty?) }
        glyphs = lines.flat_map(&:glyphs)
        return [] if glyphs.empty?

        whole_bold = lines.size >= 2 && glyphs.all?(&:bold?)
        bases = lines.flat_map(&:rubies).each_with_index.flat_map { |(base, _ruby), index| base.map { [it, index] } }.to_h
        rubies = lines.flat_map(&:rubies)

        glyphs.chunk { |glyph| inline_style(glyph, bases, whole_bold) }.map do |style, run|
          content = MarkedContent.new(glyphs: run, images: [])
          case style
          in [:ruby, index] then element(:Ruby, [content, element(:RT, [MarkedContent.new(glyphs: rubies[index].last, images: [])])])
          # 等幅の連なりでも英数字を含まないもの（上付きの「⁵」を等幅の書体で補ったものなど）はコードにしない
          in :mono then run.any? { it.text.match?(/[\x21-\x7E]/) } ? element(:Code, [content]) : content
          in :bold then element(:Strong, [content])
          in :plain then content
          end
        end
      end

      def inline_style(glyph, bases, whole_bold)
        return [:ruby, bases[glyph]] if bases.key?(glyph)
        return :mono if glyph.mono?
        return :bold if glyph.bold? && !whole_bold

        :plain
      end

      def body_sized?(line) = (line.size - @body_size).abs < 0.2

      def dominant(values) = values.compact.tally.max_by { |_value, count| count }&.first
    end
  end
end
