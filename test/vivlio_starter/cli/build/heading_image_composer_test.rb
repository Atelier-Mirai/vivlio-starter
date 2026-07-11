# frozen_string_literal: true

# ================================================================
# Test: heading_image_composer_test.rb
# ================================================================
# テスト対象:
#   Build::HeadingImageComposer
#   （lib/vivlio_starter/cli/build/heading_image_composer.rb）
#
# 検証内容:
#   - 扉絵（frontispiece）SVG が <image>（data URI）＋ 番号・タイトル <text> を組むこと
#   - 節絵（ornament）SVG が番号色付き <tspan> ＋ タイトルを組むこと
#   - 長いタイトルが複数行（tspan）へ折り返されること
#   - HTML/XML 予約文字がエスケープされること
#   - 画像が存在しないときは compose が nil（→ simple 縮退）を返すこと
#
# 注記:
#   compose は ImageMagick に依存するため、SVG 組み立てロジックは純粋な
#   frontispiece_svg / ornament_svg を直接呼んで検証する（magick 非依存）。
# ================================================================

require_relative '../../../test_helper'
require_relative '../../../../lib/vivlio_starter/cli/build/heading_image_composer'

module VivlioStarter
  module CLI
    module Build
      class HeadingImageComposerTest < Minitest::Test
        FONT = "'Zen Kaku Gothic New', sans-serif"
        DATA_URI = 'data:image/jpeg;base64,AAAA'

        def test_should_compose_frontispiece_with_image_and_heading_text
          svg = HeadingImageComposer.frontispiece_svg(1000, 1414, DATA_URI, '第1章', '春のお花見', FONT)

          assert svg.start_with?('<svg')
          assert_includes svg, 'viewBox="0 0 1000 1414"'
          assert_includes svg, %(xlink:href="#{DATA_URI}")
          assert_includes svg, 'aria-label="第1章 春のお花見"'
          assert_includes svg, '第1章'
          assert_includes svg, '春のお花見'
          # 番号には下線（line）が付く
          assert_includes svg, '<line'
        end

        def test_should_compose_ornament_with_colored_number_tspan
          svg = HeadingImageComposer.ornament_svg(1196, 500, DATA_URI, '1-1', '導入', FONT, '#f0a000')

          assert svg.start_with?('<svg')
          assert_includes svg, 'viewBox="0 0 1196 500"'
          assert_includes svg, %(<tspan fill="#f0a000" font-weight="900">1-1</tspan>)
          assert_includes svg, '導入'
        end

        # 節題の長短でフォントサイズが不揃いにならない（固定基準・kindle_h2 不揃いの回帰テスト）
        def test_should_use_uniform_ornament_font_size_regardless_of_title_length
          short = HeadingImageComposer.ornament_svg(1196, 500, DATA_URI, '8-1', '概要', FONT, '#f0a000')
          mid   = HeadingImageComposer.ornament_svg(1196, 500, DATA_URI, '8-2', 'はじめかた', FONT, '#f0a000')

          size = ->(svg) { svg[/<text [^>]*font-size="(\d+)"/, 1].to_i }
          assert_equal size.call(short), size.call(mid), '通常長の節題は同じフォントサイズで組まれる'
          assert_equal (500 * 0.22).round, size.call(short), '基準サイズは height 比の固定値'
        end

        # 長い節題は幅に収まるまで縮小される（幅あふれの回帰テスト）
        def test_should_shrink_ornament_font_for_long_title_to_fit_width
          svg = HeadingImageComposer.ornament_svg(1196, 500, DATA_URI, '7-5', 'トラブルシューティング', FONT, '#f0a000')

          font_size = svg[/<text [^>]*font-size="(\d+)"/, 1].to_i
          char_count = '7-5　トラブルシューティング'.length
          assert_operator font_size * char_count, :<=, (1196 * 0.88).ceil, 'テキスト幅は画像幅 88% に収まる'
          assert_operator font_size, :<, (500 * 0.22).round, '長い節題は基準サイズより縮む'
        end

        def test_should_wrap_long_frontispiece_title_into_multiple_tspans
          long_title = 'あ' * 30
          svg = HeadingImageComposer.frontispiece_svg(1000, 1414, DATA_URI, '第2章', long_title, FONT)

          tspan_count = svg.scan('<tspan').size
          assert_operator tspan_count, :>=, 2, 'long title should wrap into multiple tspans'
        end

        def test_should_escape_xml_reserved_characters_in_heading_text
          svg = HeadingImageComposer.frontispiece_svg(800, 1131, DATA_URI, '第3章', 'A < B & "C"', FONT)

          assert_includes svg, '&lt;'
          assert_includes svg, '&amp;'
          refute_includes svg, '<text>A < B', 'raw < must not appear inside text'
        end

        def test_should_omit_number_markup_when_number_blank
          svg = HeadingImageComposer.frontispiece_svg(1000, 1414, DATA_URI, '', 'タイトルのみ', FONT)

          refute_includes svg, '<line', 'no underline when number is blank'
          assert_includes svg, 'タイトルのみ'
        end

        def test_should_return_nil_when_image_file_missing
          result = HeadingImageComposer.compose(
            image_path: '/nonexistent/path/door.webp',
            number: '第1章', title: 'X', kind: :frontispiece, font_family: FONT
          )

          assert_nil result
        end

        # render は画像が読めなければ（compose が nil）ラスタライズに進まず nil を返す（→ simple 縮退）
        def test_render_should_return_nil_when_image_file_missing
          result = HeadingImageComposer.render(
            image_path: '/nonexistent/path/door.webp',
            number: '第1章', title: 'X', kind: :frontispiece, font_family: FONT
          )

          assert_nil result
        end
      end
    end
  end
end
