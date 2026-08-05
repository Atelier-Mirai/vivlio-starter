# frozen_string_literal: true

# ================================================================
# Test: post_process/main_chapter_token_test.rb
# ================================================================
# テスト対象:
#   HeadingProcessor.main_chapter_token?（heading_processor.rb）と、
#   CrossReferenceProcessor が前処理で組む本文章の並び（cross_reference_processor.rb）
#
# 通底する不変条件:
#   **contents/ に置いただけのファイルが、図表番号の章プレフィックスをずらさないこと。**
#   前処理（図表番号）と後処理（章見出しの番号）は別々に並びを作るため、ここが
#   ずれると「章扉は第 4 章なのに図は 5-1」という食い違いが出る。
#
# 検証内容:
#   - `_` 始まりは章として数えない（システムページ・著者向け説明ファイル）。
#     とくに contents/_README.md——TokenResolver は `_README` に番号 01 を
#     割り当てるため、素通しにすると並びの先頭に居座る
#   - catalog.yml に無い章は数えない（`vs create` したあと catalog から外した草稿）
#   - 本文章（01〜89）だけを真とし、前書き・付録・後書きは偽
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/token_resolver'
require 'vivlio_starter/cli/build'
require 'vivlio_starter/cli/pre_process'
require 'vivlio_starter/cli/post_process'

module VivlioStarter
  module CLI
    module PostProcessCommands
      class MainChapterTokenTest < Minitest::Test
        CHAPTERS = %w[11-workflow 12-quickstart 21-images].freeze

        def setup
          HeadingProcessor.chapter_tokens_override = nil
        end

        def teardown
          HeadingProcessor.chapter_tokens_override = nil
        end

        # 著者向けの説明ファイルは章ではない。
        # TokenResolver が番号 01 を割り当てても、接頭辞で弾く
        def test_should_not_count_author_readme_as_a_chapter
          in_project do
            refute HeadingProcessor.main_chapter_token?('_README')
          end
        end

        # システムページも章ではない（従来から番号を持たないが、明示的に固定する）
        def test_should_not_count_system_pages_as_chapters
          in_project do
            %w[_titlepage _legalpage _colophon _indexpage _glossarypage _toc _part1].each do |token|
              refute HeadingProcessor.main_chapter_token?(token), "#{token} は章ではない"
            end
          end
        end

        # 本文章だけが真。前書き・付録・後書きは章の並びに入れない
        def test_should_count_only_main_chapters
          in_project do
            assert HeadingProcessor.main_chapter_token?('11-workflow')
            assert HeadingProcessor.main_chapter_token?('21-images')
            refute HeadingProcessor.main_chapter_token?('00-preface')
            refute HeadingProcessor.main_chapter_token?('91-appendix')
          end
        end

        # 症状の回帰テスト。_README.md があっても図表番号の章プレフィックスがずれない
        def test_should_not_shift_chapter_numbers_when_readme_exists
          in_project do
            assert_equal '1', chapter_prefix('11-workflow.md')
            assert_equal '2', chapter_prefix('12-quickstart.md')
            assert_equal '3', chapter_prefix('21-images.md')
          end
        end

        # `vs create 15-draft` したあと catalog.yml から外した草稿は、原稿が
        # contents/ に残る。これを数に入れると以降の章の図表番号だけがずれる
        def test_should_not_shift_chapter_numbers_when_uncataloged_draft_exists
          in_project do
            File.write(File.join(Common::CONTENTS_DIR, '15-draft.md'), "# 15-draft\n")

            assert_equal '1', chapter_prefix('11-workflow.md')
            assert_equal '2', chapter_prefix('12-quickstart.md'), '草稿を数に入れて 3 にしてはならない'
            assert_equal '3', chapter_prefix('21-images.md')
          end
        end

        private

        def chapter_prefix(filename)
          PreProcessCommands::CrossReferenceProcessor.display_chapter_number_for_filename(filename)
        end

        def in_project
          Dir.mktmpdir('vs-main-chapter-token-') do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('config')
              File.write('config/catalog.yml', <<~YAML)
                PREFACE:
                  - 00-preface
                CHAPTERS:
                #{CHAPTERS.map { "  - #{it}\n" }.join}
                APPENDICES:
                  - 91-appendix
              YAML
              FileUtils.mkdir_p(Common::CONTENTS_DIR)
              # _README.md は vs new が配る著者向けの説明ファイル
              ['00-preface', *CHAPTERS, '91-appendix', '_README'].each do |basename|
                File.write(File.join(Common::CONTENTS_DIR, "#{basename}.md"), "# #{basename}\n")
              end
              yield
            end
          end
        end
      end
    end
  end
end
