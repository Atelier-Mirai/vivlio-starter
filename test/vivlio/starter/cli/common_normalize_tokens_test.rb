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

        def test_ranges_are_zero_padded
          tokens = Common.normalize_tokens(['1-3', '09-12'])
          assert_equal %w[01-03 09-12], tokens
        end

        def test_slug_with_number_prefix_is_zero_padded
          tokens = Common.normalize_tokens(['1-foo', 'contents/2-bar.md'])
          assert_equal %w[01-foo 02-bar], tokens
        end

        def test_non_numeric_tokens_are_preserved
          tokens = Common.normalize_tokens(['appendix-a', 'preface'])
          assert_equal %w[appendix-a preface], tokens
        end
      end
    end
  end
end
