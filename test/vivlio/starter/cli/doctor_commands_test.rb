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

        def test_doctor_fix_copies_textlint_assets_when_environment_complete
          with_host_os('darwin') do
            command = build_doctor_command(fix: true, yes: true)
            copy_called = false

            stub_logging do
              command.stub :ssl_certificate_configured?, true do
                command.stub :waifu2x_available?, true do
                  command.stub :command_exists?, ->(_) { true } do
                    command.stub :copy_textlint_assets_from_scaffold!, -> { copy_called = true } do
                      capture_io { command.doctor }
                    end
                  end
                end
              end
            end

            assert copy_called, 'textlint assets should be copied when --fix succeeds without reinstall'
          end
        end

        def test_doctor_reports_missing_textlint_without_fix
          with_host_os('linux') do
            command = build_doctor_command

            outputs = []

            Common.stub :echo_always, ->(message) { outputs << message } do
              stub_logging_without_echo do
                command.stub :waifu2x_available?, true do
                  command.stub :command_exists?, ->(cmd) { cmd != 'textlint' } do
                    command.doctor
                  end
                end
              end
            end

            assert outputs.any? { |msg| msg.include?('textlint') }
          end
        end

        def test_doctor_fix_installs_textlint_when_missing
          with_host_os('darwin') do
            command = build_doctor_command(fix: true, yes: true)
            system_calls = []
            textlint_installed = false
            copy_called = false

            stub_logging do
              command.stub :ssl_certificate_configured?, true do
                command.stub :waifu2x_available?, true do
                  command.stub :command_exists?, lambda { |cmd|
                    case cmd
                    when 'textlint' then textlint_installed
                    else true
                    end
                  } do
                    command.stub :copy_textlint_assets_from_scaffold!, -> { copy_called = true } do
                    command.stub :system, lambda { |cmd|
                      system_calls << cmd

                      case cmd
                      when /xcode-select -p/ then true
                      when /which brew/ then true
                      when /brew install/ then true
                      when /which npm/ then true
                      when /npm install -g /
                        textlint_installed = true
                        true
                      else
                        true
                      end
                    } do
                      capture_io { command.doctor }
                    end
                    end
                  end
                end
              end
            end

            npm_install_cmd = system_calls.find { |cmd| cmd.start_with?('npm install -g ') }
            refute_nil npm_install_cmd, 'npm install -g should be invoked'

            expected_packages = Vivlio::Starter::CLI::DoctorCommands::TEXTLINT_NPM_PACKAGES
            expected_packages.each do |pkg|
              assert_includes npm_install_cmd, pkg, "npm install -g command should include #{pkg}"
            end

            assert copy_called, 'textlint assets should be copied after installation'
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

        def stub_logging_without_echo
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
