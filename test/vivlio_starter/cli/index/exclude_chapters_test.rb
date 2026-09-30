# frozen_string_literal: true

# ================================================================
# Test: index/exclude_chapters_test.rb
# ================================================================
# テスト対象:
#   IndexCommands.without_excluded_chapters（index_glossary.exclude_chapters・改善案 #97）
#
# 検証内容:
#   - 番号・スラッグ・範囲のどれで書いても、指した章だけが外れる
#   - スラッグでも指せる（TokenResolver が解く。番号の追随は chapter_rename_test）
#   - 何も書かなければ（既定の []）何も外さない
#   - catalog.yml に無い章の指定は無視する
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/index'

module VivlioStarter
  module CLI
    module IndexCommands
      class ExcludeChaptersTest < Minitest::Test
        CHAPTERS = %w[21-markdown 22-extensions 96-books 97-sample].freeze

        def test_should_drop_the_chapter_named_by_number
          in_project(CHAPTERS) do
            assert_equal %w[21-markdown 22-extensions 96-books],
                         IndexCommands.without_excluded_chapters(CHAPTERS, tokens: [97])
          end
        end

        # TokenResolver が解くので、コマンドの章指定と同じくスラッグでも指せる
        def test_should_drop_the_chapter_named_by_slug
          in_project(%w[21-markdown 95-sample]) do
            assert_equal %w[21-markdown],
                         IndexCommands.without_excluded_chapters(%w[21-markdown 95-sample.md], tokens: ['sample'])
          end
        end

        def test_should_drop_a_range_of_chapters
          in_project(CHAPTERS) do
            assert_equal %w[21-markdown 22-extensions],
                         IndexCommands.without_excluded_chapters(CHAPTERS, tokens: ['96-97'])
          end
        end

        def test_should_keep_every_chapter_when_nothing_is_excluded
          in_project(CHAPTERS) do
            assert_equal CHAPTERS, IndexCommands.without_excluded_chapters(CHAPTERS, tokens: [])
            assert_equal CHAPTERS, IndexCommands.without_excluded_chapters(CHAPTERS, tokens: nil)
          end
        end

        def test_should_ignore_a_chapter_missing_from_the_catalog
          in_project(CHAPTERS) do
            assert_equal CHAPTERS, IndexCommands.without_excluded_chapters(CHAPTERS, tokens: ['no-such-slug'])
          end
        end

        private

        def in_project(chapters)
          Dir.mktmpdir('vs-index-exclude-') do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p(%w[config contents])
              body, appendix = chapters.partition { it.to_i < 90 }
              File.write('config/catalog.yml',
                         { 'CHAPTERS' => body, 'APPENDICES' => appendix }.to_yaml)
              chapters.each { File.write("contents/#{it}.md", "# #{it}\n") }
              yield
            end
          end
        end
      end
    end
  end
end
