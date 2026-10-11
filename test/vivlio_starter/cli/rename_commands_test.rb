# frozen_string_literal: true

# ================================================================
# Test: rename_commands_test.rb
# ================================================================
# テスト対象:
#   RenameCommandExecutor（lib/vivlio_starter/cli/rename.rb）
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
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/rename'
require 'vivlio_starter/cli/clean'
require 'vivlio_starter/cli/build'

module VivlioStarter
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

      def test_rename_accepts_slug_only_target
        within_temp_dir do
          executor = build_rename_executor(force: true)
          setup_single_chapter_fixture('11-old', images: true)

          capture_io { executor.call('11-old', 'new-slug') }

          assert File.exist?(File.join(Common::CONTENTS_DIR, '11-new-slug.md'))
          refute File.exist?(File.join(Common::CONTENTS_DIR, '11-old.md'))
          assert Dir.exist?('images/11-new-slug')
          refute Dir.exist?('images/11-old')
        end
      end

      # スラッグ付き章を番号のみで指定してリネームするとスラッグが維持されること
      # 例: `vs renumber 25 26` で 25-querystream.md → 26-querystream.md
      def test_rename_preserves_slug_when_new_arg_is_number_only
        within_temp_dir do
          executor = build_rename_executor(force: true)
          setup_single_chapter_fixture('31-beta', images: true, html: true)

          capture_io { executor.call('31', '32') }

          assert File.exist?(File.join(Common::CONTENTS_DIR, '32-beta.md'))
          refute File.exist?(File.join(Common::CONTENTS_DIR, '31-beta.md'))
          refute File.exist?(File.join(Common::CONTENTS_DIR, '32.md'))
          assert Dir.exist?('images/32-beta')
          refute Dir.exist?('images/31-beta')
          refute File.exist?('31-beta.html')
        end
      end

      def test_rename_handles_numeric_only_chapter
        within_temp_dir do
          executor = build_rename_executor(force: true)
          setup_single_chapter_fixture('15', images: true, html: true)

          capture_io { executor.call('15', '16') }

          assert File.exist?(File.join(Common::CONTENTS_DIR, '16.md'))
          refute File.exist?(File.join(Common::CONTENTS_DIR, '15.md'))
          assert Dir.exist?('images/16')
          refute Dir.exist?('images/15')
          refute File.exist?('15.html')
        end
      end

      # 変更先の番号をほかの章が使っていれば止める。変更先とまったく同じ名前の章しか見ていなかったので、
      # 20 番の章があっても 31-beta を 20-gamma に変えられた
      def test_rename_refuses_a_number_used_by_another_chapter
        within_temp_dir do
          executor = build_rename_executor(force: true)
          setup_single_chapter_fixture('31-beta')
          setup_single_chapter_fixture('20')

          out, = capture_io { assert_raises(SystemExit) { executor.call('31-beta', '20-gamma') } }

          assert File.exist?(File.join(Common::CONTENTS_DIR, '31-beta.md'))
          refute File.exist?(File.join(Common::CONTENTS_DIR, '20-gamma.md'))
          assert_includes out, '20 番は 20 が使っています'
          assert_includes out, '→ vs rename 31-beta 01-gamma'
        end
      end

      # 変更先の名前をほかの章が使っていれば、番号が違っても止める
      def test_rename_refuses_a_name_used_by_another_chapter
        within_temp_dir do
          executor = build_rename_executor(force: true)
          setup_single_chapter_fixture('31-beta')
          setup_single_chapter_fixture('11-alpha')

          out, = capture_io { assert_raises(SystemExit) { executor.call('31-beta', '32-alpha') } }

          assert File.exist?(File.join(Common::CONTENTS_DIR, '31-beta.md'))
          assert_includes out, 'スラッグ alpha は 11-alpha が使っています'
          assert_includes out, '→ vs rename 31-beta 32-alpha-2'
        end
      end

      # 変更先の名前が決まりの外（点を含む）なら止め、直した名前のコマンドを示す
      def test_rename_refuses_a_name_outside_the_rule
        within_temp_dir do
          executor = build_rename_executor(force: true)
          setup_single_chapter_fixture('31-beta')

          out, = capture_io { assert_raises(SystemExit) { executor.call('31-beta', '32-beta.v2') } }

          assert File.exist?(File.join(Common::CONTENTS_DIR, '31-beta.md'))
          assert_includes out, '→ vs rename 31-beta 32-beta-v2'
        end
      end

      # 大文字と `_` は整えて変える
      def test_rename_normalizes_capitals_and_underscores
        within_temp_dir do
          executor = build_rename_executor(force: true)
          setup_single_chapter_fixture('31-beta')

          capture_io { executor.call('31-beta', '32-Beta_Two') }

          assert File.exist?(File.join(Common::CONTENTS_DIR, '32-beta-two.md'))
        end
      end

      # 既にある重なりを解く rename は止めない（番号 11 が重なった 11-old の名前だけを変える）
      def test_rename_allows_resolving_an_existing_duplicate
        within_temp_dir do
          executor = build_rename_executor(force: true)
          setup_single_chapter_fixture('11-old')
          setup_single_chapter_fixture('11-alpha')

          capture_io { executor.call('11-old', '12-old') }

          assert File.exist?(File.join(Common::CONTENTS_DIR, '12-old.md'))
        end
      end

      # 引数なしで実行した際に章番号が再割り当てされることを確認
      def test_rename_without_arguments_performs_renumber
        within_temp_dir do
          executor = build_rename_executor(force: true)
          setup_single_chapter_fixture('11-alpha', css: true, images: true)
          setup_single_chapter_fixture('31-beta', css: true, images: true)
          setup_single_chapter_fixture('15', images: true)

          clean_calls = []
          VivlioStarter::CLI::CleanCommands.stub :execute_clean, ->(opts) { clean_calls << opts } do
            error = assert_raises(SystemExit) do
              capture_io { executor.call }
            end
            assert_equal 0, error.status
          end

          assert File.exist?(File.join(Common::CONTENTS_DIR, '11-alpha.md'))
          assert File.exist?(File.join(Common::CONTENTS_DIR, '12.md'))
          assert File.exist?(File.join(Common::CONTENTS_DIR, '13-beta.md'))
          refute File.exist?(File.join(Common::CONTENTS_DIR, '31-beta.md'))
          refute File.exist?(File.join(Common::CONTENTS_DIR, '15.md'))
          assert Dir.exist?('images/11-alpha')
          assert Dir.exist?('images/12')
          assert Dir.exist?('images/13-beta')
          refute Dir.exist?('images/31-beta')
          refute Dir.exist?('images/15')

          assert_equal [{}], clean_calls
        end
      end

      private

      def build_rename_executor(options = {})
        defaults = { force: false, dry_run: false, verbose: false, chapter_step: nil, step: nil }
        VivlioStarter::CLI::RenameCommandExecutor.new(defaults.merge(options))
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
                - 15
                - 20
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
