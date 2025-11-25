# frozen_string_literal: true

require 'fileutils'

module Vivlio
  module Starter
    module CLI
      module Build
        # ------------------------------------------------
        # PdfFinalizer: PDF圧縮・リネームモジュール
        # ------------------------------------------------
        # PDF圧縮と最終ファイル名へのリネームを担当する。
        # ------------------------------------------------
        module PdfFinalizer
          module_function

          # Step 12: 生成PDFを圧縮
          def compress_pdf!
            Common.log_action('[Step 12] 生成PDFを圧縮します…')
            Vivlio::Starter::ThorCLI.start(['pdf_compress'])
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
end
