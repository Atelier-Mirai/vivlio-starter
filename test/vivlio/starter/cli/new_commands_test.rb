# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio/starter/cli'
require 'vivlio/starter/cli/new'

module Vivlio
  module Starter
    module CLI
      class NewCommandsTest < Minitest::Test
        # プロジェクト名未指定でエラー終了することを確認
        def test_new_requires_project_name
          command = build_new_command

          error = assert_raises(SystemExit) do
            capture_io { command.new(nil) }
          end

          assert_equal 1, error.status
        end

        # 既存ディレクトリ指定時はエラー終了することを確認
        def test_new_exits_when_destination_exists
          within_temp_dir do
            command = build_new_command
            FileUtils.mkdir_p('existing')

            error = assert_raises(SystemExit) do
              capture_io { command.new('existing') }
            end

            assert_equal 1, error.status
          end
        end

        # 自動インストール有効の場合 doctor --fix --yes を呼び出すことを確認
        def test_new_auto_runs_doctor_with_fix
          within_temp_dir do
            command = build_new_command(auto_install: true, manual_install: false, interactive: false)
            thor_calls = []

            Vivlio::Starter::ThorCLI.stub :start, ->(args) { thor_calls << args } do
              capture_io { command.new('mybook') }
            end

            assert Dir.exist?('mybook'), 'プロジェクトディレクトリが生成されるはずです'
            assert_includes thor_calls, ['doctor', '--fix', '--yes']
          end
        end

        # manual_install 指定時は doctor を呼び出さないことを確認
        def test_new_skips_doctor_when_manual_install
          within_temp_dir do
            command = build_new_command(auto_install: true, manual_install: true)
            thor_calls = []

            Vivlio::Starter::ThorCLI.stub :start, ->(args) { thor_calls << args } do
              capture_io { command.new('manual-book') }
            end

            assert Dir.exist?('manual-book'), 'プロジェクトディレクトリが生成されるはずです'
            assert_empty thor_calls
          end
        end

        private

        # テスト用 New コマンドを生成
        def build_new_command(options = {})
          Class.new do
            # Thor DSL のスタブ
            def self.desc(*) = nil
            def self.long_desc(*) = nil
            def self.method_option(*) = nil

            include NewCommands

            attr_reader :options

            def initialize(options)
              defaults = { auto_install: true, manual_install: false, interactive: false, verbose: false }
              @options = defaults.merge(options)
            end
          end.new(options)
        end

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
