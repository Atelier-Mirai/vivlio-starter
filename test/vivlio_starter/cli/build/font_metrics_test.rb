# frozen_string_literal: true

# ================================================================
# Test: build/font_metrics_test.rb
# ================================================================
# 書体ファイルから字の送り・x ハイト・カーニングを読む（FontMetrics・chapter-lead-size-spec.md §4.4）。
# 同梱の書体（stylesheets/fonts）を読む。値は HarfBuzz（hb-shape）の結果と照らして決めた。
# ================================================================

require_relative '../../../test_helper'
require_relative '../../../../lib/vivlio_starter/cli/build/font_metrics'

class TestFontMetrics < Minitest::Test
  FontMetrics = VivlioStarter::CLI::Build::FontMetrics
  FONTS = File.expand_path('../../../../stylesheets/fonts', __dir__)

  def serif = FontMetrics.load("#{FONTS}/Noto_Serif_JP/NotoSerifJP-Regular.ttf")

  def test_should_read_advance_widths_relative_to_font_size
    assert_in_delta 1.0, serif.advance('あ'), 1e-9
    assert_in_delta 0.256, serif.advance(' '), 1e-9
    assert_in_delta 0.715, serif.advance('R'), 1e-9
  end

  # Chromium は和文にもカーニングを当てる。「す。」は詰まり、「え、」は開く（hb-shape の値と同じ）
  def test_should_read_kerning_pairs_from_gpos
    assert_in_delta(-0.08, serif.kern('す', '。'), 1e-9)
    assert_in_delta 0.06, serif.kern('え', '、'), 1e-9
    assert_in_delta 0.0, serif.kern('あ', 'い'), 1e-9
  end

  # 型 9（拡張）に包まれない PairPos も読む（Zen Maru Gothic の kern は型 2 のままで、欧文の組だけ）
  def test_should_read_kerning_from_plain_pair_positioning
    zen = FontMetrics.load("#{FONTS}/Zen_Maru_Gothic/ZenMaruGothic-Regular.ttf")

    assert_in_delta(-0.08, zen.kern('A', 'V'), 1e-9)
    assert_in_delta(-0.1, zen.kern('A', 'T'), 1e-9)
  end

  def test_should_read_x_height_for_ex_units
    assert_in_delta 0.514, serif.x_height, 1e-9
  end

  # 書体に無い字は nil（呼ぶ側が別の書体を探す）
  def test_should_report_missing_glyphs
    refute serif.glyph?('≒')
    assert_nil serif.advance('≒')
    assert serif.glyph?('あ')
  end

  def test_should_load_each_font_once
    assert_same serif, serif
  end
end
