# frozen_string_literal: true

require_relative '../../../test_helper'
require 'vivlio_starter/cli/import/yaml_processor'
require 'vivlio_starter/cli/common'
require 'fileutils'
require 'tmpdir'

module VivlioStarter
  module CLI
    module Import
      class YamlProcessorTest < Minitest::Test
        def setup
          @tmpdir = Dir.mktmpdir('yaml_processor_test')
          @original_pwd = Dir.pwd
        end

        def teardown
          Dir.chdir(@original_pwd)
          FileUtils.rm_rf(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
        end

        # ================================================================
        # convert_catalog_line テスト
        # ================================================================
        def test_convert_catalog_line_renames_sections_and_strips_re
          assert_equal "PREFACE:\n", YamlProcessor.convert_catalog_line("PREDEF:\n")
          assert_equal "CHAPTERS:\n", YamlProcessor.convert_catalog_line("CHAPS:\n")
          assert_equal "APPENDICES:\n", YamlProcessor.convert_catalog_line("APPENDIX:\n")
          assert_equal "POSTFACE:\n", YamlProcessor.convert_catalog_line("POSTDEF:\n")
          assert_equal "  - 01-intro\n", YamlProcessor.convert_catalog_line("  - 01-intro.re\n")
        end

        # 「まだ有効にしていない章」を書き残したコメント行は、著者にとって原稿の予定表
        # そのもの。行単位で変換して残す（YAML として読み書きすると消える）
        def test_convert_catalog_line_keeps_commented_out_entries
          assert_equal "    # - lectures\n", YamlProcessor.convert_catalog_line("    # - lectures.re\n")
        end

        # Tips コメント内のセクション名の例も、そのまま使える形に直す
        def test_convert_catalog_line_renames_sections_inside_comments
          assert_equal "##     CHAPTERS:\n", YamlProcessor.convert_catalog_line("##     CHAPS:\n")
        end

        # 部（部タイトル）は Re:VIEW と同じ書き方なので触らない
        def test_convert_catalog_line_keeps_part_titles
          assert_equal "  - 導入篇:\n", YamlProcessor.convert_catalog_line("  - 導入篇:\n")
        end

        # `.re` は拡張子のときだけ落とす（`.review` を巻き込まない）
        def test_convert_catalog_line_does_not_strip_re_inside_longer_words
          assert_equal "# https://example.com/a.review\n",
                       YamlProcessor.convert_catalog_line("# https://example.com/a.review\n")
        end

        # ================================================================
        # convert_catalog! テスト
        # ================================================================
        def test_convert_catalog_writes_converted_catalog_preserving_structure
          starter_dir = File.join(@tmpdir, 'starter')
          FileUtils.mkdir_p(starter_dir)
          File.write(File.join(starter_dir, 'catalog.yml'), <<~CATALOG)
            ## まえがき
            PREDEF:
              - 00-preface.re

            ## 本文
            CHAPS:
              - 導入篇:
                - 01-intro.re
                # - lectures.re

            APPENDIX:
              - 91-books.re

            POSTDEF:
              - 99-postface.re
          CATALOG

          work_dir = File.join(@tmpdir, 'work')
          FileUtils.mkdir_p(File.join(work_dir, 'config'))

          Dir.chdir(work_dir) do
            YamlProcessor.convert_catalog!(starter_dir)

            written = File.read(File.join('config', 'catalog.yml'))

            assert_equal <<~EXPECTED, written
              ## まえがき
              PREFACE:
                - 00-preface

              ## 本文
              CHAPTERS:
                - 導入篇:
                  - 01-intro
                  # - lectures

              APPENDICES:
                - 91-books

              POSTFACE:
                - 99-postface
            EXPECTED
          end
        end

        def test_convert_catalog_warns_and_skips_when_source_missing
          Dir.chdir(@tmpdir) do
            YamlProcessor.convert_catalog!(File.join(@tmpdir, 'nowhere'))

            refute_path_exists File.join('config', 'catalog.yml')
          end
        end

        # ================================================================
        # page_preset_for テスト
        # ================================================================
        def test_page_preset_for_maps_review_starter_sizes_to_standard_presets
          assert_equal 'a5_standard', YamlProcessor.page_preset_for('A5')
          assert_equal 'b5_standard', YamlProcessor.page_preset_for('b5')
        end

        # Re:VIEW Starter が扱わない判型は、勝手に決めずに雛形の値を残す
        def test_page_preset_for_returns_nil_for_unknown_or_blank_size
          assert_nil YamlProcessor.page_preset_for('A3')
          assert_nil YamlProcessor.page_preset_for(nil)
          assert_nil YamlProcessor.page_preset_for('  ')
        end

        # ================================================================
        # use_master_cover! テスト
        # ================================================================
        # 取り込んだ表紙は covers/frontcover_master.png になるので、book.yml も
        # master を指す必要がある。かつては撤去済みの output.pdf.cover.front を
        # 書こうとして、何も起きないまま警告だけが出ていた
        def test_use_master_cover_rewrites_output_cover
          work_dir = File.join(@tmpdir, 'work')
          FileUtils.mkdir_p(File.join(work_dir, 'config'))
          File.write(File.join(work_dir, 'config', 'book.yml'), <<~BOOK)
            output:
              cover: light # 表紙テーマ
              pdf:
                combined: true
          BOOK

          Dir.chdir(work_dir) do
            assert YamlProcessor.use_master_cover!

            written = File.read(File.join('config', 'book.yml'))

            assert_includes written, 'cover: "master" # 表紙テーマ'
            refute_includes written, 'front'
          end
        end

        # ================================================================
        # build_config_updates テスト
        # ================================================================
        def test_build_config_updates_maps_review_config_to_book_yml_keys
          config = {
            'booktitle' => "はじめてのＣ言語 練習帳\n",
            'bookname' => 'workbook_c',
            'language' => 'ja',
            'isbn' => '978-4-00-000000-0',
            'aut' => [{ 'name' => 'アトリヱ未來' }],
            'pubevent_name' => '「技術書典15 新刊」'
          }
          config_starter = { 'starter' => { 'pagesize' => 'B5' } }

          updates = YamlProcessor.build_config_updates(config, config_starter).to_h

          assert_equal 'はじめてのＣ言語 練習帳', updates[%w[book main_title]]
          assert_equal 'workbook_c', updates[%w[project name]]
          assert_equal 'ja', updates[%w[book language]]
          assert_equal '978-4-00-000000-0', updates[%w[book isbn]]
          assert_equal 'アトリヱ未來', updates[%w[book author]]
          assert_equal '「技術書典15 新刊」', updates[%w[book series]]
          assert_equal 'b5_standard', updates[%w[page use]]
        end
      end
    end
  end
end
