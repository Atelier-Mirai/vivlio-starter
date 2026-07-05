# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/samovar/pdf_command.rb
# ================================================================
# 責務:
#   Samovar CLI の pdf 系コマンドを実装する。
#   生成済み PDF の圧縮・画像化・変換を行う。
#
# コマンド分類 (help_spec.md 準拠):
#   - pdf:compress: Public コマンド（利用者向け）
#   - pdf:pages: Public コマンド（PDFページ画像化）
#   - pdf:rasterize: Public コマンド（Type3フォント対策）
#   - pdf:read: Public コマンド（PDF→Markdown 変換）
#
# PDF 生成そのもの（PdfCommands.execute_pdf）はビルドパイプラインが
# 直接呼び出す純粋な内部処理であり、Samovar コマンドは持たない
# （旧 `vs pdf` は手動フローの実体消滅に伴い撤去。
#  docs/specs/vivlioverso-manual-flow-removal-spec.md）。
#
# 依存:
#   - PdfCommands: 実際の PDF 圧縮・ページ画像化処理
#   - Commands::PdfReadCommand: PDF 読み取り処理
# ================================================================

require_relative '../pdf/pdf_read_command'
require_relative '../guards'

module VivlioStarter
  module CLI
    module SamovarCommands
      # pdf:compress コマンドの Samovar 実装（Public コマンド）
      class PdfCompressCommand < Samovar::Command
        self.description = '生成済みPDFを圧縮します'

        one :input, '入力PDFファイル', required: false
        one :output, '出力PDFファイル', required: false

        def call
          return print_compress_help if help_requested?

          # 前提条件の検証（ProjectRoot ○ / PdfArtifact ◎: 明示パス指定時のみ）
          guard_failure = Guards.precheck(
            Guards::RelaxedCheck.new(Guards::ProjectRootCheck.new),
            Guards::PdfArtifactCheck.new(input)
          )
          return guard_failure if guard_failure

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

      # pdf:pages コマンドの Samovar 実装（Public コマンド）
      class PdfPagesCommand < Samovar::Command
        self.description = 'PDFをページ単位でJPEG画像に切り出します'

        one :input, '入力PDFファイル（省略時はビルド生成物）', required: false

        options do
          option '--dpi <value>', '解像度（dpi、既定: 350）', type: Integer, default: 350, key: :dpi
          option '--quality <value>', 'JPEG品質 1〜100（既定: 95）', type: Integer, default: 95, key: :quality
          option '--pages <spec>', 'ページ指定（例: 1,3,5-8）', key: :pages
          option '--output <dir>', '出力ディレクトリ（既定: <basename>_images）', key: :output
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        def call
          return print_usage if help_requested?

          # 前提条件の検証（ProjectRoot ○ / PdfArtifact ◎: 明示パス指定時のみ）
          guard_failure = Guards.precheck(
            Guards::RelaxedCheck.new(Guards::ProjectRootCheck.new),
            Guards::PdfArtifactCheck.new(input)
          )
          return guard_failure if guard_failure

          PdfCommands.execute_pdf_pages(build_options, input)
          0
        rescue StandardError => e
          Common.log_error("[pdf:pages] #{e.message}")
          Common.log_error(e.backtrace.first(5).join("\n")) if ENV['VERBOSE']
          1
        end

        private

        def help_requested?
          options[:help] || help_flag_argument?(input)
        end

        def help_flag_argument?(value)
          %w[-h --help].include?(value.to_s.strip)
        end

        def build_options
          {
            dpi: options[:dpi],
            quality: options[:quality],
            pages: options[:pages],
            output: options[:output],
            verbose: parent_verbose?
          }
        end

        def parent_verbose?
          parent&.options&.[](:verbose) || false
        end
      end

      # pdf:rasterize コマンドの Samovar 実装（Public コマンド）
      class PdfRasterizeCommand < Samovar::Command
        self.description = 'PDFをラスタライズして再結合します（Type3フォント対策）'

        one :input, '入力PDFファイル（省略時はビルド生成物）', required: false

        options do
          option '--dpi <value>', '解像度（dpi、既定: 350）', type: Integer, default: 350, key: :dpi
          option '--quality <value>', 'JPEG品質 1〜100（既定: 95）', type: Integer, default: 95, key: :quality
          option '--clean', '中間JPEGを処理後に削除する', default: false, key: :clean
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        def call
          return print_usage if help_requested?

          # 前提条件の検証（ProjectRoot ○ / PdfArtifact ◎: 明示パス指定時のみ）
          guard_failure = Guards.precheck(
            Guards::RelaxedCheck.new(Guards::ProjectRootCheck.new),
            Guards::PdfArtifactCheck.new(input)
          )
          return guard_failure if guard_failure

          PdfCommands.execute_pdf_rasterize(build_options, input)
          0
        rescue StandardError => e
          Common.log_error("[pdf:rasterize] #{e.message}")
          Common.log_error(e.backtrace.first(5).join("\n")) if ENV['VERBOSE']
          1
        end

        private

        def help_requested?
          options[:help] || help_flag_argument?(input)
        end

        def help_flag_argument?(value)
          %w[-h --help].include?(value.to_s.strip)
        end

        def build_options
          {
            dpi: options[:dpi],
            quality: options[:quality],
            clean: options[:clean],
            verbose: parent_verbose?
          }
        end

        def parent_verbose?
          parent&.options&.[](:verbose) || false
        end
      end

      # pdf:read コマンドの Samovar 実装（Public コマンド）
      class PdfReadCommand < Samovar::Command
        self.description = 'PDF を Markdown へ変換します'

        # options を位置引数より先に宣言する。逆順だと Samovar が `--help` を
        # 章トークン（target）として消費してしまう（契約テスト CL-01 で検出）
        options do
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        one :target, '章トークンまたは PDF パス', required: false

        def call
          if options[:help] || target.to_s.strip.empty?
            print_usage
            return 0
          end

          # 前提条件の検証（ProjectRoot ○）
          # target は章トークンの場合があるため PdfArtifactCheck は適用せず、
          # PDF パス解決の失敗はドメイン層（MissingPdfError）に委ねる
          guard_failure = Guards.precheck(Guards::RelaxedCheck.new(Guards::ProjectRootCheck.new))
          return guard_failure if guard_failure

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
