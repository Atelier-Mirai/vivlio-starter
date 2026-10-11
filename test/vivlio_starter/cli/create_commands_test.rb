# frozen_string_literal: true

# ================================================================
# Test: create_commands_test.rb
# ================================================================
# テスト対象:
#   CreateCommands モジュール（lib/vivlio_starter/cli/create.rb）
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
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/create'

module VivlioStarter
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

      # 番号を別の章が使っていれば作らずに止め、同じ区分の空き番号で打ち直すコマンドを示す。
      # 作ってしまうと、vs build 97 で 97-sample と 97-foo のどちらを組むか決められない
      def test_should_refuse_a_number_used_by_another_chapter
        within_temp_dir do
          File.write(File.join(Common::CONTENTS_DIR, '97-sample.md'), "# sample\n")

          out, = capture_io do
            assert_raises(SystemExit) { CreateCommands.execute_create(command_context, ['97-foo']) }
          end

          refute File.exist?(File.join(Common::CONTENTS_DIR, '97-foo.md'))
          assert_includes out, '97 番は 97-sample が使っています'
          assert_includes out, 'vs create 90-foo'
        end
      end

      # catalog.yml にだけ載っている章（原稿がまだ無い）の番号も使われているとみなす
      def test_should_refuse_a_number_listed_only_in_catalog
        within_temp_dir do
          out, = capture_io do
            assert_raises(SystemExit) { CreateCommands.execute_create(command_context, ['01-other']) }
          end

          refute File.exist?(File.join(Common::CONTENTS_DIR, '01-other.md'))
          assert_includes out, '01 番は 01-intro が使っています'
          assert_includes out, 'vs create 02-other'
        end
      end

      # 名前が同じ章があれば、番号が違っても止める。vs build sample と章のラベル ID（@ch-sample）が
      # どちらを指すか決められず、著者もどちらを書けばよいか迷う
      def test_should_refuse_a_name_used_by_another_chapter
        within_temp_dir do
          File.write(File.join(Common::CONTENTS_DIR, '97-sample.md'), "# sample\n")

          out, = capture_io do
            assert_raises(SystemExit) { CreateCommands.execute_create(command_context, ['02-sample']) }
          end

          refute File.exist?(File.join(Common::CONTENTS_DIR, '02-sample.md'))
          assert_includes out, 'スラッグ sample は 97-sample が使っています'
          assert_includes out, 'vs create 02-sample-2'
        end
      end

      # 大文字と `_` は整えて作る（ビルド前の検査が止める形の章を作らない）
      def test_should_normalize_capitals_and_underscores
        within_temp_dir do
          capture_io { CreateCommands.execute_create(command_context, ['12-My_Chapter']) }

          assert File.exist?(File.join(Common::CONTENTS_DIR, '12-my-chapter.md'))
        end
      end

      # 点・空白・日本語を含む名前は作らずに止め、直した名前を示す。点を含む章は章の解決が別の章を指していた
      def test_should_refuse_a_name_outside_the_rule
        within_temp_dir do
          out, = capture_io do
            assert_raises(SystemExit) { CreateCommands.execute_create(command_context, ['12-notes.v2']) }
          end

          refute File.exist?(File.join(Common::CONTENTS_DIR, '12-notes.v2.md'))
          assert_includes out, '12-notes.v2 → vs create 12-notes-v2'
        end
      end

      # 一度に作る章どうしで番号が重なるときも止める
      def test_should_refuse_duplicated_numbers_in_one_command
        within_temp_dir do
          out, = capture_io do
            assert_raises(SystemExit) { CreateCommands.execute_create(command_context, %w[30-a 30-b]) }
          end

          refute File.exist?(File.join(Common::CONTENTS_DIR, '30-a.md'))
          assert_includes out, '30 番は 30-a が使っています'
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

      # 既存ファイルがあっても常に上書き再生成されることを確認
      # 旧仕様（force なしでスキップ）は book.yml 変更が反映されない不具合を招いたため廃止。
      # 詳細: book_yml_regeneration_spec.md
      def test_titlepage_always_regenerated_even_when_exists
        within_temp_dir do
          FileUtils.mkdir_p(Common::CACHE_DIR)
          original = "# 既存タイトル\n"
          File.write(File.join(Common::CACHE_DIR, '_titlepage.md'), original)

          capture_io { CreateCommands.execute_titlepage({}) }

          content = File.read(File.join(Common::CACHE_DIR, '_titlepage.md'))
          refute_equal original, content,
                       'force の有無に関わらず book.yml の内容から常に再生成される'
          assert_match(/book-title/, content, 'book.yml から再生成された内容を含む')
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
            main_title: #{title}
          output:
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
            main_title: Sample
          output:
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

        File.write(File.join('chapter_templates', 'chapter_template.md'), "# {{TITLE}}\n")
      end
    end
  end
end
