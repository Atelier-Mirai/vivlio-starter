# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require_relative '../scaffolder'

module Vivlio
  module Starter
    module CLI
      # ==============================================================================
      # Module: NewCommands
      # ------------------------------------------------------------------------------
      # 新規書籍プロジェクトの雛形を作成するコマンド群。
      # ディレクトリ構成の作成、テンプレートのコピー、初期 Markdown 生成、
      # README/Gemfile/.gitignore の配置を行う。
      # ==============================================================================
      module NewCommands
        module_function

        NEW_DESC = {
          short: '新しい書籍プロジェクトを作成します',
          long: <<~DESC
            新しい書籍プロジェクトを作成します。

            引数:
              NAME    プロジェクト名（必須）

            作成内容:
            - プロジェクトディレクトリの作成
            - 設定ファイル(config/book.yml)のコピー
            - コンテンツファイルのテンプレートコピー
            - スタイルシート・画像・コードのコピー
            - タイトルページ・リーガルページ・奥付の自動生成
            - README・Gemfile・.gitignoreの作成

            使用例:
              vs new mybook
          DESC
        }.freeze

        def included(base)
          base.class_eval do
            desc 'new NAME', NEW_DESC[:short]
            long_desc NEW_DESC[:long]

            # ================================================================
            # Command: new（新規プロジェクト作成）
            # ------------------------------------------------
            # 概要:
            #   NAME で指定したディレクトリ配下に、Vivlio Starter の標準構成を生成。
            #   設定・テンプレート・初期コンテンツ・スタイル・画像・コードを展開し、
            #   タイトル/リーガル/奥付ページの Markdown を自動生成する。
            #
            # 引数:
            #   name    プロジェクト名（必須）
            # ================================================================
            method_option :auto_install, type: :boolean, default: true, desc: '必要ツールを自動インストール (macOS Homebrew)'
            method_option :interactive, type: :boolean, default: false, desc: '対話的に確認しながら実行'
            method_option :manual_install, type: :boolean, default: false, desc: 'doctor の自動実行を無効化'
            def new(name)
              ENV['VERBOSE'] = '1' if options[:verbose]

              name = name&.strip
              if name.nil? || name.empty?
                Common.log_error('Error: プロジェクト名を指定してください。例: vs new mybook')
                exit(1)
              end

              dest = File.expand_path(name)
              if File.exist?(dest)
                Common.log_error("Error: '#{name}' は既に存在します。別名を指定してください。")
                exit(1)
              end

              gem_root = File.expand_path('..', __dir__)

              Common.log_action("[vivlio-starter] Creating new project: #{name}")

              result = Vivlio::Starter::Scaffolder.scaffold_project(
                name: name,
                dest: dest,
                gem_root: gem_root,
                copy_styles_mode: :all,
                include_ci_workflow: true,
                include_viv_config_update: true
              )

              Common.log_success("[vivlio-starter] Done. cd #{name} で移動し、執筆を開始できます。")
              Common.log_info('例: vivliostyle preview などのコマンドを実行')

              begin
                Dir.chdir(result.dest) do
                  if options[:manual_install]
                    Common.echo_always('doctor の自動実行をスキップします (--manual-install)')
                  elsif options[:auto_install]
                    Common.echo_always('必要ツールの自動インストールを有効にして doctor を実行します (--auto-install)')
                    args = ['doctor', '--fix']
                    args << '--yes' unless options[:interactive]
                    Vivlio::Starter::ThorCLI.start(args)
                  else
                    proceed = false
                    if $stdin.tty?
                      $stdout.print('qpdf / pdfinfo の診断を実行しますか？ [y/N]: ')
                      ans = $stdin.gets
                      proceed = ans && ans.strip.downcase == 'y'
                    end
                    if proceed
                      Vivlio::Starter::ThorCLI.start(['doctor'])
                    else
                      Common.echo_always('後で実行する場合: vs doctor もしくは vs doctor --fix (macOS)')
                    end
                  end
                end
              rescue StandardError => e
                Common.log_warn("doctor 実行フローでエラーが発生しました: #{e}")
              end
            end
          end
        end
      end
    end
  end
end
