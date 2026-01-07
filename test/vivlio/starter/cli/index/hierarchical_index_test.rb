# frozen_string_literal: true

require 'test_helper'
require 'vivlio/starter/cli/index/hierarchical_index'

module Vivlio
  module Starter
    module CLI
      module IndexCommands
        class HierarchicalIndexTest < Minitest::Test
          # --- phase: setup ---

          def setup
            @index = HierarchicalIndex.new
          end

          # --- phase: add_entry tests ---

          def test_add_entry_stores_term_and_link
            @index.add_entry('Ruby', '01-basics.html#idx-ruby-1')

            assert_includes @index.entries.keys, 'Ruby'
            assert_includes @index.entries['Ruby'], '01-basics.html#idx-ruby-1'
          end

          def test_add_entry_with_parent_creates_hierarchy
            @index.add_entry('HTMLタグ', '02-html.html#idx-htmltag-1', parent: 'HTML')

            assert_includes @index.hierarchy['HTML'].to_a, 'HTMLタグ'
          end

          def test_add_entry_accumulates_multiple_links
            @index.add_entry('CSS', '01-intro.html#idx-css-1')
            @index.add_entry('CSS', '02-style.html#idx-css-2')
            @index.add_entry('CSS', '03-layout.html#idx-css-3')

            assert_equal 3, @index.entries['CSS'].size
          end

          # --- phase: deduplicate_same_page tests ---

          def test_deduplicate_same_page_keeps_first_occurrence
            @index.add_entry('JavaScript', '05-js.html#idx-js-1')
            @index.add_entry('JavaScript', '05-js.html#idx-js-2')
            @index.add_entry('JavaScript', '05-js.html#idx-js-3')
            @index.add_entry('JavaScript', '06-advanced.html#idx-js-4')

            @index.deduplicate_same_page!

            links = @index.entries['JavaScript']
            assert_equal 2, links.size
            assert_includes links, '05-js.html#idx-js-1'
            assert_includes links, '06-advanced.html#idx-js-4'
          end

          # --- phase: calculate_page_ranges tests ---

          def test_calculate_page_ranges_with_consecutive_pages
            ranges = @index.calculate_page_ranges([1, 2, 3, 5, 7, 8, 9, 10])

            assert_equal ['1-3', '5', '7-10'], ranges
          end

          def test_calculate_page_ranges_with_single_pages
            ranges = @index.calculate_page_ranges([1, 5, 10])

            assert_equal %w[1 5 10], ranges
          end

          def test_calculate_page_ranges_with_empty_array
            ranges = @index.calculate_page_ranges([])

            assert_empty ranges
          end

          def test_calculate_page_ranges_removes_duplicates
            ranges = @index.calculate_page_ranges([1, 1, 2, 2, 3])

            assert_equal ['1-3'], ranges
          end

          # --- phase: hierarchy methods tests ---

          def test_get_hierarchy_returns_hash_with_arrays
            @index.add_entry('HTML要素', '01.html#1', parent: 'HTML')
            @index.add_entry('HTMLタグ', '01.html#2', parent: 'HTML')

            hierarchy = @index.get_hierarchy

            assert_kind_of Array, hierarchy['HTML']
            assert_includes hierarchy['HTML'], 'HTML要素'
            assert_includes hierarchy['HTML'], 'HTMLタグ'
          end

          def test_root_terms_returns_entry_keys
            # root_terms は @entries のキーから @hierarchy の子を除外する
            index = HierarchicalIndex.new
            index.add_entry('A', '01.html#1')
            index.add_entry('C', '02.html#1')

            roots = index.root_terms

            # 親子関係がない場合、全てルート
            assert_includes roots, 'A'
            assert_includes roots, 'C'
            assert_equal 2, roots.size
          end

          def test_children_of_returns_child_terms
            @index.add_entry('子1', '01.html#1', parent: '親')
            @index.add_entry('子2', '01.html#2', parent: '親')

            children = @index.children_of('親')

            assert_equal 2, children.size
            assert_includes children, '子1'
            assert_includes children, '子2'
          end

          # --- phase: count methods tests ---

          def test_entry_count_returns_number_of_terms
            @index.add_entry('A', '01.html#1')
            @index.add_entry('B', '02.html#1')
            @index.add_entry('C', '03.html#1')

            assert_equal 3, @index.entry_count
          end

          def test_link_count_returns_total_links
            @index.add_entry('A', '01.html#1')
            @index.add_entry('A', '01.html#2')
            @index.add_entry('B', '02.html#1')

            assert_equal 3, @index.link_count
          end
        end
      end
    end
  end
end
