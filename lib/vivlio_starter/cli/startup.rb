# frozen_string_literal: true

# `CLI.start` と無効入力時のヘルプ表示を単一定義するエントリ層。
# `bin/vs` / `bin/vivlio-starter` および `require 'vivlio_starter'` から同じ経路で参照される。

require 'vivlio_starter/version'
require_relative 'loader'

module VivlioStarter
  module CLI
    module_function

    def start(argv)
      args = Array(argv).dup

      command = VivlioStarter::CLI::SamovarCommands::RootCommand.parse(args)
      # ログレベルはここで 1 回だけ確定する。解析より前の出力（未知コマンドのエラー等）は
      # 既定レベルで出す——解析に失敗した入力の --log 指定を尊重する必要はない。
      Common.apply_log_level!(command)
      result = command.call
      result.is_a?(Integer) ? result : 0
    rescue Samovar::InvalidInputError => e
      print_usage_for_invalid_input(e)
      # 無効入力（未知のコマンド・オプション）は POSIX 慣習に従い非 0 で終了する。
      # シェルスクリプトや CI からタイプミスを検知できるようにする（契約テスト CL-02）
      1
    rescue SystemExit => e
      e.status
    rescue Interrupt
      handle_interrupt
    rescue SignalException => e
      handle_signal(e)
    rescue Exception => e
      handle_unexpected_error(e)
    end

    # Ctrl+C（SIGINT）受信時のハンドラ。
    # 既存の ensure ブロックでの一時ファイルクリーンアップが走った後、
    # UNIX 規約（128 + SIGINT=2）で終了する。
    def handle_interrupt
      warn "\n🟡 処理が中断されました（Ctrl+C）"
      130
    end

    # SIGTERM 等のシグナル受信時のハンドラ。
    # ensure による後片付けが走った後、128 + signo で終了する。
    def handle_signal(error)
      warn "\n🟡 処理が中断されました（#{error.message}）"
      128 + (Signal.list[error.signm.sub(/\ASIG/, '')] || 15)
    end

    # 想定外の Exception 受信時のハンドラ。
    # デバッグ用にはスタックトレースを出すが、通常はメッセージのみ表示。
    def handle_unexpected_error(error)
      warn "🔴 #{error.class}: #{error.message}"
      warn error.backtrace.join("\n") if ENV['VS_DEBUG']
      1
    end

    def print_usage_for_invalid_input(error)
      command = error.command

      warn error.message

      VivlioStarter::CLI::Common.log_warn('代わりに --help を表示します。') if defined?(VivlioStarter::CLI::Common)

      # `vs hogehoge` のような未知のコマンドは、RootCommand の nested が既定の help を
      # 選ぶため error.command が HelpCommand になる。この場合に help 自身の usage
      # （`help [-h/--help]`）を見せても手がかりにならないので、`vs --help` と同じ
      # 主要コマンド一覧を出す。既知コマンドのオプション誤りは、そのコマンドの
      # 使い方を見せたいので従来どおり print_usage を呼ぶ。
      if command.is_a?(VivlioStarter::CLI::SamovarCommands::HelpCommand)
        command.call
      elsif command.respond_to?(:print_usage)
        command.print_usage
      else
        VivlioStarter::CLI::SamovarCommands::RootCommand.new(['--help']).print_usage
      end
    rescue StandardError => e
      warn "🔴 #{e.class}: #{e.message}"
      warn e.backtrace.join("\n") if ENV['VS_DEBUG']
    end

    module_function :start, :print_usage_for_invalid_input,
                    :handle_interrupt, :handle_signal, :handle_unexpected_error
  end
end
