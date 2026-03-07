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
#   - pdf:read: Public コマンド（PDF→Markdown 変換）
#
# 依存:
#   - PdfCommands: 実際の PDF 生成・圧縮処理
#   - Commands::PdfReadCommand: PDF 読み取り処理
# ================================================================

require_relative '../pdf/pdf_read_command'

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

            PdfCommands.execute_pdf(build_options, output)
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

          def build_options
            { verbose: parent_verbose? }
          end

          def parent_verbose?
            parent&.options&.[](:verbose) || false
          end
        end

        # pdf:compress コマンドの Samovar 実装（Public コマンド）
        class PdfCompressCommand < Samovar::Command
          self.description = '生成済みPDFを圧縮します'

          one :input, '入力PDFファイル', required: false
          one :output, '出力PDFファイル', required: false

          def call
            return print_compress_help if help_requested?

            PdfCommands.execute_pdf_compress(build_options, input, output)
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

          def build_options
            { verbose: parent_verbose? }
          end

          def parent_verbose?
            parent&.options&.[](:verbose) || false
          end
        end

        # pdf:read コマンドの Samovar 実装（Public コマンド）
        class PdfReadCommand < Samovar::Command
          self.description = 'PDF を Markdown へ変換します'

          one :target, '章トークンまたは PDF パス', required: false

          options do
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          def call
            if options[:help] || target.to_s.strip.empty?
              print_usage
              return 0
            end

            pdf_reader.call
            0
          rescue Commands::PdfReadCommand::InvalidInputError => e
            Common.log_error("[pdf:read] #{e.message}")
            1
          rescue Commands::PdfReadCommand::MissingPdfError => e
            Common.log_error("[pdf:read] #{e.message}")
            1
          rescue StandardError => e
            Common.log_error("[pdf:read] 実行中にエラー: #{e.message}")
            Common.log_error(e.backtrace.first(5).join("\n")) if ENV['VERBOSE']
            1
          end

          private

          def pdf_reader
            @pdf_reader ||= Commands::PdfReadCommand.new(target, build_options)
          end

          def build_options
            { verbose: parent_verbose? }
          end

          def parent_verbose?
            parent&.options&.[](:verbose) || false
          end

          def print_usage
            puts <<~USAGE
              vs pdf:read - PDF を Markdown へ変換します

              Usage:
                vs pdf:read FILE

              引数:
                FILE 章トークン (01-foo) または PDF ファイルパス
            USAGE
          end
        end
      end
    end
  end
end
