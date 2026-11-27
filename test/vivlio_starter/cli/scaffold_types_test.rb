# frozen_string_literal: true

# ================================================================
# Test: scaffold_types_test.rb
# ================================================================
# テスト対象:
#   ScaffoldTypes（lib/vivlio_starter/cli/scaffold_types.rb。v2-architecture-spec.md §2.6）
#
# 検証内容:
#   - vs new で作れる種類は、技術書と、差分の置き場のある種類
#   - 種類の雛形の book.yml は、本の book.yml の種類で選ぶ（vs upgrade が足す新しいキー。
#     v2-migration-plan.md §5.1）。種類を書いていない本は技術書の雛形
#   - 差分を持つ種類は、共通の雛形の著者のデータの見本とほかの種類のテーマを外し、差分を重ねる
#   - 新しいキーの判定（ScaffoldUpdates）が、小説の本に技術書の雛形のキーを足さない
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/scaffold_types'
require 'vivlio_starter/cli/scaffold_updates'
require 'vivlio_starter/cli/new'

module VivlioStarter
  module CLI
    class ScaffoldTypesTest < Minitest::Test
      SOURCE = NewCommands::SCAFFOLD_SOURCE

      def in_book(book_yml)
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p('config')
            File.write(ScaffoldTypes::BOOK_RELATIVE, book_yml.to_yaml)
            yield
          end
        end
      end

      def test_should_offer_techbook_and_the_types_with_an_overlay
        assert_equal %i[techbook novel], ScaffoldTypes.available(scaffold_source: SOURCE)
      end

      def test_should_choose_the_book_yml_of_the_book_type
        novel = File.join(File.dirname(SOURCE), ScaffoldTypes::TYPES_DIR, 'novel', 'config', 'book.yml')
        base = File.join(SOURCE, 'config', 'book.yml')

        in_book('book' => { 'type' => 'novel' }) { assert_equal novel, ScaffoldTypes.book_yml(scaffold_source: SOURCE) }
        in_book('book' => { 'main_title' => '題' }) { assert_equal base, ScaffoldTypes.book_yml(scaffold_source: SOURCE) }
        assert_equal novel, ScaffoldTypes.book_yml(scaffold_source: SOURCE, type: :novel)
        assert_equal base, ScaffoldTypes.book_yml(scaffold_source: SOURCE, type: :picture_book), '雛形の無い種類は共通の雛形'
      end

      def test_should_overlay_the_novel_files_on_the_common_scaffold
        files = ScaffoldTypes.files(:novel, scaffold_source: SOURCE)

        assert files.key?('contents/11-chumon.md')
        refute files.key?('contents/11-workflow.md'), '技術書の原稿の見本は外す'
        refute(files.each_key.any? { it.start_with?('themes/standard/') }, 'ほかの種類のテーマは外す')
        assert files.key?('themes/novel/theme.yml')
        assert_equal File.join(File.dirname(SOURCE), ScaffoldTypes::TYPES_DIR, 'novel', 'config', 'book.yml'),
                     files['config/book.yml'], '差分が共通の雛形を上書きする'
        assert files.key?('config/page_presets.yml'), '差分に無いファイルは共通の雛形から'
      end

      # 小説の本の vs upgrade は、技術書の雛形の book.yml のキー（index_glossary など）を足さない
      def test_should_not_offer_techbook_keys_to_a_novel_book
        novel_keys = ScaffoldLock.book_keys(File.read(ScaffoldTypes.book_yml(scaffold_source: SOURCE, type: :novel)))
        in_book('book' => { 'type' => 'novel', 'main_title' => '題' }) do
          lock = { book_keys: novel_keys, files: {}, declined: {} }

          assert_empty ScaffoldUpdates.new_book_keys(lock, SOURCE)
        end
      end
    end
  end
end
