# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/samovar/new_command.rb
# ================================================================
# 責務:
#   新規書籍プロジェクトを作成する vs new コマンドの実装。
#   対話的な書籍情報収集、scaffold 展開、book.yml 置換、
#   vs doctor --fix 自動実行までを一貫して行う。
#
# 処理フロー:
#   1. 引数バリデーション（プロジェクト名の形式チェック）
#   2. 既存ディレクトリの有無チェック（--force で追加展開を許可）
#   3. 対話形式でユーザーから書籍情報を収集（--yes で省略可）
#   4. lib/project_scaffold/ のファイル一式を展開し book.yml を書き換え
#   5. vs doctor --fix を自動実行して執筆環境をセットアップ
#   6. 完了メッセージを表示
#
# scaffold ソース:
#   lib/project_scaffold/ 以下のディレクトリ・ファイルを再帰コピーする。
#   book.yml 内の {{PLACEHOLDER}} を対話で収集した値で gsub 置換する。
#   この方式は create コマンドの generate_content_from_template と同じ。
#
# 依存:
#   - lib/project_scaffold/: scaffold ソース一式
#   - Common: ログ出力ヘルパー
#   - vs doctor --fix: 環境セットアップ（外部プロセス実行）
# ================================================================

require 'fileutils'
require 'shellwords'

module Vivlio
  module Starter
    module CLI
      module SamovarCommands
        # 新規書籍プロジェクトを作成する Public コマンド
        #
        # scaffold ソース（lib/project_scaffold/）を展開し、
        # 対話で収集した書籍情報を book.yml に反映する。
        class NewCommand < Samovar::Command
          self.description = '新しい書籍プロジェクトを作成します'

          one :name, 'プロジェクト名', required: false

          options do
            option '--yes/-y', '対話をスキップしデフォルト設定で作成する', default: false, key: :yes
            option '--force', '既存ディレクトリへの追加展開を許可する', default: false, key: :force
            option '--log <level>', 'ログレベル（debug など）', key: :log
            option '-h/--help', 'このコマンドの使い方を表示', key: :help
          end

          # lib/project_scaffold/ への絶対パス
          # __dir__ = lib/vivlio/starter/cli/samovar/ から4つ上 = lib/
          SCAFFOLD_SOURCE = File.expand_path('../../../../project_scaffold', __dir__).freeze

          # プロジェクト名に使用可能な文字パターン
          VALID_NAME_PATTERN = /\A[a-zA-Z0-9_\-]+\z/

          # book.yml プレースホルダーのデフォルト値
          DEFAULT_ANSWERS = {
            main_title: '新しい本',
            subtitle: '',
            author: '',
            publisher: ''
          }.freeze

          def call
            return print_usage if options[:help]

            # --- Phase: Validation ---
            project_name = validated_project_name!
            check_existing_directory!(project_name)

            # --- Phase: Interactive ---
            answers = collect_answers(project_name)

            # --- Phase: Scaffold Expansion ---
            expand_scaffold(project_name, answers)

            # --- Phase: Doctor ---
            run_doctor(project_name)

            # --- Phase: Completion ---
            print_success(project_name)
            0
          rescue SystemExit => e
            raise e
          rescue StandardError => e
            Common.log_error("new コマンド実行中にエラー: #{e.message}")
            log_debug(e.full_message) if debug?
            1
          end

          private

          # ================================================================
          # バリデーション
          # ================================================================

          # プロジェクト名を検証し、正規化された名前を返す
          # 引数省略・不正文字はエラーメッセージを出力して exit 1
          # @return [String] 検証済みのプロジェクト名
          def validated_project_name!
            raw = name.to_s.strip
            if raw.empty?
              Common.log_error("エラー: プロジェクト名を指定してください。")
              Common.log_error("  vs new <project_name>")
              exit 1
            end
            unless raw.match?(VALID_NAME_PATTERN)
              Common.log_error("エラー: プロジェクト名に使用できる文字は英数字・ハイフン・アンダースコアのみです。")
              exit 1
            end
            raw
          end

          # 既存ディレクトリの存在をチェックする
          # --force なしで既存ディレクトリがある場合はエラー終了
          # @param project_name [String]
          def check_existing_directory!(project_name)
            return unless Dir.exist?(project_name)
            return if options[:force]

            Common.log_error("エラー: ディレクトリ \"#{project_name}\" はすでに存在します。")
            Common.log_error("上書き展開する場合は --force オプションを指定してください。")
            Common.log_error("  vs new #{project_name} --force")
            exit 1
          end

          # ================================================================
          # 対話フロー
          # ================================================================

          # ユーザーから書籍情報を収集する
          # --yes 指定時はデフォルト値を即座に返す
          # @param project_name [String]
          # @return [Hash] { main_title:, subtitle:, author:, publisher: }
          def collect_answers(project_name)
            if options[:yes]
              Common.log_action("Vivlio Starter: プロジェクト \"#{project_name}\" を作成しています...（デフォルト設定）")
              return DEFAULT_ANSWERS.dup
            end

            puts "Vivlio Starter へようこそ！新しい書籍プロジェクトを作成します。"
            puts

            answers = {
              main_title: prompt("書籍名を入力してください（例: はじめての Ruby）", DEFAULT_ANSWERS[:main_title]),
              subtitle:   prompt("副題を入力してください（任意。Enter でスキップ）", DEFAULT_ANSWERS[:subtitle]),
              author:     prompt("著者名を入力してください（例: 山田 太郎）", DEFAULT_ANSWERS[:author]),
              publisher:  prompt("発行者・サークル名を入力してください（例: アトリヱ未來）", DEFAULT_ANSWERS[:publisher])
            }

            confirm_answers!(project_name, answers)
            answers
          end

          # 1項目分の入力プロンプトを表示し、値を返す
          # 空入力時はデフォルト値を使用する
          # @param message [String] 表示メッセージ
          # @param default [String] デフォルト値
          # @return [String]
          def prompt(message, default)
            $stdout.print("#{message}: ")
            $stdout.flush
            input = $stdin.gets&.strip || ''
            input.empty? ? default : input
          end

          # 収集した回答の確認プロンプトを表示する
          # 「n」で中断、それ以外は続行
          # @param project_name [String]
          # @param answers [Hash]
          def confirm_answers!(project_name, answers)
            subtitle_display = answers[:subtitle].empty? ? '（なし）' : answers[:subtitle]
            author_display   = answers[:author].empty? ? '（なし）' : answers[:author]
            publisher_display = answers[:publisher].empty? ? '（なし）' : answers[:publisher]

            puts
            puts "以下の設定でプロジェクトを作成します。"
            puts
            puts "  プロジェクト名: #{project_name}"
            puts "  書籍名:         #{answers[:main_title]}"
            puts "  副題:           #{subtitle_display}"
            puts "  著者:           #{author_display}"
            puts "  発行者:         #{publisher_display}"
            puts
            $stdout.print("よろしいですか？ [Y/n]: ")
            $stdout.flush
            input = $stdin.gets&.strip || ''

            return unless input.downcase == 'n'

            puts "中断しました。もう一度 vs new #{project_name} を実行してください。"
            exit 0
          end

          # ================================================================
          # Scaffold 展開
          # ================================================================

          # scaffold ソースをプロジェクトディレクトリに展開する
          # --force 時は既存ファイルをスキップ（上書きしない）
          # book.yml のみプレースホルダー置換を行う
          # @param project_name [String]
          # @param answers [Hash]
          def expand_scaffold(project_name, answers)
            FileUtils.mkdir_p(project_name)

            Dir.glob('**/*', File::FNM_DOTMATCH, base: SCAFFOLD_SOURCE).each do |relative|
              src = File.join(SCAFFOLD_SOURCE, relative)
              dst = File.join(project_name, relative)

              # .DS_Store はスキップ
              next if File.basename(relative) == '.DS_Store'

              if File.directory?(src)
                FileUtils.mkdir_p(dst)
                log_debug("ディレクトリ作成: #{dst}")
                next
              end

              # --force 時: 既存ファイルはスキップして保護する
              if File.exist?(dst)
                Common.log_info("スキップ: #{dst}（既存ファイルを保持）")
                next
              end

              FileUtils.mkdir_p(File.dirname(dst))

              # book.yml はプレースホルダー置換してから書き込む
              if relative == File.join('config', 'book.yml')
                rewrite_book_yml(src, dst, answers, project_name)
              else
                FileUtils.cp(src, dst)
              end

              log_debug("コピー: #{relative}")
            end

            Common.log_action("プロジェクトファイルを展開しました: #{project_name}/")
          end

          # book.yml のプレースホルダーを置換して書き込む
          # {{MAIN_TITLE}}, {{SUBTITLE}}, {{AUTHOR}}, {{PUBLISHER}}, {{PROJECT_NAME}}
          # を対話で収集した値に差し替える
          # @param src_path [String] scaffold 内の book.yml パス
          # @param dest_path [String] 展開先の book.yml パス
          # @param answers [Hash]
          # @param project_name [String]
          def rewrite_book_yml(src_path, dest_path, answers, project_name)
            content = File.read(src_path, encoding: 'utf-8')
              .gsub('{{MAIN_TITLE}}',   answers[:main_title])
              .gsub('{{SUBTITLE}}',     answers[:subtitle])
              .gsub('{{AUTHOR}}',       answers[:author])
              .gsub('{{PUBLISHER}}',    answers[:publisher])
              .gsub('{{PROJECT_NAME}}', project_name)
            File.write(dest_path, content, encoding: 'utf-8')
            log_debug("book.yml を置換して書き込みました: #{dest_path}")
          end

          # ================================================================
          # Doctor 自動実行
          # ================================================================

          # vs doctor --fix をプロジェクトディレクトリ内で実行する
          # 失敗時は手動実行を促す警告を表示（プロジェクトは削除しない）
          # @param project_name [String]
          def run_doctor(project_name)
            cmd = "cd #{Shellwords.escape(project_name)} && vs doctor --fix"
            log_debug("実行: #{cmd}")

            success = system(cmd)

            return if success

            warn "⚠️ 警告: vs doctor --fix が失敗しました。"
            warn "  手動で以下を実行してください:"
            warn "  cd #{project_name} && vs doctor --fix"
          end

          # ================================================================
          # 完了メッセージ
          # ================================================================

          # 正常完了時のメッセージを表示する
          # @param project_name [String]
          def print_success(project_name)
            puts
            Common.log_success("プロジェクト \"#{project_name}\" を作成しました。")
            puts
            puts 'book.yml で書籍の設定を変更できます。'
            puts '書き方の参考は contents/ 内のサンプルファイルをご覧ください。'
            puts
            puts '次のコマンドで執筆を始めましょう！'
            puts
            puts "  cd #{project_name}"
            puts '  vs build'
          end

          # ================================================================
          # デバッグユーティリティ
          # ================================================================

          # --log=debug が指定されているか
          # @return [Boolean]
          def debug? = options[:log] == 'debug'

          # デバッグログを出力する（--log=debug 時のみ）
          # @param msg [String]
          def log_debug(msg)
            puts "[debug] #{msg}" if debug?
          end
        end
      end
    end
  end
end
