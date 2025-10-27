# frozen_string_literal: true

require 'thor'
require_relative 'cli/build'
require_relative 'cli/build_helpers'
require_relative 'cli/clean'
require_relative 'cli/common'
require_relative 'cli/convert'
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
require_relative 'cli/prism_lines'
require_relative 'cli/rename'
require_relative 'cli/renumber'
require_relative 'cli/resize'
require_relative 'cli/text_metrics'
require_relative 'cli/toc'
require_relative 'cli/vivliostyle'

module Vivlio
  module Starter
    module CLI
      # ThorCLI が日本語ヘルプを整形表示するためのユーティリティ群
      module HelpRendering
        # Thor の全コマンド定義を取得
        def commands_map
          return all_commands if respond_to?(:all_commands)
          return all_tasks if respond_to?(:all_tasks)

          {}
        end

        # バナー優先で usage を算出
        def usage_for(task, cmd)
          banner_usage(task) || fallback_usage(task, cmd)
        rescue StandardError
          fallback_usage(task, cmd)
        end

        # 長い説明または短い説明を返す
        def description_for(task)
          long_desc = task.respond_to?(:long_description) ? task.long_description : nil
          return long_desc unless long_desc.nil? || long_desc.strip.empty?

          short_desc = task.respond_to?(:description) ? task.description : nil
          short_desc ? "説明: #{short_desc}" : nil
        end

        # オプション一覧を整形して出力
        def print_options_for(task)
          options = task.respond_to?(:options) ? task.options : {}
          return if options.nil? || options.empty?

          puts
          puts 'オプション:'
          options.each { |name, opt| print_option_line(name, opt) }
        rescue StandardError
          # オプション出力が失敗してもヘルプ本体は表示できているため黙って続行
        end

        private

        # Thor の banner があれば利用
        def banner_usage(task)
          return unless respond_to?(:banner)

          banner(task)
        end

        # banner 取得に失敗した際の usage
        def fallback_usage(task, cmd)
          task.respond_to?(:usage) ? task.usage : "#{cmd} [ARGS]"
        end

        # 単一オプション行を出力
        def print_option_line(name, opt)
          switches = option_switches(name, opt)
          puts "  #{switches.join(', ')}  #{option_description(opt)}"
        end

        # オプションのスイッチ文字列配列を生成
        def option_switches(name, opt)
          switches = []
          switches.concat(Array(opt.aliases)) if opt.respond_to?(:aliases) && opt.aliases
          switches << "--#{name.to_s.tr('_', '-')}"
          switches
        end

        # オプション説明を取得
        def option_description(opt)
          if opt.respond_to?(:description)
            opt.description
          elsif opt.respond_to?(:desc)
            opt.desc
          else
            ''
          end
        end
      end

      # ==============================================================================
      # Class: ThorCLI
      # ------------------------------------------------------------------------------
      # Vivlio Starter の Thor ベース CLI ルーター/エントリポイント。
      # - map によりコマンドエイリアス（help, open, prism:lines, merge:appendices 等）を設定
      # - commands_supported で受け付ける公開コマンド一覧を定義
      # - jp_task_help で各コマンドの日本語ヘルプを整形表示
      # - class_option :verbose で共通オプション（-v/--verbose）を提供
      # - 各コマンド群モジュール（BuildCommands など）を include して登録
      # 備考:
      #   - include 順序は機能に影響しません（Thor の定義登録のため）
      # ==============================================================================
      class ThorCLI < ::Thor
        extend HelpRendering

        COMMANDS_SUPPORTED = %w[
          build
          clean
          config
          convert
          create
          create:colophon
          create:legalpage
          create:titlepage
          delete
          doctor
          entries
          glossary:add
          glossary:canonicalize
          glossary:canonicalize:check
          glossary:fix
          glossary:lint
          help
          merge:appendices
          new
          open
          open:pdf
          pdf
          pdf:compress
          post_process
          pre_process
          prism:lines
          rename
          renumber
          resize
          resize:high
          resize:low
          resize:medium
          text_metrics
          toc
          vivliostyle:config
        ].freeze

        map %w[-h --help help] => :help_banner
        map 'open' => 'open_pdf'
        map 'prism:lines' => 'prism_lines'

        class << self
          # 公開コマンド一覧を返す
          # @return [Array<String>]
          def commands_supported
            COMMANDS_SUPPORTED
          end

          # 受付可能なコマンドか判定
          # @param cmd [String]
          # @return [Boolean]
          def handles?(cmd)
            COMMANDS_SUPPORTED.include?(cmd)
          end

          # 個別コマンドの日本語ヘルプを出力
          # @param cmd [String]
          def jp_task_help(cmd)
            task = commands_map[cmd]
            unless task
              puts "使い方: vs #{cmd} [オプション]"
              return
            end

            puts "使い方: vs #{usage_for(task, cmd)}"

            description = description_for(task)
            puts
            puts description if description

            print_options_for(task)
          end
        end

        class_option :verbose, type: :boolean, aliases: '-v', desc: '冗長出力'

        include Vivlio::Starter::CLI::BuildCommands
        include Vivlio::Starter::CLI::CleanCommands
        include Vivlio::Starter::CLI::ConvertCommands
        include Vivlio::Starter::CLI::CreateCommands
        include Vivlio::Starter::CLI::DeleteCommands
        include Vivlio::Starter::CLI::DoctorCommands
        include Vivlio::Starter::CLI::EntriesCommands
        include Vivlio::Starter::CLI::GlossaryCommands
        include Vivlio::Starter::CLI::HelpCommands
        include Vivlio::Starter::CLI::NewCommands
        include Vivlio::Starter::CLI::PdfCommands
        include Vivlio::Starter::CLI::PostProcessCommands
        include Vivlio::Starter::CLI::PreProcessCommands
        include Vivlio::Starter::CLI::PrismLinesCommands
        include Vivlio::Starter::CLI::RenameCommands
        include Vivlio::Starter::CLI::RenumberCommands
        include Vivlio::Starter::CLI::ResizeCommands
        include Vivlio::Starter::CLI::TextMetricsCommands
        include Vivlio::Starter::CLI::TocCommands
        include Vivlio::Starter::CLI::VivliostyleCommands
      end
    end
  end
end

# 互換性維持のため `Vivlio::Starter::ThorCLI` でも参照できるようにする
module Vivlio
  module Starter
    ThorCLI = CLI::ThorCLI unless const_defined?(:ThorCLI)
  end
end
