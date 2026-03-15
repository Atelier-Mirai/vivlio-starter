# frozen_string_literal: true

# ================================================================
# Test: delete_commands_test.rb
# ================================================================
# テスト対象:
#   DeleteCommands モジュール（lib/vivlio/starter/cli/delete.rb）
#
# 検証内容:
#   - --force 指定での章 Markdown と画像ディレクトリの削除
#   - 対象が見つからない場合の終了コード 1
#
# テスト環境:
#   - 一時ディレクトリで副作用を隔離
#   - catalog.yml を自動生成（CatalogUpdater が必要とする）
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio/starter/cli/common'
require 'vivlio/starter/cli/delete'

module Vivlio
  module Starter
    module CLI
      # DeleteCommands のユニットテスト
      class DeleteCommandsTest < Minitest::Test
        # --force 指定で章 Markdown と画像ディレクトリが削除されることを確認
        def test_delete_removes_markdown_and_images_with_force
          within_temp_dir do
            setup_chapter_fixture('11-sample')
            options = { force: true }

            capture_io { DeleteCommands::DeleteCommandExecutor.new(options, ['11-sample']).call }

            refute File.exist?(File.join(Common::CONTENTS_DIR, '11-sample.md')), '章 Markdown が削除されるはずです'
            refute Dir.exist?(File.join(Common::IMAGES_DIR, '11-sample')), '画像ディレクトリが削除されるはずです'
          end
        end

        def test_delete_accepts_slug_only_target
          within_temp_dir do
            setup_chapter_fixture('11-sample')
            options = { force: true }

            capture_io { DeleteCommands::DeleteCommandExecutor.new(options, ['sample']).call }

            refute File.exist?(File.join(Common::CONTENTS_DIR, '11-sample.md'))
            refute Dir.exist?(File.join(Common::IMAGES_DIR, '11-sample'))
          end
        end

        def test_delete_handles_numeric_only_chapter
          within_temp_dir do
            setup_chapter_fixture('15')
            options = { force: true }

            capture_io { DeleteCommands::DeleteCommandExecutor.new(options, ['15']).call }

            refute File.exist?(File.join(Common::CONTENTS_DIR, '15.md'))
            refute Dir.exist?(File.join(Common::IMAGES_DIR, '15'))
          end
        end

        # 対象が見つからない場合に終了コード 1 で終了することを確認
        def test_delete_exits_when_targets_missing
          within_temp_dir do
            options = { force: true }

            error = assert_raises(SystemExit) do
              capture_io { DeleteCommands::DeleteCommandExecutor.new(options, ['11-missing']).call }
            end
            assert_equal 1, error.status
          end
        end

        private

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
              FileUtils.mkdir_p('config')
              # catalog.yml を作成（CatalogUpdater が必要とする）
              File.write('config/catalog.yml', <<~YAML)
                PREFACE:
                CHAPTERS:
                  - 11-sample
                  - 15
                APPENDICES:
                POSTFACE:
              YAML
              yield dir
            end
          end
        end
      end
    end
  end
end
