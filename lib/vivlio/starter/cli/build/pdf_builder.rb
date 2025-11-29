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
            toc_html = [File.join(base_dir, '_toc.html')].select { |f| File.exist?(f) }
            keep_numbers_main = Build::Utilities.chapter_numbers_for_book(keep)
            keep_numbers_preface = nil
            keep_numbers_appx = nil
            keep_numbers_post = nil
            if keep&.any?
              normalized_keep = Array(keep).map { |s| File.basename(s.to_s, '.md') }
              chapter_numbers = normalized_keep.map { |bn| Common.get_chapter_number(bn) }.compact.map(&:to_i)
              keep_numbers_preface = chapter_numbers.select { |n| PREFACE_RANGE.include?(n) }
              keep_numbers_appx = chapter_numbers.select { |n| APPX_RANGE.include?(n) }
              keep_numbers_post = chapter_numbers.select { |n| POSTFACE_RANGE.include?(n) }
            end
            chapter_htmls_for_pdf = [
              Build::ChapterConfig.htmls_for_range(base_dir, MAIN_RANGE, keep_numbers_main),
              Build::ChapterConfig.htmls_for_range(base_dir, APPX_RANGE, keep_numbers_appx),
              Build::ChapterConfig.htmls_for_range(base_dir, POSTFACE_RANGE, keep_numbers_post)
            ].flatten

            pdf_target_names = chapter_htmls_for_pdf.map { |p| File.basename(p) }
            toc_target_names = toc_html.map { |p| File.basename(p) }
            targets_for_pdf = chapter_htmls_for_pdf + toc_html
            Common.log_info("[Step 7] targets_for_pdf: #{(pdf_target_names + toc_target_names).join(', ')}")

            compile_overall_pdf_and_split!(targets_for_pdf, keep)
          end

          # Step 7: 全体PDF生成 → toc(目次)とsections(本文+付録+後書き)に分割
          def compile_overall_pdf_and_split!(targets_for_pdf, _keep = nil)
            if targets_for_pdf.empty?
              Common.log_warn('[Step 7] 対象HTMLが見つかりません。Step 7 をスキップします。')
              return
            end
            Common.log_info("[Step 7] 対象: #{targets_for_pdf.map { |p| File.basename(p) }.join(', ')}")

            Vivlio::Starter::ThorCLI.start(['entries', *targets_for_pdf])
            Vivlio::Starter::ThorCLI.start(['pdf'])

            pdf_config   = Common::CONFIG['pdf'] || {}
            output_pdf   = pdf_config['output_file'] || 'output.pdf'
            unless File.exist?(output_pdf)
              Common.log_warn("[Step 7] 出力PDFが見つかりません: #{output_pdf}")
              return
            end

            toc_pages = (Build::Utilities.page_count('_toc.pdf') || '0').to_i
            if toc_pages <= 0
              Common.log_warn('[Step 7] toc のページ数が 0 です。分割をスキップします。')
              return
            end

            # 新仕様: _sections.pdf（本文+付録+後書き）
            Build::Utilities.split_pdf_into_toc_and_sections(output_pdf, toc_pages, '_toc.pdf', '_sections.pdf')
          end

          # Step 8: _preface_toc.pdf 構成 + ローマ小付与
          # 新仕様: 00-preface を使用
          def build_frontmatter_pdf!(keep = nil)
            Common.log_action('[Step 8] _preface_toc.pdf を構成し、ローマ小 i〜 を付与します…')
            include_preface = keep && Array(keep).map(&:to_s).any? { |s| File.basename(s) == '00-preface.md' }
            include_toc     = File.exist?('_toc.pdf')

            if include_preface && File.exist?(File.join(Common::CONTENTS_DIR, '00-preface.md'))
              cache_on = Common.cache_enabled?
              cache_dir = cache_on ? Common.ensure_cache_dir! : nil
              preface_cache = cache_on && cache_dir ? File.join(cache_dir, '00-preface.pdf') : nil
              Build::SectionBuilder.ensure_chapter_html_up_to_date!('00-preface', extra_sources: File.join('config', 'book.yml'))

              preface_sources = [
                File.join(Common::CONTENTS_DIR, '00-preface.md'),
                File.join('config', 'book.yml')
              ]
              preface_outdated = false
              if File.exist?('00-preface.pdf')
                pdf_mtime = File.mtime('00-preface.pdf')
                preface_outdated = preface_sources.any? { |s| File.exist?(s) && File.mtime(s) > pdf_mtime }
              end

              needs_preface = !File.exist?('00-preface.pdf') || preface_outdated
              needs_preface &&= !Build::Utilities.cache_restore_file(cache_on, preface_cache, '00-preface.pdf', 'Step 8') unless preface_outdated

              if needs_preface
                %w[pre_process convert post_process entries].each do |t|
                  Vivlio::Starter::ThorCLI.start([t, '00-preface'])
                end
                Vivlio::Starter::ThorCLI.start(['pdf', '00-preface.pdf'])
                Common.log_success('[Step 8] 00-preface.pdf を生成しました') if File.exist?('00-preface.pdf')
                Build::Utilities.cache_store_file(cache_on, '00-preface.pdf', preface_cache, 'Step 8')
              else
                Common.log_action('[Step 8] 前書きPDFは最新のため再利用します: 00-preface.pdf')
              end
            end

            files_to_merge = []
            files_to_merge << '00-preface.pdf' if include_preface
            files_to_merge << '_toc.pdf'     if include_toc
            existing_files = files_to_merge.select { |f| File.exist?(f) }
            missing_files  = files_to_merge - existing_files
            Common.log_warn("[Step 8] 結合対象が見つかりません: #{missing_files.join(', ')}") if missing_files.any?

            if existing_files.length == 1
              src = existing_files.first
              FileUtils.rm_f('_preface_toc.pdf')
              FileUtils.cp(src, '_preface_toc.pdf')
              Common.log_success("[Step 8] _preface_toc.pdf を単一ソースから生成しました: #{src}")
              finalize_frontmatter_pdf
              return
            elsif existing_files.empty?
              Common.log_warn('[Step 8] frontmatter 構成対象PDFがありません。_preface_toc.pdf の生成をスキップします')
              return
            end

            Common.log_info("[Step 8] 結合順: #{existing_files.join(' -> ')}")
            FileUtils.rm_f('_preface_toc.pdf')
            cmd = ['bundle', 'exec', 'hexapdf', 'merge', *existing_files, '_preface_toc.pdf'].join(' ')
            merged = system(cmd)
            if merged && File.exist?('_preface_toc.pdf')
              Common.log_success('[Step 8] _preface_toc.pdf を生成しました')
              finalize_frontmatter_pdf
            else
              Common.log_error('[Step 8] _preface_toc.pdf の生成に失敗しました')
            end
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
            Build::SectionBuilder.ensure_chapter_html_up_to_date!('_titlepage', extra_sources: File.join('config', 'book.yml'))
            Build::SectionBuilder.ensure_chapter_html_up_to_date!('_legalpage', extra_sources: File.join('config', 'book.yml'))
            Build::SectionBuilder.ensure_chapter_html_up_to_date!('_colophon', extra_sources: File.join('config', 'book.yml'))

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
              Vivlio::Starter::ThorCLI.start(['entries', '_titlepage.html', '_legalpage.html'])
              Vivlio::Starter::ThorCLI.start(['pdf', front_pdf])
              if File.exist?(front_pdf)
                Common.log_success("[Step 9] #{front_pdf} を生成しました")
                Build::Utilities.cache_store_file(cache_on, front_pdf, front_cache, 'Step 9')
                front_regenerated = true
              else
                Common.log_warn("[Step 9] #{front_pdf} の生成に失敗しました")
              end
            else
              Common.log_action("[Step 9] フロント/奥付PDFは最新のため再利用します: #{front_pdf}, #{colophon_pdf}")
              Build::Utilities.cache_restore_file(cache_on, front_cache, front_pdf, 'Step 9') unless File.exist?(front_pdf)
              Build::Utilities.cache_restore_file(cache_on, colophon_cache, colophon_pdf, 'Step 9') unless File.exist?(colophon_pdf)
            end

            need_colophon = force || front_regenerated || colophon_missing || newer_than_any.call(colophon_pdf, colophon_srcs)
            if need_colophon
              Vivlio::Starter::ThorCLI.start(['entries', '_colophon.html'])
              Vivlio::Starter::ThorCLI.start(['pdf', colophon_pdf])
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
