# frozen_string_literal: true

# ================================================================
# Test: help_spec_test.rb
# ================================================================
# テスト対象:
#   help_spec.md に定義されたヘルプ機能の実装
#
# 検証内容:
#   - vs --help: Public Commands のみ表示
#   - vs pdf --help: pdf:compress への案内表示
#   - vs pdf:compress / pdf:pages / pdf:rasterize --help: PDF系コマンドのヘルプ表示
#   - vs build --help: ビルドコマンドのヘルプ表示
#   - Internal Commands: --help 非対応
# ================================================================

require 'test_helper'
require 'vivlio_starter'
require 'vivlio_starter/cli'

module VivlioStarter
  module CLI
    class HelpSpecTest < Minitest::Test
      # vs --help: Public Commands がカテゴリ別に表示される
      def test_root_help_shows_public_commands_only
        output, = capture_io do
          status = ::VivlioStarter::CLI.start(['--help'])
          assert_equal 0, status
        end

        # カテゴリ見出しの確認
        assert_includes output, 'プロジェクト管理:'
        assert_includes output, '執筆・編集支援:'
        assert_includes output, '索引・用語集:'
        assert_includes output, 'ビルド・出力・プレビュー:'

        # Public Commands の確認
        assert_includes output, 'new'
        assert_includes output, 'build'
        assert_includes output, 'clean'
        assert_includes output, 'import'
        assert_includes output, 'pdf:compress'
        assert_includes output, 'pdf:pages'
        assert_includes output, 'pdf:rasterize'

        # Internal Commands が含まれないことの確認
        refute_includes output, 'pre_process'
        refute_includes output, 'convert'
        refute_includes output, 'post_process'
        refute_includes output, 'entries'
      end

      # vs help: vs --help と同等の出力
      def test_help_command_shows_public_commands
        output, = capture_io do
          status = ::VivlioStarter::CLI.start(['help'])
          assert_equal 0, status
        end

        assert_includes output, 'Vivlio Starter'
        assert_includes output, 'build'
        assert_includes output, 'pdf:compress'
        assert_includes output, 'pdf:pages'
        assert_includes output, 'pdf:rasterize'
      end

      # vs pdf --help: 内部コマンドであることと pdf:compress への案内
      def test_pdf_help_shows_compress_guidance
        output, = capture_io do
          status = ::VivlioStarter::CLI.start(['pdf', '--help'])
          assert_equal 0, status
        end

        assert_includes output, '内部コマンド'
        assert_includes output, 'pdf:compress'
      end

      # vs pdf:compress --help: 圧縮コマンドの詳細ヘルプ
      def test_pdf_compress_help_shows_usage
        output, = capture_io do
          status = ::VivlioStarter::CLI.start(['pdf:compress', '--help'])
          assert_equal 0, status
        end

        assert_includes output, 'pdf:compress'
        assert_includes output, 'Usage:'
        assert_includes output, 'INPUT'
        assert_includes output, 'OUTPUT'
      end

      # vs pdf:pages --help: ページ画像化コマンドの詳細ヘルプ
      def test_pdf_pages_help_shows_usage
        output, = capture_io do
          status = ::VivlioStarter::CLI.start(['pdf:pages', '--help'])
          assert_equal 0, status
        end

        assert_includes output, 'pdf:pages'
        assert_includes output, '--dpi'
        assert_includes output, '--pages'
        assert_includes output, '--output'
      end

      # vs pdf:rasterize --help: ラスタライズコマンドの詳細ヘルプ
      def test_pdf_rasterize_help_shows_usage
        output, = capture_io do
          status = ::VivlioStarter::CLI.start(['pdf:rasterize', '--help'])
          assert_equal 0, status
        end

        assert_includes output, 'pdf:rasterize'
        assert_includes output, '--dpi'
        assert_includes output, '--quality'
        assert_includes output, '--clean'
      end

      # vs build --help: ビルドコマンドのヘルプ（print_usage）
      def test_build_help_shows_usage
        output, = capture_io do
          status = ::VivlioStarter::CLI.start(['build', '--help'])
          assert_equal 0, status
        end

        assert_includes output, 'build'
        assert_includes output, 'resize'
        assert_includes output, 'compress'
      end

      # vs clean --help: クリーンコマンドのヘルプ（--all オプション含む）
      def test_clean_help_shows_all_option
        output, = capture_io do
          status = ::VivlioStarter::CLI.start(['clean', '--help'])
          assert_equal 0, status
        end

        assert_includes output, 'clean'
        assert_includes output, '--all'
        assert_includes output, '--purge'
      end

      # vs index --help: 索引サブコマンドの案内
      def test_index_help_shows_subcommands
        output, = capture_io do
          status = ::VivlioStarter::CLI.start(['index', '--help'])
          assert_equal 0, status
        end

        assert_includes output, 'index:auto'
        assert_includes output, 'index:apply'
      end

      # vs create --help: 章作成コマンドのヘルプ
      def test_create_help_shows_usage
        output, = capture_io do
          status = ::VivlioStarter::CLI.start(['create', '--help'])
          assert_equal 0, status
        end

        assert_includes output, 'create'
      end

      # Public/Internal コマンド分類の検証
      def test_command_classification
        root = SamovarCommands::RootCommand

        # Public Commands の確認
        public_commands = root.public_commands.keys
        assert_includes public_commands, 'build'
        assert_includes public_commands, 'clean'
        assert_includes public_commands, 'pdf:compress'
        assert_includes public_commands, 'pdf:pages'
        assert_includes public_commands, 'pdf:rasterize'
        assert_includes public_commands, 'index'
        refute_includes public_commands, 'pdf'
        refute_includes public_commands, 'pre_process'

        # Internal Commands の確認
        # 注: pre_process, convert, post_process, toc, entries, vivliostyle は
        #     build コマンドから内部的に呼び出される純粋な内部処理に移行済み
        internal_commands = root.internal_commands.keys
        assert_includes internal_commands, 'pdf'
        assert_includes internal_commands, 'create:titlepage'
        assert_includes internal_commands, 'create:colophon'
        assert_includes internal_commands, 'create:legalpage'
        refute_includes internal_commands, 'build'
        refute_includes internal_commands, 'pre_process'
        refute_includes internal_commands, 'convert'
      end
    end
  end
end
