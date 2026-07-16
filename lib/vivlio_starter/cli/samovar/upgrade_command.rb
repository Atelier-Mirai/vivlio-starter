# frozen_string_literal: true

# `vs upgrade` の Samovar エントリ。処理本体は `CLI::UpgradeCommands` に集約する。

require_relative '../upgrade'
require_relative '../guards'

module VivlioStarter
  module CLI
    module SamovarCommands
      # 既存プロジェクトを新しい gem の雛形へ追従させる Public コマンド
      class UpgradeCommand < Samovar::Command
        self.description = 'プロジェクトを新しい雛形に追従させます（gem 更新後の取り込み）'

        options do
          option '--dry-run', '計画（何が追加/更新/競合か）の表示のみで書き込みしない', default: false, key: :dry_run
          option '--yes/-y', '競合以外（追加＋未カスタムの更新）を確認なしで適用する', default: false, key: :yes
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        def call
          return print_usage if options[:help]

          # プロジェクト直下でのみ実行可能（config/book.yml が目印）
          guard_failure = Guards.precheck(Guards::ProjectRootCheck.new)
          return guard_failure if guard_failure

          UpgradeCommands.run_from_command(self)
        rescue SystemExit => e
          raise e
        rescue StandardError => e
          Common.log_error("upgrade コマンド実行中にエラー: #{e.message}")
          1
        end
      end
    end
  end
end
