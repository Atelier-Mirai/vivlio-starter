# frozen_string_literal: true

# ================================================================
# Test: image_generator_transparency_test.rb
# ================================================================
# テスト対象:
#   ImageGenerator の扉絵・節絵の生成（対角線で分けて並べ直す・WebP へ変換する）
#
# 検証内容（改善案 #140）:
#   - 絵の中の白（#FFFFFF の花びら）が、透明にならず不透明の白のまま残ること
#   - 半透明の画素が、白で塗られて不透明にならず、元のアルファのまま残ること
#   - waifu2x の経路でも、付け直した透過が効くこと（以前は不透明になり、白を抜く処理に頼っていた）
#   - 作り方の版が変わると、生成キャッシュの古い扉絵・節絵を捨てること
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'open3'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/pre_process'

module VivlioStarter
  module CLI
    class ImageGeneratorTransparencyTest < Minitest::Test
      IG = PreProcessCommands::ImageGenerator
      TIR = PreProcessCommands::ThemeImageResolver

      # 透明な画布の左上に、#FFFFFF の不透明の円（白い花びら）と、
      # 右下に、アルファ 0.5 の赤い四角（半透明の縁）を置いた絵
      def test_should_keep_white_opaque_and_alpha_unchanged_without_waifu2x
        skip_unless_magick

        Dir.mktmpdir('ig-transparency') do |dir|
          variant_png = make_variant(dir)
          webp = File.join(dir, 'flower_landscape.webp')
          IG.generate_variant_output(variant_png, webp, **output_options(variant_png, waifu2x_available: false))

          assert_flower_survives(dir, variant_png, webp)
        end
      end

      # waifu2x の経路（アルファを取り出し、色と別に拡大して付け直す）でも同じ。
      # waifu2x の代わりに、ImageMagick で 2 倍にするだけの偽物を使う
      def test_should_keep_white_opaque_and_alpha_unchanged_with_waifu2x_path
        skip_unless_magick

        Dir.mktmpdir('ig-transparency') do |dir|
          fake = File.join(dir, 'fake-waifu2x')
          File.write(fake, "#!/bin/sh\nexec magick \"$2\" -resize 200% \"PNG32:$4\"\n")
          File.chmod(0o755, fake)

          variant_png = make_variant(dir)
          webp = File.join(dir, 'flower_landscape.webp')
          IG.generate_variant_output(variant_png, webp,
                                     **output_options(variant_png, waifu2x_available: true, waifu2x: fake))

          assert_flower_survives(dir, variant_png, webp)
        end
      end

      def test_should_discard_variants_made_by_older_revision
        Dir.mktmpdir('ig-revision') do |dir|
          old_variant = File.join(dir, 'bundled', 'sample_landscape.webp')
          FileUtils.mkdir_p(File.dirname(old_variant))
          File.write(old_variant, 'old')
          File.write(File.join(dir, IG::VARIANT_REVISION_STAMP), "#{IG::VARIANT_REVISION - 1}\n")

          with_cache_root(dir) { IG.discard_outdated_variants! }

          refute_path_exists old_variant
          assert_equal IG::VARIANT_REVISION.to_s, File.read(File.join(dir, IG::VARIANT_REVISION_STAMP)).strip

          File.write(old_variant, 'current')
          with_cache_root(dir) { IG.discard_outdated_variants! }

          assert_path_exists old_variant, '版が同じなら作った扉絵を残す'
        end
      end

      private

      def skip_unless_magick
        skip 'ImageMagick (magick) が見つかりません' unless system('which magick >/dev/null 2>&1')
      end

      # 元の絵を作り、トリミングして対角線で分けた landscape の PNG を返す
      def make_variant(dir)
        source = File.join(dir, 'flower.png')
        run!('magick', '-size', '200x200', 'xc:none',
             '-fill', '#FFFFFF', '-draw', 'circle 50,50 50,20',
             '-fill', 'rgba(255,0,0,0.5)', '-draw', 'rectangle 130,130 180,180',
             "PNG32:#{source}")
        trimmed = File.join(dir, 'flower_trimmed.png')
        IG.trim_image_to(source, trimmed, nil)
        variant_png = File.join(dir, 'flower_landscape.png')
        IG.generate_diagonal_variant(trimmed, variant_png, 1.0 / 2.39)
        variant_png
      end

      # 拡大・縮小で画素の数が変わらないよう、出力の幅は並べ直した PNG の幅にそろえる
      def output_options(variant_png, waifu2x_available:, waifu2x: nil)
        width, = Common.image_size(variant_png)
        { variant: :landscape, waifu2x_available:, waifu2x:, waifu2x_args: [], waifu2x_noise: 1,
          scale: 2, target_width: width, webp_quality: 100, keep_intermediate: false }
      end

      def assert_flower_survives(dir, variant_png, webp)
        trimmed = File.join(dir, 'flower_trimmed.png')
        white_before = count(trimmed, 'a>0.99 && r>0.97 && g>0.97 && b>0.97')

        assert_operator white_before, :>, 2000, '元の絵の白い円が作れていない'
        # waifu2x の経路は 2 倍にしてから縮めるので、円の縁の画素が少しぼける（1 割まで許す）。
        # 白を抜いていたころは、白い円がほぼ全部透明になった
        [variant_png, webp].each do |image|
          assert_in_delta white_before, count(image, 'a>0.99 && r>0.97 && g>0.97 && b>0.97'), white_before * 0.1,
                          "#{File.basename(image)}: 白い円が不透明の白のまま残っていない"
          assert_in_delta count(trimmed, 'a>0.4 && a<0.6'), count(image, 'a>0.4 && a<0.6'), 150,
                          "#{File.basename(image)}: 半透明の四角がアルファ 0.5 のまま残っていない"
          assert_equal 0, count(image, 'a>0.9 && r>0.97 && g<0.9'),
                       "#{File.basename(image)}: 半透明の赤が白と混ざって不透明になっている"
        end
      end

      # 条件に合う画素の数
      def count(image, condition)
        out = run!('magick', image, '-alpha', 'set', '-fx', "#{condition} ? 1 : 0", '-alpha', 'off',
                   '-format', '%[fx:round(mean*w*h)]', 'info:')
        Integer(out.strip)
      end

      def run!(*cmd)
        out, status = Open3.capture2e(*cmd)
        raise "#{cmd.first} に失敗しました: #{out}" unless status.success?

        out
      end

      def with_cache_root(dir)
        originals = [TIR.instance_variable_get(:@theme_images_cache_root),
                     IG.instance_variable_get(:@revision_checked_root)]
        TIR.instance_variable_set(:@theme_images_cache_root, dir)
        IG.instance_variable_set(:@revision_checked_root, nil)
        yield
      ensure
        TIR.instance_variable_set(:@theme_images_cache_root, originals[0])
        IG.instance_variable_set(:@revision_checked_root, originals[1])
      end
    end
  end
end
