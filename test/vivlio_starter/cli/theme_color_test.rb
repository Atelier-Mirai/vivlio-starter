# frozen_string_literal: true

# ================================================================
# Test: theme_color_test.rb
# ================================================================
# テスト対象: VivlioStarter::CLI::ThemeColor（lib/vivlio_starter/cli/theme_color.rb）
#   - 色名/hex → リテラル hex の解決（techbook 互換の resolve と、Kindle 用 6 桁保証の to_hex6）
#   - 白との混色（color-mix の事前計算）
#   - 不正値（注入文字列・未知色名）の既定色フォールバック
# ================================================================

require_relative '../../test_helper'
require_relative '../../../lib/vivlio_starter/cli/theme_color'

module VivlioStarter
  module CLI
    class ThemeColorTest < Minitest::Test
      TC = ThemeColor

      # resolve: 色名→hex・hex 透過・techbook 互換（3/8 桁はそのまま）。解決不能は nil。
      def test_resolve_matches_palette_and_passes_hex_through
        assert_equal '#f0a000', TC.resolve('yellow')
        assert_equal '#0ea5e9', TC.resolve('blue')
        assert_equal '#123abc', TC.resolve('#123ABC'), 'hex は小文字化して透過'
        assert_equal '#abcdef', TC.resolve('abcdef'), 'bare hex に # を付す'
        assert_equal '#abcdef', TC.resolve('0xabcdef')
        assert_equal '#abc', TC.resolve('#abc'), '3 桁はそのまま（techbook 互換）'
        assert_nil TC.resolve(''), '空は nil（呼び出し側が既定を当てる）'
        assert_nil TC.resolve('unknowncolor'), '未知色名は nil'
      end

      # to_hex6: 必ず #rrggbb（3→6 展開・8→6 切詰・不正は既定）
      def test_to_hex6_always_returns_six_digit_literal
        assert_equal '#f0a000', TC.to_hex6('yellow')
        assert_equal '#aabbcc', TC.to_hex6('#abc'), '3 桁は 6 桁へ展開'
        assert_equal '#123456', TC.to_hex6('#12345678'), '8 桁は alpha を捨てて 6 桁'
        assert_equal '#0ea5e9', TC.to_hex6('blue')
        assert_match(/\A#\h{6}\z/, TC.to_hex6('teal'))
      end

      # 注入文字列・未知値は fallback（既定または指定）へ落ち、CSS 構文を壊さない
      def test_to_hex6_rejects_injection_and_falls_back
        assert_equal '#f0a000', TC.to_hex6('red;}body{background:url(evil)'), '注入文字列は既定へ'
        assert_equal '#f0a000', TC.to_hex6(nil)
        assert_equal '#0ea5e9', TC.to_hex6('bogus', fallback: 'blue'), 'fallback を尊重'
      end

      # mix_with_white: accent 比率で白と混色し #rrggbb を返す
      def test_mix_with_white_precomputes_color_mix
        # #f0a000 = (240,160,0)。15% accent + 85% white → 各成分 round(c*0.15 + 255*0.85)
        assert_equal '#fdf1d9', TC.mix_with_white('#f0a000', 0.15)
        assert_equal '#ffffff', TC.mix_with_white('#f0a000', 0.0), '0% は白'
        assert_equal '#f0a000', TC.mix_with_white('#f0a000', 1.0), '100% は原色'
      end
    end
  end
end
