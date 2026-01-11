# frozen_string_literal: true

# Samovar ベース CLI への移行に伴い、このファイルは互換レイヤーのみを提供します。
# 既存コードで `require 'vivlio/starter/cli'` が使われていても、
# 実際の CLI 実装は `lib/vivlio/starter/cli/samovar` 側に存在します。

require_relative 'cli/common'
require_relative 'cli/create'
require_relative 'cli/delete'
require_relative 'cli/doctor'
require_relative 'cli/entries'
require_relative 'cli/glossary'
require_relative 'cli/help'
require_relative 'cli/new'
require_relative 'cli/pdf'
require_relative 'cli/post_process'
require_relative 'cli/pre_process'
require_relative 'cli/rename'
require_relative 'cli/renumber'
require_relative 'cli/text_lint'
require_relative 'cli/text_metrics'
require_relative 'cli/index'
require_relative 'cli/import'

require_relative 'cli/samovar'

# Vivlio Starter CLI のエントリポイント（Samovar CLI ランチャー）
module Vivlio
  module Starter
    module CLI
      module_function

      # Samovar コマンド群を読み込むだけ。

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
        token = error.respond_to?(:token) ? error.token : nil

        if defined?(Vivlio::Starter::CLI::Common) && token
          Vivlio::Starter::CLI::Common.log_warn("未知のオプション #{token.inspect} を検出しました。代わりに --help を表示します。")
        elsif token
          warn "Unknown option #{token.inspect}. Showing help."
        end

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
