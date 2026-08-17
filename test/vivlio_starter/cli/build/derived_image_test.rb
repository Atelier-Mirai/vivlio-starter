# frozen_string_literal: true

# ================================================================
# test/vivlio_starter/cli/build/derived_image_test.rb
# ================================================================
# PDF へ渡す画像の派生生成（`image-format-per-target-spec.md` §3.1 / §3.2）。
#
# 検証すること:
#   1. 透過が無い写真は JPEG になる（PDF が DCTDecode で無変換格納できる）
#   2. 透過がある絵は派生を作らない（PNG にしても PDF 内では素材と同じ Flate になる）
#   3. PNG のほうが小さい図は PNG になる（色数では分けられないので実測で選ぶ）
#   4. SVG は派生を作らない（ベクタのまま PDF へ入れるのが最善）
#   5. 2 回目はキャッシュを使い、素材が更新されたときだけ作り直す
#   6. **著者の images/ が 1 バイトも書き換わらない**（同 §6-9）
#
# magick 未導入時は skip（ImageMagick に依存するが OS は問わない）。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'digest'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/resize'
require 'vivlio_starter/cli/build/derived_image'

module VivlioStarter
  module CLI
    class DerivedImageTest < Minitest::Test
      Derived = Build::DerivedImage
      LOG_METHODS = %i[log_info log_success log_warn log_error log_action].freeze

      def setup
        skip 'ImageMagick (magick) が必要です' unless system('which magick > /dev/null 2>&1')
        @saved_logs = LOG_METHODS.to_h { [it, Common.method(it)] }
        LOG_METHODS.each { |name| Common.define_singleton_method(name) { |*, **| } }
      end

      def teardown
        @saved_logs&.each { |name, m| Common.define_singleton_method(name, m) }
      end

      # 写真（透過なし）は JPEG。PDF はこれをそのまま格納できる
      def test_should_derive_jpeg_from_opaque_photo
        in_temp_project do
          make_image('images/10-intro/photo.webp', '-size', '200x200', 'plasma:fractal')

          derived = Derived.prepare('images/10-intro/photo.webp')

          assert_equal '.cache/vs/derived/pdf/images/10-intro/photo.jpg', derived
          assert_path_exists derived
          refute_path_exists '.cache/vs/derived/pdf/images/10-intro/photo.png'
        end
      end

      # 透過がある絵は派生を作らない。JPEG は透過を持てず、PNG にしても PDF 内では
      # 素材と同じ Flate になるため、変換しても 1 バイトも縮まないからである
      def test_should_not_derive_from_transparent_image
        in_temp_project do
          make_image('images/10-intro/logo.webp',
                     '-size', '200x200', 'xc:none', '-fill', 'blue', '-draw', 'circle 100,100 100,30')

          assert_nil Derived.prepare('images/10-intro/logo.webp')
          refute_path_exists '.cache/vs/derived/pdf/images/10-intro/logo.png'
          refute_path_exists '.cache/vs/derived/pdf/images/10-intro/logo.jpg'
        end
      end

      # ベタ塗りの図は PNG のほうが小さい。色数では分けられないので実測で選ぶ
      def test_should_derive_png_when_png_is_smaller
        in_temp_project do
          make_image('images/10-intro/flat.webp', '-size', '200x200', 'xc:red')

          derived = Derived.prepare('images/10-intro/flat.webp')

          assert_equal '.cache/vs/derived/pdf/images/10-intro/flat.png', derived
          refute_path_exists '.cache/vs/derived/pdf/images/10-intro/flat.jpg'
        end
      end

      # SVG はベクタのまま PDF へ入れる
      def test_should_not_derive_from_svg
        in_temp_project do
          FileUtils.mkdir_p('images/10-intro')
          File.write('images/10-intro/icon.svg', '<svg xmlns="http://www.w3.org/2000/svg"/>')

          assert_empty Derived.prepare_all(['images/10-intro/icon.svg'])
        end
      end

      # 2 回目はキャッシュを使い、素材が更新されたときだけ作り直す
      def test_should_reuse_cache_until_source_changes
        in_temp_project do
          source = 'images/10-intro/photo.webp'
          make_image(source, '-size', '200x200', 'plasma:fractal')

          derived = Derived.prepare(source)
          first_mtime = File.mtime(derived)

          sleep 1.1 # mtime の粒度（秒）をまたぐ
          assert_equal derived, Derived.prepare(source)
          assert_equal first_mtime, File.mtime(derived), 'キャッシュがあるのに作り直している'

          FileUtils.touch(source)
          assert_equal derived, Derived.prepare(source)
          assert_operator File.mtime(derived), :>, first_mtime, '素材が新しいのに作り直していない'
        end
      end

      # 素材は読むだけ。著者の images/ を書き換えてはならない（§6-9）
      def test_should_never_modify_source_images
        in_temp_project do
          sources = {
            'images/10-intro/photo.webp' => ['-size', '200x200', 'plasma:fractal'],
            'images/10-intro/logo.webp' => ['-size', '200x200', 'xc:none'],
            'images/10-intro/flat.webp' => ['-size', '200x200', 'xc:red']
          }
          sources.each { |path, args| make_image(path, *args) }
          before = sources.keys.to_h { [it, [File.size(it), File.mtime(it), Digest::SHA256.file(it).hexdigest]] }

          mapping = Derived.prepare_all(sources.keys)

          # 透過ありの logo は派生を作らないので 3 件中 2 件
          assert_equal 2, mapping.size
          after = sources.keys.to_h { [it, [File.size(it), File.mtime(it), Digest::SHA256.file(it).hexdigest]] }
          assert_equal before, after, '素材が書き換わっている'
        end
      end

      private

      def in_temp_project(&)
        Dir.mktmpdir('vs-derived-image-') { Dir.chdir(it, &) }
      end

      def make_image(path, *magick_args)
        FileUtils.mkdir_p(File.dirname(path))
        system('magick', *magick_args, path, out: File::NULL, err: File::NULL)
        raise "フィクスチャ生成に失敗: #{path}" unless File.size?(path)
      end
    end
  end
end
