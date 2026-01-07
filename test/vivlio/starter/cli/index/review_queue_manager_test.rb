# frozen_string_literal: true

require 'test_helper'
require 'vivlio/starter/cli/index/review_queue_manager'
require 'tmpdir'
require 'fileutils'

module Vivlio
  module Starter
    module CLI
      class ReviewQueueManagerTest < Minitest::Test
        # --- phase: setup ---

        def setup
          @original_dir = Dir.pwd
          @temp_dir = Dir.mktmpdir('review_queue_test')
          Dir.chdir(@temp_dir)
          FileUtils.mkdir_p('config')
          @manager = ReviewQueueManager.new
        end

        def teardown
          Dir.chdir(@original_dir)
          FileUtils.rm_rf(@temp_dir)
        end

        # --- phase: queue management tests ---

        def test_save_and_load_queue
          candidates = [
            { 'term' => 'Ruby', 'yomi' => 'るびー', 'score' => 100.0 },
            { 'term' => 'Python', 'yomi' => 'ぱいそん', 'score' => 80.0 }
          ]

          @manager.save_queue(candidates)
          @manager.clear_cache!
          loaded = @manager.load_queue

          assert_equal 2, loaded.size
          assert_equal 'Ruby', loaded[0]['term']
        end

        def test_load_queue_returns_empty_when_file_missing
          queue = @manager.load_queue

          assert_empty queue
        end

        def test_clear_terms_removes_specified_terms
          candidates = [
            { 'term' => 'Keep', 'yomi' => 'きーぷ' },
            { 'term' => 'Remove', 'yomi' => 'りむーぶ' },
            { 'term' => 'AlsoKeep', 'yomi' => 'おるそきーぷ' }
          ]
          @manager.save_queue(candidates)

          @manager.clear_terms(['Remove'])

          queue = @manager.load_queue
          term_names = queue.map { it['term'] }
          assert_includes term_names, 'Keep'
          assert_includes term_names, 'AlsoKeep'
          refute_includes term_names, 'Remove'
        end

        # --- phase: rejected terms tests ---

        def test_save_and_load_rejected_terms
          rejected = [
            { 'term' => 'Bad', 'yomi' => 'ばっど', 'score' => 50.0 }
          ]

          @manager.save_rejected_terms(rejected)
          @manager.clear_cache!
          loaded = @manager.load_rejected_terms

          assert_includes loaded, 'Bad'
        end

        def test_save_rejected_terms_preserves_score_and_contexts
          rejected = [
            {
              'term' => 'WithMeta',
              'yomi' => 'うぃずめた',
              'score' => 75.5,
              'contexts' => [{ 'chapter' => '01', 'context' => 'sample text' }]
            }
          ]

          @manager.save_rejected_terms(rejected)
          @manager.clear_cache!
          loaded = @manager.load_rejected_terms_with_metadata

          assert_equal 1, loaded.size
          assert_equal 75.5, loaded[0]['score']
          assert_equal 1, loaded[0]['contexts'].size
        end

        def test_save_rejected_terms_skips_duplicates
          @manager.save_rejected_terms([{ 'term' => 'Dup', 'yomi' => 'だぷ' }])
          @manager.clear_cache!
          @manager.save_rejected_terms([{ 'term' => 'Dup', 'yomi' => 'だぷ' }])

          loaded = @manager.load_rejected_terms
          assert_equal 1, loaded.count { it == 'Dup' }
        end

        # --- phase: unreject tests ---

        def test_unreject_term_by_name_removes_from_list
          @manager.save_rejected_terms([
            { 'term' => 'ToRemove', 'yomi' => 'とぅりむーぶ' },
            { 'term' => 'ToKeep', 'yomi' => 'とぅきーぷ' }
          ])
          @manager.clear_cache!

          result = @manager.unreject_term_by_name!('ToRemove')

          assert result
          loaded = @manager.load_rejected_terms
          refute_includes loaded, 'ToRemove'
          assert_includes loaded, 'ToKeep'
        end

        def test_unreject_term_by_name_returns_false_for_unknown
          @manager.save_rejected_terms([{ 'term' => 'Known', 'yomi' => 'のうん' }])
          @manager.clear_cache!

          result = @manager.unreject_term_by_name!('Unknown')

          refute result
        end

        # --- phase: reset tests ---

        def test_reset_rejected_deletes_file
          @manager.save_rejected_terms([{ 'term' => 'Test', 'yomi' => 'てすと' }])

          @manager.reset_rejected!

          refute File.exist?('config/index_rejected.yml')
        end

        # --- phase: rejected_count tests ---

        def test_rejected_count_returns_number_of_terms
          @manager.save_rejected_terms([
            { 'term' => 'A', 'yomi' => 'a' },
            { 'term' => 'B', 'yomi' => 'b' },
            { 'term' => 'C', 'yomi' => 'c' }
          ])
          @manager.clear_cache!

          assert_equal 3, @manager.rejected_count
        end
      end
    end
  end
end
