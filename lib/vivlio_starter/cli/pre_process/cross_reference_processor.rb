# frozen_string_literal: true

# ================================================================
# クロスリファレンス（相互参照）機能の部品を提供する。
#
# 機能:
#   - ラベル定義の収集（** タイトル @id ** 形式）
#   - キャプション付きブロック（図・表・コード）の HTML 変換
#   - 本文中の @id 参照をリンクに置換
#   - ラベルマップ構築と重複チェック
#
# ここにあるのは部品だけで、章をまたぐ全体の段取り（ラベル収集 → マップ構築 →
# HTML 化 → 参照置換 → 孤立ラベル検出）は
# PreProcessCommands.process_cross_references_for_files（pre_process.rb）が持つ。
# 実ビルドが通るのもそちらの 1 経路のみである。
# ================================================================

require 'cgi'
require_relative '../common'
require_relative '../masking'
require_relative '../post_process/heading_processor'
require_relative 'issue_registry'
require_relative 'markdown_utils'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # クロスリファレンス処理モジュール
      # rubocop:disable Metrics/ModuleLength
      module CrossReferenceProcessor
        # ラベル種別の日本語名（sec は見出しラベル・at-directive-tier1-spec.md §2.4.1）
        LABEL_TYPE_NAMES = { list: 'リスト', table: '表', fig: '図', sec: '節' }.freeze
        CAPTION_PATTERN = /^\*\*\s*(.+?)\s+@([-\w]+)\s*\*\*\s*$/

        # 見出し行末の ` @id`（見出しラベル）。紙面には出さずアンカーだけを残す。
        HEADING_LABEL_PATTERN = /^(\#{1,6})\s+(.+?)\s+@([-\w]+)\s*$/

        # 自動採番用の予約ID（キャプションで @auto / @omakase / @id と書くと type-chapter-N 形式に採番される）
        RESERVED_IDS = %w[auto omakase id].freeze

        # 組み込み置換ルール（ReplacementRules）・ビルド生成物（QrTransformer）の
        # マクロ名（完全一致で予約）。これは @ID 参照ではなくシステム予約のマクロなので、
        # 未定義のラベルIDとして警告せず後段（post_process / pre_process）へ素通しする。
        # （@nega/@posi の後方互換別名・@comment/@commend の編集者コメントは廃止済み）
        RESERVED_MACRO_IDS = %w[vspace hspace pagebreak pageref version today title qr].freeze

        # 予約IDの判定を一元化する。
        # RESERVED_IDS: auto / omakase / id
        # RESERVED_MACRO_IDS: vspace / hspace / pagebreak / …（完全一致）
        def self.reserved_id?(label_id)
          return true if RESERVED_IDS.include?(label_id)

          RESERVED_MACRO_IDS.include?(label_id)
        end
        IMAGE_PATTERN = /^!\[[^\]]*\]\([^)]+\)(?:\{[^}]+\})?$/
        MAIN_CHAPTER_RANGE = PostProcessCommands::HeadingProcessor::MAIN_CHAPTER_RANGE

        # ラベル定義情報を保持する構造体
        Label = Struct.new(:id, :type, :chapter, :number, :title, :source_file, :line, :auto) do
          def display_name
            LABEL_TYPE_NAMES.fetch(type, '要素')
          end

          def full_number
            "#{display_name} #{number}"
          end
        end

        module_function

        # === Public API ===

        # コード（フェンス区切り行・内容行）とみなす行番号（1 始まり）の集合を Masking で判定する。
        # 各内部クラスのフェンス追跡（自前の状態機械）を Masking（唯一の実装）へ一元化するための述語。
        # 可変長フェンス・入れ子・~~~・```include: 除外に一貫して追従する。
        def code_line_numbers(content)
          prose = Set.new
          Masking.each_prose_line(content) { |_line, lineno| prose << lineno }
          total = content.each_line.count
          (1..total).reject { prose.include?(it) }.to_set
        end

        def extract_caption_label(line)
          match = line.match(CAPTION_PATTERN)
          return nil unless match

          { title: match[1].strip, id: match[2].strip,
            auto: RESERVED_IDS.include?(match[2].strip) }
        end

        # 見出し行末の ` @id` を取り出す（`## インストール @install`）。
        # 見出しラベルは @pageref / @id 参照の飛び先になる（at-directive-tier1-spec.md §1.1）。
        def extract_heading_label(line)
          match = line.match(HEADING_LABEL_PATTERN)
          return nil unless match

          { level: match[1].length, title: match[2].strip, id: match[3].strip }
        end

        def detect_block_type(lines, idx)
          ((idx + 1)...lines.size).each do |index|
            line = lines[index].strip
            next if line.empty? || line.start_with?(':::{')

            return detect_type_from_line(line)
          end
          nil
        end

        def detect_type_from_line(line)
          return :list if line.start_with?('```')
          return :table if line.start_with?('|') && line.count('|') > 1
          return :fig if line.start_with?('![')

          nil
        end
        private_class_method :detect_type_from_line

        # 章番号関連
        def extract_chapter_number(filename)
          match = File.basename(filename, '.*').match(/^(\d+)/)
          match ? match[1] : '0'
        end

        def display_chapter_number_for_filename(filename)
          num = extract_chapter_number(filename).to_i
          return num.to_s unless MAIN_CHAPTER_RANGE.include?(num)

          token = File.basename(filename, File.extname(filename))
          idx = main_chapter_order.index(token)
          idx ? (idx + 1).to_s : (num - 10).to_s
        end

        # 付録ファイル（90〜98）の図表番号プレフィックスに使う付録レター（"A".."I"）を返す。
        # 付録の見出し（付録 D）・節番号（D-1）と図表番号（表 D-1）を一致させるため、
        # 付録では章番号ではなくレターを用いる。本文章・前後付では nil を返し、
        # 各呼び出し元の既存挙動（章番号 / 表示番号）を維持する。
        def appendix_letter_for(filename)
          num = extract_chapter_number(filename).to_i
          return nil unless (90..98).cover?(num)

          Common.appendix_number_to_letter(num)&.upcase
        end

        # ラベル収集
        def collect_labels(content, source_file, chapter_number)
          collector = LabelCollectorContext.new(source_file, chapter_number)
          collector.collect(content)
        end

        # ラベル収集用コンテキスト
        class LabelCollectorContext
          def initialize(source_file, chapter_number)
            @source_file = source_file
            @chapter_number = chapter_number
            @labels = []
            @errors = []
            @counters = Hash.new(0)
          end

          def collect(content)
            lines = content.lines
            # コードブロックの除外は Masking（唯一の実装）へ委ねる。
            code_lines = CrossReferenceProcessor.code_line_numbers(content)
            lines.each_with_index { |line, idx| process_line(line, idx, lines, code_lines) }
            { labels: @labels, errors: @errors }
          end

          private

          def process_line(line, idx, lines, code_lines)
            return if code_lines.include?(idx + 1)

            if (heading = CrossReferenceProcessor.extract_heading_label(line))
              add_heading_label(heading, idx)
              return
            end

            info = CrossReferenceProcessor.extract_caption_label(line)
            return unless info

            add_label(info, idx, lines)
          end

          def add_label(info, idx, lines)
            return if reserved_macro_id?(info[:id], idx + 1)

            type = CrossReferenceProcessor.detect_block_type(lines, idx)
            unless type
              @errors << "#{@source_file}:#{idx + 1} - ブロック種別を判定できません"
              return
            end

            @counters[type] += 1
            @labels << create_label(info, type, idx + 1)
          end

          # 見出しラベル（type :sec）を登録する。番号は付けず、参照文言は
          # 「見出しテキスト」をかぎ括弧で括る（at-directive-tier1-spec.md §2.4.2）。
          def add_heading_label(heading, idx)
            return if reserved_macro_id?(heading[:id], idx + 1)

            @labels << Label.new(heading[:id], :sec, @chapter_number, @chapter_number,
                                 heading[:title], @source_file, idx + 1, false)
          end

          # 予約マクロ名（@version 等）は ラベルID に使えない。使うと本文のマクロ展開と
          # ラベル参照が衝突して解決不能になるため、収集時に 🔴 で弾く
          # （at-directive-tier1-spec.md §2.1）。自動採番の @auto / @omakase / @id は
          # 予約 *ID* であって予約マクロではないので、ここでは弾かない。
          def reserved_macro_id?(label_id, line_number)
            return false unless CrossReferenceProcessor::RESERVED_MACRO_IDS.include?(label_id)

            Common.log_error(
              "#{@source_file}:#{line_number} - '#{label_id}' は予約語のため ラベルID に使えません",
              detail: "予約語: #{CrossReferenceProcessor::RESERVED_MACRO_IDS.join(', ')}\n" \
                      "→ 別の ID に変更してください（例: @#{label_id} → @#{label_id}-detail）。"
            )
            IssueRegistry.record(
              chapter: @source_file, line: line_number, severity: :error,
              category: :cross_reference, message: "予約語 '@#{label_id}' は ラベルID に使えません"
            )
            @errors << "#{@source_file}:#{line_number} - 予約語をラベルIDに使用: @#{label_id}"
            true
          end

          def create_label(info, type, line_number)
            count = @counters[type]
            # 付録は章番号ではなく付録レター（A..I）を番号プレフィックスに使う。
            # 本文章・前後付では nil となり従来どおり章番号を用いる。
            chapter_label = CrossReferenceProcessor.appendix_letter_for(@source_file) || @chapter_number
            label_id = info[:auto] ? "#{type}-#{chapter_label}-#{count}" : info[:id]
            Label.new(label_id, type, @chapter_number, "#{chapter_label}-#{count}",
                      info[:title], @source_file, line_number, info[:auto])
          end
        end

        # キャプション付きブロック変換
        def transform_captioned_blocks(content, filename, labels_map)
          CaptionedBlockTransformer.new(content, filename, labels_map).transform
        end

        # 参照置換
        def replace_references(content, labels_map, filename = nil)
          ReferenceReplacer.new(content, labels_map, filename).replace
        end

        # ラベルマップ構築（重複チェック付き）
        # @return [Hash] labels_map と duplicates_by_id を含む
        #   duplicates_by_id: { id => [Label, ...] }（先勝ちで labels_map に載る）
        def build_labels_map_with_duplicates_check(all_labels)
          map = {}
          # IDごとに全ラベルを蓄積する（先勝ちで map に登録）
          all_occurrences = Hash.new { |h, k| h[k] = [] }

          all_labels.each do |label|
            all_occurrences[label.id] << label
            map[label.id] ||= label
          end

          duplicates_by_id = all_occurrences.select { |_, labels| labels.size > 1 }
          { labels_map: map, duplicates_by_id: }
        end

        # === Private Helpers ===

        # 前処理の時点ではまだ HTML が並んでいないので、HeadingProcessor の
        # discovered_main_chapter_tokens（html/ を舐める）は使えない。
        # 単章/選択ビルドの override があればそれを、無ければ catalog.yml から起こす。
        def main_chapter_order
          hp = PostProcessCommands::HeadingProcessor
          override = hp.chapter_tokens_override
          return hp.normalize_and_filter_tokens(override) if override&.any?

          main_chapters_from_catalog
        end
        private_class_method :main_chapter_order

        # 章立ての正典は catalog.yml なので、そこから本文章の並びを起こす。
        #
        # **contents/ を舐めてはいけない。** `vs create 15-draft` したあと
        # catalog.yml から外した草稿まで数に入り、**図表番号の章プレフィックスだけが
        # 後続の章でずれる**——後処理側の並び（`discovered_main_chapter_tokens`）は
        # 組み上がった html/ を見るので、組まれなかった草稿は入らないためである。
        # 「章扉は第 4 章なのに図は 5-1」という食い違いは、出来上がった PDF を
        # 眺めていても原因に辿り着けない類の壊れ方になる。
        def main_chapters_from_catalog
          hp = PostProcessCommands::HeadingProcessor
          TokenResolver::Resolver.new.resolve
                                 .select { it.in_catalog? && it.exists? }
                                 .map(&:basename)
                                 .select { hp.main_chapter_token?(it) }
                                 .uniq
                                 .sort_by { it[/\A\d+/].to_i }
        end
        private_class_method :main_chapters_from_catalog

        # キャプション付きブロック変換クラス
        # rubocop:disable Metrics/ClassLength
        class CaptionedBlockTransformer
          def initialize(content, filename, labels_map)
            @lines = content.lines
            @filename = filename
            @labels_map = labels_map
            @counters = Hash.new(0)
          end

          def transform
            output = []
            idx = 0
            # コードブロックの除外は Masking（唯一の実装）へ委ねる。
            code_lines = CrossReferenceProcessor.code_line_numbers(@lines.join)
            while idx < @lines.size
              idx = if code_lines.include?(idx + 1)
                      passthrough(output, idx)
                    else
                      process_line(output, idx)
                    end
            end
            output.join
          end

          private

          def passthrough(output, idx)
            output << @lines[idx]
            idx + 1
          end

          def process_line(output, idx)
            info = CrossReferenceProcessor.extract_caption_label(@lines[idx])
            return handle_non_caption(output, idx) unless info

            type = CrossReferenceProcessor.detect_block_type(@lines, idx)
            return passthrough(output, idx) unless type

            @counters[type] += 1
            transform_block(output, idx, info, type)
          end

          def handle_non_caption(output, idx)
            result = try_heading_label(output, idx)
            return result if result

            result = try_plain_image(output, idx)
            return result if result

            output << @lines[idx]
            idx + 1
          end

          # 見出し行末の ` @id` を除去し、アンカー span を見出しの「内側」へ移す。
          # 見出しの前の行に置くと、h2 の break-before: page によってアンカーだけが
          # 前ページ末尾に落ち、@pageref のページ番号が 1 ずれる
          # （at-directive-tier1-spec.md §2.4.1）。
          def try_heading_label(output, idx)
            heading = CrossReferenceProcessor.extract_heading_label(@lines[idx])
            return nil unless heading

            marks = '#' * heading[:level]
            output << %(#{marks} #{heading[:title]} <span id="#{heading[:id]}" class="vs-sec-anchor"></span>\n)
            idx + 1
          end

          def try_plain_image(output, idx)
            line = @lines[idx]
            result = try_caption_with_image(output, line, idx)
            return result if result

            try_standalone_image(output, line, idx)
          end

          def try_caption_with_image(output, line, idx)
            match = line.match(/^\s*\*\*(.+?)\*\*\s*$/)
            return nil unless match

            next_idx = skip_empty_lines(idx + 1)
            return nil unless next_idx < @lines.size && @lines[next_idx].strip.match?(IMAGE_PATTERN)

            output << build_figure_html(parse_image(@lines[next_idx].strip), match[1].strip)
            next_idx + 1
          end

          def try_standalone_image(output, line, idx)
            return nil unless line.strip.match?(IMAGE_PATTERN)

            output << build_figure_html(parse_image(line.strip), nil)
            idx + 1
          end

          def transform_block(output, idx, info, type)
            label = resolve_label(info, type)
            block_start = find_block_start(idx)
            wrapper = detect_wrapper(block_start)

            html = render_block(type, block_start, info, label, wrapper)
            output << html
            find_block_end(block_start, type, wrapper) + 1
          end

          def render_block(type, block_start, info, label, wrapper)
            case type
            when :fig then figure_html(block_start, info, label)
            when :table then table_html(block_start, info, label, wrapper)
            when :list then list_markdown(block_start, info, label)
            end
          end

          def resolve_label(info, type)
            if info[:auto]
              # 付録はレター、本文章は表示番号で照合（create_label の採番規則と一致させる）
              chapter = CrossReferenceProcessor.appendix_letter_for(@filename) ||
                        CrossReferenceProcessor.display_chapter_number_for_filename(@filename)
              @labels_map["#{type}-#{chapter}-#{@counters[type]}"]
            else
              @labels_map[info[:id]]
            end
          end

          def skip_empty_lines(idx)
            idx += 1 while idx < @lines.size && @lines[idx].strip.empty?
            idx
          end

          def find_block_start(caption_idx)
            idx = caption_idx + 1
            idx += 1 while idx < @lines.size && (@lines[idx].strip.empty? || @lines[idx].strip.start_with?(':::{'))
            idx
          end

          def detect_wrapper(block_start)
            (block_start - 1).downto(0) do |idx|
              stripped = @lines[idx].strip
              break unless stripped.empty? || stripped.start_with?(':::{')

              return Regexp.last_match(1) if stripped.match(/^:::\{\.([a-z-]+)\}/)
            end
            nil
          end

          def find_block_end(start_idx, type, wrapper)
            end_idx = compute_block_end(start_idx, type)
            wrapper ? find_wrapper_end(end_idx) : end_idx
          end

          def compute_block_end(start_idx, type)
            case type
            when :table then find_table_end(start_idx)
            when :list then find_code_end(start_idx)
            else start_idx # :fig and unknown types
            end
          end

          def find_table_end(idx)
            idx += 1 while idx < @lines.size && @lines[idx].include?('|')
            idx - 1
          end

          def find_code_end(idx)
            idx += 1
            idx += 1 until idx >= @lines.size || @lines[idx].strip.start_with?('```')
            idx
          end

          def find_wrapper_end(end_idx)
            idx = end_idx + 1
            idx += 1 until idx >= @lines.size || @lines[idx].strip == ':::'
            idx < @lines.size ? idx : end_idx
          end

          def parse_image(line)
            return nil unless line =~ /!\[(.*?)\]\((.*?)\)(?:\{([^}]+)\})?/

            attrs = Regexp.last_match(3)
            { alt: Regexp.last_match(1), src: Regexp.last_match(2),
              align: extract_attr(attrs, /align=["']?(left|center|right)/),
              width: extract_attr(attrs, /width=["']?(\d+%)/),
              classes: extract_classes(attrs) }
          end

          def extract_attr(attrs, pattern)
            attrs&.match(pattern)&.[](1)
          end

          def extract_classes(attrs)
            return [] unless attrs

            attrs.scan(/\.([a-z-]+)/).flatten
          end

          def build_figure_html(img, caption, label: nil)
            return '' unless img

            parts = ["<figure#{id_attr(label)}#{align_class(img[:align])}#{style_attr(img[:width])}>"]
            parts << "  <img src=\"#{img[:src]}\" alt=\"#{img[:alt]}\">"
            parts << "  <figcaption>#{caption}</figcaption>" if caption
            parts << '</figure>'
            "#{parts.join("\n")}\n"
          end

          def figure_html(block_start, info, label)
            img = parse_image(@lines[block_start].strip) || { src: '', alt: '' }
            caption = label ? "#{label.full_number}: #{info[:title]}" : info[:title]
            build_figure_html(img, caption, label: label)
          end

          def table_html(block_start, info, label, wrapper)
            table_lines = collect_table_lines(block_start)
            html = MarkdownUtils.render_markdown_to_html(table_lines.join).strip
            caption = label ? "#{label.full_number}: #{info[:title]}" : info[:title]
            long = wrapper == 'long-table' || table_lines.first.to_s.count('|') >= 8
            build_table_div(label, caption, html, long)
          end

          def build_table_div(label, caption, html, long)
            classes = ['cross-ref-table']
            classes << 'long-table' if long
            [
              "<div#{id_attr(label)} class=\"#{classes.join(' ')}\">",
              "  <p class=\"table-caption\">#{caption}</p>",
              "  #{html}",
              '</div>', ''
            ].join("\n")
          end

          def collect_table_lines(idx)
            lines = []
            while idx < @lines.size && @lines[idx].include?('|') && !@lines[idx].strip.empty?
              lines << @lines[idx]
              idx += 1
            end
            lines
          end

          def list_markdown(block_start, info, label)
            caption = label ? "#{label.full_number}: #{info[:title]}" : info[:title]
            data_id = label&.id || info[:id]
            # キャプション（<p>）→ <!--xref--> マーカー → コードブロック本体、の順で出力する。
            # 本体を出さないと post_process の wrap_cross_ref_code_blocks! が参照する <pre> が
            # 生成されず、リスト番号（キャプション）だけ残ってコードブロックが消える。
            code = @lines[block_start..find_code_end(block_start)].join
            "**#{caption}**\n<!--xref:#{data_id}-->\n\n#{code}"
          end

          def id_attr(label)
            label ? " id=\"#{label.id}\"" : ''
          end

          def align_class(align)
            return '' unless align

            " class=\"align-#{align}\""
          end

          def style_attr(width)
            width ? " style=\"width: #{width}\"" : ''
          end
        end
        # rubocop:enable Metrics/ClassLength

        # 参照置換クラス
        class ReferenceReplacer
          REFERENCE_PATTERN = /(?<![a-zA-Z0-9_.])@([\w-]+)/

          # ページ番号つき参照（at-directive-tier1-spec.md §2.4.2）。
          # generic の REFERENCE_PATTERN はコロンの手前までしか見ない（= `@pageref` だけを拾う）ため、
          # 必ず generic より先に処理する。
          PAGEREF_PATTERN = /@pageref:([\w-]+)/
          # 引数を書き忘れた裸の @pageref。generic 側では予約語として黙って素通しされるので、
          # ここで捕まえて書式を案内する。
          BARE_PAGEREF_PATTERN = /@pageref\b(?!:)/

          # 参照走査から除外するスパン（インライン code 以外の正当な @ 出現箇所）:
          # - Markdown リンク/画像 [text](url): リンクテキスト・URL とも @ は正当な表現
          #   （npm スコープ名 [npmjs.com/@vivliostyle/cli](https://…/@vivliostyle/cli) 等）
          # - 単独の角括弧 [ … ]: 索引・用語集の手動登録（[用語|読み]・[@用語]）や脚注参照 [^url1]
          # - 裸 URL: リンク脚注化が追記する脚注定義行（[^url1]: https://…/@scope/pkg）など、
          #   角括弧の外に現れる URL 内の @
          MASKED_SPAN_PATTERN = %r{`+[^`]*`+|!?\[[^\]]*\](?:\([^)]*\))?|https?://[^\s)]+}

          def initialize(content, labels_map, filename)
            @content = content
            @labels_map = labels_map
            @filename = filename
            @errors = []
            @used_ids = Set.new
          end

          def replace
            # コードブロックの除外は Masking（唯一の実装）へ委ねる。
            code_lines = CrossReferenceProcessor.code_line_numbers(@content)
            result = @content.lines.map.with_index(1) do |line, num|
              in_code = code_lines.include?(num)
              # 定義行（キャプション `** タイトル @id **` / 見出し `## タイトル @id`）は
              # 参照としてカウントしない（孤立ラベル検出が定義行を「使用済み」と誤認するため）
              next line if !in_code && definition_line?(line)

              in_code ? line : replace_in_line(line, num)
            end
            { content: result.join, errors: @errors, used_ids: @used_ids }
          end

          private

          def definition_line?(line)
            !CrossReferenceProcessor.extract_caption_label(line).nil? ||
              !CrossReferenceProcessor.extract_heading_label(line).nil?
          end

          def replace_in_line(line, line_num)
            line.split(%r{(<code[^>]*>.*?</code>)}).map do |part|
              part.start_with?('<code') ? part : replace_outside_code(part, line_num)
            end.join
          end

          # 除外スパン（インライン code・リンク/角括弧・裸 URL）は素通しし、
          # 残りの平文だけを参照置換にかける
          def replace_outside_code(text, line_num)
            result = +''
            pos = 0
            text.scan(MASKED_SPAN_PATTERN) do
              match = Regexp.last_match
              result << replace_refs(text[pos...match.begin(0)], line_num) << match[0]
              pos = match.end(0)
            end
            result << replace_refs(text[pos..], line_num)
          end

          def replace_refs(text, line_num)
            text = text.gsub(PAGEREF_PATTERN) { replace_pageref(Regexp.last_match(1), line_num) }
            text = text.gsub(BARE_PAGEREF_PATTERN) { report_bare_pageref(line_num) }
            text.gsub(REFERENCE_PATTERN) do
              label_id = Regexp.last_match(1)
              replace_single_ref(label_id, line_num)
            end
          end

          # @pageref:id → ページ番号つきリンク。ページ番号自体は CSS の target-counter が
          # 組版時に注入するため（chapter-common.css の a.pageref::after）、ここでは
          # class="pageref" を付けたリンクを置くだけでよい。EPUB/Kindle は target-counter を
          # 解さず宣言ごと破棄するので、自動的にタイトルのみのリンクへ劣化する。
          def replace_pageref(label_id, line_num)
            label = @labels_map[label_id]
            unless label
              @errors << "#{@filename}:#{line_num} - 未定義のラベルID: @pageref:#{label_id}"
              return "@pageref:#{label_id}"
            end

            @used_ids << label_id
            %(<a href="#{build_href(label)}" class="cross-ref-link pageref">#{link_text(label)}</a>)
          end

          # 引数を書き忘れた裸の @pageref。そのままでは紙面に生テキストが出るため書式を案内する。
          def report_bare_pageref(line_num)
            @errors << "#{@filename}:#{line_num} - @pageref には参照先が必要です（書式例: @pageref:install）"
            '@pageref'
          end

          def replace_single_ref(label_id, line_num)
            return "@#{label_id}" if CrossReferenceProcessor.reserved_id?(label_id)

            label = @labels_map[label_id]
            if label
              @used_ids << label_id
              return render_link(label)
            end

            @errors << "#{@filename}:#{line_num} - 未定義のラベルID: @#{label_id}"
            "@#{label_id}"
          end

          def render_link(label)
            href = build_href(label)
            %(<a href="#{href}" class="cross-ref-link">#{link_text(label)}</a>)
          end

          # 参照リンクの文言。見出しラベル（:sec）は「タイトル」をかぎ括弧で括り、
          # 図・表・リストは従来どおり「図 3」形式にする（:sec に full_number は使わない）。
          def link_text(label)
            return "「#{CGI.escapeHTML(label.title.to_s)}」" if label.type == :sec

            CGI.escapeHTML(label.full_number)
          end

          def build_href(label)
            return "##{label.id}" if label.source_file.to_s.empty?

            "#{File.basename(label.source_file, '.*')}.html##{label.id}"
          end
        end
      end
      # rubocop:enable Metrics/ModuleLength
    end
  end
end
