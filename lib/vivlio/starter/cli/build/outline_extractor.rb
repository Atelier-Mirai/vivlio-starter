# frozen_string_literal: true

require 'nokogiri'
require 'hexapdf'

module Vivlio
  module Starter
    module CLI
      module Build
        # ------------------------------------------------
        # OutlineExtractor: 見出し抽出・アウトラインモジュール
        # ------------------------------------------------
        # HTMLからの見出し抽出、PDFアウトライン生成を担当する。
        # ------------------------------------------------
        module OutlineExtractor
          # 章レンジ（定数）
          APPX_RANGE = (91..97)

          class << self
            attr_accessor :last_outline_debug_info
          end
          @last_outline_debug_info = nil

          module_function

          # 付録ラベル取得
          def appendix_label_for_basename(basename)
            number = Common.get_chapter_number(basename)
            return nil unless number && APPX_RANGE.include?(number.to_i)

            letter = Common.appendix_number_to_letter(number)
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
              heading_attr = node['data-heading'].to_s.strip

              number_text = extract_number_text(node, lvl)
              title_text = extract_title_text(node, lvl, text)

              search_terms = build_search_terms(number_text, title_text, heading_attr, text, appendix_label)

              headings << {
                level: lvl,
                text: text,
                chapter: chapter_token,
                id: node['id'].to_s.strip,
                appendix_label: appendix_label,
                search_terms: search_terms,
                number_display: number_text
              }
            end
            headings
          end

          # Markdownファイルから見出しを抽出
          def extract_headings_from_markdown_file(path, max_level: 2)
            headings = []
            return headings unless File.exist?(path)

            title = nil
            subtitles = []
            File.foreach(path, encoding: 'utf-8') do |line|
              stripped = line.strip
              if max_level >= 1 && title.nil? && stripped.start_with?('# ')
                title = stripped.sub('\A#\\s+', '').strip
                next
              end
              subtitles << stripped.sub('\A##\\s+', '').strip if max_level >= 2 && stripped.start_with?('## ')
              break if max_level <= 2 && !title.nil? && !subtitles.empty?
            end
            headings << { level: 1, text: title } if title && !title.empty?
            if max_level >= 2
              subtitles.each do |text|
                next if text.empty?
                headings << { level: 2, text: text }
              end
            end
            headings
          end

          # 見出しとページの対応を取得
          def heading_page_entries(pdf_path, html_paths, max_level: 3, start_page: 1)
            @last_outline_debug_info = nil
            return [] unless validate_inputs(pdf_path, html_paths)

            total_pages = (Build::Utilities.page_count(pdf_path) || '0').to_i
            return [] if total_pages <= 0

            from_base = [[start_page.to_i, 1].max, total_pages].min
            max_level = [[max_level.to_i, 1].max, 6].min

            chapter_paths = build_chapter_paths(html_paths)
            chapter_order = build_chapter_order(chapter_paths.keys)
            headings_by_chapter, chapter_markers = extract_all_headings(chapter_order, chapter_paths, max_level)
            search_helpers = build_search_helpers(pdf_path, total_pages)
            chapter_ranges = calculate_chapter_ranges(chapter_order, chapter_markers, search_helpers, from_base, total_pages)
            items, fallback_items = build_outline_items(headings_by_chapter, chapter_ranges, chapter_order, search_helpers, total_pages)
            items = add_toc_entry(items, chapter_ranges, chapter_order, search_helpers)

            log_fallback_items(fallback_items) if fallback_items.any?

            @last_outline_debug_info = {
              chapter_order: chapter_order.dup,
              chapter_starts: chapter_ranges.transform_values { |r| r[0] },
              chapter_ranges: chapter_ranges.transform_values(&:dup),
              items: items.map(&:dup)
            }

            items
          end

          # PDFにアウトラインを付与
          def add_outline_from_headings!(pdf_path, html_paths, max_level: 3, start_page: 1)
            items = heading_page_entries(pdf_path, html_paths, max_level: max_level, start_page: start_page)
            return false if items.empty?

            items = prepend_cover_item(items)
            write_outline_to_pdf(pdf_path, items, max_level)
            Common.log_success('[Outline] PDF にブックマーク（アウトライン）を付与しました')
            true
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

          def extract_title_text(node, lvl, fallback)
            title_text = case lvl
                         when 1 then node['data-chapter-title'].to_s.strip
                         when 2 then node['data-section-title'].to_s.strip
                         when 3 then node['data-subsection-title'].to_s.strip
                         else ''
                         end
            title_text.empty? ? fallback : title_text
          end

          def build_search_terms(number_text, title_text, heading_attr, text, appendix_label)
            search_terms = []
            if number_text && !number_text.empty?
              search_terms << "#{number_text}#{title_text}" unless title_text.empty?
              search_terms << "#{number_text} #{title_text}" unless title_text.empty?
              search_terms << number_text
            end
            search_terms << heading_attr unless heading_attr.empty?
            search_terms << text
            search_terms << appendix_label.to_s unless appendix_label.to_s.empty?
            search_terms.compact.map { |t| t.to_s.strip }.reject(&:empty?).uniq
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
            unless system('which pdftotext >/dev/null 2>&1')
              Common.log_warn('[Outline] pdftotext が見つかりません。`brew install poppler` を実行してください。')
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

          def build_chapter_order(html_basenames)
            chapter_order = Build::SectionBuilder.chapter_order_from(html_basenames)
            # 新仕様: _titlepage, _legalpage を使用
            frontmatter_sequence = %w[_titlepage _legalpage 00-preface _toc]
            (frontmatter_sequence + chapter_order).uniq
          end

          def extract_all_headings(chapter_order, chapter_paths, max_level)
            headings_by_chapter = Hash.new { |h, k| h[k] = [] }
            chapter_markers = {}

            chapter_order.each do |bn|
              path = chapter_paths[bn]
              headings = path ? extract_headings_from_html_file(path, max_level: max_level, include_appendix_label: true) : []
              headings_by_chapter[bn].concat(headings) if headings.any?

              primary = headings.find { |h| h[:level] == 1 } || headings.first
              if primary
                markers = Array(primary[:search_terms]) + [primary[:text]]
                chapter_markers[bn] = markers.compact.map { |s| s.to_s.strip }.reject(&:empty?).uniq
              end
            end

            [headings_by_chapter, chapter_markers]
          end

          def build_search_helpers(pdf_path, total_pages)
            page_cache = {}
            normalized_cache = {}
            normalize = ->(str) { str.to_s.gsub(/[[:space:]\u00A0\u2000-\u200B\u202F\u205F\u3000]+/, '') }

            fetch_page_text = lambda do |page|
              page = [[page.to_i, 1].max, total_pages].min
              page_cache[page] ||= `pdftotext -f #{page} -l #{page} "#{pdf_path}" - 2>/dev/null`
            end

            find_page_in_pdf = lambda do |term, from_page, to_page|
              term = term.to_s.strip
              return nil if term.empty?

              normalized_term = normalize.call(term)
              from_page = [[from_page.to_i, 1].max, total_pages].min
              to_page = [[to_page.to_i, total_pages].min, from_page].max
              return nil if from_page > to_page

              (from_page..to_page).each do |page|
                text = fetch_page_text.call(page)
                next if text.nil? || text.empty?
                return page if text.include?(term)

                normalized_text = normalized_cache[page] ||= normalize.call(text)
                return page if !normalized_term.empty? && normalized_text.include?(normalized_term)
              end
              nil
            end

            search_markers = lambda do |markers, from_page, to_page|
              Array(markers).each do |term|
                page = find_page_in_pdf.call(term, from_page, to_page)
                return page if page
              end
              nil
            end

            { search_markers: search_markers }
          end

          def calculate_chapter_ranges(chapter_order, chapter_markers, search_helpers, from_base, total_pages)
            search_markers = search_helpers[:search_markers]
            preface_pages = (Build::Utilities.page_count('00-preface.pdf') || '0').to_i
            toc_pages = (Build::Utilities.page_count('_toc.pdf') || '0').to_i

            chapter_starts = {}
            chapter_ranges = {}
            prev_bn = nil
            first_chapter_bn = chapter_order.find { |token| Common.get_file_type("#{token}.html") == 'chapter' }

            chapter_order.each do |bn|
              start_page, end_page = calculate_page_range(bn, chapter_order, chapter_markers, chapter_ranges, chapter_starts, search_markers, from_base, total_pages, preface_pages, toc_pages, first_chapter_bn, prev_bn)

              if prev_bn && chapter_ranges[prev_bn]
                prev_end = [start_page - 1, total_pages].min
                prev_end = chapter_ranges[prev_bn][0] if prev_end < chapter_ranges[prev_bn][0]
                chapter_ranges[prev_bn][1] = prev_end
              end

              chapter_starts[bn] = start_page
              chapter_ranges[bn] = [start_page, end_page]
              prev_bn = bn
            end

            chapter_ranges.each_value do |rng|
              next unless rng
              rng[0] = [[rng[0], from_base].max, total_pages].min
              rng[1] = [[rng[1], rng[0]].max, total_pages].min
            end

            chapter_ranges
          end

          def calculate_page_range(bn, chapter_order, chapter_markers, chapter_ranges, chapter_starts, search_markers, from_base, total_pages, preface_pages, toc_pages, first_chapter_bn, prev_bn)
            case bn
            when '_titlepage'
              [[from_base, 1].max, 1]
            when '_legalpage'
              start_page = [[2, from_base].max, total_pages].min
              [start_page, start_page]
            when '00-preface'
              start_page = [[3, from_base].max, total_pages].min
              end_page = preface_pages.positive? ? [start_page + preface_pages - 1, total_pages].min : start_page
              [start_page, end_page]
            when '_toc'
              start_candidate = preface_pages.positive? ? (chapter_ranges['00-preface']&.[](1) || (3 + preface_pages - 1)) + 1 : 3
              start_page = [[start_candidate, from_base].max, total_pages].min
              end_page = toc_pages.positive? ? [start_page + toc_pages - 1, total_pages].min : start_page
              [start_page, end_page]
            when first_chapter_bn
              toc_end = chapter_ranges['_toc']&.[](1)
              start_candidate = toc_end ? toc_end + 1 : (chapter_starts[prev_bn] || from_base)
              [[[start_candidate, from_base].max, total_pages].min, total_pages]
            when '99-colophon'
              [total_pages, total_pages]
            when '99-postface'
              search_from = [[chapter_starts[prev_bn] || from_base, from_base].max, total_pages].min
              markers = chapter_markers[bn] || ['終わりに']
              start_page = search_markers.call(markers, search_from, total_pages)
              start_page ||= search_markers.call(markers, from_base, total_pages) if search_from > from_base
              start_page ||= search_from
              end_page = [total_pages - 1, start_page].max
              [start_page, end_page]
            else
              search_from = [[chapter_starts[prev_bn] || from_base, from_base].max, total_pages].min
              markers = chapter_markers[bn] || []
              start_page = search_markers.call(markers, search_from, total_pages)
              start_page ||= search_markers.call(markers, from_base, total_pages) if search_from > from_base
              start_page ||= search_from
              [start_page, total_pages]
            end
          end

          def build_outline_items(headings_by_chapter, chapter_ranges, chapter_order, search_helpers, total_pages)
            search_markers = search_helpers[:search_markers]
            items = []
            fallback_items = []

            headings_by_chapter.each do |bn, headings|
              range = chapter_ranges[bn]
              next unless range

              headings.each do |heading|
                page = if bn == '_toc'
                         range[0]
                       else
                         search_terms = (Array(heading[:search_terms]) + [heading[:text], heading[:appendix_label]]).compact.map { |s| s.to_s.strip }.reject(&:empty?).uniq
                         found_page = search_markers.call(search_terms, range[0], range[1])
                         found_page ||= search_markers.call(search_terms, range[0], total_pages)
                         unless found_page
                           fallback_items << { chapter: bn, text: heading[:text], target_page: range[0], search_terms: search_terms }
                           found_page = range[0]
                         end
                         found_page
                       end

                display_text = build_display_text(bn, heading)
                items << { level: heading[:level], text: display_text, page: page, chapter: bn, id: heading[:id] }
              end
            end

            [items, fallback_items]
          end

          def build_display_text(bn, heading)
            display_text = heading[:text]
            if bn == '99-colophon' && heading[:level].to_i == 1
              '奥付'
            elsif heading[:appendix_label] && heading[:level].to_i == 1
              label = heading[:appendix_label].to_s.strip
              !label.empty? && !display_text.start_with?(label) ? "#{label} #{display_text}".strip : display_text
            elsif heading[:level].to_i == 1
              number_display = heading[:number_display].to_s.strip
              if number_display.empty?
                chapter_number = Common.get_chapter_number(bn)
                number_display = "第#{chapter_number.to_i - 10}章" if chapter_number && chapter_number.to_i.between?(11, 89)
              end
              !number_display.to_s.empty? && !display_text.start_with?(number_display) ? "#{number_display} #{display_text}".strip : display_text
            else
              display_text
            end
          end

          def add_toc_entry(items, chapter_ranges, chapter_order, search_helpers)
            return items unless chapter_ranges['_toc']

            toc_range = chapter_ranges['_toc']
            toc_page = search_helpers[:search_markers].call(['目次'], toc_range[0], toc_range[1]) || toc_range[0]

            return items if items.any? { |it| it[:chapter] == '_toc' }

            insert_index = items.index { |it| chapter_order.index(it[:chapter])&.> chapter_order.index('_toc') } || items.length
            items.insert(insert_index, { level: 1, text: '目次', page: toc_page, chapter: '_toc', id: nil })
            items
          end

          def log_fallback_items(fallback_items)
            return unless Common.current_log_level >= 3

            Common.log_warn('[Outline] 以下の見出しはページ検出に失敗したため章先頭へフォールバックしました:')
            fallback_items.each do |fb|
              Common.log_warn("  - #{fb[:chapter]} ##{fb[:text]} (fallback page=#{fb[:target_page]})")
            end
          end

          def prepend_cover_item(items)
            book_cfg = Common::CONFIG.fetch('book', {}) rescue {}
            main_title = book_cfg.fetch('main_title', '').to_s.strip
            fallback_title = book_cfg.fetch('title', '').to_s.strip
            cover_title = main_title.empty? ? fallback_title : main_title
            cover_title = '表紙' if cover_title.empty?

            return items if items.any? { |it| it[:page].to_i == 1 && it[:text] == cover_title }

            items.unshift({ level: 1, text: cover_title, page: 1, chapter: '_titlepage', id: nil })
            items
          end

          def write_outline_to_pdf(pdf_path, items, max_level)
            doc = HexaPDF::Document.open(pdf_path)
            root = doc.outline

            if root[:First]
              existing_items = []
              root.each_item { |item, _| existing_items << item }
              existing_items.each { |item| doc.delete(item) rescue nil }
              root.delete(:First)
              root.delete(:Last)
              root.delete(:Count)
            end

            parents = { 1 => root }
            items.each do |it|
              lvl = [[it[:level].to_i, 1].max, max_level].min
              parents.keys.select { |k| k > lvl }.each { |k| parents.delete(k) }
              parent = parents[lvl] || parents[parents.keys.select { |k| k < lvl }.max] || root
              parents[lvl] = parent
              page_obj = doc.pages[it[:page] - 1]
              parent.add_item(it[:text], destination: [page_obj, :Fit]) do |node|
                parents.keys.select { |k| k > lvl }.each { |k| parents.delete(k) }
                parents[lvl + 1] = node
              end
            end

            doc.write(pdf_path, optimize: true)
          end

          module_function :extract_number_text, :extract_title_text, :build_search_terms,
                          :validate_inputs, :build_chapter_paths, :build_chapter_order,
                          :extract_all_headings, :build_search_helpers, :calculate_chapter_ranges,
                          :calculate_page_range, :build_outline_items, :build_display_text,
                          :add_toc_entry, :log_fallback_items, :prepend_cover_item, :write_outline_to_pdf
        end
      end
    end
  end
end
