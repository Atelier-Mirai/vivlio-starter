# frozen_string_literal: true

# ================================================================
# Test: open_commands_test.rb
# ================================================================
# テスト対象:
#   PDF ファイルを開くロジック（lib/vivlio_starter/cli/pdf.rb）
#
# 検証内容:
#   - 圧縮版 PDF が新しい場合の優先選択
#   - 圧縮版が存在しない場合のフォールバック
#   - 複数 PDF ファイルの選択ロジック
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/pdf'

module VivlioStarter
  module CLI
    # PDF オープン機能のユニットテスト
    class OpenCommandsTest < Minitest::Test
      # 圧縮版 PDF が新しい場合に優先して開くことを確認
      def test_open_pdf_prefers_compressed_when_newer
        within_temp_dir do
          setup_pdf_files
          FileUtils.touch('output.pdf', mtime: Time.now - 60)
          FileUtils.touch('output_compressed.pdf', mtime: Time.now)

          opened = run_opener_and_capture

          assert_equal ['output_compressed.pdf'], opened
        end
      end

      # 圧縮版が存在しない場合、通常版を開くことを確認
      def test_open_pdf_uses_fallback_when_compressed_missing
        within_temp_dir do
          setup_pdf_files(include_compressed: false)

          opened = run_opener_and_capture

          assert_equal ['output.pdf'], opened
        end
      end

      # 明示的に指定したPDFパスを開くことを確認
      def test_open_pdf_with_explicit_path
        within_temp_dir do
          write_file('sample.pdf')

          opened = run_opener_and_capture(explicit_path: 'sample.pdf')

          assert_equal ['sample.pdf'], opened
        end
      end

      private

      # PdfOpener をスタブ化して開かれたパスを収集する
      def run_opener_and_capture(explicit_path: nil)
        options = { verbose: false }
        opener = VivlioStarter::CLI::PdfCommands::PdfOpener.new(options, explicit_path)
        opened = []

        capture_io do
          opener.stub(:macos?, true) do
            opener.stub(:close_existing_windows_if_needed, nil) do
              opener.stub(:position_window, nil) do
                opener.stub(:open_pdf, proc { |path| opened << path }) do
                  opener.call
                end
              end
            end
          end
        end

        opened
      end

      # 一時ディレクトリで検証を実行する
      def within_temp_dir
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) { yield dir }
        end
      end

      # テスト用の PDF ファイルを生成する
      def setup_pdf_files(include_compressed: true)
        write_file('output.pdf')
        write_file('output_compressed.pdf') if include_compressed
      end

      # ヘルパ: 空ファイルを生成
      def write_file(path)
        FileUtils.mkdir_p(File.dirname(path)) unless File.dirname(path) == '.'
        FileUtils.touch(path)
      end
    end
  end
end
