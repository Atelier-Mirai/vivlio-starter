# frozen_string_literal: true

# `vs new` の Samovar エントリ。処理本体は `CLI::NewCommands` に集約する。

require_relative '../new'

module VivlioStarter
  module CLI
    module SamovarCommands
      # 新規書籍プロジェクトを作成する Public コマンド
      class NewCommand < Samovar::Command
        self.description = '新しい書籍プロジェクトを作成します'

        many :names, 'プロジェクト名', default: []

        options do
          option '--yes/-y', '対話をスキップしデフォルト設定で作成する', default: false, key: :yes
          option '--force', '既存ディレクトリへの追加展開を許可する', default: false, key: :force
          option '--log <level>', 'ログレベル（debug など）', key: :log
          option '-h/--help', 'このコマンドの使い方を表示', key: :help
        end

        def call
          return print_usage if options[:help]

          NewCommands.run_from_command(self)
        rescue SystemExit => e
          raise e
        rescue StandardError => e
          Common.log_error("new コマンド実行中にエラー: #{e.message}")
          log_debug(e.full_message) if debug?
          1
        end

        # doctor 実行を委譲するメソッド。テスト時はこのメソッドをスタブ化する。
        def system(cmd) = Kernel.system(cmd)

        private

        def debug? = options[:log] == 'debug'

        def log_debug(msg)
          puts "[debug] #{msg}" if debug?
        end
      end
    end
  end
end
