# frozen_string_literal: true

require 'fileutils'

require_relative '../techbook/processor'
require_relative '../code_line_blocks'
require_relative 'pdf_page_map_extractor'
require_relative 'vivliostyle_config_writer'

module VivlioStarter
  module CLI
    module Build
      # ------------------------------------------------
      # PdfBuilder: PDF生成モジュール
      # ------------------------------------------------
      # Step 8: 全体PDF生成（前書き+目次+本文+付録+後書き+索引）
      # Step 9: 表紙・奥付PDF生成
      #
      # 設計方針:
      #   - PDF分割をスキップし、全体を1つのPDFとして生成
      #   - これにより索引から前書きへのリンクなど内部リンクが維持される
      #   - ローマ数字ノンブルはCSSの @page front で対応
      #
      # ワークスペース（P4 §3.1/§3.4）:
      #   共通 prep の成果（html/）を pdf/ へ無加工コピーし、pdf/ 内で
      #   用途別 entries/config（VivliostyleConfigWriter）によりビルドする。
      #   dedup の破壊的書換は pdf/ 配下のコピーに閉じ、html/ は常にクリーンな原本。
      # ------------------------------------------------
      module PdfBuilder
        # 章レンジ（定数）- 新仕様に合わせて更新
        PREFACE_RANGE  = (0..0)   # 00-preface
        MAIN_RANGE     = (1..89)  # 01..89 本文
        APPX_RANGE     = (90..98) # 90..98 付録
        POSTFACE_RANGE = (99..99) # 99-postface

        # 本文スパインの末尾へ相乗りさせる特殊ページ。並び順は最終的な綴じ順
        # （本扉 → 権利ページ → 奥付）と一致していること——結合時にこの順で
        # 切り出して並べ替えるため。
        SPECIAL_PAGE_BASENAMES = %w[_titlepage _legalpage _colophon].freeze

        module_function

        # html/ の全 HTML を pdf/ へ無加工コピーする（P4 §3.4-2）。
        # 4 兄弟 dir は同一深度のため、資産への相対参照は書き換え不要（§3.3）。
        def stage_workspace_htmls!
          FileUtils.mkdir_p(Common::BUILD_PDF_DIR)
          Dir.glob(File.join(Common::BUILD_HTML_DIR, '*.html')).each do |src|
            FileUtils.cp(src, File.join(Common::BUILD_PDF_DIR, File.basename(src)))
          end
          inject_matter_anchors!
          inject_rotate_table_anchors!
          convert_code_lines_for_pdf!
          # ビルド生成画像（数式 SVG）を pdf/ へミラーし、消費者 dir 相対の
          # images/math/… 参照を解決する（P4b §2.2）。存在すれば上書きコピー。
          images_src = File.join(Common::BUILD_HTML_DIR, 'images')
          return unless Dir.exist?(images_src)

          dest = File.join(Common::BUILD_PDF_DIR, 'images')
          FileUtils.mkdir_p(dest)
          FileUtils.cp_r(File.join(images_src, '.'), dest)
        end

        # 前付・奥付の staged HTML に、結合時にページ位置を引くための目印を埋める。
        #
        # vivliostyle が `/Dests` へ書き出すのは**リンクの飛び先になっている id だけ**で、
        # id を持つだけの要素は出てこない（実測: `<body id>` は出ず、自己参照リンクは出る。
        # 目次から参照される章見出しや脚注が dest を持つのはそのため）。前付・奥付は
        # どこからもリンクされないので、自分自身を指す空リンクを 1 つ足して目印にする。
        #
        # `position: absolute` で流れから外すのは、本扉・権利ページの body が
        # `display: grid` で行を明示しており、素の子要素を 1 つ足すと行の割り当てが
        # 1 つずつずれてレイアウトが崩れるため。インラインで書くのは、この目印が
        # 著者の意匠ではなくビルドの仕掛けで、CSS 側に散らしたくないから。
        #
        # 書き込むのは pdf/ のコピーだけ。html/ の原本はクリーンなままなので
        # EPUB / Kindle には現れない。
        def inject_matter_anchors!
          SPECIAL_PAGE_BASENAMES.each do |basename|
            path = File.join(Common::BUILD_PDF_DIR, "#{basename}.html")
            next unless File.exist?(path)

            html = File.read(path, encoding: 'utf-8')
            id = matter_anchor_id(basename)
            next if html.include?(id)

            anchor = %(<a id="#{id}" href="##{id}" style="position:absolute"></a>)
            File.write(path, html.sub(/<body[^>]*>/) { "#{it}#{anchor}" }, encoding: 'utf-8')
          end
        end

        # 目印のアンカー ID。著者が付ける id と衝突しないよう vs- 接頭辞を持つ。
        def matter_anchor_id(basename) = "vs-matter-#{basename.delete_prefix('_')}"

        # 回転テーブルのラッパ id（`rot-*`）を、リンクの飛び先にする。
        #
        # 前付・奥付とまったく同じ落とし穴で、**id を持つだけの要素は `/Dests` に出ない**。
        # 回転テーブルは本文からもどこからも参照されないため、素のままでは
        # 「この表は何ページ目に組まれたか」を PDF から引けない
        # （kindle-rotate-table-image-spec.md §4）。
        #
        # 前付・奥付と違い id は前処理が既に振っているので、ここで足すのは**リンクの側だけ**。
        # 飛び先の位置は id を持つラッパの位置なので、リンク自体はどこに置いてもよい。
        # body 直後へまとめて置くのが、レイアウトへの干渉が最も小さい。
        #
        # 書き込むのは pdf/ のコピーだけ。html/ の原本はクリーンなままなので
        # クリーン EPUB には現れない。
        def inject_rotate_table_anchors!
          Dir.glob(File.join(Common::BUILD_PDF_DIR, '*.html')).each do |path|
            html = File.read(path, encoding: 'utf-8')
            ids = html.scan(/\bid="(#{PreProcessCommands::TableConverter::ROTATE_ID_PREFIX}[^"]+)"/o).flatten.uniq
            next if ids.empty?

            links = ids.map { %(<a href="##{it}" style="position:absolute"></a>) }.join
            File.write(path, html.sub(/<body[^>]*>/) { "#{it}#{links}" }, encoding: 'utf-8')
          end
        end

        # コードブロックの中身を「1 論理行 = 1 span.vs-code-line」へ組み直す。
        #
        # Prism の .line-numbers-rows は固定行高のガターを絶対配置で並べるだけなので、
        # code.css が全 pre に掛ける white-space: pre-wrap で長行が折り返すと、番号と
        # 論理行がずれる（実測: 2 行に折り返した論理行の続きが次の番号を貰い、以降が 1 つずつ
        # 繰り上がって最終行の番号が消える）。EPUB が F 案で解いたのと同じ構造 ——
        # 行ブロック＋ぶら下げインデント —— を PDF にも敷く。
        # 分割の意味論は CodeLineBlocks が正典（EPUB と共有）。
        #
        # pre 自体は残す（枠・背景・フォントの既存 CSS をそのまま活かすため）。
        # 書き込むのは pdf/ のコピーだけなので、html/ の原本を読む EPUB 経路は影響を受けない。
        def convert_code_lines_for_pdf!
          Dir.glob(File.join(Common::BUILD_PDF_DIR, '*.html')).each do |path|
            doc = PostProcessCommands::HtmlParser.parse_html_document(File.read(path, encoding: 'utf-8'))
            targets = doc.css('pre.line-numbers')
            next if targets.empty?

            changed = targets.count { convert_code_pre_lines!(it, doc) }
            next if changed.zero?

            PostProcessCommands::HtmlParser.save_html_document(path, doc)
            Common.log_info("[PDF] #{File.basename(path)} のコード #{changed} 件を行ブロック化しました")
          end
        end

        # 1 つの pre.line-numbers の中身を行ブロックへ組み直す。失敗時は変更せず false。
        def convert_code_pre_lines!(pre, doc)
          code = pre.at_css('code')
          return false unless code

          # 絶対配置ガターは行ブロックが番号を持つので不要
          code.css('.line-numbers-rows').each(&:remove)

          lines = CodeLineBlocks.split(code)
          return false if lines.empty?

          code.inner_html = lines.map do |line_html|
            # 空行も 1 行ぶんの高さを保つ（空ブロックの潰れ防止）
            body = line_html.strip.empty? ? " " : line_html
            %(<span class="vs-code-line">#{body}</span>)
          end.join
          true
        rescue StandardError => e
          Common.log_warn("[PDF] コードの行ブロック化に失敗（元のまま維持）: #{e.message}")
          false
        end

        # 特殊ページ HTML（前付・奥付）だけを html/ から pdf/ へコピーする。
        # Step 9 で html/ に再生成された特殊ページを PDF 消費者へ届ける（P4 §3.4-5）。
        # @param basenames [Array<String>] 例: %w[_titlepage _legalpage _colophon]
        def stage_special_pages!(basenames)
          FileUtils.mkdir_p(Common::BUILD_PDF_DIR)
          basenames.each do |bn|
            src = File.join(Common::BUILD_HTML_DIR, "#{bn}.html")
            next unless File.exist?(src)

            FileUtils.cp(src, File.join(Common::BUILD_PDF_DIR, "#{bn}.html"))
          end
        end

        # Step 8: 全体PDF生成
        # 前書き+目次+本文+付録+後書き+索引を1つのPDFとして生成
        # @param entries_or_keep [Array<TokenResolver::Entry>, Array<String>, nil] Entry 配列または basename 配列
        def build_overall_pdf_from_dir!(entries_or_keep = nil)
          stage_workspace_htmls!
          targets_for_pdf = sections_entry_htmls(Common::BUILD_PDF_DIR, entries_or_keep)
          Common.log_info("[Step 7] targets_for_pdf: #{targets_for_pdf.map { |p| File.basename(p) }.join(', ')}")

          compile_overall_pdf!(targets_for_pdf)
        end

        # Step 7 (print_pdf only): 本文用 entries/config のみ生成（PDF ビルドをスキップ）
        # 生成した entries.sections.js / config は PrintPdfBuilder と dedup が再利用する
        def generate_entries_for_sections!(entries_or_keep = nil)
          stage_workspace_htmls!
          targets_for_pdf = sections_entry_htmls(Common::BUILD_PDF_DIR, entries_or_keep)

          if targets_for_pdf.empty?
            Common.log_warn('[Step 7] 対象HTMLが見つかりません。スキップします。')
            return
          end

          Common.log_info('[Step 7] 本文用 entries/config を生成します（PDF ビルドはスキップ）')
          VivliostyleConfigWriter.write!(name: 'sections', entry_htmls: targets_for_pdf,
                                         output: File.join(Common::BUILD_PDF_DIR, '_sections.pdf'))
          Common.log_success('[Step 7] entries.sections.js を生成しました')
        end

        # 書籍構成順（前書き → 目次 → [中扉+本文] → 付録 → 用語集 → 後書き → 索引）の
        # 本文エントリ HTML を base_dir から収集する。
        # ※ 00-preface, _toc を先頭に含めることで target-counter が正しく解決される
        # @param base_dir [String] HTML の置き場（pdf/）
        # @param entries_or_keep [Array<TokenResolver::Entry>, Array<String>, nil]
        # @return [Array<String>] 結合順の HTML パス配列
        def sections_entry_htmls(base_dir, entries_or_keep = nil)
          preface_html = [File.join(base_dir, '00-preface.html')].select { |f| File.exist?(f) }
          toc_html = [File.join(base_dir, '_toc.html')].select { |f| File.exist?(f) }

          keep_numbers_main = Build::Utilities.chapter_numbers_for_book(entries_or_keep)
          keep_numbers_appx = nil
          keep_numbers_post = nil
          if entries_or_keep&.any?
            chapter_numbers = extract_chapter_numbers(entries_or_keep)
            keep_numbers_appx = chapter_numbers.select { |n| APPX_RANGE.include?(n) }
            keep_numbers_post = chapter_numbers.select { |n| POSTFACE_RANGE.include?(n) }
          end
          glossary_html = if IndexCommands.index_enabled?
                            [File.join(base_dir, '_glossarypage.html')].select { |f| File.exist?(f) }
                          else
                            []
                          end
          index_html = if IndexCommands.index_enabled?
                         [File.join(base_dir, '_indexpage.html')].select { |f| File.exist?(f) }
                       else
                         []
                       end

          # 本文章 HTML に中扉を挿入（部タイトルが定義されている場合）
          main_htmls = Build::ChapterConfig.htmls_for_range(base_dir, MAIN_RANGE, keep_numbers_main)
          main_htmls_with_parts = Build::PartTitleGenerator.insert_part_titles_into(main_htmls, base_dir)

          [
            preface_html,
            toc_html,
            main_htmls_with_parts,
            Build::ChapterConfig.htmls_for_range(base_dir, APPX_RANGE, keep_numbers_appx),
            glossary_html,
            Build::ChapterConfig.htmls_for_range(base_dir, POSTFACE_RANGE, keep_numbers_post),
            index_html,
            special_page_htmls(base_dir)
          ].flatten
        end

        # 特殊ページ（本扉・権利ページ・奥付）の HTML パス。3 つ揃っているときだけ返す。
        #
        # 本文の**末尾**に足すのが要点。先頭に足すと本文のページ番号が 2 つずれ、
        # 目次の target-counter・索引・相互参照・dedup のページマップが軒並み動く。
        # 末尾なら本文のページ番号は 1 つも動かず、結合時に切り出して先頭へ回せばよい。
        #
        # 揃っていなければ空を返し、従来どおり個別レンダへ委ねる（欠けた状態で
        # 相乗りさせると、結合時のページ範囲を決められないため）。
        def special_page_htmls(base_dir)
          paths = SPECIAL_PAGE_BASENAMES.map { File.join(base_dir, "#{it}.html") }
          paths.all? { File.exist?(it) } ? paths : []
        end

        # 本文スパインに前付・奥付が載っているか（entries へ足したかどうかと同義）
        def special_pages_in_spine? = special_page_htmls(Common::BUILD_PDF_DIR).any?

        # 前付・奥付を個別にレンダしてよいかを検査し、駄目なら止める。
        #
        # 本文へ相乗り済みなのに位置が引けない状態で個別レンダすると、同じページが
        # **本文の中と結合列の両方に入って二重になる**（実測: 515 → 518 ページ）。
        # 静かに壊れた PDF を出すより、原因と対処を示して止めるほうがよい。
        def ensure_separate_render_is_safe!
          return unless special_pages_in_spine?

          Common.log_error('[前付・奥付] 本文 PDF に組まれているのにページ位置を特定できませんでした')
          Common.log_error('  個別にレンダすると同じページが二重に入るため、ビルドを中止します。')
          Common.log_error('  対処: vs build --clean で中間生成物を作り直してください。')
          exit 1
        end

        # 全体PDF生成（内部メソッド）
        # 本文用 entries/config を生成し、Vivliostyle で pdf/_sections.pdf を直接ビルドする。
        #
        # 閲覧用本文も Chrome の一過性失敗で本文欠落になり得るため、本文ガードで
        # 検証・リトライし、回復不能ならビルドを中断する（merge での degenerate を防ぐ）。
        def compile_overall_pdf!(targets_for_pdf)
          if targets_for_pdf.empty?
            Common.log_warn('[Step 7] 対象HTMLが見つかりません。スキップします。')
            return
          end
          Common.log_info("[Step 7] 対象: #{targets_for_pdf.map { |p| File.basename(p) }.join(', ')}")

          sections_pdf = File.join(Common::BUILD_PDF_DIR, '_sections.pdf')
          min_pages    = [(targets_for_pdf.size / 2.0).floor, 5].max

          Build::Utilities.build_pdf_with_body_guard!(sections_pdf, min_pages:) do
            config = VivliostyleConfigWriter.write!(name: 'sections', entry_htmls: targets_for_pdf,
                                                    output: sections_pdf)
            PdfCommands.execute_pdf({}, config_path: config, output_path: sections_pdf)
          end

          Common.log_success('[Step 7] _sections.pdf を生成しました')
        end

        # 本扉・権利ページ・奥付の Markdown と HTML を html/ に用意する（共通前段）。
        #
        # 本文レンダより前に置く理由は 2 つ。
        #   1. 本文スパインの末尾へ相乗りさせるので、レンダ開始時点で HTML が要る
        #   2. techbook 後処理（波ダッシュ置換・絵文字画像化・SVG→WebP 参照整合）が
        #      html/ を一括で舐めるため、そこへ間に合わせれば個別再適用が要らない
        # 前倒しできるのは、これら 3 ページの内容が book.yml 由来だけで、
        # 総ページ数のような「本文を組んだ結果」に依存しないからである。
        #
        # 設計方針: mtime 比較・キャッシュ判定は行わず常に再生成する。
        # 詳細は book_yml_regeneration_spec.md を参照。
        def generate_front_and_back_matter_html!
          CreateCommands.execute_titlepage(force: true)
          CreateCommands.execute_legalpage(force: true)
          CreateCommands.execute_colophon(force: true)

          SPECIAL_PAGE_BASENAMES.each do |basename|
            Common.log_info("[HTML] 再生成します: #{basename}.html")
            Build::SectionBuilder.preprocess_single_chapter!(basename)
            Build::SectionBuilder.convert_single_chapter!(basename)
          end
        end

        # 前付・奥付を単独レンダして `_titlepage_legalpage.pdf` / `_colophon.pdf` を作る。
        #
        # 本文へ相乗りできなかったとき（特殊ページの HTML が欠けている、
        # レンダ結果から位置を特定できない）だけ通るフォールバック経路。
        # vivliostyle は PDF を吐くたび約 22 秒の固定費がかかるため、
        # 通常経路ではここを通らない（front-back-matter-single-render-spec.md §0.1）。
        def build_front_pages_and_tail!
          stage_special_pages!(SPECIAL_PAGE_BASENAMES)
          build_special_page_pdf!(name: 'front', basenames: %w[_titlepage _legalpage],
                                  output_basename: '_titlepage_legalpage.pdf')
          build_special_page_pdf!(name: 'colophon', basenames: %w[_colophon],
                                  output_basename: '_colophon.pdf')
        end

        # 本文 PDF に相乗りした特殊ページのページ範囲。相乗りしていなければ nil。
        #
        # 位置は「末尾 3 ページ」と決め打ちせず `/Dests` から実測する。権利ページが
        # 2 ページに溢れることも、`chapter_pagebreak: verso` で白紙が挟まることもあり、
        # 数え間違えると**静かに隣のページを切り出す**という壊れ方をするためである。
        #
        # 同じ PDF に対して結合工程が複数回問い合わせるので、パス・mtime・サイズで
        # 覚えておく（1 回の走査が 93MB の PDF で約 0.8 秒）。
        #
        # @param sections_pdf [String] 本文 PDF のパス
        # @return [Hash{Symbol => Range}, nil] `{ body:, front:, colophon: }`
        def embedded_special_page_ranges(sections_pdf = File.join(Common::BUILD_PDF_DIR, '_sections.pdf'))
          return nil unless File.exist?(sections_pdf)

          stamp = [sections_pdf, File.mtime(sections_pdf), File.size(sections_pdf)]
          return @special_ranges if defined?(@special_ranges_stamp) && @special_ranges_stamp == stamp

          @special_ranges_stamp = stamp
          @special_ranges = compute_special_page_ranges(sections_pdf)
        rescue StandardError => e
          Common.log_warn("[Step 9] 本文 PDF から前付・奥付の位置を特定できませんでした: #{e.message}")
          nil
        end

        # `/Dests` から本扉と奥付の開始ページを引き、3 区間へ割る。
        # 本扉より前が本文、本扉から奥付の手前までが前付、奥付から末尾が奥付。
        def compute_special_page_ranges(sections_pdf)
          firsts = PdfPageMapExtractor.new(sections_pdf).document_first_pages
          title  = firsts['_titlepage']
          colo   = firsts['_colophon']
          total  = Build::Utilities.page_count(sections_pdf).to_i

          # 本文が空・順序が逆・末尾を超える、のいずれも「相乗りしていない」と見なす。
          # 中途半端な範囲で切り出すより、個別レンダへ退避したほうが安全。
          return nil unless title && colo && title > 1 && colo > title && colo <= total

          { body: (1..title - 1), front: (title..colo - 1), colophon: (colo..total) }
        end

        # 特殊ページ（前付/奥付）の PDF を用途別 config でビルドする
        def build_special_page_pdf!(name:, basenames:, output_basename:)
          entry_htmls = basenames.map { File.join(Common::BUILD_PDF_DIR, "#{it}.html") }
                                 .select { File.exist?(it) }
          output = File.join(Common::BUILD_PDF_DIR, output_basename)

          config = VivliostyleConfigWriter.write!(name:, entry_htmls:, output:)
          PdfCommands.execute_pdf({}, config_path: config, output_path: output)

          if File.exist?(output)
            Common.log_success("[Step 9] #{output_basename} を生成しました")
          else
            Common.log_warn("[Step 9] #{output_basename} の生成に失敗しました")
          end
        end

        # Entry 配列または basename 配列から章番号配列を抽出
        # @param entries_or_keep [Array<TokenResolver::Entry>, Array<String>]
        # @return [Array<Integer>] 章番号配列
        def extract_chapter_numbers(entries_or_keep)
          raw = Array(entries_or_keep).compact
          return [] if raw.empty?

          if raw.first.respond_to?(:number)
            raw.filter_map { it.number&.to_i }
          else
            resolver = TokenResolver::Resolver.new
            raw.filter_map { resolver.resolve_file(it).number&.to_i }
          end
        end
      end
    end
  end
end
