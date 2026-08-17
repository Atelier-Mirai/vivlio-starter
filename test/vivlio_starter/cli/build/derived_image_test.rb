# frozen_string_literal: true

# ================================================================
# test/vivlio_starter/cli/build/derived_image_test.rb
# ================================================================
# PDF へ渡す画像の派生生成（`image-format-per-target-spec.md` §3.1 / §3.2）。
#
# 検証すること:
#   1. 透過が無い写真は JPEG になる（PDF が DCTDecode で無変換格納できる）
#   2. 透過がある絵は白へ落として PDF へ渡す（地が紙の白なので見た目は変わらない）
#      素材そのものの透過は保たれる（EPUB / Kindle は原本を読む）
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
        # 測定結果はプロセス内にも載るので、テスト間で持ち越さない
        Derived.reset_cache!
        @saved_logs = LOG_METHODS.to_h { [it, Common.method(it)] }
        LOG_METHODS.each { |name| Common.define_singleton_method(name) { |*, **| } }
      end

      def teardown
        @saved_logs&.each { |name, m| Common.define_singleton_method(name, m) }
        Derived.reset_cache!
      end

      # 写真（透過なし）は JPEG。PDF はこれをそのまま格納できる
      def test_should_derive_jpeg_from_opaque_photo
        in_temp_project do
          make_image('images/10-intro/photo.webp', '-size', '200x200', 'plasma:fractal')

          derived = Derived.prepare('images/10-intro/photo.webp')

          assert_equal '.cache/vs/derived/pdf/images/10-intro/photo.jpg', derived.path
          assert_path_exists derived.path
          refute_path_exists '.cache/vs/derived/pdf/images/10-intro/photo.png'
        end
      end

      # 透過がある絵は白へ落とす。PDF の地は紙の白なので見た目は変わらず、透過を抱えた
      # まま Flate で入るより桁違いに小さくなる（EPUB / Kindle は素材の原本を読むので
      # 影響を受けない）。拡張子は素材次第なので固定せず、透過が落ちたことだけを見る
      def test_should_flatten_transparent_image_for_pdf
        in_temp_project do
          make_image('images/10-intro/logo.webp',
                     '-size', '200x200', 'xc:none', '-fill', 'blue', '-draw', 'circle 100,100 100,30')

          derived = Derived.prepare('images/10-intro/logo.webp')

          assert_path_exists derived.path
          assert_equal 'True', opaque_of(derived.path), 'PDF 向けの派生に透過が残っている'
        end
      end

      # 素材の透過は保たれる。EPUB / Kindle はこちらを読む
      def test_should_keep_transparency_in_source
        in_temp_project do
          source = 'images/10-intro/logo.webp'
          make_image(source, '-size', '200x200', 'xc:none', '-fill', 'blue', '-draw', 'circle 100,100 100,30')

          Derived.prepare(source)

          assert_equal 'False', opaque_of(source), '素材の透過が失われている'
        end
      end

      # ベタ塗りの図は PNG のほうが小さい。色数では分けられないので実測で選ぶ
      def test_should_derive_png_when_png_is_smaller
        in_temp_project do
          make_image('images/10-intro/flat.webp', '-size', '200x200', 'xc:red')

          derived = Derived.prepare('images/10-intro/flat.webp')

          assert_equal '.cache/vs/derived/pdf/images/10-intro/flat.png', derived.path
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

          derived = Derived.prepare(source).path
          first_mtime = File.mtime(derived)

          sleep 1.1 # mtime の粒度（秒）をまたぐ
          assert_equal derived, Derived.prepare(source).path
          assert_equal first_mtime, File.mtime(derived), 'キャッシュがあるのに作り直している'

          FileUtils.touch(source)
          assert_equal derived, Derived.prepare(source).path
          assert_operator File.mtime(derived), :>, first_mtime, '素材が新しいのに作り直していない'
        end
      end

      # 測った必要画素数を段階へ切り上げて縮める。1,073px 要るなら 800 ではなく 1280——
      # 下回らせると印刷で粗さとして残り、後から取り戻せない（§3.6）
      def test_should_shrink_to_the_step_above_what_is_needed
        in_temp_project do
          source = 'images/10-intro/photo.webp'
          make_image(source, '-size', '2048x2048', 'plasma:fractal')
          write_metrics('2048x2048' => 1073)

          derived = Derived.prepare(source)

          assert_equal 1280, width_of(derived.path)
          assert_includes derived.path, '_1280'
          # 属性へ書き出す intrinsic size は**素材の**画素数（表示サイズを動かさないため）
          assert_equal 2048, derived.width
        end
      end

      # 段階を超える必要があるときは必要画素数そのものへ丸める。2048px で打ち止めに
      # すると、版面全幅に置かれた 4K 素材がそのまま運ばれてしまう
      def test_should_use_exact_size_when_beyond_the_largest_step
        in_temp_project do
          source = 'images/10-intro/wide.webp'
          make_image(source, '-size', '3840x2160', 'plasma:fractal')
          write_metrics('3840x2160' => 2340)

          derived = Derived.prepare(source)

          assert_equal 2340, width_of(derived.path)
        end
      end

      # 足りている素材は拡大しない。縮小も派生名の接尾辞も付かない
      def test_should_not_enlarge_when_source_is_already_small
        in_temp_project do
          source = 'images/10-intro/small.webp'
          make_image(source, '-size', '400x400', 'plasma:fractal')
          write_metrics('400x400' => 1280)

          derived = Derived.prepare(source)

          assert_equal 400, width_of(derived.path)
          refute_includes derived.path, '_1280'
        end
      end

      # --- EPUB / Kindle 向け（リフローなので「組んでから測る」ができない） ---

      # 版面に対する割合を画面幅へ掛ける。版面の半分に並べた見本は EPUB でも画面の半分
      def test_should_scale_viewport_target_by_the_measured_ratio
        in_temp_project do
          write_metrics('2048x2048' => { 'px' => 1073, 'ratio' => 0.458 })

          assert_equal 938, Derived.viewport_target(2048, 2048, 2048)  # EPUB
          assert_equal 469, Derived.viewport_target(2048, 2048, 1024)  # Kindle
        end
      end

      # 版面いっぱいの絵は画面幅いっぱいが要る
      def test_should_use_full_viewport_for_full_width_image
        in_temp_project do
          write_metrics('2048x2048' => { 'px' => 2343, 'ratio' => 1.0 })

          assert_equal 2048, Derived.viewport_target(2048, 2048, 2048)
        end
      end

      # 測っていなければ画面幅そのもの（＝安全側。縮めすぎるより素材のまま運ぶ）
      def test_should_fall_back_to_viewport_when_not_measured
        in_temp_project do
          assert_equal 2048, Derived.viewport_target(999, 999, 2048)
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

          assert_equal sources.size, mapping.size
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

      def opaque_of(path) = `magick identify -format '%[opaque]' #{path}`.strip

      def width_of(path) = `magick identify -format '%w' #{path}`.strip.to_i

      # 測定結果を直に置く（実 PDF を組まずに縮小の判定だけを確かめる）。
      # 値は必要画素数だけを渡せばよく、割合は既定 1.0（版面いっぱい）で埋める。
      def write_metrics(map)
        FileUtils.mkdir_p('.cache/vs/derived')
        entries = map.transform_values do |value|
          value.is_a?(Hash) ? value : { 'px' => value, 'ratio' => 1.0 }
        end
        File.write('.cache/vs/derived/image-metrics.yml', entries.to_yaml)
        Derived.reset_cache!
      end
    end
  end
end
