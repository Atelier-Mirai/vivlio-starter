# frozen_string_literal: true

# ================================================================
# Test: theme_image_resolution_test.rb
# ================================================================
# テスト対象:
#   PreProcessCommands の画像解決ロジック
#
# 検証内容:
#   - frontispiece/ornament の既存バリアント使用
#   - ornament: nothing 指定時のプレースホルダー生成
#   - bundled ディレクトリからの画像検索
# ================================================================

require 'test_helper'
require 'fileutils'
require 'tmpdir'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/pre_process'

module VivlioStarter
  module CLI
    # テーマ画像解決のユニットテスト
    class ThemeImageResolutionTest < Minitest::Test
      # 既存のバリアント画像がそのまま使用されることを確認
      def test_frontispiece_and_ornament_use_existing_variants
        with_temp_theme_images do |images_root|
          bundled = File.join(images_root, 'bundled')
          FileUtils.mkdir_p(bundled)
          File.write(File.join(bundled, 'himawari_portrait.webp'), 'portrait')
          File.write(File.join(bundled, 'himawari_landscape.webp'), 'landscape')

          front = PreProcessCommands.resolve_frontispiece_path('himawari', allow_generation: false)
          ornament = PreProcessCommands.resolve_ornament_path('himawari', allow_generation: false)

          assert_equal 'images/bundled/himawari_portrait.webp', front
          assert_equal 'images/bundled/himawari_landscape.webp', ornament
        end
      end

      # ユーザー提供画像がバンドル画像より優先して解決されることを確認
      # （stylesheets/images/ で bundled/ の同名画像を上書きできる仕組みの回帰テスト）
      def test_user_image_overrides_bundled_image_with_same_name
        with_temp_theme_images do |images_root|
          bundled = File.join(images_root, 'bundled')
          FileUtils.mkdir_p(bundled)
          File.write(File.join(bundled, 'sample_portrait.webp'), 'bundled')
          File.write(File.join(images_root, 'sample_portrait.webp'), 'user')

          front = PreProcessCommands.resolve_frontispiece_path('sample', allow_generation: false)

          assert_equal 'images/sample_portrait.webp', front, 'ユーザー提供画像が優先して解決されるべき'
        end
      end

      # 未指定（nil/空）時は既定画像 sakura に解決されることを確認
      def test_unspecified_uses_sakura_default
        with_temp_theme_images do |images_root|
          bundled = File.join(images_root, 'bundled')
          FileUtils.mkdir_p(bundled)
          File.write(File.join(bundled, 'sakura_portrait.webp'), 'p')
          File.write(File.join(bundled, 'sakura_landscape.webp'), 'l')

          assert_equal 'images/bundled/sakura_portrait.webp',
                       PreProcessCommands.resolve_frontispiece_path(nil, allow_generation: false)
          assert_equal 'images/bundled/sakura_landscape.webp',
                       PreProcessCommands.resolve_ornament_path('', allow_generation: false)
        end
      end

      # 存在しない画像名は既定画像（sakura）へフォールバックすることを確認
      # （color: pink → yellow と同様の一貫したフォールバック）
      def test_missing_image_falls_back_to_sakura
        with_temp_theme_images do |images_root|
          bundled = File.join(images_root, 'bundled')
          FileUtils.mkdir_p(bundled)
          File.write(File.join(bundled, 'sakura_portrait.webp'), 'p')
          File.write(File.join(bundled, 'sakura_landscape.webp'), 'l')

          front = PreProcessCommands.resolve_frontispiece_path('fuji', allow_generation: false)
          ornament = PreProcessCommands.resolve_ornament_path('fuji', allow_generation: false)

          assert_equal 'images/bundled/sakura_portrait.webp', front, '扉絵は sakura へフォールバックすべき'
          assert_equal 'images/bundled/sakura_landscape.webp', ornament, '飾り画像は sakura へフォールバックすべき'
        end
      end

      # フォールバック先（sakura）自体も存在しない場合はプレースホルダーへ落ちることを確認
      def test_ornament_nothing_uses_placeholder
        with_temp_theme_images do |_images_root|
          result = PreProcessCommands.resolve_ornament_path('nothing', allow_generation: false)

          assert result.start_with?('data:image/svg+xml;charset=utf-8,'), 'プレースホルダーの data URI を期待しました'
          assert_includes result, 'nothing.webp'
        end
      end

      # frontispiece: ajisai 指定時に不足バリアントを生成して利用できることを検証
      def test_frontispiece_generation_creates_variants
        with_temp_theme_images do |images_root|
          bundled = File.join(images_root, 'bundled')
          FileUtils.mkdir_p(bundled)
          base_path = File.join(bundled, 'ajisai.webp')
          File.write(base_path, 'base')

          # ImageGenerator.ensure_variant_generated をスタブして、バリアントファイルを
          # 生成キャッシュ（theme-images/・images root からの相対サブパス維持）へ生成する
          cache_root = PreProcessCommands::ThemeImageResolver.theme_images_cache_root
          generator = lambda do |source_path, variant|
            basename = File.basename(source_path, '.*')
            variant_path = File.join(cache_root, 'bundled', "#{basename}_#{variant}.webp")
            FileUtils.mkdir_p(File.dirname(variant_path))
            File.write(variant_path, variant.to_s)
            variant_path
          end

          PreProcessCommands::ImageGenerator.stub(:ensure_variant_generated, generator) do
            front = PreProcessCommands.resolve_frontispiece_path('ajisai', allow_generation: true)
            ornament = PreProcessCommands.resolve_ornament_path('ajisai', allow_generation: true)

            assert_equal 'theme-images/bundled/ajisai_portrait.webp', front
            assert_equal 'theme-images/bundled/ajisai_landscape.webp', ornament
          end

          assert File.exist?(File.join(cache_root, 'bundled', 'ajisai_portrait.webp')),
                 'portrait バリアントが生成されていません'
          assert File.exist?(File.join(cache_root, 'bundled', 'ajisai_landscape.webp')),
                 'landscape バリアントが生成されていません'
        end
      end

      private

      # テストごとに stylesheets/images 相当の一時ディレクトリを差し替える
      # ThemeImageResolver モジュールの @theme_images_root を差し替える
      def with_temp_theme_images
        resolver = PreProcessCommands::ThemeImageResolver
        originals = %i[@theme_images_root @theme_images_cache_root].to_h do |name|
          [name, [resolver.instance_variable_defined?(name), resolver.instance_variable_get(name)]]
        end

        Dir.mktmpdir('theme-images-test') do |tmp|
          images_root = File.join(tmp, 'images')
          FileUtils.mkdir_p(images_root)

          begin
            resolver.instance_variable_set(:@theme_images_root, images_root)
            # バリアント生成キャッシュも隔離する（実リポジトリの .cache を読み書きさせない）
            resolver.instance_variable_set(:@theme_images_cache_root, File.join(tmp, 'theme-images'))
            yield images_root
          ensure
            originals.each do |name, (defined, value)|
              if defined
                resolver.instance_variable_set(name, value)
              elsif resolver.instance_variable_defined?(name)
                resolver.remove_instance_variable(name)
              end
            end
          end
        end
      end
    end
  end
end
