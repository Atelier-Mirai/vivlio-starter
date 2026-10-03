# frozen_string_literal: true

# ================================================================
# Test: index/index_library_test.rb
# ================================================================
# テスト対象:
#   IndexCommands::IndexLibrary（用語集の説明文・棄却した語・読みの export/import）
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

        # 使っていない語（説明文だけを残した語）も運ぶ。説明文の無い語は運ばない
        # （index-library-reserve-spec.md §3.2）
        def test_export_includes_unused_terms_and_skips_terms_without_definition
          write_terms([
                        { 'term' => '版面', 'yomi' => 'はんづら', 'flags' => '', 'definition' => '文字を組む範囲。' },
                        { 'term' => '扉絵', 'yomi' => 'とびらえ', 'flags' => 'g', 'definition' => '' }
                      ])

          IndexLibrary.new.export!('lib.yml')

          assert_equal [{ 'term' => '版面', 'yomi' => 'はんづら', 'definition' => '文字を組む範囲。' }],
                       YAML.load_file('lib.yml')['glossary']
        end

        def test_export_returns_false_when_nothing_to_export
          refute IndexLibrary.new.export!('lib.yml')
          refute_path_exists 'lib.yml'
        end

        def test_export_includes_yomi_from_author_touched_terms
          write_terms([
                        { 'term' => '碍子', 'yomi' => 'がいし', 'flags' => 'g', 'definition' => '絶縁体。' },
                        { 'term' => 'PDF', 'yomi' => 'ぴーでぃーえふ', 'flags' => 'i', 'definition' => '',
                          'source' => 'auto_extracted' }
                      ])

          IndexLibrary.new.export!('lib.yml')
          yomi = YAML.load_file('lib.yml')['yomi']

          # 用語集[g]の碍子は読みを持ち運ぶ。索引専用[i]の PDF は含まない。
          assert_equal({ '碍子' => 'がいし' }, yomi)
        end

        # --- import ---

        def test_import_merges_glossary_and_reject_additively
          write_library('lib.yml',
                        glossary: [{ 'term' => 'EPUB', 'yomi' => 'いーぱぶ', 'definition' => '電子書籍。' }],
                        reject: [{ 'term' => '実装' }])

          result = IndexLibrary.new.import!('lib.yml')

          assert_equal 1, result.glossary_added
          assert_equal 1, result.reject_added
          # 用語集の語は、使っていない語として待つ。用語集のページ（glossary_terms）には載らない
          epub = load_terms.find { it['term'] == 'EPUB' }
          assert_equal ['', '電子書籍。', 'imported'], epub.values_at('flags', 'definition', 'source')
          assert_empty UnifiedTermsManager.new.glossary_terms
          # 棄却した語には出どころを残す（レビューファイルの 5 節に並べない目印）
          assert_equal 'imported', load_rejected_entries.find { it['term'] == '実装' }['source']
        end

        # 取り込みは追記だけ。辞書にある語の説明文・印は変えない
        def test_import_keeps_the_local_term
          write_terms([{ 'term' => 'EPUB', 'yomi' => 'いーぱぶ', 'flags' => 'i', 'definition' => 'ローカル定義' }])
          write_library('lib.yml',
                        glossary: [{ 'term' => 'EPUB', 'yomi' => 'いー', 'definition' => 'ライブラリ定義' }], reject: [])

          result = IndexLibrary.new.import!('lib.yml')

          assert_equal 1, result.glossary_skipped
          assert_equal %w[i ローカル定義 いーぱぶ], load_terms.first.values_at('flags', 'definition', 'yomi')
        end

        # この本で棄却した語は、ライブラリに説明文があっても取り込まない（この本の判断を優先）。
        # 説明文の無い語も取り込まない
        def test_import_skips_terms_rejected_here_and_terms_without_definition
          write_rejected([{ 'term' => '実装', 'yomi' => 'じっそう' }])
          write_library('lib.yml',
                        glossary: [{ 'term' => '実装', 'yomi' => 'じっそう', 'definition' => '作ること。' },
                                   { 'term' => '扉絵', 'yomi' => 'とびらえ', 'definition' => '' }],
                        reject: [])

          result = IndexLibrary.new.import!('lib.yml')

          assert_equal [0, 2], [result.glossary_added, result.glossary_skipped]
          assert_empty load_terms
          assert_includes load_rejected, '実装'
        end

        # 棄却の理由はライブラリから引き継ぐ
        def test_import_keeps_the_reject_reason
          write_library('lib.yml', glossary: [], reject: [{ 'term' => '実装', 'reason' => '汎用語' }])

          IndexLibrary.new.import!('lib.yml')

          assert_equal '汎用語', load_rejected_entries.first['reason']
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

        def test_import_merges_yomi_into_overrides
          write_library('lib.yml', glossary: [], reject: [], yomi: { '重力' => 'じゅうりょく' })

          result = IndexLibrary.new.import!('lib.yml')

          assert_equal 1, result.yomi_added
          overrides = YAML.load_file('config/index_yomi_overrides.yml')['yomi']
          assert_equal 'じゅうりょく', overrides['重力']
        end

        # --- resolve_path ---

        def test_resolve_path_prefers_explicit_arg
          assert_equal File.expand_path('given.yml'), IndexLibrary.resolve_path('given.yml')
        end

        def test_resolve_path_returns_absolute_yaml_path_for_default
          path = IndexLibrary.resolve_path(nil)

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

        def write_library(path, glossary:, reject:, yomi: {})
          File.write(path,
                     { 'version' => 1, 'glossary' => glossary, 'reject' => reject, 'yomi' => yomi }.to_yaml)
        end

        def load_terms
          path = 'config/index_glossary_terms.yml'
          File.exist?(path) ? YAML.load_file(path)['terms'] : []
        end

        def load_rejected_entries = YAML.load_file('config/index_glossary_rejected.yml')['rejected_terms']

        def load_rejected = load_rejected_entries.map { it['term'] }
      end
    end
  end
end
