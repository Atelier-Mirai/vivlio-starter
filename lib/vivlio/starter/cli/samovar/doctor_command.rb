# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/doctor_command.rb
# ================================================================
# 責務:
#   Samovar CLI の doctor コマンドを実装する。
#   必要な外部ツールの診断と自動インストールを行う。
#
# 診断対象:
#   - node, vivliostyle, textlint
#   - qpdf, pdfinfo, gs, imagemagick
#   - Xcode Command Line Tools (macOS)
#
# 主要オプション:
#   - --fix: 不足ツールを自動インストール（macOS + Homebrew）
#   - --yes: 確認プロンプトをスキップ
#
# 依存:
#   - DoctorCommands: 実際の診断・インストール処理
# ================================================================

require_relative '../doctor'

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # doctor コマンドの Samovar 実装
        class DoctorCommand < Samovar::Command
          self.description = '環境診断と不足ツールの自動セットアップを行います'

          options do
            option '--fix', '不足ツールを自動インストール (macOS Homebrew)', default: false, key: :fix
            option '--yes/-y', '確認プロンプトをスキップ', default: false, key: :yes
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          def call
            return print_usage if options[:help]

            DoctorCommands.execute_doctor(context_options)
            0
          rescue SystemExit => e
            raise e
          rescue StandardError => e
            Vivlio::Starter::CLI::Common.log_error("doctor コマンド実行中にエラー: #{e.message}")
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
end
