# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/table_converter.rb
# ================================================================
# 責務:
#   拡張パイプテーブル（横結合 colspan・複数行ヘッダー）の変換を一元化する。
#   素テーブルの横取り・コンテナ（long-table / rotate-table）内テーブルの変換・
#   rotate-table の版面自動フィット（scale/height 自動算出）を担う。
#
# 仕様: docs/specs/table-colspan-spec.md
#
# 設計の要点:
#   - 記法 `||`（ゼロ幅セル）は直前セルへのマージ（colspan）。空白のみのセルは本物の空セル。
#   - 区切り行より上のすべての行を <thead> の複数 <tr> に一般化する。
#   - セル内は Kramdown でレンダリングし、生 HTML（数式 SVG の <img> 等）を保持する。
#   - 素テーブルの横取りは「`||` を含む／区切り行が 2 行目にない」表のみに限定し、
#     通常の GFM テーブルには一切触れない（VFM に委ねる）。
# ================================================================

require_relative '../common'
require_relative '../masking'
require_relative '../units'
require_relative 'markdown_utils'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # 拡張パイプテーブル変換（統合テーブル変換）
      module TableConverter
        # セルの値オブジェクト。colspan は結合数（1=非結合）。
        Cell = Data.define(:content, :colspan)

        # 解析済みテーブルモデル。header_rows/body_rows は Cell 配列の配列、
        # alignments は列ごとの整列（'left'/'center'/'right'/nil）の配列。
        Table = Data.define(:header_rows, :body_rows, :alignments)

        # セル内エスケープ `\|` を退避する一時マーカー（分割規則から除外するため）。
        PIPE_PLACEHOLDER = "\u{E000}"

        # --- 版面自動フィット（§6.2）の凍結定数 ---
        # セル左右パディングの中庸値（mm）。table.css の padding clamp（0.6〜1.4mm）＋罫線幅の中間。
        CELL_PAD_MM = 1.2
        # 文字幅推定（プロポーショナル欧文等）の誤差を吸収する安全率。
        SAFETY = 0.95
        # 縮小率の下限。これ未満は可読性が失われるため止め、著者に縮小限界の判断を委ねる。
        SCALE_MIN = 0.30

        module_function

        # 拡張パイプテーブル 1 個を HTML 化する。不成立（テーブルでない）なら nil。
        # @param md_text [String] テーブルブロック 1 個分のテキスト
        # @return [String, nil]
        def pipe_table_to_html(md_text)
          table = parse(md_text)
          return nil unless table

          render_table(table)
        end

        # <div class="… CLASS …">…</div> の内側テーブルを拡張変換する。
        # テーブルブロックは常に自前パーサ（不成立ブロックのみ Kramdown へフォールバック）、
        # 非テーブル区間（キャプション段落等）は Kramdown で描画し、出現順に結合する。
        # class_name が 'rotate-table' かつ page_cfg があれば版面自動フィットを style へマージする。
        def convert_container_inner(content, class_name, page_cfg: nil)
          pattern = %r{<div\s+([^>]*\bclass="[^"]*\b#{Regexp.escape(class_name)}\b[^"]*"[^>]*)>\s*(.*?)\s*</div>}m
          content.gsub(pattern) do
            attrs = ::Regexp.last_match(1)
            inner = ::Regexp.last_match(2)

            html  = render_container_inner(inner)
            attrs = merge_rotate_style(attrs, inner, page_cfg) if class_name == 'rotate-table' && page_cfg

            "<div #{attrs}>\n#{html}\n</div>"
          end
        end

        # コンテナ外の素パイプテーブルのうち、拡張記法（colspan / 複数行ヘッダー）を
        # 含むものだけを横取りして生 <table> HTML へ変換する（§4）。
        # コードフェンス・インラインコード内は Masking で退避して誤検出を防ぐ。
        # @return [Array(String, Integer)] [変換後テキスト, 変換件数]
        def intercept_extended_tables(content)
          protected_text, spans = Masking.protect_code(content)

          out   = +''
          count = 0
          lines = protected_text.lines
          i = 0

          while i < lines.size
            unless table_block_line?(lines[i])
              out << lines[i]
              i += 1
              next
            end

            # --- テーブルブロックを収集 ---
            j = i
            j += 1 while j < lines.size && table_block_line?(lines[j])
            block = lines[i...j].join

            html = intercept_candidate?(block) ? pipe_table_to_html(block) : nil
            if html
              count += 1
              out << "\n" unless out.empty? || out.end_with?("\n\n")
              out << html << "\n\n"
            else
              out << block
            end
            i = j
          end

          [Masking.restore_code(out, spans), count]
        end

        # rotate-table の版面自動フィット（§6.2）。純粋関数（CONFIG を直接参照しない）。
        # @param table_model [Table] 解析済みテーブル
        # @param page_cfg [Hash] プリセット適用・単位正規化済みの page 設定（シンボルキー）
        # @return [Hash] { 'rotate-table-height' => 'Xmm', 'rotate-table-scale' => 'Y%' }
        def estimate_rotate_style(table_model, page_cfg)
          page_w, page_h = Common.resolve_page_size(page_cfg).map { Units.length_to_mm(it) }
          content_w = page_w - mm(page_cfg[:margin_inner]) - mm(page_cfg[:margin_outer])
          content_h = page_h - mm(page_cfg[:margin_top]) - mm(page_cfg[:margin_bottom])
          height = { 'rotate-table-height' => "#{content_h.round(1)}mm" }

          font_mm        = Units.length_to_mm(page_cfg[:base_font_size])
          line_height_mm = Units.length_to_mm(page_cfg[:base_line_height])
          return height unless font_mm && line_height_mm

          table_w, table_h = table_dimensions_mm(table_model, font_mm, line_height_mm)
          return height if table_w.zero? || table_h.zero?

          # -90°回転で幅↔高さが入れ替わる。回転後にページ版面へ収める縮尺。
          scale = [content_h / table_w, content_w / table_h, 1.0].min * SAFETY
          scale = scale.clamp(SCALE_MIN, 1.0)
          scale = (scale / 0.05).floor * 0.05 # 5% 刻みへ切り捨て

          height.merge('rotate-table-scale' => "#{(scale * 100).round}%")
        end

        # =============================================================
        # 内部: 解析
        # =============================================================

        # テーブルテキストを Table モデルへ解析する。不成立なら nil。
        def parse(md_text)
          lines = md_text.to_s.split(/\r?\n/).map(&:rstrip).reject(&:empty?)
          return nil if lines.size < 2

          sep = lines.index { separator_line?(it) }
          return nil if sep.nil? || sep.zero? # ヘッダー行なし／区切り行なしは不成立

          alignments = split_raw_parts(lines[sep]).reject { it == '' }.map { align_of(it) }
          header = lines[0...sep].map { build_cells(split_raw_parts(it)) }
          body   = (lines[(sep + 1)..] || []).map { build_cells(split_raw_parts(it)) }

          Table.new(header_rows: header, body_rows: body, alignments:)
        end
        private_class_method :parse

        # 区切り行か（`-` を 1 つ以上含み、整列記号・パイプ・空白のみで構成される行）。
        def separator_line?(line)
          line.match?(/^\s*\|?[\s:\-|]+\|?\s*$/) && line.include?('-')
        end
        private_class_method :separator_line?

        # 行をセルの生文字列配列へ分割する（§3.2）。
        # `\|` を退避 → `split('|', -1)` → 行頭/行末パイプを 1 つずつ除去。
        # 退避したパイプは Kramdown 描画後に復元する（`a \| b` を Kramdown がミニテーブルと
        # 誤認しないよう、素の `|` へ戻すのはセル描画の最後段・render_cell / display_width_em）。
        def split_raw_parts(line)
          parts = line.gsub('\\|', PIPE_PLACEHOLDER).split('|', -1)
          parts.shift if parts.first == '' # 行頭のパイプ
          parts.pop   if parts.last  == '' # 行末のパイプ（`||` 終端なら残り 1 つがマージマーカー）
          parts
        end
        private_class_method :split_raw_parts

        # 生文字列配列から Cell 配列を構築する（§3.3）。
        # ゼロ幅セル（空文字列・空白すら含まない）は直前セルへマージ（colspan +1）。
        # 行頭のゼロ幅セルはマージ先が無いため空セルとして扱う。空白のみは本物の空セル。
        def build_cells(raw_parts)
          raw_parts.each_with_object([]) do |raw, cells|
            if raw == '' && !cells.empty?
              last = cells[-1]
              cells[-1] = last.with(colspan: last.colspan + 1)
            else
              cells << Cell.new(content: raw.strip, colspan: 1)
            end
          end
        end
        private_class_method :build_cells

        # 区切り行のセル記号から列整列を決定する（§3.5）。
        def align_of(spec)
          s = spec.strip
          left  = s.start_with?(':')
          right = s.end_with?(':')
          if left && right then 'center'
          elsif right then 'right'
          elsif left then 'left'
          end
        end
        private_class_method :align_of

        # =============================================================
        # 内部: HTML 組み立て
        # =============================================================

        # Table モデルを §5 の正規体裁の HTML 文字列へ組み立てる。
        def render_table(table)
          html = +"<table>\n  <thead>\n"
          table.header_rows.each { html << render_row(it, table.alignments, 'th') << "\n" }
          html << "  </thead>\n"
          unless table.body_rows.empty?
            html << "  <tbody>\n"
            table.body_rows.each { html << render_row(it, table.alignments, 'td') << "\n" }
            html << "  </tbody>\n"
          end
          html << '</table>'
          html
        end
        private_class_method :render_table

        # 1 行分のセルを <tr> へ描画する。
        # colspan 1 のセルには整列指定のある列でインラインスタイルを付与し、
        # colspan 2 以上のセルにはスタイルを付与しない（中央寄せは CSS が担う・§3.5）。
        def render_row(cells, alignments, tag)
          col = 0
          rendered = cells.map do |cell|
            align = cell.colspan == 1 ? alignments[col] : nil
            col += cell.colspan
            attrs = +''
            attrs << " colspan=\"#{cell.colspan}\"" if cell.colspan > 1
            attrs << " style=\"text-align: #{align}\"" if align
            "<#{tag}#{attrs}>#{render_cell(cell)}</#{tag}>"
          end
          "    <tr>#{rendered.join}</tr>"
        end
        private_class_method :render_row

        # セル内文字列を Kramdown でレンダリングし、単一 <p> ラッパなら中身だけを採る（§3.6）。
        # 空セルは Kramdown を通さず空文字列のまま。生 HTML（数式 SVG の <img> 等）は保持される。
        def render_cell(cell)
          text = cell.content
          return '' if text.empty?

          html = MarkdownUtils.render_markdown_to_html(text).strip
          unwrapped =
            if html.start_with?('<p>') && html.end_with?('</p>') && html.scan('<p>').size == 1
              html[3...-4]
            else
              html
            end
          unwrapped.gsub(PIPE_PLACEHOLDER, '|') # 退避したエスケープパイプを素の `|` へ復元
        end
        private_class_method :render_cell

        # =============================================================
        # 内部: コンテナ内変換
        # =============================================================

        # コンテナ内側 Markdown をテーブルブロックと非テーブル区間に分け、
        # テーブルは拡張パーサ（不成立は Kramdown）、非テーブルは Kramdown で描画して結合する。
        def render_container_inner(inner)
          segment_blocks(inner).filter_map do |kind, text|
            html = kind == :table ? (pipe_table_to_html(text) || render_prose(text)) : render_prose(text)
            html unless html.to_s.strip.empty?
          end.join("\n")
        end
        private_class_method :render_container_inner

        # 行を [:table, text] / [:prose, text] のセグメント列へ分ける（出現順を保つ）。
        def segment_blocks(inner)
          lines = inner.lines
          segments = []
          i = 0
          while i < lines.size
            table = table_block_line?(lines[i])
            j = i
            j += 1 while j < lines.size && table_block_line?(lines[j]) == table
            segments << [table ? :table : :prose, lines[i...j].join]
            i = j
          end
          segments
        end
        private_class_method :segment_blocks

        # 非テーブル区間を Kramdown で HTML 化する（空なら空文字列）。
        def render_prose(text)
          stripped = text.strip
          return '' if stripped.empty?

          MarkdownUtils.render_markdown_to_html(stripped).strip
        end
        private_class_method :render_prose

        # =============================================================
        # 内部: 素テーブル横取り判定
        # =============================================================

        # 行頭空白 3 文字以内で `|` から始まる行か（4 文字以上はインデントコードブロック・§3.1）。
        def table_block_line?(line)
          line.match?(/\A {0,3}\|/)
        end
        private_class_method :table_block_line?

        # 横取り対象か（§4.1）: 区切り行が index 1 以上にあり、かつ
        # (a) いずれかの行に colspan マージがある、または (b) 区切り行が index 2 以上（複数行ヘッダー）。
        def intercept_candidate?(block)
          lines = block.split(/\r?\n/).map(&:rstrip).reject(&:empty?)
          sep = lines.index { separator_line?(it) }
          return false if sep.nil? || sep < 1
          return true if sep >= 2

          lines.each_with_index.any? do |line, idx|
            idx != sep && build_cells(split_raw_parts(line)).any? { it.colspan > 1 }
          end
        end
        private_class_method :intercept_candidate?

        # =============================================================
        # 内部: rotate-table 自動フィット
        # =============================================================

        # div の style 属性へ自動算出値をマージする。著者指定の scale/shift-y は上書きしない。
        def merge_rotate_style(attrs, inner, page_cfg)
          model = first_table_model(inner)
          return attrs unless model

          inject_style_vars(attrs, estimate_rotate_style(model, page_cfg))
        end
        private_class_method :merge_rotate_style

        # コンテナ内側の最初のテーブルブロックを解析してモデルを返す（無ければ nil）。
        def first_table_model(inner)
          lines = inner.lines
          i = lines.index { table_block_line?(it) }
          return nil unless i

          j = i
          j += 1 while j < lines.size && table_block_line?(lines[j])
          parse(lines[i...j].join)
        end
        private_class_method :first_table_model

        # style 属性文字列へ CSS 変数を注入する。
        # 著者が既に書いた変数（--rotate-table-height 以外）は自動値で上書きしない（§6.3）。
        def inject_style_vars(attrs, auto)
          vars = parse_style_declarations(attrs[/\bstyle="([^"]*)"/, 1].to_s)
          auto.each do |name, value|
            prop = "--#{name}"
            next if vars.key?(prop) && prop != '--rotate-table-height'

            vars[prop] = value
          end
          new_style = vars.map { |prop, value| "#{prop}:#{value};" }.join(' ')

          if attrs.include?('style="')
            attrs.sub(/\bstyle="[^"]*"/, "style=\"#{new_style}\"")
          else
            "#{attrs} style=\"#{new_style}\""
          end
        end
        private_class_method :inject_style_vars

        # style 宣言文字列を { プロパティ => 値 } の順序付き Hash へ分解する。
        def parse_style_declarations(style)
          style.scan(/([^:;]+):([^;]+);?/).each_with_object({}) do |(prop, value), memo|
            memo[prop.strip] = value.strip
          end
        end
        private_class_method :parse_style_declarations

        # テーブルの推定寸法（幅 mm・高さ mm）を返す（§6.2）。
        def table_dimensions_mm(table, font_mm, line_height_mm)
          all_rows = table.header_rows + table.body_rows
          n_cols   = table.alignments.size
          col_w_em = Array.new(n_cols, 0.0)

          table_h = all_rows.sum do |cells|
            col = 0
            max_lines = 1
            cells.each do |cell|
              max_lines = [max_lines, br_line_count(cell.content)].max
              col_w_em[col] = [col_w_em[col], display_width_em(cell.content)].max if cell.colspan == 1 && col < n_cols
              col += cell.colspan
            end
            line_height_mm * max_lines + 2 * CELL_PAD_MM
          end

          table_w = col_w_em.sum { |em| em * font_mm + 2 * CELL_PAD_MM }
          [table_w, table_h]
        end
        private_class_method :table_dimensions_mm

        # セル内の <br> 区切り行数（最小 1）。
        def br_line_count(text) = text.to_s.split(%r{<br\s*/?>}i).size.clamp(1, Float::INFINITY).to_i
        private_class_method :br_line_count

        # セル表示幅（em）。インライン記法・HTML タグを除去し、ASCII=0.5em・その他=1.0em。
        # <br> で分割した最長行を採る。
        def display_width_em(text)
          text.to_s.gsub(PIPE_PLACEHOLDER, '|').split(%r{<br\s*/?>}i).map do |segment|
            plain = segment.gsub(/<[^>]+>/, '').gsub(/[*_`~]/, '')
            plain.chars.sum { |ch| ch.ascii_only? ? 0.5 : 1.0 }
          end.max || 0.0
        end
        private_class_method :display_width_em

        # CSS 長さを mm の Float へ（解釈不能は 0.0）。
        def mm(value) = Units.length_to_mm(value) || 0.0
        private_class_method :mm
      end
    end
  end
end
