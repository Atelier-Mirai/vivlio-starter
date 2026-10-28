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

  # 開始 `---` の後に閉じがない場合、警告が出て元テキストを返す。
  # 出力先は stdout——他の 🟡 と同じく Common.log_warn を通すため
  # （`cli-warning-delivery-spec.md` §5.1）。
  def test_unclosed_frontmatter_emits_warning_and_returns_original
    content = "---\ntitle: 閉じていない\nauthor: テスト\n本文はここから\n"
    result = nil
    out, _err = capture_io do
      result = FG.apply_frontmatter(content, 'chapter', '01', path: 'contents/99-draft.md')
    end

    assert_match(/frontmatter/i, out)
    assert_match(%r{contents/99-draft\.md}, out)
    assert_match(/閉じ.*見つかりません/, out)
    # 元のテキストがそのまま返ること
    assert_equal content, result
  end

  # path 省略時でも警告が出る（unknown file 表記）
  def test_unclosed_frontmatter_warns_without_path
    content = "---\ntitle: foo\n"
    out, _err = capture_io { FG.apply_frontmatter(content, 'chapter', '01') }

    assert_match(/unknown file/, out)
  end
end

# theme.frontispiece の edge_inset/heading_chars/lead_chars 正規化を検証
class FrontmatterGeneratorFrontispieceConfigTest < Minitest::Test
  FG = VivlioStarter::CLI::PreProcessCommands::FrontmatterGenerator
  TIR = VivlioStarter::CLI::PreProcessCommands::ThemeImageResolver

  # フォールバック先（sakura）も含め画像が一切無い空の一時ディレクトリへ隔離する。
  # これにより実リポジトリの bundled 画像や ImageMagick 生成を巻き込まずに検証できる。
  # バリアント生成キャッシュ（theme_images_cache_root）も同様に隔離する。
  def setup
    @had_root = TIR.instance_variable_defined?(:@theme_images_root)
    @original_root = TIR.instance_variable_get(:@theme_images_root)
    @had_cache_root = TIR.instance_variable_defined?(:@theme_images_cache_root)
    @original_cache_root = TIR.instance_variable_get(:@theme_images_cache_root)
    @tmp = Dir.mktmpdir('frontmatter-config-test')
    FileUtils.mkdir_p(File.join(@tmp, 'images'))
    TIR.instance_variable_set(:@theme_images_root, File.join(@tmp, 'images'))
    TIR.instance_variable_set(:@theme_images_cache_root, File.join(@tmp, 'theme-images'))
  end

  def teardown
    restore_ivar(:@theme_images_root, @had_root, @original_root)
    restore_ivar(:@theme_images_cache_root, @had_cache_root, @original_cache_root)
    FileUtils.rm_rf(@tmp)
  end

  def restore_ivar(name, had, original)
    if had
      TIR.instance_variable_set(name, original)
    elsif TIR.instance_variable_defined?(name)
      TIR.remove_instance_variable(name)
    end
  end

  # frontispiece 未指定時は edge_inset が既定値 0mm になり、
  # heading_chars/lead_chars は省略可（nil）のまま、画像は既定の sakura になることを確認
  def test_parse_frontispiece_config_defaults_when_unset
    bundled = File.join(@tmp, 'images', 'bundled')
    FileUtils.mkdir_p(bundled)
    File.write(File.join(bundled, 'sakura_portrait.webp'), 'p')

    config = FG.parse_frontispiece_config(nil)

    assert_equal '0mm', config[:edge_inset]
    assert_nil config[:heading_chars]
    assert_nil config[:lead_chars]
    assert_equal 'images/bundled/sakura_portrait.webp', config[:path], '未指定時は既定画像 sakura になるべき'
  end

  # edge_inset/heading_chars/lead_chars を明示指定した場合、そのまま反映されることを確認。
  # 画像は空ディレクトリのためフォールバック先(sakura)も無く、プレースホルダーへ落ちる。
  def test_parse_frontispiece_config_respects_explicit_values
    config = FG.parse_frontispiece_config(
      { image: 'not_a_real_theme_image_xyz', edge_inset: '15mm', heading_chars: 10, lead_chars: 24 }
    )

    assert_equal '15mm', config[:edge_inset]
    assert_equal 10, config[:heading_chars]
    assert_equal 24, config[:lead_chars]
    assert config[:path].start_with?('data:image/svg+xml'), '画像未検出時は data URI プレースホルダーになるはず'
    # プレースホルダーには要求された画像名がエンコードされる。
    # CGI 未ロードのフォールバック（空SVG）に落ちていないこと＝CGI require 順序バグの回帰テスト。
    assert_includes config[:path], 'not_a_real_theme_image_xyz.webp',
                    'プレースホルダーSVGに画像名が埋め込まれるべき（CGIロード順の回帰）'
  end

  # 章扉の倍率は空欄・読めない値なら書かなかった扱い（parse_theme_settings が本全体へ寄せる）。
  # 画像名だけの短縮形にも倍率は無い
  def test_should_read_frontispiece_lead_size_or_leave_it_unset
    assert_equal 1.1, FG.parse_frontispiece_config({ image: 'not_a_real_theme_image_xyz', lead_size: 1.1 })[:lead_size]
    assert_nil FG.parse_frontispiece_config({ image: 'not_a_real_theme_image_xyz', lead_size: nil })[:lead_size]
    assert_nil FG.parse_frontispiece_config({ image: 'not_a_real_theme_image_xyz', lead_size: '12pt' })[:lead_size]
    assert_nil FG.parse_frontispiece_config('not_a_real_theme_image_xyz')[:lead_size]
  end
end

# theme.color のパース（無効値のフォールバック）を検証
class FrontmatterGeneratorThemeColorTest < Minitest::Test
  FG = VivlioStarter::CLI::PreProcessCommands::FrontmatterGenerator

  # 有効な色名・HEX はそのまま解決される
  def test_valid_color_and_hex
    assert_equal ['blue', 'var(--accent-blue)'], FG.parse_theme_color('blue')
    assert_equal ['#ff0000', '#ff0000'], FG.parse_theme_color('#ff0000')
    assert_equal ['green', 'var(--accent-green)'], FG.parse_theme_color('')
  end

  # 無効な色名は exit せず既定色（config_keys.rb の green）へフォールバックする
  # （章ごとに呼ばれるため、警告は出さず ThemeValidator に集約する。exit 1 廃止の回帰テスト）
  def test_invalid_color_falls_back_to_default_without_exit_or_warning
    result = nil
    out, err = capture_io { result = FG.parse_theme_color('pink') }

    assert_equal ['green', 'var(--accent-green)'], result
    assert_empty out, 'parse_theme_color は章ごとに呼ばれるため警告を出さないこと'
    assert_empty err
  end
end

# 章リードの倍率（theme.lead_size / theme.frontispiece.lead_size）の読み方（chapter-lead-size-spec.md §2.2.1）
class FrontmatterGeneratorLeadSizeTest < Minitest::Test
  FG = VivlioStarter::CLI::PreProcessCommands::FrontmatterGenerator

  # 数値と em 付きは同じ倍率。刻みは丸めない
  def test_should_read_number_and_em_as_same_ratio
    assert_equal [1.2, nil], FG.parse_lead_size(1.2)
    assert_equal [1.2, nil], FG.parse_lead_size('1.2em')
    assert_equal [1.05, nil], FG.parse_lead_size('1.05')
    assert_equal [1.0, nil], FG.parse_lead_size(1)
  end

  # 範囲外は端へ寄せ、寄せた理由を返す（警告は ThemeValidator が一度だけ出す）
  def test_should_clamp_out_of_range_with_reason
    assert_equal [1.0, :too_small], FG.parse_lead_size(0.9)
    assert_equal [2.0, :too_large], FG.parse_lead_size('2.5em')
  end

  # 直接の大きさと読めない値は、書かなかった扱い（nil）と理由。空欄は理由なし
  def test_should_treat_lengths_and_garbage_as_unset
    assert_equal [nil, :length], FG.parse_lead_size('12pt')
    assert_equal [nil, :length], FG.parse_lead_size('16Q')
    assert_equal [nil, :invalid], FG.parse_lead_size('large')
    assert_equal [nil, :invalid], FG.parse_lead_size('110%')
    assert_equal [nil, nil], FG.parse_lead_size(nil)
    assert_equal [nil, nil], FG.parse_lead_size('')
  end

  # 章扉の倍率を書かなければ、本全体の倍率に従う（既定値 1.2 に化けない）
  def test_should_fall_back_to_book_lead_size_for_frontispiece
    config = VivlioStarter::CLI::Common::CONFIG
    cfg = config.with(theme: config.theme.with(lead_size: 1.1, frontispiece: config.theme.frontispiece.with(lead_size: nil)))

    settings = FG.parse_theme_settings(cfg)

    assert_equal 1.1, settings[:lead_size_value]
    assert_equal 1.1, settings[:frontispiece_lead_size_value]
  end
end
