# frozen_string_literal: true

# ================================================================
# Test: showcase_parser_test.rb
# ================================================================
# 検証内容（explanatory-diagram-spec.md §9）:
#   - rect / pointer の行パース（番号あり・省略、オプションあり・省略、著者コメント）
#   - 無単位＝パーミル / px 接尾辞＝元画像実ピクセル（→ パーミルへ正規化）
#   - {…} オプションの引用値保護（border="3 dashed blue"）
#   - crop shorthand 1 / 2 / 4 個
#   - コメント行・解釈不能行の扱い（その行だけ捨ててブロックは生かす）
# ================================================================

require_relative '../../../test_helper'
require 'vivlio_starter/cli/pre_process/showcase_svg_builder'

class ShowcaseParserTest < Minitest::Test
  B = VivlioStarter::CLI::PreProcessCommands::ShowcaseSvgBuilder

  # 元画像は 1000x500 px。px 表記のパーミル換算がちょうど分かりやすい寸法にしている。
  ORIG_W = 1000
  ORIG_H = 500

  def parse(text, on_warn: nil)
    B.parse(text.lines, orig_w: ORIG_W, orig_h: ORIG_H, on_warn:)
  end

  def test_should_parse_image_line_with_width_and_crop_shorthand
    block = parse(<<~MD)
      ![エディタ画面](images/10-intro/editor.png){width=80% crop="50px 100px 25px 200px"}
    MD

    assert_pattern do
      block => { image_path: 'images/10-intro/editor.png', alt: 'エディタ画面', width: '80%', annotations: [] }
    end
    # 上下は高さ 500 基準、左右は幅 1000 基準でパーミル化される
    assert_equal [100.0, 100.0, 50.0, 200.0], block.crop
  end

  def test_should_default_width_and_crop_when_attributes_are_absent
    block = parse("![](shot.png)\n")

    assert_equal '100%', block.width
    assert_equal [0.0, 0.0, 0.0, 0.0], block.crop
  end

  def test_should_expand_crop_shorthand_of_one_and_two_values
    single = parse(%(![](a.png){crop="10"}\n))
    double = parse(%(![](a.png){crop="10 20"}\n))

    assert_equal [10.0, 10.0, 10.0, 10.0], single.crop
    assert_equal [10.0, 20.0, 10.0, 20.0], double.crop
  end

  def test_should_parse_rect_with_number_options_and_author_comment
    block = parse(<<~MD)
      ![](a.png)
      # ここはコメント行（出力されない）
      rect:1 190, 30, 360, 90 {pos=right} untitled タブの枠
    MD

    assert_pattern do
      block.annotations => [
        { type: :rect, number: 1, coords: [190.0, 30.0, 360.0, 90.0], comment: 'untitled タブの枠' }
      ]
    end
    assert_equal({ 'pos' => 'right' }, block.annotations.first.options)
  end

  def test_should_parse_rect_without_number_and_with_quoted_option_values
    block = parse(<<~MD)
      ![](a.png)
      rect 580, 810, 200, 70 {pos=center border="3 dashed blue" background="rgba(0,0,255,0.2)"}
    MD

    assert_pattern do
      block.annotations => [{ type: :rect, number: nil, comment: '' }]
    end
    assert_equal({ 'pos' => 'center', 'border' => '3 dashed blue', 'background' => 'rgba(0,0,255,0.2)' },
                 block.annotations.first.options)
  end

  def test_should_normalize_px_coordinates_against_original_image_size
    block = parse("![](a.png)\npointer:2 120px, 250px {dir=up} 行番号 1\n")

    # X は幅 1000 の千分率（120px → 120）、Y は高さ 500 の千分率（250px → 500）
    assert_pattern do
      block.annotations => [{ type: :pointer, number: 2, coords: [120.0, 500.0], comment: '行番号 1' }]
    end
    assert_equal({ 'dir' => 'up' }, block.annotations.first.options)
  end

  def test_should_parse_pointer_without_options_block
    block = parse("![](a.png)\npointer:4 810, 50 検索ボタン\n")

    assert_pattern do
      block.annotations => [{ type: :pointer, number: 4, coords: [810.0, 50.0], options: {}, comment: '検索ボタン' }]
    end
  end

  def test_should_parse_pointer_without_number_but_with_label
    block = parse(%(![](a.png)\npointer 810, 50 {label="検索"} 検索について説明すること\n))

    assert_pattern do
      block.annotations => [{ type: :pointer, number: nil }]
    end
    assert_equal({ 'label' => '検索' }, block.annotations.first.options)
  end

  def test_should_drop_unparsable_line_and_report_it_while_keeping_the_block
    warned = []
    block = parse(<<~MD, on_warn: ->(line) { warned << line })
      ![](a.png)
      rect 190 30 360 90
      pointer:4 810, 50 検索ボタン
    MD

    assert_equal ['rect 190 30 360 90'], warned
    assert_equal [:pointer], block.annotations.map(&:type)
  end

  def test_should_return_nil_when_block_has_no_image_line
    assert_nil parse("rect:1 190, 30, 360, 90\n")
  end

  def test_should_build_alt_text_from_numbered_author_comments
    block = parse(<<~MD)
      ![エディタ画面](a.png)
      rect:1 190, 30, 360, 90 {pos=right} untitled タブの枠
      rect:3 580, 810, 200, 70 {pos=center}
      pointer:4 810, 50 検索アイコン
    MD

    # 番号と著者コメントが揃った注釈だけを ① 形式で集約する（コメント無しの ③ は出ない）
    assert_equal 'エディタ画面: ① untitled タブの枠 ④ 検索アイコン', B.alt_text(block)
  end
end
