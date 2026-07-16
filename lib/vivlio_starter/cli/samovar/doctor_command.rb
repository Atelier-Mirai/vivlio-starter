# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/samovar/doctor_command.rb
# ================================================================
# 責務:
#   Samovar CLI の doctor コマンドを実装する。
#   必要な外部ツールの診断と自動インストールを行う。
#   導入済みツールの一括更新は `vs upgrade` が担う（本体 gem・雛形の追従と
#   あわせて実行される。docs/archives/upgrade-unification-spec.md）。
#
# 診断対象:
#   - node, vivliostyle, textlint
#   - qpdf, pdfinfo, gs, imagemagick
#   - Xcode Command Line Tools (macOS)
#
# 主要オプション:
#   - --fix: 不足ツールを自動インストール（macOS + Homebrew、一部確認あり）
#   - --yes: 確認プロンプトをスキップ（--fix 指定時のみ有効）
#
# 依存:
#   - DoctorCommands: 実際の診断・インストール処理
# ================================================================

require_relative '../doctor'

module VivlioStarter
  module CLI
    module SamovarCommands
      # doctor コマンドの Samovar 実装
      class DoctorCommand < Samovar::Command
        self.description = '環境診断と不足ツールの自動セットアップを行います'

        options do
          option '--fix', '不足ツールを自動インストール (一部確認あり)', default: false, key: :fix
          option '--yes/-y', '確認プロンプトをスキップ (--fix 指定時のみ有効)', default: false, key: :yes
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        def call
          return print_usage if options[:help]

          # 診断の戻り値（Boolean）は従来どおり終了コードへ反映しない
          DoctorCommands.execute_doctor(context_options)
          0
        rescue SystemExit => e
          raise e
        rescue StandardError => e
          VivlioStarter::CLI::Common.log_error("doctor コマンド実行中にエラー: #{e.message}")
          1
        end

        private

        def context_options
          {
            options: {
              fix: options[:fix],
              yes: options[:yes],
              verbose: verbose_from_parent?
            }
          }
        end

        def verbose_from_parent?
          return false unless parent.respond_to?(:options)

          !!parent.options[:verbose]
        end
      end
    end
  end
end
