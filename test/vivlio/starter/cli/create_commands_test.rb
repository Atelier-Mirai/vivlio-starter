# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio/starter/cli/common'
require 'vivlio/starter/cli/create'

module Vivlio
  module Starter
    module CLI
      class CreateCommandsTest < Minitest::Test
        # vs create が章ファイル・画像ディレクトリを生成することを確認
        def test_create_generates_markdown_and_images_directory
          within_temp_dir do
            command = build_create_command

            capture_io { command.create('11-sample') }

            assert File.exist?(File.join(Common::CONTENTS_DIR, '11-sample.md'))
            assert Dir.exist?(File.join(Common::IMAGES_DIR, '11-sample'))
          end
        end

        # vs create 引数省略時はエラー終了することを確認
        def test_create_without_arguments_exits_with_usage
          within_temp_dir do
            command = build_create_command

            assert_raises(SystemExit) do
              capture_io { command.create }
            end
          end
        end

        private

        # テスト用コマンドクラスを生成
        def build_create_command
          Class.new do
            # Thor DSL のスタブを準備してから include する
            def self.desc(*) = nil
            def self.long_desc(*) = nil
            def self.method_option(*) = nil
            def self.map(*) = nil

            include CreateCommands

            def options
              {}
            end
          end.new
        end

        # 一時ディレクトリで副作用を隔離
        def within_temp_dir
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('contents')
              FileUtils.mkdir_p('images')
              FileUtils.mkdir_p('config')
              # catalog.yml を作成（CatalogUpdater が必要とする）
              File.write('config/catalog.yml', <<~YAML)
                PREFACE:
                CHAPTERS:
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
