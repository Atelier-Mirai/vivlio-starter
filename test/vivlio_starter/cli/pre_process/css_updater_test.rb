# frozen_string_literal: true

# ================================================================
# Test: css_updater_test.rb
# ================================================================
# 検証内容:
#   - format_font_value: :font 変数へ generic フォールバックを付与する
#     （明朝=serif / ゴシック=sans-serif / コード=monospace）。
#     フォント非埋め込み EPUB でも category がリーダー側で保たれることの担保。
#   - update_theme_css: theme.style: simple/image による扉絵・飾り画像の
#     CSS変数切り替え（42-frontispiece.md の記載どおりの挙動か）。
#   - update_chapter_css: chapter.css のヘッダー import 切り替え。
#   - update_chapter_common_css: markers.h3/h4 未設定時の既定記号（♣/♦）。
# ================================================================

require_relative '../../../test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/pre_process/css_updater'

class CssUpdaterFontValueTest < Minitest::Test
  CU = VivlioStarter::CLI::PreProcessCommands::CssUpdater

  # 本文（明朝）は Type3 回避フォールバック（HackGen35 Console NF）＋ serif が付く
  def test_should_append_serif_for_main_text
    assert_equal '"Zen Old Mincho", "HackGen35 Console NF", serif',
                 CU.format_font_value('--font-main-text', 'Zen Old Mincho', :font)
  end

  # コードは Type3 回避フォールバックの本体（HackGen35 Console NF）のため挿入せず、monospace のみ付く
  def test_should_append_monospace_for_code
    assert_equal '"HackGen35 Console NF", monospace',
                 CU.format_font_value('--font-code', 'HackGen35 Console NF', :font)
  end

  # 見出し・コラム・ノンブル（ゴシック系）は Type3 回避フォールバック＋ sans-serif が付く
  def test_should_append_sans_serif_for_gothic_variables
    assert_equal '"Zen Kaku Gothic New", "HackGen35 Console NF", sans-serif',
                 CU.format_font_value('--font-header', 'Zen Kaku Gothic New', :font)
    assert_equal '"Zen Maru Gothic", "HackGen35 Console NF", sans-serif',
                 CU.format_font_value('--font-column', 'Zen Maru Gothic', :font)
  end

  # book.yml 側で既にフォールバックを指定済み（カンマ含む）なら尊重して触らない
  def test_should_respect_existing_fallback_chain
    value = '"My Font", serif'
    assert_equal value, CU.format_font_value('--font-main-text', value, :font)
  end

  # :font 以外（kind が nil）の値はそのまま返す
  def test_should_not_touch_non_font_values
    assert_equal '210mm', CU.format_font_value('--page-width', '210mm', nil)
  end
end

# theme.style: simple/image による扉絵・飾り画像の CSS 変数切り替えを検証
class CssUpdaterThemeStyleTest < Minitest::Test
  CU = VivlioStarter::CLI::PreProcessCommands::CssUpdater

  def setup
    @tmpdir = Dir.mktmpdir
    @original_dir = Dir.pwd
    Dir.chdir(@tmpdir)
    FileUtils.mkdir_p('stylesheets')
    File.write(theme_css_path, <<~CSS)
      :root {
        --theme-accent: yellow;
        --color-strong: red;
        --color-em-underline: red;
        --section-bg-image: url("images/frame-yellow.webp");
        --frontispiece-image: url("images/door2.webp");
        --frontispiece-padding: 0mm;
      }
    CSS
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tmpdir)
  end

  # theme.style: simple のとき、frontispiece/ornament の指定内容に関わらず
  # 両方の画像変数が none になることを確認
  def test_simple_style_disables_both_image_variables
    CU.update_theme_css(
      theme_name: 'blue',
      theme_accent_value: 'var(--accent-blue)',
      theme_style: 'simple',
      frontispiece_path: 'images/sakura_portrait.webp',
      door_padding_value: '10mm',
      ornament_path: 'images/sakura_landscape.webp'
    )

    css = File.read(theme_css_path)
    assert_match(/--section-bg-image:\s*none\s*;/, css)
    assert_match(/--frontispiece-image:\s*none\s*;/, css)
  end

  # theme.style: image のとき、指定した frontispiece/ornament のパスと padding が反映されることを確認
  def test_image_style_applies_frontispiece_and_ornament_paths
    CU.update_theme_css(
      theme_name: 'blue',
      theme_accent_value: 'var(--accent-blue)',
      theme_style: 'image',
      frontispiece_path: 'images/sakura_portrait.webp',
      door_padding_value: '10mm',
      ornament_path: 'images/sakura_landscape.webp'
    )

    css = File.read(theme_css_path)
    assert_match(%r{--frontispiece-image:\s*url\("images/sakura_portrait\.webp"\)\s*;}, css)
    assert_match(%r{--section-bg-image:\s*url\("images/sakura_landscape\.webp"\)\s*;}, css)
    assert_match(/--frontispiece-padding:\s*10mm\s*;/, css)
  end

  private

  def theme_css_path = File.join('stylesheets', 'theme.css')
end

# chapter.css のヘッダー import が theme.style に連動して切り替わることを検証
class CssUpdaterChapterHeaderTest < Minitest::Test
  CU = VivlioStarter::CLI::PreProcessCommands::CssUpdater

  def setup
    @tmpdir = Dir.mktmpdir
    @original_dir = Dir.pwd
    Dir.chdir(@tmpdir)
    FileUtils.mkdir_p('stylesheets')
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tmpdir)
  end

  # theme.style: image のとき、import が image-header.css に切り替わることを確認
  def test_switches_header_import_to_image
    File.write(chapter_css_path, "@import url(\"simple-header.css\");\n")

    CU.update_chapter_css(theme_style: 'image')

    assert_match(/@import url\("image-header\.css"\);/, File.read(chapter_css_path))
  end

  # theme.style: simple のとき、import が simple-header.css に切り替わることを確認
  def test_switches_header_import_to_simple
    File.write(chapter_css_path, "@import url(\"image-header.css\");\n")

    CU.update_chapter_css(theme_style: 'simple')

    assert_match(/@import url\("simple-header\.css"\);/, File.read(chapter_css_path))
  end

  private

  def chapter_css_path = File.join('stylesheets', 'chapter.css')
end

# markers.h3/h4 未設定時の既定記号（♣/♦）と、カスタム指定時の反映を検証
class CssUpdaterMarkersTest < Minitest::Test
  CU = VivlioStarter::CLI::PreProcessCommands::CssUpdater

  def setup
    @tmpdir = Dir.mktmpdir
    @original_dir = Dir.pwd
    Dir.chdir(@tmpdir)
    FileUtils.mkdir_p('stylesheets')
    File.write(chapter_common_css_path, <<~CSS)
      :root {
        --h3-marker: "?";
        --h4-marker: "?";
      }
    CSS
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tmpdir)
  end

  # markers が空Hash（未設定）の場合、既定のトランプ記号（♣/♦）が使われることを確認
  def test_uses_default_markers_when_unset
    CU.update_chapter_common_css(markers: {})

    css = File.read(chapter_common_css_path)
    assert_match(/--h3-marker:\s*"♣"\s*;/, css)
    assert_match(/--h4-marker:\s*"♦"\s*;/, css)
  end

  # markers.h3/h4 を指定した場合、その記号が反映されることを確認
  def test_uses_custom_markers_when_set
    CU.update_chapter_common_css(markers: { h3: '★', h4: '☆' })

    css = File.read(chapter_common_css_path)
    assert_match(/--h3-marker:\s*"★"\s*;/, css)
    assert_match(/--h4-marker:\s*"☆"\s*;/, css)
  end

  private

  def chapter_common_css_path = File.join('stylesheets', 'chapter-common.css')
end
