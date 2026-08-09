# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/samovar/help_command.rb
# ================================================================
# 責務:
#   Samovar CLI の help コマンドを実装する。
#   Public Commands のみをカテゴリ別に表示する。
#
# 一覧が持つのは「分類と並び順」だけ:
#   コマンドの実在は RootCommand.public_commands が、説明文は各コマンドクラスの
#   self.description が正典。ここで説明文を持つと二重管理になり、実際にずれた
#   （2026-08-09 時点で 22 件中 14 件が食い違い、index:auto は旧ファイル名を案内）。
#   分類と並び順だけは読み手のための表示上の情報なので、この表に残す。
#   一覧の漏れは help_spec_test の一致検査が検出する。
# ================================================================

require_relative 'vs_command'

module VivlioStarter
  module CLI
    module SamovarCommands
      # help コマンドの Samovar 実装
      class HelpCommand < VsCommand
        self.description = 'Vivlio Starter の主要コマンド一覧を表示します'

        COMMAND_CATEGORIES = {
          'プロジェクト管理' => %w[new upgrade import pdf:read doctor clean],
          '執筆・編集支援' => %w[create delete rename renumber],
          '文章校正・統計' => %w[lint metrics],
          '索引・用語集' => %w[index index:plan index:auto index:apply index:export index:import],
          '画像・カバー' => %w[cover resize],
          'ビルド・出力・プレビュー' => %w[preflight build open pdf:compress pdf:pages pdf:rasterize]
        }.freeze

        # 一覧に載せない Public コマンド。
        # help はこの一覧そのものなので、自分を項目として並べても情報にならない
        # （マニュアルでも `vs --help` の形で案内している。contract/docs_allowlist.yml 参照）。
        UNLISTED_COMMANDS = %w[help].freeze

        options do
          option '-h/--help', 'ヘルプを表示', key: :help
        end

        def call
          print_public_commands_help
          0
        end

        private

        def print_public_commands_help
          puts <<~HEADER
            📚 Vivlio Starter - 技術書執筆のためのCLIツール 🛠️
            使い方: vs <command> [options]

          HEADER

          COMMAND_CATEGORIES.each do |category, names|
            puts "  #{category}:"
            names.each { puts format('    %-16s %s', it, description_for(it)) }
            puts
          end

          puts <<~FOOTER
            オプション:
              -h, --help       ヘルプを表示
              -v, --verbose    冗長出力を有効化
              --version        バージョン情報を表示

            各コマンドの詳細: vs <command> --help
          FOOTER
        end

        # 説明文はコマンドクラスの self.description が正典（`vs <command> --help`
        # の見出しと同じ文言になる）。一覧に無いコマンド名は表の書き間違いなので、
        # 黙って空欄にせず fetch で落とす（help_spec_test が先に検出する）。
        def description_for(name)
          RootCommand.public_commands.fetch(name).description
        end
      end
    end
  end
end
