# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/outline_extractor.rb
# ================================================================
# 責務:
#   HTML から見出しを抽出し、PDF のアウトライン（しおり）を生成する。
#
# 処理内容:
#   - HTML の h1/h2 要素から章・節タイトルを抽出
#   - 付録ラベル（付録A, 付録B...）の生成
#   - qpdf 用のアウトライン定義ファイル生成
#
# アウトライン構造:
#   - h1: 章見出し（第N章 タイトル）
#   - h2: 節見出し（N.M タイトル）
#   - 付録は「付録A」形式でラベリング
#
# 依存:
#   - Nokogiri: HTML パース
#   - HexaPDF: PDF メタデータ操作
# ================================================================

require 'nokogiri'
require 'open3'
require_relative '../index/index_match_scanner' # 用語集の印（GLOSSARY_INDICATOR）

module VivlioStarter
  module CLI
    module Build
      # HTML 見出し抽出・PDF アウトライン生成モジュール
      module OutlineExtractor
        class << self
          attr_accessor :last_outline_debug_info
        end
        @last_outline_debug_info = nil

        module_function

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

        # 見出しとページの対応を取得
        def heading_page_entries(pdf_path, html_paths, max_level: 3, start_page: 1)
          @last_outline_debug_info = nil
          return [] unless validate_inputs(pdf_path, html_paths)

          total_pages = (Build::Utilities.page_count(pdf_path) || '0').to_i
          return [] if total_pages <= 0

          from_base = start_page.to_i.clamp(1, total_pages)
          max_level = max_level.to_i.clamp(1, 6)

          chapter_paths = build_chapter_paths(html_paths)
          chapter_order = build_chapter_order(chapter_paths.keys)
          headings_by_chapter, chapter_markers = extract_all_headings(chapter_order, chapter_paths, max_level)
          search_helpers = build_search_helpers(pdf_path, total_pages)
          chapter_ranges = calculate_chapter_ranges(chapter_order, chapter_markers, search_helpers, from_base,
                                                    total_pages)
          items, fallback_items = build_outline_items(headings_by_chapter, chapter_ranges, chapter_order,
                                                      search_helpers, total_pages)
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
        def add_outline_from_headings!(pdf_path, html_files, max_level: 3, start_page: 1)
          require 'vivlio_starter/cli/pdf/provider'

          entries = heading_page_entries(pdf_path, html_files, max_level: max_level, start_page: start_page)
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
          unless Common.external_command_available?('pdftotext')
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

        def extract_all_headings(chapter_order, chapter_paths, max_level)
          headings_by_chapter = Hash.new { |h, k| h[k] = [] }
          chapter_markers = {}

          chapter_order.each do |bn|
            path = chapter_paths[bn]
            headings = if path
                         extract_headings_from_html_file(path, max_level: max_level,
                                                               include_appendix_label: true)
                       else
                         []
                       end
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
          page_texts = nil
          normalized_cache = {}
          # \u7A7A\u767D\u306B\u52A0\u3048\u3066\u3001\u7528\u8A9E\u96C6\u306E\u5370\uFF08\u2020\uFF09\u3082\u5916\u3057\u3066\u6BD4\u3079\u308B\u3002\u7D19\u9762\u306E\u7AE0\u6249\u3067\u306F\u7AE0\u984C\u306E\u7528\u8A9E\u306B\u5370\u304C\u4ED8\u304F\uFF08\u300C\u30AA\u30D6\u30B8\u30A7\u30AF\u30C8\u6307\u5411 \u2020 \u7DE8\u300D\uFF09\u304C\u3001
          # \u898B\u51FA\u3057\u306E\u6587\u5B57\u306B\u306F\u4ED8\u304B\u306A\u3044\u306E\u3067\u3001\u305D\u306E\u307E\u307E\u3067\u306F\u7AE0\u6249\u306B\u4E00\u81F4\u305B\u305A\u3001\u5370\u306E\u7121\u3044\u76EE\u6B21\u30DA\u30FC\u30B8\u306E\u7AE0\u984C\u306B\u4E00\u81F4\u3057\u3066\u3044\u305F
          mark = IndexCommands::IndexMatchScanner::GLOSSARY_INDICATOR
          normalize = ->(str) { str.to_s.gsub(/[[:space:]\u00A0\u2000-\u200B\u202F\u205F\u3000]+/, '').delete(mark) }

          # 全ページを pdftotext 1 回で読み、改ページ（\f）で分ける。1 ページずつ呼ぶと
          # 起動のたびに PDF を開き直し、300 ページの本で 10 秒ほどかかっていた
          fetch_page_text = lambda do |page|
            page_texts ||= read_page_texts(pdf_path)
            page_texts[page.to_i.clamp(1, total_pages) - 1].to_s
          end

          find_page_in_pdf = lambda do |term, from_page, to_page|
            term = term.to_s.strip
            return nil if term.empty?

            normalized_term = normalize.call(term)
            from_page = from_page.to_i.clamp(1, total_pages)
            to_page = to_page.to_i.clamp(from_page, total_pages)
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

          # ページ「先頭付近の見出し」として term が現れる最初のページを返す。
          # 本文中の偶発的な語（例: 前書き本文に出てくる「目次」）に誤マッチせず、
          # そのセクションが実際に始まるページを特定するために用いる。
          # 直前に柱（ランニングヘッダ）が入る可能性を考慮し、先頭の有意行 2 行を見る。
          # 章扉で番号と題が 2 行に分かれる組み方（「第1部」「基礎編」）もあるので、2 行をつないだものとも比べる。
          # 比べないと、章扉に「第1章」が出ない本で、本文の奥の「第1章」という見出しを最初の章の位置と取り違えた
          find_page_by_first_line = lambda do |term, from_page, to_page|
            normalized_term = normalize.call(term)
            return nil if normalized_term.empty?

            from_page = from_page.to_i.clamp(1, total_pages)
            to_page = to_page.to_i.clamp(from_page, total_pages)
            return nil if from_page > to_page

            (from_page..to_page).each do |page|
              lead = fetch_page_text.call(page).to_s.lines.map(&:strip).reject(&:empty?).first(2)
              return page if [*lead, lead.join].any? { |line| normalize.call(line) == normalized_term }
            end
            nil
          end

          { search_markers: search_markers, find_page_by_first_line: find_page_by_first_line }
        end

        # ページごとの文字。pdftotext は各ページの終わりに \f を出すので、\f の後ろで切る
        # （1 ページずつ呼んだときと同じく、各ページの文字は \f で終わる）
        # @return [Array<String>] 1 ページ目から順に
        def read_page_texts(pdf_path)
          text, = Open3.capture2('pdftotext', '-enc', 'UTF-8', pdf_path, '-', err: File::NULL)
          text.force_encoding('utf-8').split(/(?<=\f)/)
        end

        # 目次見出し（例: 「目次」）を取得する。注釈対象 PDF 内で目次ページを
        # 「ページ先頭テキスト」として特定するために用いる。_toc.html の見出しから取得し、
        # 取得できない場合は既定値「目次」を返す（旧実装の _toc.pdf 依存を解消）。
        # _toc.html はワークスペースの html/ に置かれる（P4 §3.4-1）
        def toc_heading_title
          toc_html = File.join(Common::BUILD_HTML_DIR, '_toc.html')
          return '目次' unless File.exist?(toc_html)

          doc = Nokogiri::HTML.parse(File.read(toc_html, encoding: 'utf-8'))
          h1 = doc.at_css('h1')
          title = h1 ? (h1['data-h1'].to_s.strip.empty? ? h1.text : h1['data-h1']).to_s.strip : ''
          title.empty? ? '目次' : title
        rescue StandardError
          '目次'
        end

        def calculate_chapter_ranges(chapter_order, chapter_markers, search_helpers, from_base, total_pages)
          chapter_starts = {}
          chapter_ranges = {}
          # 最初の本文章と、先頭の前書きを特定（_titlepage, _legalpage, _toc は除外）
          resolver = TokenResolver::Resolver.new
          kinds = chapter_order.to_h { [it, resolver.resolve_file(it).kind] }
          first_chapter_bn = chapter_order.find { kinds[it] == :chapter }
          preface_bn = chapter_order.find { kinds[it] == :preface }
          postfaces = chapter_order.select { kinds[it] == :postface }

          # 前付（preface）・目次（toc）のページ数を、注釈対象の結合 PDF から直接算出する。
          preface_pages, toc_pages = detect_front_matter_spans(
            chapter_markers, search_helpers, from_base, total_pages, first_chapter_bn
          )

          ctx = build_page_range_context(
            chapter_ranges, chapter_starts, chapter_markers,
            search_helpers, from_base, total_pages, preface_pages, toc_pages
          ).merge(preface_bn:, postfaces:)

          prev_bn = nil
          chapter_order.each do |bn|
            start_page, end_page = calculate_page_range(bn, ctx, first_chapter_bn, prev_bn)
            update_previous_chapter_end(chapter_ranges, prev_bn, start_page, total_pages)

            chapter_starts[bn] = start_page
            chapter_ranges[bn] = [start_page, end_page]
            prev_bn = bn
          end

          clamp_all_ranges(chapter_ranges, from_base, total_pages)
        end

        # 前付（preface）・目次（toc）のページ数を、注釈対象の結合 PDF
        # （output.pdf / output_print.pdf）から「ページ先頭の見出し」テキスト検出で算出する。
        #
        # 旧実装は補助 PDF `00-preface.pdf` / `_toc.pdf` のページ数に依存していたが、これらは
        # 閲覧用パイプライン専用の副産物で、print_pdf 単独ビルドでは生成されない。その結果、
        # 入稿用 PDF のしおりが目次ページへ集中する不具合があった。注釈対象の PDF そのものから
        # 算出することで pdf / print_pdf を同一ロジックに統一し、前書きを書かない書籍
        # （00-preface 不在）でも破綻しないようにする。
        #
        # 目次・最初の本文章は「ページ先頭が見出し」のページとして特定する（前書き本文や
        # 目次一覧に同じ語が現れても誤マッチしない）。最初の本文章の目次項目は目次の先頭ページに
        # あり、探索は toc_start+1 以降に限るため、目次一覧へ吸い寄せられることはない。
        #
        # @return [Array(Integer, Integer)] [preface のページ数, toc のページ数]
        def detect_front_matter_spans(chapter_markers, search_helpers, from_base, total_pages, first_chapter_bn)
          find_first_line = search_helpers[:find_page_by_first_line]
          # タイトル・権利の 2 ページ後が前付/目次の開始候補（表紙ぶんは from_base に含まれる）。
          front_start = (from_base + 2).clamp(1, total_pages)

          # 目次ページを特定。前書きが無ければ front_start 自体が目次になり preface_pages=0。
          toc_start = find_first_line.call(toc_heading_title, front_start, total_pages)
          return [0, 0] unless toc_start

          preface_pages = toc_start > front_start ? toc_start - front_start : 0

          # 最初の本文章のページを特定し、目次のページ数を確定する。
          # 章扉ページではページ先頭に「第1章」だけが出て、フルタイトルは画像化・改行などで
          # ページ先頭一致しないことがある（フルタイトルは柱として後続ページに現れる）。
          # マーカーごとの一致ページの最小値を採り、最も早い＝実際の章開始ページを選ぶ。
          first_chapter_start = Array(chapter_markers[first_chapter_bn]).filter_map do |term|
            find_first_line.call(term, toc_start + 1, total_pages)
          end.min
          toc_pages = first_chapter_start && first_chapter_start > toc_start ? first_chapter_start - toc_start : 1

          [preface_pages, toc_pages]
        end

        def update_previous_chapter_end(chapter_ranges, prev_bn, start_page, total_pages)
          return unless prev_bn && chapter_ranges[prev_bn]

          prev_end = [start_page - 1, total_pages].min
          prev_end = chapter_ranges[prev_bn][0] if prev_end < chapter_ranges[prev_bn][0]
          chapter_ranges[prev_bn][1] = prev_end
        end

        def clamp_all_ranges(chapter_ranges, from_base, total_pages)
          chapter_ranges.each_value do |rng|
            next unless rng

            rng[0] = rng[0].clamp(from_base, total_pages)
            rng[1] = rng[1].clamp(rng[0], total_pages)
          end

          chapter_ranges
        end

        # ページ範囲計算用のコンテキストハッシュを構築
        def build_page_range_context(chapter_ranges, chapter_starts, chapter_markers,
                                     search_helpers, from_base, total_pages, preface_pages, toc_pages)
          {
            chapter_ranges: chapter_ranges, chapter_starts: chapter_starts,
            chapter_markers: chapter_markers,
            search_markers: search_helpers[:search_markers],
            find_page_by_first_line: search_helpers[:find_page_by_first_line],
            from_base: from_base, total_pages: total_pages,
            preface_pages: preface_pages, toc_pages: toc_pages
          }
        end

        # 前書きは先頭の 1 本だけを前付の位置で数える。2 本目以降の前書きは本文と同じく見出しで探す
        def calculate_page_range(basename, ctx, first_chapter_bn, prev_bn)
          case basename
          when '_titlepage' then page_range_titlepage(ctx)
          when '_legalpage' then page_range_legalpage(ctx)
          when ctx[:preface_bn] then page_range_preface(ctx)
          when '_toc'       then page_range_toc(ctx)
          when '_glossarypage' then page_range_backmatter(basename, ctx, prev_bn, ['用語集'])
          when *ctx[:postfaces] then page_range_backmatter(basename, ctx, prev_bn, ['終わりに'])
          when '_indexpage' then page_range_backmatter(basename, ctx, prev_bn, ['索引'])
          when first_chapter_bn then page_range_first_chapter(ctx, prev_bn)
          else page_range_default(basename, ctx, prev_bn)
          end
        end

        # タイトルページ = 基点ページ（from_base）。
        # from_base には output.pdf 先頭に結合される表紙 PDF のページ数オフセットが含まれる。
        def page_range_titlepage(ctx)
          page = ctx[:from_base].clamp(1, ctx[:total_pages])
          [page, page]
        end

        # 権利表記ページ = タイトルページの次（from_base + 1）。
        def page_range_legalpage(ctx)
          page = (ctx[:from_base] + 1).clamp(1, ctx[:total_pages])
          [page, page]
        end

        # 前書き = タイトル・権利の 2 ページ後（from_base + 2）から開始。
        def page_range_preface(ctx)
          start_page = (ctx[:from_base] + 2).clamp(1, ctx[:total_pages])
          end_page = if ctx[:preface_pages].positive?
                       (start_page + ctx[:preface_pages] - 1).clamp(1,
                                                                    ctx[:total_pages])
                     else
                       start_page
                     end
          [start_page, end_page]
        end

        # 目次 = 前付の後ろ。detect_front_matter_spans が目次の見出しで見つけたページ（前付の始まり + 前付のページ数）。
        # 先頭の前書きの範囲の終わりからは数えない。2 本目以降の前書きや全巻目次が見つかると、先頭の前書きの
        # 終わりがその手前に切られるので、目次の始まりが前へずれる。すると目次の終わりも本当の目次の途中になり、
        # 章のしおりが、その後ろの目次ページに載った章題へ吸い寄せられる（前書き 4 本の本で、章の大半が目次を指した）
        def page_range_toc(ctx)
          start_page = (ctx[:from_base] + 2 + ctx[:preface_pages]).clamp(1, ctx[:total_pages])
          end_page = if ctx[:toc_pages].positive?
                       (start_page + ctx[:toc_pages] - 1).clamp(1,
                                                                ctx[:total_pages])
                     else
                       start_page
                     end
          [start_page, end_page]
        end

        def page_range_first_chapter(ctx, prev_bn)
          toc_end = ctx[:chapter_ranges]['_toc']&.[](1)
          start_candidate = toc_end ? toc_end + 1 : (ctx[:chapter_starts][prev_bn] || ctx[:from_base])
          [[start_candidate, ctx[:from_base]].max.clamp(1, ctx[:total_pages]), ctx[:total_pages]]
        end

        # 巻末ページ（用語集、終わりに、索引）のページ範囲を計算
        # これらのタイトル（用語集/終わりに/索引）は前書き本文や目次の一覧にも
        # 文字列として現れるため、単純な全文検索では誤マッチする。
        # 「ページ先頭の見出し」として現れるページを優先的に特定し、
        # 見つからない場合のみ従来の全文検索へフォールバックする。
        def page_range_backmatter(basename, ctx, prev_bn, default_markers)
          search_from = [ctx[:chapter_starts][prev_bn] || ctx[:from_base], ctx[:from_base]].max.clamp(1,
                                                                                                      ctx[:total_pages])
          markers = ctx[:chapter_markers][basename] || default_markers
          start_page = find_section_start_by_first_line(ctx, markers, search_from)
          start_page ||= search_page_with_fallback(ctx[:search_markers], markers, search_from, ctx[:from_base],
                                                   ctx[:total_pages])
          [start_page, ctx[:total_pages]]
        end

        # markers のいずれかが「ページ先頭付近の見出し」として現れる最初のページを返す。
        def find_section_start_by_first_line(ctx, markers, search_from)
          finder = ctx[:find_page_by_first_line]
          return nil unless finder

          Array(markers).each do |term|
            page = finder.call(term, search_from, ctx[:total_pages])
            return page if page
          end
          nil
        end

        # 章の始まりは、目印のどれかがページ先頭の見出しとして現れる最も早いページ。見つからないときだけ全文で探す。
        # 全文で目印を順に試すと、章扉に出ない目印（「第2章」を出さず「第2部」と組む本）が、本文の奥の
        # 「第2章」という見出しや文中の語に先に一致し、章のしおりがそこへ飛んでいた
        def page_range_default(basename, ctx, prev_bn)
          search_from = [ctx[:chapter_starts][prev_bn] || ctx[:from_base], ctx[:from_base]].max.clamp(1,
                                                                                                      ctx[:total_pages])
          markers = ctx[:chapter_markers][basename] || []
          start_page = markers.filter_map { ctx[:find_page_by_first_line].call(it, search_from, ctx[:total_pages]) }.min
          start_page ||= search_page_with_fallback(ctx[:search_markers], markers, search_from, ctx[:from_base],
                                                   ctx[:total_pages])
          [start_page, ctx[:total_pages]]
        end

        def search_page_with_fallback(search_markers, markers, search_from, from_base, total_pages)
          start_page = search_markers.call(markers, search_from, total_pages)
          start_page ||= search_markers.call(markers, from_base, total_pages) if search_from > from_base
          start_page || search_from
        end

        def build_outline_items(headings_by_chapter, chapter_ranges, _chapter_order, search_helpers, total_pages)
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
                       search_terms = (Array(heading[:search_terms]) + [heading[:text],
                                                                        heading[:appendix_label]]).compact.map do |s|
                         s.to_s.strip
                       end.reject(&:empty?).uniq
                       found_page = search_markers.call(search_terms, range[0], range[1])
                       found_page ||= search_markers.call(search_terms, range[0], total_pages)
                       unless found_page
                         fallback_items << { chapter: bn, text: heading[:text], target_page: range[0],
                                             search_terms: search_terms }
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

        def add_toc_entry(items, chapter_ranges, chapter_order, search_helpers)
          return items unless chapter_ranges['_toc']

          toc_range = chapter_ranges['_toc']
          title = toc_heading_title
          toc_page = search_helpers[:search_markers].call([title], toc_range[0], toc_range[1]) || toc_range[0]

          return items if items.any? { |it| it[:chapter] == '_toc' }

          insert_index = items.index do |it|
            chapter_order.index(it[:chapter])&.> chapter_order.index('_toc')
          end || items.length
          items.insert(insert_index, { level: 1, text: title, page: toc_page, chapter: '_toc', id: nil })
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
          # しおりは文字だけなので、扉で改行させる <br> などのタグは外す
          cover_title = Common.plain_title(Common::CONFIG.book.main_title)
          cover_title = '表紙' if cover_title.empty?

          return items if items.any? { |it| it[:page].to_i == 1 && it[:text] == cover_title }

          items.unshift({ level: 1, text: cover_title, page: 1, chapter: '_titlepage', id: nil })
          items
        end

        module_function :extract_number_text, :extract_title_text, :build_search_terms,
                        :validate_inputs, :build_chapter_paths, :build_chapter_order, :supplement_basenames,
                        :extract_all_headings, :build_search_helpers, :read_page_texts, :toc_heading_title,
                        :calculate_chapter_ranges, :detect_front_matter_spans,
                        :build_page_range_context, :calculate_page_range,
                        :page_range_titlepage, :page_range_legalpage, :page_range_preface,
                        :page_range_toc, :page_range_first_chapter, :page_range_backmatter,
                        :find_section_start_by_first_line,
                        :page_range_default, :search_page_with_fallback,
                        :update_previous_chapter_end, :clamp_all_ranges,
                        :build_outline_items, :build_display_text,
                        :build_chapter_display_text, :resolve_chapter_number_display, :prepend_label_if_needed,
                        :add_toc_entry, :log_fallback_items, :prepend_cover_item
      end
    end
  end
end
