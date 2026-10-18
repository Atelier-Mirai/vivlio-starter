# frozen_string_literal: true

# `vs new` の Samovar エントリ。処理本体は `CLI::NewCommands` に集約する。

require_relative '../new'
require_relative '../doctor'
require_relative 'vs_command'

module VivlioStarter
  module CLI
    module SamovarCommands
      # 新規書籍プロジェクトを作成する Public コマンド
      class NewCommand < VsCommand
        self.description = '新しい書籍プロジェクトを作成します'

        many :names, 'プロジェクト名', default: []

        options do
          option '--yes/-y', '対話をスキップしデフォルト設定で作成する', default: false, key: :yes
          option '--log <level>', 'ログレベル（debug など）', key: :log_level
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
        #
        # 別プロセスの `vs doctor --fix` でなく、このプロセスの中で呼ぶ。`vs` の名前は Vivliostyle
        # CLI の別名とぶつかりうるうえ、揃っているツールを並べない quiet は、vs new のための
        # 指定なのでコマンドのオプションとして外に見せない（改善案.md #87）。
        # @return [Boolean] ツールが揃ったか
        def run_doctor(project_dir)
          Dir.chdir(project_dir) { DoctorCommands.execute_doctor(options: { fix: true, quiet: true }) }
        end

        private

        # --log の解釈は Common に一本化する（options[:log_level] を直接読まない）
        def debug? = Common.current_log_level >= Common::LEVELS['debug']

        def log_debug(msg)
          puts "[debug] #{msg}" if debug?
        end
      end
    end
  end
end
