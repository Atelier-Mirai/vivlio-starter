# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/samovar/open_command.rb
# ================================================================
# 責務:
#   生成されたPDFを開く（macOS専用）
#   vs pdf:open のショートハンド
# ================================================================

require_relative '../guards'

module VivlioStarter
  module CLI
    module SamovarCommands
      # open コマンド - 生成されたPDFを開く
      class OpenCommand < Samovar::Command
        self.description = '生成されたPDFを開く（macOS専用）'

        # options を位置引数より先に宣言する。逆順だと Samovar が `--help` を
        # PDF ファイル名（target）として消費してしまう（契約テスト CL-01 で検出）
        options do
          option '-v/--verbose', '冗長出力', default: false, key: :verbose
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        one :target, 'PDFファイル名（省略時はビルド生成物を自動選択）', required: false

        def call
          apply_verbose

          if options[:help]
            print_usage
            return 0
          end

          # 前提条件の検証（ProjectRoot ○）
          # target は拡張子省略・sources/ 探索などの自動解決があるため
          # PdfArtifactCheck は適用せず、解決失敗はドメイン層のメッセージに委ねる
          guard_failure = Guards.precheck(Guards::RelaxedCheck.new(Guards::ProjectRootCheck.new))
          return guard_failure if guard_failure

          PdfCommands.execute_open_pdf(build_options, target)
          0
        rescue SystemExit => e
          raise e
        rescue StandardError => e
          Common.log_error("open 実行中にエラー: #{e.message}")
          Common.log_error(e.backtrace.first(5).join("\n")) if ENV['VERBOSE']
          1
        end

        private

        def apply_verbose
          ENV['VERBOSE'] = '1' if options[:verbose]
        end

        def build_options
          { verbose: options[:verbose] }
        end

        def print_usage
          puts <<~USAGE
            vs open - 生成されたPDFを開く（macOS専用）

            Usage: vs open [TARGET] [-v/--verbose] [-h/--help]

            引数:
              TARGET  PDFファイル名（拡張子 .pdf は省略可）
                      省略時はビルド生成物を自動選択
                      プロジェクトルート → sources/ の順で探索

            例:
              vs open                    # ビルド生成物を自動選択
              vs open 01-quickstart      # 01-quickstart.pdf を開く
              vs open 01-quickstart.pdf  # 同上
              vs open quickstart         # sources/quickstart.pdf を開く
          USAGE
        end
      end
    end
  end
end
