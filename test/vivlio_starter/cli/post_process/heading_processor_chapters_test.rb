# frozen_string_literal: true

# ================================================================
# Test: heading_processor_chapters_test.rb
# ================================================================
# テスト対象:
#   HeadingProcessor.configured_main_chapter_tokens
#   （lib/vivlio_starter/cli/post_process/heading_processor.rb）
#
# 検証内容:
#   book.yml の chapters に書ける 6 形式（nil / all / 番号・範囲 / 番号配列 /
#   ファイルベース名の行並び / ファイルベース名配列）が、それぞれ意図どおり
#   章トークンへ落ちること。番号の綴りの解釈は Build::ChapterConfig に寄せたので、
#   その委譲が形式の判別を壊していないことを含めて固定する。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/token_resolver'
require 'vivlio_starter/cli/build'
require 'vivlio_starter/cli/post_process'

module VivlioStarter
  module CLI
    module PostProcessCommands
      class HeadingProcessorChaptersTest < Minitest::Test
        CHAPTERS = %w[11-install 12-tutorial 13-advanced 21-images].freeze

        def setup
          @saved_config = Common::CONFIG
        end

        def teardown
          Common.install_configuration!(@saved_config)
        end

        # nil / 'all' はフルビルド（絞り込みなし）
        def test_should_return_nil_for_full_build
          in_project do
            assert_nil tokens_for(nil)
            assert_nil tokens_for('all')
            assert_nil tokens_for('ALL')
          end
        end

        # 番号・範囲・カンマ区切りは番号指定として解釈される
        def test_should_resolve_number_and_range_strings
          in_project do
            assert_equal ['11-install'], tokens_for('11')
            assert_equal %w[11-install 12-tutorial 13-advanced], tokens_for('11-13')
            assert_equal %w[11-install 13-advanced 21-images], tokens_for('11, 13, 21')
            assert_equal %w[11-install 12-tutorial 21-images], tokens_for('11-12, 21')
          end
        end

        # 全要素が整数の配列も番号指定
        def test_should_resolve_integer_arrays
          in_project do
            assert_equal %w[11-install 13-advanced], tokens_for([11, 13])
            assert_equal %w[11-install 13-advanced], tokens_for(%w[11 13])
          end
        end

        # ファイルベース名は番号指定ではないので、そのままトークンとして扱う
        def test_should_treat_basenames_as_tokens
          in_project do
            assert_equal %w[11-install 12-tutorial], tokens_for("11-install\n12-tutorial")
            assert_equal %w[11-install 21-images], tokens_for(%w[11-install 21-images])
          end
        end

        # 番号とファイルベース名の混在（"11-12, 21-images"）は「番号指定ではない」側へ落ち、
        # 1 行なので行トークンとして丸ごと 1 つのトークンになる。
        # **これは現在の挙動の記録であって、望ましい姿ではない**——実在しない章名なので
        # どの章にも当たらず、著者には何も知らされない。番号指定として展開されていない
        # ことだけが、ここで守りたい性質である。
        def test_should_not_read_mixed_spec_as_numbers
          in_project do
            tokens = tokens_for('11-12, 21-images')

            refute_includes tokens, '11-install', '番号として展開してはならない'
            assert_equal ['11-12, 21-images'], tokens
          end
        end

        # 該当する章が 1 つも無ければ nil（フルビルドへ戻す）
        def test_should_return_nil_when_nothing_selected
          in_project do
            assert_nil tokens_for('')
            assert_nil tokens_for([])
          end
        end

        private

        def tokens_for(chapters)
          Common.install_configuration!(Common.build_direct_configuration(chapters:))
          HeadingProcessor.configured_main_chapter_tokens
        end

        def in_project
          Dir.mktmpdir('vs-heading-chapters-') do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p('config')
              File.write('config/catalog.yml', "CHAPTERS:\n#{CHAPTERS.map { "  - #{it}\n" }.join}")
              FileUtils.mkdir_p(Common::CONTENTS_DIR)
              CHAPTERS.each { File.write(File.join(Common::CONTENTS_DIR, "#{it}.md"), "# #{it}\n") }
              yield
            end
          end
        end
      end
    end
  end
end
