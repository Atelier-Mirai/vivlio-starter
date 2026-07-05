# frozen_string_literal: true

# ================================================================
# クロスリファレンス（相互参照）機能を提供する。
#
# 機能:
#   - ラベル定義の収集（** タイトル @id ** 形式）
#   - キャプション付きブロック（図・表・コード）の HTML 変換
#   - 本文中の @id 参照をリンクに置換
#   - 重複チェックとレポート生成
# ================================================================

require 'cgi'
require 'set'
require_relative '../common'
require_relative '../masking'
require_relative '../post_process/heading_processor'
require_relative 'markdown_utils'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # クロスリファレンス処理モジュール
      # rubocop:disable Metrics/ModuleLength
      module CrossReferenceProcessor
        # ラベル種別の日本語名
        LABEL_TYPE_NAMES = { list: 'リスト', table: '表', fig: '図' }.freeze
        CAPTION_PATTERN = /^\*\*\s*(.+?)\s+@([-\w]+)\s*\*\*\s*$/

        # 自動採番用の予約ID（キャプションで @auto / @omakase / @id と書くと type-chapter-N 形式に採番される）
        RESERVED_IDS = %w[auto omakase id].freeze

        # config/post_replace_list.yml のマクロ名（完全一致で予約）。
        # これらは @ID 参照ではなくシステム予約のマクロなので、
        # 未定義のラベルIDとして警告しない。
        RESERVED_MACRO_IDS = %w[
          vspace nega posi
          comment commend
        ].freeze

        # config/post_replace_list.yml の絶対配置＋SVG ガイド線マクロ接頭辞。
        # 例: @lu25,15@20,30 の `lu25` や、@ls40@20,20 の `ls40` など、
        # 接頭辞に続く数字列（幅/高さ指定）を丸ごと予約する。
        # Planned 扱いのため現状はコメントアウトされているが、
        # 資料やコードサンプルで登場しても警告しないようにしておく。
        RESERVED_MACRO_POSITION_PREFIXES = %w[
          lu ld ru rd ur
          ls rs us ds
        ].freeze

        # 予約IDの判定を一元化する。
        # RESERVED_IDS: auto / omakase / id
        # RESERVED_MACRO_IDS: div / nega / comment など完全一致
        # RESERVED_MACRO_POSITION_PREFIXES: lu25 / ls40 など接頭辞＋数字
        def self.reserved_id?(label_id)
          return true if RESERVED_IDS.include?(label_id)
          return true if RESERVED_MACRO_IDS.include?(label_id)

          RESERVED_MACRO_POSITION_PREFIXES.any? { |prefix| label_id.match?(/\A#{prefix}\d*\z/) }
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

        def process_cross_references(chapters)
          all_labels, all_errors = collect_all_labels(chapters)
          labels_map, duplicates = build_labels_map(all_labels)
          log_duplicates(duplicates, all_errors)

          processed = transform_all_chapters(chapters, labels_map)
          processed, ref_errors = replace_all_references(processed, labels_map)
          all_errors.concat(ref_errors)

          { chapters: processed, report: generate_report(all_labels),
            errors: all_errors, labels_count: all_labels.size }
        end

        def extract_caption_label(line)
          match = line.match(CAPTION_PATTERN)
          return nil unless match

          { title: match[1].strip, id: match[2].strip,
            auto: RESERVED_IDS.include?(match[2].strip) }
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

            info = CrossReferenceProcessor.extract_caption_label(line)
            return unless info

            add_label(info, idx, lines)
          end

          def add_label(info, idx, lines)
            type = CrossReferenceProcessor.detect_block_type(lines, idx)
            unless type
              @errors << "#{@source_file}:#{idx + 1} - ブロック種別を判定できません"
              return
            end

            @counters[type] += 1
            @labels << create_label(info, type, idx + 1)
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

        # レポート生成
        # @return [Hash] labels_map と duplicates_by_id を含む
        #   duplicates_by_id: { id => { first_label: Label, all_labels: [Label, ...] } }
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

        def collect_all_labels(chapters)
          all_labels = []
          all_errors = []
          Common.log_info('Phase 1: ラベル定義を収集中...')
          chapters.each do |filename, content|
            result = collect_labels(content, filename, extract_chapter_number(filename))
            all_labels.concat(result[:labels])
            all_errors.concat(result[:errors])
            Common.log_info("  #{filename}: #{result[:labels].size}個")
          end
          [all_labels, all_errors]
        end
        private_class_method :collect_all_labels

        def build_labels_map(all_labels)
          Common.log_info('Phase 2: ラベルマップ構築...')
          result = build_labels_map_with_duplicates_check(all_labels)
          [result[:labels_map], result[:duplicates_by_id]]
        end
        private_class_method :build_labels_map

        def log_duplicates(duplicates_by_id, all_errors)
          return if duplicates_by_id.empty?

          duplicates_by_id.each do |_id, labels|
            first = labels.first
            # ファイルごとに行番号をグループ化して detail を構築する
            by_file = labels.group_by(&:source_file)
            detail_lines = by_file.map do |file, file_labels|
              "#{file}: #{file_labels.map(&:line).join(', ')}"
            end
            Common.log_error(
              "#{first.source_file}:#{first.line} - ラベルID '#{first.title} @#{first.id}' は重複しています",
              detail: "重複箇所: #{detail_lines.join("\n          ")}"
            )
            all_errors << "ラベルID '@#{first.id}' 重複"
          end
        end
        private_class_method :log_duplicates

        def transform_all_chapters(chapters, labels_map)
          Common.log_info('Phase 3: キャプション付きブロックをHTML化中...')
          chapters.to_h do |filename, content|
            [filename, transform_captioned_blocks(content, filename, labels_map)]
          end
        end
        private_class_method :transform_all_chapters

        def replace_all_references(chapters, labels_map)
          Common.log_info('Phase 4: @id 参照を置換中...')
          all_errors = []
          processed = {}
          chapters.each do |filename, content|
            result = replace_references(content, labels_map, filename)
            processed[filename] = result[:content]
            log_reference_errors(filename, result[:errors])
            all_errors.concat(result[:errors])
          end
          [processed, all_errors]
        end
        private_class_method :replace_all_references

        def log_reference_errors(filename, errors)
          return if errors.empty?

          Common.log_warn("  #{filename}: #{errors.size}個の未定義参照")
          errors.each { |err| Common.log_warn("    - #{err}") }
        end
        private_class_method :log_reference_errors

        def format_label_line(label)
          mode = label.auto ? 'auto' : 'manual'
          "  - @#{label.id.ljust(25)} (#{label.full_number.ljust(10)}, #{mode}) 「#{label.title}」"
        end
        private_class_method :format_label_line

        def main_chapter_order
          hp = PostProcessCommands::HeadingProcessor
          override = hp.chapter_tokens_override
          return hp.normalize_and_filter_tokens(override) if override&.any?

          tokens = hp.configured_main_chapter_tokens
          return tokens if tokens&.any?

          detect_main_chapters_from_files
        end
        private_class_method :main_chapter_order

        def detect_main_chapters_from_files
          hp = PostProcessCommands::HeadingProcessor
          resolver = TokenResolver::Resolver.new
          seen = {}
          tokens = Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).filter_map do |path|
            token = hp.normalize_chapter_token(File.basename(path, '.md'))
            next unless token && hp.main_chapter_token?(token) && !seen[token]

            seen[token] = true
            token
          end
          tokens.sort_by { |tkn| resolver.resolve_file(tkn).number.to_i }
        end
        private_class_method :detect_main_chapters_from_files

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
            result = try_plain_image(output, idx)
            return result if result

            output << @lines[idx]
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
              # キャプション定義行（** タイトル @id **）は参照としてカウントしない
              next line if !in_code && CrossReferenceProcessor.extract_caption_label(line)

              in_code ? line : replace_in_line(line, num)
            end
            { content: result.join, errors: @errors, used_ids: @used_ids }
          end

          private

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
            text.gsub(REFERENCE_PATTERN) do
              label_id = Regexp.last_match(1)
              replace_single_ref(label_id, line_num)
            end
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
            %(<a href="#{href}" class="cross-ref-link">#{CGI.escapeHTML(label.full_number)}</a>)
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
