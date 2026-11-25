# frozen_string_literal: true

# ================================================================
# Test: image_flip_test.rb
# ================================================================
# 検証内容（改善案 #163 の flip=horizontal・flip=vertical）:
#   - 向きの計算: crop は元の画像の向きで書き、反転した後の窓では左右（上下）を入れ替える
#   - ラスター: 合成 SVG の <image> に反転の transform を掛ける。反転は鍵にも入る
#   - SVG: 写しの中身を transform を持つ <g> で包む。crop と一緒なら窓は入れ替えた値で切る
#   - 図を組む: flip のある画像は、切り抜いた画像の経路（framed_image）を通る
#   - 前処理の点検: 値の誤り（直し方の推測つき）・文中の画像・showcase の中を原稿の行番号で 🟡
# 外部ツールは使わない（SVG の反転と窓は文字列の書き換えだけで済む）。
# ================================================================

require_relative '../../../test_helper'
require 'fileutils'
require 'tmpdir'
require 'vivlio_starter/cli/loader'

class ImageFlipGeometryTest < Minitest::Test
  B = VivlioStarter::CLI::PreProcessCommands::ShowcaseSvgBuilder

  def test_should_swap_right_and_left_for_horizontal_flip
    assert_equal [10.0, 40.0, 30.0, 20.0], B.flipped_crop([10.0, 20.0, 30.0, 40.0], 'horizontal')
  end

  def test_should_swap_top_and_bottom_for_vertical_flip
    assert_equal [30.0, 20.0, 10.0, 40.0], B.flipped_crop([10.0, 20.0, 30.0, 40.0], 'vertical')
  end

  def test_should_keep_crop_without_flip
    assert_equal [10.0, 20.0, 30.0, 40.0], B.flipped_crop([10.0, 20.0, 30.0, 40.0], nil)
  end

  # viewBox の原点が 0 でない SVG も、その範囲の中で反転する
  def test_should_flip_within_the_given_box
    assert_equal 'matrix(-1 0 0 1 400 0)', B.flip_transform('horizontal', width: 400, height: 200)
    assert_equal 'matrix(1 0 0 -1 0 200)', B.flip_transform('vertical', width: 400, height: 200)
    assert_equal 'matrix(-1 0 0 1 120 0)', B.flip_transform('horizontal', width: 100, height: 50, x: 10, y: 5)
    assert_nil B.flip_transform(nil, width: 400, height: 200)
  end

  def test_should_flip_only_the_image_in_composed_svg
    block = B::ShowcaseBlock.new(image_path: 'a.png', alt: '', width: '100%', crop: [0.0, 0.0, 0.0, 0.0], annotations: [])

    flipped = B.build(block, orig_w: 400, orig_h: 200, data_uri: 'data:image/png;base64,AA', flip: 'horizontal')
    plain = B.build(block, orig_w: 400, orig_h: 200, data_uri: 'data:image/png;base64,AA')

    assert_includes flipped, 'width="400" height="200" transform="matrix(-1 0 0 1 400 0)"/>'
    assert_includes flipped, 'viewBox="0 0 400 200"'
    refute_includes plain, 'transform='
  end
end

class ImageFlipSvgTest < Minitest::Test
  T = VivlioStarter::CLI::PreProcessCommands::ImageTrimmer
  Common = VivlioStarter::CLI::Common

  # 左半分が赤・右半分が青の図（680×600）
  SVG = <<~SVG
    <svg width="100%" viewBox="0 0 680 600" xmlns="http://www.w3.org/2000/svg">
      <rect x="0" y="0" width="340" height="600" fill="red"/>
      <rect x="340" y="0" width="340" height="600" fill="blue"/>
    </svg>
  SVG

  class NoTools
    def available? = false
    def content_box(_source) = raise('測らないはず')
  end

  def in_project
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('images/11-x')
        File.write('images/11-x/fig.svg', SVG)
        yield
      end
    end
  end

  def framed(attributes)
    line = "![](#{Common.asset_prefix}images/11-x/fig.svg){#{attributes}}"
    result = T.framed_image(line, chapter_slug: '11-x', source_filename: '11-x.md', tools: NoTools.new)
    result && [result, File.read(File.join(Common::BUILD_HTML_DIR, result[:svg]))]
  end

  def test_should_wrap_svg_body_in_flipping_group
    flipped = T.flip_svg(SVG, 'horizontal')

    assert_includes flipped, '<svg width="100%" viewBox="0 0 680 600" xmlns="http://www.w3.org/2000/svg"><g transform="matrix(-1 0 0 1 680 0)">'
    assert_includes flipped, "</g></svg>\n"
    assert_includes flipped, '<rect x="0" y="0" width="340" height="600" fill="red"/>' # 中身は書き換えない
  end

  def test_should_give_up_svg_without_size
    assert_nil T.flip_svg('<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>', 'horizontal')
  end

  # flip だけなら、余白を測らず（trim=on でない）、窓も元のまま
  def test_should_flip_svg_copy_without_cropping
    in_project do
      result, written = framed('flip=horizontal')

      assert_match %r{\Aimages/trim/11-x/\h{16}\.svg\z}, result[:svg]
      assert_path_exists result[:source]
      assert_includes written, 'viewBox="0 0 680 600"'
      assert_includes written, '<g transform="matrix(-1 0 0 1 680 0)">'
      assert_equal SVG, File.read('images/11-x/fig.svg') # 原本は変えない
    end
  end

  # crop="0 0 0 68px" は元の画像の左 68px（赤の側）を切る。反転した後では右の端になる
  def test_should_count_crop_in_original_orientation
    in_project do
      _result, written = framed('flip=horizontal crop="0 0 0 68px"')

      assert_includes written, 'viewBox="0 0 612 600"'
    end
  end

  def test_should_flip_svg_vertically
    in_project do
      _result, written = framed('flip=vertical crop="60px 0 0 0"')

      assert_includes written, '<g transform="matrix(1 0 0 -1 0 600)">'
      assert_includes written, 'viewBox="0 0 680 540"' # 上の 60px は、反転した後では下の端
    end
  end

  def test_should_ignore_unknown_flip_value
    in_project do
      assert_nil framed('flip=left')
    end
  end
end

class ImageFlipRasterTest < Minitest::Test
  ST = VivlioStarter::CLI::PreProcessCommands::ShowcaseTransformer
  B = VivlioStarter::CLI::PreProcessCommands::ShowcaseSvgBuilder

  def test_should_put_flip_into_cache_key
    Dir.mktmpdir do |dir|
      source = File.join(dir, 'a.png')
      File.binwrite(source, 'png')
      block = B::ShowcaseBlock.new(image_path: 'a.png', alt: '', width: '100%', crop: [0.0, 0.0, 0.0, 0.0], annotations: [])

      keys = [nil, 'horizontal', 'vertical'].map { ST.cache_key(source, block, flip: it) }

      assert_equal 3, keys.uniq.size
      assert_equal ST.cache_key(source, block), keys.first, '反転しない画像の鍵は今までと同じ'
    end
  end
end

# 図を組むとき、flip のある画像は切り抜いた画像の経路を通る
class CrossReferenceFlipTest < Minitest::Test
  XR = VivlioStarter::CLI::PreProcessCommands::CrossReferenceProcessor
  T = VivlioStarter::CLI::PreProcessCommands::ImageTrimmer

  def test_should_frame_flipped_image
    framed = { svg: 'images/showcase/11-x/k.svg', raster: 'images/showcase/11-x/k.png' }

    out = T.stub(:framed_image, framed) do
      XR.transform_captioned_blocks("![未來](mirai.webp){flip=horizontal width=40%}\n", '11-x.md', {})
    end

    assert_includes out, '<img class="vs-cropped" src="images/showcase/11-x/k.svg" data-vs-raster="images/showcase/11-x/k.png" alt="未來">'
    assert_includes out, 'style="width: 40%"'
  end
end

# 前処理の点検は原稿そのままの行番号で知らせる
class MarkdownPreprocessorFlipValidationTest < Minitest::Test
  MP = VivlioStarter::CLI::PreProcessCommands::MarkdownPreprocessor
  Common = VivlioStarter::CLI::Common

  def warnings_for(content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, '11-x.md')
      File.write(path, content)
      entry = Data.define(:kind, :number).new(kind: :chapter, number: 11)
      preprocessor = MP.new(path, entry)
      lines = []
      Common.with_emit_sink(lines) { preprocessor.send(:validate_image_flips!) }
      lines
    end
  end

  def test_should_suggest_direction_for_misspelled_value
    log = warnings_for("本文\n\n![](a.webp){flip=left}\n\n![](b.webp){flip=up}\n\n![](c.webp){flip=yes}\n")

    assert(log.any? { it.include?('11-x.md:3 - 画像の flip の値が不正です（flip=left）') })
    assert(log.any? { it.include?('→ flip=left を flip=horizontal に直してください。') })
    assert(log.any? { it.include?('→ flip=up を flip=vertical に直してください。') })
    assert(log.any? { it.include?('→ flip=yes を、左右に反転するなら flip=horizontal、上下に反転するなら flip=vertical に直してください。') })
  end

  def test_should_warn_flip_on_inline_image
    log = warnings_for("文の中の ![](a.webp){flip=horizontal} 画像\n")

    assert(log.any? { it.include?('11-x.md:1 - flip は、段落に単独で置いた画像にだけ効きます') })
  end

  def test_should_warn_flip_inside_showcase
    log = warnings_for(":::{.showcase}\n![](a.webp){flip=horizontal}\nrect:1 10, 10, 20, 20\n:::\n")

    assert(log.any? { it.include?('11-x.md:2 - :::{.showcase} の中の画像は反転できません') })
  end

  def test_should_accept_flip_on_standalone_images
    content = "![](a.webp){flip=horizontal}\n\n:::{.spot-right}\n吹き出し\n\n![](b.webp){flip=vertical width=30%}\n:::\n\n" \
              "`![](c.webp){flip=bad}`\n"

    assert_empty warnings_for(content)
  end
end
