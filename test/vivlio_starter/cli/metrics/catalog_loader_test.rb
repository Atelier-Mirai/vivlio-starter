# frozen_string_literal: true

require 'test_helper'
require 'vivlio_starter/cli/metrics/catalog_loader'

module VivlioStarter
  module CLI
    module Metrics
      class CatalogLoaderTest < Minitest::Test
        def setup
          @tmp_dir = Dir.mktmpdir
          @catalog_path = File.join(@tmp_dir, 'catalog.yml')
        end

        def teardown
          FileUtils.rm_rf(@tmp_dir)
        end

        def test_enabled_chapters_returns_empty_when_file_not_exists
          loader = CatalogLoader.new('/nonexistent/path.yml')

          assert_empty loader.enabled_chapters
        end

        def test_enabled_chapters_extracts_flat_list
          File.write(@catalog_path, <<~YAML)
            PREFACE:
              - 00-preface
            CHAPTERS:
              - 01-intro
              - 02-basics
            APPENDICES:
              - 91-appendix
            POSTFACE:
              - 99-postface
          YAML

          loader = CatalogLoader.new(@catalog_path)
          chapters = loader.enabled_chapters

          assert_includes chapters, '00-preface'
          assert_includes chapters, '01-intro'
          assert_includes chapters, '02-basics'
          assert_includes chapters, '91-appendix'
          assert_includes chapters, '99-postface'
        end

        def test_enabled_chapters_flattens_nested_parts
          File.write(@catalog_path, <<~YAML)
            CHAPTERS:
              - 第一部:
                  - 01-intro
                  - 02-basics
              - 第二部:
                  - 03-advanced
          YAML

          loader = CatalogLoader.new(@catalog_path)
          chapters = loader.enabled_chapters

          assert_includes chapters, '01-intro'
          assert_includes chapters, '02-basics'
          assert_includes chapters, '03-advanced'
          refute_includes chapters, '第一部'
          refute_includes chapters, '第二部'
        end

        def test_enabled_chapters_removes_md_extension
          File.write(@catalog_path, <<~YAML)
            CHAPTERS:
              - 01-intro.md
              - 02-basics
          YAML

          loader = CatalogLoader.new(@catalog_path)
          chapters = loader.enabled_chapters

          assert_includes chapters, '01-intro'
          assert_includes chapters, '02-basics'
          refute_includes chapters, '01-intro.md'
        end

        def test_enabled_chapters_returns_unique_entries
          File.write(@catalog_path, <<~YAML)
            PREFACE:
              - 00-preface
            CHAPTERS:
              - 00-preface
              - 01-intro
          YAML

          loader = CatalogLoader.new(@catalog_path)
          chapters = loader.enabled_chapters

          assert_equal 1, chapters.count('00-preface')
        end

        def test_catalog_exists_returns_true_when_file_exists
          File.write(@catalog_path, 'CHAPTERS: []')

          loader = CatalogLoader.new(@catalog_path)

          assert loader.catalog_exists?
        end

        def test_catalog_exists_returns_false_when_file_missing
          loader = CatalogLoader.new('/nonexistent/path.yml')

          refute loader.catalog_exists?
        end
      end
    end
  end
end
