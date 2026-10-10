# frozen_string_literal: true

require_relative 'marked_content_receiver'

module VivlioStarter
  module PDF
    # 線で描いた図（回路図・関係図・矢印の図）の範囲を、ページに描いた図形から見つける（pdf-read-structure-spec.md §4.11）。
    #
    # 埋め込みの画像ではないので、プラグインは取り出せず、図の中のラベル（「S：ソース」「（a）」）だけが本文に
    # 散らばっていた。曲線か斜めの線を含む図形を種にし、近くの図形をつないだまとまりを図とする。表の罫線や
    # 囲みの枠は縦横の線と長方形だけなので種にならない。見つけた範囲は、埋め込みの画像と同じく図として扱う
    # （範囲の上の字は図のラベルとして本文から除き、Enhanced Mode では範囲を画像に描き出す）。
    module VectorFigures
      Box = MarkedContentReceiver::ImageBox

      # 図形どうしを同じ図とみなす距離（pt）。線と線のつなぎ目は接するか、わずかに離れる
      SHAPE_GAP = 8.0
      # 並べた図（「(a)」「(b)」の 2 つのトランジスタ）を 1 つの図にまとめる距離（pt）
      FIGURE_GAP = 20.0
      MIN_SHAPES = 5
      MIN_WIDTH = 40.0
      MIN_HEIGHT = 30.0
      # 囲みの枠とみなす、中に入る行の字数（コードの行は字数によらない）。枠は文やコードを囲み、図のラベルは短い
      CONTAINER_ROW = 12
      # 図にしない、範囲の中の行の字数・字の面積の割合・本文に対する字の大きさ
      TEXT_ROW = 25
      TEXT_RATIO = 0.15
      HEADING_SCALE = 1.5
      # 図のラベルの行の数の上限。これを超えるのは表（線で描いた字の表）
      LABEL_ROWS = 20
      # 図にしない、埋め込みの画像（画面写真）と重なる割合（over_image?）
      IMAGE_OVERLAP = 0.3
      CAPTION = /\A[図表]/
      SENTENCE_END = /[。．.!?！？」』]\z/
      # 2 段組みのページで、隣の段の本文の行と同じ高さに並んでもラベルとみなす字数（column_line?）
      SHORT_LABEL = 6

      module_function

      # @param receiver [MarkedContentReceiver] 読み終えたページ
      # @return [Array<MarkedContentReceiver::ImageBox>] 図の範囲（ラベルを含む）
      def find(receiver)
        width, height = receiver.page_size.map(&:to_f)
        glyphs = receiver.page_glyphs
        body_size = glyphs.map { it.size.round(1) }.tally.max_by(&:last)&.first || 10.0
        rows = text_rows(glyphs)

        # --- Phase: 図の部品になる図形（ページの枠・背景・文を囲む枠を除く） ---
        containers = rows.select { it.size >= CONTAINER_ROW || code_row?(it) }.map { row_box(it) }
        shapes = receiver.page_shapes.reject do |shape|
          shape.right - shape.left > width * 0.85 || (shape.right - shape.left) * (shape.top - shape.bottom) > width * height * 0.5 ||
            containers.any? { inside?(shape, it) }
        end

        # --- Phase: 近くの図形をつないだまとまりのうち、曲線か斜めの線を含むもの ---
        figures = shape_groups(shapes).filter_map do |members|
          next unless members.size >= MIN_SHAPES && members.any? { it.curved || it.diagonal }

          box = members.map { Box.new(page: it.page, left: it.left, bottom: it.bottom, right: it.right, top: it.top) }.reduce { merge(_1, _2) }
          box if box.right - box.left >= MIN_WIDTH && box.top - box.bottom >= MIN_HEIGHT
        end

        # --- Phase: 近くの短いラベルを含め、並べた図をまとめ、文や見出しを含むものを除く ---
        # ラベルは短い行。隙間で切った行の切れ端ではなく 1 行まるごとで見て、本文の行（body_line?）の切れ端はラベルにしない。式を線で描いた行は字数が減り、式の周りの空きで切れる。
        # 図の両側に置いたラベルの行は、間に図が挟まって空く。回して描いた字（版面の外のつめ）・キャプションもラベルにしない
        # 2 段組みでは、図のラベル（「U0」「si」）が隣の段の本文の行と同じ高さに並び、本文の行の字とみなされてラベルから外れる。
        # 2 段組みのページに限り、ページの真ん中をまたぐ隙間で行を分け、段の行らしい切れ端（column_line?）だけを本文の行の字とする
        # （1 段組みのページでは、式の空きが真ん中をまたぐ本文の行の切れ端がラベルになる）
        lines = text_lines(glyphs)
        two_columns = two_column_page?(lines, width)
        body_lines = lines.flat_map do |line|
          next [] unless body_line?(line, width)

          two_columns ? split_at_center(line, width).select { column_line?(it) } : [line]
        end
        long = body_lines.flatten.to_h { [it, true] }.compare_by_identity
        labels = rows.select do |row|
          row.size < TEXT_ROW && row.none? { long[it] || it.rotated } && row.first.size <= body_size * 1.3 && !row.map(&:text).join.match?(CAPTION)
        end
        rejection = ->(box) { over_image?(box, receiver.page_images) ? :image : text_rejection(box, glyphs, body_size) }
        labeled = merge_near(figures.map { with_labels(it, labels) }, FIGURE_GAP).filter_map { without_body_lines(it, body_lines) }
        # 2 段組みのページで、ラベルを入れて字が多くなりすぎただけの図（「the nearest reference vector」のような長いラベルを
        # 散らした図）は、ラベルを入れる前の範囲で確かめ直す。ラベルはその範囲の外で本文に残る。文・見出し・コードを含んで
        # 除いた図（コードと実行結果を矢印でつないだ組）は確かめ直さない（矢印だけが図になる）。1 段組みのページでは確かめ
        # 直さない（式を線で描いた本の記号の一覧表や、式の空きで切れた本文の行を含む範囲が図になる）
        labeled.flat_map do |box|
          case rejection.(box)
          in nil then [box]
          in :crowded if two_columns
            merge_near(figures.select { inside?(box, it) }, FIGURE_GAP).filter_map { without_body_lines(it, body_lines) }.select { rejection.(it).nil? }
          else []
          end
        end
      end

      # 図形を、SHAPE_GAP 以内で接するものどうしでつなぐ（左端の順に並べ、届く範囲だけを比べる）
      def shape_groups(shapes)
        sorted = shapes.sort_by(&:left)
        parents = Array.new(sorted.size) { it }
        root = ->(index) { parents[index] == index ? index : (parents[index] = root.(parents[index])) }
        sorted.each_with_index do |shape, index|
          ((index + 1)...sorted.size).each do |other|
            break if sorted[other].left > shape.right + SHAPE_GAP
            next unless near?(shape, sorted[other], SHAPE_GAP)

            parents[root.(other)] = root.(index)
          end
        end
        sorted.each_index.group_by { root.(it) }.values.map { |indexes| indexes.map { sorted[it] } }
      end

      # 図の近く（行の高さの 1.5 倍以内）にある短い行を、図の範囲に入れる。入れた行の近くの行も続けて入れる
      def with_labels(box, labels)
        loop do
          near = labels.map { row_box(it) }.select { near?(box, it, (it.top - it.bottom) * 1.5) && !inside?(box, it) }
          grown = near.reduce(box) { merge(_1, _2) }
          return box if grown == box

          box = grown
        end
      end

      # 本文の行が範囲の上端か下端にかかれば、その行を外すように範囲を縮める（行の中の式を線で描くと、その線が図の
      # 図形とつながる）。本文の行が範囲の中ほどを通るなら図にしない。縮めて小さくなりすぎたら図にしない
      def without_body_lines(box, body_lines)
        body_lines.each do |line|
          bottom = line.map(&:y).min - (line.first.size * 0.25)
          top = line.map { it.y + it.size }.max
          next unless bottom < box.top && top > box.bottom && line.first.x < box.right && line.last.right > box.left

          middle = (box.top + box.bottom) / 2
          return nil if bottom < middle && top > middle

          box = top > middle ? box.with(top: bottom) : box.with(bottom: top)
        end
        box if box.right - box.left >= MIN_WIDTH && box.top - box.bottom >= MIN_HEIGHT
      end

      def merge_near(boxes, gap)
        boxes = boxes.dup
        loop do
          pair = boxes.combination(2).find { |a, b| near?(a, b, gap) }
          return boxes unless pair

          boxes -= pair
          boxes << merge(*pair)
        end
      end

      # 範囲の中の字で図にしない理由。文（25 字以上の行）・見出し（本文の 1.5 倍以上の字）・コード（2 行以上）を含めば :content
      # （章の題の飾り枠、吹き出しの文、コードと実行結果を矢印でつないだ組）、表（20 を超える行）を含むか字が範囲の 15% を
      # 超えて占めれば :crowded。図にしてよければ nil
      def text_rejection(box, glyphs, body_size)
        inside = glyphs.select { (it.x + it.right) / 2 >= box.left && (it.x + it.right) / 2 <= box.right && it.y >= box.bottom && it.y <= box.top }
        area = (box.right - box.left) * (box.top - box.bottom)
        rows = text_rows(inside)
        return :content if inside.any? { it.size >= body_size * HEADING_SCALE } || rows.any? { it.size >= TEXT_ROW } || rows.count { code_row?(it) } >= 2

        :crowded if rows.size > LABEL_ROWS || inside.sum { it.width * it.size } > area * TEXT_RATIO
      end

      # 埋め込みの画像と重なる図は除く。画面写真の上に引いた注記の枠と矢印（範囲の 3 割を超えて重なる）と、
      # 小さな画像（アイコン）を囲んだ図（画像の半分を超えて入る）。後者は、図と画像の位置の結び付けを取り違える
      def over_image?(box, images)
        area = (box.right - box.left) * (box.top - box.bottom)
        overlaps = images.map do |image|
          overlap = [[image.right, box.right].min - [image.left, box.left].max, 0].max * [[image.top, box.top].min - [image.bottom, box.bottom].max, 0].max
          [overlap, (image.right - image.left) * (image.top - image.bottom)]
        end
        overlaps.sum(&:first) > area * IMAGE_OVERLAP || overlaps.any? { |overlap, image_area| overlap > image_area * 0.5 }
      end

      # 高さのそろう字の 1 行（隙間で切らない）
      def text_lines(glyphs)
        glyphs.sort_by { [-it.y, it.x] }.chunk_while { |a, b| (a.y - b.y).abs < [a.size, b.size].min * 0.5 }.map { it.sort_by(&:x) }
      end

      # 本文の行。10 字以上で、ページ幅の 4 割を超えて伸び、字が行の 7 割以上を占める。図の中のラベルは短く、図の両側に
      # 置いたラベルの行は間に図が挟まって空く（行の中の式を線で描いた本文の行も空くので、見分けられない）
      def body_line?(line, page_width)
        extent = line.last.right - line.first.x
        line.size >= 10 && extent >= page_width * 0.4 && line.sum(&:width) >= extent * 0.7
      end

      # 2 段組みのページか。ページの真ん中で分けた 8 字以上の切れ端のうち、左半分に収まるものの右端と、右半分に収まるものの
      # 左端が、どちらも 3 つ以上同じ位置（2pt 以内）にそろう（両端そろえの段）。1 段組みのページの行は全幅にわたり、式の空きで
      # 切れた切れ端の端はそろわない
      def two_column_page?(lines, page_width)
        center = page_width / 2
        parts = lines.flat_map { split_at_center(it, page_width) }.select { it.size >= 8 }
        rights = parts.select { it.last.right < center }.map { (it.last.right / 2).round }
        lefts = parts.select { it.first.x > center }.map { (it.first.x / 2).round }
        [rights, lefts].all? { it.tally.values.max.to_i >= 3 }
      end

      # 2 段組みの段の行の切れ端か。図のラベル（「U0」「si」「splane」）は SHORT_LABEL 字以下で、文末で終わらない。段落の最後の
      # 短い行（「追加されません。」）は文末で終わる。段の幅に足りない行（本文の横の吹き出しの文）もラベルにしない
      def column_line?(part) = part.size > SHORT_LABEL || part.last.text.match?(SENTENCE_END)

      # 1 行を、ページの真ん中をまたぐ字の大きさの 1.5 倍を超える隙間（2 段組みの段の間）で左右に分ける
      def split_at_center(line, page_width)
        center = page_width / 2
        line.slice_when { |a, b| b.x - a.right > a.size * 1.5 && a.right < center && b.x > center }.to_a
      end

      # 1 行を、字の大きさの 1.5 倍を超える隙間で分ける（図の中の離れたラベルは別の行）
      def text_rows(glyphs)
        text_lines(glyphs).flat_map { |row| row.chunk_while { |a, b| b.x - a.right < a.size * 1.5 }.to_a }
      end

      # コードの行。等幅の字が 4 字以上で、行の半分を超える（図のラベルが等幅になることはまれ）
      def code_row?(row) = row.count(&:mono?).then { it >= 4 && it * 2 > row.size }

      def row_box(row)
        Box.new(page: row.first.page, left: row.first.x, bottom: row.map(&:y).min, right: row.map(&:right).max, top: row.map { it.y + it.size }.max)
      end

      def near?(a, b, gap)
        b.left <= a.right + gap && b.right >= a.left - gap && b.bottom <= a.top + gap && b.top >= a.bottom - gap
      end

      def inside?(outer, inner)
        inner.left >= outer.left && inner.right <= outer.right && inner.bottom >= outer.bottom && inner.top <= outer.top
      end

      def merge(a, b)
        a.with(left: [a.left, b.left].min, bottom: [a.bottom, b.bottom].min, right: [a.right, b.right].max, top: [a.top, b.top].max)
      end
    end
  end
end
