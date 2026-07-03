# frozen_string_literal: true

# ================================================================
# Test: book_settings_css_test.rb
# ================================================================
# 検証内容（VivlioVerso 基盤整備 P3）:
#   BookSettingsCss 生成器が book.yml のビルド設定を .cache/vs/book-settings.css へ
#   全文書き出す。ここで確立する「変数名一覧」がテーマ互換の公開インターフェース
#   （第 2 部 §3.4）であり、それを網羅・整形・相対パス解決の観点で固定する。
#
#   - theme 系: theme.style（simple/image）による画像 2 変数と padding の条件付き宣言
#   - 画像 URL: .cache/vs/ 基準（../../stylesheets/）への組替。data:/http(s): は不変
#   - appendix/preface: appendix は未指定なら宣言しない、preface は常に宣言
#   - markers: 未指定は既定 ♣/♦、指定はその記号
#   - page 系 22 変数の網羅とフォントスタック整形（generic フォールバック）
#   - @page { size } はリテラル値
# ================================================================

require_relative '../../../test_helper'
require 'vivlio_starter/cli/loader'

class BookSettingsCssThemeTest < Minitest::Test
  BSC = VivlioStarter::CLI::PreProcessCommands::BookSettingsCss
  PREFIX = '../../stylesheets/'

  # theme.style: simple では画像 2 変数を none にし、padding は宣言しない
  def test_should_disable_images_and_omit_padding_for_simple_style
    settings = {
      theme_accent_value: 'var(--accent-blue)', theme_style: 'simple',
      ornament_path: 'images/bundled/sakura_landscape.webp',
      frontispiece_path: 'images/bundled/sakura_portrait.webp',
      door_padding_value: '10mm', heading_width_value: nil, lead_width_value: nil
    }

    lines = BSC.theme_declarations(settings, image_prefix: PREFIX)

    assert_includes lines, '--section-bg-image: none;'
    assert_includes lines, '--frontispiece-image: none;'
    refute(lines.any? { it.start_with?('--frontispiece-padding:') })
  end

  # theme.style: image では画像 URL を .cache/vs/ 基準へ組み替え、padding と幅も宣言する
  def test_should_emit_rebased_urls_and_padding_for_image_style
    settings = {
      theme_accent_value: 'var(--accent-yellow)', theme_style: 'image',
      ornament_path: 'images/bundled/sakura_landscape.webp',
      frontispiece_path: 'images/bundled/sakura_portrait.webp',
      door_padding_value: '10mm', heading_width_value: '108mm', lead_width_value: '88mm'
    }

    lines = BSC.theme_declarations(settings, image_prefix: PREFIX)

    assert_includes lines, '--section-bg-image: url("../../stylesheets/images/bundled/sakura_landscape.webp");'
    assert_includes lines, '--frontispiece-image: url("../../stylesheets/images/bundled/sakura_portrait.webp");'
    assert_includes lines, '--frontispiece-padding: 10mm;'
    assert_includes lines, '--frontispiece-heading-width: 108mm;'
    assert_includes lines, '--frontispiece-lead-width: 88mm;'
  end

  # heading_width / lead_width が nil のときはその行を宣言しない
  def test_should_omit_widths_when_nil
    settings = {
      theme_accent_value: 'var(--accent-yellow)', theme_style: 'image',
      ornament_path: 'images/x_landscape.webp', frontispiece_path: 'images/x_portrait.webp',
      door_padding_value: '0mm', heading_width_value: nil, lead_width_value: nil
    }

    lines = BSC.theme_declarations(settings, image_prefix: PREFIX)

    refute(lines.any? { it.start_with?('--frontispiece-heading-width:') })
    refute(lines.any? { it.start_with?('--frontispiece-lead-width:') })
  end

  # theme accent と強調色は常に宣言される
  def test_should_always_declare_accent_and_strong_colors
    settings = {
      theme_accent_value: '#123456', theme_style: 'simple',
      ornament_path: nil, frontispiece_path: nil,
      door_padding_value: '0mm', heading_width_value: nil, lead_width_value: nil
    }

    lines = BSC.theme_declarations(settings, image_prefix: PREFIX)

    assert_includes lines, '--theme-accent: #123456;'
    assert_includes lines, '--color-strong: var(--theme-accent);'
    assert_includes lines, '--color-em-underline: var(--theme-accent);'
  end
end

class BookSettingsCssUrlRebaseTest < Minitest::Test
  BSC = VivlioStarter::CLI::PreProcessCommands::BookSettingsCss
  PREFIX = '../../stylesheets/'

  # 素の相対パスは接頭辞で組み替えて url() 化する
  def test_should_rebase_bare_relative_path
    assert_equal 'url("../../stylesheets/images/bundled/x.webp")',
                 BSC.css_image_value('images/bundled/x.webp', image_prefix: PREFIX)
  end

  # url("...") 指定は内側の相対を組み替える
  def test_should_rebase_inner_of_url_form
    assert_equal 'url("../../stylesheets/images/custom.webp")',
                 BSC.css_image_value('url("images/custom.webp")', image_prefix: PREFIX)
  end

  # data: URI と http(s): は組み替えない
  def test_should_not_rebase_data_uri_or_external_url
    assert_equal 'url("data:image/svg+xml;base64,AAAA")',
                 BSC.css_image_value('url("data:image/svg+xml;base64,AAAA")', image_prefix: PREFIX)
    assert_equal 'url("https://example.com/a.webp")',
                 BSC.css_image_value('https://example.com/a.webp', image_prefix: PREFIX)
  end

  # none はそのまま
  def test_should_pass_through_none
    assert_equal 'none', BSC.css_image_value('none', image_prefix: PREFIX)
  end

  # 既に組替済みのパスは二重に組み替えない（冪等）
  def test_should_be_idempotent_for_already_rebased_path
    assert_equal 'url("../../stylesheets/images/x.webp")',
                 BSC.css_image_value('../../stylesheets/images/x.webp', image_prefix: PREFIX)
  end
end

class BookSettingsCssSupplementalTest < Minitest::Test
  BSC = VivlioStarter::CLI::PreProcessCommands::BookSettingsCss
  ThemeDouble = Data.define(:appendix_color, :preface_color)
  CfgDouble = Data.define(:theme)

  # appendix_color 未指定なら --appendix-accent-color は宣言せず、preface は常に宣言する
  def test_should_omit_appendix_when_unset_but_always_declare_preface
    cfg = CfgDouble.new(theme: ThemeDouble.new(appendix_color: '', preface_color: ''))
    settings = { theme_accent_value: 'var(--accent-yellow)' }

    lines = BSC.supplemental_color_declarations(settings, cfg)

    refute(lines.any? { it.start_with?('--appendix-accent-color:') })
    assert_includes lines, '--color-preface-accent: var(--accent-yellow);'
  end

  # appendix_color / preface_color を指定すればその色（色名→var(--accent-*)）を宣言する
  def test_should_declare_configured_appendix_and_preface_colors
    cfg = CfgDouble.new(theme: ThemeDouble.new(appendix_color: 'red', preface_color: 'indigo'))
    settings = { theme_accent_value: 'var(--accent-yellow)' }

    lines = BSC.supplemental_color_declarations(settings, cfg)

    assert_includes lines, '--appendix-accent-color: var(--accent-red);'
    assert_includes lines, '--color-preface-accent: var(--accent-indigo);'
  end
end

class BookSettingsCssMarkerTest < Minitest::Test
  BSC = VivlioStarter::CLI::PreProcessCommands::BookSettingsCss
  ThemeDouble = Data.define(:markers)
  CfgDouble = Data.define(:theme)

  # markers 未指定なら既定のトランプ記号（♣/♦）
  def test_should_use_default_markers_when_unset
    cfg = CfgDouble.new(theme: ThemeDouble.new(markers: {}))

    lines = BSC.marker_declarations(cfg)

    assert_includes lines, '--h3-marker: "♣";'
    assert_includes lines, '--h4-marker: "♦";'
  end

  # markers.h3/h4 を指定すればその記号
  def test_should_use_custom_markers_when_set
    cfg = CfgDouble.new(theme: ThemeDouble.new(markers: { h3: '★', h4: '☆' }))

    lines = BSC.marker_declarations(cfg)

    assert_includes lines, '--h3-marker: "★";'
    assert_includes lines, '--h4-marker: "☆";'
  end
end

class BookSettingsCssPageTest < Minitest::Test
  BSC = VivlioStarter::CLI::PreProcessCommands::BookSettingsCss

  # @page { size } はリテラル値で出力する（var() は @page size 不可）
  def test_should_emit_literal_page_size
    assert_equal '@page { size: 182mm 232mm; }',
                 BSC.page_size_rule({ width: '182mm', height: '232mm' })
  end

  # width/height が空なら @page 規則を出さない
  def test_should_omit_page_rule_without_dimensions
    assert_equal '', BSC.page_size_rule({ width: '', height: '210mm' })
  end

  # nil/空値の変数は宣言しない（page-settings.css の既定がカスケードで生きる）
  def test_should_skip_nil_and_empty_page_variables
    page_cfg = { width: '148mm', height: nil, base_font_size: '', paper_scale: '0.7' }

    lines = BSC.page_declarations(page_cfg)

    assert_includes lines, '--page-width: 148mm;'
    assert_includes lines, '--paper-scale: 0.7;'
    refute(lines.any? { it.start_with?('--page-height:') })
    refute(lines.any? { it.start_with?('--base-font-size:') })
  end

  # :font 変数はフォントスタック整形（generic フォールバック）を通す
  def test_should_format_font_stack_for_font_variables
    page_cfg = { main_text_font: 'Zen Old Mincho' }

    lines = BSC.page_declarations(page_cfg)

    assert_includes lines, '--font-main-text: "Zen Old Mincho", "HackGen35 Console NF", serif;'
  end
end

# 実 book.yml（同梱プリセット）での全文生成が、テーマ互換の公開インターフェース
# となる変数一覧を網羅し、@page size と theme 変数を含むことを確認する統合テスト。
class BookSettingsCssRenderIntegrationTest < Minitest::Test
  BSC = VivlioStarter::CLI::PreProcessCommands::BookSettingsCss
  Common = VivlioStarter::CLI::Common

  PAGE_VARS = %w[
    --page-width --page-height --paper-scale --align-max-width
    --base-font-size --base-line-height --letter-spacing
    --page-margin-top --page-margin-bottom --page-margin-inner --page-margin-outer
    --frontispiece-binding-offset --column-font-size
    --font-main-text --font-header --font-code --font-column --font-folio
    --folio-center-content --folio-left-content --folio-right-content
  ].freeze

  THEME_VARS = %w[
    --theme-accent --color-strong --color-em-underline
    --frontispiece-image --section-bg-image --frontispiece-padding
    --color-preface-accent --h3-marker --h4-marker
  ].freeze

  def test_should_render_all_public_interface_variables_and_page_size
    css = BSC.render(Common::CONFIG)

    (PAGE_VARS + THEME_VARS).each do |var|
      assert_includes css, "#{var}:", "生成 CSS に #{var} が含まれること"
    end
    assert_match(/@page \{ size: \d+mm \d+mm; \}/, css)
  end
end
