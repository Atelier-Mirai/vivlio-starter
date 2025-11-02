# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'vivlio/starter/cli'
require 'vivlio/starter/cli/doctor'

module Vivlio
  module Starter
    module CLI
      class DoctorCommandsTest < Minitest::Test
        # すべてのツールが揃っている場合、案内だけで終了することを確認
        def test_doctor_reports_success_when_environment_complete
          with_host_os('linux') do
            command = build_doctor_command
            stub_logging do
              command.stub :command_exists?, ->(_) { true } do
                command.stub :waifu2x_available?, true do
                  command.stub :install_waifu2x_macos!, ->(*) { flunk('install_waifu2x_macos! should not be called when waifu2x is available') } do
                    capture_io { command.doctor }
                  end
                end
              end
            end
          end
        end

        # --fix 指定が非 macOS 環境ではインストールを試みず終了することを確認
        def test_doctor_fix_on_non_macos_aborts_install
          with_host_os('linux') do
            command = build_doctor_command(fix: true)
            system_calls = []

            stub_logging do
              command.stub :command_exists?, ->(_) { false } do
                command.stub :waifu2x_available?, false do
                  command.stub :install_waifu2x_macos!, ->(*) { flunk('install_waifu2x_macos! should not be called on non-macOS') } do
                    command.stub :system, ->(cmd) { system_calls << cmd; false } do
                      capture_io { command.doctor }
                    end
                  end
                end
              end
            end

            refute system_calls.any? { |cmd| cmd.include?('brew install') }
          end
        end

        private

        # テスト用 Doctor コマンドを生成
        def build_doctor_command(options = {})
          Class.new do
            # Thor DSL のスタブ
            def self.desc(*) = nil
            def self.long_desc(*) = nil
            def self.method_option(*) = nil

            include DoctorCommands

            attr_reader :options

            def initialize(options)
              defaults = { fix: false, yes: false, verbose: false }
              @options = defaults.merge(options)
            end
          end.new(options)
        end

        # 指定した host_os を一時的に設定
        def with_host_os(value)
          original = RbConfig::CONFIG['host_os']
          RbConfig::CONFIG['host_os'] = value
          yield
        ensure
          RbConfig::CONFIG['host_os'] = original
        end

        # ログ出力を抑制
        def stub_logging
          Common.stub :echo_always, nil do
            Common.stub :log_info, nil do
              Common.stub :log_warn, nil do
                Common.stub :log_error, nil do
                  Common.stub :log_action, nil do
                    yield
                  end
                end
              end
            end
          end
        end

        # 成功として扱う system 呼び出し
        def command_system_success(cmd)
          case cmd
          when /which/
            true
          when /convert/ # ImageMagick 判定
            true
          else
            true
          end
        end

        # 不足を想定した system 呼び出し（--fix 非対応判定用）
        def command_system_missing(cmd)
          case cmd
          when /which/
            false
          else
            false
          end
        end
      end
    end
  end
end
