# frozen_string_literal: true

# ================================================================
# Test: delete_commands_test.rb
# ================================================================
# テスト対象:
#   DeleteCommands モジュール（lib/vivlio_starter/cli/delete.rb）
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
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/delete'

module VivlioStarter
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

      # 消した章を指す索引辞書の main: を外す（vs rename の追随と対・改善案.md #108）
      def test_delete_forgets_main_references_to_the_deleted_chapter
        within_temp_dir do
          setup_chapter_fixture('11-sample')
          File.write('config/index_glossary_terms.yml', {
            'terms' => [
              { 'term' => 'テスト', 'yomi' => 'てすと', 'flags' => 'i', 'main' => ['11-sample'] },
              { 'term' => 'CSS', 'yomi' => 'CSS', 'flags' => 'i', 'main' => %w[11-sample 15] }
            ]
          }.to_yaml)

          capture_io { DeleteCommands::DeleteCommandExecutor.new({ force: true }, ['11-sample']).call }

          terms = YAML.load_file('config/index_glossary_terms.yml')['terms'].to_h { [it['term'], it] }
          refute terms['テスト'].key?('main'), '空になった語は「未決定」に戻す'
          assert_equal ['15'], terms['CSS']['main']
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
