# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/samovar/import_command.rb
# ================================================================
# 責務:
#   Samovar CLI の import コマンドを実装する。
#   Re:VIEW Starter プロジェクトから vivlio-starter への移行を行う。
#
# 処理内容:
#   - 既存ディレクトリの削除（確認後）
#   - .re → .md 変換
#   - 画像の WebP 変換
#   - source/ → codes/ コピー
#   - catalog.yml / config.yml の変換
#
# 依存:
#   - ImportCommands: 移行処理の実装
# ================================================================

require_relative '../import'

module VivlioStarter
  module CLI
    module SamovarCommands
      # import コマンドの Samovar 実装
      class ImportCommand < Samovar::Command
        self.description = 'Re:VIEW Starter プロジェクトをインポートします'

        many :arguments, 'Re:VIEW Starter プロジェクトのディレクトリ', default: []

        options do
          option '--force', '確認プロンプトをスキップして実行', default: false
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        def call
          return print_usage if options[:help]

          starter_dir = arguments.first
          return print_usage if starter_dir.to_s.strip.empty?

          ensure_starter_dir!(starter_dir)

          ImportCommands.execute_import(starter_dir, force: options[:force])
        rescue ArgumentError => e
          common.log_error(e.message)
          1
        rescue StandardError => e
          common.log_error("Error: #{e.message}")
          common.log_error(e.backtrace.join("\n")) if ENV['VS_DEBUG']
          1
        end

        private

        def common
          VivlioStarter::CLI::Common
        end

        def ensure_starter_dir!(starter_dir)
          return unless starter_dir.to_s.strip.empty?

          raise ArgumentError, 'Error: Starter ディレクトリを指定してください。例: vs import ../review_starter_project'
        end
      end
    end
  end
end
