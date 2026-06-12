# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/pdf_finalizer.rb
# ================================================================
# 責務:
#   生成した PDF の圧縮と最終ファイル名へのリネームを行う。
#
# 処理内容:
#   - Step 12: Ghostscript による PDF 圧縮
#   - Step 13: output.pdf → 書籍名_v1.0.0.pdf へリネーム
#
# ファイル名生成:
#   - config/book.yml の output.filename 設定に基づく
#   - include_version: true の場合はバージョン番号を付与
#
# 依存:
#   - PdfCommands: PDF 圧縮の実装
#   - Common: ファイル名生成
# ================================================================

require 'fileutils'

module VivlioStarter
  module CLI
    module Build
      # PDF 圧縮・リネームモジュール
      module PdfFinalizer
        module_function

        # Step 12: 生成PDFを圧縮
        # pipeline: true — PDF は生成済みのため、gs 不在や圧縮失敗で
        # ビルド全体を止めず、スキップして未圧縮 PDF のまま続行する
        def compress_pdf!
          Common.log_action('[Step 12] 生成PDFを圧縮します…')
          PdfCommands.execute_pdf_compress({ pipeline: true })
        end

        # Step 13: 出力PDFを最終ファイル名にリネーム
        def rename_output_pdfs!
          rename_main_pdf
          rename_compressed_pdf if File.exist?('output_compressed.pdf')
        end

        # output.pdf を動的生成されたファイル名にリネーム
        def rename_main_pdf
          return unless File.exist?('output.pdf')

          target_name = Common.generate_output_filename('pdf')
          return if target_name == 'output.pdf'

          FileUtils.rm_f(target_name)
          FileUtils.mv('output.pdf', target_name)
          Common.log_success("出力PDFをリネームしました: output.pdf → #{target_name}")
        end

        # output_compressed.pdf を動的生成されたファイル名にリネーム
        def rename_compressed_pdf
          target_name = Common.generate_compressed_pdf_filename('pdf')
          return if target_name == 'output_compressed.pdf'

          FileUtils.rm_f(target_name)
          FileUtils.mv('output_compressed.pdf', target_name)
          Common.log_success("圧縮PDFをリネームしました: output_compressed.pdf → #{target_name}")
        end
      end
    end
  end
end
