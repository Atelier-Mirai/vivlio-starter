# frozen_string_literal: true

require 'test_helper'
require 'fileutils'
require 'tmpdir'
require 'vivlio/starter/cli/common'
require 'vivlio/starter/cli/pre_process'

module Vivlio
  module Starter
    module CLI
      class ThemeImageResolutionTest < Minitest::Test
        # frontispiece / ornament に同名バリアントが存在する場合は生成せずそのまま採用できるかを検証
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
            File.write(File.join(bundled, 'ajisai.webp'), 'base')

            generator = lambda do |spec, **_kwargs|
              relative = spec.sub(/\.webp\z/, '')
              stem = File.join(images_root, relative)
              FileUtils.mkdir_p(File.dirname(stem))
              File.write("#{stem}_portrait.webp", 'portrait')
              File.write("#{stem}_landscape.webp", 'landscape')
              true
            end

            PreProcessCommands.stub(:generate_frontispiece_and_ornament_from, generator) do
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
        def with_temp_theme_images
          original_defined = PreProcessCommands.instance_variable_defined?(:@theme_images_root)
          original_root = PreProcessCommands.instance_variable_get(:@theme_images_root)

          Dir.mktmpdir('theme-images-test') do |tmp|
            images_root = File.join(tmp, 'images')
            FileUtils.mkdir_p(images_root)

            begin
              PreProcessCommands.instance_variable_set(:@theme_images_root, images_root)
              yield images_root
            ensure
              if original_defined
                PreProcessCommands.instance_variable_set(:@theme_images_root, original_root)
              elsif PreProcessCommands.instance_variable_defined?(:@theme_images_root)
                PreProcessCommands.remove_instance_variable(:@theme_images_root)
              end
            end
          end
        end
      end
    end
  end
end
