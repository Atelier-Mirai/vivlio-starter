# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio/starter/cli/common'
require 'vivlio/starter/cli/rename'
require 'vivlio/starter/cli/build_helpers'
require 'vivlio/starter/cli'

module Vivlio
  module Starter
    module CLI
      class RenameCommandsTest < Minitest::Test
        # 章名変更で Markdown/CSS/画像が揃ってリネームされることを確認
        def test_rename_updates_markdown_css_and_images
          within_temp_dir do
            command = build_rename_command(force: true)
            setup_single_chapter_fixture('11-old', css: true, images: true, html: true)

            build_helpers_calls = []
            thor_calls = []

            BuildHelpers.stub :update_css_counter, ->(path, value) { build_helpers_calls << [path, value] } do
              Vivlio::Starter::ThorCLI.stub :start, ->(args) { thor_calls << args } do
                capture_io { command.rename('11-old', '12-new') }
              end
            end

            assert File.exist?(File.join(Common::CONTENTS_DIR, '12-new.md'))
            refute File.exist?(File.join(Common::CONTENTS_DIR, '11-old.md'))
            assert Dir.exist?('images/12-new')
            refute Dir.exist?('images/11-old')
            refute File.exist?('11-old.html')

            assert_empty build_helpers_calls
            assert_empty thor_calls
          end
        end

        # 引数なしで実行した際に章番号が再割り当てされることを確認
        def test_rename_without_arguments_performs_renumber
          within_temp_dir do
            command = build_rename_command(force: true)
            setup_single_chapter_fixture('11-alpha', css: true, images: true)
            setup_single_chapter_fixture('31-beta', css: true, images: true)

            build_helpers_calls = []
            thor_calls = []

            BuildHelpers.stub :update_css_counter, ->(path, value) { build_helpers_calls << [path, value] } do
              Vivlio::Starter::ThorCLI.stub :start, ->(args) { thor_calls << args } do
                error = assert_raises(SystemExit) do
                  capture_io { command.rename }
                end
                assert_equal 0, error.status
              end
            end

            assert File.exist?(File.join(Common::CONTENTS_DIR, '11-alpha.md'))
            assert File.exist?(File.join(Common::CONTENTS_DIR, '12-beta.md'))
            refute File.exist?(File.join(Common::CONTENTS_DIR, '31-beta.md'))
            assert Dir.exist?('images/11-alpha')
            assert Dir.exist?('images/12-beta')
            refute Dir.exist?('images/31-beta')

            assert_empty build_helpers_calls
            assert_equal [['clean']], thor_calls
          end
        end

        private

        # テスト用 Rename コマンドを生成
        def build_rename_command(options = {})
          Class.new do
            # Thor DSL のスタブを用意
            def self.desc(*) = nil
            def self.long_desc(*) = nil
            def self.method_option(*) = nil

            include RenameCommands

            attr_reader :options

            def initialize(options)
              @options = options
            end
          end.new({ force: false, dry_run: false, verbose: false }.merge(options))
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
              yield dir
            end
          end
        end
      end
    end
  end
end
