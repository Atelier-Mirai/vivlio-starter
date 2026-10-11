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
      # OCR が箇条書きの点を読み違えた字（「•」を「e」「©」「es」など）。単独では本文の字と見分けられない
      # ので、ocr_bullet_markers で並びを見る
      OCR_BULLET = /\A[eocs©®°•・●○◦*]{1,2}\z/i
      # 本文の 1.15 倍以上で、本文と違うフォント（太字・ゴシック）なら見出しの候補にする。
      # フォントが本文と同じなら 1.4 倍以上を求める（本のカードの書名のような、大きいだけの字を除く）
      HEADING_RATIO = 1.15
      PLAIN_HEADING_RATIO = 1.4
      # 表の列のあいだとみなす隙間（pt）。和文の両端揃えの字間は 2.5pt、欧文の空白は 3pt ほど
      COLUMN_GAP = 4.0
      # 数式に使うフォント。MMa（MMaCentury-Italic・MMaVariable など）はモリサワの数式の書体（IPSJ の論文）。立体の Century
      # （MMaCentury-Regular）は数式の中の数字のほか表の数字にも使うので除く（罫線の下の年を否定の線と取り違える）
      MATH_FONT_NAME = /\ACM(?:MI|SY|EX)|Symbol|Math|MSAM|MSBM|rsfs|esint|\AMMa(?!Century[A-Z]?-Regular)/i
      # OCR の字で、同じ段落とみなす字の大きさの差（大きいほうに対する割合）。97 章のスキャンで、段落の途中の
      # 切れ目が 139 から 53 に減った。15〜35% のどこでも文字の一致は変わらない
      OCR_SIZE_TOLERANCE = 0.25
      # 文末とみなす OCR の行末（wrapped_mid_sentence?）
      OCR_SENTENCE_END = /[。．.!?！？」』）):：]\z/
      # OCR のコードの行の手がかり（中身）。コメント・よく使う語で始まる行、末尾の do・end、コードの記号
      OCR_CODE_TEXT = /\A(?:#|def|end|class|module|puts|return|require|if|else|elsif|while)|(?:do|end)\z|[={}\[\]|<>]|\.\w+\(/
      # コードの行にはさまれて含める、手がかりの無い行の数
      OCR_CODE_FILLER = 2
      # コードのキャプションの前に付く番号の見出し（「リスト 1.8:」「List 2-3:」）。キャプションにはファイル名だけを残す
      CODE_CAPTION_LABEL = /(?:リスト|List(?:ing)?)\s*\d+(?:[.\-]\d+)*\s*[:：]?\s*/i
      # コードのキャプションになるファイル名だけの行（番号の見出しが前に付いてもよい）
      CODE_FILE_NAME = %r{\A(?:#{CODE_CAPTION_LABEL})?[\w.\-/]+\.\w+\z}
      # 2 段組みとみなすのに要る、段の境目で左右に分かれる行の数
      COLUMN_MIN_LINES = 3
      # 柱とみなすページの端のかたまりの行の数の上限（edge_block）
      MARGIN_BLOCK = 2
      # 2 段の区間に要る、段の境目で左右に分かれる行の数（境目はページ全体の 3 行以上で確かめてある）
      COLUMN_MIN_BAND_LINES = 2
      # キャプションとコードの 1 行目の間（字の大きさの倍）。OCR ではコードの 1 行目が読めず、2 行目までの間になる
      CODE_CAPTION_GAP = 4.5
      # 図や表のキャプションの頭（「図 9-8」「表 1」「Figure 3」）。番号の後に助詞や読点が続く本文の文（「図 5.4 は、」「図 5–6 の例では」）は除く
      FIGURE_CAPTION = /\A(?:[図表]|Fig(?:ure|\.)|Table)\s*\d++(?:[.．\-–—‐]\d++)*+(?!\s*[はのにをがでとも、，])/
      # 否定の線の下の字を TeX にするときの置き換え（overline_tex）
      OVERLINE_TEX = { '·' => '\cdot ', '⋅' => '\cdot ', '×' => '\times ', '⊕' => '\oplus ', '↑' => '\uparrow ', '↓' => '\downarrow ',
                       '∨' => '\lor ', '∧' => '\land ', '{' => '\{', '}' => '\}' }.freeze
      # 筆算の 1 行（演算記号と数。16 進の A〜F・基数の「(2)」を含む）
      CALC_ROW = /\A[+\-−×÷]?[0-9A-Fa-f.]+(?:\(\d{1,2}\))?\z/
      # 筆算の割り算の行（除数「)」被除数）
      CALC_DIVISION_ROW = /\A[0-9A-Fa-f.]+\)[0-9A-Fa-f.]+\z/
      # 筆算の演算記号を TeX にするときの置き換え
      CALC_TEX = { '−' => '-', '×' => '\times', '÷' => '\div' }.freeze
      # 目次の項目の行末。点線のリーダーとページ番号で終わる。点（. ． ・ ･ ·）は 3 字以上、三点リーダー（… ‥ ⋯）は
      # 1 字で点 3 つぶんなので 1 字以上（「大事なこと … 16」）。GPU の育てかたは半角の中黒（･ U+FF65）で、項目がつながっていた
      TOC_ENTRY_END = /(?:(?:[.．・･·]\s*){3,}|(?:[…‥⋯]\s*)+)\d+\z/

      # @param pages [Array<MarkedContentReceiver>] ページごとに読み終えた受け手
      # @param text_area [Hash, nil] { top:, bottom:, inner:, outer: }（pt）。指定したときだけ版面の外を除く
      # @param page_numbers [Array<Integer>, nil] pages のそれぞれの、0 から数えたページの番号。一部のページだけを渡すときに要る
      # @param output_pages [Array<Integer>, nil] 原稿に出すページの番号。ほかのページは、柱・ノンブル・本文の字の大きさなどの
      #   ページをまたいで見る手がかりにだけ使う（vs pdf:read --pages の前後のページ。pdf-read-file-naming-spec.md §10.3）
      def initialize(pages, text_area: nil, page_numbers: nil, output_pages: nil)
        @pages = pages
        @text_area = text_area
        @page_numbers = page_numbers || pages.each_index.to_a
        @output_pages = output_pages&.to_set
      end

      # @return [StructureReader::Element]
      def root
        @column_right_edges = {}.compare_by_identity
        @column_left_edges = {}.compare_by_identity
        @figures = @pages.map { page_figures(it) }
        page_glyphs = @pages.each_with_index.map { |page, index| visible_glyphs(page, index) - figure_labels(page, index) }
        page_lines = page_glyphs.map { build_lines(it) }
        all_lines = page_lines.flatten
        # 本文の大きさは、字の数でなく字の幅の合計で決める。和文の論文は英語の参考文献や数式の小さな字が字の数で本文を上回る
        # （73-4-218 は 8pt の英字が 8,456 字、9.2pt の本文が 6,649 字）。和文の 1 字は英字の 2 字分の幅を取る
        @body_size = all_lines.flat_map(&:glyphs).group_by { it.size.round(1) }.max_by { |_size, glyphs| glyphs.sum(&:width) }&.first || 10.0
        body_glyphs = all_lines.flat_map(&:glyphs).select { (it.size - @body_size).abs < 0.2 }
        @body_font = dominant(body_glyphs.map { it.font&.name })
        if (plain = plain_body_font(body_glyphs.find { it.font&.name == @body_font }&.font))
          page_lines = page_glyphs.map { |glyphs| build_lines(glyphs.map { it.font&.name == @body_font ? it.with(font: plain) : it }) }
        end
        @pitch = line_pitch(page_lines)
        @right_edges = right_edges(page_lines)

        page_lines = drop_running_heads(drop_margin_labels(page_lines))
        page_lines = page_lines.each_with_index.map { |lines, index| output_page?(index) ? lines : [] }
        page_lines = page_lines.zip(column_gutters(page_lines)).map { |lines, gutter| split_columns(lines, gutter) }
        @overlines = overline_marks(page_lines)
        page_lines = drop_radicals(page_lines)
        blocks = page_lines.each_with_index.flat_map do |lines, index|
          lines, calculations = written_calculations(lines, index)
          place_images(insert_by_top(page_blocks(attach_rubies(lines)), calculations), output_page?(index) ? @figures[index] : [])
        end
        element(:Document, elements(blocks))
      end

      private

      def output_page?(index) = @output_pages.nil? || @output_pages.include?(@page_numbers[index])

      # --- Phase: 行を組む ---

      # 本文の書体が太字の名前（論文の本文の「FutoMinA101Pro-Bold」）や等幅の印（Word の論文の本文の MS ゴシック）を
      # 持つときは、印を外した書体を返す。本文の字がすべて強調（**）や見出しに、英数字がすべて行内のコードになるため。
      # 等幅は名前が等幅の書体（Courier・HackGen など）なら残す（コードの多い本では、コードの書体が最も多いことがある）
      def plain_body_font(font)
        return nil unless font

        mono = font.mono && !font.name.match?(MarkedContentReceiver::MONO_FONT_NAME)
        font.with(bold: false, mono: font.mono && !mono) if font.bold || mono
      end

      # text_area を指定したときだけ、版面の外の文字を除く（論点 6）。奇数ページは左が綴じ側
      def visible_glyphs(page, index)
        glyphs = drop_overprinted(page.page_glyphs.reject { it.text.strip.empty? || it.text.match?(/\A[[:cntrl:]]+\z/) })
        return glyphs unless @text_area

        width, height = page.page_size
        inner, outer = @text_area.values_at(:inner, :outer)
        left, right = @page_numbers[index].even? ? [inner, width - outer] : [outer, width - inner]
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

      # ページの図。埋め込みの画像と、線で描いた図（§4.11）。線で描いた図は、図形を読んだページ（文字の層のある
      # ページ）だけで探す（OCR したページとテストのページは図形を持たない）
      def page_figures(page)
        vector = page.respond_to?(:page_shapes) ? VectorFigures.find(page) : []
        page.page_images + vector
      end

      # 図の上に描かれた文字（図解の番号や注釈）は図の一部なので、本文から除く。ページを覆う画像
      # （背景・スキャン）の上の文字は本文として残す
      def figure_labels(page, index)
        width, height = page.page_size
        figures = @figures[index].select { (it.right - it.left) * (it.top - it.bottom) < width * height * 0.6 }
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

      # --- Phase: 2 段組み（pdf-read-structure-spec.md §4.10） ---

      # 2 段に組んだ区間の行を、段の境目で左右に分け、左の段を読み終えてから右の段を読む順に並べる。
      # 分けないと、同じ高さの左右の行が 1 行につながり、段の間の隙間が表の列の境目になる（gitlab.pdf で 194 個）。
      # 区間は、段の境目で分かれる行（:split）が 2 行以上続くところ。その上下には、同じ段の行頭にあって行送りの
      # 1.5 倍以内に続く片側だけの行（段の長さの違い・段落の終わり）を足す。全幅の見出しや囲みは区間に入らない
      def split_columns(lines, gutter)
        return lines unless gutter

        sides = lines.map { column_side(it, gutter) }
        bands = column_bands(lines, sides, gutter)
        return lines if bands.empty?

        order = lines.each_index.to_a
        bands.reverse_each { |band| order[band] = [band] } # 区間の添字を、その範囲（Range）1 つに置き換える
        order.flat_map do |entry|
          next [lines[entry]] if entry.is_a?(Integer)

          lefts, rights = entry.each_with_object([[], []]) do |index, (left, right)|
            line = lines[index]
            case sides[index]
            in :left then left << line
            in :right then right << line
            in Integer => cut
              left << make_line(line.glyphs.take(cut))
              right << make_line(line.glyphs.drop(cut))
            end
          end
          lefts.each { @column_right_edges[it] = gutter[:left_edge] }
          rights.each { @column_left_edges[it] = gutter[:right_start] }
          lefts + rights
        end
      end

      # ページごとの段の境目。2 段の区間が 2 行しかないページは、ページの中では境目が決まらない（3 行で確かめる）。
      # 同じ側（偶数・奇数）のページの 3 割以上で境目が見つかる本なら、その側で見つかり、両側を合わせて 3 回以上
      # 見つかった境目（紙面の型がいくつかあると位置が違う）を試し、そのページでいちばん多くの行を左右に分けるものを
      # 借りる。数を両側で合わせるのは、左右の余白を入れ替えない短い論文のため（4 ページの論文は奇数ページが 2 枚で、
      # 題と要旨のある 1 ページ目は自分では境目が決まらない）。1 段組みの本の数ページだけの段組み（索引など）は、
      # ほかのページへ広げない
      def column_gutters(page_lines)
        gutters = page_lines.map { column_gutter(it) }
        counts = gutters.compact.tally
        shared = gutters.each_with_index.group_by { |_gutter, page| page % 2 }.transform_values do |pairs|
          found = pairs.map(&:first).compact
          found.size >= pairs.size * 0.3 ? found.uniq.select { counts[it] >= 3 } : []
        end
        gutters.each_with_index.map do |gutter, page|
          gutter || shared.fetch(page % 2, []).map { [it, banded_count(page_lines[page], it)] }
                          .select { |_gutter, count| count.positive? }.max_by(&:last)&.first
        end
      end

      # 借りた境目で 2 段の区間に入る行の数
      def banded_count(lines, gutter) = column_bands(lines, lines.map { column_side(it, gutter) }, gutter).sum(&:size)

      # 2 段の区間（行の添字の範囲）。:split の行の並びから、上下へ片側の行を足して広げる
      def column_bands(lines, sides, gutter)
        splits = sides.each_index.select { sides[it].is_a?(Integer) }
        # 境目をまたぐ行、段の幅に収まる見出し（字の大きさが違う行）、行送りの 2.5 倍を超える空きで区間を切る
        groups = splits.slice_when do |a, b|
          (a + 1...b).any? { sides[it] == :span || (lines[it].size - lines[a].size).abs > 1 } ||
            lines[a].baseline - lines[b].baseline > @pitch * 2.5
        end
        groups = groups.select { it.size >= COLUMN_MIN_BAND_LINES }
        bands = groups.map do |group|
          first, last = group.minmax
          first -= 1 while first.positive? && column_continues?(lines, sides, gutter, first - 1, first)
          last += 1 while last + 1 < lines.size && column_continues?(lines, sides, gutter, last + 1, last)
          first..last
        end
        merge_ranges(bands + interleaved_bands(lines, sides))
      end

      # 左右の段で行の高さ（ベースライン）がずれる紙面では、境目で分かれる行（:split）が 1 行も無い（論文の 1 ページ目は、
      # 全幅の題と要旨の下で右の段の行が左の段の行の間の高さに並ぶ）。片側だけの行が全幅の行を挟まずに続き、左右とも
      # COLUMN_MIN_LINES 行以上あって、左右が COLUMN_MIN_LINES 回以上入れ替わるところも 2 段の区間にする
      def interleaved_bands(lines, sides)
        one_side = ->(index) { %i[left right].include?(sides[index]) }
        runs = lines.each_index.chunk_while do |a, b|
          one_side.(a) && one_side.(b) && lines[a].baseline - lines[b].baseline <= @pitch * 2.5
        end
        runs.select do |run|
          run.count { sides[it] == :left } >= COLUMN_MIN_LINES && run.count { sides[it] == :right } >= COLUMN_MIN_LINES &&
            run.each_cons(2).count { |a, b| sides[a] != sides[b] } >= COLUMN_MIN_LINES
        end.map { it.first..it.last }
      end

      def merge_ranges(ranges)
        ranges.sort_by(&:first).each_with_object([]) do |range, merged|
          if merged.any? && range.first <= merged.last.last + 1
            merged[-1] = merged.last.first..[merged.last.last, range.last].max
          else
            merged << range
          end
        end
      end

      # 片側だけの行が、隣の区間の行と同じ段の続きか。段の行頭（左の段は区間の行頭、右の段は右の段の左端）から
      # 1.5 字以内で始まり、行送りの 1.5 倍以内にある
      def column_continues?(lines, sides, gutter, index, neighbor)
        side = sides[index]
        return false unless %i[left right].include?(side)

        line = lines[index]
        start = side == :left ? lines[neighbor].x : gutter[:right_start]
        (line.x - start).abs <= line.size * 1.5 && (lines[neighbor].baseline - line.baseline).abs <= @pitch * 1.5
      end

      # 段の境目。字の大きさの 0.8 倍以上の隙間を 1 つだけ持ち、それが同じ位置を挟む 10 字以上の行のうち、左の部分の右端がそろう
      # （両端揃えの段は境目の手前で止まる）行が 3 行以上あるところ。そろう行の左右の部分は、どちらも 8 字ぶん
      # 以上の幅がいる。表の升目（右端がそろわない・幅が狭い）、囲みの中の 2 列の一覧や図のラベル（右端がそろわない）は
      # 数に入らない。隙間の中ほどを候補にし、そろう行のいちばん多いものを採る
      # @return [Hash{Symbol => Integer}, nil] 左の段の右端と、右の段の左端
      def column_gutter(lines)
        # 大きな隙間が 1 つだけの行（左右の段の中は字が詰まっている）。字間を広げた見出しや両端揃えで字間の
        # 開いた短い行は、隙間がいくつもあるので数えない。行末の句読点を段の外へぶら下げると、隙間は字の 0.9 倍
        # ほどに縮む
        gaps = lines.select { it.glyphs.size >= 10 && !mostly_mono?(it) }.filter_map do |line|
          found = line.glyphs.each_cons(2).filter_map { |a, b| [a.right, b.x, line] if b.x - a.right >= a.size * 0.8 }
          found.first if found.one?
        end
        candidates = gaps.map { |left, right, _line| ((left + right) / 2).round }.uniq
        candidates.filter_map { column_gutter_at(gaps, it) }.max_by { it[:lines] }&.except(:lines)
      end

      def column_gutter_at(gaps, x)
        crossing = gaps.select { |left, right, _line| left <= x && x <= right }.map(&:last).uniq
        lefts = crossing.to_h { |line| [line, line.glyphs.select { it.right <= x }] }
        edge = dominant(lefts.values.map { it.last.right.round })
        aligned = crossing.select { |line| column_end?(lefts[line].last, edge, line.size) }
        return nil if aligned.size < COLUMN_MIN_LINES

        rights = aligned.map { |line| line.glyphs.select { it.x >= x } }
        size = aligned.first.size
        return nil unless [aligned.map { lefts[it] }, rights].all? { |parts| median(parts.map { it.last.right - it.first.x }) >= size * 8 }

        # 2 段組みの段の幅はほぼ等しい。表の列（記法と説明・名前と値）は幅が違うので外れる
        right_start = dominant(rights.map { it.first.x.round })
        left_width = edge - dominant(aligned.map { lefts[it].first.x.round })
        right_width = rights.map { it.last.right }.max - right_start # 段落の終わりの短い行があるので、いちばん右で測る
        return nil unless left_width.fdiv(right_width).between?(0.75, 1.33)

        { left_edge: edge, right_start:, lines: aligned.size }
      end

      # 行が段の境目のどちら側にあるか。境目は左の段の右端から右の段の左端までの帯で見る（1 点で見ると、
      # 帯にかかる句読点の字で外れる）。帯の中に半字以上の隙間がある行は、隙間の右の字の位置（Integer）で
      # 左右に分ける。ただし左の部分が段の右端にそろうか、文末で終わる（段落の終わり）行に限る。囲みの中の
      # 2 列の一覧のようにどちらでもない行と、境目をまたぐ行（全幅の見出し・図の注記）は :span
      def column_side(line, gutter)
        left_edge, right_start = gutter.values_at(:left_edge, :right_start)
        return :left if line.right <= right_start - (line.size * 0.5)
        return :right if line.x >= left_edge + (line.size * 0.5)
        return :span if mostly_mono?(line)

        cut = line.glyphs.each_cons(2).find_index do |a, b|
          a.right <= right_start && b.x >= left_edge && b.x - a.right >= line.size * 0.5
        end
        return :span unless cut

        last = line.glyphs[cut]
        column_end?(last, left_edge, line.size) || last.text.match?(/[。．.!?！？」』）)]\z/) ? cut + 1 : :span
      end

      # 段の右端で終わる字か。行末の句読点は段の外へぶら下げることがあり、そのときは字の左端が段の右端にそろう
      def column_end?(glyph, edge, size)
        (glyph.right - edge).abs <= size * 0.5 || (glyph.text.match?(/\A[、。，．,.」』）)]\z/) && (glyph.x - edge).abs <= size * 0.5)
      end

      def median(values) = values.sort[values.size / 2]

      # 等幅の字が半分以上の行（コード）。コードの中の 2 字以上の空白（ログの欄・そろえたコメント）を段の境目にしない
      def mostly_mono?(line) = line.glyphs.count(&:mono?) * 2 >= line.glyphs.size

      # 行の右端の基準。2 段組みの左の段の行は段の右端、ほかはページの本文の右端
      def right_edge(line, fallback) = @column_right_edges[line] || @right_edges.fetch(line.page, fallback)

      # ベースラインがそろうか、小さな字が大きな字の 0.6 倍以内に持ち上がっている（上付きの番号）。
      # TeX の脚注の番号は本文の 0.45 倍ほど持ち上がる。ルビは 1 字ぶん以上離れているので入らない。
      # OCR の字には持ち上がりを当てない。語の高さは行でそろい（上付きの番号も行の高さになる）、コードの左の
      # 欄を縦に読んだ崩れた語は大きさを 27pt と見積もられて、上の行（8pt）を持ち上がった字として取り込んだ
      def same_row?(base, glyph)
        return true if (base.y - glyph.y).abs <= [base.size, glyph.size].min * 0.5
        return false if base.font.nil? || glyph.font.nil?

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
            next ocr_running_head?(line, candidates, needed) if line.glyphs.first.font.nil?

            key = line.baseline.round
            heights.fetch(key, 0) >= needed &&
              (line.text.match?(/\A[\divxlcdm\-–— ]+\z/i) || repeats[[key, normalize_running(line.text)]].to_i >= 2)
          end
        end
      end

      # OCR の柱とノンブル。OCR の行は、高さがスキャンの傾きや行の枠の取り方で数 pt 揺れ、字も読み違える
      # （「贈り物」を「り物」）ので、同じ高さ・同じ文字列では見つからない（97 章のスキャンで柱が 9 回残った）。
      # 高さの差が字の大きさ以内で、字の 6 割以上が共通する行が、ほかのページと合わせて needed ページ以上に
      # あれば柱とする。数字だけの行は、同じ高さに並ぶ行の数で見る
      def ocr_running_head?(line, candidates, needed)
        nearby = candidates.select { |other| (other.baseline - line.baseline).abs <= [line.size, other.size].max }
        return nearby.size >= needed if line.text.match?(/\A[\divxlcdm\-–— ]+\z/i)

        text = normalize_running(line.text)
        nearby.map(&:page).uniq.count do |page|
          nearby.any? { it.page == page && common_ratio(text, normalize_running(it.text)) >= 0.6 }
        end >= needed
      end

      # 2 つの文字列に共通する字の割合（最長共通部分列の長さ × 2 ÷ 両方の長さ）
      def common_ratio(a, b)
        return 0.0 if a.empty? || b.empty?

        row = Array.new(b.size + 1, 0)
        a.each_char do |char|
          diagonal = 0
          b.each_char.with_index(1) do |other, index|
            above = row[index]
            row[index] = char == other ? diagonal + 1 : [row[index], row[index - 1]].max
            diagonal = above
          end
        end
        row.last * 2.0 / (a.size + b.size)
      end

      # 版面の左右の外に置いた柱・ノンブル・つめ（章の見出しを縦に並べた印）は、本文と同じ高さに
      # 並ぶと行に混ざる。版面の外にあり、数字だけか、同じ文字列が同じ位置に何ページも出るまとまりを落とす
      def drop_margin_labels(page_lines)
        columns = page_lines.each_with_index.map { |lines, page| body_column(lines, @pages[page].page_size.first) }
        # 図や画面写真の多いページは本文の行が少なく版面が決まらない。回した字（つめ）だけは、同じ側（偶数・奇数）の
        # ページでいちばん多い版面で見る。ほかの字にまで広げると、版面の広い目次のページ番号を落とす
        by_side = columns.each_with_index.group_by { |_column, page| page % 2 }.transform_values { dominant(it.map(&:first)) }
        segments = page_lines.each_with_index.flat_map do |lines, page|
          lines.flat_map { |line| outside_segments(line, columns[page], columns[page] || by_side[page % 2]) }.map { [page, it] }
        end
        counts = segments.group_by { |_page, run| [(run.first.x / 10).round, normalize_running(run.map(&:text).join)] }
                         .transform_values { it.map(&:first).uniq.size }
        dropped = segments.select do |_page, run|
          text = run.map(&:text).join
          # 回して描いた字（縦に並べたつめ）は、1 ページだけでも落とす。字ごとに別の行になり、繰り返しでは見分けにくい
          text.match?(/\A\d+\z/) || run.all?(&:rotated) || counts[[(run.first.x / 10).round, normalize_running(text)]] >= 2
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

        # 行頭は回して描いた字（つめ）を除いて測る。本文の行頭に接したつめの字で、版面が外へ広がらないように
        [dominant(wide.map { (it.glyphs.find { !it.rotated } || it.glyphs.first).x.round }), dominant(wide.map { it.right.round })]
      end

      # 行のうち、1 字を超える隙間で区切ったまとまりが版面の外にあるもの（本文の字間が 1 字を超えることはまず無い）
      def outside_segments(line, column, rotated_column = column)
        return [] unless rotated_column

        left, right = column || [-Float::INFINITY, Float::INFINITY]
        rotated_left, rotated_right = rotated_column
        # 回して描いた字（縦に組んだつめ）は、本文の行頭に接していても別のまとまりにし、最初の字が版面の端より
        # 外なら落とす。縦書きの字は pdf-reader が横に進めて位置を出すので、正しいのは最初の字の位置だけ
        runs = line.glyphs.chunk_while { |a, b| b.x - a.right <= line.size && a.rotated == b.rotated }
        runs.select do |run|
          next run.first.right <= rotated_left || run.first.x >= rotated_right if run.all?(&:rotated)

          # 等幅の字（コードの行番号）は落とさない
          !run.all?(&:mono?) && (run.map(&:right).max < left - line.size || run.first.x > right + line.size)
        end
      end

      def margin_lines(lines)
        return lines if lines.size <= 1

        (edge_block(lines) + edge_block(lines.reverse)).uniq
      end

      # ページの端から MARGIN_BLOCK 行までのかたまりで、次の行から行送りの 1.8 倍より離れるもの。柱は 2 行のこともある
      # （IPSJ の論文の「Vol.2014-ARC-208 No.19」と、その下の「2014/1/24」）。2 行のかたまりは、どちらも本文より小さい字で、
      # ほかに 3 行以上あるページに限る（数学クイズの各ページの下の「答え」と答えの字・本文が 2 行だけのページは柱ではない）
      def edge_block(lines)
        (1..MARGIN_BLOCK).each do |size|
          break if size >= lines.size
          next unless (lines[size - 1].baseline - lines[size].baseline).abs > @pitch * 1.8
          return lines.first(size) if size == 1 || (lines.size >= size + 3 && lines.first(size).all? { it.size < @body_size * 0.95 })

          break
        end
        []
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

      # ページごとの本文の右端（本文の大きさの行の右端で、いちばん多い位置）。OCR のページは ocr_right_edge
      def right_edges(page_lines)
        page_lines.each_with_index.to_h do |lines, page|
          next [page, ocr_right_edge(lines, @pages[page].page_size&.first.to_f)] if lines.any? && lines.none? { it.glyphs.first.font }

          [page, dominant(lines.select { body_sized?(it) }.map { it.right.round })]
        end.compact
      end

      # OCR のページの本文の右端。ページの幅の 4 割を超える行の右端を右から見て、6pt 以内にもう 1 行の右端が
      # そろういちばん右の位置にする。OCR の行は字の大きさの見積もりが揺れて「本文の大きさの行」がページに
      # 数行しか残らず、右端も 1〜2pt 揺れるので、いちばん多い位置では決まらない（コードの多いページで
      # 本当は 516pt の右端を 323pt としていた）
      def ocr_right_edge(lines, page_width)
        rights = lines.select { it.right - it.x > page_width * 0.4 }.map(&:right).sort.reverse
        rights.find { |right| rights.count { (right - it).between?(0, 6) } >= 2 } || rights.first
      end

      # --- Phase: 否定の線（pdf-read-structure-spec.md §4・pdf-read-ocr-improvement-notes.md §4.21） ---

      # 論理式の否定（Ā・(A+B) の上の線）は、TeX では字ではなく細い横線で描かれ、読み取ると消えて式の意味が
      # 変わる（ド・モルガンの定理が「A + B = A · B」になる）。横線の真下の字の並びを見つけ、字ごとに、
      # かかる線を外側から並べて覚える（{字 => [線]}）。外側は幅の広い線、同じ幅なら高い線（二重否定）。
      # 左端に根号の字が接する線は平方根の横棒で、下の字の並びを $\sqrt{…}$ にする（§4.22）。根号の字は
      # @radicals に覚えて本文から除き（drop_radicals）、横棒は @sqrt_rules に覚える
      def overline_marks(page_lines)
        marks = {}.compare_by_identity
        @radicals = {}.compare_by_identity
        @sqrt_rules = {}.compare_by_identity
        page_lines.each_with_index do |lines, index|
          rules = @pages[index].page_rules
          next if rules.empty?

          glyphs = lines.flat_map(&:glyphs)
          rules.each do |rule|
            radical = glyphs.find { radical_of?(it, rule) }
            # 行は上から並ぶ。線の下でいちばん近い、条件に合う行だけを採る（平方根の横棒の高さの許容は広く、
            # 中身の行の下の本文の行まで当てはまった）
            covered = lines.lazy.filter_map { radical ? radicand_glyphs(it, rule) : overlined_glyphs(it, rule, glyphs) }.first
            next unless covered

            covered.each { (marks[it] ||= []) << rule }
            (@radicals[radical] = true) && (@sqrt_rules[rule] = true) if radical
          end
        end
        marks.each_value { |list| list.sort_by! { |rule| [-(rule.right - rule.left), -rule.bottom] } }
      end

      # 平方根の横棒の根号の字か。TeX の根号は横棒の高さから下へ垂れ下がる字で、右端が横棒の左端に接し、
      # 字の基準の高さが横棒とそろう（H21-takase.pdf で差は 0.3pt 以内）。「√」の字は基準の高さを問わない
      def radical_of?(glyph, rule)
        return false unless radical?(glyph, rule, inside: true) && (glyph.right - rule.left).abs <= 0.6

        glyph.text == '√' ? glyph.y < rule.bottom : (glyph.y - rule.bottom).abs <= 1.0
      end

      # 平方根の横棒の下の字の並び（中身）。横棒は中身の行の上の字の大きさの 2.5 倍まで（入れ子の外側の横棒は
      # 内側の根号の分だけ高い）。両端が中身の並びとそろい、和文の字と大きな隙間を含まない。中身は数字だけの
      # こともあるので、数式の書体は求めない（根号が十分な手がかり）
      def radicand_glyphs(line, rule)
        size = line.size
        return nil unless (rule.bottom - line.baseline).between?(size * 0.3, size * 2.5)

        covered = line.glyphs.select { ((it.x + it.right) / 2).between?(rule.left - 0.5, rule.right + 0.5) && !radical?(it, rule, inside: true) }
        return nil if covered.empty? || covered.any? { it.text.match?(StructureMarkdown::WIDE_CHAR) }
        return nil if (covered.first.x - rule.left).abs > size * 0.6 || (covered.last.right - rule.right).abs > size * 0.6
        return nil if covered.each_cons(2).any? { |a, b| b.x - a.right > size * 1.5 }

        covered
      end

      # 平方根に置き換えた根号の字を、行から除く（字だけの行は行ごと落とす）
      def drop_radicals(page_lines)
        return page_lines if @radicals.empty?

        page_lines.map do |lines|
          lines.filter_map do |line|
            kept = line.glyphs.reject { @radicals.key?(it) }
            next line if kept.size == line.glyphs.size
            next nil if kept.empty?

            make_line(kept, rubies: line.rubies)
          end
        end
      end

      # 横線が否定の線なら、その下の字の並びを返す。線は行の字の上端の少し上にあり、両端が下の字の並びの
      # 両端とそろう。和文の字や、大きく空いた所（表の罫線は升目をまたぐ）を含まない。英数字を含み（記号「▲」
      # だけの飾りを除く）、半分以上が数式の書体で、平方根の横棒（根号がくっつく）でも分数の線でもないこと
      def overlined_glyphs(line, rule, page_glyphs)
        size = line.size
        return nil unless (rule.bottom - line.baseline).between?(size * 0.5, size * 1.6)

        covered = line.glyphs.select { ((it.x + it.right) / 2).between?(rule.left - 0.5, rule.right + 0.5) }
        return nil if covered.empty? || covered.any? { it.text.match?(StructureMarkdown::WIDE_CHAR) }
        return nil if covered.none? { it.text.match?(/[A-Za-z0-9]/) } || covered.count { math_glyph?(it) } * 2 < covered.size
        return nil if page_glyphs.any? { radical?(it, rule) } || covered.any? { radical?(it, rule, inside: true) }
        return nil if (covered.first.x - rule.left).abs > size * 0.5 || (covered.last.right - rule.right).abs > size * 0.5
        return nil if covered.each_cons(2).any? { |a, b| b.x - a.right > size * 1.5 }
        return nil if fraction_bar?(rule, size, page_glyphs)

        covered
      end

      # 数式の書体（TeX の CMMI・CMSY など）の字。否定の線は数式の中にあり、線の下の字の半分以上がこの書体で
      # 組まれる。表の升目の上の罫線や見出しの飾りの枠の下の字（本文の書体）を除く（文字の層のある 23 本の
      # PDF のうち 13 本で取り違えていた）
      def math_glyph?(glyph) = glyph.font&.name.to_s.sub(/\A[A-Z]{6}\+/, '').match?(MATH_FONT_NAME)

      # 根号（√。TeX の CMSY では「p」、CMEX では「p」〜「t」の字）。線の左端にくっつくか（inside なら線の下に
      # 入り込むか）すれば、線は平方根の横棒で、否定の線ではない
      def radical?(glyph, rule, inside: false)
        return false unless glyph.text.match?(/\A[√pqrst]\z/) && glyph.font&.name.to_s.match?(/CMSY|CMEX|Symbol|Math/i)

        inside || (glyph.right.between?(rule.left - 3, rule.left + 1) && glyph.y < rule.bottom)
      end

      # 分数の線か。線にほとんど接して（字の大きさの 0.45 倍以内）上に字があるか、線の上の字の大きさ以内に
      # 中ほどが線の幅に入る字があり、その字の行が線の幅（左右に半字のゆとり）に収まれば、それは分子。
      # 行の詰まった前の行の本文は、線から 6pt ほど離れ、線より左右に長く伸びる。同じ行に分数が並ぶと
      # 分子の行は線の外まで伸びるので、接しているかでも見る
      def fraction_bar?(rule, size, page_glyphs)
        return true if page_glyphs.any? { (it.y - rule.top).between?(0, size * 0.45) && it.right > rule.left && it.x < rule.right }

        above = page_glyphs.select { (it.y - rule.top).between?(0, size) && ((it.x + it.right) / 2).between?(rule.left, rule.right) }
        return false if above.empty?

        row = page_glyphs.select { (it.y - above.first.y).abs < 1 }
        row.all? { it.x >= rule.left - (size * 0.5) && it.right <= rule.right + (size * 0.5) }
      end

      # 否定の線と平方根の横棒の下の字を TeX にする。線の入れ子は \overline・\sqrt の入れ子にする
      # （depth は外から数えた線の段）
      def overline_tex(glyphs, depth = 0)
        glyphs.chunk_while { |a, b| @overlines[a][depth].equal?(@overlines[b][depth]) }.map do |run|
          rule = @overlines[run.first][depth]
          next "#{@sqrt_rules.key?(rule) ? '\sqrt' : '\overline'}{#{overline_tex(run, depth + 1)}}" if rule

          run.map { |glyph| glyph.text.each_char.map { OVERLINE_TEX.fetch(it, it) }.join }.join
        end.join
      end

      # --- Phase: 筆算（pdf-read-structure-spec.md §4.9・pdf-read-ocr-improvement-notes.md §4.23） ---

      # 筆算（数を右そろえで縦に並べ、横線を引いた計算）を見つけ、別行立ての数式（$$\begin{array}{r}…$$）の
      # かたまりにする。筆算の字は行から除く。横線は字ではないので、読み取ると線が消え、数が段落やコードに
      # ばらけていた（fundamentals-of-system-design.pdf の例題）。否定の線・平方根に使った線は見ない
      # @return [Array(Array<Line>, Array<Block>)] 筆算の字を除いた行と、筆算のかたまり
      def written_calculations(lines, index)
        marked = @overlines.values.flatten.to_h { [it, true] }.compare_by_identity
        rules = @pages[index].page_rules.reject { marked.key?(it) }.sort_by { -it.bottom }
        consumed = {}.compare_by_identity
        used = {}.compare_by_identity
        blocks = rules.filter_map do |rule|
          next if used.key?(rule)

          calculation = calculation_at(lines, rule, rules)
          next unless calculation

          rows, chain = calculation
          chain.each { used[it] = true }
          rows.flatten.each { consumed[it] = true }
          [rows.first.first.x, Block.new(kind: :math, lines: [], top: rows.first.map { it.y + it.size }.max, page: index, data: calculation_tex(rows, chain))]
        end
        return [lines, []] if blocks.empty?

        # 横に並んだ筆算（2 進・8 進・16 進）は、上端の高さ、続いて左から順に読む
        blocks = blocks.sort_by { |left, block| [-block.top.round, left] }.map(&:last)

        kept = lines.filter_map do |line|
          glyphs = line.glyphs.reject { consumed.key?(it) }
          next line if glyphs.size == line.glyphs.size
          next nil if glyphs.empty?

          make_line(glyphs, rubies: line.rubies)
        end
        [kept, blocks]
      end

      # rule を一番上の横線とする筆算の行（上から。行は字の並び）と横線の並び。筆算でなければ nil。
      # 横線の幅の中の字を行ごとに拾い、上の横線の上に 2 行まで（割り算は商の 1 行）、下の横線の下に 1 行を
      # 求める。幅がほぼ重なり、字の大きさの 10 倍以内で続く横線は 1 つの筆算の横線（掛け算・割り算。2 進の
      # 掛け算は部分積が 5 行あり、横線が 77pt 離れる）。
      # 行はどれも数と演算記号だけ（calculation_row）
      def calculation_at(lines, rule, rules)
        line = lines.min_by { (it.baseline - rule.bottom).abs }
        return nil unless line

        size = line.size
        left = rule.left - (size * 0.6)
        right = rule.right + (size * 0.6)
        # 横線のすぐ上が数の行でなければ筆算ではない。ほとんどの横線（表の罫線・囲みの枠）はここで外れる
        above = lines.select { it.baseline > rule.bottom && it.baseline - rule.bottom <= size * 1.9 }.min_by(&:baseline)
        return nil unless above && calculation_row(above, left, right, size, below_top: false)

        chain = [rule]
        rules.drop(rules.index { it.equal?(rule) } + 1).each do |other|
          last = chain.last
          break if last.bottom - other.bottom > size * 10
          next unless other.bottom < last.bottom && overlap?(other, rule)

          # 間の行がすべて数の行のときだけつなぐ（次の例題の筆算の横線まで続けない）
          between = lines.select { it.baseline < last.bottom && it.baseline > other.bottom && line_in_span?(it, left, right) }
          chain << other if between.any? && between.all? { calculation_row(it, left, right, size, below_top: below_top?(it, rule, size)) }
        end
        candidates = lines.select { it.baseline.between?(chain.last.bottom - (size * 2), rule.bottom + (size * 3.2)) }
        rows = candidates.filter_map { calculation_row(it, left, right, size, below_top: below_top?(it, rule, size)) }
        above = rows.count { it.first.y > rule.bottom }
        below = rows.count { it.first.y < chain.last.bottom }
        return nil unless above.between?(1, 2) && below >= 1 && rows.size == candidates.count { line_in_span?(it, left, right) }
        # 演算記号が数から離れて置かれた行（「+　101.11」）か、割り算の行があること。表の結果の列の
        # 負の数（「-10」）は記号が数にくっついている
        return nil unless rows.size >= 3 && rows.any? { separate_operator?(it, size) || it.map(&:text).join.match?(CALC_DIVISION_ROW) }

        [rows, chain]
      end

      # 同じ筆算の横線か。幅の 6 割以上が重なり、幅が近い（0.6〜1.6 倍。筆算の下の表の罫線は幅が違う）
      def overlap?(a, b)
        widths = [a.right - a.left, b.right - b.left]
        [a.right, b.right].min - [a.left, b.left].max >= widths.min * 0.6 && widths.max <= widths.min * 1.6
      end

      def separate_operator?(row, size)
        operator, number = row.chunk_while { |a, b| b.x - a.right < size * 0.3 }.to_a
        number && operator.map(&:text).join.match?(/\A[+\-−×÷]\z/)
      end

      # 一番上の横線のすぐ下の行か（割り算なら「除数)被除数」の行）
      def below_top?(line, rule, size) = line.baseline < rule.bottom && line.baseline > rule.bottom - (size * 1.9)

      def line_in_span?(line, left, right) = line.glyphs.any? { ((it.x + it.right) / 2).between?(left, right) }

      # 筆算の 1 行の字。横線の幅の中の字で、数と演算記号だけのもの。一番上の横線のすぐ下の行（below_top）は、
      # 割り算なら左に除数と「)」が横線の外へ出るので、行の「)」から左の数も含める
      def calculation_row(line, left, right, size, below_top:)
        inside = line.glyphs.select { ((it.x + it.right) / 2).between?(left, right) }
        return nil if inside.empty?

        if below_top && (bracket = line.glyphs.find { it.text == ')' && it.x.between?(left - (size * 6), left + (size * 2)) })
          divisor = line.glyphs.select { it.right <= bracket.x + 0.5 && it.x >= bracket.x - (size * 8) }
          row = (divisor + [bracket] + inside).uniq.sort_by(&:x)
          return row if row.map(&:text).join.match?(CALC_DIVISION_ROW)
        end
        # 字のまとまりは 1 つ。2 つは、1 つ目が演算記号 1 字のときだけ（「+ 101.11」。表の行は升目ごとに分かれる）
        chunks = inside.chunk_while { |a, b| b.x - a.right < size * 0.8 }.to_a
        return nil if chunks.size > 2 || (chunks.size == 2 && !chunks.first.map(&:text).join.match?(/\A[+\-−×÷]\z/))
        return nil unless inside.map(&:text).join.match?(CALC_ROW)

        inside
      end

      # 筆算を TeX にする。数は原本と同じ等幅（\mathtt）で書き、行の右端をそろえるため、右に足りない桁を
      # \phantom{0} で埋める（字の位置から測る）。横線は \hline。割り算は「除数\enclose{longdiv}{被除数}」とし、
      # 引く数の行（すぐ下に横線のある行）に下線を引く
      def calculation_tex(rows, chain)
        digits = rows.flatten.select { it.text.match?(/\A\d\z/) }.map(&:width).sort
        width = digits.empty? ? rows.first.first.size * 0.5 : digits[digits.size / 2]
        right = rows.map { it.last.right }.max
        division = rows.index { |row| row.map(&:text).join.match?(CALC_DIVISION_ROW) }
        body = rows.each_with_index.map do |row, number|
          pad = '\phantom{0}' * ((right - row.last.right) / width).round
          rule_below = chain.any? { |rule| rule.bottom < row.first.y && (number == rows.size - 1 || rule.bottom > rows[number + 1].first.y) }
          if division
            text = number == division ? division_tex(row) : calculation_text(row)
            text = "\\underline{#{text}}" if number > division && rule_below
            "#{text}\\mathtt{#{pad}}"
          else
            hline = number.positive? && chain.any? { |rule| rule.bottom < rows[number - 1].first.y && rule.bottom > row.first.y }
            "#{'\hline ' if hline}#{calculation_text(row)}\\mathtt{#{pad}}"
          end
        end
        "$$\\begin{array}{r} #{body.join(' \\\\ ')} \\end{array}$$"
      end

      def calculation_text(row)
        text = row.map(&:text).join
        operator = text[/\A[+\-−×÷]/]
        number = "\\mathtt{#{operator ? text[1..] : text}}"
        operator ? "#{CALC_TEX.fetch(operator, operator)}\\ #{number}" : number
      end

      def division_tex(row)
        divisor, dividend = row.map(&:text).join.split(')', 2)
        "\\mathtt{#{divisor}}\\enclose{longdiv}{\\mathtt{#{dividend}}}"
      end

      # 筆算のかたまりを、上端の高さで読む順に差し込む。同じ行の字（「解答例」）の後ろに入るよう、半字の
      # ゆとりを持たせる（字の大きさの違いで上端が 0.5pt ずれた）
      def insert_by_top(blocks, inserted)
        inserted.reduce(blocks) do |list, block|
          position = list.index { it.top < block.top - (@body_size * 0.5) } || list.size
          list.dup.insert(position, block)
        end
      end

      # --- Phase: かたまりに分ける ---

      def page_blocks(lines)
        @numbered_neighbors ||= {}
        @numbered_neighbors[lines.first&.page] = lines
        (@ocr_bullets ||= {}.compare_by_identity).merge!(ocr_bullet_markers(lines))
        blocks = []
        index = 0
        while index < lines.size
          line = lines[index]
          kind, length = if line.glyphs.first.font.nil? && (code = ocr_code_length(lines, index)).positive? then [:code, code]
                         elsif code_line?(line) then [:code, run_length(lines, index) { code_line?(it) }]
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

      # --- OCR のコード（pdf-read-ocr-improvement-notes.md §4.12） ---

      # OCR の行から始まるコードの行数（コードでなければ 0）。OCR の字には書体の情報が無いので、等幅かどうかでは
      # 見分けられない。行番号で始まる行を強い手がかり、中身がコードらしい行を弱い手がかりとして、どちらかの
      # 行が続く範囲をコードにする。間にはさまる「。」の無い 2 行までの行（崩れて読めた行）も含める。
      # 強い手がかりの行を 2 行以上含むことを求める（番号付きの箇条書きや、記号を含む本文の 1 行を除くため）。
      # 直前にファイル名だけの行（キャプション）があれば、それを強い手がかり 2 行分とみなす。行番号を読めな
      # かったコードや、1 行目が崩れて読めたコードも拾える
      def ocr_code_length(lines, start)
        captioned = start.positive? && ocr_file_caption?(lines[start - 1], lines[start])
        strong = captioned ? 2 : 0
        length = 0
        index = start
        while index < lines.size
          line = lines[index]
          signal = ocr_code_signal(lines, index)
          # 手がかりの無い行は、コードの行の後で、「。」が無く、OCR_CODE_FILLER 行以内にコードの行が続くときだけ含める
          break unless signal || ((index > start || captioned) && !line.text.include?('。') &&
                                  lines[index + 1, OCR_CODE_FILLER].to_a.each_index.any? { ocr_code_signal(lines, index + 1 + it) })
          # 行間は、コードの中の空行（行番号を読めていない）をはさむ字の大きさの 4.5 倍まで。字の大きさは揺れる
          # ので、前後の行と本文の大きいほうで測る
          break if index > start && (lines[index - 1].baseline - line.baseline) > [line.size, lines[index - 1].size, @body_size].max * 4.5
          strong += 1 if signal == :strong
          length = index - start + 1 if signal
          index += 1
        end
        strong >= 2 ? length : 0
      end

      # :strong（行番号で始まり、近くに番号の続く行がある）、:weak（中身がコードらしい）、nil
      def ocr_code_signal(lines, index)
        line = lines[index]
        return nil if line.text.empty?

        number = ocr_line_number(line)
        if number && code_after_number?(line)
          nearby = lines[[index - 3, 0].max..(index + 3)].each_with_index.filter_map do |other, offset|
            other_number = ocr_line_number(other) unless other.equal?(line) || !code_after_number?(other)
            other_number && [other_number - number, offset - [index, 3].min]
          end
          return :strong if nearby.any? { |gap, position| gap.abs.between?(1, 4) && (gap.positive? == position.positive?) }
        end
        text = line.text.sub(/\A\d{1,3}/, '')
        return :weak if text.start_with?('#')

        OCR_CODE_TEXT.match?(text) && text.count("\x21-\x7E") * 2 >= text.size ? :weak : nil
      end

      # 行番号の後が空（空行）か、英字・# を含む（コード）。数と記号だけが続く行（九九の「3 = 27」）の
      # 頭の数は、行番号ではなく数式の左辺
      def code_after_number?(line) = line.text.sub(/\A\d{1,4}/, '').then { it.strip.empty? || it.match?(/[A-Za-z_#]/) }

      # OCR のファイル名だけの行が、すぐ下の行の上にある（コードの 1 行目が読めず、間が開くことがある）
      def ocr_file_caption?(caption, line)
        caption.glyphs.first.font.nil? && caption.text.match?(CODE_FILE_NAME) && caption.page == line.page &&
          caption.baseline - line.baseline <= [caption.size, line.size].max * CODE_CAPTION_GAP
      end

      # 行頭の行番号。番号の後に隙間がある行（line_number）のほか、OCR が番号と字をつなげて読んだ行
      # （「2#v0」「33puts」）も数える。「1827年」「16歳」のように和文が続くものは番号ではない
      def ocr_line_number(line)
        line_number(line) || line.text[/\A(\d{1,3})(?=[#A-Za-z_])/, 1]&.to_i
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
        # 文末で終わる行は見出しにしない。英文のピリオドも見る（Smith の論文の段落の最後の短い行「We call this the storage independence goal.」）
        return false if ratio < HEADING_RATIO || line.text.match?(/(?:[。．]|[a-z]\.)\z/)

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
        # OCR のファイル名だけの行は、下のコードのキャプションになる（ocr_code_length）
        return true if ocr_file_caption?(previous, following)
        return true if code_line?(following) || (!large && heading_candidate?(following)) || list_start?(following)
        wide_gap = previous.baseline - following.baseline > following.size * (@pitch / @body_size) * 1.35
        return footnote_start?(following) || wide_gap if wrapped_mid_sentence?(previous)
        return true if (previous.size - following.size).abs > size_tolerance(previous, following) || footnote_start?(following)
        return true if wide_gap
        # 2 段組みで左の段の下から右の段の上へ移る所。左の段の右端まで届いた行から、右の段の頭へ字下げせずに続けば
        # 同じ段落（下の比べ方では、右の段の行の右端と字下げで必ず切れる）
        if following.baseline > previous.baseline && (start = @column_left_edges[following])
          return previous.right < right_edge(previous, previous.right) - previous.size || following.x > start + (following.size * 0.5)
        end

        # 右端と左端は、この段落の行と次の行で測る。左端には、次の行と右端がそろい、左へ 1.5 字以内に
        # ある先の行（字下げした 1 行目の続き）も使う。先の段落の幅の広い行（囲みの外・画像の下）まで
        # 含めると、狭い段落が 1 行ずつ切れる
        size = following.size
        right = (paragraph + [following]).map(&:right).max
        return true if previous.right < right - (size * 2)
        # 次の行も短い（中央に置いた引用・ファイル名）と上の比べ方では切れないので、文末で終わり
        # ページの本文の右端より手前で止まった行の後でも切る
        return true if previous.text.match?(/[。．.!?！？」』]\z/) && previous.right < right_edge(previous, right) - (size * 2)
        # 和文は両端をそろえて組むので、段落の途中の行は右端まで届く。全角の文末で、この段落と次の行の右端より 1 字を超えて
        # 手前に止まれば段落の終わり。ページの本文の右端とは比べない（囲みの中の行は囲みの右端で折り返す）
        # （『実践 Rust Web 開発 5』の「…保存期間は 30 日です。」は英字の幅の端数で 1.9 字手前に止まり、次の段落とつながった）
        return true if previous.glyphs.first.font && previous.text.match?(/[。．！？」』]\z/) && previous.right < right - size

        column = paragraph + [following] + ahead.select { (it.right - following.right).abs <= 1 && it.x >= following.x - (size * 1.5) }
        # 2 段組みの右の段の行は、段の左端と比べる（段落の行には左の段の行も入っている）
        following.x - (@column_left_edges[following] || column.map(&:x).min) > size * 0.5
      end

      # 文の途中で折り返した OCR の行か。版面の右端まで届き、文末（「。」や閉じ括弧）で終わらない行は、
      # 次の行と同じ段落とみなし、字の大きさ・右端・字下げの比べ方では切らない。OCR の行は字の大きさも
      # 行頭の位置も揺れるので、それらの比べ方だけでは「1903年に結婚／します。」のように切れた。
      # 右端まで届くことを求めるのは、文末で終わらない題・札・コードの行（短い）を巻き込まないため。
      # 文字の層のある PDF の字には当てない
      def wrapped_mid_sentence?(line)
        line.glyphs.first.font.nil? && !line.text.match?(OCR_SENTENCE_END) &&
          line.right >= right_edge(line, line.right) - line.size
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
        return true if @ocr_bullets&.key?(line)
        # 本文より大きな字の行（「■コラム: …」の題）は箇条書きにしない
        return false if line.size < @body_size * 0.92 || line.size >= @body_size * HEADING_RATIO
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

      # OCR の行のうち、頭が箇条書きの点を読み違えた字で始まるもの（行 => 点の字数）。点の字の後に隙間が
      # あり、点と続く字の位置がそろう行が 3 行以上あるときだけ採る。97 章のスキャンの年譜（13 項目）は、
      # 点を「e 1879年:」「© 1895年」と読み、箇条書きにならず、一部は表と取り違えた
      def ocr_bullet_markers(lines)
        candidates = lines.filter_map do |line|
          next if line.glyphs.first.font

          marker = line.glyphs.take(3).chunk_while { |a, b| b.x - a.right < line.size * 0.15 }.first
          following = line.glyphs[marker.size]
          next unless following && marker.map(&:text).join.match?(OCR_BULLET) && following.text.match?(/[\p{Han}\p{Hiragana}\p{Katakana}\d]/)

          [line, marker.size]
        end
        candidates.select do |line, size|
          candidates.count do |other, other_size|
            (other.x - line.x).abs <= line.size && (other.glyphs[other_size].x - line.glyphs[size].x).abs <= line.size
          end >= 3
        end.to_h
      end

      def list_marker_glyphs(line)
        return line.glyphs.take(@ocr_bullets[line]) if @ocr_bullets&.key?(line)

        text = line.text[LIST_MARKER].to_s
        count = 0
        glyphs = line.glyphs.take_while { (count += it.text.length) <= text.length }
        glyphs.map(&:text).join == text ? glyphs : []
      end

      # 項目の続きの行は、頭の記号の後ろの文字の位置にそろう。
      # OCR の行は、字の大きさを比べず（短い行の大きさの見積もりは本文の 1.2〜1.8 倍に揺れ、見出しの候補にもなる）、
      # 版面の右端の代わりに文末で項目の終わりを見る。年譜のように図の横の狭い欄に組んだ項目は、版面の右端まで
      # 届かずに折り返す
      def list_item_length(lines, start)
        text_x = lines[start].glyphs[list_marker_glyphs(lines[start]).size].x
        length = 1
        while (following = lines[start + length])
          previous = lines[start + length - 1]
          ocr = previous.glyphs.first.font.nil?
          break if list_start?(following) || code_line?(following) || (!ocr && heading_candidate?(following))
          break if (following.x - text_x).abs > following.size * 0.6 || (!ocr && (previous.size - following.size).abs > 0.5)
          # 版面の右端より手前で止まった行で、項目は終わる
          break if ocr ? previous.text.match?(/[。．]\z/) : previous.right < right_edge(previous, previous.right) - (following.size * 2)
          break if previous.baseline - following.baseline > following.size * (@pitch / @body_size) * 1.35

          length += 1
        end
        length
      end

      # 等幅の字が 9 割を占める行はコード。行内のコードが多い本文の行（8 割台）と分ける。
      # 書体の分からない行（OCR）は、行頭の番号が前後の行と 1 ずつ続くこと（コードの行番号）で見る。
      # pLaTeX はコードの中の和文を和文の書体で描くので（「13: <th>削除</th>」）、和文を除いた字がすべて等幅で、
      # 行頭が等幅の行番号の行もコードとする。行内のコードで始まる本文の行（「NKF は…」）は行番号が無いので外れる
      def code_line?(line)
        visible = line.glyphs.reject { it.text.tr("\u00A0", ' ').strip.empty? }
        return false if visible.empty?
        return numbered_code_line?(line) if visible.none?(&:font)
        return true if visible.count(&:mono?) >= visible.size * 0.9

        latin = visible.reject { it.text.match?(StructureMarkdown::WIDE_CHAR) }
        latin.any? && latin.all?(&:mono?) && numbered_code_line?(line)
      end

      def numbered_code_line?(line)
        number = line_number(line)
        return false unless number && code_after_number?(line)

        lines = @numbered_neighbors.fetch(line.page, [])
        index = lines.index(line)
        # 前後の行に番号が無いとき（nil.to_i は 0）に、番号 1 の行を続きと取り違えない
        index && [lines[index - 1], lines[index + 1]].compact.any? { (other = line_number(it)) && code_after_number?(it) && (other - number).abs == 1 } &&
          (index.positive? || lines.size > 1)
      end

      # 行頭の数字のあとに 0.5 字以上の隙間がある行の、その数字。数字の直後のコロン（「13:」）は番号の側に含める
      def line_number(line)
        digits = line.glyphs.take_while { it.text.match?(/\A\d\z/) }
        return nil if digits.empty? || digits.size > 4

        colon = line.glyphs[digits.size]
        colon = nil unless colon&.text == ':' && colon.x - digits.last.right < line.size * 0.3
        following = line.glyphs[digits.size + (colon ? 1 : 0)]
        return nil if following && following.x - (colon || digits.last).right < line.size * 0.5

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
          candidate.lines.first.text.match?(CODE_FILE_NAME) &&
          candidate.lines.first.baseline - code.lines.first.baseline <= [candidate.lines.first.size, code.lines.first.size].max * CODE_CAPTION_GAP
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
          (line.size - @body_size).abs <= (line.glyphs.first.font ? @body_size * 0.15 : [line.size, @body_size].max * OCR_SIZE_TOLERANCE) && segments(line).size >= 2
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

      # 画像は、描かれた上端の高さで読む順に差し込む。文のかたまりは並べ直さない（2 段組みでは、右の段の上の
      # 段落が左の段の下の段落より高い位置にある）
      def place_images(blocks, images)
        images.sort_by { -it.top }.reduce(blocks) do |list, box|
          image = Block.new(kind: :image, lines: [], top: box.top, page: box.page, data: box)
          list.dup.insert(list.index { it.top < image.top } || list.size, image)
        end
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
        in :math then element(:Figure, [], alt: block.data)
        in :image then element(:Figure, [MarkedContent.new(glyphs: [], images: [block.data])])
        end
      end

      # StructureReader は本ファイルを読み込んでから定義されるので、要素の型は使うときに引く
      def element(type, children, alt: nil) = StructureReader::Element.new(type:, children:, alt:, actual_text: nil)

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
          # 否定の線の下の字は、行内の数式（$\overline{…}$）にする。書き出しは Alt に TeX を持つ図と同じ
          in [:overline, _rule] then element(:Figure, [], alt: "$#{overline_tex(run)}$")
          end
        end
      end

      def inline_style(glyph, bases, whole_bold)
        return [:overline, @overlines[glyph].first] if @overlines&.key?(glyph)
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
