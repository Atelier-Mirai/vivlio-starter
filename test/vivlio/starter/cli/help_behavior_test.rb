# frozen_string_literal: true

require 'test_helper'
require 'vivlio/starter'
require 'vivlio/starter/cli'

module Vivlio
  module Starter
    module CLI
      class HelpBehaviorTest < Minitest::Test
        # `vs --help` 実行時に ThorCLI の help が呼び出されることを確認
        def test_global_help_invokes_thor_help
          calls = []

          Vivlio::Starter::ThorCLI.stub :start, ->(args) { calls << args; 0 } do
            status = ::Vivlio::Starter::CLI.start(['--help'])
            assert_equal 0, status
          end

          assert_equal [['help']], calls
        end

        # `vs build --help` 実行時に jp_task_help が呼び出されることを確認
        def test_command_help_uses_jp_task_help
          jp_calls = []

          Vivlio::Starter::ThorCLI.stub :start, ->(_args) { flunk('start should not be called when jp_task_help is available') } do
            Vivlio::Starter::ThorCLI.stub :jp_task_help, ->(cmd) { jp_calls << cmd } do
              status = ::Vivlio::Starter::CLI.start(['build', '--help'])
              assert_equal 0, status
            end
          end

          assert_equal ['build'], jp_calls
        end
      end
    end
  end
end
