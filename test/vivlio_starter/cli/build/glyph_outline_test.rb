# frozen_string_literal: true

# ================================================================
# Test: build/glyph_outline_test.rb
# ================================================================
# 書体の 1 字の輪郭を SVG の path にする（GlyphOutline・改善案 #127 段階 4）。
# TrueType（glyf）は座標を自前で読み、CFF は TTFunk の Path を使う。
# 同梱の書体で確かめる: Noto Serif JP（TrueType）と Keyboard JP（CFF）
# ================================================================

require 'test_helper'
require 'ttfunk'
require 'vivlio_starter/cli/build/glyph_outline'

module VivlioStarter
  module CLI
    class GlyphOutlineTest < Minitest::Test
      GlyphOutline = Build::GlyphOutline
      FONTS = File.expand_path('../../../../stylesheets/fonts', __dir__)

      # TrueType の「口」は外と内の輪郭（明朝のうろこも別の輪郭）。輪郭ごとに始まりと閉じがあり、字面の枠に収まる
      def test_should_read_truetype_contours_into_an_svg_path
        outline = GlyphOutline.for(TTFunk::File.open("#{FONTS}/Noto_Serif_JP/NotoSerifJP-Regular.ttf"), '口')

        assert_operator outline.d.scan('M').size, :>=, 2
        assert_equal outline.d.scan('M').size, outline.d.scan('Z').size
        assert_in_delta 1000.0, outline.advance
        assert_operator outline.top, :>, -880, '上端が字面の枠の中'
        assert_operator outline.bottom, :<, 120, '下端が字面の枠の中'
        assert_operator outline.top, :<, outline.bottom, 'SVG の座標は下向きが正'
      end

      # 曲線の多い字は、TrueType の 2 次ベジェ（Q）になる。外の点が続く所は中点を補う
      def test_should_turn_off_curve_points_into_quadratic_curves
        outline = GlyphOutline.for(TTFunk::File.open("#{FONTS}/Noto_Serif_JP/NotoSerifJP-Regular.ttf"), 'の')

        assert_includes outline.d, 'Q'
        refute_includes outline.d, 'NaN'
      end

      # CFF は 3 次ベジェ（C）
      def test_should_read_cff_outlines
        outline = GlyphOutline.for(TTFunk::File.open("#{FONTS}/Keyboard_font/Keyboard-JP-Regular.otf"), 'A')

        assert outline.d.start_with?('M')
        assert_operator outline.advance, :positive?
      end

      def test_should_return_nil_for_a_character_the_font_lacks
        assert_nil GlyphOutline.for(TTFunk::File.open("#{FONTS}/Noto_Serif_JP/NotoSerifJP-Regular.ttf"), '暅')
      end
    end
  end
end
