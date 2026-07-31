# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/samovar'
require 'vivlio_starter/cli/samovar/build_command'
require 'vivlio_starter/cli/token_resolver'

module VivlioStarter
  module CLI
    module SamovarCommands
      class BuildCommandOptionTest < Minitest::Test
        def test_should_keep_clean_enabled_by_default
          command = BuildCommand.new([])

          assert_equal true, command.options[:clean], '既定ではクリーンが有効のままになるはずです'
        end

        def test_should_disable_clean_when_no_clean_is_passed
          command = BuildCommand.new(['--no-clean'])

          assert_equal false, command.options[:clean], '--no-clean 指定時は options[:clean] が false になるはずです'
        end

        # Samovar は `--opt=value` を解さないため、初期化時に `--opt value` へ開いている
        def test_should_accept_equals_separated_option_values
          assert_equal 'blue', BuildCommand.new(['x.md', '--theme=blue']).options[:theme]
          assert_equal '#e91e63', BuildCommand.new(['x.md', '--theme=#e91e63']).options[:theme]
          assert_equal 'debug', BuildCommand.new(['10-intro', '--log=debug']).options[:log_level]
        end

        def test_should_keep_space_separated_option_values
          command = BuildCommand.new(['x.md', '--theme', 'blue'])

          assert_equal 'blue', command.options[:theme]
          assert_equal ['x.md'], command.targets
        end

        # 値の既定を持つのは --log だけ（bare `--log` = info）
        def test_should_fill_default_value_only_for_log
          assert_equal 'info', BuildCommand.new(['--log']).options[:log_level]
          assert_nil BuildCommand.new(['x.md', '--theme']).options[:theme]
        end

        # 値が続かない --log の後ろに別オプションが並んでも取りこぼさない
        def test_should_not_swallow_the_option_following_a_bare_log
          command = BuildCommand.new(['10-intro', '--log', '--no-clean'])

          assert_equal 'info', command.options[:log_level]
          assert_equal false, command.options[:clean], '--log の次のオプションが失われないはずです'
        end

        # `=` を含むビルド対象は正規化の対象外（素通し）
        def test_should_pass_through_targets_containing_equals
          assert_equal ['a=b.md'], BuildCommand.new(['a=b.md']).targets
        end
      end

      class BuildCommandExecutionTest < Minitest::Test
        def setup
          @command = BuildCommand.new([])
        end

        def test_call_runs_full_pipeline_when_no_targets
          entries = sample_entries('11-sample', '12-tutorial')
          resolver_instances = [ResolverStub.new(entries)]

          with_resolver_sequence(resolver_instances) do
            pipelines = []
            with_pipeline_stub(pipelines) do
              suppress_build_outputs(@command) do
                assert_equal 0, @command.call
              end
            end

            pipeline = pipelines.last
            assert pipeline.run_called, 'pipeline#run が呼ばれるべきです'
            assert_equal :full, pipeline.mode
            assert_equal entries, pipeline.entries_param
          end
        end

        def test_call_runs_single_pipeline_when_targets_present
          entries = sample_entries('11-sample')
          resolver_instances = [ResolverStub.new(entries)]

          with_resolver_sequence(resolver_instances) do
            pipelines = []
            with_pipeline_stub(pipelines) do
              command = BuildCommand.new(['11-sample'])
              suppress_build_outputs(command) do
                assert_equal 0, command.call
              end
            end

            pipeline = pipelines.last
            assert pipeline.run_called, 'pipeline#run が呼ばれるべきです'
            assert_equal :single, pipeline.mode
            assert_equal entries, pipeline.entries_param
          end
        end

        # 単章ビルドは output.targets によらず閲覧用 PDF だけを作るため、成果物の報告と
        # 自動オープンも targets ではなく「生成できた事実」で決める（targets: kindle でも報告する）
        def test_single_mode_reports_and_opens_generated_pdf_regardless_of_targets
          original_config = Common::CONFIG
          kindle_only = Common.build_direct_configuration(output: { targets: ['kindle'] })

          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('contents')
              FileUtils.mkdir_p('config')
              File.write('config/catalog.yml', "CHAPTERS:\n  - 15\n")
              File.write('contents/15.md', "# Chapter 15\n")
              File.write('config/book.yml', "book:\n  main_title: 'test'\n")
              # PipelineStub が生成したと報告するファイル
              File.write('single.pdf', '%PDF-1.7')
              Common.install_configuration!(kindle_only)

              opened = []
              command = BuildCommand.new(['15'])
              command.stub(:open_generated_pdf, ->(path) { opened << path }) do
                with_pipeline_stub([]) do
                  out = capture_io { assert_equal 0, command.call }.join

                  assert_match(/single\.pdf を作成しました/, out, 'targets: kindle でも成果物を報告するべきです')
                  assert_equal ['single.pdf'], opened, '生成された PDF を開くべきです'
                end
              end
            end
          end
        ensure
          Common.install_configuration!(original_config)
        end

        def test_call_accepts_numeric_only_chapter_targets
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('contents')
              FileUtils.mkdir_p('config')
              File.write('config/catalog.yml', <<~YAML)
                CHAPTERS:
                  - 15
              YAML
              File.write('contents/15.md', "# Chapter 15\n")
              # Guard（前提条件検証）を通過させるための最小プロジェクト構成
              File.write('config/book.yml', "book:\n  main_title: 'test'\n")

              pipelines = []
              with_pipeline_stub(pipelines) do
                command = BuildCommand.new(['15'])
                suppress_build_outputs(command) do
                  assert_equal 0, command.call
                end
              end

              pipeline = pipelines.last
              assert_equal ['15'], pipeline.entries_param.map(&:basename)
            end
          end
        end

        # ルート vivliostyle.config.js は撤去済み（手動フロー撤去・
        # vivlioverso-manual-flow-removal-spec.md）。build はルート config の
        # 存在に一切依存しない（パイプラインは workspace の生成 config を使う）。
        def test_call_proceeds_without_root_vivliostyle_config
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('contents')
              FileUtils.mkdir_p('config')
              File.write('config/catalog.yml', "CHAPTERS:\n  - 15\n")
              File.write('contents/15.md', "# Chapter 15\n")
              File.write('config/book.yml', "book:\n  main_title: 'test'\n")
              refute_path_exists('vivliostyle.config.js')

              pipelines = []
              with_pipeline_stub(pipelines) do
                command = BuildCommand.new(['15'])
                suppress_build_outputs(command) do
                  assert_equal 0, command.call, 'ルート config が無くても build が進行するはずです'
                end
              end
            end
          end
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

        def suppress_build_outputs(command)
          command.stub :print_build_timings, nil do
            command.stub :print_outline_debug_info, nil do
              command.stub :open_pdf, nil do
                command.stub :open_generated_pdf, nil do
                  yield
                end
              end
            end
          end
        end

        def with_resolver_sequence(instances)
          original_new = TokenResolver::Resolver.method(:new)
          calls = instances.dup
          fallback = instances.last

          TokenResolver::Resolver.singleton_class.send(:define_method, :new) do |*args|
            instance = calls.shift || fallback
            if instance
              instance
            else
              original_new.call(*args)
            end
          end

          yield
        ensure
          TokenResolver::Resolver.singleton_class.send(:define_method, :new, original_new)
        end

        def with_pipeline_stub(registry)
          BuildCommands::UnifiedBuildPipeline.stub :new, ->(_cmd, entries:, mode:) {
            fake = PipelineStub.new(entries, mode)
            registry << fake
            fake
          } do
            yield
          end
        end

        # ----------------------------------------
        # Test Doubles
        # ----------------------------------------
        class ResolverStub
          def initialize(return_value)
            @return_value = return_value
          end

          def resolve(*_tokens)
            @return_value
          end
        end

        class PipelineStub
          attr_reader :entries_param, :mode, :run_called, :generated_pdf_name, :wall_time,
                      :parallel_step_labels

          def initialize(entries, mode)
            @entries_param = entries
            @mode = mode
            @generated_pdf_name = mode == :single ? 'single.pdf' : nil
            @run_called = false
            @parallel_step_labels = []
          end

          def run
            @run_called = true
            @wall_time = 0.0
            []
          end
        end
      end
    end
  end
end
