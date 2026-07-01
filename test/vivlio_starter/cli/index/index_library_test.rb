# frozen_string_literal: true

# ================================================================
# Test: index/index_library_test.rb
# ================================================================
# テスト対象:
#   IndexCommands::IndexLibrary（用語集[g]・reject の export/import）
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/index/index_library'
require 'tmpdir'
require 'fileutils'
require 'yaml'

module VivlioStarter
  module CLI
    module IndexCommands
      class IndexLibraryTest < Minitest::Test
        def setup
          @original_dir = Dir.pwd
          @temp_dir = Dir.mktmpdir('index_library_test')
          Dir.chdir(@temp_dir)
          FileUtils.mkdir_p('config')
        end

        def teardown
          Dir.chdir(@original_dir)
          FileUtils.rm_rf(@temp_dir)
        end

        # --- export ---

        def test_export_extracts_only_glossary_and_reject_dropping_book_specifics
          write_terms([
                        { 'term' => 'EPUB', 'yomi' => 'いーぱぶ', 'flags' => 'ig', 'definition' => '電子書籍の標準規格。',
                          'source' => 'review', 'contexts' => [{ 'chapter' => '10', 'context' => 'x' }] },
                        { 'term' => 'PDF', 'yomi' => 'ぴーでぃーえふ', 'flags' => 'i', 'definition' => '', 'source' => 'auto_extracted' }
                      ])
          write_rejected([{ 'term' => '実装', 'yomi' => 'じっそう' }])

          assert IndexLibrary.new.export!('lib.yml')
          data = YAML.load_file('lib.yml')

          assert_equal 1, data['version']
          # [g] を含む EPUB のみ。索引専用の PDF は含まない。
          assert_equal [{ 'term' => 'EPUB', 'yomi' => 'いーぱぶ', 'definition' => '電子書籍の標準規格。' }], data['glossary']
          assert_equal [{ 'term' => '実装' }], data['reject']
          # 書籍固有情報は落とす
          refute_includes data['glossary'].first.keys, 'contexts'
          refute_includes data['glossary'].first.keys, 'source'
        end

        def test_export_returns_false_when_nothing_to_export
          refute IndexLibrary.new.export!('lib.yml')
          refute_path_exists 'lib.yml'
        end

        # --- import ---

        def test_import_merges_glossary_and_reject_additively
          write_library('lib.yml',
                        glossary: [{ 'term' => 'EPUB', 'yomi' => 'いーぱぶ', 'definition' => '電子書籍。' }],
                        reject: [{ 'term' => '実装' }])

          result = IndexLibrary.new.import!('lib.yml')

          assert_equal 1, result.glossary_added
          assert_equal 1, result.reject_added
          epub = load_terms.find { it['term'] == 'EPUB' }
          assert_includes epub['flags'], 'g'
          assert_equal '電子書籍。', epub['definition']
          assert_includes load_rejected, '実装'
        end

        def test_import_keeps_local_by_default_but_prefer_import_overwrites
          write_terms([{ 'term' => 'EPUB', 'yomi' => 'いーぱぶ', 'flags' => 'g', 'definition' => 'ローカル定義' }])
          write_library('lib.yml',
                        glossary: [{ 'term' => 'EPUB', 'yomi' => 'いー', 'definition' => 'ライブラリ定義' }], reject: [])

          IndexLibrary.new.import!('lib.yml')
          assert_equal 'ローカル定義', load_terms.find { it['term'] == 'EPUB' }['definition']

          IndexLibrary.new.import!('lib.yml', prefer_import: true)
          assert_equal 'ライブラリ定義', load_terms.find { it['term'] == 'EPUB' }['definition']
        end

        def test_import_skips_reject_for_adopted_terms
          write_terms([{ 'term' => 'EPUB', 'yomi' => 'い', 'flags' => 'g', 'definition' => 'd' }])
          write_library('lib.yml', glossary: [], reject: [{ 'term' => 'EPUB' }, { 'term' => '実装' }])

          result = IndexLibrary.new.import!('lib.yml')

          assert_equal 1, result.reject_added   # 実装 のみ
          assert_equal 1, result.reject_skipped # EPUB は採用済みなので reject しない
          refute_includes load_rejected, 'EPUB'
        end

        def test_import_returns_nil_when_file_missing
          assert_nil IndexLibrary.new.import!('missing.yml')
        end

        # --- resolve_path ---

        def test_resolve_path_prefers_explicit_arg
          assert_equal File.expand_path('given.yml'), IndexLibrary.resolve_path('given.yml', :export)
        end

        def test_resolve_path_returns_absolute_yaml_path_for_default
          path = IndexLibrary.resolve_path(nil, :import)

          assert path.start_with?('/'), "絶対パスであること: #{path}"
          assert path.end_with?('.yml')
        end

        private

        def write_terms(terms)
          File.write('config/index_glossary_terms.yml',
                     { 'generated_at' => '2026-07-01 00:00:00', 'terms' => terms }.to_yaml)
        end

        def write_rejected(rejected)
          File.write('config/index_glossary_rejected.yml',
                     { 'rejected_at' => '2026-07-01 00:00:00', 'rejected_terms' => rejected }.to_yaml)
        end

        def write_library(path, glossary:, reject:)
          File.write(path, { 'version' => 1, 'glossary' => glossary, 'reject' => reject }.to_yaml)
        end

        def load_terms = YAML.load_file('config/index_glossary_terms.yml')['terms']

        def load_rejected = YAML.load_file('config/index_glossary_rejected.yml')['rejected_terms'].map { it['term'] }
      end
    end
  end
end
