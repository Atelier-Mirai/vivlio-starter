# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/samovar/root_command.rb
# ================================================================
# 責務:
#   Samovar CLI のルートコマンドを実装する。
#   サブコマンドへのディスパッチとグローバルオプションを処理する。
#
# グローバルオプション:
#   - --help: ヘルプ表示
#   - --version: バージョン表示
#
# コマンド分類 (help_spec.md 準拠):
#   Public Commands   … 利用者が直接実行する。`vs --help` に表示する
#   Internal Commands … ビルドパイプラインが内部的に呼ぶ。`vs --help` に出さない
#
#   一覧はこのファイルの public_commands / internal_commands が正典。コメントや
#   help 側で列挙し直すと必ずずれるため、ここでは列挙しない（実際に index 系 3 つが
#   help から漏れた）。表示上の分類と並び順だけを help_command.rb が持ち、
#   両者の一致は help_spec_test が検査する。
# ================================================================

require_relative '../../version'

module VivlioStarter
  module CLI
    module SamovarCommands
      # Samovar CLI のルートコマンド
      class RootCommand < Samovar::Command
        self.description = 'Vivlio Starter CLI (Samovar)'

        options do
          option '-h/--help', 'Vivlio Starter のヘルプを表示', key: :help
          option '--version', 'バージョン情報を表示', key: :version
        end

        class << self
          # 利用者向け Public Commands (vs --help に表示)
          def public_commands
            @public_commands ||= {
              'help' => HelpCommand,
              'new' => NewCommand,
              'upgrade' => UpgradeCommand,
              'build' => BuildCommand,
              'clean' => CleanCommand,
              'delete' => DeleteCommand,
              'doctor' => DoctorCommand,
              'config' => ConfigCommand,
              'config:book' => ConfigBookCommand,
              'config:catalog' => ConfigCatalogCommand,
              'config:talk' => ConfigTalkCommand,
              'import' => ImportCommand,
              'create' => CreateCommand,
              'rename' => RenameCommand,
              'renumber' => RenumberCommand,
              'open' => OpenCommand,
              'cover' => CoverCommand,
              'theme' => ThemeCommand,
              'theme:add' => ThemeAddCommand,
              'theme:check' => ThemeCheckCommand,
              'theme:new' => ThemeNewCommand,
              'index' => IndexCommand,
              'index:plan' => IndexPlanCommand,
              'index:auto' => IndexAutoCommand,
              'index:apply' => IndexApplyCommand,
              'index:export' => IndexExportCommand,
              'index:import' => IndexImportCommand,
              'pdf:compress' => PdfCompressCommand,
              'pdf:pages' => PdfPagesCommand,
              'pdf:read' => PdfReadCommand,
              'lint' => LintCommand,
              'metrics' => MetricsCommand,
              'preflight' => PreflightCommand
            }.freeze
          end

          # 内部コマンド (vs --help に非表示、開発者向け)
          # 注: pre_process, convert, post_process, entries, toc, pdf, vivliostyle は
          #     build コマンドから内部的に呼び出される純粋な内部処理に移行済み
          def internal_commands
            @internal_commands ||= {
              'create:titlepage' => CreateTitlepageCommand,
              'create:colophon' => CreateColophonCommand,
              'create:legalpage' => CreateLegalpageCommand,
              # ビルドが出力形式ごとに画像を用意するので、著者が素材を変換する必要はない。
              # 手元の画像を一括で WebP にしたいときのために残す（改善案.md #45）
              'resize' => ResizeCommand
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

        def print_version
          puts "vivlio-starter #{VivlioStarter::VERSION}"
          0
        end

        # プロジェクト外でも実行可能なコマンド
        PROJECTLESS_COMMANDS = [
          NewCommand, DoctorCommand, HelpCommand,
          ConfigCommand, ConfigBookCommand, ConfigCatalogCommand, ConfigTalkCommand
        ].freeze

        def ensure_project_context!(target)
          return if PROJECTLESS_COMMANDS.any? { |klass| target.is_a?(klass) }
          # コマンド自身が引数からプロジェクト不要と判断する場合（build の .md 直接指定）
          return if target.respond_to?(:projectless?) && target.projectless?

          # vs upgrade は廃止キーを計画に載せて直すので、「vs upgrade で消せます」と案内しない
          return Common.ensure_configured!(retired_notice: false) if target.is_a?(UpgradeCommand)

          stop_unmigrated_book!
          stop_unknown_page_preset!
          Common.ensure_configured!
        end

        # page_presets.yml に無い判型を選んだ本は、本文が既定の B5 で組まれ、判型の違う本ができる。
        # 本を読むコマンドは最初に止める。vs upgrade（page_presets.yml を新しくする）・vs doctor は上で抜けるので止めない
        def stop_unknown_page_preset!
          message, detail = Common.unknown_page_preset_notice
          return unless message

          Common.log_error(message, detail:)
          exit 1
        end

        # 1.x の配置のままの本は、2.0 の vs では CSS が読まれず、エラーも出ずに崩れた本ができる
        # （v2-migration-plan.md §5.7）。本を読むコマンドは最初に止めて、二つの道を示す。
        # vs upgrade・vs doctor・vs help は上で抜けるので止めない。設定の読み込みより先に止めるのは、
        # 廃止キーなどの 🟡（どれも vs upgrade が直す）を 🔴 の前に並べないため
        def stop_unmigrated_book!
          return unless V1Migration.legacy?

          message, detail = V1Migration.unmigrated_notice
          Common.log_error(message, detail:)
          exit 1
        end
      end
    end
  end
end
