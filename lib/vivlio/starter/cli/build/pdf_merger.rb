# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/build/pdf_merger.rb
# ================================================================
# 責務:
#   複数の中間 PDF を結合して最終的な output.pdf を生成する。
#
# マージ対象（順序）:
#   1. _titlepage_legalpage.pdf: 表紙・法的ページ
#   2. _sections.pdf: 前書き・目次・本文・付録・後書き・索引（全体PDF）
#   3. _colophon.pdf: 奥付
#
# 設計方針:
#   - _sections.pdf は全体を1つのPDFとして生成（分割なし）
#   - これにより索引から前書きへのリンクなど内部リンクが維持される
#
# アウトライン:
#   - qpdf --add-outline で目次リンクを付与
#   - pdfinfo でページ数を取得して各章の開始位置を計算
#
# 依存:
#   - qpdf: PDF 結合・アウトライン付与
#   - pdfinfo: ページ数取得
# ================================================================

require 'fileutils'

module Vivlio
  module Starter
    module CLI
      module Build
        # PDF 結合・アウトライン付与モジュール
        module PdfMerger
          module_function

          # Step 10: すべてのPDFを結合して output.pdf を生成
          def merge_all_pdfs!(_keep = nil)
            Common.log_action('[Step 10] 表紙、本文、奥付を結合します…')
            # 結合対象: 表紙・扉裏 + 全体PDF + 奥付
            files_to_merge = %w[_titlepage_legalpage.pdf _sections.pdf _colophon.pdf]
            existing_files = files_to_merge.select { |f| File.exist?(f) }
            missing_files  = files_to_merge - existing_files
            Common.log_info("[Step 10] 結合対象: #{existing_files.join(', ')}")
            Common.log_warn("[Step 10] 見つからないPDF: #{missing_files.join(', ')}") if missing_files.any?

            if existing_files.empty?
              Common.log_error('[Step 10] 結合対象PDFがありません。処理を中止します')
              return false
            end

            unless system('which qpdf >/dev/null 2>&1')
              Common.log_warn('[Step 10] qpdf が見つかりません。`brew install qpdf` でインストールしてください。')
              return false
            end

            base_pdf = existing_files.include?('_sections.pdf') ? '_sections.pdf' : existing_files.first
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
              allows_numeric = n && (keep_numbers.nil? || keep_numbers.include?(n))
              special_includes = %w[_toc _indexpage].include?(bn)
              allows_numeric || special_includes
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
