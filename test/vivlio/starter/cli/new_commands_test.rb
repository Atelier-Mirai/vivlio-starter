# frozen_string_literal: true

# ================================================================
# Test: new_commands_test.rb
# ================================================================
# テスト対象:
#   NewCommands モジュール（lib/vivlio/starter/cli/new.rb）
#
# 検証内容:
#   - プロジェクト名未指定時のエラー終了
#   - 既存ディレクトリ指定時のエラー終了
#   - --auto-install オプションでの doctor 自動実行
#   - --manual-install オプションでの doctor スキップ
#
# テスト環境:
#   - 一時ディレクトリで副作用を隔離
#   - DoctorCommands をスタブ化
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio/starter/cli'
require 'vivlio/starter/cli/new'

module Vivlio
  module Starter
    module CLI
      # NewCommands のユニットテスト
      class NewCommandsTest < Minitest::Test
        # プロジェクト名未指定でエラー終了することを確認
        def test_new_requires_project_name
          error = assert_raises(SystemExit) do
            capture_io { NewCommands.execute_new(nil) }
          end

          assert_equal 1, error.status
        end

        # 既存ディレクトリ指定時はエラー終了することを確認
        def test_new_exits_when_destination_exists
          within_temp_dir do
            FileUtils.mkdir_p('existing')

            error = assert_raises(SystemExit) do
              capture_io { NewCommands.execute_new('existing') }
            end

            assert_equal 1, error.status
          end
        end

        # 自動インストール有効の場合 DoctorCommands.execute_doctor を呼び出すことを確認
        def test_new_auto_runs_doctor_with_fix
          within_temp_dir do
            options = { auto_install: true, manual_install: false, interactive: false }
            doctor_calls = []

            DoctorCommands.stub :execute_doctor, ->(opts) { doctor_calls << opts } do
              capture_io { NewCommands.execute_new('mybook', options) }
            end

            assert Dir.exist?('mybook'), 'プロジェクトディレクトリが生成されるはずです'
            assert_equal 1, doctor_calls.size
            assert_equal true, doctor_calls.first.dig(:options, :fix)
            assert_equal true, doctor_calls.first.dig(:options, :yes)
          end
        end

        # manual_install 指定時は doctor を呼び出さないことを確認
        def test_new_skips_doctor_when_manual_install
          within_temp_dir do
            options = { auto_install: true, manual_install: true }
            doctor_calls = []

            DoctorCommands.stub :execute_doctor, ->(opts) { doctor_calls << opts } do
              capture_io { NewCommands.execute_new('manual-book', options) }
            end

            assert Dir.exist?('manual-book'), 'プロジェクトディレクトリが生成されるはずです'
            assert_empty doctor_calls
          end
        end

        private

        # 一時ディレクトリで副作用を隔離
        def within_temp_dir
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) { yield dir }
          end
        end
      end
    end
  end
end
