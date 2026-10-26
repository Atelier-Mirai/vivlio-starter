# frozen_string_literal: true

# ================================================================
# Test: catalog_section_kind_test.rb
# ================================================================
# テスト対象（catalog-section-kind-spec.md）:
#   原稿の種類を catalog.yml の区分で決めたことが、番号を見ていた各所に届いていること
#   - TocDocumentBuilder: 目次の並びと、前書き・後書きの扱い（§4.2）
#   - OutlineExtractor.build_chapter_order: PDF のしおりの並び（§4.2）
#   - Common.appendix_number_to_letter: 付録の記号は付録の中の位置から振る（§4.3）
#   - HeadingProcessor.main_chapter_token?: 章番号を数える並びに前書きを入れない（§4.3）
#   - CatalogUpdater.rename_chapter: 範囲の外の番号で書いた章は区分を動かさない（§4.4）
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/loader'

module VivlioStarter
  module CLI
    class CatalogSectionKindTest < Minitest::Test
      CATALOG = <<~YAML
        PREFACE:
          - 00-preface
          - 20-vol2-intro
        CHAPTERS:
          - 01-intro
          - 21-janken
        APPENDICES:
          - 05-glossary
          - 90-how-to-ask
        POSTFACE:
          - 98-afterword
      YAML

      BASENAMES = %w[00-preface 20-vol2-intro 01-intro 21-janken 05-glossary 90-how-to-ask 98-afterword].freeze

      def test_should_order_toc_by_kind_and_list_supplements_without_numbers
        with_project do
          entry_map = BASENAMES.to_h do |bn|
            path = File.expand_path("html/#{bn}.html")
            File.write(path, %(<html><body><h1 id="h-#{bn}">#{bn}</h1></body></html>))
            [path, TokenResolver::Resolver.new.resolve_file(bn)]
          end

          toc = TocCommands::TocDocumentBuilder.new(entry_map, base_dir: 'html', depth: 1).build
          order = toc.scan(/href="([^"#]+)\.html#/).flatten

          assert_equal %w[00-preface 20-vol2-intro 01-intro 21-janken 05-glossary 90-how-to-ask 98-afterword], order
          assert_includes toc, %(<li class="toc-chapter-no-number toc-preface"><a href="20-vol2-intro.html#h-20-vol2-intro"),
                          'PREFACE に書いた原稿は、前書きとして番号なしで載ること'
          assert_includes toc, %(<li class="toc-chapter-no-number"><a href="98-afterword.html#h-98-afterword"),
                          'POSTFACE に書いた原稿は、後書きとして番号なしで載ること'
        end
      end

      def test_should_put_prefaces_and_postfaces_at_outline_ends
        with_project do
          IndexCommands.stub(:index_enabled?, false) do
            order = Build::OutlineExtractor.build_chapter_order(BASENAMES.shuffle(random: Random.new(1)))

            # APPENDICES に書いた 05-glossary は、本文の章の後ろ（番号の順では本文の章の間に入っていた）
            assert_equal %w[_titlepage _legalpage 00-preface 20-vol2-intro _toc
                            01-intro 21-janken 05-glossary 90-how-to-ask 98-afterword], order
          end
        end
      end

      def test_should_letter_appendices_by_position_even_outside_90_to_98
        with_project do
          assert_equal 'a', Common.appendix_number_to_letter('05')
          assert_equal 'b', Common.appendix_number_to_letter('90')
          assert_equal 'b', Common.appendix_number_to_letter('91'), '目次に無い付録の番号は 90 からの差で決める（vs rename が付録の名前を決めるため）'
        end
      end

      def test_should_not_count_preface_as_main_chapter
        with_project do
          refute PostProcessCommands::HeadingProcessor.main_chapter_token?('20-vol2-intro')
          assert PostProcessCommands::HeadingProcessor.main_chapter_token?('21-janken')
          refute PostProcessCommands::HeadingProcessor.main_chapter_token?('05-glossary')
        end
      end

      def test_should_keep_section_when_renaming_out_of_range_entry
        with_project do
          Build::CatalogUpdater.rename_chapter('20-vol2-intro', '19-vol2-intro')

          catalog = Build::CatalogLoader.load_catalog
          assert_includes catalog['PREFACE'], '19-vol2-intro', '区分を選んで書いた前書きは PREFACE に残ること'
          refute_includes catalog['CHAPTERS'], '19-vol2-intro'
        end
      end

      def test_should_move_section_when_renaming_in_range_entry
        with_project do
          Build::CatalogUpdater.rename_chapter('21-janken', '92-janken')

          catalog = Build::CatalogLoader.load_catalog
          assert_includes catalog['APPENDICES'], '92-janken', '番号どおりに書いていた章は新しい番号の区分へ移ること'
          refute_includes catalog['CHAPTERS'], '92-janken'
        end
      end

      private

      def with_project
        Dir.mktmpdir('vs-section-kind') do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p(%w[config contents html])
            File.write('config/catalog.yml', CATALOG)
            BASENAMES.each { File.write("contents/#{it}.md", "# #{it}\n") }
            Common.stub(:log_info, nil) { yield }
          end
        end
      end
    end
  end
end
