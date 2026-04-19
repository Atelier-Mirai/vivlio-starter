# frozen_string_literal: true

require 'fileutils'

module Vivlio
  module Starter
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
        # ------------------------------------------------
        module PdfBuilder
          # 章レンジ（定数）- 新仕様に合わせて更新
          PREFACE_RANGE  = (0..0)   # 00-preface
          MAIN_RANGE     = (1..89)  # 01..89 本文
          APPX_RANGE     = (90..98) # 90..98 付録
          POSTFACE_RANGE = (99..99) # 99-postface

          module_function

          # Step 8: 全体PDF生成（ディレクトリスキャン版）
          # 前書き+目次+本文+付録+後書き+索引を1つのPDFとして生成
          # @param base_dir [String] ベースディレクトリ
          # @param entries_or_keep [Array<TokenResolver::Entry>, Array<String>, nil] Entry 配列または basename 配列
          def build_overall_pdf_from_dir!(base_dir = '.', entries_or_keep = nil)
            # 前付け: 00-preface + _toc
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

            # 書籍構成順序: 前書き → 目次 → [中扉+本文] → 付録 → 用語集 → 後書き → 索引
            # ※ 00-preface, _toc を先頭に含めることで target-counter が正しく解決される
            chapter_htmls_for_pdf = [
              preface_html,
              toc_html,
              main_htmls_with_parts,
              Build::ChapterConfig.htmls_for_range(base_dir, APPX_RANGE, keep_numbers_appx),
              glossary_html,
              Build::ChapterConfig.htmls_for_range(base_dir, POSTFACE_RANGE, keep_numbers_post),
              index_html
            ].flatten

            targets_for_pdf = chapter_htmls_for_pdf
            Common.log_info("[Step 7] targets_for_pdf: #{targets_for_pdf.map { |p| File.basename(p) }.join(', ')}")

            compile_overall_pdf!(targets_for_pdf)
          end

          # Step 7 (print_pdf only): entries.js のみ生成（PDF ビルドをスキップ）
          # print_pdf ターゲットのみの場合、entries.js は Step 13 で再利用される
          # @param base_dir [String] ベースディレクトリ
          # @param entries_or_keep [Array<TokenResolver::Entry>, Array<String>, nil]
          def generate_entries_for_sections!(base_dir = '.', entries_or_keep = nil)
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
                              [File.join(base_dir, '_glossarypage.html')].select do |f|
                                File.exist?(f)
                              end
                            else
                              []
                            end
            index_html = if IndexCommands.index_enabled?
                           [File.join(base_dir, '_indexpage.html')].select do |f|
                             File.exist?(f)
                           end
                         else
                           []
                         end

            # 本文章 HTML に中扉を挿入（部タイトルが定義されている場合）
            main_htmls = Build::ChapterConfig.htmls_for_range(base_dir, MAIN_RANGE, keep_numbers_main)
            main_htmls_with_parts = Build::PartTitleGenerator.insert_part_titles_into(main_htmls, base_dir)

            chapter_htmls_for_pdf = [
              preface_html,
              toc_html,
              main_htmls_with_parts,
              Build::ChapterConfig.htmls_for_range(base_dir, APPX_RANGE, keep_numbers_appx),
              glossary_html,
              Build::ChapterConfig.htmls_for_range(base_dir, POSTFACE_RANGE, keep_numbers_post),
              index_html
            ].flatten

            if chapter_htmls_for_pdf.empty?
              Common.log_warn('[Step 7] 対象HTMLが見つかりません。スキップします。')
              return
            end

            Common.log_info('[Step 7] entries.js を生成します（PDF ビルドはスキップ）')
            EntriesCommands.execute_entries({}, chapter_htmls_for_pdf)
            Common.log_success('[Step 7] entries.js を生成しました')
          end

          # 全体PDF生成（内部メソッド）
          # entries.jsを生成し、VivliostyleでPDFをビルド
          def compile_overall_pdf!(targets_for_pdf)
            if targets_for_pdf.empty?
              Common.log_warn('[Step 7] 対象HTMLが見つかりません。スキップします。')
              return
            end
            Common.log_info("[Step 7] 対象: #{targets_for_pdf.map { |p| File.basename(p) }.join(', ')}")

            EntriesCommands.execute_entries({}, targets_for_pdf)
            PdfCommands.execute_pdf({})

            pdf_config   = Common::CONFIG['pdf'] || {}
            output_pdf   = pdf_config['output_file'] || 'output.pdf'
            unless File.exist?(output_pdf)
              Common.log_warn("[Step 7] 出力PDFが見つかりません: #{output_pdf}")
              return
            end

            # 全体PDFをそのまま _sections.pdf として使用
            # これにより内部リンク（索引→00-preface等）が維持される
            FileUtils.cp(output_pdf, '_sections.pdf')
            Common.log_success('[Step 7] _sections.pdf を生成しました')
          end

          # Step 9: 本扉・扉裏・後書き・奥付の生成
          # 新仕様: _titlepage, _legalpage, _colophon を使用
          #
          # 設計方針: mtime 比較・キャッシュ判定は行わず、常に HTML と PDF を再生成する。
          # 計測上これらの生成はビルド全体への影響が軽微なため、判定ロジックの脆さ
          # （`FileUtils.cp` による mtime 破壊、book.yml 無関係変更での誤判定等）を
          # 排除する方を優先する。詳細は docs/specs/book_yml_regeneration_spec.md 参照。
          def build_front_pages_and_tail!
            # --- Phase: 特殊ページ HTML を常に再生成 ---
            %w[_titlepage _legalpage _colophon].each do |basename|
              Common.log_info("[HTML] 再生成します: #{basename}.html")
              Build::SectionBuilder.preprocess_single_chapter!(basename)
              Build::SectionBuilder.convert_single_chapter!(basename)
            end

            # --- Phase: 表紙＋扉裏 PDF を常に再生成 ---
            front_pdf = '_titlepage_legalpage.pdf'
            EntriesCommands.execute_entries({}, ['_titlepage.html', '_legalpage.html'])
            PdfCommands.execute_pdf({}, front_pdf)
            if File.exist?(front_pdf)
              Common.log_success("[Step 9] #{front_pdf} を生成しました")
            else
              Common.log_warn("[Step 9] #{front_pdf} の生成に失敗しました")
            end

            # --- Phase: 奥付 PDF を常に再生成 ---
            colophon_pdf = '_colophon.pdf'
            EntriesCommands.execute_entries({}, ['_colophon.html'])
            PdfCommands.execute_pdf({}, colophon_pdf)
            if File.exist?(colophon_pdf)
              Common.log_success('[Step 9] _colophon.pdf を生成しました')
            else
              Common.log_warn('[Step 9] _colophon.pdf の生成に失敗しました')
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
end
