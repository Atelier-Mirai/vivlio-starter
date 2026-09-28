# frozen_string_literal: true

# ================================================================
# Test: cross_reference_processor_test.rb
# ================================================================
# 検証内容（at-directive-tier1-spec.md §2.1 / §2.4）:
#   - 見出しラベル `## タイトル @id` の収集（type :sec）と変換（アンカー span 注入）
#   - @pageref:id の置換（class="cross-ref-link pageref"・リンク文言）
#   - generic @id 参照の :sec 分岐（ページ番号なしのタイトルリンク）
#   - 未定義 ID・裸 @pageref・予約語をラベルID に使った場合の 🔴
# ================================================================

require_relative '../../../test_helper'
require 'vivlio_starter/cli/loader'

class CrossReferenceHeadingLabelTest < Minitest::Test
  XR = VivlioStarter::CLI::PreProcessCommands::CrossReferenceProcessor

  # --- 収集 ---

  def test_should_collect_heading_label_as_sec_type
    content = <<~MD
      # 第1章

      ## インストール @install

      本文。
    MD

    result = XR.collect_labels(content, '11-install.md', '1')
    label = result[:labels].find { it.id == 'install' }

    assert_equal :sec, label.type
    assert_equal 'インストール', label.title
    assert_equal '1', label.chapter
    assert_equal 3, label.line
    refute label.auto
  end

  # コードブロック内の見出し風の行はラベルにしない（Masking へ委譲していることの確認）
  def test_should_not_collect_heading_label_inside_code_fence
    content = <<~MD
      ```markdown
      ## インストール @install
      ```
    MD

    result = XR.collect_labels(content, '11-install.md', '1')

    assert_empty result[:labels]
  end

  # 予約マクロ名は ラベルID に使えない（使うとマクロ展開と参照が衝突する）
  def test_should_reject_reserved_macro_id_as_label
    content = "## 版数について @version\n"

    result = nil
    out, = capture_io { result = XR.collect_labels(content, '11-install.md', '1') }

    assert_empty result[:labels]
    assert_match(/予約語/, out)
    assert_match(/version/, out)
  end

  # 自動採番の @auto は予約 *ID* であって予約マクロではないので弾かない
  def test_should_still_allow_auto_numbering_id_on_caption
    content = <<~MD
      ** サンプル画像 @auto **

      ![図](images/a.png)
    MD

    result = XR.collect_labels(content, '21-images.md', '11')

    assert_equal 1, result[:labels].size
    assert result[:labels].first.auto
  end

  # --- 変換 ---

  def test_should_strip_heading_label_and_inject_anchor_span
    content = "## インストール @install\n\n本文。\n"

    out = XR.transform_captioned_blocks(content, '11-install.md', {})

    assert_includes out, '## インストール <span id="install" class="vs-sec-anchor"></span>'
    refute_includes out, '@install'
  end
end

class CrossReferencePagerefTest < Minitest::Test
  XR = VivlioStarter::CLI::PreProcessCommands::CrossReferenceProcessor

  def labels_map
    {
      'install' => XR::Label.new('install', :sec, '1', '1', 'インストール', '11-install.md', 3, false),
      'fig-flow' => XR::Label.new('fig-flow', :fig, '11', '11-2', '処理の流れ', '21-images.md', 40, false)
    }
  end

  def test_should_replace_pageref_with_pageref_class_link
    result = XR.replace_references("詳しくは @pageref:install を参照。\n", labels_map, '31-usage.md')

    assert_includes result[:content], '<a href="11-install.html#install" class="cross-ref-link pageref">'
    assert_includes result[:content], '「インストール」</a>'
    assert_empty result[:errors]
    assert_includes result[:used_ids], 'install'
  end

  # 図・表・リストのラベルへの @pageref は従来の「図 11-2」形式のまま
  def test_should_use_full_number_text_for_caption_label_pageref
    result = XR.replace_references("@pageref:fig-flow を参照。\n", labels_map, '31-usage.md')

    assert_includes result[:content], 'class="cross-ref-link pageref">図 11-2</a>'
  end

  # generic @id 参照（ページ番号なし）も見出しラベルならタイトルリンクになる
  def test_should_render_sec_label_as_title_link_for_generic_reference
    result = XR.replace_references("@install を参照。\n", labels_map, '31-usage.md')

    assert_includes result[:content], '<a href="11-install.html#install" class="cross-ref-link">「インストール」</a>'
    refute_includes result[:content], 'pageref'
  end

  def test_should_report_undefined_pageref_and_pass_through
    result = XR.replace_references("@pageref:zzz を参照。\n", labels_map, '31-usage.md')

    assert_includes result[:content], '@pageref:zzz'
    assert_equal 1, result[:errors].size
    assert_match(/未定義のラベルID: @pageref:zzz/, result[:errors].first)
  end

  # 引数を書き忘れた裸の @pageref は書式例つきで指摘する
  def test_should_report_bare_pageref_with_example
    result = XR.replace_references("詳しくは @pageref を参照。\n", labels_map, '31-usage.md')

    assert_includes result[:content], '@pageref'
    assert_equal 1, result[:errors].size
    assert_match(/@pageref:install/, result[:errors].first)
  end

  # 定義行そのもの（`## タイトル @id`）は参照として数えない（孤立ラベル検出の前提）
  def test_should_not_count_heading_definition_line_as_reference
    result = XR.replace_references("## インストール @install\n", labels_map, '11-install.md')

    assert_empty result[:used_ids]
    assert_includes result[:content], '## インストール @install'
  end

  # コードブロック内の @pageref は置換しない
  def test_should_not_replace_pageref_inside_code_fence
    content = "```markdown\n@pageref:install\n```\n"

    result = XR.replace_references(content, labels_map, '31-usage.md')

    assert_includes result[:content], '@pageref:install'
    refute_includes result[:content], '<a href'
  end
end

# 単独で置いた画像の幅は、% のほかに CSS の長さも受け付ける（改善案.md #55）
class CrossReferenceImageWidthTest < Minitest::Test
  XR = VivlioStarter::CLI::PreProcessCommands::CrossReferenceProcessor

  def figure_for(attributes)
    XR.transform_captioned_blocks("本文\n\n![a](a.webp){#{attributes}}\n", '11-install.md', {})[/<figure[^>]*>/]
  end

  def test_should_accept_percentage_and_css_lengths
    assert_equal '<figure style="width: 30%">', figure_for('width=30%')
    assert_equal '<figure style="width: 2em">', figure_for('width=2em')
    assert_equal '<figure class="align-right" style="width: 40mm">', figure_for('width=40mm align=right')
    assert_equal '<figure style="width: 12.5rem">', figure_for('width="12.5rem"')
  end

  # 単位のない整数は、HTML の width 属性の意味どおり px とみなす
  def test_should_treat_bare_integer_as_pixels
    assert_equal '<figure style="width: 300px">', figure_for('width=300')
  end

  # 幅として読めない値は付けない（既定の大きさ）
  def test_should_ignore_unreadable_width
    assert_equal '<figure>', figure_for('width=big')
    assert_equal '<figure>', figure_for('max-width=30%')
  end
end

# crop を付けた普通の画像は、図の組み立てで画像だけを切り抜いた SVG／ラスターへ差し替える。
# キャプション・図番号・align・border・幅は普通の図のまま引き継ぐ（改善案.md #54）
class CrossReferenceCroppedImageTest < Minitest::Test
  XR = VivlioStarter::CLI::PreProcessCommands::CrossReferenceProcessor
  ST = VivlioStarter::CLI::PreProcessCommands::ShowcaseTransformer
  ASSETS = ['images/showcase/11-install/k.svg', 'images/showcase/11-install/k.jpg'].freeze

  # crop_assets に渡った画像の行を集めつつ、生成物の参照を返す
  def transform(content, assets: ASSETS)
    calls = []
    out = ST.stub(:crop_assets, lambda { |line, chapter_slug:, source_filename:|
      calls << [line, chapter_slug, source_filename]
      assets
    }) do
      XR.transform_captioned_blocks(content, '11-install.md', {})
    end
    [out, calls]
  end

  def test_should_swap_image_for_cropped_assets_and_keep_figure_attributes
    out, calls = transform(%(本文\n\n![肖像](a.webp){width=40% align=right crop="30 100" .vs-borderless}\n))

    assert_includes out, '<figure class="align-right vs-borderless" style="width: 40%">'
    assert_includes out, '<img class="vs-cropped" src="images/showcase/11-install/k.svg" ' \
                         'data-vs-raster="images/showcase/11-install/k.jpg" alt="肖像">'
    assert_equal [[%(![肖像](a.webp){width=40% align=right crop="30 100" .vs-borderless}), '11-install', '11-install.md']],
                 calls
  end

  def test_should_keep_caption_on_cropped_image
    out, = transform(%(** アインシュタインの肖像 **\n\n![肖像](a.webp){crop="50"}\n))

    assert_includes out, '<figcaption>アインシュタインの肖像</figcaption>'
    assert_includes out, 'class="vs-cropped"'
  end

  # 切り抜けなければ元の画像のまま出す（警告は ShowcaseTransformer が出す）
  def test_should_fall_back_to_original_image_when_cropping_fails
    out, = transform(%(![肖像](a.webp){crop="50"}\n), assets: nil)

    assert_includes out, '<img src="a.webp" alt="肖像">'
  end

  def test_should_not_call_crop_for_images_without_crop
    _out, calls = transform("![肖像](a.webp){width=40%}\n")

    assert_empty calls
  end
end

# showcase（図解注釈）の直前のキャプションで、図番号とキャプションを付ける（改善案.md #58）。
# 図番号を振る時点で showcase はすでに <figure class="vs-showcase"> の HTML になっている
class CrossReferenceShowcaseCaptionTest < Minitest::Test
  XR = VivlioStarter::CLI::PreProcessCommands::CrossReferenceProcessor

  SHOWCASE = <<~HTML


    <figure class="vs-showcase">
    <img class="vs-showcase" src="images/showcase/11-install/k.svg" data-vs-raster="images/showcase/11-install/k.png" alt="画面" style="width: 100%;">
    </figure>

  HTML

  def test_should_number_and_caption_showcase_with_label
    content = "** 設定画面 @fig-settings **\n#{SHOWCASE}本文は @fig-settings を参照します。\n"
    labels = XR.collect_labels(content, '11-install.md', '1')[:labels]
    labels_map = XR.build_labels_map_with_duplicates_check(labels)[:labels_map]

    out = XR.transform_captioned_blocks(content, '11-install.md', labels_map)

    assert_equal 1, labels.size
    assert_equal :fig, labels.first.type
    assert_includes out, '<figure id="fig-settings" class="vs-showcase">'
    assert_includes out, "<figcaption>図 1-1: 設定画面</figcaption>\n</figure>"
    assert_includes out, 'data-vs-raster="images/showcase/11-install/k.png"', '合成画像はそのまま'
    refute_includes out, '** 設定画面'
  end

  def test_should_caption_showcase_without_label
    out = XR.transform_captioned_blocks("** 設定画面 **\n#{SHOWCASE}", '11-install.md', {})

    assert_includes out, '<figure class="vs-showcase">'
    assert_includes out, "<figcaption>設定画面</figcaption>\n</figure>"
    assert_equal 1, out.scan('</figure>').size
  end

  def test_should_leave_showcase_without_caption_untouched
    content = "本文\n#{SHOWCASE}"

    assert_equal content, XR.transform_captioned_blocks(content, '11-install.md', {})
  end
end
