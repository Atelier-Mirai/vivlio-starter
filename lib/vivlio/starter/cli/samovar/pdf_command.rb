# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/pdf_command.rb
# ================================================================
# 責務:
#   Samovar CLI の pdf 系コマンドを実装する。
#   Vivliostyle による PDF 生成と Ghostscript による圧縮を行う。
#
# 提供コマンド:
#   - pdf: HTML から PDF を生成
#   - pdf:compress: 生成済み PDF を圧縮
#
# 依存:
#   - PdfCommands: 実際の PDF 生成・圧縮処理
# ================================================================

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # pdf コマンドの Samovar 実装
        class PdfCommand < Samovar::Command
          self.description = 'PDFを生成します'

          one :output, '出力ファイル名（省略時は設定に従う）', required: false

          def call
            PdfCommands.execute_pdf(context_options, output)
          end

          private

          def context_options
            { options: parent_options }
          end

          def parent_options
            parent&.options || {}
          end
        end

        class PdfCompressCommand < Samovar::Command
          self.description = '生成済みPDFを圧縮します'

          one :input, '入力PDFファイル', required: false
          one :output, '出力PDFファイル', required: false

          def call
            PdfCommands.execute_pdf_compress(context_options, input, output)
          end

          private

          def context_options
            { options: parent_options }
          end

          def parent_options
            parent&.options || {}
          end
        end
      end
    end
  end
end
