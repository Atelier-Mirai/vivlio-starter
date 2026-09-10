# frozen_string_literal: true

# ================================================================
# Test: build/epub_author_svg_test.rb
# ================================================================
# テスト対象:
#   Build::EpubBuilder.stage_author_svg_for_epub!
#   （著者の SVG 図版を、書体を抱かせた派生へ差し替える・
#     `type3-font-embedding-notes.md` §9.6）
#
# 検証内容:
#   - クリーン EPUB（:epub）はベクタのまま置く（拡張子 .svg・@font-face を内包）
#   - Kindle（:kindle）は KFX が SVG を扱えないので PNG / JPEG へ焼く
#   - 差し替えた元 SVG はパッケージから落とす（未参照の重複を残さない）
#   - 素材（images/ の原本）は書き換えない
#   - 文字を持たない図は素材のまま運ぶ（複製しない）
#
# 背景:
#   ラスタライズで逃げる手は採れない。librsvg は data: URI の @font-face を読まず、
#   macOS では fontconfig 登録も見ないため、焼いた機械の OS 書体が焼き付いて
#   成果物が再現しない。だからクリーン EPUB はベクタのまま運ぶ。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/pre_process'
require 'vivlio_starter/cli/build/epub_builder'

module VivlioStarter
  module CLI
    class EpubAuthorSvgTest < Minitest::Test
      Builder = Build::EpubBuilder
      LOG_METHODS = %i[log_info log_success log_warn log_error log_action].freeze

      # 同梱書体の実体（サブセットを実際に作るために要る）。
      REAL_FONT = File.expand_path('../../../../stylesheets/fonts/Zen_Kaku_Gothic_New/ZenKakuGothicNew-Regular.ttf',
                                   __dir__)

      FIGURE = <<~SVG
        <svg xmlns="http://www.w3.org/2000/svg" width="100%" viewBox="0 0 200 80">
        <text x="10" y="40" font-family="sans-serif" font-size="14">座標</text></svg>
      SVG

      def setup
        skip 'ImageMagick (magick) が必要です' unless system('which magick > /dev/null 2>&1')
        skip 'librsvg (rsvg-convert) が必要です' unless system('which rsvg-convert > /dev/null 2>&1')
        skip '同梱書体が無い環境では検証できない' unless File.file?(REAL_FONT)

        @saved_logs = LOG_METHODS.to_h { [it, Common.method(it)] }
        LOG_METHODS.each { |name| Common.define_singleton_method(name) { |*, **| } }
        @saved_config = Common::CONFIG
      end

      def teardown
        @saved_logs&.each { |name, m| Common.define_singleton_method(name, m) }
        Common.install_configuration!(@saved_config)
      end

      # クリーン EPUB はベクタのまま。書体は SVG 自身が抱える。
      def test_should_keep_the_figure_as_vector_for_clean_epub
        in_temp_project do
          write_svg('images/22-ext/coords.svg', FIGURE)
          html = stage_html('images/22-ext/coords.svg')

          Builder.stage_author_svg_for_epub!([html], flavor: :epub)

          staged = staged_src(File.read(html))

          assert_match %r{\Aimages/_epub_assets/[0-9a-f]{16}\.svg\z}, staged
          body = File.read(File.join('epub', staged))

          assert_includes body, '@font-face'
          assert_includes body, 'data:font/ttf;base64,'
          assert_includes body, 'Zen Kaku Gothic New, sans-serif'
        end
      end

      # Kindle は KFX が SVG を扱えないのでラスタへ焼く。
      def test_should_rasterize_the_figure_for_kindle
        in_temp_project do
          write_svg('images/22-ext/coords.svg', FIGURE)
          html = stage_html('images/22-ext/coords.svg')

          Builder.stage_author_svg_for_epub!([html], flavor: :kindle)

          staged = staged_src(File.read(html))

          assert_match %r{\Aimages/_epub_assets/[0-9a-f]{16}\.(png|jpg)\z}, staged
          assert File.size?(File.join('epub', staged)), 'ラスタが空'
          # 中間 PNG を置き去りにしない
          assert_empty Dir.glob('epub/images/_epub_assets/*.tmp.png')
        end
      end

      # 差し替えた元 SVG はパッケージから落とす。素材（images/）には触れない。
      def test_should_drop_the_packaged_original_and_leave_the_source_untouched
        in_temp_project do
          write_svg('images/22-ext/coords.svg', FIGURE)
          html = stage_html('images/22-ext/coords.svg')

          Builder.stage_author_svg_for_epub!([html], flavor: :epub)

          refute_path_exists 'epub/images/22-ext/coords.svg', 'パッケージに元 SVG が残っている'
          assert_equal FIGURE, File.read('images/22-ext/coords.svg'), '素材が書き換えられている'
        end
      end

      # 文字を持たない図は素材のまま運ぶ。複製すればパッケージが太るだけである。
      def test_should_leave_a_figure_without_text_alone
        in_temp_project do
          write_svg('images/22-ext/shapes.svg',
                    %(<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10"/></svg>))
          html = stage_html('images/22-ext/shapes.svg')

          Builder.stage_author_svg_for_epub!([html], flavor: :epub)

          assert_equal 'images/22-ext/shapes.svg', staged_src(File.read(html))
          assert_path_exists 'epub/images/22-ext/shapes.svg', 'パッケージから落としてはいけない'
        end
      end

      # 2 回通しても同じ鍵に落ち、出力が増えない。
      def test_should_be_idempotent
        in_temp_project do
          write_svg('images/22-ext/coords.svg', FIGURE)
          html = stage_html('images/22-ext/coords.svg')

          Builder.stage_author_svg_for_epub!([html], flavor: :epub)
          first = staged_src(File.read(html))
          Builder.stage_author_svg_for_epub!([html], flavor: :epub)

          assert_equal first, staged_src(File.read(html))
          assert_equal 1, Dir.glob('epub/images/_epub_assets/*').size
        end
      end

      private

      # 書体を置いた一時プロジェクトで実行する。消費者 dir は epub/ を使う。
      def in_temp_project
        Dir.mktmpdir('vs-author-svg') do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p('stylesheets/fonts/Zen_Kaku_Gothic_New')
            FileUtils.cp(REAL_FONT, 'stylesheets/fonts/Zen_Kaku_Gothic_New/ZenKakuGothicNew-Regular.ttf')
            Common.install_configuration!(
              Common.build_direct_configuration(typography: { heading: { font: 'Zen Kaku Gothic New' } })
            )
            yield
          end
        end
      end

      def write_svg(path, content)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content, encoding: 'utf-8')
      end

      # ローカライズ済みの消費者 dir を再現する（HTML と、その隣にコピーされた図）。
      def stage_html(src)
        FileUtils.mkdir_p(File.dirname(File.join('epub', src)))
        FileUtils.cp(src, File.join('epub', src))
        path = File.join('epub', 'chapter.html')
        File.write(path, %(<html><body><img src="#{src}" alt="t"></body></html>), encoding: 'utf-8')
        path
      end

      def staged_src(html) = html[/src="([^"]+)"/, 1]
    end
  end
end
