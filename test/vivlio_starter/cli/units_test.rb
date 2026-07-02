# frozen_string_literal: true

# ================================================================
# Test: units_test.rb
# ================================================================
# テスト対象:
#   Units（lib/vivlio_starter/cli/units.rb）— 印刷単位の変換定数と長さパーサ。
#   CONFIG 非依存の純粋関数のため chdir 等の段取りは不要。
#
# 仕様: docs/specs/page-unit-conversion-spec.md §3.2 / §7.1
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/units'

module VivlioStarter
  module CLI
    class UnitsTest < Minitest::Test
      # 係数は「1Q = 0.25mm」「1in = 25.4mm = 72pt」から導出され、近似値 0.709 の
      # 直書きでないこと（B6）。
      def test_should_define_exact_conversion_constants
        assert_in_delta 0.25 * 72.0 / 25.4, Units::PT_PER_Q, 1e-12
        assert_in_delta 72.0 / 25.4, Units::PT_PER_MM, 1e-12
        assert_equal 25.4, Units::MM_PER_INCH
      end

      def test_should_convert_lengths_to_mm
        assert_in_delta 22.0, Units.length_to_mm('22mm'), 1e-9
        assert_in_delta 10.0, Units.length_to_mm('1cm'), 1e-9
        assert_in_delta 25.4, Units.length_to_mm('1in'), 1e-9
        assert_in_delta 25.4, Units.length_to_mm('72pt'), 1e-9
        assert_in_delta 22.0, Units.length_to_mm('88Q'), 1e-9
        assert_in_delta 22.0, Units.length_to_mm('88q'), 1e-9
        assert_in_delta 22.0, Units.length_to_mm(22), 1e-9
        assert_in_delta 22.0, Units.length_to_mm('22'), 1e-9
      end

      def test_should_return_nil_for_unparsable_lengths
        assert_nil Units.length_to_mm('0em')
        assert_nil Units.length_to_mm('50%')
        assert_nil Units.length_to_mm('abc')
        assert_nil Units.length_to_mm('')
        assert_nil Units.length_to_mm(nil)
      end

      def test_should_normalize_font_sizes_to_pt
        assert_equal '10pt', Units.font_size_to_pt('10pt')
        assert_equal '17.008pt', Units.font_size_to_pt('24Q')
        assert_equal '10.5pt', Units.font_size_to_pt(10.5)
        assert_equal '10.5pt', Units.font_size_to_pt('10.5')
        assert_equal '12px', Units.font_size_to_pt('12px')
        assert_nil Units.font_size_to_pt(nil)
      end

      def test_should_extract_pt_value
        assert_in_delta 10.5, Units.pt_value('10.5pt'), 1e-9
        assert_in_delta 10.5, Units.pt_value('10.5PT'), 1e-9
        assert_nil Units.pt_value('10.5mm')
        assert_nil Units.pt_value(nil)
      end

      def test_should_format_pt_with_three_decimals
        assert_equal '17.0pt', Units.format_pt(17)
        assert_equal '21.26pt', Units.format_pt(21.2598)
      end
    end
  end
end
