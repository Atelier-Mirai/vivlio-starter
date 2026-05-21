# frozen_string_literal: true

# ================================================================
# Test: help_behavior_test.rb
# ================================================================
# テスト対象:
#   VivlioStarter::CLI.start（lib/vivlio_starter/cli/startup.rb）
#
# 検証内容:
#   - vs --help: グローバルヘルプの表示
#   - vs build --help: コマンドヘルプの表示
#   - 終了コード 0 での正常終了
# ================================================================

require 'test_helper'
require 'vivlio_starter'
require 'vivlio_starter/cli'

module VivlioStarter
  module CLI
    # ヘルプ表示動作のユニットテスト
    class HelpBehaviorTest < Minitest::Test
      # vs --help 実行時に Samovar のヘルプが表示されることを確認
      def test_global_help_invokes_samovar_help
        status = ::VivlioStarter::CLI.start(['--help'])
        assert_equal 0, status
      end

      # `vs build --help` 実行時に Samovar のコマンドヘルプが表示されることを確認
      def test_command_help_displays_samovar_help
        status = ::VivlioStarter::CLI.start(['build', '--help'])
        assert_equal 0, status
      end

      # `vs build --unknown-option` 実行時に build コマンドのヘルプが表示されることを確認
      def test_build_unknown_option_displays_command_help
        output, error = capture_io do
          status = ::VivlioStarter::CLI.start(['build', '--unknown-option'])
          assert_equal 0, status
        end

        combined = "#{output}#{error}"
        assert_includes combined, 'Could not parse token "--unknown-option"'
        assert_includes combined, 'build <targets...>'
        assert_includes combined, '書籍全体または指定章をビルドします'
      end

      # `vs clean --unknown-option` 実行時に clean コマンドのヘルプが表示されることを確認
      def test_clean_unknown_option_displays_command_help
        output, error = capture_io do
          status = ::VivlioStarter::CLI.start(['clean', '--unknown-option'])
          assert_equal 0, status
        end

        combined = "#{output}#{error}"
        assert_includes combined, 'Could not parse token "--unknown-option"'
        assert_includes combined, 'clean [--purge/-P]'
        assert_includes combined, '生成物やキャッシュを削除します'
      end
    end
  end
end
