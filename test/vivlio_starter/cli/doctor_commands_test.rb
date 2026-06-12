# frozen_string_literal: true

# ================================================================
# Test: doctor_commands_test.rb
# ================================================================
# テスト対象:
#   DoctorCommands モジュール（lib/vivlio_starter/cli/doctor.rb）
#
# 検証内容:
#   - 全ツール揃っている場合の正常終了
#   - --fix オプションでの設定ファイル診断・復元の起動
#   - macOS 環境での Homebrew インストール処理
#   - OCR ツールのプラグイン連動診断（PT-01 / PT-02）
#
# テスト環境:
#   - ホスト OS をスタブ化（darwin/linux）
#   - command_exists? をスタブ化
#   - diagnose_config_files! をスタブ化（テスト実行ディレクトリの config/ に
#     復元処理が走らないよう隔離する）
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'vivlio_starter/cli'
require 'vivlio_starter/cli/doctor'

module VivlioStarter
  module CLI
    # DoctorCommands のユニットテスト
    class DoctorCommandsTest < Minitest::Test
      # すべてのツールが揃っている場合、正常終了することを確認
      def test_doctor_reports_success_when_environment_complete
        with_host_os('linux') do
          stub_logging do
            DoctorCommands.stub :diagnose_config_files!, nil do
              DoctorCommands.stub :tesseract_language_available?, true do
                DoctorCommands.stub :command_exists?, ->(_) { true } do
                  DoctorCommands.stub :waifu2x_available?, true do
                    DoctorCommands.stub :install_waifu2x_macos!, ->(*) { flunk('install_waifu2x_macos! should not be called when waifu2x is available') } do
                      capture_io { DoctorCommands.execute_doctor(options_context) }
                    end
                  end
                end
              end
            end
          end
        end
      end

      # --fix 実行時に設定ファイルの診断・復元（diagnose_config_files!）が起動することを確認するテスト。
      # ※ 開発環境のNode.jsやPlaywrightの有無に依存せずテストをパスさせるため、
      #    playwright_npm_available?, chromium_available?, rouge_gem_available? も true にスタブ化しています。
      def test_doctor_fix_diagnoses_config_files_when_environment_complete
        with_host_os('darwin') do
          diagnose_called = false

          stub_logging do
            DoctorCommands.stub :ssl_certificate_configured?, true do
              DoctorCommands.stub :tesseract_language_available?, true do
                DoctorCommands.stub :waifu2x_available?, true do
                  DoctorCommands.stub :playwright_npm_available?, true do
                    DoctorCommands.stub :chromium_available?, true do
                      DoctorCommands.stub :rouge_gem_available?, true do
                        DoctorCommands.stub :command_exists?, ->(_) { true } do
                          DoctorCommands.stub :diagnose_config_files!, ->(_opts) { diagnose_called = true } do
                            capture_io { DoctorCommands.execute_doctor(options_context(fix: true, yes: true)) }
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end

          assert diagnose_called, 'config files should be diagnosed when --fix succeeds without reinstall'
        end
      end

      def test_doctor_reports_missing_textlint_without_fix
        with_host_os('linux') do
          outputs = []

          Common.stub :log_always, ->(message) { outputs << message } do
            stub_logging_without_echo do
              DoctorCommands.stub :diagnose_config_files!, nil do
                DoctorCommands.stub :tesseract_language_available?, true do
                  DoctorCommands.stub :waifu2x_available?, true do
                    DoctorCommands.stub :command_exists?, ->(cmd) { cmd != 'textlint' } do
                      DoctorCommands.execute_doctor(options_context)
                    end
                  end
                end
              end
            end
          end

          assert outputs.any? { |msg| msg.include?('textlint') }
        end
      end

      def test_doctor_fix_installs_textlint_when_missing
        with_host_os('darwin') do
          system_calls = []
          textlint_installed = false
          diagnose_called = false

          stub_logging do
            DoctorCommands.stub :ssl_certificate_configured?, true do
              DoctorCommands.stub :tesseract_language_available?, true do
                DoctorCommands.stub :waifu2x_available?, true do
                  DoctorCommands.stub :command_exists?, lambda { |cmd|
                    case cmd
                    when 'textlint' then textlint_installed
                    else true
                    end
                  } do
                    DoctorCommands.stub :diagnose_config_files!, ->(_opts) { diagnose_called = true } do
                      DoctorCommands.stub :system, lambda { |cmd|
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
                        capture_io { DoctorCommands.execute_doctor(options_context(fix: true, yes: true)) }
                      end
                    end
                  end
                end
              end
            end
          end

          npm_install_cmd = system_calls.find { |cmd| cmd.include?('npm install') && cmd.include?('-g') }
          refute_nil npm_install_cmd, 'npm install -g should be invoked'

          expected_packages = VivlioStarter::CLI::DoctorCommands::TEXTLINT_NPM_PACKAGES
          expected_packages.each do |pkg|
            assert_includes npm_install_cmd, pkg, "npm install -g command should include #{pkg}"
          end

          assert diagnose_called, 'config files should be diagnosed before tool installation'
        end
      end

      def test_tesseract_language_available_detects_japanese_data
        DoctorCommands.stub :command_exists?, true do
          DoctorCommands.stub :capture_command, "List of available languages in /opt/homebrew/share/tessdata/ (3):\neng\njpn\nosd\n" do
            assert_equal(true, DoctorCommands.send(:tesseract_language_available?, 'jpn'))
          end
        end
      end

      def test_doctor_fix_installs_vips_when_missing
        with_host_os('darwin') do
          system_calls = []
          vips_installed = false

          stub_logging do
            DoctorCommands.stub :ssl_certificate_configured?, true do
              DoctorCommands.stub :tesseract_language_available?, true do
                DoctorCommands.stub :waifu2x_available?, true do
                  DoctorCommands.stub :playwright_npm_available?, true do
                    DoctorCommands.stub :chromium_available?, true do
                      DoctorCommands.stub :rouge_gem_available?, true do
                        DoctorCommands.stub :diagnose_config_files!, nil do
                          DoctorCommands.stub :command_exists?, lambda { |cmd|
                            case cmd
                            when 'vips' then vips_installed
                            else true
                            end
                          } do
                            DoctorCommands.stub :system, lambda { |cmd|
                              system_calls << cmd

                              case cmd
                              when /xcode-select -p/ then true
                              when /which brew/ then true
                              when 'brew install vips'
                                vips_installed = true
                                true
                              else
                                true
                              end
                            } do
                              capture_io { DoctorCommands.execute_doctor(options_context(fix: true, yes: true)) }
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end

          assert_includes(system_calls, 'brew install vips')
        end
      end

      def test_doctor_fix_installs_tesseract_language_data_when_missing
        with_host_os('darwin') do
          system_calls = []
          tesseract_installed = false
          tesseract_lang_installed = false

          stub_logging do
            DoctorCommands.stub :ssl_certificate_configured?, true do
              DoctorCommands.stub :waifu2x_available?, true do
                DoctorCommands.stub :playwright_npm_available?, true do
                  DoctorCommands.stub :chromium_available?, true do
                    DoctorCommands.stub :rouge_gem_available?, true do
                      DoctorCommands.stub :diagnose_config_files!, nil do
                        DoctorCommands.stub :tesseract_language_available?, lambda { |language|
                          language == 'jpn' && tesseract_lang_installed
                        } do
                          DoctorCommands.stub :command_exists?, lambda { |cmd|
                            case cmd
                            when 'tesseract' then tesseract_installed
                            else true
                            end
                          } do
                            DoctorCommands.stub :system, lambda { |cmd|
                              system_calls << cmd

                              case cmd
                              when /xcode-select -p/ then true
                              when /which brew/ then true
                              when 'brew install tesseract'
                                tesseract_installed = true
                                true
                              when 'brew install tesseract-lang'
                                tesseract_lang_installed = true
                                true
                              else
                                true
                              end
                            } do
                              capture_io { DoctorCommands.execute_doctor(options_context(fix: true, yes: true)) }
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end

          assert_includes(system_calls, 'brew install tesseract')
          assert_includes(system_calls, 'brew install tesseract-lang')
        end
      end


      def test_doctor_fix_installs_chromium_when_missing
        with_host_os('darwin') do
          system_calls = []

          stub_logging do
            DoctorCommands.stub :ssl_certificate_configured?, true do
              DoctorCommands.stub :tesseract_language_available?, true do
                DoctorCommands.stub :waifu2x_available?, true do
                  DoctorCommands.stub :playwright_npm_available?, true do
                    DoctorCommands.stub :chromium_available?, false do
                      DoctorCommands.stub :rouge_gem_available?, true do
                        DoctorCommands.stub :diagnose_config_files!, nil do
                          DoctorCommands.stub :command_exists?, ->(_) { true } do
                            DoctorCommands.stub :system, lambda { |cmd|
                              system_calls << cmd
                              true
                            } do
                              original_exist = File.method(:exist?)
                              File.stub :exist?, lambda { |path|
                                if path == 'node_modules/playwright/cli.js'
                                  true
                                else
                                  original_exist.call(path)
                                end
                              } do
                                capture_io { DoctorCommands.execute_doctor(options_context(fix: true, yes: true)) }
                              end
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end

          assert_includes system_calls, 'node node_modules/playwright/cli.js install chromium'
        end
      end

      # --fix 指定が非 macOS 環境ではインストールを試みず終了することを確認
      def test_doctor_fix_on_non_macos_aborts_install
        with_host_os('linux') do
          system_calls = []

          stub_logging do
            DoctorCommands.stub :diagnose_config_files!, nil do
              DoctorCommands.stub :command_exists?, ->(_) { false } do
                DoctorCommands.stub :waifu2x_available?, false do
                  DoctorCommands.stub :install_waifu2x_macos!, ->(*) { flunk('install_waifu2x_macos! should not be called on non-macOS') } do
                    DoctorCommands.stub :system, ->(cmd) { system_calls << cmd; false } do
                      capture_io { DoctorCommands.execute_doctor(options_context(fix: true)) }
                    end
                  end
                end
              end
            end
          end

          refute system_calls.any? { |cmd| cmd.include?('brew install') }
        end
      end

      # PT-01: プラグイン未導入なら OCR ツールの不足は :error にせず 🟡 注記で案内する
      def test_should_report_ocr_tools_as_optional_note_when_plugin_absent
        with_host_os('linux') do
          errors = []
          warns = []

          Common.stub :log_error, ->(msg, **) { errors << msg } do
            Common.stub :log_warn, ->(msg, **) { warns << msg } do
              Common.stub :log_always, nil do
                Common.stub :log_info, nil do
                  DoctorCommands.stub :diagnose_config_files!, nil do
                    DoctorCommands.stub :pdf_plugin_installed?, false do
                      DoctorCommands.stub :tesseract_language_available?, false do
                        DoctorCommands.stub :waifu2x_available?, true do
                          DoctorCommands.stub :playwright_npm_available?, true do
                            DoctorCommands.stub :chromium_available?, true do
                              DoctorCommands.stub :rouge_gem_available?, true do
                                DoctorCommands.stub :command_exists?, ->(cmd) { !%w[tesseract vips].include?(cmd) } do
                                  DoctorCommands.execute_doctor(options_context)
                                end
                              end
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end

          refute errors.any? { it.include?('tesseract') || it.include?('vips') },
                 'プラグイン未導入時は OCR ツールの不足を 🔴 にしない'
          assert warns.any? { it.include?('任意ツール') },
                 'プラグイン未導入時は OCR ツールを 🟡 任意ツールとして案内する'
        end
      end

      # PT-02: プラグイン導入済みなら OCR ツールの不足は通常どおり :error として報告する
      def test_should_report_ocr_tools_as_missing_when_plugin_installed
        with_host_os('linux') do
          errors = []
          warns = []

          Common.stub :log_error, ->(msg, **) { errors << msg } do
            Common.stub :log_warn, ->(msg, **) { warns << msg } do
              Common.stub :log_always, nil do
                Common.stub :log_info, nil do
                  DoctorCommands.stub :diagnose_config_files!, nil do
                    DoctorCommands.stub :pdf_plugin_installed?, true do
                      DoctorCommands.stub :tesseract_language_available?, false do
                        DoctorCommands.stub :waifu2x_available?, true do
                          DoctorCommands.stub :playwright_npm_available?, true do
                            DoctorCommands.stub :chromium_available?, true do
                              DoctorCommands.stub :rouge_gem_available?, true do
                                DoctorCommands.stub :command_exists?, ->(cmd) { !%w[tesseract vips].include?(cmd) } do
                                  DoctorCommands.execute_doctor(options_context)
                                end
                              end
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end

          assert errors.any? { it.include?('tesseract') }, 'プラグイン導入時は tesseract の不足を 🔴 で報告する'
          assert errors.any? { it.include?('vips') }, 'プラグイン導入時は vips の不足を 🔴 で報告する'
          refute warns.any? { it.include?('任意ツール') }, 'プラグイン導入時は 🟡 任意ツール注記を出さない'
        end
      end

      private

      def options_context(opts = {})
        { options: { fix: false, yes: false, verbose: false }.merge(opts) }
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
        Common.stub :log_always, nil do
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
