# frozen_string_literal: true

# ================================================================
# Test: samovar_smoke_test.rb
# ================================================================
# テスト対象:
#   Samovar CLI コマンド群の起動可能性・参照関係
#
# 検証内容:
#   1. スモークテスト: 各コマンドがロード・インスタンス化できるか
#   2. require チェーン検証: 依存定数が正しく解決できるか
#   3. CLI→モジュール統合: コマンドが内部モジュールを呼び出せるか
#
# 目的:
#   Samovar 化に伴う require_relative 不足や定数参照エラーを
#   早期に検出し、「コマンドが起動すらできない」問題を防ぐ。
# ================================================================

require 'test_helper'
require 'vivlio/starter/cli/samovar'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # 1. スモークテスト: コマンドの起動可能性を検証
      # ================================================================
      class SamovarCommandsSmokeTest < Minitest::Test
        # テスト対象のコマンドクラス一覧
        COMMAND_CLASSES = {
          build: SamovarCommands::BuildCommand,
          clean: SamovarCommands::CleanCommand,
          create: SamovarCommands::CreateCommand,
          delete: SamovarCommands::DeleteCommand,
          doctor: SamovarCommands::DoctorCommand,
          entries: SamovarCommands::EntriesCommand,
          help: SamovarCommands::HelpCommand,
          new: SamovarCommands::NewCommand,
          pdf: SamovarCommands::PdfCommand,
          rename: SamovarCommands::RenameCommand,
          resize: SamovarCommands::ResizeCommand,
          toc: SamovarCommands::TocCommand,
          pre_process: SamovarCommands::PreProcessCommand,
          post_process: SamovarCommands::PostProcessCommand,
          convert: SamovarCommands::ConvertCommand
        }.freeze

        COMMAND_CLASSES.each do |name, klass|
          define_method("test_#{name}_command_can_be_instantiated") do
            # コマンドクラスが定義されていることを確認
            assert klass, "#{name} コマンドクラスが定義されているべき"

            # 引数なしでインスタンス化できることを確認
            instance = klass.new([])
            assert instance, "#{name} コマンドをインスタンス化できるべき"

            # call メソッドを持つことを確認
            assert instance.respond_to?(:call), "#{name} は call メソッドを持つべき"
          end
        end
      end

      # ================================================================
      # 2. require チェーン検証: 依存定数の解決を検証
      # ================================================================
      class SamovarRequireChainTest < Minitest::Test
        def test_build_command_resolves_unified_build_pipeline
          # BuildCommand から UnifiedBuildPipeline が参照可能であることを確認
          assert defined?(Vivlio::Starter::CLI::BuildCommands::UnifiedBuildPipeline),
                 'BuildCommand から UnifiedBuildPipeline が参照可能であるべき'
        end

        def test_build_command_resolves_token_expander
          assert defined?(Vivlio::Starter::CLI::BuildCommands::TokenExpander),
                 'BuildCommand から TokenExpander が参照可能であるべき'
        end

        def test_build_command_resolves_output_helpers
          assert defined?(Vivlio::Starter::CLI::BuildCommands::OutputHelpers),
                 'BuildCommand から OutputHelpers が参照可能であるべき'
        end

        def test_create_command_resolves_create_commands
          assert defined?(Vivlio::Starter::CLI::CreateCommands),
                 'CreateCommand から CreateCommands が参照可能であるべき'
        end

        def test_delete_command_resolves_delete_command_executor
          assert defined?(Vivlio::Starter::CLI::DeleteCommands::DeleteCommandExecutor),
                 'DeleteCommand から DeleteCommandExecutor が参照可能であるべき'
        end

        def test_doctor_command_resolves_doctor_commands
          assert defined?(Vivlio::Starter::CLI::DoctorCommands),
                 'DoctorCommand から DoctorCommands が参照可能であるべき'
        end

        def test_entries_command_resolves_entries_commands
          assert defined?(Vivlio::Starter::CLI::EntriesCommands),
                 'EntriesCommand から EntriesCommands が参照可能であるべき'
        end

        def test_rename_command_resolves_rename_command_executor
          assert defined?(Vivlio::Starter::CLI::RenameCommandExecutor),
                 'RenameCommand から RenameCommandExecutor が参照可能であるべき'
        end

        def test_clean_command_resolves_clean_commands
          assert defined?(Vivlio::Starter::CLI::CleanCommands),
                 'CleanCommand から CleanCommands が参照可能であるべき'
        end

        def test_pdf_command_resolves_pdf_commands
          assert defined?(Vivlio::Starter::CLI::PdfCommands),
                 'PdfCommand から PdfCommands が参照可能であるべき'
        end

        def test_resize_command_resolves_resize_commands
          assert defined?(Vivlio::Starter::CLI::ResizeCommands),
                 'ResizeCommand から ResizeCommands が参照可能であるべき'
        end

        def test_toc_command_resolves_toc_commands
          assert defined?(Vivlio::Starter::CLI::TocCommands),
                 'TocCommand から TocCommands が参照可能であるべき'
        end

        def test_pre_process_command_resolves_pre_process_commands
          assert defined?(Vivlio::Starter::CLI::PreProcessCommands),
                 'PreProcessCommand から PreProcessCommands が参照可能であるべき'
        end

        def test_post_process_command_resolves_post_process_commands
          assert defined?(Vivlio::Starter::CLI::PostProcessCommands),
                 'PostProcessCommand から PostProcessCommands が参照可能であるべき'
        end

        def test_convert_command_resolves_convert_commands
          assert defined?(Vivlio::Starter::CLI::ConvertCommands),
                 'ConvertCommand から ConvertCommands が参照可能であるべき'
        end
      end

      # ================================================================
      # 3. CLI→モジュール統合テスト: コマンドが内部モジュールを呼び出せるか
      # ================================================================
      class SamovarCommandIntegrationTest < Minitest::Test
        def test_build_command_can_invoke_pipeline
          pipeline_new_called = false
          mock_pipeline = Object.new
          mock_pipeline.define_singleton_method(:run) { [] }
          mock_pipeline.define_singleton_method(:generated_pdf_name) { 'test.pdf' }

          # UnifiedBuildPipeline.new が呼ばれることを確認
          BuildCommands::UnifiedBuildPipeline.stub :new, ->(*_args) {
            pipeline_new_called = true
            mock_pipeline
          } do
            cmd = SamovarCommands::BuildCommand.new([])
            # 内部メソッドをスタブ化して副作用を排除
            cmd.stub(:print_build_timings, nil) do
              cmd.stub(:print_outline_debug_info, nil) do
                cmd.stub(:save_timings_to_file, nil) do
                  cmd.stub(:open_pdf, nil) do
                    Build::ChapterConfig.stub(:configured_chapters, nil) do
                      Common.stub(:log_action, nil) do
                        Common.stub(:log_success, nil) do
                          cmd.call
                        end
                      end
                    end
                  end
                end
              end
            end
          end

          assert pipeline_new_called, 'BuildCommand は UnifiedBuildPipeline.new を呼び出すべき'
        end

        def test_create_command_can_invoke_execute_create
          execute_called = false

          CreateCommands.stub :execute_create, ->(*_args) { execute_called = true } do
            cmd = SamovarCommands::CreateCommand.new(['test-chapter'])
            cmd.call
          end

          assert execute_called, 'CreateCommand は CreateCommands.execute_create を呼び出すべき'
        end

        def test_delete_command_can_invoke_executor
          executor_call_invoked = false

          mock_executor = Object.new
          mock_executor.define_singleton_method(:call) { executor_call_invoked = true }

          DeleteCommands::DeleteCommandExecutor.stub :new, ->(*_args) { mock_executor } do
            cmd = SamovarCommands::DeleteCommand.new(['11'])
            cmd.call
          end

          assert executor_call_invoked, 'DeleteCommand は DeleteCommandExecutor を呼び出すべき'
        end

        def test_doctor_command_can_invoke_execute_doctor
          execute_called = false

          DoctorCommands.stub :execute_doctor, ->(*_args) { execute_called = true } do
            cmd = SamovarCommands::DoctorCommand.new([])
            cmd.call
          end

          assert execute_called, 'DoctorCommand は DoctorCommands.execute_doctor を呼び出すべき'
        end

        def test_clean_command_can_invoke_execute_clean
          execute_called = false

          CleanCommands.stub :execute_clean, ->(*_args) { execute_called = true } do
            cmd = SamovarCommands::CleanCommand.new([])
            cmd.call
          end

          assert execute_called, 'CleanCommand は CleanCommands.execute_clean を呼び出すべき'
        end

        def test_entries_command_can_invoke_execute_entries
          execute_called = false

          EntriesCommands.stub :execute_entries, ->(*_args) { execute_called = true } do
            cmd = SamovarCommands::EntriesCommand.new([])
            cmd.call
          end

          assert execute_called, 'EntriesCommand は EntriesCommands.execute_entries を呼び出すべき'
        end

        def test_rename_command_can_invoke_executor
          executor_call_invoked = false

          mock_executor = Object.new
          mock_executor.define_singleton_method(:call) { |*_args| executor_call_invoked = true }

          RenameCommandExecutor.stub :new, ->(*_args) { mock_executor } do
            cmd = SamovarCommands::RenameCommand.new([])
            cmd.call
          end

          assert executor_call_invoked, 'RenameCommand は RenameCommandExecutor を呼び出すべき'
        end
      end
    end
  end
end
