# frozen_string_literal: true

require 'test_helper'
require 'vivlio/starter/cli/index/index_terms_manager'
require 'tmpdir'
require 'fileutils'

module Vivlio
  module Starter
    module CLI
      class IndexTermsManagerTest < Minitest::Test
        # --- phase: setup ---

        def setup
          @original_dir = Dir.pwd
          @temp_dir = Dir.mktmpdir('index_terms_test')
          Dir.chdir(@temp_dir)
          FileUtils.mkdir_p('config')
          @manager = IndexTermsManager.new
        end

        def teardown
          Dir.chdir(@original_dir)
          FileUtils.rm_rf(@temp_dir)
        end

        # --- phase: load_existing_terms tests ---

        def test_load_existing_terms_returns_empty_when_file_missing
          terms = @manager.load_existing_terms

          assert_empty terms
        end

        def test_load_existing_terms_parses_yaml_correctly
          yaml_content = <<~YAML
            terms:
              - term: Ruby
                yomi: るびー
                pattern: "/Ruby/"
              - term: CSS
                yomi: CSS
                pattern: "/CSS/"
          YAML
          File.write('config/index_terms.yml', yaml_content)

          terms = @manager.load_existing_terms

          assert_equal 2, terms.size
          assert_equal 'Ruby', terms[0]['term']
          assert_equal 'CSS', terms[1]['term']
        end

        def test_load_existing_terms_caches_result
          File.write('config/index_terms.yml', "terms:\n  - term: Test\n    yomi: てすと\n")

          first_load = @manager.load_existing_terms
          # ファイルを変更
          File.write('config/index_terms.yml', "terms:\n  - term: Changed\n    yomi: ちぇんじど\n")
          second_load = @manager.load_existing_terms

          # キャッシュされているので同じ結果
          assert_equal first_load, second_load
        end

        # --- phase: merge_terms! tests ---

        def test_merge_terms_adds_new_terms
          new_terms = [
            { 'term' => 'JavaScript', 'yomi' => 'じゃばすくりぷと' },
            { 'term' => 'HTML', 'yomi' => 'HTML' }
          ]

          @manager.merge_terms!(new_terms, source: 'auto_extracted')

          terms = @manager.load_existing_terms
          assert_equal 2, terms.size
          term_names = terms.map { it['term'] }
          assert_includes term_names, 'JavaScript'
          assert_includes term_names, 'HTML'
        end

        def test_merge_terms_skips_duplicates
          File.write('config/index_terms.yml', "terms:\n  - term: Ruby\n    yomi: るびー\n")
          @manager.clear_cache!

          new_terms = [
            { 'term' => 'Ruby', 'yomi' => 'るびー' },
            { 'term' => 'Python', 'yomi' => 'ぱいそん' }
          ]

          @manager.merge_terms!(new_terms, source: 'auto_extracted')

          terms = @manager.load_existing_terms
          # Ruby は重複なので追加されない、Python のみ追加
          ruby_count = terms.count { it['term'] == 'Ruby' }
          assert_equal 1, ruby_count
        end

        def test_merge_terms_sets_source_correctly
          new_terms = [{ 'term' => 'Manual', 'yomi' => 'まにゅある' }]

          @manager.merge_terms!(new_terms, source: 'manual_markup')

          terms = @manager.load_existing_terms
          assert_equal 'manual_markup', terms[0]['source']
        end

        def test_merge_terms_preserves_score_when_present
          new_terms = [{ 'term' => 'Scored', 'yomi' => 'すこあど', 'score' => 150.5 }]

          @manager.merge_terms!(new_terms, source: 'auto_extracted')

          terms = @manager.load_existing_terms
          assert_equal 150.5, terms[0]['score']
        end

        # --- phase: update_yomi! tests ---

        def test_update_yomi_changes_reading
          File.write('config/index_terms.yml', "terms:\n  - term: Ruby\n    yomi: るびー\n")
          @manager.clear_cache!

          yomi_changes = [{ 'term' => 'Ruby', 'yomi' => 'ルビー' }]
          @manager.update_yomi!(yomi_changes)

          terms = @manager.load_existing_terms
          ruby_term = terms.find { it['term'] == 'Ruby' }
          assert_equal 'ルビー', ruby_term['yomi']
        end

        def test_update_yomi_skips_nonexistent_terms
          File.write('config/index_terms.yml', "terms:\n  - term: Ruby\n    yomi: るびー\n")
          @manager.clear_cache!

          yomi_changes = [{ 'term' => 'NonExistent', 'yomi' => 'なし' }]
          @manager.update_yomi!(yomi_changes)

          # エラーなく完了
          terms = @manager.load_existing_terms
          assert_equal 1, terms.size
        end

        # --- phase: term_names tests ---

        def test_term_names_returns_array_of_strings
          File.write('config/index_terms.yml', "terms:\n  - term: A\n    yomi: a\n  - term: B\n    yomi: b\n")
          @manager.clear_cache!

          names = @manager.term_names

          assert_equal %w[A B], names
        end

        # --- phase: save_terms! tests ---

        def test_save_terms_sorts_by_yomi
          terms = [
            { 'term' => 'Z', 'yomi' => 'ぜっと' },
            { 'term' => 'A', 'yomi' => 'あ' },
            { 'term' => 'M', 'yomi' => 'ま' }
          ]

          @manager.save_terms!(terms)

          saved = @manager.load_existing_terms
          yomis = saved.map { it['yomi'] }
          # Unicode順でソートされる
          assert_equal %w[あ ぜっと ま], yomis
        end

        # --- phase: clear_cache! tests ---

        def test_clear_cache_forces_reload
          File.write('config/index_terms.yml', "terms:\n  - term: Original\n    yomi: おりじなる\n")
          @manager.load_existing_terms

          File.write('config/index_terms.yml', "terms:\n  - term: Updated\n    yomi: あっぷでーとど\n")
          @manager.clear_cache!

          terms = @manager.load_existing_terms
          assert_equal 'Updated', terms[0]['term']
        end
      end
    end
  end
end
