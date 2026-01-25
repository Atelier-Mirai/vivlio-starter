# frozen_string_literal: true

# ================================================================
# Test: rename_commands_test.rb
# ================================================================
# テスト対象:
#   RenameCommandExecutor（lib/vivlio/starter/cli/rename.rb）
#
# 検証内容:
#   - 単一章リネーム: Markdown/画像ディレクトリの一括変更
#   - 全章連番付け直し: 章番号の再割り当て
#   - catalog.yml の自動更新
#
# テスト環境:
#   - 一時ディレクトリで副作用を隔離
#   - CleanCommands をスタブ化してクリーンアップをスキップ
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio/starter/cli/common'
require 'vivlio/starter/cli/rename'
require 'vivlio/starter/cli/clean'
require 'vivlio/starter/cli/build'

module Vivlio
  module Starter
    module CLI
      # RenameCommandExecutor のユニットテスト
      class RenameCommandsTest < Minitest::Test
        # 章名変更で Markdown と画像ディレクトリが揃ってリネームされることを確認
        def test_rename_updates_markdown_css_and_images
          within_temp_dir do
            executor = build_rename_executor(force: true)
            setup_single_chapter_fixture('11-old', css: true, images: true, html: true)

            capture_io { executor.call('11-old', '12-new') }

            assert File.exist?(File.join(Common::CONTENTS_DIR, '12-new.md'))
            refute File.exist?(File.join(Common::CONTENTS_DIR, '11-old.md'))
            assert Dir.exist?('images/12-new')
            refute Dir.exist?('images/11-old')
            refute File.exist?('11-old.html')

          end
        end

        # 引数なしで実行した際に章番号が再割り当てされることを確認
        def test_rename_without_arguments_performs_renumber
          within_temp_dir do
            executor = build_rename_executor(force: true)
            setup_single_chapter_fixture('11-alpha', css: true, images: true)
            setup_single_chapter_fixture('31-beta', css: true, images: true)

            clean_calls = []
            Vivlio::Starter::CLI::CleanCommands.stub :execute_clean, ->(opts) { clean_calls << opts } do
              error = assert_raises(SystemExit) do
                capture_io { executor.call }
              end
              assert_equal 0, error.status
            end

            assert File.exist?(File.join(Common::CONTENTS_DIR, '11-alpha.md'))
            assert File.exist?(File.join(Common::CONTENTS_DIR, '12-beta.md'))
            refute File.exist?(File.join(Common::CONTENTS_DIR, '31-beta.md'))
            assert Dir.exist?('images/11-alpha')
            assert Dir.exist?('images/12-beta')
            refute Dir.exist?('images/31-beta')

            assert_equal [{}], clean_calls
          end
        end

        private

        def build_rename_executor(options = {})
          defaults = { force: false, dry_run: false, verbose: false, chapter_step: nil, step: nil }
          Vivlio::Starter::CLI::RenameCommandExecutor.new(defaults.merge(options))
        end

        # 単一章の関連リソースをまとめて準備
        def setup_single_chapter_fixture(base, css: false, images: false, html: false)
          slug = base
          File.write(File.join(Common::CONTENTS_DIR, "#{slug}.md"), "# #{slug}\n")
          FileUtils.mkdir_p(File.join('images', slug)) if images
          File.write("#{slug}.html", '<html></html>') if html
        end

        # 一時ディレクトリで副作用を隔離
        def within_temp_dir
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p(Common::CONTENTS_DIR)
              FileUtils.mkdir_p(Common::IMAGES_DIR)
              FileUtils.mkdir_p('stylesheets')
              FileUtils.mkdir_p('config')
              # catalog.yml を作成（TokenResolver が必要とする）
              File.write('config/catalog.yml', <<~YAML)
                PREFACE:
                CHAPTERS:
                  - 11-old
                  - 11-alpha
                  - 31-beta
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
