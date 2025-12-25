# frozen_string_literal: true

# ================================================================
# Test: text_lint_commands_test.rb
# ================================================================
# テスト対象:
#   TextLintCommands（lib/vivlio/starter/cli/text_lint.rb）
#
# 検証内容:
#   - Markdown ファイル未検出時の警告
#   - textlint 実行結果の解析
#   - 終了コードの適切な設定
#
# テスト環境:
#   - VIVLIO_TEXTLINT_BIN をスタブ化
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio/starter/cli/text_lint'

module Vivlio
  module Starter
    module CLI
      # TextLintCommands のユニットテスト
      class TextLintCommandsTest < Minitest::Test
        def setup
          @original_pwd = Dir.pwd
          @tmpdir = Dir.mktmpdir('textlint-test')
          Dir.chdir(@tmpdir)
          setup_project_structure
          @textlint_bin = ENV['VIVLIO_TEXTLINT_BIN']
          ENV['VIVLIO_TEXTLINT_BIN'] = 'textlint'
        end

        def teardown
          ENV['VIVLIO_TEXTLINT_BIN'] = @textlint_bin
          Dir.chdir(@original_pwd)
          FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
        end

        def test_runner_warns_when_no_markdown_found
          FileUtils.rm_rf('contents')

          status = nil
          with_stubbed_textlint_available do
            stdout, stderr = capture_io do
              status = TextLintCommands.execute_text_lint([], {})
            end
            assert_match(/textlint 対象となる Markdown ファイルが見つかりません。/, stdout)
            assert_empty(stderr)
          end
          assert_equal 0, status
        end

        def test_runner_invokes_textlint_with_resolved_targets
          FileUtils.touch('contents/11-install.md')
          FileUtils.touch('contents/21-customize.md')

          expected_command = nil
          fake_status = Struct.new(:success?).new(true)
          def fake_status.exitstatus
            0
          end

          returned_status = nil
          with_stubbed_textlint_available do
            Open3.stub(:capture3, ->(*args) do
              expected_command = args
              ['STDOUT', 'STDERR', fake_status]
            end) do
              stdout, stderr = capture_io do
                returned_status = TextLintCommands.execute_text_lint(['11-install'], format: nil)
              end
              assert_equal 'STDOUT', stdout
              assert_equal 'STDERR', stderr
            end
          end
          assert_equal 0, returned_status

          assert_equal [
            'textlint',
            '--config', File.expand_path(File.join('config', '.textlintrc.yml')),
            '--format', 'stylish',
            File.join('contents', '11-install.md')
          ], expected_command
        end

        def test_runner_returns_non_zero_status_on_failure
          FileUtils.touch('contents/11-install.md')

          failure_status = Struct.new(:success?).new(false)
          def failure_status.exitstatus
            3
          end

          returned_status = nil
          with_stubbed_textlint_available do
            stdout, stderr = capture_io do
              Open3.stub(:capture3, ->(*_) { ['', '', failure_status] }) do
                returned_status = TextLintCommands.execute_text_lint([], {})
              end
            end
            assert_match(/textlint: ❌/, stdout)
            assert_empty(stderr)
          end
          assert_equal 3, returned_status
        end

        def test_fix_option_includes_fix_flag
          FileUtils.touch('contents/11-install.md')

          expected_command = nil
          fake_status = Struct.new(:success?).new(true)
          def fake_status.exitstatus
            0
          end

          returned_status = nil
          with_stubbed_textlint_available do
            Open3.stub(:capture3, ->(*args) do
              expected_command = args
              ['STDOUT', 'STDERR', fake_status]
            end) do
              stdout, stderr = capture_io do
                returned_status = TextLintCommands.execute_text_lint(['11-install'], { fix: true })
              end
              assert_equal 'STDOUT', stdout
              assert_equal 'STDERR', stderr
            end
          end
          assert_equal 0, returned_status

          assert_includes expected_command, '--fix'
        end

        def test_chapter_number_only_resolution
          FileUtils.touch('contents/91-appendix-a.md')
          FileUtils.touch('contents/91-appendix-b.md')
          FileUtils.touch('contents/92-appendix-c.md')
          FileUtils.touch('contents/93-appendix-d.md')

          expected_command = nil
          fake_status = Struct.new(:success?).new(true)
          def fake_status.exitstatus
            0
          end

          returned_status = nil
          with_stubbed_textlint_available do
            Open3.stub(:capture3, ->(*args) do
              expected_command = args
              ['STDOUT', 'STDERR', fake_status]
            end) do
              stdout, stderr = capture_io do
                returned_status = TextLintCommands.execute_text_lint(['91', '93'], {})
              end
              assert_equal 'STDOUT', stdout
              assert_equal 'STDERR', stderr
            end
          end
          assert_equal 0, returned_status

          # 91 と 93 で始まるファイルが含まれていることを確認
          assert_includes expected_command, File.join('contents', '91-appendix-a.md')
          assert_includes expected_command, File.join('contents', '91-appendix-b.md')
          assert_includes expected_command, File.join('contents', '93-appendix-d.md')
          # 92 は含まれていないことを確認
          refute_includes expected_command, File.join('contents', '92-appendix-c.md')
        end

        def test_range_specification_resolution
          FileUtils.touch('contents/11-install.md')
          FileUtils.touch('contents/12-setup.md')
          FileUtils.touch('contents/13-build.md')
          FileUtils.touch('contents/21-customize.md')

          expected_command = nil
          fake_status = Struct.new(:success?).new(true)
          def fake_status.exitstatus
            0
          end

          returned_status = nil
          with_stubbed_textlint_available do
            Open3.stub(:capture3, ->(*args) do
              expected_command = args
              ['STDOUT', 'STDERR', fake_status]
            end) do
              stdout, stderr = capture_io do
                returned_status = TextLintCommands.execute_text_lint(['11-13'], {})
              end
              assert_equal 'STDOUT', stdout
              assert_equal 'STDERR', stderr
            end
          end
          assert_equal 0, returned_status

          # 11-13 の範囲のファイルが含まれていることを確認
          assert_includes expected_command, File.join('contents', '11-install.md')
          assert_includes expected_command, File.join('contents', '12-setup.md')
          assert_includes expected_command, File.join('contents', '13-build.md')
          # 21 は範囲外なので含まれていないことを確認
          refute_includes expected_command, File.join('contents', '21-customize.md')
        end

        def test_mixed_target_resolution
          FileUtils.touch('contents/11-install.md')
          FileUtils.touch('contents/12-setup.md')
          FileUtils.touch('contents/21-customize.md')
          FileUtils.touch('contents/91-appendix-a.md')

          expected_command = nil
          fake_status = Struct.new(:success?).new(true)
          def fake_status.exitstatus
            0
          end

          returned_status = nil
          with_stubbed_textlint_available do
            Open3.stub(:capture3, ->(*args) do
              expected_command = args
              ['STDOUT', 'STDERR', fake_status]
            end) do
              stdout, stderr = capture_io do
                returned_status = TextLintCommands.execute_text_lint(['11-install', '91', '12-21'], {})
              end
              assert_equal 'STDOUT', stdout
              assert_equal 'STDERR', stderr
            end
          end
          assert_equal 0, returned_status

          # すべての指定されたファイルが含まれていることを確認
          assert_includes expected_command, File.join('contents', '11-install.md')
          assert_includes expected_command, File.join('contents', '91-appendix-a.md')
          assert_includes expected_command, File.join('contents', '12-setup.md')
          assert_includes expected_command, File.join('contents', '21-customize.md')
        end

        def test_fixable_count_extraction
          output_with_fixable = "✖ 10 problems (10 errors, 0 warnings, 0 infos)\n✓ 4 fixable problems.\n"
          output_without_fixable = "✖ 10 problems (10 errors, 0 warnings, 0 infos)\n"
          empty_output = ""

          runner = TextLintCommands::TextLintRunner.new([], {})
          
          assert_equal 4, runner.send(:extract_fixable_count, output_with_fixable)
          assert_equal 0, runner.send(:extract_fixable_count, output_without_fixable)
          assert_equal 0, runner.send(:extract_fixable_count, empty_output)
        end

        def test_target_resolver_range_pattern
          resolver = TextLintCommands::TextLintRunner::TargetResolver.new([])
          
          assert resolver.send(:range_pattern?, '11-21')
          assert resolver.send(:range_pattern?, '1-9')
          refute resolver.send(:range_pattern?, '11-install')
          refute resolver.send(:range_pattern?, '91')
          refute resolver.send(:range_pattern?, 'install-11')
        end

        def test_target_resolver_numeric_only
          resolver = TextLintCommands::TextLintRunner::TargetResolver.new([])
          
          assert resolver.send(:numeric_only?, '91')
          assert resolver.send(:numeric_only?, '11')
          refute resolver.send(:numeric_only?, '11-install')
          refute resolver.send(:numeric_only?, '11-21')
          refute resolver.send(:numeric_only?, 'install')
        end

        private

        def setup_project_structure
          FileUtils.mkdir_p('contents')
          FileUtils.mkdir_p('config/textlint_dictionaries')

          File.write('config/.textlintrc.yml', "rules: {}\n")
          File.write('config/textlint_allowlist.yml', "allow: []\n")
          File.write('config/textlint_prh.yml', "rules: []\n")

          File.write('config/textlint_dictionaries/prh.yml', "version: 1\nrules: []\n")
          File.write('config/textlint_dictionaries/icsmedia.yml', "version: 1\nrules: []\n")
          File.write('config/textlint_dictionaries/js_primer.yml', "version: 1\nrules: []\n")
        end

        def with_stubbed_textlint_available
          runner = TextLintCommands::TextLintRunner
          original = runner.instance_method(:ensure_textlint_available!)
          runner.define_method(:ensure_textlint_available!) { nil }
          yield
        ensure
          runner.define_method(:ensure_textlint_available!) do |*args, &block|
            original.bind(self).call(*args, &block)
          end
        end
      end
    end
  end
end
