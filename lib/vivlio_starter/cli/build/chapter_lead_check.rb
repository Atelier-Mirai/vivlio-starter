# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/chapter_lead_check.rb
# ================================================================
# 責務:
#   image の章扉に収まらず、終わりが次のページへ送られたリードを、組んだ PDF から見つけて
#   🟡 で知らせる（chapter-lead-size-spec.md §4・改善案 #125 段階 2）。章ごとに縮める字数を、
#   book.yml にはすべての章が収まる lead_size・lead_chars の目安を添える。
#
# なぜ PDF を調べるのか:
#   リードが章扉に収まるかは、章題の行数・禁則・半角の字で決まり、組む前には見積もれない。
#   組み上がった PDF を開いて見るまで気づけなかった（spiral-ruby の第7部で、最後の 1 文が
#   次のページへ送られていた）。
#
# 調べ方:
#   1. 組んだ HTML から、章扉のある章（body.vs-header-image）のリードの段落を取る
#   2. PDF を pdftotext で 1 回読み、リードの頭のページに尾が無ければ、はみ出しの候補にする
#      （899 ページの合本で 2.1 秒）
#   3. 候補の 2 ページだけを -bbox-layout で読み、リードの字が通る行を、章扉のページと次の
#      ページに分けて数える。柱やノンブルの行は、リードの字の並びに無いので数えない
#
#   照合できない章（リードの文が PDF の文字と合わない）は黙って飛ばす。判定を誤ると、
#   収まっている章に「縮めて」と言うことになるので、見逃す方を選ぶ（§4.2）。
# ================================================================

require 'nokogiri'
require 'open3'

module VivlioStarter
  module CLI
    module Build
      module ChapterLeadCheck
        # リードの頭と尾の字数。この並びで PDF のページを探す
        PROBE = 15

        # 大きさの案の刻み（読みやすさのため。設定に書ける値の刻みは自由）
        SIZE_STEP = 0.05

        # 縮める字数の丸め
        CUT_UNIT = 10

        # 行の見積もりで、1 行あたり平均して空くとみる字数（estimated_lines）
        LINE_LOSS = 0.5

        # 比べる前に除く字。PDF の文字には行の折り返しと、用語の印「†」が混ざる
        IGNORED = /[[:space:]†­]/

        # 章扉のある章のリード。paragraphs は段落ごとの文字
        Lead = Data.define(:path, :title, :paragraphs)

        # はみ出したリード。fitted は章扉のページにある行数、overflow は次のページへ送られた行数
        Overflow = Data.define(:lead, :fitted, :overflow) do
          def lines = fitted + overflow
        end

        module_function

        # 組んだ PDF を調べ、章扉からはみ出したリードがあれば 🟡 で知らせる。
        # theme.style が image でない本・PDF が無いときは何もしない。
        #
        # @param pdf_path [String]
        # @param entries [Array<TokenResolver::Entry>] 組んだ章
        # @return [Array<Overflow>]
        def check!(pdf_path, entries)
          return [] unless image_style? && File.exist?(pdf_path)

          leads = collect_leads(entries)
          return [] if leads.empty?

          overflows = scan(pdf_path, leads)
          warn_overflows(overflows) unless overflows.empty?
          overflows
        rescue StandardError => e
          Common.log_warn("[pdf] 章扉のリードが収まっているかを調べられませんでした: #{e.message}")
          []
        end

        def image_style? = Common::CONFIG.theme.style.to_s.strip.downcase == 'image'

        # 組んだ HTML から、章扉のある章のリードを取る。付録は image の本でも vs-header-simple
        # なので入らない（前書きの章扉は入る）
        def collect_leads(entries)
          entries.filter_map do |entry|
            html = File.join(Common::BUILD_HTML_DIR, "#{entry.basename}.html")
            next unless File.exist?(html)

            doc = Nokogiri::HTML(File.read(html, encoding: 'utf-8'))
            next unless doc.at_css('body')&.[]('class').to_s.split.include?('vs-header-image')

            lead = doc.at_css('.chapter-lead') or next
            blocks = lead.css('p').empty? ? [lead] : lead.css('p')
            paragraphs = blocks.map { it.text.gsub(/[[:space:]]+/, ' ').strip }.reject(&:empty?)
            next if paragraphs.empty?

            Lead.new(path: entry.path || "#{entry.basename}.md", title: chapter_title(doc), paragraphs:)
          end
        end

        def chapter_title(doc)
          h1 = doc.at_css('h1') or return ''
          title = h1['data-chapter-title'].to_s.strip
          title.empty? ? h1.text.gsub(/[[:space:]]+/, ' ').strip : title
        end

        # @return [Array<Overflow>]
        def scan(pdf_path, leads)
          pages = page_texts(pdf_path)
          leads.filter_map do |lead|
            text = normalize(lead.paragraphs.join)
            next if text.size < PROBE * 2

            head = text[0, PROBE]
            tail = text[-PROBE..]
            # 頭の字の並びは、ほかのページにも出ることがある（前の部の終わりに「第3部は、…」と
            # 次の部を案内する文など。spiral-ruby で実際にあった）。頭のあるページをすべて試し、
            # 尾も同じページにあれば収まっている。無ければ、次のページへ続くページを探す
            firsts = pages.each_index.select { pages[it].include?(head) }
            next if firsts.empty? || firsts.any? { pages[it].include?(tail) }

            counts = firsts.lazy.filter_map { count_lines(pdf_path, it, text, head, tail) }.first
            next unless counts

            fitted, overflow = counts
            Overflow.new(lead:, fitted:, overflow:) if fitted.positive? && overflow.positive?
          end
        end

        # ページごとの文字（比べる形にしたもの）
        def page_texts(pdf_path)
          out, status = Open3.capture2('pdftotext', '-raw', pdf_path, '-', err: File::NULL)
          status.success? ? out.split("\f").map { normalize(it) } : []
        end

        # 章扉のページ（first・0 から数える）と次のページで、リードの字が通る行を数える。
        # 尾が次のページの頭で切れていても数えられるように、ページの文字ではなく、リードの
        # 一部である行だけをつないで照合する（柱・ノンブルの行がはさまると尾が見つからない）。
        #
        # @return [Array(Integer, Integer), nil] [章扉のページの行数, 次のページの行数]。照合できなければ nil
        def count_lines(pdf_path, first, text, head, tail)
          out, status = Open3.capture2('pdftotext', '-bbox-layout', '-f', (first + 1).to_s, '-l', (first + 2).to_s,
                                       pdf_path, '-', err: File::NULL)
          return nil unless status.success?

          lines = Nokogiri::HTML(out).css('page').each_with_index.flat_map do |page, index|
            page.css('line').map { [index, normalize(it.css('word').map(&:text).join)] }
          end
          lines = lines.select { |_, line| lead_line?(line, text) }

          joined = +''
          spans = lines.map do |index, line|
            start = joined.size
            joined << line
            [index, start...joined.size]
          end
          from = joined.index(head) or return nil
          to = joined.index(tail, from) or return nil

          hit = spans.filter_map { |index, span| index if span.begin < to + tail.size && from < span.end }
          [hit.count(0), hit.count(&:positive?)]
        end

        # リードの一部である行か。数字だけの行（ノンブル）は、リードの中に同じ数があっても除く
        def lead_line?(line, text) = !line.empty? && !line.match?(/\A\d+\z/) && text.include?(line)

        def normalize(text) = text.gsub(IGNORED, '')

        # --- 直し方の案 ---

        # すべてのはみ出しが収まる book.yml の案。出せないものは nil
        #
        # @param size [Float] 今の章扉の倍率（theme.frontispiece.lead_size、空なら theme.lead_size）
        # @param chars [Integer] 今の 1 行の字数（theme.frontispiece.lead_chars）
        # @param max_chars [#call] 倍率 → リードの幅が版面に収まる最大の字数
        # @return [Hash] { size: 倍率, chars: 字数, pair: [倍率, 字数] }
        def suggestions(overflows, size:, chars:, max_chars:)
          fits = ->(new_size, new_chars) { overflows.all? { fits?(it, size, chars, new_size, new_chars) } }
          sizes = smaller_sizes(size)
          # 大きさだけ。行数は変わらず、高さが倍率に比例して縮む（§1.1）
          size_only = sizes.find { fits.(it, chars) }
          # 大きさを下げ、幅が変わらないように字数を増やす（1.2 倍・28 字 → 1.1 倍・30 字の形）。
          # 大きさだけの案より字を大きく保てるときだけ出す（同じだけ下げるなら、大きさだけで足りる）
          pair = sizes.map { [it, keep_width_chars(chars, size, it)] }
                      .find { |new_size, new_chars| new_chars <= max_chars.(new_size) && fits.(new_size, new_chars) }
          pair = nil if pair && size_only && pair.first <= size_only
          {
            size: size_only,
            # 字数だけ。大きさはそのままで、1 行の字数を増やして行を減らす
            chars: ((chars + 1)..max_chars.(size)).find { fits.(size, it) },
            pair:
          }
        end

        # 倍率と字数を変えたとき、章扉に収まるか。行数は段落の字数から見積もり、今の字数での
        # 見積もりと PDF の実際の行数の比で補正する（禁則や半角の字で、割り算とずれるため）。
        # 行の高さは字の大きさに比例する（line-height は単位の無い倍率）
        def fits?(overflow, size, chars, new_size, new_chars)
          paragraphs = overflow.lead.paragraphs
          scale = overflow.lines.to_f / estimated_lines(paragraphs, chars)
          # ちょうど収まる値（24 行 × 1.05 / 1.2 = 21 行）を、小数の誤差で外さないよう、わずかに許す
          estimated_lines(paragraphs, new_chars) * scale * new_size / size <= overflow.fitted + 1e-9
        end

        # 段落ごとに、頭の 1 字下げを含めて何行になるか。
        # 1 行に入る字は、字数の指定より平均 LINE_LOSS 字少ないとみる。行頭に来られない字（、。」）や、
        # 途中で折れない語（BASIC・CRC・数）で、行の終わりが空くため。満杯で数えると、段落の最後の
        # 行がぎりぎり（9.91 行 → 10 行）の案を出し、組むと 1 行あふれた（spiral-ruby の 33 章・25 字）
        def estimated_lines(paragraphs, chars)
          paragraphs.sum { ((HeadingImageComposer.display_width(it) + 1) / (chars - LINE_LOSS)).ceil }
        end

        # 今より小さい倍率を、刻みにそろえて大きい順に（下限 1.0 まで）
        def smaller_sizes(size)
          min = PreProcessCommands::FrontmatterGenerator::LEAD_SIZE_RANGE.min
          top = ((size - SIZE_STEP + 1e-9) / SIZE_STEP).floor
          top.downto((min / SIZE_STEP).round).map { (it * SIZE_STEP).round(2) }
        end

        # 倍率を下げても幅が変わらない字数（切り上げ）。小数の誤差で 1 字多くならないよう、わずかに引く
        def keep_width_chars(chars, size, new_size) = ((chars * size / new_size) - 1e-9).ceil

        # --- 知らせ ---

        def warn_overflows(overflows)
          current = current_metrics
          lines = overflows.map { overflow_line(it, current[:chars]) }
          options = suggestion_lines(suggestions(overflows, size: current[:size], chars: current[:chars],
                                                            max_chars: current[:max_chars]), current)
          lines.push('book.yml で直すなら、次のどれか 1 つ:', *options.map { "  #{it}" }) unless options.empty?
          Common.log_warn("リードが章扉に収まらず、次のページへ送られている章があります（#{overflows.size} 章）",
                          detail: lines.join("\n"))
        end

        def overflow_line(overflow, chars)
          cut = ((overflow.overflow * chars).to_f / CUT_UNIT).ceil * CUT_UNIT
          lead = overflow.lead
          "#{lead.path}（#{lead.title}）: #{overflow.overflow} 行が次のページへ。リードを #{cut} 字ほど縮める"
        end

        # 今の章扉の倍率と字数。書いていない値は、何に従っているかを添えて見せる
        def current_metrics
          settings = PreProcessCommands::FrontmatterGenerator.parse_theme_settings
          bsc = PreProcessCommands::BookSettingsCss
          page_cfg = bsc.build_page_cfg(Common::CONFIG)
          text_mm = bsc.text_area_width_mm(page_cfg)
          raw = settings[:theme_cfg]&.dig(:frontispiece)
          written = raw.is_a?(String) ? nil : PreProcessCommands::FrontmatterGenerator.parse_lead_size(raw&.dig(:lead_size)).first
          {
            size: settings[:frontispiece_lead_size_value] || bsc::DEFAULT_LEAD_SIZE,
            chars: settings[:lead_chars_value] || bsc::DEFAULT_LEAD_CHARS,
            size_written: !written.nil?,
            chars_written: !settings[:lead_chars_value].nil?,
            max_chars: ->(size) { ((text_mm / bsc.chapter_lead_advance_mm(page_cfg, size)) + 1e-9).floor }
          }
        end

        def suggestion_lines(found, current)
          size_from = current[:size_written] ? format_size(current[:size]) : '（空欄）'
          chars_from = current[:chars_written] ? current[:chars].to_s : "#{current[:chars]}（既定）"
          lines = []
          lines << "theme.frontispiece.lead_size: #{size_from} → #{format_size(found[:size])}" if found[:size]
          lines << "theme.frontispiece.lead_chars: #{chars_from} → #{found[:chars]}" if found[:chars]
          if (pair = found[:pair])
            lines << "theme.frontispiece.lead_size: #{size_from} → #{format_size(pair[0])} と " \
                     "lead_chars: #{chars_from} → #{pair[1]}（リードの幅はそのまま）"
          end
          lines
        end

        # 1.05・1.1・1.0 のように書く（1.0 を「1」にしない）
        def format_size(value) = format('%.2f', value).sub(/(\.\d)0\z/, '\1')
      end
    end
  end
end
