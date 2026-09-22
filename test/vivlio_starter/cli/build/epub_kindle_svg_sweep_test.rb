# frozen_string_literal: true

# ================================================================
# Test: build/epub_kindle_svg_sweep_test.rb
# ================================================================
# テスト対象:
#   Build::EpubBuilder.sweep_unreferenced_svg!
#   （Kindle パッケージから、参照の切れた SVG を回収する）
#
# 検証内容:
#   - 誰も参照していない SVG を落とす
#   - 本文・CSS が参照している SVG は残す
#   - 落とした跡の空ディレクトリを畳む
#   - 落とせなかった SVG があれば警告する
#   - クリーン EPUB（:epub）では何もしない
#
# 背景:
#   Kindle Previewer 4 は同梱された SVG を KVG へ変換しようとし、1 枚でも躓くと
#   Enhanced Typesetting ごと無効にして KPF ではなく Mobi を出す（実測 2026-09-22。
#   同じ EPUB が Previewer 3 では KPF になっていた）。空ディレクトリを残した場合は
#   変換そのものが失敗する——epubcheck は PKG-014 の警告で通すので気づけない。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build/epub_builder'

module VivlioStarter
  module CLI
    class EpubKindleSvgSweepTest < Minitest::Test
      Builder = Build::EpubBuilder
      LOG_METHODS = %i[log_info log_success log_warn log_error log_action].freeze

      SVG = %(<svg xmlns="http://www.w3.org/2000/svg"><rect width="4" height="4"/></svg>)

      def setup
        @warnings = []
        @saved_logs = LOG_METHODS.to_h { [it, Common.method(it)] }
        warnings = @warnings
        LOG_METHODS.each { |name| Common.define_singleton_method(name) { |*, **| } }
        Common.define_singleton_method(:log_warn) { |message, **| warnings << message }
      end

      def teardown
        @saved_logs&.each { |name, m| Common.define_singleton_method(name, m) }
      end

      # 参照の切れた SVG は落とし、参照されているものは残す。
      def test_should_drop_unreferenced_svg_and_keep_referenced_one
        in_package do |dir|
          write(dir, 'images/logo.svg', SVG)
          write(dir, 'images/math/97-sample/a1b2c3.svg', SVG)
          write(dir, 'stylesheets/twemoji/vs-techbook/circled-1.svg', SVG)
          write(dir, 'chapter.html', %(<html><body><img src="images/logo.svg"></body></html>))

          Builder.sweep_unreferenced_svg!(dir, flavor: :kindle)

          assert_path_exists File.join(dir, 'images/logo.svg'), '参照されている SVG を落としてはいけない'
          refute_path_exists File.join(dir, 'images/math/97-sample/a1b2c3.svg'), '孤児が残っている'
          refute_path_exists File.join(dir, 'stylesheets/twemoji/vs-techbook/circled-1.svg'), '孤児が残っている'
        end
      end

      # CSS の url() も参照とみなす。
      def test_should_treat_a_css_url_as_a_reference
        in_package do |dir|
          write(dir, 'images/bullet.svg', SVG)
          write(dir, 'chapter.html', '<html><body></body></html>')
          write(dir, 'stylesheets/chapter.css', 'li { list-style-image: url("../images/bullet.svg"); }')

          Builder.sweep_unreferenced_svg!(dir, flavor: :kindle)

          assert_path_exists File.join(dir, 'images/bullet.svg'), 'CSS からの参照を見落としている'
        end
      end

      # 落とした跡に空ディレクトリを残さない（残すと Previewer 4 が変換に失敗する）。
      def test_should_prune_directories_left_empty
        in_package do |dir|
          write(dir, 'images/math/97-sample/a1b2c3.svg', SVG)
          write(dir, 'chapter.html', '<html><body></body></html>')

          Builder.sweep_unreferenced_svg!(dir, flavor: :kindle)

          refute_path_exists File.join(dir, 'images/math/97-sample'), '空ディレクトリが残っている'
          refute_path_exists File.join(dir, 'images/math'), '入れ子の空ディレクトリが残っている'
          refute_path_exists File.join(dir, 'images'), '入れ子の空ディレクトリが残っている'
        end
      end

      # 中身の残るディレクトリは畳まない。
      def test_should_keep_directories_that_still_hold_something
        in_package do |dir|
          write(dir, 'images/math/97-sample/a1b2c3.svg', SVG)
          write(dir, 'images/math/97-sample/a1b2c3.png', 'PNG')
          write(dir, 'chapter.html', %(<html><body><img src="images/math/97-sample/a1b2c3.png"></body></html>))

          Builder.sweep_unreferenced_svg!(dir, flavor: :kindle)

          refute_path_exists File.join(dir, 'images/math/97-sample/a1b2c3.svg'), '孤児が残っている'
          assert_path_exists File.join(dir, 'images/math/97-sample/a1b2c3.png'), 'PNG まで消している'
        end
      end

      # 落とせなかった SVG は、そのまま出すと KPF にならない。警告して知らせる。
      def test_should_warn_when_an_svg_survives_in_the_kindle_package
        in_package do |dir|
          write(dir, 'images/logo.svg', SVG)
          write(dir, 'chapter.html', %(<html><body><img src="images/logo.svg"></body></html>))

          Builder.sweep_unreferenced_svg!(dir, flavor: :kindle)

          assert_equal 1, @warnings.size, "警告が出ていない: #{@warnings.inspect}"
          assert_includes @warnings.first, 'logo.svg'
        end
      end

      # クリーン EPUB はベクタのまま運ぶ。ここで手を出してはいけない。
      def test_should_do_nothing_for_the_clean_epub
        in_package do |dir|
          write(dir, 'images/math/97-sample/a1b2c3.svg', SVG)
          write(dir, 'chapter.html', '<html><body></body></html>')

          Builder.sweep_unreferenced_svg!(dir, flavor: :epub)

          assert_path_exists File.join(dir, 'images/math/97-sample/a1b2c3.svg'), 'クリーン EPUB の SVG を落としている'
          assert_empty @warnings
        end
      end

      private

      def in_package
        Dir.mktmpdir('vs-svg-sweep') { yield File.join(_1, 'kindle').tap { FileUtils.mkdir_p(it) } }
      end

      def write(dir, path, content)
        full = File.join(dir, path)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, content, encoding: 'utf-8')
      end
    end
  end
end
