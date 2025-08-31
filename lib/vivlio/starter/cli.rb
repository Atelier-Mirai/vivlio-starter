# frozen_string_literal: true

require 'thor'
require_relative 'cli/build'
require_relative 'cli/build_helpers'
require_relative 'cli/clean'
require_relative 'cli/common'
require_relative 'cli/convert'
require_relative 'cli/create'
require_relative 'cli/delete'
require_relative 'cli/entries'
require_relative 'cli/glossary'
require_relative 'cli/help'
require_relative 'cli/merge'
require_relative 'cli/new'
require_relative 'cli/pdf'
require_relative 'cli/post_process'
require_relative 'cli/pre_process'
require_relative 'cli/prism_lines'
require_relative 'cli/rename'
require_relative 'cli/renumber'
require_relative 'cli/resize'
require_relative 'cli/toc'
require_relative 'cli/vivliostyle'
require_relative 'cli/doctor'

module Vivlio
  module Starter
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
      map %w[-h --help help] => :help_banner
      # alias: vs open => vs open:pdf（Thor の map はメソッド名にマップする必要がある）
      map 'open' => 'open_pdf'
      # Prism コマンドのコロン表記をメソッド名にマップ
      map 'prism:lines' => 'prism_lines'
      # Merge コマンドのコロン表記をメソッド名にマップ
      map 'merge:appendices' => 'merge_appendices'
      # このクラスで扱うコマンド一覧（router から参照される）
      # ================================================================
      # Method: self.commands_supported（公開コマンド一覧）
      # ------------------------------------------------
      # 概要:
      #   ThorCLI が受け付ける公開コマンド名の配列を返す。
      #   ルーターや補助関数が、この一覧に含まれるかで取り扱い可否を判定する。
      # 戻り値:
      #   Array<String>  公開コマンド名の一覧
      # ================================================================
      def self.commands_supported
        %w[
          build clean config convert 
          create create:colophon create:legalpage create:titlepage
          delete entries glossary:add glossary:canonicalize
          glossary:canonicalize:check glossary:fix glossary:lint help 
          merge:appendices new open open:pdf pdf pdf:compress post_process
          pre_process prism:lines rename renumber resize
          resize:high resize:low resize:medium toc vivliostyle:config
          doctor
        ]
      end

      # ================================================================
      # Method: self.handles?(cmd)（コマンド受付可否の判定）
      # ------------------------------------------------
      # 概要:
      #   与えられたコマンド名が `commands_supported` に含まれるかどうかを返す。
      # 引数:
      #   cmd  String  判定対象のコマンド名
      # 戻り値:
      #   true/false
      # ================================================================
      def self.handles?(cmd)
        commands_supported.include?(cmd)
      end

      # ================================================================
      # Method: self.jp_task_help(cmd)（日本語ヘルプ表示: 個別コマンド）
      # ------------------------------------------------
      # 概要:
      #   Thor のコマンド定義から usage/説明/オプションを取得し、
      #   日本語の整形済みヘルプとして標準出力に表示する。
      # 引数:
      #   cmd  String  対象コマンド名
      # 備考:
      #   - long_description があれば優先して出力
      #   - オプション出力時のエラーは握りつぶし、ヘルプ本体の表示を優先
      # ================================================================
      def self.jp_task_help(cmd)
        # Thor 内部のコマンド定義にアクセス
        commands = respond_to?(:all_commands) ? all_commands : (respond_to?(:all_tasks) ? all_tasks : {})
        task = commands[cmd]
        unless task
          puts "使い方: vs #{cmd} [オプション]"
          return
        end

        # Usage（使い方）
        usage = if respond_to?(:banner)
                  begin
                    banner(task)
                  rescue
                    task.respond_to?(:usage) ? task.usage : "#{cmd} [ARGS]"
                  end
                else
                  task.respond_to?(:usage) ? task.usage : "#{cmd} [ARGS]"
                end
        puts "使い方: vs #{usage}"

        # 説明（long_desc 優先）
        desc_text = if task.respond_to?(:long_description) && task.long_description && !task.long_description.strip.empty?
                      task.long_description
                    else
                      base_desc = task.respond_to?(:description) ? task.description : nil
                      base_desc ? "説明: #{base_desc}" : nil
                    end
        puts
        puts desc_text if desc_text

        # オプション
        begin
          opts = task.respond_to?(:options) ? task.options : {}
          unless opts.nil? || opts.empty?
            puts
            puts 'オプション:'
            opts.each do |name, opt|
              switches = []
              if opt.respond_to?(:aliases) && opt.aliases
                switches.concat(Array(opt.aliases))
              end
              switches << "--#{name.to_s.tr('_','-')}"
              sw = switches.join(', ')
              desc = if opt.respond_to?(:description)
                       opt.description
                     elsif opt.respond_to?(:desc)
                       opt.desc
                     else
                       ''
                     end
              puts "  #{sw}  #{desc}"
            end
          end
        rescue
          # オプション出力に失敗してもヘルプ本体は表示できているので黙って続行
        end
      end
      class_option :verbose, type: :boolean, aliases: '-v', desc: '冗長出力'

      no_commands do; end

      # ================================================================
      # Section: コマンド群の登録（モジュール include）
      # ------------------------------------------------
      # 概要:
      #   CLI の各機能を提供する Thor コマンドモジュールを登録する。
      # 備考:
      #   - include の順序は意味を持たない（Thor へメソッドが定義されればよい）
      #   - map によるエイリアスは本クラスの先頭で定義済み
      # ================================================================
      include Vivlio::Starter::CLI::BuildCommands
      include Vivlio::Starter::CLI::CleanCommands
      include Vivlio::Starter::CLI::ConvertCommands
      include Vivlio::Starter::CLI::CreateCommands
      include Vivlio::Starter::CLI::DeleteCommands
      include Vivlio::Starter::CLI::EntriesCommands
      include Vivlio::Starter::CLI::GlossaryCommands
      include Vivlio::Starter::CLI::HelpCommands
      include Vivlio::Starter::CLI::MergeCommands
      include Vivlio::Starter::CLI::NewCommands
      include Vivlio::Starter::CLI::DoctorCommands
      include Vivlio::Starter::CLI::PdfCommands
      include Vivlio::Starter::CLI::PostProcessCommands
      include Vivlio::Starter::CLI::PreProcessCommands
      include Vivlio::Starter::CLI::PrismLinesCommands
      include Vivlio::Starter::CLI::RenameCommands
      include Vivlio::Starter::CLI::RenumberCommands
      include Vivlio::Starter::CLI::ResizeCommands
      include Vivlio::Starter::CLI::TocCommands
      include Vivlio::Starter::CLI::VivliostyleCommands
    end
  end
end
