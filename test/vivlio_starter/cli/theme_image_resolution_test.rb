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
      TIR = PreProcessCommands::ThemeImageResolver

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
      # （color: pink → 既定色と同様の一貫したフォールバック）
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

      # 手置きの扉絵用バリアントは、元画像と同じく PNG でも使われる（ornament と揃える）
      def test_user_portrait_variant_accepts_png
        with_temp_theme_images do |images_root|
          File.write(File.join(images_root, 'sample_portrait.png'), 'user')

          front = PreProcessCommands.resolve_frontispiece_path('sample', allow_generation: false)

          assert_equal 'images/sample_portrait.png', front
        end
      end

      # 元画像のほうが新しければ（描き直した）、生成済みのバリアントは使わない
      def test_cached_variant_is_stale_when_source_is_newer
        with_temp_theme_images do |images_root|
          source, cached = write_source_and_cached_variant(images_root, :landscape)

          File.utime(Time.now, Time.now - 60, cached)

          refute TIR.cached_variant_current?(cached, :landscape)

          File.utime(Time.now, Time.now - 120, source)

          assert TIR.cached_variant_current?(cached, :landscape)
        end
      end

      # 扉絵のバリアントは、縦横比が今の判型の比からずれていれば使わない（判型を変えたとき）
      def test_cached_portrait_is_stale_when_ratio_differs
        with_temp_theme_images do |images_root|
          _source, cached = write_source_and_cached_variant(images_root, :portrait)

          TIR.stub(:binding_safe_portrait_ratio, 1.44) do
            TIR.stub(:image_ratio, 1.44) { assert TIR.cached_variant_current?(cached, :portrait) }
            TIR.stub(:image_ratio, 1.414) { refute TIR.cached_variant_current?(cached, :portrait) }
          end
        end
      end

      # 元画像が見つからないバリアントは、残っているものを使う
      def test_cached_variant_without_source_is_current
        with_temp_theme_images do |_images_root|
          cached = File.join(TIR.theme_images_cache_root, 'gone_landscape.webp')
          FileUtils.mkdir_p(File.dirname(cached))
          File.write(cached, 'l')

          assert TIR.cached_variant_current?(cached, :landscape)
        end
      end

      # 古いバリアントは解決の段階で作り直す（生成済みでも ensure_variant_generated が生成し直す）
      def test_stale_variant_is_regenerated
        with_temp_theme_images do |images_root|
          _source, cached = write_source_and_cached_variant(images_root, :landscape)
          File.utime(Time.now, Time.now - 60, cached)
          calls = []

          PreProcessCommands::ImageGenerator.stub(:generate_frontispiece_and_ornament_from,
                                                  ->(spec) { calls << spec }) do
            result = PreProcessCommands.resolve_ornament_path('sample', allow_generation: true)

            assert_equal 'theme-images/bundled/sample_landscape.webp', result
          end

          assert_equal ['bundled/sample.webp'], calls
        end
      end

      private

      # bundled/sample.webp と、その生成済みバリアント（キャッシュ）を作る
      def write_source_and_cached_variant(images_root, variant)
        source = File.join(images_root, 'bundled', 'sample.webp')
        FileUtils.mkdir_p(File.dirname(source))
        File.write(source, 'base')
        cached = File.join(TIR.theme_images_cache_root, 'bundled', "sample_#{variant}.webp")
        FileUtils.mkdir_p(File.dirname(cached))
        File.write(cached, variant.to_s)
        [source, cached]
      end

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
