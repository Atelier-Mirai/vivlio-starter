# frozen_string_literal: true

require 'fileutils'
require 'hexapdf'

module Vivlio
  module Starter
    module CLI
      module Build
        # ------------------------------------------------
        # PdfBuilder: PDF生成・分割モジュール
        # ------------------------------------------------
        # Step 7, 8, 9 の PDF 生成・分割処理を担当する。
        # ------------------------------------------------
        module PdfBuilder
          # 章レンジ（定数）- 新仕様に合わせて更新
          PREFACE_RANGE  = (0..0)   # 00-preface
          MAIN_RANGE     = (1..89)  # 01..89 本文
          APPX_RANGE     = (90..98) # 90..98 付録
          POSTFACE_RANGE = (99..99) # 99-postface

          module_function

          # Step 7: 全体PDF生成→分割（ディレクトリスキャン版）
          def build_overall_pdf_and_split_from_dir!(base_dir = '.', keep = nil)
            # 前付け: 00-preface + _toc
            preface_html = [File.join(base_dir, '00-preface.html')].select { |f| File.exist?(f) }
            toc_html = [File.join(base_dir, '_toc.html')].select { |f| File.exist?(f) }

            keep_numbers_main = Build::Utilities.chapter_numbers_for_book(keep)
            keep_numbers_appx = nil
            keep_numbers_post = nil
            if keep&.any?
              normalized_keep = Array(keep).map { |s| File.basename(s.to_s, '.md') }
              chapter_numbers = normalized_keep.map { |bn| Common.get_chapter_number(bn) }.compact.map(&:to_i)
              chapter_numbers.select { |n| PREFACE_RANGE.include?(n) }
              keep_numbers_appx = chapter_numbers.select { |n| APPX_RANGE.include?(n) }
              keep_numbers_post = chapter_numbers.select { |n| POSTFACE_RANGE.include?(n) }
            end
            index_html = [File.join(base_dir, '_indexpage.html')].select { |f| File.exist?(f) }

            # 書籍構成順序: 前書き → 目次 → 本文 → 付録 → 後書き → 索引
            # ※ 00-preface, _toc を先頭に含めることで target-counter が正しく解決される
            chapter_htmls_for_pdf = [
              preface_html,
              toc_html,
              Build::ChapterConfig.htmls_for_range(base_dir, MAIN_RANGE, keep_numbers_main),
              Build::ChapterConfig.htmls_for_range(base_dir, APPX_RANGE, keep_numbers_appx),
              Build::ChapterConfig.htmls_for_range(base_dir, POSTFACE_RANGE, keep_numbers_post),
              index_html
            ].flatten

            targets_for_pdf = chapter_htmls_for_pdf
            Common.log_info("[Step 7] targets_for_pdf: #{targets_for_pdf.map { |p| File.basename(p) }.join(', ')}")

            compile_overall_pdf_and_split!(targets_for_pdf, keep)
          end

          # Step 7: 全体PDF生成（分割なし）
          # 新仕様: 00-preface + _toc を含めて全体をビルドし、target-counter を正しく解決
          # PDF分割をスキップすることで、索引から00-prefaceへのリンクを維持
          def compile_overall_pdf_and_split!(targets_for_pdf, _keep = nil)
            if targets_for_pdf.empty?
              Common.log_warn('[Step 7] 対象HTMLが見つかりません。Step 7 をスキップします。')
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

            # PDF分割をスキップ: 全体PDFをそのまま _sections.pdf として使用
            # これにより内部リンク（索引→00-preface等）が維持される
            # ローマ数字ノンブルはCSSの @page front で対応済み
            Common.log_info('[Step 7] PDF分割をスキップ（内部リンク維持のため）')
            FileUtils.cp(output_pdf, '_sections.pdf')
            Common.log_success('[Step 7] _sections.pdf を生成しました（全体PDF、分割なし）')
          end

          # 前付け（00-preface + _toc）のページ数を計算
          # Step 6 で生成された _toc.pdf のページ数から推定
          # 00-preface のページ数は全体 PDF から逆算
          def calculate_frontmatter_pages(targets_for_pdf)
            # entries.js から frontmatter の位置を特定
            frontmatter_count = 0

            targets_for_pdf.each do |path|
              basename = File.basename(path)
              case basename
              when '00-preface.html', '_toc.html'
                frontmatter_count += 1
              else
                break # frontmatter 以外が出てきたら終了
              end
            end

            # frontmatter が含まれていない場合は 0 を返す
            return 0 if frontmatter_count.zero?

            # _toc.pdf のページ数を取得（Step 6 で生成済み）
            toc_pages = (Build::Utilities.page_count('_toc.pdf') || '0').to_i

            # 00-preface が含まれている場合、推定ページ数を追加
            # 通常、前書きは 2-4 ページ程度と仮定
            preface_pages = 0
            if targets_for_pdf.any? { |p| File.basename(p) == '00-preface.html' }
              # 前書きのページ数を推定（偶数に丸める）
              preface_pages = estimate_preface_pages
            end

            Common.log_info("[Step 7] preface_pages: #{preface_pages}, toc_pages: #{toc_pages}")
            preface_pages + toc_pages
          end

          # 前書きのページ数を推定
          # contents/00-preface.md の行数からおおよそのページ数を計算
          def estimate_preface_pages
            preface_md = File.join(Common::CONTENTS_DIR, '00-preface.md')
            return 2 unless File.exist?(preface_md) # デフォルト 2 ページ

            lines = File.readlines(preface_md, encoding: 'utf-8').size
            # 約 50 行で 1 ページと仮定（A4、10.5pt フォント）
            pages = (lines / 50.0).ceil
            # 最低 2 ページ、偶数に丸める
            pages = [pages, 2].max
            pages += 1 if pages.odd?
            pages
          end

          # Step 8: スキップ（ローマ数字ノンブルはCSSで対応済み）
          # PDF分割をスキップしたため、_preface_toc.pdf は生成されない
          # ローマ数字ノンブルは stylesheets/toc.css の @page front で対応
          def build_frontmatter_pdf!(_keep = nil)
            Common.log_action('[Step 8] スキップ（ローマ数字ノンブルはCSSで対応済み）')
            Common.log_info('[Step 8] PDF分割をスキップしたため、HexaPDFによるノンブル描画は不要')
          end

          # frontmatter PDF の仕上げ処理（奇数ページ調整、ラベル、ノンブル）
          def finalize_frontmatter_pdf
            pages = (Build::Utilities.page_count('_preface_toc.pdf') || '0').to_i
            if pages.odd?
              doc = HexaPDF::Document.open('_preface_toc.pdf')
              first_box = doc.pages[0].box(:media)
              doc.pages.add([first_box.left, first_box.bottom, first_box.right, first_box.top])
              doc.write('_preface_toc.pdf', optimize: true)
              Common.log_info('[Step 8] _preface_toc.pdf が奇数ページのため、空白1ページを末尾に挿入しました')
            end

            PageNumberer.apply_page_labels_hexapdf('_preface_toc.pdf', 0)
            if PageNumberer.overlay_roman_page_numbers!('_preface_toc.pdf')
              Common.log_success('[Step 8] _preface_toc.pdf にローマ小を描画しました')
            else
              Common.log_warn('[Step 8] _preface_toc.pdf へのローマ小描画をスキップ/失敗')
            end
          end

          # Step 9: 本扉・扉裏・後書き・奥付の生成
          # 新仕様: _titlepage, _legalpage, _colophon を使用
          def build_front_pages_and_tail!(force = false)
            front_regenerated = false
            Build::SectionBuilder.ensure_chapter_html_up_to_date!('_titlepage',
                                                                  extra_sources: File.join('config', 'book.yml'))
            Build::SectionBuilder.ensure_chapter_html_up_to_date!('_legalpage',
                                                                  extra_sources: File.join('config', 'book.yml'))
            Build::SectionBuilder.ensure_chapter_html_up_to_date!('_colophon',
                                                                  extra_sources: File.join('config', 'book.yml'))

            front_srcs = [
              File.join(Common::CONTENTS_DIR, '_titlepage.md'),
              File.join(Common::CONTENTS_DIR, '_legalpage.md'),
              File.join('config', 'book.yml')
            ]
            colophon_srcs = [
              File.join(Common::CONTENTS_DIR, '_colophon.md'),
              File.join('config', 'book.yml')
            ]

            newer_than_any = lambda do |target, sources|
              return true unless File.exist?(target)

              t_mtime = File.exist?(target) ? File.mtime(target) : Time.at(0)
              Array(sources).any? { |s| File.exist?(s) && File.mtime(s) > t_mtime }
            end

            front_pdf = '_titlepage_legalpage.pdf'
            colophon_pdf = '_colophon.pdf'
            cache_on = Common.cache_enabled? && !force
            cache_dir = cache_on ? Common.ensure_cache_dir! : nil
            front_cache = cache_on && cache_dir ? File.join(cache_dir, front_pdf) : nil
            colophon_cache = cache_on && cache_dir ? File.join(cache_dir, colophon_pdf) : nil

            front_missing = !File.exist?(front_pdf)
            front_missing &&= !Build::Utilities.cache_restore_file(cache_on, front_cache, front_pdf, 'Step 9')

            colophon_missing = !File.exist?(colophon_pdf)
            colophon_missing &&= !Build::Utilities.cache_restore_file(cache_on, colophon_cache, colophon_pdf, 'Step 9')

            need_front = force || front_missing || newer_than_any.call(front_pdf, front_srcs)

            if need_front
              EntriesCommands.execute_entries({}, ['_titlepage.html', '_legalpage.html'])
              PdfCommands.execute_pdf({}, front_pdf)
              if File.exist?(front_pdf)
                Common.log_success("[Step 9] #{front_pdf} を生成しました")
                Build::Utilities.cache_store_file(cache_on, front_pdf, front_cache, 'Step 9')
                front_regenerated = true
              else
                Common.log_warn("[Step 9] #{front_pdf} の生成に失敗しました")
              end
            else
              Common.log_action("[Step 9] フロント/奥付PDFは最新のため再利用します: #{front_pdf}, #{colophon_pdf}")
              unless File.exist?(front_pdf)
                Build::Utilities.cache_restore_file(cache_on, front_cache, front_pdf,
                                                    'Step 9')
              end
              unless File.exist?(colophon_pdf)
                Build::Utilities.cache_restore_file(cache_on, colophon_cache, colophon_pdf,
                                                    'Step 9')
              end
            end

            need_colophon = force || front_regenerated || colophon_missing || newer_than_any.call(colophon_pdf,
                                                                                                  colophon_srcs)
            if need_colophon
              EntriesCommands.execute_entries({}, ['_colophon.html'])
              PdfCommands.execute_pdf({}, colophon_pdf)
              if File.exist?(colophon_pdf)
                Common.log_success('[Step 9] _colophon.pdf を生成しました')
                Build::Utilities.cache_store_file(cache_on, colophon_pdf, colophon_cache, 'Step 9')
              else
                Common.log_warn('[Step 9] _colophon.pdf の生成に失敗しました')
              end
            else
              Common.log_info('[Step 9] 奥付は最新のため、再生成をスキップしました（既存/キャッシュを利用）')
            end
          end
        end
      end
    end
  end
end
