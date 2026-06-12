# frozen_string_literal: true

# ================================================================
# Test: contract/cli_contract_test.rb
# ================================================================
# CLI 契約テスト（CL）— docs/specs/test-suite-expansion-spec.md §10
#
# 検証内容:
#   CL-01: 全 Public コマンドの --help が exit 0・🔴 なしで応答する
#   CL-02: 未知のコマンドはクラッシュせず help へ誘導する
#   CL-03: vs --version / vs --help が exit 0 で応答する
#
# コマンド一覧は RootCommand.public_commands から動的に取得するため、
# コマンドを追加すると自動的に契約対象へ入る（一覧のハードコードはしない）。
# Guard の挙動（プロジェクト外で exit 1 等）は guards テストの守備範囲のため
# ここでは検証しない（spec §1.1 の分担）。
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/startup'

module VivlioStarter
  module CLI
    class CliContractTest < Minitest::Test
      # CL-01: 全 Public コマンドが --help に exit 0 で応答し、🔴 を出さない
      def test_should_respond_to_help_for_every_public_command
        SamovarCommands::RootCommand.public_commands.each_key do |name|
          out, err = capture_io do
            status = CLI.start([name, '--help'])
            assert_equal 0, status, "vs #{name} --help は exit 0 であるべき"
          end
          combined = out + err

          refute_empty combined.strip, "vs #{name} --help は使い方を表示するべき"
          refute_includes combined, '🔴', "vs #{name} --help が 🔴 を出力した:\n#{combined}"
        end
      end

      # CL-02: 未知のコマンドはクラッシュせず（スタックトレースなしで）help へ誘導する
      def test_should_guide_to_help_for_unknown_command
        out, err = capture_io { CLI.start(['nosuchcommand']) }
        combined = out + err

        refute_includes combined, 'backtrace', 'スタックトレースを露出すべきではない'
        assert_match(/help|使い方|Usage|コマンド/i, combined, 'help への誘導を表示するべき')
      end

      # CL-02 補遺: 未知のコマンド・オプションは POSIX 慣習に従い非 0 で終了する
      # （シェルスクリプト・CI からタイプミスを検知できるようにする）
      def test_should_exit_nonzero_for_unknown_command
        capture_io do
          assert_equal 1, CLI.start(['nosuchcommand']), '未知コマンドは exit 1 であるべき'
          assert_equal 1, CLI.start(['build', '--nosuchoption']), '未知オプションは exit 1 であるべき'
        end
      end

      # CL-03: --version / --help のグローバルオプション契約
      def test_should_respond_to_version_and_root_help
        out, = capture_io do
          assert_equal 0, CLI.start(['--version'])
        end
        assert_match(/\d+\.\d+\.\d+/, out, 'バージョン文字列を表示するべき')

        out, err = capture_io do
          assert_equal 0, CLI.start(['--help'])
        end
        assert_match(/build/, out + err, 'コマンド一覧に build を含むべき')
      end
    end
  end
end
