# frozen_string_literal: true

# ================================================================
# Test: contract/docs_consistency_test.rb
# ================================================================
# ドキュメント整合テスト（DC）— docs/specs/test-suite-expansion-spec.md §11
#
# 検証内容:
#   DC-01: contents/*.md 中の `vs <サブコマンド>` 表記がすべて実在する
#          （タイプミス・廃止コマンドの残骸を検出）
#   DC-02: 全 Public コマンドが contents/ のいずれかで言及されている
#          （新コマンドのドキュメント漏れを検出）
#
# 正規表現抽出のため誤検知は原理的に避けられない。意図的な例外は
# contract/docs_allowlist.yml に理由コメント付きで登録する。
# DC-03（オプション整合）は誤検知コストが高いため初期導入では見送り（spec §11.3）。
# ================================================================

require 'test_helper'
require 'yaml'
require 'vivlio_starter/cli/startup'

module VivlioStarter
  module CLI
    class DocsConsistencyTest < Minitest::Test
      REPO_ROOT = File.expand_path('../../..', __dir__)
      CONTENTS_GLOB = File.join(REPO_ROOT, 'contents', '*.md')
      ALLOWLIST_PATH = File.expand_path('docs_allowlist.yml', __dir__)

      # `vs <サブコマンド>` 表記の抽出パターン。
      # サブコマンドは英小文字始まり・英数字 / `:` / `-` / `_` で構成される
      MENTION_PATTERN = /\bvs\s+([a-z][a-z0-9:_-]*)/

      def setup
        skip 'contents/ が見つかりません（リポジトリ実体でのみ実行）' if manual_files.empty?
      end

      # DC-01: マニュアルに登場するサブコマンドはすべて実在する
      def test_should_mention_only_existing_commands_in_manual
        known = SamovarCommands::RootCommand.command_map.keys
        allowed = allowlist.fetch('non_commands', [])

        unknown_mentions = manual_files.flat_map do |path|
          File.read(path, encoding: 'utf-8').scan(MENTION_PATTERN).flatten.uniq
              .reject { known.include?(it) || allowed.include?(it) }
              .map { "#{File.basename(path)}: vs #{it}" }
        end

        assert_empty unknown_mentions, <<~MSG
          マニュアルに実在しないコマンドへの言及があります（タイプミス・廃止残骸の可能性）:
          #{unknown_mentions.uniq.join("\n")}
          コマンド名以外の表記（例: 一般語）であれば理由コメント付きで
          #{ALLOWLIST_PATH} の non_commands へ追加してください。
        MSG
      end

      # DC-02: 全 Public コマンドがマニュアルのどこかで言及されている
      def test_should_document_every_public_command_in_manual
        corpus = manual_files.map { File.read(it, encoding: 'utf-8') }.join("\n")
        allowed = allowlist.fetch('undocumented_commands', [])

        undocumented = SamovarCommands::RootCommand.public_commands.keys
                                                   .reject { corpus.include?("vs #{it}") }
                                                   .reject { allowed.include?(it) }

        assert_empty undocumented, <<~MSG
          マニュアル（contents/）で言及されていない Public コマンドがあります:
          #{undocumented.join(', ')}
          ドキュメント追加までの暫定許容は理由コメント付きで
          #{ALLOWLIST_PATH} の undocumented_commands へ追加してください。
        MSG
      end

      private

      def manual_files
        @manual_files ||= Dir.glob(CONTENTS_GLOB).sort
      end

      def allowlist
        @allowlist ||= File.exist?(ALLOWLIST_PATH) ? YAML.safe_load(File.read(ALLOWLIST_PATH)) || {} : {}
      end
    end
  end
end
