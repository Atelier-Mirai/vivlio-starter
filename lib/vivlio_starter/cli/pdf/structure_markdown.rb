# frozen_string_literal: true

module VivlioStarter
  module PDF
    # 構造ツリーの要素の木を Markdown へ写す（pdf-read-structure-spec.md §3.1・§3.3・§7.1）。
    #
    # 構造ツリーには改行・字下げ・語のあいだの空白が無い（Chrome は空白を文字として描かない）。
    # そこで文字の座標から、同じ行か・隙間が空白か・字下げが何字かを戻す。
    #
    # 脚注は 2 度描いて決める。1 度目で本文の候補（本文より小さい字で番号から始まる段落）と
    # 参照（小さく持ち上がった数字）を集め、両方そろった番号だけを 2 度目で `[^n]` にする。
    class StructureMarkdown
      # Enhanced Mode で抜き出した画像。page は 0 から数える
      ImagePlacement = Data.define(:page, :left, :bottom, :right, :top, :path)

      # 強調・コード・ルビなどの記号。side は :open（後ろの文字に付く）・:close（前の文字に付く）・
      # :inline（数式などの塊）
      Mark = Data.define(:text, :side)

      # 本文の中の脚注の参照（小さく持ち上がった数字）
      FootnoteRef = Data.define(:number, :page, :glyphs)

      # 段落・見出しなどを積む先。top は章の地の文（ページをまたいだ段落をつなぐのはここだけ）
      class Flow
        attr_reader :blocks, :atoms, :last, :top

        def initialize(top: false)
          @blocks = []
          @atoms = []
          @top = top
          @last = nil
        end

        def push(text, kind, **info)
          @blocks << text
          @last = { kind:, **info }
        end

        def replace_last(text, **info)
          @blocks[-1] = text
          @last = @last.merge(info)
        end

        def take_atoms
          taken = @atoms
          @atoms = []
          taken
        end
      end

      Glyph = MarkedContentReceiver::Glyph
      MarkedContent = MarkedContentReceiver::MarkedContent

      # 和文の文字。和文どうしの隙間は空白にしない（両端揃えで字間が空くため）。
      # 長音（ー）と中黒（・）は Unicode の上では和文の文字種に入らないので、別に足す
      WIDE_CHAR = /[\p{Han}\p{Hiragana}\p{Katakana}\u3000-\u303F\uFF01-\uFF60\u2014\u2015\u2025\u2026\u30FB\u30FC]/
      # 段落の終わりらしい文末
      SENTENCE_END = /[。．.!?！？][」』）)"”]*\z/
      # 脚注の本文の頭の番号（「1.」「1)」「1」）
      FOOTNOTE_BODY_HEAD = /\A(\d{1,3})(?:[.．)）]\s*|\s+)/

      # 中身だけを辿る入れ物
      CONTAINER_TYPES = %i[Document DocumentFragment Part Art Sect Div NonStruct Private Span TOC Index Form].freeze
      # 段落の中に入る要素
      INLINE_TYPES = %i[Strong Em Link Ruby RB RT Quote Reference Annot Lbl Sub BibEntry WP WT Warichu].freeze
      # 捨てる要素。柱とノンブルは Aside に入る（§2.1）
      DROPPED_TYPES = %i[Aside Artifact RP].freeze
      # 段落として写す要素
      PARAGRAPH_TYPES = %i[P Note FENote Caption LBody TOCI TR TH TD].freeze

      INFERRED_TABLE_NOTE = '<!-- pdf:read: 列を推定して組んだ表です。列の対応を確かめてください -->'

      HEADING_LEVELS = { H1: 1, H2: 2, H3: 3, H4: 4, H5: 5, H6: 6, H: 2, Title: 1 }.freeze

      # ファイル名の拡張子から、囲みの言語名を決める
      CODE_LANGUAGES = {
        'rb' => 'ruby', 'py' => 'python', 'js' => 'javascript', 'ts' => 'typescript', 'sh' => 'bash',
        'yml' => 'yaml', 'md' => 'markdown', 'rs' => 'rust', 'kt' => 'kotlin', 'h' => 'c', 'hpp' => 'cpp'
      }.freeze

      # @param root [StructureReader::Element]
      # @param images [Array<ImagePlacement>]
      # @param unmarked [Array<Array<Glyph>>] ページごとの、構造ツリーの外の文字
      def initialize(root, images: [], unmarked: [])
        @root = root
        @images = images
        @unmarked = unmarked
        glyphs = all_glyphs(root)
        @body_size = glyphs.map { it.size.round(1) }.tally.max_by { |_size, count| count }&.first || 10.0
        @heading_offset = heading_offset(root)
        @left_edges = left_edges(glyphs)
        @indent_style = indent_style?(root)
      end

      # @return [String]
      def render
        return '' unless @root

        @labels = nil
        render_pass
        @labels = footnote_labels
        render_pass
      end

      private

      # --- Phase: 全体 ---

      def render_pass
        @found_bodies = []
        @found_refs = {}
        @pending_notes = []
        @used_images = {}
        @first_heading_done = false

        flow = Flow.new(top: true)
        render_blocks(@root.children, flow)
        flush(flow, loose: true)
        flush_notes(flow)

        markdown = flow.blocks.join("\n\n").gsub(/\n{3,}/, "\n\n").strip
        markdown.empty? ? '' : "#{markdown}\n"
      end

      # 入れ物の子を順に写す。地の文（P に入っていない文字）は atoms に溜め、ブロックの手前で段落にする
      def render_blocks(children, flow, para: false)
        children.each do |child|
          case child
          in MarkedContent then add_glyphs(child.glyphs, flow.atoms)
          in StructureReader::Element => element
            if DROPPED_TYPES.include?(element.type)
              flush(flow, loose: !para)
            elsif CONTAINER_TYPES.include?(element.type)
              render_blocks(element.children, flow, para:)
            elsif inline_element?(element, para)
              collect_inline(element, flow.atoms)
            else
              flush(flow, loose: !para)
              render_block(element, flow)
            end
          end
        end
      end

      def inline_element?(element, para)
        return true if INLINE_TYPES.include?(element.type)
        # P の外の Code は、2 行以上にわたるときだけコードの囲みにする（箇条書きの中の行内コードを守る）
        return para || code_lines(glyphs_of_element(element)).size < 2 if element.type == :Code
        return false unless %i[Figure Formula].include?(element.type)

        # 行内の数式（$…$）は段落の中に置く。P の中の画像も行内として扱う
        inline_math?(element.alt) || (para && !display_math?(element.alt) && !code_figure?(element))
      end

      def render_block(element, flow)
        case element.type
        in type if HEADING_LEVELS.key?(type) then render_heading(element, flow)
        in type if PARAGRAPH_TYPES.include?(type)
          render_blocks(element.children, flow, para: true)
          flush(flow, loose: false)
        in :L then render_list(element, flow)
        in :LI then render_list(StructureReader::Element.new(type: :L, children: [element], alt: nil, actual_text: nil), flow)
        in :Table | :InferredTable then render_table(element, flow)
        in :BlockQuote then render_quote(element, flow)
        in :Figure | :Formula then render_figure(element, flow)
        in :Code then render_code(element, nil, flow)
        else render_blocks(element.children, flow)
        end
      end

      # --- Phase: 段落 ---

      def flush(flow, loose:)
        atoms = flow.take_atoms
        return if atoms.none? { !it.is_a?(Mark) || it.side == :inline }

        (loose ? split_loose_paragraphs(atoms) : [atoms]).each { emit_paragraph(flow, it) }
      end

      def emit_paragraph(flow, atoms)
        text = stringify(atoms).strip
        return if text.empty?
        return if footnote_body?(atoms, text)

        last = flow.last
        if flow.top && last&.dig(:kind) == :paragraph && continues_on_next_page?(last[:atoms], atoms)
          merged = last[:atoms] + atoms
          flow.replace_last(stringify(merged).strip, atoms: merged)
        else
          flow.push(text, :paragraph, atoms:)
        end
      end

      # ページの終わりで切れた段落の続き。構造ツリーはページごとに作られることがあり（Chrome）、
      # 1 つの段落が 2 つの P に分かれる。段落の頭を 1 字下げる組み方なら、次のページの頭が
      # 下がっていないことで続きと分かる（文末の「。」で切れていてもよい）。下げない組み方なら、
      # 前の段落が文末で終わっていないことで見る。目次の項目（リーダーとページ番号で終わる）は続かない。
      # 文末の「。」が無いので、次のページの頭の柱（CONTENTS）がつながっていた。図や表のキャプションも続かない
      # （Rust-tutorial のページの下の「図 9-8 所有権を移す関数の呼び出し」が、次のページの段落の頭につながっていた）
      def continues_on_next_page?(previous, following)
        last_page = glyphs_of(previous).last&.page
        first_page = glyphs_of(following).first&.page
        return false unless last_page && first_page && first_page > last_page

        text = glyphs_of(previous).map(&:text).join
        return false if text.match?(LayoutStructure::TOC_ENTRY_END) || text.match?(LayoutStructure::FIGURE_CAPTION)
        return !indented?(following) if @indent_style

        !stringify(previous).strip.match?(SENTENCE_END)
      end

      # 段落の 1 行目が、本文の左端より半字以上下がっているか。2 行目以降が無ければ、
      # そのページの本文の行頭でいちばん多い位置を左端とする
      def indented?(atoms)
        lines = glyphs_of(atoms).chunk_while { same_line?(_1, _2) }.to_a
        return false if lines.empty?

        first = lines.first.first
        left = lines.drop(1).map { it.first.x }.min || @left_edges[first.page]
        left ? first.x - left > first.size * 0.5 : false
      end

      # P に入っていない地の文は、脚注の番号で始まる行と、大きく空いた行で段落を分ける
      def split_loose_paragraphs(atoms)
        lines = atom_lines(atoms)
        paragraphs = []
        lines.each_with_index do |line, index|
          previous = index.positive? ? glyphs_of(lines[index - 1]).last : nil
          first = glyphs_of(line).first
          new_paragraph = paragraphs.empty? || footnote_head_line?(line) ||
                          (previous && first && (previous.page != first.page || previous.y - first.y > first.size * 2.5))
          new_paragraph ? paragraphs << line.dup : paragraphs.last.concat(line)
        end
        paragraphs
      end

      def atom_lines(atoms)
        lines = [[]]
        previous = nil
        atoms.each do |atom|
          glyph = atom.is_a?(FootnoteRef) ? atom.glyphs.first : atom
          if glyph.is_a?(Glyph) && previous && !atom.is_a?(FootnoteRef) && !same_line?(previous, glyph)
            # 次の行の頭に付く記号（** など）は次の行へ移す
            carried = []
            carried.unshift(lines.last.pop) while lines.last.last.is_a?(Mark) && lines.last.last.side == :open
            lines << carried
          end
          lines.last << atom
          previous = atom.is_a?(FootnoteRef) ? atom.glyphs.last : glyph if glyph.is_a?(Glyph)
        end
        lines.reject(&:empty?)
      end

      def footnote_head_line?(line)
        glyphs = glyphs_of(line)
        return false if glyphs.empty? || dominant_size(glyphs) >= @body_size * 0.92

        !footnote_head(glyphs, stringify(line)).nil?
      end

      # --- Phase: 脚注 ---

      # 本文より小さい字で、番号から始まる段落を脚注の本文とする。参照のある番号だけを脚注にする
      def footnote_body?(atoms, text)
        # 番号が太字で描かれると「**1.**」になるので、強調などの印を外した文字で見る
        text = stringify(atoms.reject { it.is_a?(Mark) && it.side != :inline }).strip
        glyphs = glyphs_of(atoms)
        return false if glyphs.empty? || dominant_size(glyphs) >= @body_size * 0.92

        number, rest = footnote_head(glyphs, text)
        # 番号の後ろに文字の無い段落（ページ番号の並んだ行など）は脚注ではない
        return false unless number && rest.match?(/[[:alpha:]]/)

        page = glyphs.first.page
        @found_bodies << [number, page]
        return false unless @labels

        label = @labels[:bodies][[number, page]]
        return false unless label

        @pending_notes << "[^#{label}]: #{rest}"
        true
      end

      # 脚注の本文の頭の番号と、その後ろの文字。「1.」「1)」「1 」の形のほか、TeX のように
      # 持ち上げた小さな番号のすぐ後に本文が続く形（「¹本テキストの…」）も番号とみなす
      def footnote_head(glyphs, text)
        match = text.match(FOOTNOTE_BODY_HEAD)
        return [match[1], text[match.end(0)..].strip] if match

        digits = glyphs.take_while { it.text.match?(/\A\d\z/) }
        following = glyphs[digits.size]
        return nil if digits.empty? || digits.size > 3 || following.nil?
        return nil unless digits.last.y - following.y >= following.size * 0.15

        number = digits.map(&:text).join
        [number, text.delete_prefix(number).strip]
      end

      # 番号が重なったとき（ページごとに 1 から振る PDF など）は、2 つめから「1-2」のように分ける。
      # 参照の見つかった番号の本文だけを脚注にする。OCR の参照（ページを記録してある）は同じページの本文に限る
      def footnote_labels
        counts = Hash.new(0)
        bodies = @found_bodies.uniq.select { |number, page| @found_refs.fetch(number, []).any? { it == :any || it == page } }.to_h do |number, page|
          counts[number] += 1
          [[number, page], counts[number] == 1 ? number : "#{number}-#{counts[number]}"]
        end
        { bodies: }
      end

      # 参照は、同じページの本文、なければ手前のページで最後の本文、なければ後ろの本文へ結ぶ。
      # OCR の参照（ocr_note_digit?）は同じページの本文にだけ結ぶ。本文の中のただの数字を参照にしないため
      def footnote_label_for(ref)
        return nil unless @labels

        candidates = @labels[:bodies].select { |(number, _page), _label| number == ref.number }
        return nil if candidates.empty?

        same = candidates.find { |(_number, page), _label| page == ref.page }
        return same&.last if ref.glyphs.first.font.nil?
        before = candidates.select { |(_number, page), _label| page < ref.page }.max_by { |(_number, page), _label| page }
        (same || before || candidates.first).last
      end

      # 脚注の本文は、次の見出しの手前（なければ章の終わり）にまとめて置く。ページの下で
      # 割り込ませると、ページをまたいだ段落をつなげなくなる
      def flush_notes(flow)
        return if @pending_notes.empty?

        flow.push(@pending_notes.join("\n\n"), :notes)
        @pending_notes = []
      end

      # --- Phase: 見出し ---

      def render_heading(element, flow)
        atoms = []
        element.children.each { collect_inline(it, atoms, plain: true) }
        text = stringify(atoms).gsub(/\s+/, ' ').strip
        return if text.empty?

        flush_notes(flow) if flow.top
        flow.push("#{'#' * heading_level(element.type)} #{text}", :heading)
      end

      # H1 が複数ある PDF（Word の書き出しなど）では、最初の H1 だけを章題にし、ほかを 1 段下げる
      def heading_level(type)
        level = HEADING_LEVELS.fetch(type)
        first = !@first_heading_done && level == 1
        @first_heading_done = true if level == 1
        first ? 1 : [level + @heading_offset, 6].min
      end

      def heading_offset(root)
        types = element_types(root)
        types.count(:H1) + types.count(:Title) > 1 ? 1 : 0
      end

      # --- Phase: リスト ---

      def render_list(element, flow)
        items = descendants(element, %i[LI]) { %i[L].include?(it.type) }
        text = items.map { list_item(it) }.join("\n")
        return if text.strip.empty?

        # ページで分かれたリストは 1 つにつなぐ
        if flow.last&.dig(:kind) == :list
          flow.replace_last("#{flow.blocks.last}\n#{text}")
        else
          flow.push(text, :list)
        end
      end

      def list_item(item)
        labels, body_children = item.children.partition { it.is_a?(StructureReader::Element) && it.type == :Lbl }
        marker = list_marker(labels)
        inner = Flow.new
        render_blocks(body_children, inner)
        flush(inner, loose: true)
        body = inner.blocks.join("\n\n").gsub(/\n(?=.)/, "\n#{' ' * (marker.length + 1)}")
        "#{marker} #{body}"
      end

      # 番号のラベル（1. や (1)）なら番号付き、記号（•・-）なら箇条書きにする
      def list_marker(labels)
        atoms = []
        labels.each { collect_inline(it, atoms, plain: true) }
        number = stringify(atoms).strip[/\A\(?(\d+)[.)）]?\z/, 1]
        number ? "#{number}." : '-'
      end

      # --- Phase: 表 ---

      def render_table(element, flow)
        captions = element.children.select { it.is_a?(StructureReader::Element) && it.type == :Caption }
        captions.each { render_block(it, flow) }

        rows = descendants(element, %i[TR]) { %i[THead TBody TFoot].include?(it.type) }.map do |row|
          descendants(row, %i[TH TD]).map { [it.type, table_cell(it)] }
        end
        rows.reject!(&:empty?)
        return if rows.empty?

        width = rows.map(&:size).max
        lines = rows.map { |cells| "| #{Array.new(width) { cells[it]&.last.to_s }.join(' | ')} |" }
        header_first = rows.first.any? { |type, _text| type == :TH }
        pages = glyphs_of_element(element).map(&:page)

        if (previous = flow.last) && previous[:kind] == :table && previous[:width] == width &&
           pages.first.to_i > previous[:last_page].to_i
          # ページで分かれた表。繰り返された見出しの行は落とす
          lines.shift if header_first && lines.first == previous[:header]
          flow.replace_last("#{flow.blocks.last}\n#{lines.join("\n")}", last_page: pages.last)
        else
          separator = "| #{Array.new(width, '---').join(' | ')} |"
          table = [lines.first, separator, *lines.drop(1)].join("\n")
          # 紙面から列を推定した表（経路 B）は、列の対応を確かめるよう促す（§7.2）
          table = "#{INFERRED_TABLE_NOTE}\n\n#{table}" if element.type == :InferredTable
          flow.push(table, :table, width:, header: lines.first, last_page: pages.last)
        end
      end

      def table_cell(cell)
        atoms = []
        cell.children.each { collect_inline(it, atoms) }
        stringify(atoms).gsub(/\s+/, ' ').strip.gsub('|', '\|')
      end

      # --- Phase: 引用 ---

      def render_quote(element, flow)
        inner = Flow.new
        render_blocks(element.children, inner)
        flush(inner, loose: true)
        text = inner.blocks.join("\n\n")
        return if text.strip.empty?

        flow.push(text.lines.map { it.strip.empty? ? ">\n" : "> #{it}" }.join, :quote)
      end

      # --- Phase: 図・数式・コード ---

      def render_figure(element, flow)
        alt = element.alt
        return flow.push(display_math(alt), :math) if display_math?(alt)
        return render_code_figure(element, flow) if code_figure?(element)

        boxes = own_images(element)
        return render_blocks(element.children, flow) if boxes.empty? && alt.nil?

        paths = boxes.filter_map { matching_image(it) }
        image = if paths.any?
                  paths.map { "![#{alt}](#{it})" }.join("\n")
                else
                  "<!-- 画像#{alt ? ": #{alt}" : ''} -->"
                end
        flow.push(image, :image)
        element.children.each { render_block(it, flow) if it.is_a?(StructureReader::Element) && it.type == :Caption }
      end

      def render_code_figure(element, flow)
        parts = descendants(element, %i[Caption Code]) { false }
        caption = parts.find { it.type == :Caption }
        parts.select { it.type == :Code }.each { render_code(it, caption, flow) }
      end

      def code_figure?(element) = descendants(element, %i[Code]) { false }.any?

      # 行内の数式は $…$、別行立ての数式は $$…$$ の形で Alt に入っている（§2.1）
      def inline_math?(alt) = alt.to_s.match?(/\A\$[^$].*\$\z/m)

      def display_math?(alt) = alt.to_s.match?(/\A\$\$.*\$\$\z/m)

      def display_math(alt) = "$$\n#{alt[2..-3].strip}\n$$"

      # 図の中の画像のうち、入れ子の図に属さないもの
      def own_images(element)
        element.children.flat_map do |child|
          case child
          in MarkedContent then child.images
          in StructureReader::Element if %i[Figure Formula].include?(child.type) then []
          in StructureReader::Element then own_images(child)
          end
        end
      end

      # 抜き出した画像のうち、描かれた位置が重なるものへ結ぶ
      def matching_image(box)
        placement = @images.find do |image|
          next false if @used_images[image] || image.page != box.page

          width = [box.right, image.right].min - [box.left, image.left].max
          height = [box.top, image.top].min - [box.bottom, image.bottom].max
          next false unless width.positive? && height.positive?

          smaller = [(box.right - box.left) * (box.top - box.bottom), (image.right - image.left) * (image.top - image.bottom)].min
          # 座標が整数で来ることがあるので fdiv で割る（/ だと 0 になる）
          smaller.positive? && (width * height).fdiv(smaller) > 0.5
        end
        return nil unless placement

        @used_images[placement] = true
        placement.path
      end

      # コードの囲み。行と字下げは座標から戻し、行番号は §7.1 の規則で外す
      def render_code(element, caption, flow)
        glyphs = glyphs_of_element(element)
        lines = code_lines(glyphs)
        return if lines.empty?

        char_width = code_char_width(lines.flatten)
        lines, start = strip_line_numbers(lines, char_width)
        lines, start = strip_margin_numbers(glyphs, char_width) || [lines, start] unless start
        origin = lines.filter_map { |line| line.find { !blank_glyph?(it) }&.x }.min || 0
        # OCR のコードは、番号の読み違いで連番にならない。番号の欄の位置で外し、左端も行ごとに測る
        if start.nil? && glyphs.first.font.nil?
          lines, origins = strip_gutter_numbers(lines, char_width) || strip_stray_numbers(lines, char_width) || [lines, nil]
        end
        text_lines = lines.map { code_line_text(it, origins&.fetch(it, origin) || origin, char_width) }
        text_lines.shift while text_lines.first&.empty?
        text_lines.pop while text_lines.last&.empty?
        return if text_lines.empty?

        title = caption && inline_text(caption).gsub(/\s+/, '').sub(/\A#{LayoutStructure::CODE_CAPTION_LABEL}/, '')
        if flow.last&.dig(:kind) == :code && title.nil? && glyphs.first.page > flow.last[:last_page]
          # ページで分かれたコード。キャプションは最初の 1 つにしか付かない
          body = flow.last[:lines] + text_lines
          flow.replace_last(code_fence(flow.last[:info], body), lines: body, last_page: glyphs.last.page)
          return
        end

        info, comment = code_info(title, start)
        flow.push(comment, :comment) if comment
        flow.push(code_fence(info, text_lines), :code, info:, lines: text_lines, last_page: glyphs.last.page)
      end

      def code_fence(info, lines)
        fence = lines.any? { it.include?('```') } ? '````' : '```'
        "#{fence}#{info}\n#{lines.join("\n")}\n#{fence}"
      end

      # ファイル名のキャプションは「```ruby:photoelectric.rb」の形にする。行番号が 1 以外から始まって
      # いたら「#L28」を添える。ファイル名が無ければ、元の開始番号をコメントで残す
      def code_info(title, start)
        offset = start && start != 1
        if title&.match?(/\A[\w.\-\/]+\.(\w+)\z/)
          extension = title[/\.(\w+)\z/, 1].downcase
          ["#{CODE_LANGUAGES.fetch(extension, extension)}:#{title}#{offset ? "#L#{start}" : ''}", nil]
        else
          comment = offset ? "<!-- pdf:read: 元の行番号は #{start} から -->" : nil
          comment = [title && "<!-- pdf:read: コードの見出し「#{title}」 -->", comment].compact.join("\n")
          ['', comment.empty? ? nil : comment]
        end
      end

      def code_lines(glyphs)
        lines = []
        glyphs.each do |glyph|
          previous = lines.last&.last
          previous && same_line?(previous, glyph) ? lines.last << glyph : lines << [glyph]
        end
        insert_blank_lines(lines)
      end

      # 空の行に何も描かない PDF もある。行送りの倍ほど空いたところへ空行を補う
      def insert_blank_lines(lines)
        steps = lines.each_cons(2).filter_map { |a, b| a.first.y - b.first.y if a.first.page == b.first.page }
        positive = steps.select(&:positive?).sort
        pitch = positive[positive.size / 2]
        return lines unless pitch&.positive?

        lines.each_with_index.flat_map do |line, index|
          following = lines[index + 1]
          gap = following && following.first.page == line.first.page ? line.first.y - following.first.y : 0
          [line, *Array.new([gap.fdiv(pitch).round - 1, 0].max) { [] }]
        end
      end

      def code_char_width(glyphs)
        widths = glyphs.select { it.text.match?(/\A[\x21-\x7E]\z/) }.map(&:width).sort
        widths.empty? ? @body_size * 0.5 : widths[widths.size / 2]
      end

      # 1 ずつ増える連番が全行の頭にあれば外す。始まりは 1 でなくてよい（抜粋の 28・29・30）。
      # 番号の無い行は折り返した続きとして前の行へつなぐ。番号が飛ぶ・重なる・一部にしか無い形は
      # コードの一部かもしれないので外さない（論点 4）
      def strip_line_numbers(lines, char_width)
        heads = lines.map { leading_number(it, char_width) }
        numbered = heads.compact
        return [lines, nil] if numbered.size < 2 || heads.first.nil?
        return [lines, nil] unless numbered.each_cons(2).all? { |a, b| b[:number] == a[:number] + 1 }

        rights = numbered.map { it[:right] }
        lefts = numbered.map { it[:left] }
        return [lines, nil] unless rights.max - rights.min <= char_width || lefts.max - lefts.min <= char_width * 0.5

        stripped = lines.each_with_index.each_with_object([]) do |(line, index), result|
          if heads[index] then result << heads[index][:rest]
          elsif line.empty? then result << []
          else result.last.concat(line)
          end
        end
        [stripped, numbered.first[:number]]
      end

      # 行番号を構造ツリーから外した PDF（vs build の PDF は aria-hidden にしている）では、番号は
      # コードの左にタグの無い文字として描かれる。それを行の頭に戻してから、同じ規則で外す。
      # 開始番号（#L28）と、折り返した行の見分けが戻る
      def strip_margin_numbers(glyphs, char_width)
        numbers = glyphs.group_by(&:page).flat_map do |page, on_page|
          left = on_page.map(&:x).min
          top = on_page.map(&:y).max
          bottom = on_page.map(&:y).min
          Array(@unmarked[page]).select do |glyph|
            glyph.text.match?(/\A\d+\z/) && glyph.y.between?(bottom - 1, top + 1) &&
              glyph.right <= left + 0.5 && left - glyph.right < char_width * 4
          end
        end
        return nil if numbers.empty?

        ordered = (glyphs + numbers).sort_by { [it.page, -it.y.round(1), it.x] }
        lines, start = strip_line_numbers(code_lines(ordered), char_width)
        start ? [lines, start] : nil
      end

      # OCR のコードの行番号を、番号の欄の位置で外す（pdf-read-ocr-improvement-notes.md §4.13）。番号は欄の右端に
      # そろえて描かれ、コードはその右の決まった位置から始まる。読み違えた番号（11 を「1」、17 を「L}」）も、
      # 番号の欄を縦に読んだ崩れ（「ee2」「まき」）も、この欄に収まる。欄の右端はスキャンの傾きでページの
      # 上と下で数 pt ずれるので、番号の行の右端に直線を当てはめて測る。
      # 欄だけの行（番号だけの空行と崩れ）は捨て、空行は残った行の間隔から補い直す。番号が 3 行未満なら外さない
      # @return [Array(Array<Array<Glyph>>, Hash{Array<Glyph> => Float}), nil] 行と、行ごとの左端
      def strip_gutter_numbers(lines, char_width)
        rows = lines.reject(&:empty?)
        heads = rows.filter_map do |row|
          head = leading_number(row, char_width)
          head && { row:, right: head[:right], code: head[:rest].find { !blank_glyph?(it) } }
        end
        return nil if heads.size < 3

        edges = heads.group_by { it[:row].first.page }.transform_values { gutter_edge(it, char_width) }
        edge_at = ->(row) { edges.fetch(row.first.page, edges.values.first).call(row.first.y) }
        # 番号とコードの間は、行頭から書いた行（字下げの無い行）で狭い。いちばん狭い 1 行は読みの揺れで
        # 外れることがあるので、そこから 0.6 字以内に集まる行の中央値をとる
        gaps = heads.filter_map { it[:code] && (it[:code].x - edge_at.(it[:row])) }.select { it >= char_width * 0.3 }.sort
        return nil if gaps.empty?

        unindented = gaps.take_while { it <= gaps.first + (char_width * 0.6) }
        offset = unindented[unindented.size / 2]

        origins = {}.compare_by_identity
        stripped = rows.filter_map do |row|
          rest = row.drop_while { it.x + (it.width / 2) < edge_at.(row) + (offset / 2) }
          next if rest.all? { blank_glyph?(it) }

          rest.tap { origins[it] = edge_at.(row) + offset }
        end
        [insert_blank_lines(stripped), origins]
      end

      # 番号の欄を読めなかった OCR のコード（高い解像度では、薄い番号を読み落とす）。左端は、2 行以上が
      # そろういちばん左の位置にする。そこより左へ飛び出した行頭の数字（コードとつなげて読んだ番号「2#」）は外す
      # @return [Array(Array<Array<Glyph>>, Hash{Array<Glyph> => Float}), nil]
      def strip_stray_numbers(lines, char_width)
        lefts = lines.filter_map { |line| line.find { !blank_glyph?(it) }&.x }.sort
        origin = lefts.find { |left| lefts.count { (it - left).between?(0, char_width * 0.5) } >= 2 }
        return nil unless origin

        origins = {}.compare_by_identity
        stripped = lines.map do |line|
          digits = line.take_while { it.text.match?(/\A\d\z/) && it.right <= origin }
          line.drop(digits.size).tap { origins[it] = origin }
        end
        [stripped, origins]
      end

      # 番号の欄の右端を、縦の位置から求める式。番号の行の右端に直線を当てはめ、1 字より外れた行（番号の
      # 読み違い）を除いて当てはめ直す。番号の行が 3 行未満のページは傾きを見ず、右端の中央値を使う
      def gutter_edge(heads, char_width)
        points = heads.map { [it[:row].first.y, it[:right]] }
        fit = lambda do |pairs|
          if pairs.size < 3
            median = pairs.map(&:last).sort[pairs.size / 2]
            next ->(_y) { median }
          end

          mean_y = pairs.sum(&:first) / pairs.size
          mean_right = pairs.sum(&:last) / pairs.size
          spread = pairs.sum { (it.first - mean_y)**2 }
          slope = spread.zero? ? 0.0 : pairs.sum { (it.first - mean_y) * (it.last - mean_right) } / spread
          ->(y) { mean_right + (slope * (y - mean_y)) }
        end
        first = fit.(points)
        kept = points.select { |y, right| (right - first.(y)).abs <= char_width }
        fit.(kept.size >= 3 ? kept : points)
      end

      def leading_number(line, char_width)
        return nil if line.empty? # 行送りから補った空行

        # 番号のすぐ後のコードが数字で始まる（34 の行の「3.times」）ことがあるので、隙間で切る
        digits = line.chunk_while { |a, b| b.x - a.right <= char_width * 0.3 }.first
                     .take_while { it.text.match?(/\A\d+\z/) }
        return nil if digits.empty?

        rest = line.drop(digits.size)
        # 「1: @import」のように番号の直後にコロンを置く本（pLaTeX の listings など）もある。コロンも番号の側に含める
        separator = rest.first if rest.first&.text == ':' && rest.first.x - digits.last.right <= char_width * 0.3
        rest = rest.drop(1) if separator
        number_end = (separator || digits.last).right
        return nil if rest.any? && !blank_glyph?(rest.first) && rest.first.x - number_end < char_width * 0.5

        { number: digits.map(&:text).join.to_i, rest:, left: digits.first.x, right: digits.last.right }
      end

      def code_line_text(glyphs, origin, char_width)
        text = +''
        previous = nil
        glyphs.each do |glyph|
          if previous.nil?
            text << (' ' * [(glyph.x - origin).fdiv(char_width).round, 0].max) unless blank_glyph?(glyph)
          elsif same_line?(previous, glyph)
            text << (' ' * [(glyph.x - previous.right).fdiv(char_width).round, 0].max)
          end
          text << glyph.text.tr("\u00A0", ' ')
          previous = glyph
        end
        text.rstrip
      end

      def blank_glyph?(glyph) = glyph.text.tr("\u00A0", ' ').strip.empty?

      # --- Phase: 行内 ---

      # plain は見出しとラベル用。強調の記号を付けない
      def collect_inline(node, atoms, plain: false)
        case node
        in MarkedContent then add_glyphs(node.glyphs, atoms)
        in StructureReader::Element => element
          return add_actual_text(element, atoms) if element.actual_text

          case element.type
          in type if DROPPED_TYPES.include?(type) then nil
          in :Strong | :Em unless plain
            mark = element.type == :Strong ? '**' : '*'
            atoms << Mark.new(mark, :open)
            element.children.each { collect_inline(it, atoms, plain:) }
            atoms << Mark.new(mark, :close)
          in :Code then collect_inline_code(element, atoms)
          in :Ruby then collect_ruby(element, atoms)
          in :Figure | :Formula then collect_inline_figure(element, atoms, plain:)
          else element.children.each { collect_inline(it, atoms, plain:) }
          end
        end
      end

      # 中に ` があれば、中に無い長さの ` で囲む。端が ` なら空白を挟む（CommonMark の決まり）
      def collect_inline_code(element, atoms)
        inner = []
        element.children.each { collect_inline(it, inner, plain: true) }
        content = stringify(inner)
        runs = content.scan(/`+/).map(&:size)
        fence = '`' * (1..).find { !runs.include?(it) }
        pad = content.start_with?('`') || content.end_with?('`') ? ' ' : ''
        atoms.push(Mark.new(fence + pad, :open), *inner, Mark.new(pad + fence, :close))
      end

      # ルビは {親文字|ルビ} にする
      def collect_ruby(element, atoms)
        base = []
        ruby = []
        element.children.each do |child|
          next if child.is_a?(StructureReader::Element) && child.type == :RP

          target = child.is_a?(StructureReader::Element) && child.type == :RT ? ruby : base
          collect_inline(child, target, plain: true)
        end
        reading = stringify(ruby).gsub(/\s+/, '')
        return atoms.concat(base) if reading.empty?

        atoms.push(Mark.new('{', :open), *base, Mark.new("|#{reading}}", :close))
      end

      def collect_inline_figure(element, atoms, plain:)
        if inline_math?(element.alt) || display_math?(element.alt)
          atoms << Mark.new(element.alt, :inline)
        elsif (paths = own_images(element).filter_map { matching_image(it) }).any?
          atoms.concat(paths.map { Mark.new("![#{element.alt}](#{it})", :inline) })
        else
          element.children.each { collect_inline(it, atoms, plain:) }
        end
      end

      # ActualText は、描かれた文字の代わりに読む文字（合字・画像にした文字など）。
      # 位置は描かれた文字のものを借りる
      def add_actual_text(element, atoms)
        glyphs = glyphs_of_element(element)
        first = glyphs.first
        if first
          atoms << Glyph.new(text: element.actual_text, x: first.x, y: first.y,
                             width: glyphs.last.right - first.x, size: first.size, page: first.page)
        else
          atoms << Mark.new(element.actual_text, :inline)
        end
      end

      # 小さく持ち上がった数字は脚注の参照の候補にする
      def add_glyphs(glyphs, atoms)
        glyphs.each_with_index do |glyph, index|
          base = atoms.reverse_each.find { it.is_a?(Glyph) }
          last = atoms.last
          if last.is_a?(FootnoteRef) && glyph.text.match?(/\A\d+\z/) && glyph.x - last.glyphs.last.right < glyph.size * 0.3 &&
             (glyph.y - last.glyphs.last.y).abs < 0.5
            atoms[-1] = last.with(number: last.number + glyph.text, glyphs: last.glyphs + [glyph])
          elsif superscript_digit?(glyph, base) || ocr_note_digit?(glyph, base, glyphs[index + 1])
            atoms << FootnoteRef.new(number: glyph.text, page: glyph.page, glyphs: [glyph])
          else
            atoms << glyph
          end
        end
      end

      # 数字や数式の字（TeX の CMMI など）の直後に持ち上がった数字は指数（10²・r¹）で、脚注の参照では
      # ない。参照は語の後に付く
      def superscript_digit?(glyph, base)
        return false unless base && glyph.text.match?(/\A\d+\z/) && glyph.page == base.page
        return false if base.text.match?(/\d\z/) || base.font&.name.to_s.match?(LayoutStructure::MATH_FONT_NAME)

        rise = glyph.y - base.y
        glyph.size <= base.size * 0.9 && rise >= base.size * 0.15 && rise < base.size
      end

      # OCR の字は行の中で高さがそろう（Tesseract は語の位置しか返さない）ので、持ち上がりでは参照を見分け
      # られない。和文の直後の 1 桁の数字で、後ろが句読点・閉じ括弧（「!」と読み違えたものも）か段落の終わりのものを
      # 候補にする（「記しています1。」）。同じページに同じ番号の脚注の本文があるときだけ参照になる（footnote_label_for）
      def ocr_note_digit?(glyph, base, following)
        glyph.font.nil? && base && glyph.page == base.page && glyph.text.match?(/\A\d\z/) &&
          wide?(base.text[-1]) && (following.nil? || following.text.match?(/\A[。、．，」』）)!！]/))
      end

      # 原子の列を文字列にする。行の変わり目は、和文なら詰め、欧文なら空白にする
      def stringify(atoms)
        spread = line_spreads(atoms)
        text = +''
        pending = []
        previous = nil
        after_inline = false
        atoms.each do |atom|
          case atom
          in Glyph
            if previous then text << separator(previous, atom, spread)
            elsif after_inline && !wide?(atom.text[0]) then text << ' '
            end
            text << pending.join << atom.text.tr("\u00A0", ' ')
            pending.clear
            previous = atom
            after_inline = false
          in Mark(side: :open) then pending << atom.text
          in Mark(side: :close) then pending.any? ? pending.pop : text << atom.text
          in Mark(side: :inline)
            text << ' ' if previous && !wide?(previous.text[-1])
            text << pending.join << atom.text
            pending.clear
            previous = nil
            after_inline = true
          in FootnoteRef
            (@found_refs[atom.number] ||= []) << (atom.glyphs.first.font.nil? ? atom.page : :any)
            label = footnote_label_for(atom)
            text << (label ? "[^#{label}]" : atom.number)
            previous = atom.glyphs.last
          end
        end
        text.gsub(/ {2,}/, ' ')
      end

      # 同じ行の隙間を空白とみなすか。欧文どうしは字の 0.15 倍より広ければ空白にする。
      # 和文が絡むところは、両端揃えで広がった字間（spread）を引いてから字の 0.2 倍で見る。
      # 和欧間のアキ（0.125 字前後）や両端揃えの字間（実測で最大 0.25 字）を空白にしないため。
      # 本物の空白は 0.28 字ほどある
      def separator(previous, glyph, spread = {})
        if same_line?(previous, glyph)
          gap = glyph.x - previous.right
          size = [previous.size, glyph.size].min
          before = wide?(previous.text[-1])
          after = wide?(glyph.text[0])
          return '' if before && after
          return gap > size * 0.15 ? ' ' : '' unless before || after

          gap - spread.fetch(line_key(glyph), 0.0) > size * 0.2 ? ' ' : ''
        elsif previous.text.end_with?('-') || wide?(previous.text[-1]) || wide?(glyph.text[0])
          ''
        else
          ' '
        end
      end

      # 行ごとの、和文どうしの字間の中央値。両端揃えで行ごとに字間が広がるので、その幅を測る
      def line_spreads(atoms)
        glyphs_of(atoms).chunk_while { same_line?(_1, _2) }.to_h do |line|
          gaps = line.each_cons(2).filter_map do |a, b|
            b.x - a.right if wide?(a.text[-1]) && wide?(b.text[0]) && b.x >= a.x
          end.sort
          [line_key(line.first), gaps.empty? ? 0.0 : [gaps[gaps.size / 2], 0.0].max]
        end
      end

      def line_key(glyph) = [glyph.page, glyph.y.round]

      def same_line?(previous, glyph)
        previous.page == glyph.page && (previous.y - glyph.y).abs <= [previous.size, glyph.size].min * 0.5
      end

      def wide?(char) = char.to_s.match?(WIDE_CHAR)

      # --- Phase: 木を辿る小道具 ---

      def inline_text(element)
        atoms = []
        collect_inline(element, atoms, plain: true)
        stringify(atoms).strip
      end

      def glyphs_of(atoms)
        atoms.flat_map do |atom|
          case atom
          in Glyph then [atom]
          in FootnoteRef then atom.glyphs
          else []
          end
        end
      end

      def glyphs_of_element(element)
        element.children.flat_map do |child|
          case child
          in MarkedContent then child.glyphs
          in StructureReader::Element then DROPPED_TYPES.include?(child.type) ? [] : glyphs_of_element(child)
          end
        end
      end

      def all_glyphs(root) = root ? glyphs_of_element(root) : []

      # ページごとの本文の左端（本文の大きさの行の頭で、いちばん多い位置）
      def left_edges(glyphs)
        glyphs.chunk_while { same_line?(_1, _2) }
              .select { (it.first.size - @body_size).abs < 0.2 }
              .group_by { it.first.page }
              .transform_values { |lines| lines.map { it.first.x.round(1) }.tally.max_by { |_x, count| count }.first }
      end

      # 2 行以上の段落の過半が 1 行目を下げていれば、段落の頭を下げる組み方とみなす
      def indent_style?(root)
        paragraphs = descendants_all(root, :P).filter_map do |paragraph|
          lines = glyphs_of_element(paragraph).chunk_while { same_line?(_1, _2) }.to_a
          next if lines.size < 2

          first = lines.first.first
          first.x - lines.drop(1).map { it.first.x }.min > first.size * 0.5
        end
        paragraphs.count(true) > paragraphs.count(false)
      end

      def descendants_all(element, type)
        element.children.flat_map do |child|
          next [] unless child.is_a?(StructureReader::Element)

          [*(child.type == type ? [child] : []), *descendants_all(child, type)]
        end
      end

      def dominant_size(glyphs) = glyphs.map { it.size.round(1) }.tally.max_by { |_size, count| count }.first

      # 指定の型の子孫を集める。through が真の要素と入れ物は、中まで辿る
      def descendants(element, types, &through)
        element.children.flat_map do |child|
          next [] unless child.is_a?(StructureReader::Element)
          next [child] if types.include?(child.type)
          next descendants(child, types, &through) if CONTAINER_TYPES.include?(child.type) || through&.call(child)

          []
        end
      end

      def element_types(element)
        element.children.flat_map do |child|
          child.is_a?(StructureReader::Element) ? [child.type, *element_types(child)] : []
        end
      end
    end
  end
end
