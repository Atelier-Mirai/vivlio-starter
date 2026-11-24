# frozen_string_literal: true

# ================================================================
# Test: spot_transformer_test.rb
# ================================================================
# 検証内容（改善案 #157）:
#   - :::{.spot-right}・:::{.spot-left} を <div> へ書き換え、width= を style へ移す
#   - 中の画像に trim=on・border=off を足す（著者が書いた trim=・crop=・border= を優先）
#   - 記法解説フェンスの中・閉じない囲み・ほかの囲みは書き換えない
#   - 読めない属性を原稿の行番号で知らせる
# ================================================================

require_relative '../../../test_helper'
require 'vivlio_starter/cli/loader'

class SpotTransformerTest < Minitest::Test
  ST = VivlioStarter::CLI::PreProcessCommands::SpotTransformer

  def test_should_wrap_block_in_div_and_add_image_defaults
    content = <<~MD
      本文
      :::{.spot-left}
      すてきな世界だわ

      ![笑顔](images/a.webp)
      :::
      「楽しそうね」
    MD

    assert_equal <<~HTML, ST.transform(content)
      本文
      <div class="spot-left">

      すてきな世界だわ

      ![笑顔](images/a.webp){trim=on border=off}

      </div>

      「楽しそうね」
    HTML
  end

  # 幅は画像の width= と同じ書き方。単位のない数は px
  def test_should_move_width_to_style
    assert_includes ST.transform(":::{.spot-right width=35%}\n![a](a.webp)\n:::\n"),
                    '<div class="spot-right" style="width: 35%">'
    assert_includes ST.transform(":::{.spot-right width=40mm}\n![a](a.webp)\n:::\n"), 'style="width: 40mm"'
    assert_includes ST.transform(":::{.spot-right width=120}\n![a](a.webp)\n:::\n"), 'style="width: 120px"'
  end

  # 著者が書いた属性はそのまま使う（足すのは書いていないものだけ）
  def test_should_keep_author_attributes
    result = ST.transform(<<~MD)
      :::{.spot-right .extra}
      ![a](a.webp){trim=off}
      ![b](b.webp){crop="10 20" border=on}
      ![c](c.webp){width=50%}
      :::
    MD

    assert_includes result, '<div class="spot-right extra">'
    assert_includes result, '![a](a.webp){trim=off border=off}'
    assert_includes result, '![b](b.webp){crop="10 20" border=on}'
    assert_includes result, '![c](c.webp){width=50% trim=on border=off}'
  end

  def test_should_leave_code_unclosed_and_other_blocks
    content = <<~MD
      ```markdown
      :::{.spot-right}
      ![x](x.webp)
      :::
      ```

      :::{.memo}
      ![y](y.webp)
      :::

      :::{.spot-left}
      ![z](z.webp)
    MD

    assert_equal content, ST.transform(content)
  end

  # ほかの囲みの中に置いた小さな挿絵も書き換える
  def test_should_transform_spot_inside_other_block
    result = ST.transform(":::{.memo}\n:::{.spot-right}\n![a](a.webp)\n:::\n本文\n:::\n")

    assert_includes result, "<div class=\"spot-right\">\n\n![a](a.webp){trim=on border=off}\n\n</div>\n"
    assert result.end_with?("本文\n:::\n"), result
  end

  def test_should_warn_unreadable_params_with_line_number
    out, = capture_io do
      ST.validate("本文\n\n:::{.spot-right width=abc}\n![a](a.webp)\n:::\n:::{.spot-left width=30%}\n:::\n", '11-x.md')
    end

    assert_includes out, '11-x.md:3 - 小さな挿絵の囲みの属性を読めません（width=abc）'
    assert_includes out, ':::{.spot-right width=35%}'
    refute_includes out, 'width=30%）'
  end
end
