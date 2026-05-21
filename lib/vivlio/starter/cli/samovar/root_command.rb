# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/root_command.rb
# ================================================================
# 責務:
#   Samovar CLI のルートコマンドを実装する。
#   サブコマンドへのディスパッチとグローバルオプションを処理する。
#
# グローバルオプション:
#   - --help: ヘルプ表示
#   - --version: バージョン表示
#   - --verbose: 詳細ログ出力
#
# コマンド分類 (help_spec.md 準拠):
#   Public Commands (vs --help に表示):
#     - help, new, build, clean, delete, doctor, import
#     - create, rename, renumber, open, cover
#     - resize
#     - index, index:auto, index:apply
#     - lint, metrics
#     - pdf:compress, pdf:pages, pdf:rasterize
#   Internal Commands (vs --help に非表示、DEVELOPER_GUIDE.md 参照):
#     - pre_process, convert, post_process, pdf, toc, entries, vivliostyle
#     - create:titlepage, create:colophon, create:legalpage
# ================================================================

require_relative '../../../starter/version'

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # Samovar CLI のルートコマンド
        class RootCommand < Samovar::Command
          self.description = 'Vivlio Starter CLI (Samovar)'

          options do
            option '-h/--help', 'Vivlio Starter のヘルプを表示', key: :help
            option '--version', 'バージョン情報を表示', key: :version
            option '-v/--verbose', '冗長出力を有効化', default: false, key: :verbose
          end

          class << self
            # 利用者向け Public Commands (vs --help に表示)
            def public_commands
              @public_commands ||= {
                'help' => HelpCommand,
                'new' => NewCommand,
                'build' => BuildCommand,
                'clean' => CleanCommand,
                'delete' => DeleteCommand,
                'doctor' => DoctorCommand,
                'import' => ImportCommand,
                'create' => CreateCommand,
                'rename' => RenameCommand,
                'renumber' => RenumberCommand,
                'open' => OpenCommand,
                'cover' => CoverCommand,
                'resize' => ResizeCommand,
                'index' => IndexCommand,
                'index:auto' => IndexAutoCommand,
                'index:apply' => IndexApplyCommand,
                'pdf:compress' => PdfCompressCommand,
                'pdf:pages' => PdfPagesCommand,
                'pdf:rasterize' => PdfRasterizeCommand,
                'pdf:read' => PdfReadCommand,
                'lint' => LintCommand,
                'metrics' => MetricsCommand,
                'preflight' => PreflightCommand
              }.freeze
            end

            # 内部コマンド (vs --help に非表示、開発者向け)
            # 注: pre_process, convert, post_process, entries, toc, vivliostyle は
            #     build コマンドから内部的に呼び出される純粋な内部処理に移行済み
            def internal_commands
              @internal_commands ||= {
                'pdf' => PdfCommand,
                'create:cover' => CreateCoverCommand,
                'create:titlepage' => CreateTitlepageCommand,
                'create:colophon' => CreateColophonCommand,
                'create:legalpage' => CreateLegalpageCommand
              }.freeze
            end

            # 全コマンドマップ (ルーティング用)
            def command_map
              @command_map ||= public_commands.merge(internal_commands).freeze
            end
          end

          nested :command, command_map, default: 'help'

          def call
            mark_cli_context

            return print_version if options[:version]

            set_verbose_flag if options[:verbose]

            return help_command.call if options[:help]

            target = command || help_command
            ensure_project_context!(target)
            target.call || 0
          rescue SystemExit => e
            e.status
          end

          private

          def help_command
            @help_command ||= HelpCommand.new([], parent: self, name: 'help')
          end

          def mark_cli_context
            ENV['VS_CLI'] ||= '1'
          end

          def set_verbose_flag
            ENV['VERBOSE'] = '1'
          end

          def print_version
            puts "vivlio-starter #{Vivlio::Starter::VERSION}"
            0
          end

          # プロジェクト外でも実行可能なコマンド
          PROJECTLESS_COMMANDS = [NewCommand, DoctorCommand, HelpCommand].freeze

          def ensure_project_context!(target)
            return if PROJECTLESS_COMMANDS.any? { |klass| target.is_a?(klass) }

            Common.ensure_configured!
          end
        end
      end
    end
  end
end
