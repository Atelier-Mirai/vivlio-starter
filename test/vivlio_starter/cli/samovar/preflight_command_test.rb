# frozen_string_literal: true

# ================================================================
# Test: preflight_command_test.rb
# ================================================================
# テスト対象:
#   PreflightCommand — vs preflight コマンドの Samovar 実装
#
# 検証内容:
#   - 引数なしで全章が対象になること
#   - 章番号トークンが正しく解決されること
#   - 範囲トークンが正しく解決されること
#   - --no-resize で Step 1 がスキップされること
#   - preflight 実行後に HTML/PDF が生成されないこと
#   - RootCommand.public_commands に登録されていること
#   - vs --help に preflight が表示されること
#   - --help / -h でヘルプが表示されること
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/samovar'
require 'vivlio_starter/cli/samovar/preflight_command'
require 'vivlio_starter/cli/token_resolver'
require 'vivlio_starter'
require 'vivlio_starter/cli'

module VivlioStarter
  module CLI
    module SamovarCommands
      # ----------------------------------------------------------------
      # オプション解析テスト
      # ----------------------------------------------------------------
      class PreflightCommandOptionTest < Minitest::Test
        # --no-resize で options[:resize] が false になる
        def test_should_disable_resize_when_no_resize_is_passed
          command = PreflightCommand.new(['--no-resize'])
          assert_equal false, command.options[:resize]
        end

        # デフォルトで resize が有効
        def test_should_keep_resize_enabled_by_default
          command = PreflightCommand.new([])
          assert_equal true, command.options[:resize]
        end

        # --help で options[:help] が true になる
        def test_should_set_help_option_when_help_is_passed
          command = PreflightCommand.new(['--help'])
          assert_equal true, command.options[:help]
        end

        # -h でも options[:help] が true になる
        def test_should_set_help_option_when_h_is_passed
          command = PreflightCommand.new(['-h'])
          assert_equal true, command.options[:help]
        end
      end

      # ----------------------------------------------------------------
      # 実行テスト
      # ----------------------------------------------------------------
      class PreflightCommandExecutionTest < Minitest::Test
        # 引数なしで全章が対象になり、mode: :preflight で pipeline が呼ばれる
        def test_should_run_all_chapters_when_no_targets_given
          entries = sample_entries('11-sample', '12-tutorial')
          with_resolver_stub(entries) do
            pipelines = []
            with_pipeline_stub(pipelines) do
              command = PreflightCommand.new([])
              suppress_outputs(command) { command.call }
            end

            pipeline = pipelines.last
            assert pipeline.run_called, 'pipeline#run が呼ばれるべきです'
            assert_equal :preflight, pipeline.mode
            assert_equal entries, pipeline.entries_param
          end
        end

        # 章番号トークン "0" が 00-preface に解決される
        def test_should_resolve_chapter_number_token
          entries = sample_entries('00-preface')
          with_resolver_stub(entries) do
            pipelines = []
            with_pipeline_stub(pipelines) do
              command = PreflightCommand.new(['0'])
              suppress_outputs(command) { command.call }
            end

            assert_equal entries, pipelines.last.entries_param
          end
        end

        # 範囲トークン "1-10" が複数章に解決される
        def test_should_resolve_range_token
          entries = sample_entries('01-intro', '05-advanced', '10-summary')
          with_resolver_stub(entries) do
            pipelines = []
            with_pipeline_stub(pipelines) do
              command = PreflightCommand.new(['1-10'])
              suppress_outputs(command) { command.call }
            end

            assert_equal entries, pipelines.last.entries_param
          end
        end

        # --no-resize で pipeline の run_step1 がスキップされる（options[:resize] = false）
        def test_should_skip_step1_when_no_resize
          entries = sample_entries('11-sample')
          with_resolver_stub(entries) do
            pipelines = []
            with_pipeline_stub(pipelines) do
              command = PreflightCommand.new(['--no-resize'])
              suppress_outputs(command) { command.call }
            end

            assert_equal false, pipelines.last.command_options[:resize]
          end
        end

        # preflight 実行後に HTML/PDF ファイルが生成されない
        def test_should_not_generate_html_or_pdf
          entries = sample_entries('11-sample')
          with_resolver_stub(entries) do
            with_pipeline_stub([]) do
              command = PreflightCommand.new([])
              Dir.mktmpdir do |dir|
                Dir.chdir(dir) do
                  suppress_outputs(command) { command.call }
                  html_files = Dir.glob('*.html')
                  pdf_files  = Dir.glob('*.pdf')
                  assert_empty html_files, 'preflight 後に HTML が生成されるべきではありません'
                  assert_empty pdf_files,  'preflight 後に PDF が生成されるべきではありません'
                end
              end
            end
          end
        end

        # --help でヘルプが表示されて終了コード 0 が返る
        def test_should_print_help_with_help_option
          output, = capture_io do
            command = PreflightCommand.new(['--help'])
            result = command.call
            assert_equal 0, result
          end
          assert_includes output, 'preflight'
        end

        private

        def sample_entries(*basenames)
          basenames.map do |bn|
            number = bn[/^\d+/, 0].to_i
            slug = bn.sub(/^\d+-/, '')
            TokenResolver::Entry.new(
              number: number,
              slug: slug,
              kind: :chapter,
              label: bn,
              path: "contents/#{bn}.md",
              exists: true,
              in_catalog: true,
              valid: true
            )
          end
        end

        def suppress_outputs(command)
          PreProcessCommands::LinkImageValidator.stub :reset!, nil do
            PreProcessCommands::LinkImageValidator.stub :print_summary, nil do
              PreProcessCommands::LinkImageValidator.stub :any_issues?, false do
                Common.stub :log_always, nil do
                  yield
                end
              end
            end
          end
        end

        def with_resolver_stub(entries)
          TokenResolver::Resolver.stub :new, -> { ResolverStub.new(entries) } do
            yield
          end
        end

        def with_pipeline_stub(registry)
          BuildCommands::UnifiedBuildPipeline.stub :new, ->(_cmd, entries:, mode:) {
            fake = PipelineStub.new(_cmd, entries, mode)
            registry << fake
            fake
          } do
            yield
          end
        end

        class ResolverStub
          def initialize(return_value)
            @return_value = return_value
          end

          def resolve(*_tokens)
            @return_value
          end
        end

        class PipelineStub
          attr_reader :entries_param, :mode, :run_called, :command_options

          def initialize(command, entries, mode)
            @command_options = command.options
            @entries_param = entries
            @mode = mode
            @run_called = false
          end

          def run
            @run_called = true
            []
          end
        end
      end

      # ----------------------------------------------------------------
      # CLI 統合テスト
      # ----------------------------------------------------------------
      class PreflightCommandRegistrationTest < Minitest::Test
        # RootCommand.public_commands に 'preflight' が登録されている
        def test_should_register_in_public_commands
          assert_includes RootCommand.public_commands.keys, 'preflight'
          assert_equal PreflightCommand, RootCommand.public_commands['preflight']
        end

        # vs --help に preflight が表示される
        def test_should_appear_in_help_output
          output, = capture_io do
            ::VivlioStarter::CLI.start(['--help'])
          end
          assert_includes output, 'preflight'
        end

        # vs preflight --help でヘルプが表示される
        def test_should_print_help_with_help_option_via_cli
          output, = capture_io do
            status = ::VivlioStarter::CLI.start(['preflight', '--help'])
            assert_equal 0, status
          end
          assert_includes output, 'preflight'
          assert_includes output, 'targets'
          assert_includes output, 'resize'
        end
      end
    end
  end
end
