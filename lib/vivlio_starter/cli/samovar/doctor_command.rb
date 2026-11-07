# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/samovar/doctor_command.rb
# ================================================================
# 責務:
#   Samovar CLI の doctor コマンドを実装する。
#   必要な外部ツールの診断と自動インストールを行う。
#   導入済みツールの一括更新は `vs upgrade` が担う（本体 gem・雛形の追従と
#   あわせて実行される。upgrade-unification-spec.md）。
#
# 診断対象:
#   - node, vivliostyle, textlint
#   - qpdf, pdfinfo, gs, imagemagick
#   - Xcode Command Line Tools (macOS)
#
# 主要オプション:
#   - --fix: 診断で見つかった問題を修正する（不足ツールのインストール・設定ファイルの復元。macOS + Homebrew、一部確認あり）
#            非 macOS では自動導入せず、手動で入れるパッケージを種別ごとに案内する
#            （release-1.0-considerations.md A-2）
#   - --yes: 確認プロンプトをスキップ（--fix 指定時のみ有効）。導入スクリプト（bin/install.zsh）が
#            対話せずに --fix を実行するためのもので、ヘルプとマニュアルには載せない
#
# 依存:
#   - DoctorCommands: 実際の診断・インストール処理
# ================================================================

require_relative '../doctor'
require_relative 'vs_command'

module VivlioStarter
  module CLI
    module SamovarCommands
      # doctor コマンドの Samovar 実装
      class DoctorCommand < VsCommand
        self.description = '環境診断と不足ツールの自動セットアップを行います'

        options do
          option '--fix', '診断で見つかった問題を修正 (ツールのインストール・設定ファイルの復元)', default: false, key: :fix
          internal_option '--yes/-y', '確認プロンプトをスキップ (--fix 指定時のみ有効)', default: false, key: :yes
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        def call
          return print_usage if options[:help]

          # 診断の戻り値（Boolean）は従来どおり終了コードへ反映しない
          DoctorCommands.execute_doctor(context_options)
          0
        rescue StandardError => e
          VivlioStarter::CLI::Common.log_error("doctor コマンド実行中にエラー: #{e.message}")
          1
        end

        private

        def context_options
          {
            options: {
              fix: options[:fix],
              yes: options[:yes]
            }
          }
        end
      end
    end
  end
end
