# frozen_string_literal: true

require 'fileutils'

require_relative '../techbook/processor'
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

        module_function

        # html/ の全 HTML を pdf/ へ無加工コピーする（P4 §3.4-2）。
        # 4 兄弟 dir は同一深度のため、資産への相対参照は書き換え不要（§3.3）。
        def stage_workspace_htmls!
          FileUtils.mkdir_p(Common::BUILD_PDF_DIR)
          Dir.glob(File.join(Common::BUILD_HTML_DIR, '*.html')).each do |src|
            FileUtils.cp(src, File.join(Common::BUILD_PDF_DIR, File.basename(src)))
          end
          # ビルド生成画像（数式 SVG）を pdf/ へミラーし、消費者 dir 相対の
          # images/math/… 参照を解決する（P4b §2.2）。存在すれば上書きコピー。
          images_src = File.join(Common::BUILD_HTML_DIR, 'images')
          return unless Dir.exist?(images_src)

          dest = File.join(Common::BUILD_PDF_DIR, 'images')
          FileUtils.mkdir_p(dest)
          FileUtils.cp_r(File.join(images_src, '.'), dest)
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
            index_html
          ].flatten
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
            PdfCommands.execute_pdf({}, nil, config_path: config, output_path: sections_pdf)
          end

          Common.log_success('[Step 7] _sections.pdf を生成しました')
        end

        # Step 9: 本扉・扉裏・後書き・奥付の生成
        # 新仕様: _titlepage, _legalpage, _colophon を使用
        #
        # 設計方針: mtime 比較・キャッシュ判定は行わず、常に .md / HTML / PDF を再生成する。
        # 詳細は docs/specs/book_yml_regeneration_spec.md を参照。
        def build_front_pages_and_tail!
          # --- Phase: 特殊ページ HTML を常に再生成（html/ へ） ---
          special_basenames = %w[_titlepage _legalpage _colophon]
          special_basenames.each do |basename|
            Common.log_info("[HTML] 再生成します: #{basename}.html")
            Build::SectionBuilder.preprocess_single_chapter!(basename)
            Build::SectionBuilder.convert_single_chapter!(basename)
          end

          # Step 9 で生成されたタイトル・奥付 HTML は Step 5c より後に作られるため、
          # 波ダッシュ置換 / 絵文字画像化 / SVG→WebP 参照整合 / CSS 注入をここで再適用する。
          special_html_files = special_basenames.map { File.join(Common::BUILD_HTML_DIR, "#{it}.html") }
          Techbook::Processor.new(Common::CONFIG).post_process_html_files!(special_html_files)

          # --- Phase: pdf/ へステージングして前付・奥付 PDF を生成 ---
          stage_special_pages!(special_basenames)
          build_special_page_pdf!(name: 'front', basenames: %w[_titlepage _legalpage],
                                  output_basename: '_titlepage_legalpage.pdf')
          build_special_page_pdf!(name: 'colophon', basenames: %w[_colophon],
                                  output_basename: '_colophon.pdf')
        end

        # 特殊ページ（前付/奥付）の PDF を用途別 config でビルドする
        def build_special_page_pdf!(name:, basenames:, output_basename:)
          entry_htmls = basenames.map { File.join(Common::BUILD_PDF_DIR, "#{it}.html") }
                                 .select { File.exist?(it) }
          output = File.join(Common::BUILD_PDF_DIR, output_basename)

          config = VivliostyleConfigWriter.write!(name:, entry_htmls:, output:)
          PdfCommands.execute_pdf({}, nil, config_path: config, output_path: output)

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
