# frozen_string_literal: true

# ================================================================
# Test: showcase_svg_builder_test.rb
# ================================================================
# 検証内容（explanatory-diagram-spec.md §9）:
#   - viewBox が crop を反映し、座標系は元画像実寸のまま（§5.2・§7.4）
#   - rect 座標のパーミル → 元画像 px 変換、border の太さ・線種・色の振り分け
#   - バッジ（丸数字）の pos ごとの配置と有無
#   - pointer の rotate 角・本体中心・番号／ラベルの 3 態
#   - スタイル寸法がクロップ後幅の正規化単位（u）でスケールすること
#   - テキスト・属性値のエスケープ
# 画像寸法は引数 DI で与えるため外部ツールに依存しない。
# ================================================================

require_relative '../../../test_helper'
require 'vivlio_starter/cli/pre_process/showcase_svg_builder'

class ShowcaseSvgBuilderTest < Minitest::Test
  B = VivlioStarter::CLI::PreProcessCommands::ShowcaseSvgBuilder

  # 元画像 1000x500。crop 無しなら u = 1000/1000 = 1.0 となり、正規化単位＝px で読める。
  ORIG_W = 1000
  ORIG_H = 500
  DATA_URI = 'data:image/png;base64,AAAA'

  def build(markdown, orig_w: ORIG_W, orig_h: ORIG_H)
    block = B.parse(markdown.lines, orig_w:, orig_h:)
    B.build(block, orig_w:, orig_h:, data_uri: DATA_URI)
  end

  def test_should_lay_the_original_image_at_full_size_and_span_the_whole_viewbox
    svg = build("![画面](a.png)\n")

    assert_includes svg, %(<image xlink:href="#{DATA_URI}" x="0" y="0" width="1000" height="500"/>)
    assert_includes svg, %(viewBox="0 0 1000 500" width="1000" height="500")
    assert_includes svg, %(role="img" aria-label="画面")
  end

  def test_should_reflect_crop_in_the_viewbox_window_without_moving_the_coordinate_system
    # 上 50px / 右 100px / 下 25px / 左 200px を切り落とす
    svg = build(%(![](a.png){crop="50px 100px 25px 200px"}\nrect 190, 30, 360, 90\n))

    # 窓は原点 (200, 50)、寸法は 1000-200-100 = 700 × 500-50-25 = 425
    assert_includes svg, %(viewBox="200 50 700 425" width="700" height="425")
    # 注釈の座標は crop に影響されず元画像基準のまま（190‰ → 190px）
    assert_includes svg, %(<rect x="190" y="15" width="360" height="45")
  end

  def test_should_convert_rect_permille_coordinates_to_original_image_pixels
    svg = build("![](a.png)\nrect 190, 30, 360, 90\n")

    # X 系は幅 1000・Y 系は高さ 500 基準（30‰ × 500 = 15px、90‰ × 500 = 45px）
    assert_includes svg, %(<rect x="190" y="15" width="360" height="45")
    # 既定の枠線: 3 solid #ff3b30・背景は transparent
    assert_includes svg, %(fill="transparent" stroke="#ff3b30" stroke-width="3")
    refute_includes svg, 'stroke-dasharray'
  end

  def test_should_parse_border_tokens_in_any_order_and_emit_dasharray_for_dashed
    svg = build(%(![](a.png)\nrect 0, 0, 100, 100 {border="dashed blue 5" background="rgba(0,0,255,0.2)"}\n))

    assert_includes svg, %(fill="rgba(0,0,255,0.2)" stroke="blue" stroke-width="5")
    assert_includes svg, %(stroke-dasharray="8,5")
  end

  def test_should_place_badge_at_the_edge_midpoint_for_each_pos
    left   = build("![](a.png)\nrect:1 100, 0, 200, 100 {pos=left}\n")
    right  = build("![](a.png)\nrect:1 100, 0, 200, 100 {pos=right}\n")
    top    = build("![](a.png)\nrect:1 100, 0, 200, 100 {pos=top}\n")
    bottom = build("![](a.png)\nrect:1 100, 0, 200, 100 {pos=bottom}\n")
    center = build("![](a.png)\nrect:1 100, 0, 200, 100 {pos=center}\n")

    # 枠は x=100..300 / y=0..50（Y 系は高さ 500 基準）
    assert_includes left,   %(<circle cx="100" cy="25" r="26")
    assert_includes right,  %(<circle cx="300" cy="25" r="26")
    assert_includes top,    %(<circle cx="200" cy="0" r="26")
    assert_includes bottom, %(<circle cx="200" cy="50" r="26")
    assert_includes center, %(<circle cx="200" cy="25" r="26")
  end

  def test_should_draw_badge_as_white_circle_with_number_and_omit_it_when_number_is_absent
    numbered = build("![](a.png)\nrect:7 100, 0, 200, 100\n")
    bare     = build("![](a.png)\nrect 100, 0, 200, 100\n")

    assert_includes numbered, %(fill="white" stroke="#333333")
    assert_includes numbered, %(font-size="28" font-weight="700" fill="#222222">7</text>)
    refute_includes bare, '<circle'
  end

  def test_should_scale_style_dimensions_by_the_cropped_width_unit
    # 元画像 2000px 幅で左右を 500px ずつ切ると、クロップ後幅 1000px → u = 1.0
    svg = build(%(![](a.png){crop="0 500px"}\nrect:1 500, 0, 100, 100\n), orig_w: 2000)

    assert_includes svg, %(viewBox="500 0 1000 500")
    # u = 1.0 なので、半径・枠太さは正規化単位そのままの値で出る
    assert_includes svg, %(r="26")
    assert_includes svg, %(stroke-width="3")
  end

  def test_should_draw_pointer_tip_at_the_given_coordinate_with_body_extending_left_by_default
    svg = build("![](a.png)\npointer 500, 100\n")

    # 先端 (500, 50)、本体高さ 72・先端長 36・本体長 = max(72*1.2, 0+24) = 86.4
    assert_includes svg, %(<polygon points="500,50 464,14 377.6,14 377.6,86 464,86")
    assert_includes svg, %(fill="#ff3b30")
    # dir=right は基準形なので回転しない
    refute_includes svg, 'transform="rotate'
  end

  def test_should_rotate_the_pointer_polygon_around_the_tip_for_each_direction
    up   = build("![](a.png)\npointer 500, 100 {dir=up}\n")
    down = build("![](a.png)\npointer 500, 100 {dir=down}\n")
    left = build("![](a.png)\npointer 500, 100 {dir=left}\n")

    assert_includes up,   %(transform="rotate(270 500 50)")
    assert_includes down, %(transform="rotate(90 500 50)")
    assert_includes left, %(transform="rotate(180 500 50)")
  end

  def test_should_keep_pointer_text_horizontal_at_the_body_center_regardless_of_direction
    svg = build(%(![](a.png)\npointer 500, 100 {dir=up label="検索"}\n))

    # dir=up の本体中心は先端から下へ hd + bl/2。ラベルは回転させず水平に描く
    label = svg[/<text[^>]*>検索<\/text>/]

    refute_nil label
    assert_includes label, %(text-anchor="start")
    refute_includes label, 'rotate'
  end

  def test_should_lay_out_pointer_badge_and_label_side_by_side
    both  = build(%(![](a.png)\npointer:4 500, 100 {label="検索"}\n))
    only  = build("![](a.png)\npointer:4 500, 100\n")
    plain = build(%(![](a.png)\npointer 500, 100 {label="検索"}\n))

    # 番号は白抜きの小バッジ（白枠円＋番号）、ラベルは既定色 white
    assert_includes both, %(r="20" fill="none" stroke="white")
    assert_includes both, %(>4</text>)
    assert_includes both, %(>検索</text>)
    # 番号のみ・ラベルのみでも描き分ける
    assert_includes only, %(>4</text>)
    refute_includes only, 'text-anchor="start"'
    refute_includes plain, %(r="20" fill="none")
    assert_includes plain, %(>検索</text>)
  end

  def test_should_honor_color_and_font_size_options
    svg = build(%(![](a.png)\nrect:1 100, 0, 200, 100 {color=blue font-size=40}\n))

    assert_includes svg, %(font-size="40" font-weight="700" fill="blue")
  end

  def test_should_escape_text_and_attribute_values
    svg = build(%(![A & B <img>](a.png)\npointer:1 500, 100 {label="<b>&x"} "引用" を含む注記\n))

    # 属性値の " は &quot; へ（著者コメントは alt/aria-label に集約される）
    assert_includes svg, %(aria-label="A &amp; B &lt;img&gt;: ① &quot;引用&quot; を含む注記")
    assert_includes svg, %(>&lt;b&gt;&amp;x</text>)
    refute_includes svg, '<b>'
  end
end
