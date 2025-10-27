# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio/starter/cli/common'
require 'vivlio/starter/cli/delete'

module Vivlio
  module Starter
    module CLI
      class DeleteCommandsTest < Minitest::Test
        # --force 指定で Markdown と画像ディレクトリが削除されることを確認
        def test_delete_removes_markdown_and_images_with_force
          within_temp_dir do
            command = build_delete_command(force: true)
            setup_chapter_fixture('11-sample')

            capture_io { command.delete('11-sample') }

            refute File.exist?(File.join(Common::CONTENTS_DIR, '11-sample.md')), '章 Markdown が削除されるはずです'
            refute Dir.exist?(File.join(Common::IMAGES_DIR, '11-sample')), '画像ディレクトリが削除されるはずです'
          end
        end

        # 対象が見つからない場合に終了コード 1 で終了することを確認
        def test_delete_exits_when_targets_missing
          within_temp_dir do
            command = build_delete_command(force: true)

            error = assert_raises(SystemExit) do
              capture_io { command.delete('11-missing') }
            end
            assert_equal 1, error.status
          end
        end

        private

        # テスト用 Delete コマンドを生成
        def build_delete_command(options = {})
          Class.new do
            # Thor DSL のスタブを用意
            def self.desc(*) = nil
            def self.long_desc(*) = nil
            def self.method_option(*) = nil

            include DeleteCommands

            attr_reader :options

            def initialize(options)
              @options = options
            end
          end.new(options)
        end

        # 章の Markdown と画像ディレクトリを用意
        def setup_chapter_fixture(slug)
          FileUtils.mkdir_p(Common::CONTENTS_DIR)
          FileUtils.mkdir_p(Common::IMAGES_DIR)
          File.write(File.join(Common::CONTENTS_DIR, "#{slug}.md"), "# #{slug}\n")
          FileUtils.mkdir_p(File.join(Common::IMAGES_DIR, slug))
        end

        # 一時ディレクトリを利用して副作用を隔離
        def within_temp_dir
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p(Common::CONTENTS_DIR)
              FileUtils.mkdir_p(Common::IMAGES_DIR)
              yield dir
            end
          end
        end
      end
    end
  end
end
