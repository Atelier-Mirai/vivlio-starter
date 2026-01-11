# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/pdf_command.rb
# ================================================================
# 責務:
#   Samovar CLI の pdf 系コマンドを実装する。
#   Vivliostyle による PDF 生成と Ghostscript による圧縮を行う。
#
# コマンド分類 (help_spec.md 準拠):
#   - pdf: 内部コマンド（ビルドパイプラインから呼び出し）
#   - pdf:compress: Public コマンド（利用者向け）
#
# 依存:
#   - PdfCommands: 実際の PDF 生成・圧縮処理
# ================================================================

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # pdf コマンドの Samovar 実装（内部コマンド）
        # --help 時は pdf:compress の存在を案内する
        class PdfCommand < Samovar::Command
          self.description = 'PDFを生成します（内部コマンド）'

          one :output, '出力ファイル名（省略時は設定に従う）', required: false

          def call
            return print_pdf_internal_help if help_requested?

            PdfCommands.execute_pdf(context_options, output)
          end

          private

          def help_requested?
            help_flag_argument?(output)
          end

          def help_flag_argument?(value)
            %w[-h --help].include?(value.to_s.strip)
          end

          def print_pdf_internal_help
            puts <<~HELP
              vs pdf は内部コマンドです（ビルドパイプラインから自動呼び出し）。

              PDF圧縮機能をお探しの場合:
                vs pdf:compress [INPUT] [OUTPUT]

              詳細は vs pdf:compress --help を参照してください。
              内部コマンドの情報: docs/DEVELOPER_GUIDE.md
            HELP
            0
          end

          def context_options
            { options: parent_options }
          end

          def parent_options
            parent&.options || {}
          end
        end

        # pdf:compress コマンドの Samovar 実装（Public コマンド）
        class PdfCompressCommand < Samovar::Command
          self.description = '生成済みPDFを圧縮します'

          one :input, '入力PDFファイル', required: false
          one :output, '出力PDFファイル', required: false

          def call
            return print_compress_help if help_requested?

            PdfCommands.execute_pdf_compress(context_options, input, output)
          end

          private

          def help_requested?
            help_flag_argument?(input) || help_flag_argument?(output)
          end

          def help_flag_argument?(value)
            %w[-h --help].include?(value.to_s.strip)
          end

          def print_compress_help
            puts <<~HELP
              vs pdf:compress - 生成済みPDFを圧縮します

              Usage: vs pdf:compress [INPUT] [OUTPUT]

              引数:
                INPUT   入力PDFファイル（省略時: output/book.pdf）
                OUTPUT  出力PDFファイル（省略時: output/book_compressed.pdf）

              例:
                vs pdf:compress                           # デフォルトファイルを圧縮
                vs pdf:compress mybook.pdf                # 指定ファイルを圧縮
                vs pdf:compress input.pdf output.pdf      # 入出力を明示指定
            HELP
            0
          end

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
