# frozen_string_literal: true

require 'test_helper'
require 'vivlio/starter/cli/samovar'
require 'vivlio/starter/cli/samovar/build_command'
require 'vivlio/starter/cli/token_resolver'

module Vivlio
  module Starter
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
                command.stub :save_timings_to_file, nil do
                  command.stub :open_pdf, nil do
                    command.stub :open_generated_pdf, nil do
                      yield
                    end
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
            attr_reader :entries_param, :mode, :run_called, :generated_pdf_name

            def initialize(entries, mode)
              @entries_param = entries
              @mode = mode
              @generated_pdf_name = mode == :single ? 'single.pdf' : nil
              @run_called = false
            end

            def run
              @run_called = true
              []
            end
          end
        end
      end
    end
  end
end
