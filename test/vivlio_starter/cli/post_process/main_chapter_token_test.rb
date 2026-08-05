# frozen_string_literal: true

# ================================================================
# Test: post_process/main_chapter_token_test.rb
# ================================================================
# テスト対象:
#   HeadingProcessor.main_chapter_token?
#   （lib/vivlio_starter/cli/post_process/heading_processor.rb）
#
# 検証内容:
#   - `_` 始まりは章として数えない（システムページ・著者向け説明ファイル）
#   - とくに contents/_README.md が本文章の並びに紛れないこと。
#     TokenResolver は `_README` に番号 01 を割り当てるため、素通しにすると
#     並びの先頭に居座り、図表番号の章プレフィックスが 1 つずれる
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
            assert_equal '1', PreProcessCommands::CrossReferenceProcessor
                              .display_chapter_number_for_filename('11-workflow.md')
            assert_equal '2', PreProcessCommands::CrossReferenceProcessor
                              .display_chapter_number_for_filename('12-quickstart.md')
            assert_equal '3', PreProcessCommands::CrossReferenceProcessor
                              .display_chapter_number_for_filename('21-images.md')
          end
        end

        private

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
