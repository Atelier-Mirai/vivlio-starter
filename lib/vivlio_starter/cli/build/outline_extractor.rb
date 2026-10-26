# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/outline_extractor.rb
# ================================================================
# 責務:
#   HTML から見出しを抽出し、PDF のアウトライン（しおり）の項目を作る。
#
# 処理内容:
#   - HTML の h1〜h3 要素から章・節・項の題を抽出
#   - 付録ラベル（付録A, 付録B...）の生成
#   - 各見出しのページと位置を、組み上がった PDF の飛び先（/Dests）から引く
#
# なぜ飛び先から引くのか（pdf-outline-heading-id-spec.md）:
#   以前は見出しの文字が PDF のどのページにあるかを pdftotext の文字から探していた。
#   本文・柱・目次・図に同じ文字があるとそちらを指し、spiral-ruby の合本では
#   1853 項目のうち 724 項目が違うページを指した。飛び先は見出しが実際に組まれた
#   位置そのものなので、本の組み方によらず外れない。目次に載らない見出しにも
#   飛び先が出るよう、PdfBuilder.inject_heading_anchors! がリンクを足している。
#
# アウトライン構造:
#   - h1: 章見出し（第N章 タイトル）。ページ全体へ飛ぶ
#   - h2/h3: 節・項見出し。見出しの位置へ飛ぶ（:top）
#   - 付録は「付録A」形式でラベリング
#
# 依存:
#   - Nokogiri: HTML パース
#   - PdfPageMapExtractor: PDF の飛び先の読み取り
# ================================================================

require 'nokogiri'
require_relative 'pdf_page_map_extractor'

module VivlioStarter
  module CLI
    module Build
      # HTML 見出し抽出・PDF アウトライン生成モジュール
      module OutlineExtractor
        # しおりに載せる見出しの深さ。PdfBuilder.inject_heading_anchors! も同じ見出しに飛び先を作る
        MAX_LEVEL = 3
        HEADING_SELECTOR = (1..MAX_LEVEL).map { "h#{it}" }.join(', ')

        # 節・項のしおりで、見出しの上に空ける高さ（pt）。ページの外へ出る分はプラグインがページ全体に戻す
        HEADING_TOP_MARGIN = 12

        class << self
          attr_accessor :last_outline_debug_info
        end
        @last_outline_debug_info = nil

        module_function

        # 節・項の見出しのすぐ外の要素（節絵の article か section）。しおりはこの要素の飛び先から位置を取る。
        # 章（h1）と、外が body のときは nil（PdfBuilder.inject_heading_anchors!）
        def heading_box(node)
          parent = node.parent
          parent if node.name != 'h1' && parent&.element? && !%w[body html].include?(parent.name)
        end

        # heading_box に振る id
        def box_anchor_id(heading_id) = "vs-box-#{heading_id}"

        # 付録ラベル取得
        # 章番号を振らない本（heading-numbering-spec.md）では、章扉に「付録 A」が無いので付けない
        def appendix_label_for_basename(basename)
          return nil unless PostProcessCommands::HeadingProcessor.chapter_numbering?

          entry = TokenResolver::Resolver.new.resolve_file(basename)
          return nil unless entry.number && entry.kind == :appendix

          letter = Common.appendix_number_to_letter(entry.number)
          return nil unless letter

          "付録#{letter.upcase}"
        end

        # HTMLファイルから見出しを抽出
        def extract_headings_from_html_file(path, max_level:, include_appendix_label: true)
          html = File.read(path, encoding: 'utf-8')
          doc  = Nokogiri::HTML.parse(html)
          basename = File.basename(path, '.html')
          headings = []
          selector = (1..max_level).map { |lvl| "h#{lvl}" }.join(',')
          doc.css(selector).each do |node|
            lvl = node.name.delete_prefix('h').to_i
            next unless lvl.positive? && lvl <= max_level

            text = node["data-h#{lvl}"].to_s.strip
            text = node['data-heading'].to_s.strip if text.empty?
            text = node.text.to_s.strip if text.empty?
            next if text.empty?

            appendix_label = nil
            appendix_label = appendix_label_for_basename(basename) if include_appendix_label && lvl == 1

            chapter_token = node['data-chapter'].to_s.strip
            chapter_token = basename if chapter_token.empty?

            headings << {
              level: lvl,
              text: text,
              chapter: chapter_token,
              id: node['id'].to_s.strip,
              box_id: heading_box(node)&.[]('id').to_s,
              appendix_label: appendix_label,
              number_display: extract_number_text(node, lvl)
            }
          end
          headings
        end

        # しおりの項目を作る。各項目の :page（と節・項の :top）は、pdf_path の飛び先から引く。
        # pdf_path は結合を終えた PDF（閲覧用は output.pdf、入稿用は output_print.pdf）で、
        # 飛び先の名前の付け替え（DestinationNames.shorten!）より前のものであること——
        # 名前に入っている「文書と id」を手がかりにするため。
        #
        # @return [Array<Hash>] :level, :text, :page, :chapter, :id, 節・項は :top も
        def heading_page_entries(pdf_path, html_paths, max_level: MAX_LEVEL)
          @last_outline_debug_info = nil
          return [] unless validate_inputs(pdf_path, html_paths)

          max_level = max_level.to_i.clamp(1, 6)
          chapter_paths = build_chapter_paths(html_paths)
          chapter_order = build_chapter_order(chapter_paths.keys)
          positions = PdfPageMapExtractor.new(pdf_path).positions_by_document

          items, missing = build_outline_items(chapter_order, chapter_paths, positions, max_level)
          log_missing_items(missing) if missing.any?

          @last_outline_debug_info = { items: items.map(&:dup), missing: missing.map(&:dup) }
          items
        end

        # PDFにアウトラインを付与
        def add_outline_from_headings!(pdf_path, html_files, max_level: MAX_LEVEL)
          require 'vivlio_starter/cli/pdf/provider'

          entries = heading_page_entries(pdf_path, html_files, max_level: max_level)
          return if entries.empty?

          VivlioStarter::Pdf.provider.add_outline!(pdf_path, entries, max_level: max_level)
        end

        private

        def extract_number_text(node, lvl)
          case lvl
          when 1
            val = node['data-chapter-number-display'].to_s.strip
            val = node.at_css('span.chapter-number')&.text&.strip if val.empty?
            val
          when 2
            val = node['data-section-number-display'].to_s.strip
            val = node.at_css('span.section-number')&.text&.strip if val.empty?
            val
          when 3
            val = node['data-subsection-number-display'].to_s.strip
            val = node.at_css('span.subsection-marker')&.text&.strip if val.empty?
            val
          end
        end

        def validate_inputs(pdf_path, html_paths)
          unless File.exist?(pdf_path)
            Common.log_warn("[Outline] PDF が見つかりません: #{pdf_path}")
            return false
          end
          if html_paths.nil? || html_paths.empty?
            Common.log_warn('[Outline] HTML ファイルが指定されていません')
            return false
          end
          if html_paths.any? { |path| !File.exist?(path) }
            Common.log_warn('[Outline] HTML ファイルが存在しません')
            return false
          end
          true
        end

        def build_chapter_paths(html_paths)
          chapter_paths = {}
          html_paths.each do |path|
            bn = File.basename(path, '.html')
            chapter_paths[bn] = path
          end
          chapter_paths
        end

        # 前書き・後書きは catalog.yml の区分で決まる（catalog-section-kind-spec.md §2.1）。
        # `00-preface`・`99-postface` の名前で決めると、PREFACE に書いた `20-vol2-intro` が本文の章として並ぶ
        def build_chapter_order(html_basenames)
          chapter_order = Build::SectionBuilder.chapter_order_from(html_basenames)
          prefaces, postfaces = supplement_basenames(chapter_order)
          # 新仕様: _titlepage, _legalpage を使用
          # 分冊の全巻目次（multivolume-spec.md §9）は、その巻の目次の前に置く
          frontmatter_sequence = [*%w[_titlepage _legalpage], *prefaces, *([WholeTocGenerator::BASENAME] & chapter_order),
                                  '_toc']
          # 巻末の順序: 用語集 → 終わりに → 索引
          # 索引・用語集が無効の場合は除外
          backmatter_sequence = if IndexCommands.index_enabled?
                                  ['_glossarypage', *postfaces, '_indexpage']
                                else
                                  postfaces
                                end

          # 巻末ページを除外した章順序
          main_chapters = chapter_order.reject { |bn| backmatter_sequence.include?(bn) }

          (frontmatter_sequence + main_chapters + backmatter_sequence).uniq
        end

        # 章の並びのうち、前書きと後書きの basename
        # @return [Array(Array<String>, Array<String>)] [前書き, 後書き]
        def supplement_basenames(chapter_order)
          resolver = TokenResolver::Resolver.new
          kinds = chapter_order.to_h { [it, resolver.resolve_file(it).kind] }
          [chapter_order.select { kinds[it] == :preface }, chapter_order.select { kinds[it] == :postface }]
        end

        # 見出しを本の順に並べ、各項目のページと位置を飛び先から引く。
        #
        # 飛び先が無い見出しは、直前の項目のページを指す（しおりの中でページが前へ戻らない）。
        # 文書の最初の見出しなら、その文書のほかの飛び先のうち最も前のページ（文書の始まり）を指す。
        # 借りたページには :top を付けない——別の見出しの位置へ飛ばさないため（spec §3 R3・R7）。
        #
        # @return [Array(Array<Hash>, Array<Hash>)] [しおりの項目, 飛び先が無かった項目]
        def build_outline_items(chapter_order, chapter_paths, positions, max_level)
          # --- Phase: 文書ごとの始まりのページ ---
          first_pages = positions.each_with_object({}) do |((document, _id), position), first|
            first[document] = position.page if first[document].nil? || position.page < first[document]
          end

          # --- Phase: 見出しごとの項目 ---
          items = []
          missing = []
          chapter_order.each do |bn|
            path = chapter_paths[bn]
            next unless path

            extract_headings_from_html_file(path, max_level: max_level).each_with_index do |heading, index|
              item = { level: heading[:level], text: build_display_text(bn, heading), chapter: bn, id: heading[:id] }
              position = positions[[bn, heading[:id]]] unless heading[:id].empty?
              if position
                item[:page] = position.page
                # 章（h1）はページ全体を見せる。章扉は見出しの上に扉絵や「第1章」がある
                top = heading_top(position, positions[[bn, heading[:box_id]]]) if heading[:level] >= 2
                item[:top] = top if top
              else
                item[:page] = (first_pages[bn] if index.zero?) || items.last&.dig(:page) || first_pages[bn] || 1
                missing << item
              end
              items << item
            end
          end

          [items, missing]
        end

        # 節・項のしおりが飛ぶ高さ。nil ならページ全体を見せる。
        #
        # 見出しの飛び先は文字の行の上端を指すので、文字より上に描く飾り（節絵の帯）が切れる。
        # 見出しのすぐ外の要素（heading_box）の飛び先が同じページでそれより上にあれば、そちらを採る
        # （PdfBuilder.inject_heading_anchors!）。さらに HEADING_TOP_MARGIN だけ上へ空ける——
        # 3 行の節題は帯より上へはみ出し、帯の上端でも 1 行目の頭が 8pt 切れた（spiral-ruby のコラム）。
        #
        # 外の要素が前のページから始まるなら、見出しは改ページでページの頭へ送られている。
        # 見出しの行の上端だと帯と文字の上半分が切れるので、ページ全体を見せる。
        def heading_top(heading_position, box_position)
          return nil if box_position && box_position.page < heading_position.page

          tops = [heading_position.top]
          tops << box_position.top if box_position&.page == heading_position.page
          top = tops.compact.max
          top && (top + HEADING_TOP_MARGIN)
        end

        def build_display_text(basename, heading)
          return heading[:text] unless heading[:level].to_i == 1

          build_chapter_display_text(basename, heading)
        end

        def build_chapter_display_text(basename, heading)
          display_text = heading[:text]

          if heading[:appendix_label]
            prepend_label_if_needed(display_text, heading[:appendix_label].to_s.strip)
          else
            number_display = resolve_chapter_number_display(basename, heading)
            prepend_label_if_needed(display_text, number_display)
          end
        end

        def resolve_chapter_number_display(basename, heading)
          number_display = heading[:number_display].to_s.strip
          return number_display unless number_display.empty?

          # 章番号を振らない本では、章扉に無い「第N章」をしおりにも足さない（heading-numbering-spec.md）
          return '' unless PostProcessCommands::HeadingProcessor.chapter_numbering?

          # 前書き・後書きは番号の範囲によらず番号を付けない（PREFACE の `20-vol2-intro` を「第10章」としない）
          entry = TokenResolver::Resolver.new.resolve_file(basename)
          return '' unless entry.kind == :chapter && entry.number&.to_i&.between?(11, 89)

          "第#{entry.number.to_i - 10}章"
        end

        def prepend_label_if_needed(text, label)
          return text if label.to_s.empty? || text.start_with?(label)

          "#{label} #{text}".strip
        end

        # 飛び先が無かった見出し。原稿の誤りではないので 🟡 にはせず、--log=debug でだけ出す
        def log_missing_items(missing)
          Common.log_debug("[Outline] 飛び先が見つからず、前の項目のページを指した見出し: #{missing.size} 件")
          missing.each { Common.log_debug("  - #{it[:chapter]} ##{it[:id]} #{it[:text]} (page=#{it[:page]})") }
        end

        module_function :extract_number_text, :validate_inputs, :build_chapter_paths, :build_chapter_order,
                        :supplement_basenames, :build_outline_items, :heading_top, :build_display_text,
                        :build_chapter_display_text, :resolve_chapter_number_display, :prepend_label_if_needed,
                        :log_missing_items
      end
    end
  end
end
