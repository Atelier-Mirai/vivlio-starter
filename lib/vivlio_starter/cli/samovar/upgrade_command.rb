# frozen_string_literal: true

# `vs upgrade` の Samovar エントリ。処理本体は `CLI::UpgradeCommands` に集約する。
# 本体 gem 更新 → 雛形追従 → 外部ツール更新 の三段を一括実行する（統合の経緯は
# docs/archives/upgrade-unification-spec.md）。プロジェクト外でも実行でき、
# その場合は雛形追従だけがスキップされる。

require_relative '../upgrade'

module VivlioStarter
  module CLI
    module SamovarCommands
      # 執筆環境（本体 gem・プロジェクト雛形・外部ツール）を一括更新する Public コマンド
      class UpgradeCommand < Samovar::Command
        self.description = '本体 gem・プロジェクト雛形・外部ツールをまとめて最新化します'

        options do
          option '--dry-run', '計画（何が追加/更新/競合か）の表示のみで書き込みしない', default: false, key: :dry_run
          option '--yes/-y', '競合以外（追加＋未カスタムの更新）を確認なしで適用する', default: false, key: :yes
          option '--skip-self-update', 'vivlio-starter 本体の gem 更新を行わない', default: false, key: :skip_self_update
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        def call
          return print_usage if options[:help]

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
