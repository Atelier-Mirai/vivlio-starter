# frozen_string_literal: true

# ================================================================
# Test: theme_validator_test.rb
# ================================================================
# テスト対象:
#   ThemeValidator（theme.color / frontispiece / ornament の検証）
#
# 検証内容:
#   - 無効な色名（例: pink）で警告、有効な色名・HEX・未指定では警告なし
#   - 存在しない frontispiece/ornament 画像名で警告、実在画像では警告なし
#   - theme.style: simple では画像検証をスキップ（色検証は継続）
#   - URL/url() 指定は検証対象外
#   - ThemeImageResolver.theme_image_available? の判定
# ================================================================

require 'test_helper'
require 'fileutils'
require 'tmpdir'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/pre_process'

module VivlioStarter
  module CLI
    class ThemeValidatorTest < Minitest::Test
      TV = PreProcessCommands::ThemeValidator

      def teardown
        restore_theme_images_root
      end

      # 無効な色名は警告する（既定色フォールバックの案内込み）
      def test_invalid_color_warns
        out = capture_stdout { TV.validate_color('pink') }

        assert_match(/theme\.color 'pink'/, out)
        assert_match(/既定色（green）/, out)
      end

      # 有効な色名・HEX・未指定では警告しない
      def test_valid_colors_do_not_warn
        assert_empty capture_stdout { TV.validate_color('blue') }
        assert_empty capture_stdout { TV.validate_color('#ff0000') }
        assert_empty capture_stdout { TV.validate_color('0xffcc00') }
        assert_empty capture_stdout { TV.validate_color('') }
        assert_empty capture_stdout { TV.validate_color(nil) }
      end

      # 実在しない画像名は警告する
      def test_missing_image_warns
        with_temp_theme_images do |_root|
          out = capture_stdout { TV.validate_image(:frontispiece, 'fuji', variant: :portrait) }

          assert_match(/theme\.frontispiece の画像 'fuji' が見つかりません/, out)
        end
      end

      # 実在する base 画像（バリアント生成元）があれば警告しない
      def test_existing_base_image_does_not_warn
        with_temp_theme_images do |root|
          bundled = File.join(root, 'bundled')
          FileUtils.mkdir_p(bundled)
          File.write(File.join(bundled, 'sakura.webp'), 'base')

          assert_empty capture_stdout { TV.validate_image(:ornament, 'sakura', variant: :landscape) }
        end
      end

      # URL/url() 指定・未指定は検証対象外（警告しない）
      def test_url_and_blank_sources_skip_validation
        with_temp_theme_images do |_root|
          assert_empty capture_stdout { TV.validate_image(:ornament, 'https://example.com/x.webp', variant: :landscape) }
          assert_empty capture_stdout { TV.validate_image(:frontispiece, 'url("x.webp")', variant: :portrait) }
          assert_empty capture_stdout { TV.validate_image(:frontispiece, nil, variant: :portrait) }
          assert_empty capture_stdout { TV.validate_image(:frontispiece, '', variant: :portrait) }
        end
      end

      # validate! : simple スタイルでは画像検証をスキップし、色検証のみ行う
      def test_validate_bang_simple_style_skips_image_check_but_checks_color
        with_temp_theme_images do |_root|
          cfg = { theme: { style: 'simple', color: 'pink', frontispiece: 'fuji', ornament: 'fuji' } }
          out = capture_stdout { TV.validate!(cfg) }

          assert_match(/theme\.color 'pink'/, out)
          refute_match(/theme\.frontispiece/, out)
          refute_match(/theme\.ornament/, out)
        end
      end

      # validate! : image スタイルでは色・扉絵・飾り画像すべてを検証する
      def test_validate_bang_image_style_checks_all
        with_temp_theme_images do |_root|
          cfg = { theme: { style: 'image', color: 'pink',
                           frontispiece: { image: 'fuji' }, ornament: 'kaede' } }
          out = capture_stdout { TV.validate!(cfg) }

          assert_match(/theme\.color 'pink'/, out)
          assert_match(/theme\.frontispiece の画像 'fuji'/, out)
          assert_match(/theme\.ornament の画像 'kaede'/, out)
        end
      end

      # 章リードの倍率: 範囲外は寄せた値と書き直し案を示す（chapter-lead-size-spec.md §2.3）
      def test_lead_size_out_of_range_warns_with_fix
        small = capture_stdout { TV.validate_lead_size('theme.lead_size', 0.9) }
        large = capture_stdout { TV.validate_lead_size('theme.frontispiece.lead_size', 2.5) }

        assert_match(/theme\.lead_size は 1\.0 以上にしてください/, small)
        assert_match(/lead_size: 0\.9 → 1\.0/, small)
        assert_match(/theme\.frontispiece\.lead_size は 2\.0 以下にしてください/, large)
        assert_match(/lead_size: 2\.5 → 2\.0/, large)
      end

      # 直接の大きさは、今の判型の本文の大きさで割った倍率を示す（本文 10.5pt で 12pt → 1.14）
      def test_lead_size_length_suggests_ratio_of_base_font
        out = PreProcessCommands::BookSettingsCss.stub(:build_page_cfg, { base_font_size: '10.5pt' }) do
          capture_stdout { TV.validate_lead_size('theme.lead_size', '12pt') }
        end

        assert_match(/本文に対する倍率（1\.0〜2\.0）で書いてください（12pt）。1\.2 倍で組みます/, out)
        assert_match(/lead_size: 12pt → 1\.14/, out)
      end

      # 章扉の倍率が読めなければ、本全体に従うと案内する
      def test_frontispiece_lead_size_invalid_falls_back_to_book
        out = capture_stdout { TV.validate_lead_size('theme.frontispiece.lead_size', 'large') }

        assert_match(/theme\.lead_size に従います/, out)
        assert_match(/lead_size: large → 1\.2 など/, out)
      end

      # 範囲内・em 付き・空欄は警告しない
      def test_valid_lead_sizes_do_not_warn
        assert_empty capture_stdout { TV.validate_lead_size('theme.lead_size', 1.1) }
        assert_empty capture_stdout { TV.validate_lead_size('theme.lead_size', '1.05em') }
        assert_empty capture_stdout { TV.validate_lead_size('theme.frontispiece.lead_size', nil) }
      end

      # validate! : 本全体の倍率は simple でも検証し、章扉の倍率は image のときだけ検証する
      def test_validate_bang_checks_frontispiece_lead_size_only_for_image_style
        with_temp_theme_images do |_root|
          simple = { theme: { style: 'simple', lead_size: 0.5, frontispiece: { lead_size: 0.5 } } }
          image = { theme: { style: 'image', lead_size: 1.2, frontispiece: { lead_size: 0.5 } } }

          simple_out = capture_stdout { TV.validate!(simple) }
          image_out = capture_stdout { TV.validate!(image) }

          assert_match(/theme\.lead_size は/, simple_out)
          refute_match(/theme\.frontispiece\.lead_size/, simple_out)
          assert_match(/theme\.frontispiece\.lead_size は 1\.0 以上/, image_out)
        end
      end

      # theme_image_available? : base 画像があれば true（バリアント未生成でも生成元になる）
      def test_theme_image_available_true_for_base_image
        with_temp_theme_images do |root|
          bundled = File.join(root, 'bundled')
          FileUtils.mkdir_p(bundled)
          File.write(File.join(bundled, 'himawari.webp'), 'base')

          assert PreProcessCommands::ThemeImageResolver.theme_image_available?('himawari', variant: :portrait)
        end
      end

      # theme_image_available? : どこにも無ければ false
      def test_theme_image_available_false_when_missing
        with_temp_theme_images do |_root|
          refute PreProcessCommands::ThemeImageResolver.theme_image_available?('fuji', variant: :portrait)
        end
      end

      private

      # log_warn は $stdout へ puts するため、標準出力を捕捉する
      def capture_stdout(&)
        out, = capture_io(&)
        out
      end

      # ThemeImageResolver の画像ルートを一時ディレクトリへ差し替える
      def with_temp_theme_images
        resolver = PreProcessCommands::ThemeImageResolver
        @resolver_had_root = resolver.instance_variable_defined?(:@theme_images_root)
        @resolver_original_root = resolver.instance_variable_get(:@theme_images_root)

        Dir.mktmpdir('theme-validator-test') do |tmp|
          images_root = File.join(tmp, 'images')
          FileUtils.mkdir_p(images_root)
          resolver.instance_variable_set(:@theme_images_root, images_root)
          yield images_root
        end
      end

      def restore_theme_images_root
        resolver = PreProcessCommands::ThemeImageResolver
        return unless defined?(@resolver_had_root)

        if @resolver_had_root
          resolver.instance_variable_set(:@theme_images_root, @resolver_original_root)
        elsif resolver.instance_variable_defined?(:@theme_images_root)
          resolver.remove_instance_variable(:@theme_images_root)
        end
      end
    end
  end
end
