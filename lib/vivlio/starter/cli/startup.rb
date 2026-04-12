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
      rescue Exception => e
        warn "❌ #{e.class}: #{e.message}"
        warn e.backtrace.join("\n") if ENV['VS_DEBUG']
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

      module_function :start, :print_usage_for_invalid_input
    end
  end
end
