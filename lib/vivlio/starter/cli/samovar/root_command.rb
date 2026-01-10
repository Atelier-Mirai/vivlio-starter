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
# サブコマンド:
#   - new, build, clean, delete, doctor
#   - create, create:titlepage, create:colophon, create:legalpage
#   - rename, renumber, pre_process, convert, post_process
#   - toc, pdf, pdf:compress, resize, resize:high/medium/low
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
            def command_map
              @command_map ||= {
                'help' => HelpCommand,
                'new' => NewCommand,
                'build' => BuildCommand,
                'clean' => CleanCommand,
                'delete' => DeleteCommand,
                'doctor' => DoctorCommand,
                'entries' => EntriesCommand,
                'create' => CreateCommand,
                'create:titlepage' => CreateTitlepageCommand,
                'create:colophon' => CreateColophonCommand,
                'create:legalpage' => CreateLegalpageCommand,
                'rename' => RenameCommand,
                'renumber' => RenumberCommand,
                'pre_process' => PreProcessCommand,
                'convert' => ConvertCommand,
                'post_process' => PostProcessCommand,
                'toc' => TocCommand,
                'pdf' => PdfCommand,
                'pdf:compress' => PdfCompressCommand,
                'resize' => ResizeCommand,
                'resize:high' => ResizeHighCommand,
                'resize:medium' => ResizeMediumCommand,
                'resize:low' => ResizeLowCommand,
                'index' => IndexCommand,
                'index:auto' => IndexAutoCommand,
                'index:apply' => IndexApplyCommand,
                'open' => OpenCommand,
                'import' => ImportCommand
              }.freeze
            end
          end

          nested :command, command_map, default: 'help'

          def call
            mark_cli_context

            return print_version if options[:version]

            set_verbose_flag if options[:verbose]

            return help_command.call if options[:help]

            target = command || help_command
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
        end
      end
    end
  end
end
