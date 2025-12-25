# frozen_string_literal: true

# ================================================================
# Test: create_commands_test.rb
# ================================================================
# テスト対象:
#   CreateCommands モジュール（lib/vivlio/starter/cli/create.rb）
#
# 検証内容:
#   - execute_create: 章 Markdown と画像ディレクトリの生成
#   - 引数省略時のエラー終了
#
# テスト環境:
#   - 一時ディレクトリで副作用を隔離
#   - 必須設定ファイル（book.yml, catalog.yml）を自動生成
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio/starter/cli/common'
require 'vivlio/starter/cli/create'

module Vivlio
  module Starter
    module CLI
      # CreateCommands のユニットテスト
      class CreateCommandsTest < Minitest::Test
        # 章ファイルと画像ディレクトリが正しく生成されることを確認
        def test_create_generates_markdown_and_images_directory
          within_temp_dir do
            capture_io { CreateCommands.execute_create(command_context, ['11-sample']) }

            assert File.exist?(File.join(Common::CONTENTS_DIR, '11-sample.md'))
            assert Dir.exist?(File.join(Common::IMAGES_DIR, '11-sample'))
          end
        end

        # vs create 引数省略時はエラー終了することを確認
        def test_create_without_arguments_exits_with_usage
          within_temp_dir do
            assert_raises(SystemExit) do
              capture_io { CreateCommands.execute_create(command_context, []) }
            end
          end
        end

        private

        def command_context(options = {})
          { options: options }
        end

        # 一時ディレクトリで副作用を隔離
        def within_temp_dir
          original_dir = Dir.pwd
          Dir.mktmpdir do |dir|
            Dir.chdir(dir) do
              setup_directories
              setup_required_configs
              Common.reload_configuration!
              yield dir
            ensure
              Common.reload_configuration!
            end
          end
        ensure
          Dir.chdir(original_dir) unless Dir.pwd == original_dir
          Common.reload_configuration!
        end

        def setup_directories
          %w[contents images config stylesheets codes chapter_templates].each do |name|
            FileUtils.mkdir_p(name)
          end
        end

        def setup_required_configs
          File.write('config/book.yml', <<~YAML)
            directories:
              config: config
              contents: contents
              images: images
              stylesheets: stylesheets
              codes: codes
              chapter_templates: chapter_templates
            commands:
              vfm: vfm
            book:
              title: Sample
            output:
              filename:
                include_version: false
          YAML

          File.write('config/catalog.yml', <<~YAML)
            PREFACE:
              - 00-preface
            CHAPTERS:
              - 01-intro
            APPENDICES:
            POSTFACE:
          YAML

          File.write('config/page_presets.yml', <<~YAML)
            default:
              base_font_size: 10pt
              base_line_height: 15pt
          YAML

          File.write('config/post_replace_list.yml', <<~YAML)
            replacements: []
          YAML

          File.write(File.join('chapter_templates', 'chapter_template.md'), "# {{TITLE}}\n")
        end
      end
    end
  end
end
