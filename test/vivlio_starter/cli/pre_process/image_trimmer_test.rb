# frozen_string_literal: true

# ================================================================
# Test: image_trimmer_test.rb
# ================================================================
# 検証内容（image-trim-spec.md）:
#   - 測った範囲から crop（パーミル）を作る: 余白 2% の足し戻し・元の余白を超えない・一色だけは nil（§3.2）
#   - SVG の背景の四角は測るときだけ外す。定義の中・線あり・塗りなし・クラス付きは残す（§3.3）
#   - SVG は viewBox を書き換える: 原点が 0 でない viewBox・width の % / 絶対値（§3.4）
#   - 段落に単独で置いた画像: SVG の crop / trim=on は詰めた SVG と data-vs-source、
#     詰める余白が無ければ元の画像のまま（§3.4・§3.7・§4）
#   - showcase の trim=on は crop に置き換わる・crop を併記したら crop を使う（§3.5・§3.6）
#   - 前処理の点検: trim の値の誤りと crop との併記を原稿の行番号で 🟡（§3.6）
#   - preflight の 💡: 対象の絞り込み・同じ画像は 1 回・before → after（§5）
#   - EPUB へは data-vs-source を持ち込まない
# 外部ツールはフェイクに差し替える（magick / rsvg-convert の無い環境でも走る）。
# ================================================================

require_relative '../../../test_helper'
require 'fileutils'
require 'tmpdir'
require 'vivlio_starter/cli/loader'

class ImageTrimmerTest < Minitest::Test
  T = VivlioStarter::CLI::PreProcessCommands::ImageTrimmer
  Common = VivlioStarter::CLI::Common

  # 決まった範囲を返すフェイク。呼ばれた回数で、キャッシュが効いたかを見る。
  class BoxTools
    attr_reader :calls

    def initialize(box) = (@box = box) && (@calls = 0)
    def available? = true

    def content_box(_source)
      @calls += 1
      @box
    end
  end

  class NoTools
    def available? = false
    def content_box(_source) = raise('呼ばれないはず')
  end

  # 1 章の図（手で詰める前）の形。絵は x 40〜605・y 30〜580。
  WORKFLOW_SVG = <<~SVG
    <svg width="100%" viewBox="0 0 680 600" role="img" xmlns="http://www.w3.org/2000/svg">
      <text x="40" y="40">ラベル</text>
    </svg>
  SVG

  # 680×600 を長い辺 2000 で描いた画素での範囲（x 40〜605・y 30〜580 に当たる）
  WORKFLOW_BOX = { width: 2000, height: 1765, x: 118, y: 88, w: 1662, h: 1618 }.freeze

  def in_project
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('images/11-workflow')
        yield dir
      end
    end
  end

  def capture_log(&)
    lines = []
    Common.with_emit_sink(lines, &)
    lines
  end

  # --- 測った範囲から crop を作る（§3.2） ---

  def test_should_add_back_two_percent_margin_and_report_usage
    m = T.measurement_from({ width: 1000, height: 500, x: 100, y: 50, w: 800, h: 400 })

    # 余白は絵の幅 800 の 2% = 16 画素。上下左右とも元の余白から 16 を残して削る
    assert_equal [(34 / 500.0 * 1000).round(2), 84.0, (34 / 500.0 * 1000).round(2), 84.0], m.crop
    assert_in_delta 0.8, m.usage
    assert_in_delta 1000.0 / 832, m.scale, 0.001
    assert_predicate m, :trimmed?
  end

  def test_should_not_widen_beyond_original_margin
    m = T.measurement_from({ width: 1000, height: 1000, x: 5, y: 0, w: 990, h: 1000 })

    assert_equal [0, 0, 0, 0], m.crop
    refute_predicate m, :trimmed?
  end

  def test_should_return_nil_for_single_color_image
    assert_nil T.measurement_from({ width: 50, height: 40, x: 50, y: 40, w: 0, h: 0 })
  end

  def test_should_parse_magick_trim_geometry
    tools = T::Tools.new

    assert_equal({ width: 680, height: 600, x: 40, y: 30, w: 565, h: 550 }, tools.parse_box('565x550+40+30 680 600'))
    assert_equal({ width: 50, height: 40, x: 50, y: 40, w: 0, h: 0 }, tools.parse_box('0x0+50+40 50 40'))
  end

  def test_should_cache_measurement_by_image_content
    in_project do
      File.write('images/11-workflow/fig.svg', WORKFLOW_SVG)
      tools = BoxTools.new(WORKFLOW_BOX)

      first = T.measure('images/11-workflow/fig.svg', tools:)
      second = T.measure('images/11-workflow/fig.svg', tools:)

      assert_equal first, second
      assert_equal 1, tools.calls
    end
  end

  def test_should_remember_single_color_image_without_redrawing
    in_project do
      File.write('images/11-workflow/blank.svg', WORKFLOW_SVG)
      tools = BoxTools.new({ width: 50, height: 40, x: 50, y: 40, w: 0, h: 0 })

      assert_nil T.measure('images/11-workflow/blank.svg', tools:)
      assert_nil T.measure('images/11-workflow/blank.svg', tools:)
      assert_equal 1, tools.calls
    end
  end

  # --- SVG の背景の四角（§3.3） ---

  def test_should_strip_only_full_filled_background_rect
    svg = <<~SVG
      <svg viewBox="10 20 100 50" xmlns="http://www.w3.org/2000/svg">
        <defs><clipPath id="c"><rect x="10" y="20" width="100" height="50" fill="red"/></clipPath></defs>
        <rect id="bg" x="10" y="20" width="100" height="50" fill="#fff"/>
        <rect id="pct" x="10" y="20" width="100%" height="100%" style="fill: #eee"/>
        <rect id="frame" x="10" y="20" width="100" height="50" fill="#fff" stroke="#000"/>
        <rect id="none" x="10" y="20" width="100" height="50" fill="none"/>
        <rect id="classed" x="10" y="20" width="100" height="50" class="frame" fill="#fff"/>
        <rect id="part" x="30" y="30" width="20" height="10" fill="#000"/>
      </svg>
    SVG

    stripped = T.strip_background(svg)

    refute_includes stripped, 'id="bg"'
    refute_includes stripped, 'id="pct"'
    %w[frame none classed part].each { assert_includes stripped, %(id="#{it}") }
    assert_includes stripped, '<clipPath id="c">'
  end

  # --- SVG の窓（§3.4） ---

  def test_should_rewrite_viewbox_relative_to_origin_and_keep_percent_width
    svg = %(<svg width="100%" viewBox="100 50 200 100" xmlns="http://www.w3.org/2000/svg"><g/></svg>)

    windowed = T.window_svg(svg, [100, 50, 200, 250])

    assert_includes windowed, '<svg width="100%" viewBox="150 60 140 70"'
    assert_includes windowed, '<g/>'
  end

  def test_should_shrink_absolute_size_with_viewbox
    svg = %(<svg width="600" height="400px" viewBox="0 0 600 400" xmlns="http://www.w3.org/2000/svg"/>)

    windowed = T.window_svg(svg, [250, 100, 250, 100])

    assert_includes windowed, 'width="480" height="200px" viewBox="60 100 480 200"'
  end

  def test_should_derive_viewbox_from_absolute_size_when_missing
    windowed = T.window_svg(%(<svg width="200" height="100" xmlns="http://www.w3.org/2000/svg"/>), [0, 250, 0, 250])

    assert_includes windowed, 'viewBox="50 0 100 100"'
    assert_includes windowed, 'width="100"'
  end

  def test_should_give_up_svg_without_size
    assert_nil T.window_svg(%(<svg xmlns="http://www.w3.org/2000/svg"/>), [10, 10, 10, 10])
  end

  # --- 段落に単独で置いた画像（§3.4・§3.7・§4） ---

  def test_should_trim_svg_by_rewriting_viewbox_copy
    in_project do
      File.write('images/11-workflow/workflow.svg', WORKFLOW_SVG)
      line = "![](#{Common.asset_prefix}images/11-workflow/workflow.svg){trim=on}"

      framed = T.framed_image(line, chapter_slug: '11-workflow', source_filename: '11-workflow.md',
                                    tools: BoxTools.new(WORKFLOW_BOX))

      assert_match %r{\Aimages/trim/11-workflow/\h{16}\.svg\z}, framed[:svg]
      assert_path_exists framed[:source]
      written = File.read(File.join(Common::BUILD_HTML_DIR, framed[:svg]))
      assert_includes written, %(viewBox="28.82 18.62 587.68 572.63") # 絵 40.12〜605.2 の周りに 11.3（幅の 2%）
      assert_includes written, '<text x="40" y="40">ラベル</text>'
      assert_equal WORKFLOW_SVG, File.read('images/11-workflow/workflow.svg') # 原本は変えない
    end
  end

  # SVG の crop は PNG に焼かず viewBox を書き換える。値を書き換えるだけなので外部ツールは要らない
  def test_should_crop_svg_by_viewbox_without_tools
    in_project do
      File.write('images/11-workflow/workflow.svg', WORKFLOW_SVG)
      line = "![](#{Common.asset_prefix}images/11-workflow/workflow.svg){crop=\"100 0 0 68px\"}"

      framed = T.framed_image(line, chapter_slug: '11-workflow', source_filename: '11-workflow.md', tools: NoTools.new)

      written = File.read(File.join(Common::BUILD_HTML_DIR, framed[:svg]))
      assert_includes written, 'viewBox="68 60 612 540"'
    end
  end

  def test_should_keep_original_when_nothing_to_trim
    in_project do
      File.write('images/11-workflow/full.svg', WORKFLOW_SVG)
      line = "![](#{Common.asset_prefix}images/11-workflow/full.svg){trim=on}"
      full = { width: 2000, height: 1765, x: 0, y: 0, w: 2000, h: 1765 }

      assert_nil T.framed_image(line, chapter_slug: '11-workflow', source_filename: '11-workflow.md',
                                      tools: BoxTools.new(full))
    end
  end

  def test_should_warn_and_keep_original_for_single_color_image
    in_project do
      File.write('images/11-workflow/blank.svg', WORKFLOW_SVG)
      line = "![](#{Common.asset_prefix}images/11-workflow/blank.svg){trim=on}"
      blank = { width: 50, height: 40, x: 50, y: 40, w: 0, h: 0 }

      framed = nil
      log = capture_log do
        framed = T.framed_image(line, chapter_slug: '11-workflow', source_filename: '11-workflow.md',
                                      tools: BoxTools.new(blank))
      end

      assert_nil framed
      assert(log.any? { it.include?('blank.svg は一色だけの画像') })
    end
  end

  def test_should_not_trim_without_tools
    in_project do
      File.write('images/11-workflow/workflow.svg', WORKFLOW_SVG)
      line = "![](#{Common.asset_prefix}images/11-workflow/workflow.svg){trim=on}"

      framed = nil
      log = capture_log do
        framed = T.framed_image(line, chapter_slug: '11-workflow', source_filename: '11-workflow.md',
                                      tools: NoTools.new)
      end

      assert_nil framed
      assert(log.any? { it.include?('vs doctor --fix') })
    end
  end

  def test_should_ignore_images_without_crop_or_trim
    assert_nil T.framed_image('![](a.svg){trim=off width=50%}', chapter_slug: 'x', source_filename: 'x.md',
                                                                  tools: NoTools.new)
  end

  # --- 余白の多い画像を知らせる（§5） ---

  def hints_for(content, box)
    T.reset_hints!
    T.note_hint_candidates(content, chapter: '11-workflow.md')
    capture_log { T.report_hints!(tools: BoxTools.new(box)) }
  ensure
    T.reset_hints!
  end

  def test_should_hint_wide_margin_image_with_before_and_after
    in_project do
      File.write('images/11-workflow/workflow.svg', WORKFLOW_SVG)

      log = hints_for("本文\n\n![](workflow.svg){width=80%}\n\n![](workflow.svg)\n", WORKFLOW_BOX)

      assert_equal 3, log.size
      assert_equal '🟡 11-workflow.md:3 - workflow.svg は、絵が画像の幅の 83% しか使っていません。' \
                   '余白を詰めると約 1.16 倍で載ります（ほか 1 か所）', log[0]
      assert_includes log[1], '→ ![](workflow.svg){width=80%} を ![](workflow.svg){width=80% trim=on} に直してください。'
      assert_includes log[2], '{trim=off}'
    end
  end

  def test_should_not_hint_images_already_decided_or_not_trimmable
    in_project do
      File.write('images/11-workflow/workflow.svg', WORKFLOW_SVG)
      content = <<~MD
        ![](workflow.svg){trim=off}

        ![](workflow.svg){crop="10"}

        文中の ![](workflow.svg) 画像

        :::{.book-card}
        ![](workflow.svg)
        **書名**
        :::

        ```markdown
        ![](workflow.svg)
        ```

        ![](missing.svg)
      MD

      assert_empty hints_for(content, WORKFLOW_BOX)
    end
  end

  def test_should_not_hint_images_using_most_of_width
    in_project do
      File.write('images/11-workflow/workflow.svg', WORKFLOW_SVG)
      tight = { width: 2000, height: 1765, x: 100, y: 88, w: 1800, h: 1618 } # 90%

      assert_empty hints_for("![](workflow.svg)\n", tight)
    end
  end

  # 🟡 として preflight の件数に数える（終了コードは変えない）。build でも同じものが出る
  def test_should_record_wide_margin_as_warning
    registry = VivlioStarter::CLI::PreProcessCommands::IssueRegistry
    in_project do
      File.write('images/11-workflow/workflow.svg', WORKFLOW_SVG)
      registry.reset!

      hints_for("![](workflow.svg)\n", WORKFLOW_BOX)

      assert_equal [['11-workflow', 1, :warn, :image]], # 章の名前は .md を外して記録される
                   registry.issues.map { [it.chapter, it.line, it.severity, it.category] }
    end
  ensure
    registry.reset!
  end

  # 章の前処理の最初に、前回のビルドの候補を捨てる
  def test_should_forget_candidates_on_reset
    in_project do
      File.write('images/11-workflow/workflow.svg', WORKFLOW_SVG)
      T.note_hint_candidates("![](workflow.svg)\n", chapter: '11-workflow.md')
      T.reset_hints!

      assert_empty capture_log { T.report_hints!(tools: BoxTools.new(WORKFLOW_BOX)) }
    end
  end
end

# showcase の中の trim=on は、測った値の crop に置き換わる（image-trim-spec.md §3.5・§3.6）
class ShowcaseTrimTest < Minitest::Test
  ST = VivlioStarter::CLI::PreProcessCommands::ShowcaseTransformer
  T = VivlioStarter::CLI::PreProcessCommands::ImageTrimmer
  Builder = VivlioStarter::CLI::PreProcessCommands::ShowcaseSvgBuilder
  MEASURED = T::Measurement.new(crop: [10.0, 20.0, 30.0, 40.0], usage: 0.9)

  def block_and_image(line)
    lines = ["#{line}\n", "rect:1 100, 100, 200, 200\n"]
    [Builder.parse(lines, orig_w: 400, orig_h: 200), Builder.scan_image(lines)]
  end

  def test_should_replace_crop_with_measured_value
    block, image = block_and_image('![](a.webp){trim=on}')

    trimmed = T.stub(:measure, MEASURED) { ST.trimmed_block(block, image, 'a.webp', 'x.md') }

    assert_equal [10.0, 20.0, 30.0, 40.0], trimmed.crop
    assert_equal block.annotations, trimmed.annotations
  end

  def test_should_prefer_crop_when_both_are_written
    block, image = block_and_image('![](a.webp){crop="50" trim=on}')

    trimmed = T.stub(:measure, ->(*) { raise '測らないはず' }) { ST.trimmed_block(block, image, 'a.webp', 'x.md') }

    assert_equal [50.0, 50.0, 50.0, 50.0], trimmed.crop
  end
end

# 段落に単独で置いた SVG は、詰めた SVG を指し、PDF の書体の差し替えの入口（data-vs-source）を持つ
class CrossReferenceTrimmedSvgTest < Minitest::Test
  XR = VivlioStarter::CLI::PreProcessCommands::CrossReferenceProcessor
  T = VivlioStarter::CLI::PreProcessCommands::ImageTrimmer

  def test_should_emit_trimmed_svg_without_cropped_class
    framed = { svg: 'images/trim/11-workflow/k.svg', source: '.cache/vs/trim/k.svg' }

    out = T.stub(:framed_image, framed) do
      XR.transform_captioned_blocks("![流れ](workflow.svg){trim=on}\n", '11-workflow.md', {})
    end

    assert_includes out, '<img src="images/trim/11-workflow/k.svg" data-vs-source=".cache/vs/trim/k.svg" alt="流れ">'
    refute_includes out, 'vs-cropped'
  end

  def test_should_not_frame_trim_off
    out = T.stub(:framed_image, ->(*) { raise '呼ばれないはず' }) do
      XR.transform_captioned_blocks("![流れ](workflow.svg){trim=off}\n", '11-workflow.md', {})
    end

    assert_includes out, '<img src="workflow.svg" alt="流れ">'
  end
end

# 前処理の点検は原稿そのままの行番号で知らせる（image-trim-spec.md §3.6）
class MarkdownPreprocessorTrimValidationTest < Minitest::Test
  MP = VivlioStarter::CLI::PreProcessCommands::MarkdownPreprocessor
  Common = VivlioStarter::CLI::Common

  def warnings_for(content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, '11-workflow.md')
      File.write(path, content)
      entry = Data.define(:kind, :number).new(kind: :chapter, number: 11)
      preprocessor = MP.new(path, entry)
      lines = []
      Common.with_emit_sink(lines) { preprocessor.send(:validate_image_trims!) }
      lines
    end
  end

  def test_should_warn_invalid_trim_value
    log = warnings_for("本文\n\n![](a.svg){trim=yes}\n")

    assert(log.any? { it.include?('11-workflow.md:3 - 画像の trim の値が不正です（trim=yes）') })
  end

  def test_should_warn_crop_with_trim_and_show_crop_only_form
    log = warnings_for(%(![](a.webp){width=50% crop="30 100" trim=on}\n))

    assert(log.any? { it.include?('11-workflow.md:1 - 画像に crop と trim=on の両方があります') })
    assert(log.any? { it.include?('→ 切り抜く範囲を自分で決めるなら trim=on を消してください: ![](a.webp){width=50% crop="30 100"}') })
  end

  def test_should_accept_trim_on_and_off
    assert_empty warnings_for("![](a.svg){trim=on}\n\n![](b.svg){trim=off}\n\n`![](c.svg){trim=bad}`\n")
  end
end

# EPUB には data-vs-source（ビルド機のパス）を持ち込まない
class EpubStageDropsTrimSourceTest < Minitest::Test
  EB = VivlioStarter::CLI::Build::EpubBuilder
  Common = VivlioStarter::CLI::Common

  def test_should_strip_data_vs_source_when_staging
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p(Common::BUILD_HTML_DIR)
        File.write(File.join(Common::BUILD_HTML_DIR, '11-workflow.html'),
                   '<img src="images/trim/11-workflow/k.svg" data-vs-source=".cache/vs/trim/k.svg" alt="流れ">')

        EB.stage_consumer_htmls!('epub')

        assert_equal '<img src="images/trim/11-workflow/k.svg" alt="流れ">', File.read('epub/11-workflow.html')
      end
    end
  end
end
