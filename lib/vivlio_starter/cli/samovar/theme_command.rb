# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/samovar/theme_command.rb
# ================================================================
# 責務:
#   Samovar CLI の theme 系コマンド（theme-contract-spec.md §7.2）。
#
#   - vs theme                        : 本のテーマと、選ばれているテーマ、本に無い同梱のテーマの一覧
#   - vs theme:add <名前|パス>         : テーマを本の themes/ へ複製する（book.yml は書き換えない）
#   - vs theme:check [名前]            : テーマの検査
#   - vs theme:new <名前> [--extends]  : 配色のテーマか組版のテーマの雛形を作る
#
# 依存:
#   - ThemeCommands: 処理と表示
# ================================================================

require_relative '../theme_commands'
require_relative 'vs_command'

module VivlioStarter
  module CLI
    module SamovarCommands
      # theme コマンドの Samovar 実装
      class ThemeCommand < VsCommand
        self.description = '本のテーマと、同梱のテーマの一覧を表示します'

        options do
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        def call
          return print_usage if options[:help]

          ThemeCommands.list
        rescue StandardError => e
          Common.log_error("theme コマンド実行中にエラー: #{e.message}")
          1
        end
      end

      # theme:add コマンドの Samovar 実装
      class ThemeAddCommand < VsCommand
        self.description = 'テーマを本の themes/ に入れます'

        options do
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        one :source, '同梱のテーマの名前、テーマのディレクトリか zip のパス', required: false

        def call
          return print_usage if options[:help] || source.nil?

          ThemeCommands.add(source)
        rescue StandardError => e
          Common.log_error("theme:add コマンド実行中にエラー: #{e.message}")
          1
        end
      end

      # theme:check コマンドの Samovar 実装
      class ThemeCheckCommand < VsCommand
        self.description = 'テーマを検査します（Kindle に届かない書き方・契約 HTML に無いクラスなど）'

        options do
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        one :theme_name, 'テーマの名前（省略すると config/book.yml の theme.name）', required: false

        def call
          return print_usage if options[:help]

          ThemeCommands.check(theme_name)
        rescue StandardError => e
          Common.log_error("theme:check コマンド実行中にエラー: #{e.message}")
          1
        end
      end

      # theme:new コマンドの Samovar 実装
      class ThemeNewCommand < VsCommand
        self.description = 'テーマの雛形を themes/ に作ります（--extends で配色のテーマ）'

        options do
          option '--extends <name>', '土台にするテーマ（値だけを差し替える配色のテーマを作る）', key: :extends
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        one :theme_name, '作るテーマの名前', required: false

        def call
          return print_usage if options[:help] || theme_name.nil?

          ThemeCommands.new_theme(theme_name, extends: options[:extends])
        rescue StandardError => e
          Common.log_error("theme:new コマンド実行中にエラー: #{e.message}")
          1
        end
      end
    end
  end
end
