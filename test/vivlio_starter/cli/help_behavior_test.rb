# frozen_string_literal: true

# ================================================================
# Test: help_behavior_test.rb
# ================================================================
# テスト対象:
#   VivlioStarter::CLI.start（lib/vivlio_starter/cli/startup.rb）
#
# 検証内容:
#   - vs --help: グローバルヘルプの表示（終了コード 0）
#   - vs build --help: コマンドヘルプの表示（終了コード 0）
#   - 未知オプション: ヘルプ表示 + 終了コード 1（POSIX 慣習。CL-02 と同じ契約）
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

      # `vs build --unknown-option` 実行時に build コマンドのヘルプが表示され、
      # 無効入力として終了コード 1 を返すことを確認
      def test_build_unknown_option_displays_command_help
        output, error = capture_io do
          status = ::VivlioStarter::CLI.start(['build', '--unknown-option'])
          assert_equal 1, status
        end

        combined = "#{output}#{error}"
        assert_includes combined, '🔴 「--unknown-option」は指定できません。'
        refute_includes combined, 'Could not parse', 'Samovar の英語を著者へ見せない'
        assert_includes combined, 'build <targets...>'
        assert_includes combined, '書籍全体または指定章をビルドします'
      end

      # print_usage を private で書き直しているコマンドでも、全体の使い方でなく
      # そのコマンドの使い方を出す
      def test_commands_with_private_usage_display_their_own_help
        [['preflight', '--unknown-option'], ['pdf:read', '--unknown-option'],
         %w[open one two], %w[resize one two]].each do |name, *arguments|
          output, error = capture_io do
            status = ::VivlioStarter::CLI.start([name, *arguments])
            assert_equal 1, status, name
          end

          combined = "#{output}#{error}"
          assert_includes combined, "🔴 「#{arguments.last}」は指定できません。", name
          assert_includes combined, "vs #{name} - ", name
          refute_includes combined, 'Vivlio Starter CLI (Samovar)', name
        end
      end

      # `vs clean --unknown-option` 実行時に clean コマンドのヘルプが表示され、
      # 無効入力として終了コード 1 を返すことを確認
      def test_clean_unknown_option_displays_command_help
        output, error = capture_io do
          status = ::VivlioStarter::CLI.start(['clean', '--unknown-option'])
          assert_equal 1, status
        end

        combined = "#{output}#{error}"
        assert_includes combined, '🔴 「--unknown-option」は指定できません。'
        assert_includes combined, 'clean [--purge/-P]'
        assert_includes combined, '生成物やキャッシュを削除します'
      end

      # `vs hogehoge`（存在しないコマンド）は主要コマンド一覧を出す。
      # 未知コマンドでは nested の既定で HelpCommand が選ばれるため、放っておくと
      # help 自身の usage（`help [-h/--help]`）という手がかりのない表示になる。
      def test_unknown_command_displays_the_public_command_list
        output, error = capture_io do
          status = ::VivlioStarter::CLI.start(['hogehoge'])

          assert_equal 1, status, '未知コマンドは POSIX 慣習で非 0 を返すはずです'
        end

        combined = "#{output}#{error}"

        assert_includes combined, '使い方: vs <command> [options]', '主要コマンド一覧を出すはずです'
        assert_includes combined, 'プロジェクト管理:'
        assert_includes combined, 'build'
        refute_includes combined, 'help [-h/--help]', 'help 自身の usage は手がかりにならない'
      end
    end
  end
end
