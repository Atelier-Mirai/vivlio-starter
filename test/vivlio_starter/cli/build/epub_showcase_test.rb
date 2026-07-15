# frozen_string_literal: true

# ================================================================
# Test: build/epub_showcase_test.rb
# ================================================================
# テスト対象:
#   Build::EpubBuilder の図解注釈（showcase）ローカライズ
#   （docs/specs/explanatory-diagram-spec.md §7.9）
#
# 検証内容:
#   - img.vs-showcase の src を data-vs-raster の値へ差し替える（EPUB は SVG 内 base64 を運べない）
#   - 形式は png / jpg のどちらもありうる（写真は JPEG・スクショは PNG）ため属性値をそのまま使う
#   - 使用後は data-vs-raster を取り除く
#   - ラスター実体が無ければ src を変えず警告に留める
#   - showcase 以外の SVG（数式など）や showcase 以外の img には触れない
#   - 合成 SVG は同梱対象から外れる（localized_image? が弾く）
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build/epub_builder'

module VivlioStarter
  module CLI
    class EpubShowcaseTest < Minitest::Test
      Builder = Build::EpubBuilder
      LOG_METHODS = %i[log_info log_success log_warn log_error log_action].freeze

      def setup
        @warnings = []
        @saved_logs = LOG_METHODS.to_h { [it, Common.method(it)] }
        LOG_METHODS.each { |name| Common.define_singleton_method(name) { |*, **| } }
        warnings = @warnings
        Common.define_singleton_method(:log_warn) { |msg, **| warnings << msg }
      end

      def teardown
        @saved_logs&.each { |name, m| Common.define_singleton_method(name, m) }
      end

      def test_should_rewrite_showcase_src_to_the_declared_raster
        in_temp_project do
          make_showcase_assets('10-intro', 'ab12cd34ef567890', ext: 'png')
          write_html('10-intro.html', 'ab12cd34ef567890', ext: 'png')

          Builder.localize_showcase_images!(['10-intro.html'])
          updated = File.read('10-intro.html')

          assert_includes updated, 'images/showcase/10-intro/ab12cd34ef567890.png'
          refute_includes updated, '.svg'
          # EPUB へは不要な属性なので取り除く
          refute_includes updated, 'data-vs-raster'
          assert_empty @warnings
        end
      end

      # 写真は JPEG で焼かれる。拡張子を推測せず属性値に従う（--no-clean での残骸を拾わない）
      def test_should_follow_the_raster_attribute_for_jpeg
        in_temp_project do
          make_showcase_assets('10-intro', 'ab12cd34ef567890', ext: 'jpg')
          write_html('10-intro.html', 'ab12cd34ef567890', ext: 'jpg')

          Builder.localize_showcase_images!(['10-intro.html'])
          updated = File.read('10-intro.html')

          assert_includes updated, 'images/showcase/10-intro/ab12cd34ef567890.jpg'
          assert_empty @warnings
        end
      end

      def test_should_keep_svg_src_and_warn_when_the_raster_is_missing
        in_temp_project do
          make_showcase_assets('10-intro', 'ab12cd34ef567890', ext: nil)
          write_html('10-intro.html', 'ab12cd34ef567890', ext: 'png')

          Builder.localize_showcase_images!(['10-intro.html'])
          updated = File.read('10-intro.html')

          assert_includes updated, 'ab12cd34ef567890.svg'
          assert_match(/図解注釈のラスター画像が見つかりません/, @warnings.join)
        end
      end

      def test_should_not_touch_other_images
        in_temp_project do
          html = <<~HTML
            <html><body>
            <figure class="vs-math vs-math-display"><img src="images/math/10-intro/deadbeef.svg" alt="x"></figure>
            <img src="images/10-intro/photo.png" alt="p">
            </body></html>
          HTML
          File.write('10-intro.html', html, encoding: 'utf-8')

          Builder.localize_showcase_images!(['10-intro.html'])
          updated = File.read('10-intro.html')

          assert_includes updated, 'images/math/10-intro/deadbeef.svg'
          assert_includes updated, 'images/10-intro/photo.png'
        end
      end

      # 合成 SVG は元画像を base64 で内包しており Kindle が非対応。参照は PNG へ移るため
      # 未参照になり、両フレーバとも同梱しない。対の PNG と他の SVG は同梱を続ける。
      def test_should_exclude_showcase_svg_from_localized_assets
        refute Builder.localized_image?('showcase/10-intro/ab12.svg', :epub)
        refute Builder.localized_image?('showcase/10-intro/ab12.svg', :kindle)
        assert Builder.localized_image?('showcase/10-intro/ab12.png', :epub)
        assert Builder.localized_image?('math/10-intro/deadbeef.svg', :epub)
      end

      private

      def in_temp_project(&)
        Dir.mktmpdir('vs-showcase-epub') do |dir|
          Dir.chdir(dir, &)
        end
      end

      # 前処理が焼いた生成物（ワークスペース html/images/showcase/）を用意する。
      # 実体確認は消費者 dir ではなく生成元に対して行われる（ローカライズは後段のため）。
      def make_showcase_assets(chapter_slug, key, ext:)
        dir = File.join(Common::BUILD_HTML_DIR, 'images', 'showcase', chapter_slug)
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, "#{key}.svg"), '<svg/>', encoding: 'utf-8')
        File.binwrite(File.join(dir, "#{key}.#{ext}"), 'RASTER') if ext
      end

      def write_html(path, key, ext:)
        rel = "images/showcase/10-intro/#{key}"
        File.write(path, %(<html><body><figure class="vs-showcase">) +
                         %(<img class="vs-showcase" src="#{rel}.svg" data-vs-raster="#{rel}.#{ext}" ) +
                         %(alt="図"></figure></body></html>),
                   encoding: 'utf-8')
      end
    end
  end
end
