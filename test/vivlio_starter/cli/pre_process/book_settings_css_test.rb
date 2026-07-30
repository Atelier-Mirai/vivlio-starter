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
  Common = VivlioStarter::CLI::Common
  PREFIX = '../../stylesheets/'

  # theme.style: simple では画像 2 変数を none にし、edge_inset は宣言しない
  def test_should_disable_images_and_omit_edge_inset_for_simple_style
    settings = {
      theme_accent_value: 'var(--accent-blue)', theme_style: 'simple',
      ornament_path: 'images/bundled/sakura_landscape.webp',
      frontispiece_path: 'images/bundled/sakura_portrait.webp',
      edge_inset_value: '10mm', heading_chars_value: nil, lead_chars_value: nil
    }

    lines = BSC.theme_declarations(settings, image_prefix: PREFIX)

    assert_includes lines, '--section-bg-image: none;'
    assert_includes lines, '--frontispiece-image: none;'
    refute(lines.any? { it.start_with?('--frontispiece-edge-inset:') })
  end

  # theme.style: image では画像 URL を .cache/vs/ 基準へ組み替え、edge_inset と幅も宣言する
  def test_should_emit_rebased_urls_and_edge_inset_for_image_style
    settings = {
      theme_accent_value: 'var(--accent-yellow)', theme_style: 'image',
      ornament_path: 'images/bundled/sakura_landscape.webp',
      frontispiece_path: 'images/bundled/sakura_portrait.webp',
      edge_inset_value: '10mm', heading_chars_value: 8, lead_chars_value: 20
    }

    lines = BSC.theme_declarations(settings, image_prefix: PREFIX)

    assert_includes lines, '--section-bg-image: url("../../stylesheets/images/bundled/sakura_landscape.webp");'
    assert_includes lines, '--frontispiece-image: url("../../stylesheets/images/bundled/sakura_portrait.webp");'
    assert_includes lines, '--frontispiece-edge-inset: 10mm;'
    # 文字数 → リテラル mm 換算（A4・paper_scale 1.0: 章題 8 × 12.96mm / リード 20 × 4.445mm）
    assert_includes lines, '--frontispiece-heading-width: 103.68mm;'
    assert_includes lines, '--frontispiece-lead-width: 88.9mm;'
  end

  # heading_chars / lead_chars が nil のときはその行を宣言しない
  def test_should_omit_widths_when_nil
    settings = {
      theme_accent_value: 'var(--accent-yellow)', theme_style: 'image',
      ornament_path: 'images/x_landscape.webp', frontispiece_path: 'images/x_portrait.webp',
      edge_inset_value: '0mm', heading_chars_value: nil, lead_chars_value: nil
    }

    lines = BSC.theme_declarations(settings, image_prefix: PREFIX)

    refute(lines.any? { it.start_with?('--frontispiece-heading-width:') })
    refute(lines.any? { it.start_with?('--frontispiece-lead-width:') })
  end

  # --- 見出しの寸法（heading-metrics-spec §1-2） ---

  # 文字数は判型ごとの 1 字の送りでリテラル mm へ解かれる。
  # 「8 文字」がどの判型でも 8 文字になる（＝紙で意味が変わらない）ことが要点。
  def test_should_resolve_heading_chars_to_literal_mm_per_paper_size
    a4 = { width: '210mm', height: '297mm', margin_inner: '26mm', margin_outer: '22mm', paper_scale: 1.0 }
    a5 = { width: '148mm', height: '210mm', margin_inner: '22mm', margin_outer: '18mm', paper_scale: 0.7048 }

    # A4: font 48Q → 1 字 12.96mm / A5: font は下限 34Q → 1 字 9.18mm
    assert_in_delta 12.96, BSC.chapter_title_advance_mm(BSC.paper_scale_of(a4)), 0.01
    assert_in_delta 9.18, BSC.chapter_title_advance_mm(BSC.paper_scale_of(a5)), 0.01

    lines = BSC.heading_metric_declarations({ heading_chars_value: 8 }, a4)
    assert_includes lines, '--frontispiece-heading-width: 103.68mm;'
    lines = BSC.heading_metric_declarations({ heading_chars_value: 8 }, a5)
    assert_includes lines, '--frontispiece-heading-width: 73.44mm;'
  end

  # 節題は箱幅ではなくフォントサイズで字数を決める（帯は版面幅いっぱいで固定のため）。
  # 字数を減らすと字が大きくなる関係が保たれること。
  def test_should_resolve_ornament_chars_to_font_size_inversely
    a4 = { width: '210mm', height: '297mm', margin_inner: '26mm', margin_outer: '22mm', paper_scale: 1.0 }

    # 版面 162mm − 飾り避け 34mm = 128mm を字数で割る
    assert_includes BSC.heading_metric_declarations({ ornament_heading_chars_value: 14 }, a4),
                    '--section-title-font-size: 36.57Q;'
    assert_includes BSC.heading_metric_declarations({ ornament_heading_chars_value: 20 }, a4),
                    '--section-title-font-size: 25.6Q;'
    # 極端な指定は本文との階層が壊れるため 20〜48Q に収める
    assert_includes BSC.heading_metric_declarations({ ornament_heading_chars_value: 4 }, a4),
                    '--section-title-font-size: 48Q;'
    assert_includes BSC.heading_metric_declarations({ ornament_heading_chars_value: 40 }, a4),
                    '--section-title-font-size: 20Q;'
  end

  # 版面に収まらない字数は 🟡 で上限を示す（warning-messages-actionable の方針）
  def test_should_warn_when_heading_chars_exceed_text_area
    a5 = { width: '148mm', height: '210mm', margin_inner: '22mm', margin_outer: '18mm', paper_scale: 0.7048 }
    warnings = []
    Common.stub(:log_warn, ->(msg, **) { warnings << msg }) do
      BSC.heading_metric_declarations({ heading_chars_value: 16 }, a5)
    end

    # A5 の版面 108mm ÷ 1 字 9.18mm = 11 文字が上限
    assert_equal 1, warnings.size
    assert_includes warnings.first, 'theme.frontispiece.heading_chars: 16'
    assert_includes warnings.first, '最大 11 文字'
  end

  # 版面に収まる指定では警告を出さない（正常系を騒がせない）
  def test_should_not_warn_when_heading_chars_fit
    a4 = { width: '210mm', height: '297mm', margin_inner: '26mm', margin_outer: '22mm', paper_scale: 1.0 }
    warnings = []
    Common.stub(:log_warn, ->(msg, **) { warnings << msg }) do
      BSC.heading_metric_declarations({ heading_chars_value: 12, lead_chars_value: 24 }, a4)
    end

    assert_empty warnings
  end

  # theme accent と強調色は常に宣言される
  def test_should_always_declare_accent_and_strong_colors
    settings = {
      theme_accent_value: '#123456', theme_style: 'simple',
      ornament_path: nil, frontispiece_path: nil,
      edge_inset_value: '0mm', heading_chars_value: nil, lead_chars_value: nil
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

  # --- page.section_page_break（page-break-control-spec.md §2.2） ---

  # false のときだけ、h2 改ページの元セレクタ一式を打ち消す規則を出す
  def test_should_emit_section_page_break_negation_when_disabled
    css = BSC.section_page_break_rule({ section_page_break: false })

    assert_includes css, 'body.vs-header-image .section-topic h2'
    assert_includes css, 'body.vs-header-simple h2'
    assert_includes css, 'body.vs-header-simple.vs-kindle h2'
    assert_includes css, 'article.vs-section-topic-epub'
    assert_includes css, 'break-before: auto;'
    # Kindle KFX 用の legacy 併記も打ち消す
    assert_includes css, 'page-break-before: auto;'
  end

  # 章扉は @page :nth(1) の全面背景（扉絵）で成立するページなので、節の改ページを
  # 止めても最初の節だけは次ページから始める（pdf_h1.png）。PDF 限定。
  def test_should_keep_chapter_frontispiece_page_dedicated_when_disabled
    css = BSC.section_page_break_rule({ section_page_break: false })

    assert_includes css,
                    'body.vs-header-image:not(.vs-epub) section.level2:first-of-type > .section-topic h2'
    assert_includes css, 'break-before: page;'
    assert_includes css, 'page-break-before: always;'
  end

  # 既定（true）・未設定では何も出さず、テーマ CSS の改ページがそのまま生きる
  def test_should_emit_nothing_when_section_page_break_enabled
    assert_equal '', BSC.section_page_break_rule({ section_page_break: true })
    assert_equal '', BSC.section_page_break_rule({})
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

  # 両 style で必ず宣言される公開変数（--frontispiece-image / --section-bg-image は
  # simple では値が none になるが宣言自体は出る）。image 固有の --frontispiece-edge-inset は除く。
  THEME_VARS_COMMON = %w[
    --theme-accent --color-strong --color-em-underline
    --frontispiece-image --section-bg-image
    --color-preface-accent --h3-marker --h4-marker
  ].freeze

  # live book.yml の theme.style（image/simple どちらで作業中でも）に依存せず通るようにする。
  # image 固有の --frontispiece-edge-inset は style で条件分岐して検証する。
  def test_should_render_all_public_interface_variables_and_page_size
    css = BSC.render(Common::CONFIG)

    (PAGE_VARS + THEME_VARS_COMMON).each do |var|
      assert_includes css, "#{var}:", "生成 CSS に #{var} が含まれること"
    end
    if Common::CONFIG.theme.style == 'image'
      assert_includes css, '--frontispiece-edge-inset:', 'image では扉絵の引っ込み量を宣言する'
    else
      assert_includes css, '--frontispiece-image: none;', 'simple では画像を none 宣言する'
      refute_includes css, '--frontispiece-edge-inset:', 'simple では扉絵の引っ込み量を宣言しない'
    end
    assert_match(/@page \{ size: \d+mm \d+mm; \}/, css)
  end

  # Kindle 用テーマ色リテラル: body.vs-kindle 規則がリテラル hex で焼かれ、var()/color-mix を含まない
  def test_should_bake_kindle_accent_literals
    settings_yellow = build_config(theme_color: 'yellow')
    css = BSC.render(settings_yellow)

    assert_includes css, 'body.vs-kindle strong { color: #f0a000; }'
    assert_includes css, 'body.vs-header-simple.vs-kindle h1 { border-color: #f0a000; }'
    assert_includes css, 'body.vs-kindle .column { border-color: #f0a000; background: #fdf1d9; }'
    # vs-kindle 規則の実行部分に var()/color-mix() が漏れていない
    kindle_lines = css.lines.grep(/vs-kindle/).grep_v(%r{/\*})
    assert(kindle_lines.none? { it.include?('var(') }, 'Kindle 規則に var() を残さない')
    assert(kindle_lines.none? { it.include?('color-mix(') }, 'Kindle 規則に color-mix() を残さない')
  end

  # テーマ色を変えると Kindle アクセントが追従する（固定でない）。付録色も揃えれば yellow は消える。
  def test_should_follow_theme_color_in_kindle_accent
    css = BSC.render(build_config(theme_color: 'blue', appendix_color: 'blue'))

    assert_includes css, 'body.vs-kindle strong { color: #0ea5e9; }'
    assert_includes css, 'body.vs-header-simple.vs-kindle h1 { border-color: #0ea5e9; }'
    refute_includes css, '#f0a000', '全て blue に追従し、既定の yellow は焼かれない'
  end

  # 付録色未指定のときは appendix.css の静的既定（yellow）に合わせる（PDF の実カスケードと一致）
  def test_should_default_unset_appendix_accent_to_yellow
    css = BSC.render(build_config(theme_color: 'blue', appendix_color: nil))

    assert_includes css, 'body.appendix.vs-header-simple.vs-kindle h1 { border-color: #f0a000; }',
                    '付録は未指定なら yellow（PDF と同じ）'
    assert_includes css, 'body.vs-header-simple.vs-kindle h1 { border-color: #0ea5e9; }', '本文は theme 色'
  end

  # appendix_color がテーマ色と異なるときだけ付録専用（body.appendix）規則を出す
  def test_should_emit_appendix_override_only_when_distinct
    same = BSC.render(build_config(theme_color: 'yellow', appendix_color: 'yellow'))
    refute_includes same, 'body.appendix.vs-header-simple.vs-kindle h1', '同色なら付録規則は出さない'

    distinct = BSC.render(build_config(theme_color: 'blue', appendix_color: 'red'))
    assert_includes distinct, 'body.appendix.vs-header-simple.vs-kindle h1 { border-color: #dc2626; }'
    assert_includes distinct, 'body.vs-header-simple.vs-kindle h1 { border-color: #0ea5e9; }', '本文側は theme 色のまま'
  end

  # クリーン EPUB 非汚染: 生成した accent 規則はすべて body.vs-kindle 前置
  def test_should_scope_all_accent_rules_to_vs_kindle
    css = BSC.render(build_config(theme_color: 'blue', appendix_color: 'red'))

    accent_rules = css.lines.select { it.match?(/\{[^}]*(?:border-color|text-decoration-color|section-number|chapter-number|\bcolor:)/) }
                      .grep_v(%r{/\*}).grep_v(/^\s*--/) # コメントと :root の変数宣言を除く
    refute_empty accent_rules
    assert(accent_rules.all? { it.include?('vs-kindle') }, '裸の accent 規則を book-settings.css に出さない')
  end

  # 前書き/後書きの accent も preface_color に追従してリテラル化される（body.preface/postface スコープ）
  def test_should_bake_preface_accent_following_preface_color
    css = BSC.render(build_config(theme_color: 'yellow', preface_color: 'red'))

    assert_includes css, 'body.preface.vs-kindle h1, body.postface.vs-kindle h1 { border-bottom-color: #dc2626; }'
    assert_includes css, 'body.preface.vs-kindle a, body.postface.vs-kindle a { color: #dc2626; border-bottom: 1px dotted #dc2626; }'
    # 前書き固有の border-bottom-color 規則は必ず body.preface / body.postface でスコープする
    # （裸の h1 を出すと本文章 h1 へ波及する）
    css.lines.select { it.include?('border-bottom-color') }.each do |line|
      assert_includes line, 'body.preface', '前書き h1 下線は preface/postface にスコープする'
    end
  end

  # preface_color 未指定時はテーマ色へフォールバック（PDF の --color-preface-accent と同じ挙動）
  def test_should_default_unset_preface_accent_to_theme_color
    css = BSC.render(build_config(theme_color: 'blue', preface_color: nil))

    assert_includes css, 'body.preface.vs-kindle h1, body.postface.vs-kindle h1 { border-bottom-color: #0ea5e9; }'
  end

  # page.section_page_break: false を book.yml に書くと、全文生成に打ち消し規則が載る。
  # 値は明示的に与える——このリポジトリ自身の book.yml を読ませると、著者が
  # section_page_break を false にした瞬間に「既定では出ない」側の検証が落ちる。
  def test_should_render_section_page_break_negation_from_config
    disabled = Common::CONFIG.with(page: Common::CONFIG.page.with(section_page_break: false))
    enabled  = Common::CONFIG.with(page: Common::CONFIG.page.with(section_page_break: true))

    assert_includes BSC.render(disabled), 'body.vs-header-simple h2'
    refute_includes BSC.render(enabled), 'break-before: auto;'
  end

  # theme.color / appendix_color / preface_color を差し替えた Common::CONFIG 相当の Data を組む
  def build_config(theme_color: 'yellow', appendix_color: nil, preface_color: nil)
    Common::CONFIG.with(theme: Common::CONFIG.theme.with(color: theme_color, appendix_color:, preface_color:))
  end
end

# ================================================================
# 打ち消しセレクタと元 CSS の一致（page-break-control-spec.md §2.2）
# ================================================================
# book-settings.css は後段読込のため「同特異度なら後勝ち」で打ち消せるが、
# 元ルールのセレクタが変わると打ち消し側が特異度負けして黙って効かなくなる。
# テーマ CSS を触ったときに必ず気づけるよう、対応を回帰として固定する。
class BookSettingsCssSectionBreakSelectorTest < Minitest::Test
  BSC = VivlioStarter::CLI::PreProcessCommands::BookSettingsCss
  STYLESHEETS = File.expand_path('../../../../stylesheets', __dir__)

  def test_should_mirror_selectors_that_actually_break_before_a_section
    sources = Dir.glob(File.join(STYLESHEETS, '*.css')).map { File.read(it) }.join("\n")

    BSC::SECTION_PAGE_BREAK_SELECTORS.each do |selector|
      assert_includes sources, selector,
                      "#{selector} が stylesheets/ に存在しません。" \
                      '元ルールを改名したなら SECTION_PAGE_BREAK_SELECTORS も追随させてください。'
    end
  end

  # 文字数 → mm 換算は image-header.css の実際の font-size / letter-spacing を
  # Ruby 側で再現している（clamp() を calc() の中で掛けると Vivliostyle が宣言ごと落とすため
  # 生成時に解いてリテラルで焼く）。CSS 側だけ変えると換算が黙ってずれるので前提を固定する。
  def test_should_pin_chapter_title_metrics_that_the_char_conversion_reproduces
    css = File.read(File.join(STYLESHEETS, 'image-header.css'))

    assert_match(/font-size:\s*clamp\(34Q,\s*calc\(var\(--paper-scale\)\s*\*\s*48Q\),\s*50Q\)/, css,
                 '.chapter-title の font-size clamp が変わりました。' \
                 'BookSettingsCss#chapter_title_advance_mm の換算も合わせてください。')
    assert_match(/letter-spacing:\s*0\.08em/, css,
                 '.chapter-title の letter-spacing が変わりました。' \
                 'BookSettingsCss#chapter_title_advance_mm の 1.08 も合わせてください。')
  end

  # 節題のフォントサイズは「版面幅 − 左右の飾り避け」を文字数で割って決める。
  # 飾り避け（padding-inline）が変わると 1 行の字数がずれるので、CSS 側の値を固定する。
  def test_should_pin_ornament_padding_that_the_font_size_conversion_assumes
    css = File.read(File.join(STYLESHEETS, 'image-header.css'))
    assumed = BSC::SECTION_TITLE_ORNAMENT_PADDING_MM

    assert_match(/padding-inline:\s*clamp\(11mm,[^;]*16mm\)\s*clamp\(12mm,[^;]*18mm\)/m, css,
                 '節絵の飾り避け（padding-inline）が変わりました。' \
                 "BookSettingsCss::SECTION_TITLE_ORNAMENT_PADDING_MM (#{assumed}) も合わせてください。")
    assert_in_delta 34.0, assumed, 0.01, '16mm + 18mm = 34mm と一致していること'
  end

  # 見出しの前後の余白は「前 ≫ 後」でなければ、前節の末尾と次節の見出しが 1 つの塊に見える
  # （近接の原則・heading-metrics-spec §4）。数値ではなく比の向きを固定する。
  def test_should_keep_section_topic_margin_before_larger_than_after
    css = File.read(File.join(STYLESHEETS, 'image-header.css'))
    block = css[/body\.vs-header-image \.section-topic \{(.+?)\}/m, 1]

    refute_nil block, '.section-topic のルールが見つかりません'
    before_mm = block[/margin-block-start:[^;]*?(\d+(?:\.\d+)?)mm\s*\)/, 1]&.to_f
    after_mm  = block[/margin-block-end:[^;]*?(\d+(?:\.\d+)?)mm\s*\)/, 1]&.to_f

    refute_nil before_mm, 'margin-block-start が読み取れません'
    refute_nil after_mm, 'margin-block-end が読み取れません'
    assert_operator before_mm, :>, after_mm * 2,
                    "見出しの前の空き(#{before_mm}mm)は後ろ(#{after_mm}mm)の 2 倍以上あるべきです（近接の原則）"
  end
end

# ================================================================
# 会話文キャラクター色の生成（characters-dialogue-spec.md §3-3）
# ================================================================
class BookSettingsCssTalkTest < Minitest::Test
  BSC = VivlioStarter::CLI::PreProcessCommands::BookSettingsCss
  TalkRegistry = VivlioStarter::CLI::PreProcessCommands::TalkRegistry
  LOG_METHODS = %i[log_info log_success log_warn log_error log_action].freeze
  Common = VivlioStarter::CLI::Common

  def setup
    @saved = LOG_METHODS.to_h { [it, Common.method(it)] }
    LOG_METHODS.each { |name| Common.define_singleton_method(name) { |*, **| } }
  end

  def teardown
    @saved&.each { |name, m| Common.define_singleton_method(name, m) }
  end

  def registry
    TalkRegistry.from_hash({
      'sensei' => { 'color' => 'indigo' }, # テーマ色名 → var(--accent-indigo) / Kindle は hex
      'yamada' => '#1565c0',               # HEX はそのまま
      'nocolor' => { 'name' => '色なし' }  # 色未指定 → 生成しない（テーマ色を使う）
    })
  end

  # :root の --talk-c-<key> は色を明示した話者のみ。名前色は var()、HEX はそのまま。
  def test_should_declare_talk_color_variables_for_colored_characters
    lines = BSC.talk_variable_declarations(registry)

    assert_includes lines, '--talk-c-sensei: var(--accent-indigo);'
    assert_includes lines, '--talk-c-yamada: #1565c0;'
    refute(lines.any? { it.include?('nocolor') }, '色未指定の話者は宣言しない')
  end

  # .talk-c-<key> の var() 差し替え。
  def test_should_emit_class_rules
    css = BSC.talk_class_rules(registry)

    assert_includes css, '.talk-c-sensei { --talk-accent: var(--talk-c-sensei); }'
    assert_includes css, '.talk-c-yamada { --talk-accent: var(--talk-c-yamada); }'
    refute_includes css, 'nocolor'
  end

  # Kindle は inline 形式へ組み替わるため、話者名・区切り・強調の色をリテラルで焼く
  # （吹き出しの枠線は Kindle に存在しないのでリテラル化しない）。
  def test_should_emit_kindle_literals_for_inline_form
    css = BSC.talk_class_rules(registry)

    assert_includes css, 'body.vs-kindle .talk-c-sensei .talk-name { color: #4f46e5; }'
    assert_includes css, 'body.vs-kindle .talk-c-sensei .talk-sep { color: #4f46e5; }'
    assert_includes css, 'body.vs-kindle .talk-c-sensei strong { color: #4f46e5; }'
    assert_includes css, 'body.vs-kindle .talk-c-yamada .talk-name { color: #1565c0; }'
    refute_includes css, 'border-left-color', 'Kindle に吹き出しの枠線は無い'
  end

  # characters.yml 不在（空 registry）なら talk の宣言・ルールを一切出さない。
  def test_should_emit_nothing_when_registry_empty
    empty = TalkRegistry.from_hash({})

    assert_empty BSC.talk_variable_declarations(empty)
    assert_equal '', BSC.talk_class_rules(empty)
  end
end
