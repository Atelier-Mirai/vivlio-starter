# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/chapter_lead_check.rb
# ================================================================
# 責務:
#   image の章扉に収まらず、終わりが次のページへ送られたリードを見つけて 🟡 で知らせる
#   （chapter-lead-size-spec.md §4・改善案 #125 段階 2）。章ごとに縮める字数を、
#   book.yml にはすべての章が収まる lead_size・lead_chars の組を添える。
#
# build と preflight で調べ方が違う:
#   - build（check!）: 組んだ PDF を読む。実物なので確か
#   - preflight（estimate!）: 組まずに見積もる（FrontispieceEstimate）。PDF を作らない preflight でも、
#     build と同じ知らせを出すため。章扉だけを組むと 20 秒ほど遅くなるので、計算で済ませる
#   直し方の案は、どちらも FrontispieceEstimate で倍率と字数の組を試して選ぶ。
#
# PDF の調べ方:
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
require_relative 'frontispiece_estimate'
require_relative '../pre_process/issue_registry'

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

        # 比べる前に除く字。PDF の文字には行の折り返しと、用語の印「†」が混ざる
        IGNORED = /[[:space:]†­]/

        # 章扉のある章のリード。paragraphs は段落ごとの文字（PDF と照らす）、chapter は見積もりに使う章
        Lead = Data.define(:path, :title, :paragraphs, :chapter)

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

        # 前処理を終えた原稿から、章扉からはみ出すリードを見積もって 🟡 で知らせる（preflight）。
        # 書体のファイルが見つからないなど、見積もれないときは何もしない。
        #
        # @param entries [Array<TokenResolver::Entry>]
        # @return [Array<Overflow>]
        def estimate!(entries)
          return [] unless image_style?

          page = FrontispieceEstimate.current_page or return []
          current = current_metrics
          overflows = FrontispieceEstimate.chapters_from_markdown(entries).filter_map do |chapter|
            layout = FrontispieceEstimate.layout(chapter, page, size: current[:size], chars: current[:chars_setting])
            next if layout.fits?

            lead = Lead.new(path: chapter.path, title: chapter.title, paragraphs: [], chapter:)
            # preflight の章別サマリーと最後の件数に入れる（まとめの 🟡 だけでは「問題なし」と出てしまう）
            PreProcessCommands::IssueRegistry.record(severity: :warn, category: :frontispiece, chapter: chapter.path,
                                                     message: 'リードが章扉に収まらない')
            Overflow.new(lead:, fitted: layout.fitted, overflow: layout.overflow)
          end
          warn_overflows(overflows, page:) unless overflows.empty?
          overflows
        rescue StandardError => e
          Common.log_warn("章扉のリードが収まるかを見積もれませんでした: #{e.message}")
          []
        end

        def image_style? = Common::CONFIG.theme.style.to_s.strip.downcase == 'image'

        # 組んだ HTML から、章扉のある章のリードを取る。付録は image の本でも vs-header-simple
        # なので入らない
        def collect_leads(entries)
          entries.filter_map do |entry|
            html = File.join(Common::BUILD_HTML_DIR, "#{entry.basename}.html")
            next unless File.exist?(html)

            doc = Nokogiri::HTML(File.read(html, encoding: 'utf-8'))
            next unless doc.at_css('body')&.[]('class').to_s.split.include?('vs-header-image')

            lead = doc.at_css('.chapter-lead') or next
            blocks = (lead.css('p').empty? ? [lead] : lead.css('p')).reject { it.text.strip.empty? }
            next if blocks.empty?

            path = entry.path || "#{entry.basename}.md"
            title = chapter_title(doc)
            Lead.new(path:, title:, paragraphs: blocks.map { it.text.gsub(/[[:space:]]+/, ' ').strip },
                     chapter: FrontispieceEstimate.chapter_from_html(path, title, doc, blocks))
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
            page.css('line').map { [index, it['ymin'].to_f, it['xmin'].to_f, normalize(it.css('word').map(&:text).join)] }
          end
          lines = same_height_joined(lines).select { |_, line| lead_line?(line, text) }

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

        # 高さのそろった行を 1 行にまとめ、[ページ, 字] の並びにする。行の途中に数式の画像があると、
        # pdftotext は画像の前と後ろを別の行として出す（画像は字を持たない）。まとめないと 1 行を
        # 2 行と数え、spiral-ruby の 22 章では 22 行の送りを 24 行と言っていた
        def same_height_joined(lines)
          lines.sort_by { |page, top, left, _| [page, top, left] }
               .chunk_while { |a, b| a[0] == b[0] && (a[1] - b[1]).abs < 1 }
               .map { |row| [row.first[0], row.map(&:last).join] }
        end

        # リードの一部である行か。数字だけの行（ノンブル）は、リードの中に同じ数があっても除く
        def lead_line?(line, text) = !line.empty? && !line.match?(/\A\d+\z/) && text.include?(line)

        def normalize(text) = text.gsub(IGNORED, '')

        # --- 直し方の案 ---

        # すべてのはみ出しが収まる、倍率と字数の組。今の倍率から小さい方へ、その倍率で収まる
        # いちばん少ない字数を添えて並べる（§4.1）。収まるかは FrontispieceEstimate で見積もる。
        #
        # 並べる倍率は、今の倍率（字数だけ増やす）、0.1 刻みの倍率、字数を変えずに収まる倍率
        # （大きさだけ下げる）。字数を変えずに収まる倍率より下は、字を小さくするだけなので並べない。
        # 倍率を下げても字数が減らない組も、字を小さくするだけなので落とす。
        # 大きさだけ下げても行数は変わらず、高さが倍率に比例して縮むだけなので（§1.1）、
        # はみ出しが大きいと大きさだけの組は出ない（1.2 倍から 1.0 倍へ下げても 17% しか縮まない）。
        #
        # 今の倍率では、今の字数より多い字数から探す。今の組ではみ出したことは分かっているので、
        # 見積もりが「収まる」と言っても今の組は案にしない（build の PDF で見つけたはみ出しのとき）。
        #
        # @param size [Float] 今の章扉の倍率（theme.frontispiece.lead_size、空なら theme.lead_size）
        # @param chars [Integer] 今の 1 行の字数（theme.frontispiece.lead_chars）
        # @param max_chars [#call] 倍率 → リードの幅が版面に収まる最大の字数
        # @param page [FrontispieceEstimate::Page]
        # @return [Array<Array(Float, Integer)>] [倍率, 字数] の組。出せなければ空
        def suggestions(overflows, size:, chars:, max_chars:, page:)
          fits = lambda do |new_size, new_chars|
            overflows.all? { FrontispieceEstimate.layout(it.lead.chapter, page, size: new_size, chars: new_chars).fits? }
          end
          smaller = smaller_sizes(size)
          size_only = smaller.find { fits.(it, chars) }
          sizes = [size, *smaller.select { tenth?(it) && (size_only.nil? || it > size_only) }, size_only].compact

          sizes.each_with_object([]) do |new_size, combos|
            from = new_size == size ? chars + 1 : chars
            new_chars = (from..max_chars.(new_size)).find { fits.(new_size, it) } or next
            combos << [new_size, new_chars] if combos.empty? || new_chars < combos.last[1]
          end
        end

        # 1.1・1.0 のような 0.1 刻みの倍率か
        def tenth?(value) = ((value * 10) - (value * 10).round).abs < 1e-9

        # 今より小さい倍率を、刻みにそろえて大きい順に（下限 1.0 まで）
        def smaller_sizes(size)
          min = PreProcessCommands::FrontmatterGenerator::LEAD_SIZE_RANGE.min
          top = ((size - SIZE_STEP + 1e-9) / SIZE_STEP).floor
          top.downto((min / SIZE_STEP).round).map { (it * SIZE_STEP).round(2) }
        end

        # --- 知らせ ---

        # @param page [FrontispieceEstimate::Page, nil] 見積もりに使う版面。nil なら今の book.yml から作る。
        #   作れなければ（書体が見つからない）直し方の案は添えない
        def warn_overflows(overflows, page: FrontispieceEstimate.current_page)
          current = current_metrics
          lines = overflows.map { overflow_line(it, current[:chars]) }
          combos = page ? suggestions(overflows, size: current[:size], chars: current[:chars], max_chars: current[:max_chars], page:) : []
          options = suggestion_lines(combos, current)
          lines.push(suggestion_heading(options.size), *options.map { "  #{it}" }) unless options.empty?
          Common.log_warn("リードが章扉に収まらず、次のページへ送られている章があります（#{overflows.size} 章）",
                          detail: lines.join("\n"))
        end

        def overflow_line(overflow, chars)
          cut = ((overflow.overflow * chars).to_f / CUT_UNIT).ceil * CUT_UNIT
          lead = overflow.lead
          "#{lead.path}（#{lead.title}）: #{overflow.overflow} 行が次のページへ。リードを #{cut} 字ほど縮める"
        end

        # 今の章扉の倍率と字数。書いていない値は、何に従っているかを添えて見せる。
        # chars_setting は book.yml に書いた字数（無ければ nil。既定の幅で見積もる）
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
            chars_setting: settings[:lead_chars_value],
            size_written: !written.nil?,
            chars_written: !settings[:lead_chars_value].nil?,
            max_chars: ->(size) { ((text_mm / bsc.chapter_lead_advance_mm(page_cfg, size)) + 1e-9).floor }
          }
        end

        # 案が 1 つなら「こう変えると」、2 つ以上なら「どれかにすると」。どの行も倍率と字数の組
        def suggestion_heading(count)
          change = count == 1 ? 'をこう変えると' : 'を次の組み合わせのどれかにすると'
          "book.yml の theme.frontispiece #{change}、すべての章が章扉に収まります:"
        end

        # 組ごとに 1 行。変えない方の値も「のまま」と書き、行だけで設定が読めるようにする
        def suggestion_lines(combos, current)
          size_from = current[:size_written] ? format_size(current[:size]) : '（空欄）'
          chars_from = current[:chars_written] ? current[:chars].to_s : "#{current[:chars]}（既定）"
          combos.map do |size, chars|
            size_part = size == current[:size] ? "#{size_from} のまま" : "#{size_from} → #{format_size(size)}"
            chars_part = chars == current[:chars] ? "#{chars_from} のまま" : "#{chars_from} → #{chars}"
            "lead_size: #{size_part}・lead_chars: #{chars_part}"
          end
        end

        # 1.05・1.1・1.0 のように書く（1.0 を「1」にしない）
        def format_size(value) = format('%.2f', value).sub(/(\.\d)0\z/, '\1')
      end
    end
  end
end
