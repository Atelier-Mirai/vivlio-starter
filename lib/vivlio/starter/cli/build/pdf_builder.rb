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
          def build_overall_pdf_from_dir!(base_dir = '.', keep = nil)
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
            Common.log_info("[Step 8] targets_for_pdf: #{targets_for_pdf.map { |p| File.basename(p) }.join(', ')}")

            compile_overall_pdf!(targets_for_pdf)
          end

          # 全体PDF生成（内部メソッド）
          # entries.jsを生成し、VivliostyleでPDFをビルド
          def compile_overall_pdf!(targets_for_pdf)
            if targets_for_pdf.empty?
              Common.log_warn('[Step 8] 対象HTMLが見つかりません。Step 8 をスキップします。')
              return
            end
            Common.log_info("[Step 8] 対象: #{targets_for_pdf.map { |p| File.basename(p) }.join(', ')}")

            EntriesCommands.execute_entries({}, targets_for_pdf)
            PdfCommands.execute_pdf({})

            pdf_config   = Common::CONFIG['pdf'] || {}
            output_pdf   = pdf_config['output_file'] || 'output.pdf'
            unless File.exist?(output_pdf)
              Common.log_warn("[Step 8] 出力PDFが見つかりません: #{output_pdf}")
              return
            end

            # 全体PDFをそのまま _sections.pdf として使用
            # これにより内部リンク（索引→00-preface等）が維持される
            FileUtils.cp(output_pdf, '_sections.pdf')
            Common.log_success('[Step 8] _sections.pdf を生成しました')
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
