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
        assert_match(/yellow/, out)
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
