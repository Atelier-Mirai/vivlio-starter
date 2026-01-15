# frozen_string_literal: true

require 'test_helper'
require 'vivlio/starter/cli/common'

module Vivlio
  module Starter
    module CLI
      class CommonNormalizeTokensTest < Minitest::Test
        def test_digits_are_zero_padded_and_uniqued
          tokens = Common.normalize_tokens(%w[1 01 11])
          assert_equal %w[01 11], tokens
        end

        def test_ranges_are_expanded_and_zero_padded
          tokens = Common.normalize_tokens(['1-3', '09-12'])
          assert_equal %w[01 02 03 09 10 11 12], tokens
        end

        def test_slug_with_number_prefix_is_zero_padded
          tokens = Common.normalize_tokens(['1-foo', 'contents/2-bar.md'])
          assert_equal %w[01-foo 02-bar], tokens
        end

        def test_non_numeric_tokens_are_preserved
          tokens = Common.normalize_tokens(['appendix-a', 'preface'])
          assert_equal %w[appendix-a preface], tokens
        end

        def test_combination_of_ranges_and_individual_tokens
          tokens = Common.normalize_tokens(['1-3,5,8-10'])
          assert_equal %w[01 02 03 05 08 09 10], tokens
        end

        def test_descending_ranges_are_handled
          tokens = Common.normalize_tokens(['5-3'])
          assert_equal %w[03 04 05], tokens
        end
      end
    end
  end
end
