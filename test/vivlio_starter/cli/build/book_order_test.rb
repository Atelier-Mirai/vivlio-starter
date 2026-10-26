# frozen_string_literal: true

# ================================================================
# Test: build/book_order_test.rb
# ================================================================
# テスト対象（catalog-written-order-spec.md）:
#   本を catalog.yml に書いた順に組むこと。区分の中を番号の順に並べ直さない
#   - CatalogLoader.book_order・in_book_order: 本の並び（R1）と、目次に無い原稿の置き場（R4）
#   - ChapterConfig.htmls_for_kind・TocDocumentBuilder・OutlineExtractor.build_chapter_order:
#     紙面・目次・しおりの並び（R3）
#   - CrossReferenceProcessor.chapter_number_text_for・Common.appendix_number_to_letter: 章番号・付録の記号（R3）
#   - HeadingProcessor.main_chapter_order: 選んで組む章も、指定の順でなく本の並びで数える（R5）
#   - PartTitleGenerator.insert_part_titles_into: 部扉は、部に書いた最初の章の前（R3）
#   - 分冊: 本全体の前書き → 巻の前書き、合本の章は巻の順（R2）
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/loader'

module VivlioStarter
  module CLI
    module Build
      class BookOrderTest < Minitest::Test
        CATALOG = <<~YAML
          PREFACE:
            - 00-preface
          CHAPTERS:
            - 13-c
            - 11-a
            - 12-b
          APPENDICES:
            - 92-y
            - 91-x
          POSTFACE:
            - 99-postface
        YAML

        BASENAMES = %w[00-preface 13-c 11-a 12-b 92-y 91-x 99-postface].freeze

        def teardown
          Volumes.select!(nil)
          PostProcessCommands::HeadingProcessor.chapter_tokens_override = nil
        end

        def test_should_build_in_written_order_rather_than_number_order
          with_project do
            names = ->(kind) { ChapterConfig.htmls_for_kind('html', kind).map { File.basename(it, '.html') } }
            assert_equal %w[13-c 11-a 12-b], names.(:chapter), '紙面の本文の章は書いた順'
            assert_equal %w[92-y 91-x], names.(:appendix), '付録も書いた順'

            number = ->(basename) { PreProcessCommands::CrossReferenceProcessor.chapter_number_text_for(basename) }
            assert_equal %w[第1章 第2章 第3章], [number.('13-c'), number.('11-a'), number.('12-b')],
                         '章番号（@chapref・図表番号の頭）も書いた順に数える'
            assert_equal %w[a b], [Common.appendix_number_to_letter(92), Common.appendix_number_to_letter(91)],
                         '付録の記号も書いた順に振る'
          end
        end

        def test_should_list_toc_and_outline_in_written_order
          with_project do
            entry_map = BASENAMES.to_h do |bn|
              path = File.expand_path("html/#{bn}.html")
              File.write(path, %(<html><body><h1 id="h-#{bn}">#{bn}</h1></body></html>))
              [path, TokenResolver::Resolver.new.resolve_file(bn)]
            end
            toc = TocCommands::TocDocumentBuilder.new(entry_map, base_dir: 'html', depth: 1).build
            assert_equal BASENAMES, toc.scan(/href="([^"#]+)\.html#/).flatten, '目次'

            IndexCommands.stub(:index_enabled?, false) do
              order = OutlineExtractor.build_chapter_order(BASENAMES.shuffle(random: Random.new(1)))
              assert_equal BASENAMES, order.reject { it.start_with?('_') }, 'しおり'
            end
          end
        end

        # 選んで組む章は、選んだ章の中で数える。並びは指定の順でなく本の並び
        def test_should_number_chosen_chapters_in_written_order
          with_project do
            PostProcessCommands::HeadingProcessor.chapter_tokens_override = %w[12-b 13-c]

            assert_equal %w[13-c 12-b], PostProcessCommands::HeadingProcessor.main_chapter_order
          end
        end

        # 目次に無い原稿は、その種類の最後に番号の順で置く。ふつうは組まないが、黙って落とさない
        def test_should_put_html_missing_from_catalog_last_in_its_kind
          with_project do
            File.write('html/05-draft.html', '')
            File.write('html/04-memo.html', '')

            assert_equal %w[13-c 11-a 12-b 04-memo 05-draft],
                         ChapterConfig.htmls_for_kind('html', :chapter).map { File.basename(it, '.html') }
          end
        end

        # 部扉は、部に書いた最初の章の前に入る。部の中で一番小さい番号の章とは限らない
        def test_should_insert_part_title_before_first_chapter_written_in_part
          catalog = <<~YAML
            CHAPTERS:
              - 応用編:
                  - 13-c
                  - 11-a
              - 発展編:
                  - 12-b
          YAML
          with_project(catalog:, basenames: %w[13-c 11-a 12-b]) do
            %w[_part1 _part2].each { File.write("html/#{it}.html", '') }

            htmls = PartTitleGenerator.insert_part_titles_into(ChapterConfig.htmls_for_kind('html', :chapter), 'html')
            assert_equal %w[_part1 13-c 11-a _part2 12-b], htmls.map { File.basename(it, '.html') }
          end
        end

        VOLUME_CATALOG = <<~YAML
          PREFACE:
            - 50-preface
          VOLUMES:
            - name: 上巻
              id: upper
              PREFACE:
                - 01-volume-1
              CHAPTERS:
                - 11-a
                - 12-b
                - 26-z
            - name: 下巻
              id: lower
              CHAPTERS:
                - 21-c
                - 22-d
        YAML

        # 本全体の前書きを先に、巻の前書きをその後に組む。番号の順では 01-volume-1 が先になっていた
        def test_should_put_book_preface_before_volume_preface
          with_project(catalog: VOLUME_CATALOG, basenames: %w[50-preface 01-volume-1 11-a 12-b 26-z]) do
            Volumes.select!(Volumes.find('upper'))

            assert_equal %w[50-preface 01-volume-1],
                         ChapterConfig.htmls_for_kind('html', :preface).map { File.basename(it, '.html') }
          end
        end

        # 合本の本文の章は巻の順。後から上巻に足した 26-z は、下巻の章の前に載り、第3章になる
        def test_should_keep_volume_order_in_combined_edition
          with_project(catalog: VOLUME_CATALOG, basenames: %w[50-preface 11-a 12-b 26-z 21-c 22-d]) do
            Volumes.select!(:combined)

            assert_equal %w[11-a 12-b 26-z 21-c 22-d],
                         ChapterConfig.htmls_for_kind('html', :chapter).map { File.basename(it, '.html') }
            number = ->(basename) { PreProcessCommands::CrossReferenceProcessor.chapter_number_text_for(basename) }
            assert_equal %w[第3章 第4章], [number.('26-z'), number.('21-c')]
          end
        end

        private

        # basenames の原稿と、組み上がった中間 HTML（html/）を置いた一時プロジェクトで動かす
        def with_project(catalog: CATALOG, basenames: BASENAMES)
          Dir.mktmpdir('vs-book-order') do |dir|
            Dir.chdir(dir) do
              FileUtils.mkdir_p(%w[config contents html])
              File.write('config/catalog.yml', catalog)
              basenames.each do
                File.write("contents/#{it}.md", "# #{it}\n")
                File.write("html/#{it}.html", '')
              end
              Common.stub(:log_info, nil) { yield }
            end
          end
        end
      end
    end
  end
end
