# frozen_string_literal: true

# `CLI.start` と無効入力時のヘルプ表示を単一定義するエントリ層。
# `bin/vs` / `bin/vivlio-starter` および `require 'vivlio/starter'` から同じ経路で参照される。

require 'vivlio/starter/version'
require_relative 'loader'

module Vivlio
  module Starter
    module CLI
      module_function

      def start(argv)
        args = Array(argv).dup

        command = Vivlio::Starter::CLI::SamovarCommands::RootCommand.parse(args)
        result = command.call
        result.is_a?(Integer) ? result : 0
      rescue Samovar::InvalidInputError => e
        print_usage_for_invalid_input(e)
        0
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
        warn "\n⚠️  処理が中断されました（Ctrl+C）"
        130
      end

      # SIGTERM 等のシグナル受信時のハンドラ。
      # ensure による後片付けが走った後、128 + signo で終了する。
      def handle_signal(error)
        warn "\n⚠️  処理が中断されました（#{error.message}）"
        128 + (Signal.list[error.signm.sub(/\ASIG/, '')] || 15)
      end

      # 想定外の Exception 受信時のハンドラ。
      # デバッグ用にはスタックトレースを出すが、通常はメッセージのみ表示。
      def handle_unexpected_error(error)
        warn "❌ #{error.class}: #{error.message}"
        warn error.backtrace.join("\n") if ENV['VS_DEBUG']
        1
      end

      def print_usage_for_invalid_input(error)
        command = error.command

        warn error.message

        Vivlio::Starter::CLI::Common.log_warn('代わりに --help を表示します。') if defined?(Vivlio::Starter::CLI::Common)

        if command.respond_to?(:print_usage)
          command.print_usage
        else
          Vivlio::Starter::CLI::SamovarCommands::RootCommand.new(['--help']).print_usage
        end
      rescue StandardError => e
        warn "❌ #{e.class}: #{e.message}"
        warn e.backtrace.join("\n") if ENV['VS_DEBUG']
      end

      module_function :start, :print_usage_for_invalid_input,
                      :handle_interrupt, :handle_signal, :handle_unexpected_error
    end
  end
end
