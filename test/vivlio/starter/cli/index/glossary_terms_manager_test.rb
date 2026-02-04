# frozen_string_literal: true

# ================================================================
# Test: glossary_terms_manager_test.rb
# ----------------------------------------------------------------
# テスト対象:
#   GlossaryTermsManager（lib/vivlio/starter/cli/index/glossary_terms_manager.rb）
#
# 検証内容:
#   - 用語集データの読み書き
#   - 用語のマージと更新
#   - 説明文の更新
#   - backlink_sources の更新
# ================================================================

require 'test_helper'
require 'vivlio/starter/cli/index/glossary_terms_manager'
require 'tmpdir'
require 'fileutils'

module Vivlio
  module Starter
    module CLI
      class GlossaryTermsManagerTest < Minitest::Test
        # --- phase: setup ---

        def setup
          @original_dir = Dir.pwd
          @temp_dir = Dir.mktmpdir('glossary_terms_test')
          Dir.chdir(@temp_dir)
          FileUtils.mkdir_p('config')
          @manager = GlossaryTermsManager.new
        end

        def teardown
          Dir.chdir(@original_dir)
          FileUtils.rm_rf(@temp_dir)
        end

        # --- phase: load_existing_terms tests ---

        def test_load_existing_terms_returns_empty_array_when_no_file
          result = @manager.load_existing_terms

          assert_equal [], result
        end

        def test_load_existing_terms_returns_terms_from_yaml
          data = {
            'generated_at' => '2025-01-01 00:00:00',
            'terms' => [
              { 'term' => 'Ruby', 'yomi' => 'るびー', 'definition' => 'プログラミング言語' }
            ]
          }
          File.write('config/glossary_terms.yml', data.to_yaml)

          result = @manager.load_existing_terms

          assert_equal 1, result.size
          assert_equal 'Ruby', result[0]['term']
        end

        # --- phase: merge_terms! tests ---

        def test_merge_terms_creates_file_if_not_exists
          terms = [{ 'term' => 'JavaScript', 'yomi' => 'じゃばすくりぷと', 'definition' => 'Web言語' }]

          @manager.merge_terms!(terms, source: 'review')

          assert File.exist?('config/glossary_terms.yml')
          content = File.read('config/glossary_terms.yml')
          assert_includes content, 'JavaScript'
        end

        def test_merge_terms_adds_new_terms
          existing = {
            'terms' => [{ 'term' => 'Ruby', 'yomi' => 'るびー', 'definition' => 'プログラミング言語' }]
          }
          File.write('config/glossary_terms.yml', existing.to_yaml)
          @manager.clear_cache!

          new_terms = [{ 'term' => 'Python', 'yomi' => 'ぱいそん', 'definition' => 'AI言語' }]
          @manager.merge_terms!(new_terms, source: 'review')

          result = @manager.load_existing_terms
          assert_equal 2, result.size
        end

        def test_merge_terms_updates_existing_term_definition
          existing = {
            'terms' => [{ 'term' => 'Ruby', 'yomi' => 'るびー', 'definition' => '古い説明' }]
          }
          File.write('config/glossary_terms.yml', existing.to_yaml)
          @manager.clear_cache!

          new_terms = [{ 'term' => 'Ruby', 'yomi' => 'るびー', 'definition' => '新しい説明' }]
          @manager.merge_terms!(new_terms, source: 'review')

          result = @manager.load_existing_terms
          assert_equal 1, result.size
          assert_equal '新しい説明', result[0]['definition']
        end

        # --- phase: term_names tests ---

        def test_term_names_returns_list_of_term_names
          data = {
            'terms' => [
              { 'term' => 'Ruby', 'yomi' => 'るびー' },
              { 'term' => 'Python', 'yomi' => 'ぱいそん' }
            ]
          }
          File.write('config/glossary_terms.yml', data.to_yaml)
          @manager.clear_cache!

          result = @manager.term_names

          assert_includes result, 'Ruby'
          assert_includes result, 'Python'
        end

        # --- phase: update_definition! tests ---

        def test_update_definition_updates_term
          data = {
            'terms' => [{ 'term' => 'Ruby', 'yomi' => 'るびー', 'definition' => '古い説明' }]
          }
          File.write('config/glossary_terms.yml', data.to_yaml)
          @manager.clear_cache!

          result = @manager.update_definition!('Ruby', '更新された説明')

          assert result
          terms = @manager.load_existing_terms
          assert_equal '更新された説明', terms[0]['definition']
        end

        def test_update_definition_returns_false_for_nonexistent_term
          data = { 'terms' => [] }
          File.write('config/glossary_terms.yml', data.to_yaml)
          @manager.clear_cache!

          result = @manager.update_definition!('NonExistent', '説明')

          refute result
        end

        # --- phase: remove_term! tests ---

        def test_remove_term_deletes_term
          data = {
            'terms' => [
              { 'term' => 'Ruby', 'yomi' => 'るびー' },
              { 'term' => 'Python', 'yomi' => 'ぱいそん' }
            ]
          }
          File.write('config/glossary_terms.yml', data.to_yaml)
          @manager.clear_cache!

          @manager.remove_term!('Ruby')

          result = @manager.load_existing_terms
          assert_equal 1, result.size
          assert_equal 'Python', result[0]['term']
        end

        # --- phase: update_backlink_sources! tests ---

        def test_update_backlink_sources_adds_sources
          data = {
            'terms' => [{ 'term' => 'Ruby', 'yomi' => 'るびー', 'definition' => '言語' }]
          }
          File.write('config/glossary_terms.yml', data.to_yaml)
          @manager.clear_cache!

          sources = [
            { 'chapter' => '01-intro', 'occurrence' => 1 },
            { 'chapter' => '02-basics', 'occurrence' => 1 }
          ]
          result = @manager.update_backlink_sources!('Ruby', sources)

          assert result
          terms = @manager.load_existing_terms
          assert_equal 2, terms[0]['backlink_sources'].size
        end
      end
    end
  end
end
