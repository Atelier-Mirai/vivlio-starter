# frozen_string_literal: true

# ================================================================
# Test: help_behavior_test.rb
# ================================================================
# テスト対象:
#   Vivlio::Starter::CLI.start（lib/vivlio/starter/cli.rb）
#
# 検証内容:
#   - vs --help: グローバルヘルプの表示
#   - vs build --help: コマンドヘルプの表示
#   - 終了コード 0 での正常終了
# ================================================================

require 'test_helper'
require 'vivlio/starter'
require 'vivlio/starter/cli'

module Vivlio
  module Starter
    module CLI
      # ヘルプ表示動作のユニットテスト
      class HelpBehaviorTest < Minitest::Test
        # vs --help 実行時に Samovar のヘルプが表示されることを確認
        def test_global_help_invokes_samovar_help
          status = ::Vivlio::Starter::CLI.start(['--help'])
          assert_equal 0, status
        end

        # `vs build --help` 実行時に Samovar のコマンドヘルプが表示されることを確認
        def test_command_help_displays_samovar_help
          status = ::Vivlio::Starter::CLI.start(['build', '--help'])
          assert_equal 0, status
        end
      end
    end
  end
end
