# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/frontispiece_estimate.rb
# ================================================================
# 責務:
#   章扉のリードが章扉に収まるかを、組まずに見積もる（chapter-lead-size-spec.md §4.4）。
#   preflight はこれで知らせ、build は直し方の案（倍率と字数の組）をこれで選ぶ。
#
# 見積もり方:
#   - リードが何行になるか: LeadLayout が 1 字ずつ並べて折る
#   - 章扉に何行入るか: 章扉の上下の並び（image-header.css の寸法）を足して、リードの始まる
#     高さを出し、版面の下端までに入る行を数える。章題の行数も LeadLayout が数える
#
#   3 冊・67 章のリードを、判型（A4・B5・A5）・倍率・字数・章番号の有無を変えて 11 通りに組み、
#   収まるかの判定を実物と比べると、737 件のうち 736 件で合った。外れた 1 件は、章番号のある章題が
#   text-wrap: balance で前から詰めたより 1 行多く折れたもの（章題の行数を少なく見て、収まると判定）。
#
# 寸法の出どころ:
#   image-header.css の章扉の寸法を、ここで同じ式で足し上げる。CSS を変えたらここも直すこと。
#   章番号の無い章でも、h1 の grid の 2 行目の gap は残る（実物の位置で確かめた）。
# ================================================================

require 'cgi'
require 'nokogiri'
require_relative 'lead_layout'
require_relative '../heading_segmenter'
require_relative '../units'

module VivlioStarter
  module CLI
    module Build
      module FrontispieceEstimate
        # 見積もる章。segments は章題の文節（用語集の印は "†"）、paragraphs はリードの段落のインラインの HTML
        Chapter = Data.define(:path, :title, :numbered, :segments, :paragraphs)

        # 見積もりの結果。lines はリードの行数、capacity は章扉に入る行数、fitted は章扉に残る行数
        # （段落が割れるときは widows・orphans の 2 行を守るので、capacity より少ないことがある）
        Layout = Data.define(:lines, :capacity, :fitted) do
          def fits? = lines <= capacity
          def overflow = lines - fitted
        end

        # page-settings.css の widows・orphans
        WIDOWS = 2
        ORPHANS = 2

        # 本の版面と書体（倍率と字数によらない部分）
        Page = Data.define(:height, :margin_top, :margin_bottom, :scale, :base_font_mm, :base_line_mm,
                           :text_width, :heading_offset, :heading_width, :lead_width, :fonts, :title_font)

        # theme.css の既定（book.yml に書いていないとき）
        DEFAULT_HEADING_WIDTH_MM = 103.7
        DEFAULT_LEAD_WIDTH_MM = 88.9

        # image-header.css の .chapter-title（行送り・字間）と .chapter-lead（行送り）
        TITLE_LINE_HEIGHT = 1.45
        TITLE_LETTER_SPACING = 0.08
        LEAD_LINE_HEIGHT = 1.7

        PX_PER_MM = 96 / 25.4

        module_function

        # --- 見積もり ---

        # @param chapter [Chapter]
        # @param page [Page]
        # @param size [Float] theme.frontispiece.lead_size（倍率）
        # @param chars [Integer, nil] theme.frontispiece.lead_chars（nil なら既定の幅）
        # @return [Layout]
        def layout(chapter, page, size:, chars:)
          font_mm = page.base_font_mm * size
          counts = LeadLayout.line_counts(chapter.paragraphs, fonts: page.fonts,
                                                              width_px: page.lead_width.(size, chars) * PX_PER_MM,
                                                              font_px: font_mm * PX_PER_MM)
          pitch = font_mm * LEAD_LINE_HEIGHT
          room = page.height - page.margin_bottom - lead_top(chapter, page)
          capacity = ((room / pitch) + 1e-6).floor
          Layout.new(lines: counts.sum, capacity:, fitted: fitted_lines(counts, capacity))
        end

        # 章扉に残る行数。段落が章扉の終わりで割れるとき、次のページへ送る行を WIDOWS 行より少なくせず、
        # 章扉に残す行が ORPHANS 行より少なければ段落ごと送る（build の「何行が次のページへ」と合わせる）
        def fitted_lines(counts, capacity)
          used = 0
          counts.each do |lines|
            room = capacity - used
            if lines > room
              kept = [room, lines - WIDOWS].min
              return kept >= ORPHANS ? used + kept : used
            end
            used += lines
          end
          used
        end

        # リードの最初の行の上端（紙の上端から mm）。image-header.css の章扉の上下の並びを足す:
        #   天の余白 → 見出しの下げ量 → h1 の上の内余白 → 章番号（あれば） → grid の行間 →
        #   章題 → 章題の下の余白 → h1 の下の内余白 → リードの上の余白
        def lead_top(chapter, page)
          s = page.scale
          padding = (6 * s).clamp(3, 8)
          gap = (2 * s).clamp(1, 2)
          number = chapter.numbered ? (10 * s).clamp(8, 12) + page.base_line_mm + (3 * s).clamp(2, 4) : 0.0
          title_mm = PreProcessCommands::BookSettingsCss.chapter_title_font_q(s) * 0.25
          title_lines = LeadLayout.title_line_count(chapter.segments, metrics: page.title_font,
                                                                      glossary_metrics: page.fonts.body,
                                                                      width_px: page.heading_width * PX_PER_MM,
                                                                      font_px: title_mm * PX_PER_MM,
                                                                      letter_spacing: TITLE_LETTER_SPACING)
          page.margin_top + page.heading_offset + padding + number + gap +
            (title_lines * title_mm * TITLE_LINE_HEIGHT) + (4 * s).clamp(2, 5) + padding + (5 * s).clamp(3, 5)
        end

        # --- 本の設定 ---

        # 今の book.yml の版面と書体。書体のファイルが見つからなければ nil（見積もらない）
        # @return [Page, nil]
        def current_page
          bsc = PreProcessCommands::BookSettingsCss
          embedder = PreProcessCommands::SvgFontEmbedder
          body = embedder.font_path(embedder.configured_body_font, weight: :regular)
          title = embedder.font_path(embedder.configured_heading_font, weight: :bold)
          return nil unless body && title && File.file?(body) && File.file?(title)

          page_cfg = bsc.build_page_cfg(Common::CONFIG)
          settings = PreProcessCommands::FrontmatterGenerator.parse_theme_settings
          scale = bsc.paper_scale_of(page_cfg)
          text_width = bsc.text_area_width_mm(page_cfg)
          bold = embedder.font_path(embedder.configured_body_font, weight: :bold)
          code = embedder.font_path(embedder.configured_code_font, weight: :regular)
          heading_chars = settings[:heading_chars_value]
          heading_width = heading_chars ? round_mm(heading_chars * bsc.chapter_title_advance_mm(scale)) : DEFAULT_HEADING_WIDTH_MM

          Page.new(
            height: mm(page_cfg[:height]), margin_top: mm(page_cfg[:margin_top]), margin_bottom: mm(page_cfg[:margin_bottom]),
            scale:, base_font_mm: mm(page_cfg[:base_font_size]) || (10.5 * 25.4 / 72), base_line_mm: mm(page_cfg[:base_line_height]) || 0.0,
            text_width:, heading_offset: mm(settings[:heading_offset_value]) || 0.0,
            heading_width: [heading_width, text_width].min,
            lead_width: ->(size, chars) { [lead_width_mm(page_cfg, size, chars), text_width].min },
            fonts: LeadLayout::Fonts.new(body: FontMetrics.load(body), bold: bold && File.file?(bold) ? FontMetrics.load(bold) : nil,
                                         code: code && File.file?(code) ? FontMetrics.load(code) : nil),
            title_font: FontMetrics.load(title)
          )
        rescue StandardError => e
          Common.log_debug("[preflight] 章扉の寸法を読めませんでした（見積もりません）: #{e.message}")
          nil
        end

        # リードの幅（mm）。BookSettingsCss が CSS に書く値と同じく、小数 2 桁に丸める
        # （heading_metric_declarations）。字数も倍率も既定なら theme.css の既定の幅
        def lead_width_mm(page_cfg, size, chars)
          bsc = PreProcessCommands::BookSettingsCss
          chars ||= bsc::DEFAULT_LEAD_CHARS unless size == bsc::DEFAULT_LEAD_SIZE
          chars ? round_mm(chars * bsc.chapter_lead_advance_mm(page_cfg, size)) : DEFAULT_LEAD_WIDTH_MM
        end

        def round_mm(value) = value.round(2)
        def mm(value) = Units.length_to_mm(value)

        # --- 原稿から章を取り出す（preflight） ---

        # 前処理と索引の走査を終えた原稿（ワークスペースの html/*.md）から、章扉のある章を取り出す
        # @return [Array<Chapter>]
        def chapters_from_markdown(entries)
          entries.filter_map do |entry|
            next unless entry.kind == :chapter

            source = File.join(Common::BUILD_HTML_DIR, "#{entry.basename}.md")
            next unless File.exist?(source)

            text = File.read(source, encoding: 'utf-8')
            heading = text[/^#[ \t]+(.+)$/, 1] or next
            lead = text[/^:{3,}[ \t]*\{\.chapter-lead\}[ \t]*\n(.*?)\n:{3,}[ \t]*$/m, 1] or next
            paragraphs = lead.split(/\n[ \t]*\n/).map { inline_html(it.strip.gsub(/[ \t]*\n[ \t]*/, ' ')) }.reject(&:empty?)
            next if paragraphs.empty?

            title_html = inline_html(heading)
            Chapter.new(path: entry.path || "#{entry.basename}.md", title: plain_text(title_html),
                        numbered: !PreProcessCommands::CrossReferenceProcessor.chapter_number_text_for(entry.basename).nil?,
                        segments: title_segments(title_html), paragraphs:)
          end
        end

        # 組んだ HTML から章を作る（build で、直し方の案を選ぶのに使う）
        # @param doc [Nokogiri::HTML::Document]
        # @param paragraphs [Array<Nokogiri::XML::Node>] リードの段落
        def chapter_from_html(path, title, doc, paragraphs)
          h1 = doc.at_css('h1')
          heading = h1&.at_css('.chapter-title') || h1
          Chapter.new(path:, title:, numbered: !h1&.at_css('.chapter-number').nil?,
                      segments: heading ? title_segments(heading) : [], paragraphs: paragraphs.map(&:inner_html))
        end

        # 原稿の行内の記法を、組んだときの HTML に近づける（字の幅を数えるのに要る分だけ）。
        # 索引の印・数式の画像・用語集の印は、前処理と索引の走査で既に HTML になっている
        def inline_html(markdown)
          markdown.to_s
                  .gsub(/(`+)(.+?)\1/) { "<code>#{CGI.escapeHTML(::Regexp.last_match(2).strip)}</code>" }
                  .gsub(/\*\*(.+?)\*\*|__(.+?)__/) { "<strong>#{::Regexp.last_match(1) || ::Regexp.last_match(2)}</strong>" }
                  .gsub(/!\[[^\]]*\]\([^)]*\)/, '')
                  .gsub(/\[([^\]]+)\]\([^)]*\)/, '\1')
                  .gsub(/\[\^[^\]]+\]/, '')
                  .gsub(/\{([^{}|]+)\|[^{}]+\}/, '\1')
                  .gsub(/\\([\\`*_{}\[\]()#+\-.!|])/, '\1')
        end

        def plain_text(html)
          fragment = Nokogiri::HTML.fragment(html.to_s)
          fragment.css('a.glossary-link, .vs-sec-anchor').each(&:remove)
          fragment.text.gsub(/[ \t\r\n]+/, ' ').strip
        end

        # 章題の文節。HeadingProcessor と同じく、文字のかたまり（要素の中の文字）ごとに語へ分ける。
        # 組んだ HTML なら、HeadingProcessor が付けた .vs-nobr をそのまま文節にする
        # @param html [String, Nokogiri::XML::Node] 章題（章番号を除く）
        def title_segments(html)
          segments = []
          walk = lambda do |node|
            node.children.each do |child|
              classes = child.element? ? child['class'].to_s.split : []
              if child.text?
                next if child.text.empty?

                if child.text.strip.empty?
                  # 文節のあいだの空白は、前の文節の後ろに付ける（折れ目になる）
                  segments[-1] += ' ' unless segments.empty? || segments[-1].end_with?(' ')
                else
                  segments.concat(HeadingSegmenter.segment(child.text))
                end
              elsif classes.include?('glossary-link')
                segments << '†'
              elsif classes.include?('vs-nobr')
                segments << child.text
              elsif !classes.include?('vs-sec-anchor')
                walk.(child)
              end
            end
          end
          walk.(html.is_a?(String) ? Nokogiri::HTML.fragment(html) : html)
          segments[0] = segments[0].lstrip unless segments.empty?
          segments.reject(&:empty?)
        end
      end
    end
  end
end
