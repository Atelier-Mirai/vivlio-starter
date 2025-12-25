# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/new_command.rb
# ================================================================
# 責務:
#   Samovar CLI の new コマンドを実装する。
#   新規書籍プロジェクトの雛形を作成する。
#
# 生成されるプロジェクト:
#   - contents/: 章 Markdown
#   - images/: 画像
#   - stylesheets/: CSS
#   - config/: 設定ファイル
#   - Gemfile, README.md
#
# 主要オプション:
#   - --auto-install: 必要ツールを自動インストール
#   - --manual-install: doctor の自動実行を無効化
#
# 依存:
#   - Scaffolder: プロジェクト雛形の生成
#   - DoctorCommand: 環境診断
# ================================================================

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # new コマンドの Samovar 実装
        class NewCommand < Samovar::Command
          self.description = '新しい書籍プロジェクトを作成します'

          one :name, 'プロジェクト名（必須）', required: true

          options do
            option '--[no]-auto-install', '必要ツールを自動インストール (macOS Homebrew)', default: true, key: :auto_install
            option '--interactive', '対話的に確認しながら実行', default: false
            option '--manual-install', 'doctor の自動実行を無効化', default: false
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          def call
            return print_usage if options[:help]

            ensure_project_name!

            common.log_action("[vivlio-starter] Creating new project: #{normalized_name}")

            result = Vivlio::Starter::Scaffolder.scaffold_project(
              name: normalized_name,
              dest: destination_path,
              gem_root: gem_root,
              copy_styles_mode: :all,
              include_ci_workflow: true,
              include_viv_config_update: true
            )

            common.log_success("[vivlio-starter] Done. cd #{normalized_name} で移動し、執筆を開始できます。")
            common.log_info('例: vivliostyle preview などのコマンドを実行')

            run_post_setup(result)
            0
          rescue ArgumentError => e
            common.log_error(e.message)
            1
          rescue StandardError => e
            common.log_error("Error: #{e.message}")
            1
          end

          private

          def common
            Vivlio::Starter::CLI::Common
          end

          def normalized_name
            @normalized_name ||= name.to_s.strip
          end

          def ensure_project_name!
            if normalized_name.empty?
              raise ArgumentError, 'Error: プロジェクト名を指定してください。例: vs new mybook'
            end
          end

          def destination_path
            dest = File.expand_path(normalized_name)
            if File.exist?(dest)
              raise ArgumentError, "Error: '#{normalized_name}' は既に存在します。別名を指定してください。"
            end
            dest
          end

          def gem_root
            File.expand_path('..', __dir__)
          end

          def run_post_setup(result)
            Dir.chdir(result.dest) do
              if options[:manual_install]
                common.echo_always('doctor の自動実行をスキップします (--manual-install)')
                return
              end

              if options[:auto_install]
                common.echo_always('必要ツールの自動インストールを有効にして doctor を実行します (--auto-install)')
                args = ['doctor', '--fix']
                args << '--yes' unless options[:interactive]
                samovar_root.call(args)
                return
              end

              if confirm_doctor?
                samovar_root.call(['doctor'])
              else
                common.echo_always('後で実行する場合: vs doctor もしくは vs doctor --fix (macOS)')
              end
            end
          rescue StandardError => e
            common.log_warn("doctor 実行フローでエラーが発生しました: #{e}")
          end

          def samovar_root
            Vivlio::Starter::CLI::SamovarCommands::RootCommand
          end

          def confirm_doctor?
            return false unless $stdin.tty?

            $stdout.print('qpdf / pdfinfo の診断を実行しますか？ [y/N]: ')
            ans = $stdin.gets
            ans && ans.strip.downcase == 'y'
          end
        end
      end
    end
  end
end
