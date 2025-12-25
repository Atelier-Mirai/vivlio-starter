# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/rename_command.rb
# ================================================================
# 責務:
#   Samovar CLI の rename/renumber コマンドを実装する。
#   章ファイルの名前変更・番号変更を行う。
#
# 実行モード:
#   - 単一章リネーム: vs rename 11-old 12-new
#   - 番号のみ変更: vs rename 11 12
#   - 全章連番付け直し: vs rename（引数なし）
#
# 主要オプション:
#   - --dry-run: 変更予定のみ表示
#   - --force: 確認なしで実行
#   - --chapter-step: 連番の刻み幅（デフォルト: 1）
#
# 依存:
#   - RenameCommandExecutor: 実際のリネーム処理
# ================================================================

require_relative '../rename'

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # rename コマンドの Samovar 実装
        class RenameCommand < Samovar::Command
          self.description = '章のスラッグ/番号を変更します'

          many :arguments, 'OLD と NEW を指定。省略すると一括連番モード', default: []

          options do
            option '-n/--dry-run', '変更予定のみ表示（実行しない）', default: false, key: :dry_run
            option '--force/-f/-y', '確認なしで変更を実行', default: false, key: :force
            option '--chapter-step/-S <step>', '章番号の刻み幅を指定（既定: 1）', type: Integer, key: :chapter_step
            option '--step <step>', '[互換] 章番号の刻み幅（--chapter-step と同義）', type: Integer, key: :step
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          def call
            return print_usage if options[:help]

            ensure_argument_count!
            executor.call(*arguments.first(2))
            0
          rescue SystemExit => e
            raise e
          rescue StandardError => e
            Vivlio::Starter::CLI::Common.log_error("rename コマンド実行中にエラー: #{e.message}")
            1
          end

          private

          def ensure_argument_count!
            return if arguments.length <= 2

            raise Samovar::Error, '指定できる引数は旧名(OLD)と新名(NEW)の最大2つです'
          end

          def executor
            @executor ||= Vivlio::Starter::CLI::RenameCommandExecutor.new(executor_options)
          end

          def executor_options
            {
              dry_run: options[:dry_run],
              force: options[:force],
              chapter_step: options[:chapter_step],
              step: options[:step],
              verbose: verbose_from_parent
            }
          end

          def verbose_from_parent
            return false unless parent.respond_to?(:options)

            !!parent.options[:verbose]
          end
        end

        class RenumberCommand < RenameCommand
          self.description = '章番号を一括で付け直します（rename の別名）'
        end
      end
    end
  end
end
