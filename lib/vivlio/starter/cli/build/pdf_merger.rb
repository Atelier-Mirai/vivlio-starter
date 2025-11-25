# frozen_string_literal: true

require 'fileutils'

module Vivlio
  module Starter
    module CLI
      module Build
        # ------------------------------------------------
        # PdfMerger: PDFマージモジュール
        # ------------------------------------------------
        # Step 10, 11 の PDF マージ・アウトライン付与を担当する。
        # ------------------------------------------------
        module PdfMerger
          module_function

          # Step 10: すべてのPDFを結合して output.pdf を生成
          def merge_all_pdfs_only!(_keep = nil)
            Common.log_action('[Step 10] フロント(00-01)、前書き、目次、本文、付録、奥付を結合します…')
            Common.log_info('[Step 10] 存在するPDFのみで結合を実行します（02-preface.pdf は任意）')
            files_to_merge = ['00-01-front.pdf', '02-03-front.pdf', '11-98-sections.pdf', '99-colophon.pdf']
            existing_files = files_to_merge.select { |f| File.exist?(f) }
            missing_files  = files_to_merge - existing_files
            Common.log_warn("[Step 10] 結合対象が見つかりません: #{missing_files.join(', ')}") if missing_files.any?
            if existing_files.empty?
              Common.log_error('[Step 10] 結合対象PDFがありません。処理を中止します')
              return false
            end

            unless system('which qpdf >/dev/null 2>&1')
              Common.log_warn('[Step 10] qpdf が見つかりません。`brew install qpdf` でインストールしてください。')
              return false
            end

            base_pdf = existing_files.include?('11-98-sections.pdf') ? '11-98-sections.pdf' : existing_files.first
            FileUtils.rm_f('output.pdf')
            ranges = existing_files.map { |f| %("#{f}" 1-z) }.join(' ')
            cmd = %(qpdf "#{base_pdf}" --pages #{ranges} -- "output.pdf" > /dev/null)
            merged = system(cmd)

            if merged && File.exist?('output.pdf')
              Common.log_success('[Step 10] output.pdf を生成しました')
              true
            else
              Common.log_error('[Step 10] PDF結合に失敗しました')
              false
            end
          end

          # Step 11: アウトライン付与
          def add_outline_to_output_pdf!(keep = nil)
            unless File.exist?('output.pdf')
              Common.log_warn('[Step 11] output.pdf がまだ存在しないため、アウトライン付与をスキップします')
              return false
            end

            keep_numbers = Build::Utilities.chapter_numbers_for_outline(keep)
            chapter_htmls = Dir.glob(File.join('.', '*.html')).select do |path|
              bn = File.basename(path, '.html')
              n = bn[/\A(\d+)-/, 1]&.to_i
              next false unless n
              keep_numbers.nil? || keep_numbers.include?(n)
            end.sort

            if chapter_htmls.any?
              Common.log_action('[Step 11] 本文HTMLの h1〜h3 から PDF ブックマーク（アウトライン）を付与します…')
              total_pages = (Build::Utilities.page_count('output.pdf') || '0').to_i
              start_from  = 1
              Common.log_info("[Outline] page offset: start_page=#{start_from}, total_pages=#{total_pages}")
              OutlineExtractor.add_outline_from_headings!('output.pdf', chapter_htmls, max_level: 3, start_page: start_from)
              true
            else
              Common.log_info('[Step 11] 本文HTMLが見つからないため、アウトライン付与をスキップします')
              false
            end
          end
        end
      end
    end
  end
end
