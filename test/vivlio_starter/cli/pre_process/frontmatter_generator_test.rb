# frozen_string_literal: true

# ================================================================
# Test: frontmatter_generator_test.rb
# ================================================================
# 検証内容:
#   - 未クローズ frontmatter の警告（2-1-1 の回帰テスト）
#   - コードフェンス内の `---` を閉じと誤認しないこと
#   - parse_frontispiece_config: padding の既定値(0mm)と
#     heading_width/lead_width が省略可であること
# ================================================================

require_relative '../../../test_helper'
require 'fileutils'
require 'tmpdir'
require 'vivlio_starter/cli/pre_process/frontmatter_generator'
require 'vivlio_starter/cli/pre_process/theme_image_resolver'

class FrontmatterGeneratorUnclosedTest < Minitest::Test
  FG = VivlioStarter::CLI::PreProcessCommands::FrontmatterGenerator

  # 開始 `---` の後に閉じがない場合、警告が stderr に出て元テキストを返す
  def test_unclosed_frontmatter_emits_warning_and_returns_original
    content = "---\ntitle: 閉じていない\nauthor: テスト\n本文はここから\n"
    result = nil
    _out, err = capture_io do
      result = FG.apply_frontmatter(content, 'chapter', '01', path: 'contents/99-draft.md')
    end

    assert_match(/frontmatter/i, err)
    assert_match(%r{contents/99-draft\.md}, err)
    assert_match(/閉じ.*見つかりません/, err)
    # 元のテキストがそのまま返ること
    assert_equal content, result
  end

  # path 省略時でも警告が出る（unknown file 表記）
  def test_unclosed_frontmatter_warns_without_path
    content = "---\ntitle: foo\n"
    _out, err = capture_io { FG.apply_frontmatter(content, 'chapter', '01') }

    assert_match(/unknown file/, err)
  end
end

# theme.frontispiece の padding/heading_width/lead_width 正規化を検証
class FrontmatterGeneratorFrontispieceConfigTest < Minitest::Test
  FG = VivlioStarter::CLI::PreProcessCommands::FrontmatterGenerator
  TIR = VivlioStarter::CLI::PreProcessCommands::ThemeImageResolver

  # フォールバック先（sakura）も含め画像が一切無い空の一時ディレクトリへ隔離する。
  # これにより実リポジトリの bundled 画像や ImageMagick 生成を巻き込まずに検証できる。
  def setup
    @had_root = TIR.instance_variable_defined?(:@theme_images_root)
    @original_root = TIR.instance_variable_get(:@theme_images_root)
    @tmp = Dir.mktmpdir('frontmatter-config-test')
    FileUtils.mkdir_p(File.join(@tmp, 'images'))
    TIR.instance_variable_set(:@theme_images_root, File.join(@tmp, 'images'))
  end

  def teardown
    if @had_root
      TIR.instance_variable_set(:@theme_images_root, @original_root)
    elsif TIR.instance_variable_defined?(:@theme_images_root)
      TIR.remove_instance_variable(:@theme_images_root)
    end
    FileUtils.rm_rf(@tmp)
  end

  # frontispiece 未指定時は padding が既定値 0mm になり、
  # heading_width/lead_width は省略可（nil）のまま、画像は既定の sakura になることを確認
  def test_parse_frontispiece_config_defaults_when_unset
    bundled = File.join(@tmp, 'images', 'bundled')
    FileUtils.mkdir_p(bundled)
    File.write(File.join(bundled, 'sakura_portrait.webp'), 'p')

    config = FG.parse_frontispiece_config(nil)

    assert_equal '0mm', config[:padding]
    assert_nil config[:heading_width]
    assert_nil config[:lead_width]
    assert_equal 'images/bundled/sakura_portrait.webp', config[:path], '未指定時は既定画像 sakura になるべき'
  end

  # padding/heading_width/lead_width を明示指定した場合、そのまま反映されることを確認。
  # 画像は空ディレクトリのためフォールバック先(sakura)も無く、プレースホルダーへ落ちる。
  def test_parse_frontispiece_config_respects_explicit_values
    config = FG.parse_frontispiece_config(
      { image: 'not_a_real_theme_image_xyz', padding: '15mm', heading_width: '100mm', lead_width: '90mm' }
    )

    assert_equal '15mm', config[:padding]
    assert_equal '100mm', config[:heading_width]
    assert_equal '90mm', config[:lead_width]
    assert config[:path].start_with?('data:image/svg+xml'), '画像未検出時は data URI プレースホルダーになるはず'
    # プレースホルダーには要求された画像名がエンコードされる。
    # CGI 未ロードのフォールバック（空SVG）に落ちていないこと＝CGI require 順序バグの回帰テスト。
    assert_includes config[:path], 'not_a_real_theme_image_xyz.webp',
                    'プレースホルダーSVGに画像名が埋め込まれるべき（CGIロード順の回帰）'
  end
end

# theme.color のパース（無効値のフォールバック）を検証
class FrontmatterGeneratorThemeColorTest < Minitest::Test
  FG = VivlioStarter::CLI::PreProcessCommands::FrontmatterGenerator

  # 有効な色名・HEX はそのまま解決される
  def test_valid_color_and_hex
    assert_equal ['blue', 'var(--accent-blue)'], FG.parse_theme_color('blue')
    assert_equal ['#ff0000', '#ff0000'], FG.parse_theme_color('#ff0000')
    assert_equal ['yellow', 'var(--accent-yellow)'], FG.parse_theme_color('')
  end

  # 無効な色名は exit せず既定色（yellow）へフォールバックする
  # （章ごとに呼ばれるため、警告は出さず ThemeValidator に集約する。exit 1 廃止の回帰テスト）
  def test_invalid_color_falls_back_to_yellow_without_exit_or_warning
    result = nil
    out, err = capture_io { result = FG.parse_theme_color('pink') }

    assert_equal ['yellow', 'var(--accent-yellow)'], result
    assert_empty out, 'parse_theme_color は章ごとに呼ばれるため警告を出さないこと'
    assert_empty err
  end
end
