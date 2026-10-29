# frozen_string_literal: true

# ================================================================
# Test: build/figure_emoji_test.rb
# ================================================================
# 図の SVG の、中身が絵文字だけの <text> を twemoji の図形に差し替える（改善案 #127 段階 3）。
# twemoji は同梱のもの（stylesheets/twemoji）を使う。位置は 1 字 = 1em の正方形で、
# 下端を基線から 0.15em 下に置く（地の文の twemoji の <img> と同じ）。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'vivlio_starter/cli/build/figure_emoji'

module VivlioStarter
  module CLI
    class FigureEmojiTest < Minitest::Test
      FigureEmoji = Build::FigureEmoji
      TWEMOJI = File.expand_path('../../../../stylesheets/twemoji', __dir__)

      def replace(svg) = FigureEmoji.replace(svg, emoji_dir: TWEMOJI)

      # 祖先の text-anchor="middle" と字の font-size から、中央寄せの 17px 四方に置く。
      # 異体字セレクタの付いた ✌️ も 1 字。ほかの字と図形は 1 バイトも変えない
      def test_should_replace_emoji_only_text_at_the_same_position
        svg = <<~SVG
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 253"><g font-family="sans-serif" text-anchor="middle">
          <text x="160" y="52" font-size="17.00">✊</text>
          <text x="160" y="70" font-size="14.00">グー 0</text>
          <text x="246.6" y="202" font-size="17.00">✌️</text>
          </g></svg>
        SVG

        result = replace(svg)

        assert_includes result, '<g role="img" aria-label="✊"><svg x="151.5" y="37.55" width="17" height="17" viewBox="0 0 36 36">'
        assert_includes result, '<g role="img" aria-label="✌️"><svg x="238.1" y="187.55" width="17" height="17"'
        assert_includes result, '<text x="160" y="70" font-size="14.00">グー 0</text>'
        refute_match(%r{<text[^>]*>[✊✌]}, result)
      end

      # 2 字並べば 2 つの正方形を横に並べる。text-anchor が無ければ x が左端。大きさが無ければ 16px
      def test_should_lay_out_several_emoji_from_the_start
        result = replace(%(<svg xmlns="http://www.w3.org/2000/svg"><text x="10" y="20">✊✋</text></svg>))

        assert_includes result, '<svg x="10" y="6.4" width="16" height="16"'
        assert_includes result, '<svg x="26" y="6.4" width="16" height="16"'
      end

      # 差し替えないもの: 文字と混ざった絵文字・dx のある字・em の大きさ・twemoji に無い字・
      # <style> が大きさを決めるかもしれない class 付きの字
      def test_should_leave_text_it_cannot_place
        [
          %(<svg xmlns="http://www.w3.org/2000/svg"><text x="1" y="2">勝つ ✊</text></svg>),
          %(<svg xmlns="http://www.w3.org/2000/svg"><text x="1" y="2" dx="3">✊</text></svg>),
          %(<svg xmlns="http://www.w3.org/2000/svg"><text x="1" y="2" font-size="1.2em">✊</text></svg>),
          %(<svg xmlns="http://www.w3.org/2000/svg"><style>.e { font-size: 20px }</style><text class="e" x="1" y="2">✊</text></svg>)
        ].each { assert_equal it, replace(it) }

        Dir.mktmpdir do |empty|
          svg = %(<svg xmlns="http://www.w3.org/2000/svg"><text x="1" y="2">✊</text></svg>)

          assert_equal svg, FigureEmoji.replace(svg, emoji_dir: empty)
        end
      end

      # 字の transform は、図形をまとめた <g> へ移す
      def test_should_keep_the_transform_of_the_text
        result = replace(%(<svg xmlns="http://www.w3.org/2000/svg"><text x="0" y="16" transform="rotate(30)">✊</text></svg>))

        assert_includes result, '<g role="img" aria-label="✊" transform="rotate(30)"><svg x="0" y="2.4"'
      end
    end
  end
end
