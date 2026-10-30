# frozen_string_literal: true

# ================================================================
# Test: build/stroked_text_test.rb
# ================================================================
# テスト対象:
#   StrokedText（図の SVG の縁取りした字の縁を、字の輪郭の図形にする・改善案 #129）
#
# 背景:
#   `stroke` を掛けた字は、書体を埋めた図でも Chromium が Type 3 で書き出す。
#   lives-mathematics の 10 枚の図のラベルの白い縁取りで、本の書体が Type 3 になっていた。
#
# 検証方法:
#   字の輪郭と送りは本物の書体から取るので、同梱の書体を一時プロジェクトへ持ち込む。
#   Chromium で Type 3 が消えることは組んだ PDF で確かめた（`type3-font-embedding-notes.md` §11）。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/pre_process'
require 'vivlio_starter/cli/build/stroked_text'

module VivlioStarter
  module CLI
    class StrokedTextTest < Minitest::Test
      StrokedText = Build::StrokedText
      BUNDLED_FONTS = File.expand_path('../../../../stylesheets/fonts', __dir__)

      def setup
        skip '同梱書体が無い環境では検証できない' unless Dir.exist?(File.join(BUNDLED_FONTS, 'Noto_Sans_JP'))
      end

      # 白い縁取り（lives-mathematics の形）。縁は字の輪郭の図形になって字の後ろへ入り、字は塗りだけになる。
      # text-anchor="middle" なので、2 字ぶん（26）の半分だけ左から始める
      def test_should_turn_the_halo_into_glyph_outlines_behind_the_text
        with_project do
          svg = figure(%(<text x="260.0" y="162.0" font-size="13" text-anchor="middle" fill="#b5651d" ) +
                       %(stroke="#fff" stroke-width="3" paint-order="stroke">半径</text>))

          result = StrokedText.outline(svg)

          assert_includes result, %(<g transform="translate(247 162) scale(0.013)" fill="none" stroke="#fff" stroke-width="230.77">)
          assert_equal 2, result.scan('<path ').size
          assert_includes result, '<path transform="translate(1000 0)"'
          assert_operator result.index('<path '), :<, result.index('<text'), '縁は字の後ろに描く'
          assert_includes result, 'style="stroke:none">半径</text>'
          assert_empty StrokedText.remaining(svg)
        end
      end

      # paint-order の指定が無ければ、縁は字の上に重なる（疑似的な太字の形）
      def test_should_keep_the_stroke_on_top_without_paint_order
        with_project do
          result = StrokedText.outline(figure(%(<text x="0" y="20" stroke="#000" stroke-width="0.5">辺</text>)))

          assert_operator result.index('<text'), :<, result.index('<path '), '縁は字の上に描く'
          assert_includes result, 'scale(0.016)', '大きさの指定が無ければ 16px'
        end
      end

      # 字の送りは図に埋める書体の値だけを足す（埋める部分集合に kern は無い）。空白も 1 字ぶん進み、図形にはならない。
      # text-anchor="end" は字の並びの右端を x にそろえる
      def test_should_lay_out_by_advances_including_spaces
        with_project do
          font = Build::FontMetrics.load(StrokedText::Embedder.font_path('Noto Sans JP', weight: :regular))
          width = %w[A \  B].sum { font.advance(it) } * 10

          result = StrokedText.outline(figure(%(<text x="100" y="50" font-size="10" text-anchor="end" stroke="#fff">A B</text>)))

          assert_includes result, "translate(#{format('%.2f', 100 - width).sub(/\.?0+\z/, '')} 50)"
          assert_equal 2, result.scan('<path ').size
        end
      end

      # 太字は太字の面の輪郭・本の書体に無い字は予備の書体（図に埋めるのと同じ順）の輪郭で描く
      def test_should_pick_the_same_face_as_the_embedded_fonts
        with_project do
          regular = StrokedText.outline(figure(%(<text stroke="#fff">中</text>)))
          bold = StrokedText.outline(figure(%(<text stroke="#fff" font-weight="700">中</text>)))
          svg = figure(%(<text stroke="#fff">≒</text>))

          refute_equal regular[/ d="[^"]+"/], bold[/ d="[^"]+"/]
          assert_equal 1, StrokedText.outline(svg).scan('<path ').size
          assert_empty StrokedText.remaining(svg)
        end
      end

      # 線の形の指定と、字の回転はそのまま写す
      def test_should_copy_stroke_properties_and_transform
        with_project do
          result = StrokedText.outline(figure(%(<text x="10" y="20" font-size="10" transform="rotate(-90 10 20)" stroke="#fff" ) +
                                              %(stroke-width="2" stroke-linejoin="round" stroke-opacity="0.5" opacity="0.8">角</text>)))

          assert_includes result, 'transform="rotate(-90 10 20) translate(10 20) scale(0.01)"'
          assert_includes result, 'stroke-linejoin="round"'
          assert_includes result, 'stroke-opacity="0.5"'
          assert_includes result, 'opacity="0.8"'
          assert_includes result, 'stroke-width="200"'
        end
      end

      # 親の `<g>` の縁取りも `<style>` の規則の縁取りも同じに組み替える。字の style の `stroke:none` は
      # 規則より強いので、字の上に縁は残らない
      def test_should_read_strokes_from_ancestors_and_style_rules
        with_project do
          grouped = figure(%(<g stroke="#fff" stroke-width="3" font-size="12"><text x="1" y="2">図</text></g>))
          ruled = figure(%(<style>.halo { stroke: #eee; stroke-width: 4px; font-size: 20px; paint-order: stroke }</style>) +
                         %(<text class="halo" x="1" y="2">図</text>))

          assert_includes StrokedText.outline(grouped), 'scale(0.012)'
          assert_empty StrokedText.remaining(grouped)

          result = StrokedText.outline(ruled)

          assert_includes result, 'stroke="#eee"'
          assert_includes result, 'scale(0.02)'
          assert_operator result.index('<path '), :<, result.index('<text')
          assert_empty StrokedText.remaining(ruled)
        end
      end

      # 字の位置を読み取れない字は組み替えず、知らせる側へ渡す
      def test_should_leave_text_whose_position_cannot_be_read
        with_project do
          [
            %(<text stroke="#fff">x<tspan baseline-shift="super">2</tspan></text>),
            %(<text stroke="#fff" dy="3">字</text>),
            %(<text stroke="#fff" x="1 2 3">字</text>),
            %(<text stroke="#fff" letter-spacing="2">字</text>),
            %(<text stroke="#fff" dominant-baseline="middle">字</text>),
            %(<text stroke="#fff" font-size="1.2em">字</text>),
            %(<text stroke="#fff" stroke-dasharray="1 2">字</text>),
            %(<text stroke="#fff" font-family="no such font">字</text>)
          ].each do |text|
            svg = figure(text)

            assert_equal svg, StrokedText.outline(svg), text
            assert_equal 1, StrokedText.remaining(svg).size, text
          end
        end
      end

      # 縁取りの無い字・線の stroke は触らない
      def test_should_leave_figures_without_stroked_text
        with_project do
          svg = figure(%(<line stroke="#000"/><text stroke="none">字</text><text stroke="#fff" stroke-width="0">字</text><text>字</text>))

          assert_equal svg, StrokedText.outline(svg)
          assert_empty StrokedText.remaining(svg)
        end
      end

      # 図に埋めた書体（`<style>` の巨大な @font-face）を規則として読まず、root の既定の書体は引く
      def test_should_skip_font_faces_in_the_embedded_style
        with_project do
          style = %(<style>@font-face{font-family:"X";src:url("data:font/ttf;base64,AAAA") format("truetype");}) +
                  %(svg{font-family:"Noto Sans JP";font-synthesis-weight:none}</style>)

          assert_includes StrokedText.outline(figure(%(#{style}<text stroke="#fff">字</text>))), '<path '
        end
      end

      private

      def figure(body) = %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 200">#{body}</svg>)

      def with_project
        original = Common::CONFIG
        Dir.mktmpdir('vs-stroked-text') do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p('stylesheets/fonts')
            FileUtils.cp_r(Dir[File.join(BUNDLED_FONTS, '{Noto_Sans_JP,hackgen35,DejaVu_Sans,DejaVu_Sans_Mono}')], 'stylesheets/fonts')
            Common.install_configuration!(
              Common.build_direct_configuration(typography: { heading: { font: 'Noto Sans JP' }, body: { font: 'Noto Serif JP' },
                                                              code: { font: 'HackGen35 Console NF' } })
            )
            yield
          end
        end
      ensure
        Common.install_configuration!(original)
      end
    end
  end
end
