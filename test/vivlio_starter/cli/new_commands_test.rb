# frozen_string_literal: true

# ================================================================
# Test: new_commands_test.rb
# ================================================================
# テスト対象:
#   NewCommand（lib/vivlio_starter/cli/samovar/new_command.rb）
#
# 検証内容:
#   - プロジェクト名省略時のバリデーションエラー
#   - 不正文字を含むプロジェクト名のバリデーションエラー
#   - --yes モードで全ファイルが展開されデフォルト値が反映される
#   - {{PROJECT_NAME}} が引数のプロジェクト名で置換される
#   - 既存ディレクトリ（デフォルト）でエラー終了
#   - 既存ディレクトリ（--force）で既存ファイルをスキップ
#   - vs doctor --fix 失敗時に警告を出力しファイルは残る
#   - 対話で「n」を入力した場合の中断
#   - --log=debug でコピー中のファイルパスが出力される
#
# テスト環境:
#   - 一時ディレクトリで副作用を隔離
#   - system() をスタブ化して doctor 実行を差し替え
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'samovar'
require 'vivlio_starter/cli/samovar'

module VivlioStarter
  module CLI
    # NewCommand の統合テスト
    class NewCommandsTest < Minitest::Test
      # プロジェクト名省略でエラー終了（exit 1）することを確認
      def test_should_exit_with_error_when_project_name_is_missing
        within_temp_dir do
          error = assert_raises(SystemExit) do
            capture_io { run_new_command([]) }
          end

          assert_equal 1, error.status
        end
      end

      # 不正文字を含むプロジェクト名でエラー終了することを確認
      def test_should_exit_with_error_when_project_name_contains_invalid_chars
        within_temp_dir do
          error = assert_raises(SystemExit) do
            capture_io { run_new_command(['my book!']) }
          end

          assert_equal 1, error.status
        end
      end

      # --yes モードで全ファイルが展開されデフォルト値が book.yml に反映されることを確認
      def test_should_expand_scaffold_with_default_values_in_yes_mode
        within_temp_dir do
          stub_system_call do
            capture_io { run_new_command(['testbook', '--yes']) }
          end

          assert Dir.exist?('testbook'), 'プロジェクトディレクトリが生成されるべき'
          assert File.exist?('testbook/config/book.yml'), 'book.yml が生成されるべき'
          assert File.exist?('testbook/package.json'), 'package.json がコピーされるべき'
          assert Dir.exist?('testbook/contents'), 'contents/ が生成されるべき'
          assert Dir.exist?('testbook/stylesheets'), 'stylesheets/ が生成されるべき'

          book_yml = File.read('testbook/config/book.yml', encoding: 'utf-8')
          assert_includes book_yml, '新しい本', 'デフォルトの書籍名が反映されるべき'
          refute_includes book_yml, '{{MAIN_TITLE}}', 'プレースホルダーが残っていてはいけない'
        end
      end

      # {{PROJECT_NAME}} がコマンド引数の値で置換されることを確認
      def test_should_replace_project_name_placeholder_in_book_yml
        within_temp_dir do
          stub_system_call do
            capture_io { run_new_command(['myproject', '--yes']) }
          end

          book_yml = File.read('myproject/config/book.yml', encoding: 'utf-8')
          assert_includes book_yml, 'myproject', 'project.name がプロジェクト名と一致するべき'
          refute_includes book_yml, '{{PROJECT_NAME}}', 'プレースホルダーが残っていてはいけない'
        end
      end

      # 既存ディレクトリ（--force なし）でエラー終了しディレクトリが変更されないことを確認
      def test_should_exit_with_error_when_directory_exists_without_force
        within_temp_dir do
          FileUtils.mkdir_p('existing')
          File.write('existing/my_file.txt', 'original', encoding: 'utf-8')

          error = assert_raises(SystemExit) do
            capture_io { run_new_command(['existing']) }
          end

          assert_equal 1, error.status
          assert_equal 'original', File.read('existing/my_file.txt')
        end
      end

      # --force で既存ファイルをスキップし不足ファイルのみ追加されることを確認
      def test_should_skip_existing_files_and_add_missing_ones_with_force
        within_temp_dir do
          FileUtils.mkdir_p('partial/config')
          File.write('partial/config/book.yml', 'custom content', encoding: 'utf-8')

          stub_system_call do
            capture_io { run_new_command(['partial', '--force', '--yes']) }
          end

          # 既存ファイルは上書きされない
          assert_equal 'custom content', File.read('partial/config/book.yml')
          # 不足ファイルは追加される
          assert File.exist?('partial/package.json'), '不足ファイルが追加されるべき'
        end
      end

      # vs doctor --fix 失敗時に警告を出力しファイル展開は成功していることを確認
      def test_should_warn_when_doctor_fails_but_keep_files
        within_temp_dir do
          # system() が false を返す（doctor 失敗）
          stub_system_call(success: false) do
            out, _err = capture_io { run_new_command(['doctorfail', '--yes']) }

            assert Dir.exist?('doctorfail'), 'プロジェクトディレクトリは残るべき'
            assert File.exist?('doctorfail/config/book.yml'), 'ファイル展開は成功しているべき'
            assert_match(/doctor --fix/, out, '手動実行の案内が出力されるべき')
          end
        end
      end

      # 対話で「n」を入力した場合に中断されることを確認
      def test_should_abort_when_user_answers_no_in_confirmation
        within_temp_dir do
          # stdin に「n」を含む入力を流し込む
          # 4つのプロンプト（書籍名、副題、著者、発行者）+ 確認
          input = StringIO.new("テスト本\n\nテスト著者\n\nn\n")

          exit_error = assert_raises(SystemExit) do
            $stdin = input
            capture_io { run_new_command(['cancelbook']) }
          ensure
            $stdin = STDIN
          end

          assert_equal 0, exit_error.status
          refute Dir.exist?('cancelbook'), 'ディレクトリは作成されないべき'
        end
      end

      # 特殊文字を含む著者名が book.yml を破壊せず、YAML としてパース可能であることを確認
      # （3-2-1, 3-2-2 の回帰テスト）
      def test_should_escape_special_chars_in_interactive_answers_safely
        within_temp_dir do
          # 書籍名(")、副題(\\)、著者名(改行混入ペースト事故想定)、発行者(タブ)
          input = StringIO.new(%(my"book\n\\\\series\n山田\t太郎\nmy\rpublisher\ny\n))

          stub_system_call do
            $stdin = input
            capture_io { run_new_command(['escbook']) }
          ensure
            $stdin = STDIN
          end

          book_yml_path = 'escbook/config/book.yml'
          assert File.exist?(book_yml_path), 'book.yml が生成されるべき'

          # YAML としてパース可能であること（最重要）
          parsed = nil
          assert_silent do
            parsed = YAML.safe_load_file(book_yml_path, aliases: true)
          rescue StandardError => e
            flunk "book.yml が YAML としてパースできない: #{e.message}"
          end

          # エスケープされた値が正しく読み出せること
          # subtitle: 入力の `\\series`（バックスラッシュ2つ）が round-trip で完全保持されるべき
          #   YAML 二重引用符内では `\` を `\\` に倍化する必要があるため、ファイル上は 4 つ。
          #   YAML パース後は元の 2 つに戻る（= 入力の完全保持）。
          assert_equal 'my"book', parsed.dig('book', 'main_title')
          assert_equal '\\\\series', parsed.dig('book', 'subtitle')
          assert_equal "山田\t太郎", parsed.dig('book', 'author')
        end
      end

      # --log=debug でコピー中のファイルパスが出力されることを確認
      def test_should_output_debug_logs_when_log_debug_is_set
        within_temp_dir do
          stub_system_call do
            out, _err = capture_io { run_new_command(['debugbook', '--yes', '--log', 'debug']) }

            assert_match(/\[debug\]/, out, 'デバッグログが出力されるべき')
          end
        end
      end

      private

      # NewCommand を Samovar 経由で実行するヘルパー
      # @param args [Array<String>] コマンド引数
      def run_new_command(args)
        cmd = SamovarCommands::NewCommand.new(args)
        cmd.call
      end

      # system() をスタブ化して doctor 実行をスキップする
      # @param success [Boolean] system() の戻り値
      def stub_system_call(success: true)
        SamovarCommands::NewCommand.define_method(:system) { |*| success }
        yield
      ensure
        SamovarCommands::NewCommand.remove_method(:system)
      end

      # 一時ディレクトリで副作用を隔離する
      def within_temp_dir
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) { yield dir }
        end
      end
    end
  end
end
