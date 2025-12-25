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
require 'vivlio/starter/cli/common'
require 'vivlio/starter/cli/pre_process'

module Vivlio
  module Starter
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

        # ornament: nothing 指定時に SVG プレースホルダーの data URI が返ることを検証
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

            # ImageGenerator.ensure_variant_generated をスタブして、バリアントファイルを生成
            generator = lambda do |source_path, variant|
              dir = File.dirname(source_path)
              basename = File.basename(source_path, '.*')
              variant_path = File.join(dir, "#{basename}_#{variant}.webp")
              File.write(variant_path, variant.to_s)
              variant_path
            end

            PreProcessCommands::ImageGenerator.stub(:ensure_variant_generated, generator) do
              front = PreProcessCommands.resolve_frontispiece_path('ajisai', allow_generation: true)
              ornament = PreProcessCommands.resolve_ornament_path('ajisai', allow_generation: true)

              assert_equal 'images/bundled/ajisai_portrait.webp', front
              assert_equal 'images/bundled/ajisai_landscape.webp', ornament
            end

            assert File.exist?(File.join(bundled, 'ajisai_portrait.webp')), 'portrait バリアントが生成されていません'
            assert File.exist?(File.join(bundled, 'ajisai_landscape.webp')), 'landscape バリアントが生成されていません'
          end
        end

        private

        # テストごとに stylesheets/images 相当の一時ディレクトリを差し替える
        # ThemeImageResolver モジュールの @theme_images_root を差し替える
        def with_temp_theme_images
          resolver = PreProcessCommands::ThemeImageResolver
          original_defined = resolver.instance_variable_defined?(:@theme_images_root)
          original_root = resolver.instance_variable_get(:@theme_images_root)

          Dir.mktmpdir('theme-images-test') do |tmp|
            images_root = File.join(tmp, 'images')
            FileUtils.mkdir_p(images_root)

            begin
              resolver.instance_variable_set(:@theme_images_root, images_root)
              yield images_root
            ensure
              if original_defined
                resolver.instance_variable_set(:@theme_images_root, original_root)
              elsif resolver.instance_variable_defined?(:@theme_images_root)
                resolver.remove_instance_variable(:@theme_images_root)
              end
            end
          end
        end
      end
    end
  end
end
