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
            calls = []

            stub_logging do
              command.stub :system, ->(cmd) { calls << cmd; command_system_success(cmd) } do
                capture_io { command.doctor }
              end
            end

            expected_checks = %w[node vivliostyle qpdf pdfinfo gs convert]
            expected_checks.each do |label|
              assert_includes calls.any? ? calls.join(' ') : '', label
            end
          end
        end

        # --fix 指定が非 macOS 環境ではインストールを試みず終了することを確認
        def test_doctor_fix_on_non_macos_aborts_install
          with_host_os('linux') do
            command = build_doctor_command(fix: true)
            calls = []

            stub_logging do
              command.stub :system, ->(cmd) { calls << cmd; command_system_missing(cmd) } do
                capture_io { command.doctor }
              end
            end

            refute calls.any? { |cmd| cmd.include?('brew install') }
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
