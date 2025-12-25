# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/new.rb
# ================================================================
# 責務:
#   新規書籍プロジェクトの雛形を作成するコマンドを提供する。
#
# 生成されるプロジェクト構成:
#   - contents/: 章 Markdown ファイル
#   - images/: 画像ファイル
#   - stylesheets/: CSS スタイルシート
#   - config/: 設定ファイル（book.yml, catalog.yml）
#   - templates/: テンプレートファイル
#   - Gemfile, README.md, .gitignore
#
# オプション:
#   - --auto-install: 必要ツールを自動インストール（doctor --fix を実行）
#   - --manual-install: doctor の自動実行をスキップ
#   - --interactive: 対話的に確認しながら実行
#
# 依存:
#   - Scaffolder: プロジェクト雛形の生成
#   - DoctorCommands: 必要ツールの診断・インストール
# ================================================================

require 'yaml'
require 'fileutils'
require_relative '../scaffolder'

module Vivlio
  module Starter
    module CLI
      # 新規プロジェクト作成コマンド
      module NewCommands
        module_function

        # 新規書籍プロジェクトを作成する
        #
        # @param name [String, nil] プロジェクト名（ディレクトリ名として使用）
        # @param options [Hash] オプション設定
        #   - :verbose [Boolean] 詳細ログを出力
        #   - :auto_install [Boolean] 必要ツールを自動インストール
        #   - :manual_install [Boolean] doctor の自動実行をスキップ
        #   - :interactive [Boolean] 対話的に確認
        # @return [void]
        # @raise [SystemExit] プロジェクト名が未指定または既存の場合
        #
        # 副作用:
        #   - 指定名のディレクトリを作成し、プロジェクト雛形を配置
        #   - --auto-install 時は qpdf/pdfinfo 等を Homebrew でインストール
        def execute_new(name, options = {})
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
                opts = { fix: true }
                opts[:yes] = true unless options[:interactive]
                DoctorCommands.execute_doctor({ options: opts })
              else
                proceed = false
                if $stdin.tty?
                  $stdout.print('qpdf / pdfinfo の診断を実行しますか？ [y/N]: ')
                  ans = $stdin.gets
                  proceed = ans && ans.strip.downcase == 'y'
                end
                if proceed
                  DoctorCommands.execute_doctor({})
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
