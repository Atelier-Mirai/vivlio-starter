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
require_relative 'showcase_transformer'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # クロスリファレンス処理モジュール
      # rubocop:disable Metrics/ModuleLength
      module CrossReferenceProcessor
        # ラベル種別の日本語名（sec は見出しラベル・at-directive-tier1-spec.md §2.4.1、
        # chap はファイル名から付く暗黙の章ラベル・chapter-reference-spec.md §1.1）
        LABEL_TYPE_NAMES = { list: 'リスト', table: '表', fig: '図', sec: '節', chap: '章' }.freeze
        CAPTION_PATTERN = /^\*\*\s*(.+?)\s+@([-\w]+)\s*\*\*\s*$/

        # 見出し行末の ` @id`（見出しラベル）。紙面には出さずアンカーだけを残す。
        HEADING_LABEL_PATTERN = /^(\#{1,6})\s+(.+?)\s+@([-\w]+)\s*$/

        # 章題（第 1 レベルの見出し）。暗黙の章ラベルの飛び先と表示文字列になる。
        CHAPTER_HEADING_PATTERN = /^#[ \t]+(.+?)\s*$/

        # 暗黙の章ラベルの接頭辞。著者が手で付けるラベルと名前がぶつからないよう、
        # この接頭辞は予約にする（chapter-reference-spec.md §2.1・§2.5）。
        CHAPTER_LABEL_PREFIX = 'ch-'

        # 自動採番用の予約ID（キャプションで @auto / @id と書くと type-chapter-N 形式に採番される）
        RESERVED_IDS = %w[auto id].freeze

        # 組み込み置換ルール（ReplacementRules）・ビルド生成物（QrTransformer）の
        # マクロ名（完全一致で予約）。これは @ID 参照ではなくシステム予約のマクロなので、
        # 未定義のラベルIDとして警告せず後段（post_process / pre_process）へ素通しする。
        # （@nega/@posi の後方互換別名・@comment/@commend の編集者コメントは廃止済み）
        RESERVED_MACRO_IDS = %w[vspace hspace pagebreak pageref chapref version today title qr].freeze

        # 予約IDの判定を一元化する。
        # RESERVED_IDS: auto / id
        # RESERVED_MACRO_IDS: vspace / hspace / pagebreak / …（完全一致）
        def self.reserved_id?(label_id)
          return true if RESERVED_IDS.include?(label_id)

          RESERVED_MACRO_IDS.include?(label_id)
        end
        IMAGE_PATTERN = /^!\[[^\]]*\]\([^)]+\)(?:\{[^}]+\})?$/
        # showcase（図解注釈）が前処理で組んだ図の開始行（ShowcaseTransformer#figure の出力）。
        # 図番号を振るのは全章の前処理の後なので、この時点で showcase はすでに HTML になっている。
        # 画像の行の代わりにこれを図として扱い、キャプションと図番号を差し込む（改善案.md #58）。
        SHOWCASE_FIGURE_OPEN = /\A<figure class="vs-showcase"/
        # 画像の幅（`{width=30%}` / `{width=2em}` / `{width=48}`）。CSS の長さか割合で、
        # 単位のない整数は px とみなす。文中の画像（post_process の apply_inline_image_widths!）と
        # 書ける値をそろえる（改善案.md #55）。
        IMAGE_WIDTH = /(?<![\w-])width=["']?(\d+(?:\.\d+)?(?:%|mm|cm|Q|in|pt|px|em|rem)?)(?=["'\s]|\z)/
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
          return :fig if line.start_with?('![') || line.match?(SHOWCASE_FIGURE_OPEN)

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

        # --- 暗黙の章ラベル（chapter-reference-spec.md） ---

        # 章ファイルの暗黙のラベル ID（`44-build.md` → `ch-build`）。スラッグのない章
        # （`11.md`）には付けない。番号でラベルを作ると改番のたびに参照が切れるため（§2.4）。
        def chapter_label_id_for(filename)
          slug = File.basename(filename.to_s, '.*')[/\A\d+-(.+)\z/, 1]
          slug && "#{CHAPTER_LABEL_PREFIX}#{slug}"
        end

        # `@chapref:` が章題の前に置く章番号の文字（「第7章」「付録 A」）。前書き・後書きは nil。
        #
        # 文字の形は章扉と同じ build_h1_number_text に任せる。番号は単章ビルドの絞り込みを見ず、
        # 常に catalog.yml の全体から数える。参照先の章は単章ビルドの対象に入っていないので、
        # 絞り込みで数えると全章ビルドと違う番号になる（§2.11）。
        def chapter_number_text_for(filename)
          basename = File.basename(filename.to_s, '.*')
          number = extract_chapter_number(basename).to_i
          context = { file_type: nil, chapter_display_number: nil, appendix_letter: nil }
          if MAIN_CHAPTER_RANGE.include?(number) && PostProcessCommands::HeadingProcessor.chapter_numbering?
            index = main_chapters_from_catalog.index(basename)
            context[:chapter_display_number] = index && (index + 1)
          elsif (90..98).cover?(number)
            context[:file_type] = 'appendix'
            context[:appendix_letter] = Common.appendix_number_to_letter(number)&.upcase
          end
          PostProcessCommands::HeadingProcessor.build_h1_number_text(context)
        end

        # 章題の表示文字列。タグ（97 章の `<br>`）と強調・コードの記号、手書きの見出しラベルを除き、
        # 目次に出る文字とそろえる（§2.8）。
        def plain_chapter_title(heading_text)
          heading_text.to_s
                      .sub(/\s+@[-\w]+\s*\z/, '')
                      .gsub(/<[^>]+>/, '')
                      .gsub(/\*\*|__|`/, '')
                      .strip
        end

        # ラベル収集
        # @param chapter_number_text [String, nil] 章ラベルの章番号の文字（chapter_number_text_for の値）
        def collect_labels(content, source_file, chapter_number, chapter_number_text: nil)
          collector = LabelCollectorContext.new(source_file, chapter_number, chapter_number_text)
          collector.collect(content)
        end

        # ラベル収集用コンテキスト
        class LabelCollectorContext
          def initialize(source_file, chapter_number, chapter_number_text = nil)
            @source_file = source_file
            @chapter_number = chapter_number
            @chapter_number_text = chapter_number_text
            @chapter_label_id = CrossReferenceProcessor.chapter_label_id_for(source_file)
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

            add_chapter_label(line, idx) if @chapter_label_id

            if (heading = CrossReferenceProcessor.extract_heading_label(line))
              add_heading_label(heading, idx)
              return
            end

            info = CrossReferenceProcessor.extract_caption_label(line)
            return unless info

            add_label(info, idx, lines)
          end

          # 最初の章題に暗黙の章ラベル（type :chap）を 1 つだけ付ける。number には
          # `@chapref:` が使う章番号の文字（「第7章」）を持たせる。
          def add_chapter_label(line, idx)
            match = line.match(CHAPTER_HEADING_PATTERN)
            return unless match

            @labels << Label.new(@chapter_label_id, :chap, @chapter_number, @chapter_number_text,
                                 CrossReferenceProcessor.plain_chapter_title(match[1]), @source_file, idx + 1, false)
            @chapter_label_id = nil
          end

          def add_label(info, idx, lines)
            return if reserved_macro_id?(info[:id], idx + 1)
            return if reserved_chapter_prefix?(info[:id], idx + 1)

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
            return if reserved_chapter_prefix?(heading[:id], idx + 1)

            @labels << Label.new(heading[:id], :sec, @chapter_number, @chapter_number,
                                 heading[:title], @source_file, idx + 1, false)
          end

          # 予約マクロ名（@version 等）は ラベルID に使えない。使うと本文のマクロ展開と
          # ラベル参照が衝突して解決不能になるため、収集時に 🔴 で弾く
          # （at-directive-tier1-spec.md §2.1）。自動採番の @auto / @id は
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

          # `ch-` で始まるラベルは暗黙の章ラベルの予約。手で付けると暗黙のラベルとぶつかり、
          # どちらが参照されるかが章の並び順で決まって気づけないため、🔴 で弾く（§2.5）。
          def reserved_chapter_prefix?(label_id, line_number)
            return false unless label_id.start_with?(CHAPTER_LABEL_PREFIX)

            Common.log_error(
              "#{@source_file}:#{line_number} - '@#{label_id}' の '#{CHAPTER_LABEL_PREFIX}' は章のラベル用の予約です",
              detail: "章にはファイル名から @#{CHAPTER_LABEL_PREFIX}<スラッグ> のラベルが自動で付きます。\n" \
                      "→ 別の ID に変更してください（例: @#{label_id} → @#{label_id.delete_prefix(CHAPTER_LABEL_PREFIX)}）。"
            )
            IssueRegistry.record(
              chapter: @source_file, line: line_number, severity: :error,
              category: :cross_reference, message: "'@#{label_id}' の '#{CHAPTER_LABEL_PREFIX}' は章のラベル用の予約です"
            )
            @errors << "#{@source_file}:#{line_number} - 章ラベルの予約をラベルIDに使用: @#{label_id}"
            true
          end

          def create_label(info, type, line_number)
            count = @counters[type]
            # 付録は章番号ではなく付録レター（A..I）を番号プレフィックスに使う。
            # 本文章・前後付では nil となり従来どおり章番号を用いる。
            chapter_label = CrossReferenceProcessor.appendix_letter_for(@source_file) || @chapter_number
            label_id = info[:auto] ? "#{type}-#{chapter_label}-#{count}" : info[:id]
            # 章番号を振らない配布資料では「図 1」（HeadingProcessor.chapter_numbering?・改善案 #84）
            number = PostProcessCommands::HeadingProcessor.chapter_numbering? ? "#{chapter_label}-#{count}" : count.to_s
            Label.new(label_id, type, @chapter_number, number, info[:title], @source_file, line_number, info[:auto])
          end
        end

        # キャプション付きブロック変換
        def transform_captioned_blocks(content, filename, labels_map)
          CaptionedBlockTransformer.new(content, filename, labels_map).transform
        end

        # 参照置換
        # @param chapter_order [Array<String>, nil] catalog.yml の章の basename の並び。
        #   渡したときだけ「前の章 @ch-x」の x が隣の章かを確かめる（chapter-reference-spec.md §2.10）
        def replace_references(content, labels_map, filename = nil, chapter_order: nil)
          ReferenceReplacer.new(content, labels_map, filename, chapter_order:).replace
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
            # 章ラベルを集めた章（catalog.yml に載った章）だけ、章題にアンカーを置く
            chapter_id = CrossReferenceProcessor.chapter_label_id_for(filename)
            @pending_chapter_anchor = chapter_id if labels_map[chapter_id]&.type == :chap
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
            result = try_chapter_heading(output, idx)
            return result if result

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

          # 最初の章題の内側に暗黙の章ラベルのアンカーを置く（chapter-reference-spec.md §3.2）。
          # 見出しラベルと同じく内側に置くのは、改ページでアンカーだけが前のページに落ちないため。
          # 章題に手書きの見出しラベルもあれば、両方のアンカーを並べる。
          def try_chapter_heading(output, idx)
            return nil unless @pending_chapter_anchor

            match = @lines[idx].match(CHAPTER_HEADING_PATTERN)
            return nil unless match

            title = match[1]
            anchors = []
            if (heading = CrossReferenceProcessor.extract_heading_label(@lines[idx]))
              title = heading[:title]
              anchors << heading[:id]
            end
            anchors << @pending_chapter_anchor
            @pending_chapter_anchor = nil
            spans = anchors.map { %(<span id="#{it}" class="vs-sec-anchor"></span>) }.join
            output << "# #{title} #{spans}\n"
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
            return nil unless next_idx < @lines.size

            if showcase_figure?(next_idx)
              output << showcase_figure_html(next_idx, match[1].strip, label: nil)
              return separate_from_next(output, showcase_figure_end(next_idx) + 1)
            end
            return nil unless @lines[next_idx].strip.match?(IMAGE_PATTERN)

            output << build_figure_html(parse_image(@lines[next_idx].strip), match[1].strip)
            separate_from_next(output, next_idx + 1)
          end

          def try_standalone_image(output, line, idx)
            return nil unless line.strip.match?(IMAGE_PATTERN)

            output << build_figure_html(parse_image(line.strip), nil)
            separate_from_next(output, idx + 1)
          end

          # 図・表を HTML にしたあと、次の行が空行でなければ空行を 1 つ補う（改善案.md #68）。
          # `<figure>` や `<div>` で始まる HTML のかたまりは、Markdown では空行まで続く。
          # `![図](a.webp)` の直後の行に本文を続けて書くと（`:::{.img-text}` でよく書く形）、
          # 本文まで HTML のかたまりに入り、`**太字**` などの記法が記号のまま紙面に出ていた。
          def separate_from_next(output, next_idx)
            output << "\n" if next_idx < @lines.size && !@lines[next_idx].strip.empty?
            next_idx
          end

          def transform_block(output, idx, info, type)
            label = resolve_label(info, type)
            block_start = find_block_start(idx)
            wrapper = detect_wrapper(block_start)

            html = render_block(type, block_start, info, label, wrapper)
            output << html
            separate_from_next(output, find_block_end(block_start, type, wrapper) + 1)
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
            when :fig then showcase_figure?(start_idx) ? showcase_figure_end(start_idx) : start_idx
            else start_idx # unknown types
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
              width: image_width(attrs),
              crop: attrs&.match?(/(?<![\w-])crop=/), line:,
              classes: extract_classes(attrs) }
          end

          def image_width(attrs)
            width = extract_attr(attrs, IMAGE_WIDTH)
            width&.match?(/\A[\d.]+\z/) ? "#{width}px" : width
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

            parts = ["<figure#{id_attr(label)}#{class_attr(img)}#{style_attr(img[:width])}>"]
            parts << "  #{img_tag(img)}"
            parts << "  <figcaption>#{caption}</figcaption>" if caption
            parts << '</figure>'
            "#{parts.join("\n")}\n"
          end

          # crop のある画像は、切り抜いた SVG（PDF 用）とラスター（EPUB 用・data-vs-raster）へ
          # 差し替える。切り抜けなければ元の画像のまま出す（警告は ShowcaseTransformer が出す）。
          def img_tag(img)
            svg, raster = img[:crop] && cropped_sources(img)
            return %(<img src="#{img[:src]}" alt="#{img[:alt]}">) unless svg

            %(<img class="vs-cropped" src="#{svg}" data-vs-raster="#{raster}" alt="#{img[:alt]}">)
          end

          def cropped_sources(img)
            ShowcaseTransformer.crop_assets(img[:line], chapter_slug: File.basename(@filename.to_s, '.*'),
                                                        source_filename: File.basename(@filename.to_s))
          end

          def figure_html(block_start, info, label)
            caption = label ? "#{label.full_number}: #{info[:title]}" : info[:title]
            return showcase_figure_html(block_start, caption, label:) if showcase_figure?(block_start)

            img = parse_image(@lines[block_start].strip) || { src: '', alt: '' }
            build_figure_html(img, caption, label: label)
          end

          def showcase_figure?(idx) = @lines[idx].to_s.strip.match?(SHOWCASE_FIGURE_OPEN)

          # showcase の図の閉じ（</figure>）の行。見つからなければ開始行（図を 1 行とみなす）。
          def showcase_figure_end(start_idx)
            end_idx = (start_idx...@lines.size).find { @lines[it].strip == '</figure>' }
            end_idx || start_idx
          end

          # showcase が組んだ図へ、ラベルの id とキャプションを差し込む。図の中身（合成画像）は変えない。
          def showcase_figure_html(start_idx, caption, label:)
            lines = @lines[start_idx..showcase_figure_end(start_idx)].map(&:dup)
            lines[0] = lines[0].sub('<figure', "<figure#{id_attr(label)}")
            lines.insert(lines.size > 1 ? -2 : -1, "<figcaption>#{caption}</figcaption>\n")
            lines.join
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

          # 配置（align-*）と著者が書いたクラス（`{.bordered}` など）をまとめて出す
          def class_attr(img)
            classes = []
            classes << "align-#{img[:align]}" if img[:align]
            classes.concat(img[:classes])
            classes.empty? ? '' : " class=\"#{classes.join(' ')}\""
          end

          def style_attr(width)
            width ? " style=\"width: #{width}\"" : ''
          end
        end
        # rubocop:enable Metrics/ClassLength

        # 参照置換クラス
        # rubocop:disable Metrics/ClassLength
        class ReferenceReplacer
          REFERENCE_PATTERN = /(?<![a-zA-Z0-9_.])@([\w-]+)/

          # ページ番号つき参照。`@pageref:id`（at-directive-tier1-spec.md §2.4.2）と、章番号も添える
          # `@chapref:ch-slug`（chapter-reference-spec.md §2.11）。
          # generic の REFERENCE_PATTERN はコロンの手前までしか見ない（= `@pageref` だけを拾う）ため、
          # 必ず generic より先に処理する。
          PAGED_REFERENCE_PATTERN = /@(pageref|chapref):([\w-]+)/
          # 引数を書き忘れた裸の @pageref / @chapref。generic 側では予約語として黙って素通しされるので、
          # ここで捕まえて書式を案内する。
          BARE_PAGED_REFERENCE_PATTERN = /@(pageref|chapref)\b(?!:)/
          BARE_EXAMPLES = { 'pageref' => '@pageref:install', 'chapref' => '@chapref:ch-build' }.freeze

          # 前後の半角空白ごと捕まえる形（join_spaces が和文と接する側の空白を取り除く）。
          # 番号つきの捕獲: PAGED は 1=前の空白 2=種別 3=ID 4=後の空白、REFERENCE は 1=前 2=ID 3=後。
          PAGED_WITH_SPACES = /([ \t]*)#{PAGED_REFERENCE_PATTERN}([ \t]*)/
          REFERENCE_WITH_SPACES = /([ \t]*)#{REFERENCE_PATTERN}([ \t]*)/

          # 「前の章 @ch-x」のように、隣の章を指す言葉の直後の参照（chapter-reference-spec.md §2.10）
          ADJACENT_CHAPTER_WORD = /(前の章|前章|次の章|次章)\s*\z/

          # 段落の区切りとみなす行（chapter-reference-spec.md §2.9）。空行のほか、箇条書きの項目と
          # 表の行は読者が一つずつ読むので、それぞれを別のまとまりとして扱う。前処理で HTML に
          # なった箇条書き・表（fancy list など）も同じに扱う。
          PARAGRAPH_START = /\A\s*(?:\z|[-*+]\s|\d+[.)]\s|\||#+\s|<(?:li|tr|td|th|dt|dd|p)[\s>])/

          # 参照走査から除外するスパン（インライン code 以外の正当な @ 出現箇所）:
          # - Markdown リンク/画像 [text](url): リンクテキスト・URL とも @ は正当な表現
          #   （npm スコープ名 [npmjs.com/@vivliostyle/cli](https://…/@vivliostyle/cli) 等）
          # - 単独の角括弧 [ … ]: 索引・用語集の手動登録（[用語|読み]・[@用語]）や脚注参照 [^url1]
          # - 裸 URL: リンク脚注化が追記する脚注定義行（[^url1]: https://…/@scope/pkg）など、
          #   角括弧の外に現れる URL 内の @
          MASKED_SPAN_PATTERN = %r{`+[^`]*`+|!?\[[^\]]*\](?:\([^)]*\))?|https?://[^\s)]+}

          def initialize(content, labels_map, filename, chapter_order: nil)
            @content = content
            @labels_map = labels_map
            @filename = filename
            @chapter_order = chapter_order
            @errors = []
            @used_ids = Set.new
            @paged_in_paragraph = Set.new
          end

          def replace
            # コードブロックの除外は Masking（唯一の実装）へ委ねる。
            code_lines = CrossReferenceProcessor.code_line_numbers(@content)
            result = @content.lines.map.with_index(1) do |line, num|
              in_code = code_lines.include?(num)
              @paged_in_paragraph.clear if in_code || line.match?(PARAGRAPH_START)
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
            text = text.gsub(PAGED_WITH_SPACES) do
              match = Regexp.last_match
              html = replace_paged(match[2], match[3], match.pre_match, line_num)
              join_spaces(match, match[1], html, match[4], @labels_map[match[3]])
            end
            text = text.gsub(BARE_PAGED_REFERENCE_PATTERN) { report_bare_paged(Regexp.last_match(1), line_num) }
            text.gsub(REFERENCE_WITH_SPACES) do
              match = Regexp.last_match
              html = replace_single_ref(match[2], match.pre_match, line_num)
              join_spaces(match, match[1], html, match[3], @labels_map[match[2]])
            end
          end

          # 章題・見出しを鉤括弧で出す参照（:chap・:sec）は、和文と接する側の半角空白を取り除く
          # （chapter-reference-spec.md §1.2）。原稿は `次の章 @ch-new では` と区切って書くほうが
          # 読みやすいが、鉤括弧にはもともとアキがあるので、空白が残ると「「新規」 では」と間延びする。
          # 図表の参照（「図 4-1 を」）と、置き換えなかった参照（未定義など）は書いたとおりに残す。
          def join_spaces(match, lead, html, trail, label)
            return "#{lead}#{html}#{trail}" unless html.start_with?('<a') && %i[sec chap].include?(label&.type)

            lead = '' if japanese_char?(match.pre_match[-1])
            trail = '' if japanese_char?(match.post_match[0])
            "#{lead}#{html}#{trail}"
          end

          def japanese_char?(char) = !char.nil? && !char.ascii_only?

          # @pageref:id / @chapref:ch-slug → ページ番号つきリンク。ページ番号自体は CSS の
          # target-counter が組版時に注入するため（chapter-common.css の a.pageref::after）、
          # ここでは class="pageref" を付けたリンクを置くだけでよい。EPUB/Kindle は target-counter を
          # 解さず宣言ごと破棄するので、自動的にタイトルのみのリンクへ劣化する。
          #
          # 同じ段落で同じラベルを二度引いたら、二度目以降は pageref クラスを付けない
          # （chapter-reference-spec.md §2.9）。著者が段落の組み立てを気にせずに済むよう、
          # 省くかどうかは書き手ではなくこちらで決める。
          def replace_paged(kind, label_id, pre_text, line_num)
            raw = "@#{kind}:#{label_id}"
            label = @labels_map[label_id]
            return report_undefined(raw, label_id, line_num) unless label
            return report_chapref_to_non_chapter(raw, line_num) if kind == 'chapref' && label.type != :chap

            check_adjacent_chapter(label, pre_text, line_num)
            @used_ids << label_id
            text = kind == 'chapref' ? chapref_text(label) : link_text(label)
            %(<a href="#{build_href(label)}" class="#{paged_classes(label)}">#{text}</a>)
          end

          # 二度目以降は pageref を付けない。前付け（00-）への参照には frontmatter を付け、
          # 前付けのローマ数字のノンブル（p.iii）で出す（索引の frontmatter と同じ扱い）。
          def paged_classes(label)
            return 'cross-ref-link' unless @paged_in_paragraph.add?(label.id)

            front = File.basename(label.source_file.to_s).start_with?('00-')
            front ? 'cross-ref-link pageref frontmatter' : 'cross-ref-link pageref'
          end

          # 引数を書き忘れた裸の @pageref / @chapref。そのままでは紙面に生テキストが出るため書式を案内する。
          def report_bare_paged(kind, line_num)
            @errors << "#{@filename}:#{line_num} - @#{kind} には参照先が必要です（書式例: #{BARE_EXAMPLES[kind]}）"
            "@#{kind}"
          end

          def report_chapref_to_non_chapter(raw, line_num)
            @errors << "#{@filename}:#{line_num} - #{raw}: @chapref: には章のラベル" \
                       "（#{CHAPTER_LABEL_PREFIX}…）を指定してください。見出しや図表には @pageref: を使います"
            raw
          end

          def replace_single_ref(label_id, pre_text, line_num)
            return "@#{label_id}" if CrossReferenceProcessor.reserved_id?(label_id)

            label = @labels_map[label_id]
            return report_undefined("@#{label_id}", label_id, line_num) unless label

            check_adjacent_chapter(label, pre_text, line_num)
            @used_ids << label_id
            render_link(label)
          end

          # 未定義のラベルは文字のまま残し、直し方の手がかりを 1 つ添える（chapter-reference-spec.md
          # §2.4・§2.7）。候補を 1 件に絞る理由は ChapterTargetCheck#suggestion_for と同じ。
          def report_undefined(raw, label_id, line_num)
            @errors << "#{@filename}:#{line_num} - 未定義のラベルID: #{raw}#{undefined_hint(raw, label_id)}"
            raw
          end

          def undefined_hint(raw, label_id)
            if (number = label_id[/\A#{CHAPTER_LABEL_PREFIX}(\d+)\z/o, 1])
              return "（スラッグのない章には章ラベルが付きません。" \
                     "vs rename #{number} #{number}-<スラッグ> で名前を付けられます）"
            end

            near = DidYouMean::SpellChecker.new(dictionary: @labels_map.keys).correct(label_id).first
            near ? "（もしかして: #{raw.delete_suffix(label_id)}#{near}）" : ''
          end

          # 「前の章 @ch-x」の x が本当に前の章か（「次の章」なら次の章か）を catalog.yml の並びで
          # 確かめる（chapter-reference-spec.md §2.10）。章を入れ替えると章題は参照から差し替わるが、
          # 「前の」は著者が書いた文字なので追随せず、読み返しても食い違いに気づきにくい。
          def check_adjacent_chapter(label, pre_text, line_num)
            return unless @chapter_order && @filename && label.type == :chap

            word = pre_text[ADJACENT_CHAPTER_WORD, 1]
            return unless word

            index = @chapter_order.index(File.basename(@filename, '.*'))
            return unless index

            direction = word.start_with?('前') ? '前' : '次'
            expected_index = index + (direction == '前' ? -1 : 1)
            expected = @chapter_order[expected_index] if expected_index >= 0
            return if File.basename(label.source_file.to_s, '.*') == expected

            @errors << "#{@filename}:#{line_num} - 「#{word}」の参照先 @#{label.id}（「#{label.title}」）は、" \
                       "この章の#{direction}の章ではありません#{adjacent_hint(direction, expected)}"
          end

          def adjacent_hint(direction, expected)
            return "（この章の#{direction}に章はありません）" unless expected

            expected_id = CrossReferenceProcessor.chapter_label_id_for(expected)
            expected_id ? "（#{direction}の章は #{expected}。→ @#{expected_id}）" : "（#{direction}の章は #{expected}）"
          end

          def render_link(label)
            href = build_href(label)
            %(<a href="#{href}" class="cross-ref-link">#{link_text(label)}</a>)
          end

          # 参照リンクの文言。見出しラベル（:sec）と章ラベル（:chap）は「タイトル」をかぎ括弧で括り、
          # 図・表・リストは従来どおり「図 3」形式にする（:sec・:chap に full_number は使わない）。
          def link_text(label)
            return "「#{CGI.escapeHTML(label.title.to_s)}」" if %i[sec chap].include?(label.type)

            CGI.escapeHTML(label.full_number)
          end

          # `@chapref:` の文言。章扉と同じ章番号の文字を「章題」の前に置く（前書き・後書きは章題だけ）。
          def chapref_text(label)
            "#{CGI.escapeHTML(label.number.to_s)}#{link_text(label)}"
          end

          def build_href(label)
            return "##{label.id}" if label.source_file.to_s.empty?

            "#{File.basename(label.source_file, '.*')}.html##{label.id}"
          end
        end
        # rubocop:enable Metrics/ClassLength
      end
      # rubocop:enable Metrics/ModuleLength
    end
  end
end
