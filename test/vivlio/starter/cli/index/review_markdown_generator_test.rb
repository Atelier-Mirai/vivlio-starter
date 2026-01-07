# frozen_string_literal: true

require 'test_helper'
require 'vivlio/starter/cli/index/review_markdown_generator'
require 'tmpdir'
require 'fileutils'

module Vivlio
  module Starter
    module CLI
      class ReviewMarkdownGeneratorTest < Minitest::Test
        # --- phase: setup ---

        def setup
          @original_dir = Dir.pwd
          @temp_dir = Dir.mktmpdir('review_md_test')
          Dir.chdir(@temp_dir)
          FileUtils.mkdir_p('config')
          @generator = ReviewMarkdownGenerator.new
        end

        def teardown
          Dir.chdir(@original_dir)
          FileUtils.rm_rf(@temp_dir)
        end

        # --- phase: generate! tests ---

        def test_generate_creates_review_file
          data = {
            terms: [],
            high_candidates: [],
            low_candidates: [],
            rejected: []
          }

          @generator.generate!(data)

          assert File.exist?('_index_review.md')
        end

        def test_generate_includes_all_sections
          data = {
            terms: [
              { 'term' => 'Ruby', 'yomi' => 'るびー', 'source' => 'manual_markup' }
            ],
            high_candidates: [
              { 'term' => 'JavaScript', 'yomi' => 'じゃばすくりぷと', 'score' => 200.0, 'is_new' => true, 'contexts' => [] }
            ],
            low_candidates: [
              { 'term' => 'Python', 'yomi' => 'ぱいそん', 'score' => 150.0, 'is_new' => true, 'contexts' => [] }
            ],
            rejected: [
              { 'term' => 'Bad', 'yomi' => 'ばっど', 'rejected_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S'), 'contexts' => [] }
            ]
          }

          @generator.generate!(data)

          content = File.read('_index_review.md')
          assert_includes content, '## 1. 登録済み用語の確認'
          assert_includes content, '## 2. 推奨候補'
          assert_includes content, '## 3. 一般候補'
          assert_includes content, '## 4. 除外済みリスト'
        end

        def test_generate_shows_manual_markup_label
          data = {
            terms: [
              { 'term' => 'Manual', 'yomi' => 'まにゅある', 'source' => 'manual_markup', 'contexts' => [] }
            ],
            high_candidates: [],
            low_candidates: [],
            rejected: []
          }

          @generator.generate!(data)

          content = File.read('_index_review.md')
          assert_includes content, '[手動登録]'
        end

        def test_generate_shows_score_for_auto_extracted
          data = {
            terms: [
              { 'term' => 'Auto', 'yomi' => 'おーと', 'source' => 'auto_extracted', 'score' => 150.5, 'contexts' => [] }
            ],
            high_candidates: [],
            low_candidates: [],
            rejected: []
          }

          @generator.generate!(data)

          content = File.read('_index_review.md')
          assert_includes content, 'スコア: 150.5'
        end

        # --- phase: parse_approved tests ---

        def test_parse_approved_extracts_checked_items
          content = <<~MD
            ## 2. 推奨候補 (High Candidates: 2語)

            - [x] `NEW!` **JavaScript** (じゃばすくりぷと) - スコア: 200.0
              - 01-intro - "sample context"

            - [ ] `NEW!` **Python** (ぱいそん) - スコア: 150.0
              - 02-basics - "another context"
          MD
          File.write('_index_review.md', content)

          approved = @generator.parse_approved

          assert_equal 1, approved.size
          assert_equal 'JavaScript', approved[0]['term']
          assert_equal 'じゃばすくりぷと', approved[0]['yomi']
        end

        # --- phase: parse_rejected tests ---

        def test_parse_rejected_extracts_r_marked_items
          content = <<~MD
            ## 2. 推奨候補 (High Candidates: 2語)

            - [r] `NEW!` **BadTerm** (ばっどたーむ) - スコア: 100.0
              - 01-intro - "context"

            - [ ] `NEW!` **GoodTerm** (ぐっどたーむ) - スコア: 150.0
              - 02-basics - "context"

            ## 4. 除外済みリスト (Rejected: 0語)
          MD
          File.write('_index_review.md', content)

          rejected = @generator.parse_rejected

          assert_equal 1, rejected.size
          assert_equal 'BadTerm', rejected[0]['term']
        end

        def test_parse_rejected_ignores_rejected_section
          content = <<~MD
            ## 2. 推奨候補 (High Candidates: 1語)

            - [r] `NEW!` **FromCandidates** (ふろむきゃんでぃでーつ) - スコア: 100.0

            ## 4. 除外済みリスト (Rejected: 1語)

            - [r] `Today` **AlreadyRejected** (おるれでぃりじぇくてっど)
          MD
          File.write('_index_review.md', content)

          rejected = @generator.parse_rejected

          assert_equal 1, rejected.size
          assert_equal 'FromCandidates', rejected[0]['term']
        end

        # --- phase: parse_unreject tests ---

        def test_parse_unreject_extracts_from_rejected_section
          content = <<~MD
            ## 2. 推奨候補 (High Candidates: 0語)

            ## 4. 除外済みリスト (Rejected: 2語)

            - [r] `Today` **ToUnreject** (とぅあんりじぇくと) - スコア: 50.0
              - 01-intro - "context"

            - [ ] `Today` **StayRejected** (すていりじぇくてっど)
          MD
          File.write('_index_review.md', content)

          unreject = @generator.parse_unreject

          assert_equal 1, unreject.size
          assert_equal 'ToUnreject', unreject[0]['term']
        end

        # --- phase: parse_yomi_changes tests ---

        def test_parse_yomi_changes_extracts_from_terms_section
          content = <<~MD
            ## 1. 登録済み用語の確認 (Terms: 1語)

            - [x] **Ruby** (るびー・かいてい)
              - 01-intro - "context"

            ## 2. 推奨候補 (High Candidates: 0語)
          MD
          File.write('_index_review.md', content)

          changes = @generator.parse_yomi_changes

          assert_equal 1, changes.size
          assert_equal 'Ruby', changes[0]['term']
          assert_equal 'るびー・かいてい', changes[0]['yomi']
        end

        # --- phase: exists? and cleanup! tests ---

        def test_exists_returns_false_when_file_missing
          refute @generator.exists?
        end

        def test_exists_returns_true_when_file_present
          File.write('_index_review.md', 'test')

          assert @generator.exists?
        end

        def test_cleanup_removes_file
          File.write('_index_review.md', 'test')

          @generator.cleanup!

          refute File.exist?('_index_review.md')
        end
      end
    end
  end
end
