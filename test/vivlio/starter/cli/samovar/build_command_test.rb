# frozen_string_literal: true

require 'test_helper'
require 'vivlio/starter/cli/samovar'
require 'vivlio/starter/cli/samovar/build_command'

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
      end
    end
  end
end
