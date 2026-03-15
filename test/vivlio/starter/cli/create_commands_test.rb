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

        def test_create_supports_numeric_only_name
          within_temp_dir do
            capture_io { CreateCommands.execute_create(command_context, ['15']) }

            assert File.exist?(File.join(Common::CONTENTS_DIR, '15.md')), '数字のみ指定でも Markdown を生成すべき'
            assert Dir.exist?(File.join(Common::IMAGES_DIR, '15')), '画像ディレクトリは数字のみで作成されるべき'

            catalog = File.read('config/catalog.yml')
            assert_includes catalog, '15', 'catalog.yml にも数字章が追記されるべき'
          end
        end

        def test_create_assigns_number_for_slug_only_input
          within_temp_dir do
            capture_io { CreateCommands.execute_create(command_context, ['three-elements']) }

            assert File.exist?(File.join(Common::CONTENTS_DIR, '02-three-elements.md')),
                   '次の若番 (02) を払い出してファイルを生成するべき'
            assert Dir.exist?(File.join(Common::IMAGES_DIR, '02-three-elements')),
                   '画像ディレクトリも自動作成されるべき'

            catalog = File.read('config/catalog.yml')
            assert_includes catalog, '02-three-elements', 'catalog.yml にも追加されるべき'
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

        # --- システムページ生成テスト ---

        # _titlepage.md が .cache/vs/ に生成されることを確認
        def test_titlepage_generated_in_cache_dir
          within_temp_dir do
            capture_io { CreateCommands.execute_titlepage({}) }

            assert File.exist?(File.join(Common::CACHE_DIR, '_titlepage.md')),
                   '_titlepage.md は .cache/vs/ に生成されるべき'
            refute File.exist?(File.join(Common::CONTENTS_DIR, '_titlepage.md')),
                   '_titlepage.md は contents/ に生成されてはならない'
          end
        end

        # _colophon.md が .cache/vs/ に生成されることを確認
        def test_colophon_generated_in_cache_dir
          within_temp_dir do
            capture_io { CreateCommands.execute_colophon({}) }

            assert File.exist?(File.join(Common::CACHE_DIR, '_colophon.md')),
                   '_colophon.md は .cache/vs/ に生成されるべき'
            refute File.exist?(File.join(Common::CONTENTS_DIR, '_colophon.md')),
                   '_colophon.md は contents/ に生成されてはならない'
          end
        end

        # _legalpage.md が .cache/vs/ に生成されることを確認
        def test_legalpage_generated_in_cache_dir
          within_temp_dir do
            capture_io { CreateCommands.execute_legalpage({}) }

            assert File.exist?(File.join(Common::CACHE_DIR, '_legalpage.md')),
                   '_legalpage.md は .cache/vs/ に生成されるべき'
            refute File.exist?(File.join(Common::CONTENTS_DIR, '_legalpage.md')),
                   '_legalpage.md は contents/ に生成されてはならない'
          end
        end

        # 既に存在する場合はスキップされることを確認
        def test_titlepage_skipped_when_already_exists
          within_temp_dir do
            FileUtils.mkdir_p(Common::CACHE_DIR)
            original = "# 既存タイトル\n"
            File.write(File.join(Common::CACHE_DIR, '_titlepage.md'), original)

            capture_io { CreateCommands.execute_titlepage({}) }

            assert_equal original, File.read(File.join(Common::CACHE_DIR, '_titlepage.md')),
                         'force なしでは既存ファイルを上書きしない'
          end
        end

        # force: true で既存ファイルが上書きされることを確認
        def test_titlepage_regenerated_with_force
          within_temp_dir do
            FileUtils.mkdir_p(Common::CACHE_DIR)
            File.write(File.join(Common::CACHE_DIR, '_titlepage.md'), '# 古い内容')

            capture_io { CreateCommands.execute_titlepage({ force: true }) }

            content = File.read(File.join(Common::CACHE_DIR, '_titlepage.md'))
            assert_match(/book-title/, content, 'force: true で book.yml の内容に再生成される')
          end
        end

        # book.yml のタイトル変更が force: true で反映されることを確認
        def test_titlepage_reflects_book_yml_title
          within_temp_dir do
            capture_io { CreateCommands.execute_titlepage({ force: true }) }

            content = File.read(File.join(Common::CACHE_DIR, '_titlepage.md'))
            assert_match(/Sample/, content, 'book.yml の title が反映される')

            # book.yml を更新
            update_book_title('New Title')
            Common.reload_configuration!

            capture_io { CreateCommands.execute_titlepage({ force: true }) }

            content = File.read(File.join(Common::CACHE_DIR, '_titlepage.md'))
            assert_match(/New Title/, content, 'book.yml 更新後に再生成すると新タイトルが反映される')
          end
        end

        private

        def update_book_title(title)
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
              title: #{title}
            output:
              filename:
                include_version: false
          YAML
        end

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
