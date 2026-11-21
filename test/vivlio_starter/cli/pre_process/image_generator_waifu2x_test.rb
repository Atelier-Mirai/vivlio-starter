# frozen_string_literal: true

# ================================================================
# Test: image_generator_waifu2x_test.rb
# ================================================================
# テスト対象:
#   ImageGenerator.generate_frontispiece_and_ornament_from が waifu2x を通すかの判断
#
# 検証内容（改善案 #143）:
#   - 並べ直した絵が仕上がりの幅の 2/3 以上なら、waifu2x を通さない
#   - それより小さい絵だけ waifu2x を通す
#   - waifu2x が無いときの警告は、拡大が要る絵のときだけ、1 回だけ出す
#
# 仕上がりの幅（target_width）を 300 に縮めて、小さい絵で速く確かめる。
# waifu2x の代わりに、呼ばれた入力を記録して ImageMagick で 2 倍にするだけの偽物を使う。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/pre_process'

module VivlioStarter
  module CLI
    class ImageGeneratorWaifu2xTest < Minitest::Test
      IG = PreProcessCommands::ImageGenerator
      TARGET_WIDTH = 300

      # 240 は 300 の 2/3（200）以上。扉絵・節絵とも waifu2x を通さない
      def test_should_skip_waifu2x_when_the_image_is_wide_enough
        in_project('big.png', 240) do |calls, warns|
          assert_empty calls, 'waifu2x を通している'
          assert_empty warns
          assert_path_exists '.cache/vs/theme-images/big_portrait.webp'
          assert_path_exists '.cache/vs/theme-images/big_landscape.webp'
        end
      end

      # 100 の扉絵は 2/3 に満たないので waifu2x を通す。節絵は 2.39:1 に並べ直すと幅が 239 で通さない
      def test_should_upscale_only_small_variants_with_waifu2x
        in_project('small.png', 100) do |calls, warns|
          assert_equal ['small_portrait.png'], calls.map { File.basename(it) }
          assert_empty warns
        end
      end

      # waifu2x が無いときは、拡大が要る絵のときだけ 1 回警告する
      def test_should_warn_once_only_when_upscale_is_needed_without_waifu2x
        in_project('small.png', 60, waifu2x: '/nonexistent/waifu2x-ncnn-vulkan') do |_calls, warns|
          assert_equal 1, warns.count { it.include?('ImageMagick のみで生成します') }
        end

        in_project('big.png', 240, waifu2x: '/nonexistent/waifu2x-ncnn-vulkan') do |_calls, warns|
          assert_empty warns, '拡大の要らない絵で waifu2x の不在を警告している'
        end
      end

      private

      # 一時プロジェクトに、全面に模様のある正方形の絵を置いて扉絵・節絵を作る
      def in_project(name, size, waifu2x: nil)
        skip 'ImageMagick (magick) が見つかりません' unless system('which magick >/dev/null 2>&1')

        Dir.mktmpdir('vs-waifu2x') do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p('stylesheets/images')
            system('magick', '-size', "#{size}x#{size}", 'gradient:navy-pink', "stylesheets/images/#{name}",
                   exception: true)
            log = File.join(dir, 'waifu2x-calls.txt')
            fake = File.join(dir, 'fake-waifu2x')
            File.write(fake, "#!/bin/sh\necho \"$2\" >> #{log}\nexec magick \"$2\" -resize 200% \"PNG32:$4\"\n")
            File.chmod(0o755, fake)

            warns = []
            result = nil
            Common.stub(:log_warn, ->(msg, **) { warns << msg }) do
              capture_io do
                result = IG.generate_frontispiece_and_ornament_from(name, waifu2x: waifu2x || fake,
                                                                          target_width: TARGET_WIDTH)
              end
            end

            assert result, '扉絵・節絵の生成に失敗した'
            yield(File.exist?(log) ? File.readlines(log, chomp: true) : [], warns)
          end
        end
      end
    end
  end
end
