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
