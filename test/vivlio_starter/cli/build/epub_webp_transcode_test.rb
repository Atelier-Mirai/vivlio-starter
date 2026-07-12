# frozen_string_literal: true

# ================================================================
# Test: build/epub_webp_transcode_test.rb
# ================================================================
# テスト対象:
#   Build::EpubBuilder の WebP→JPEG/PNG トランスコード
#   （docs/specs/epub-kindle-webp-transcode-spec.md §2・§6-1）
#
# 検証内容:
#   - <img src="*.webp"> を images/_epub_assets/<hash>.{jpg,png} へ差し替える
#   - 出力形式判定: 透過→PNG / 不透過写真→JPEG / 元が PNG→PNG
#   - 変換元優先: 同名の元 png/jpg があればそれを使う（拡張子で判定）
#   - &apos; / ' を含む src でも実ファイルを解決し差し替える（W14010 自動解消）
#   - 冪等性: 2 回実行で同一ハッシュ・出力が増えない
#
# magick 未導入時は skip（OS 非依存だが ImageMagick に依存）。
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build/epub_builder'

module VivlioStarter
  module CLI
    class EpubWebpTranscodeTest < Minitest::Test
      Builder = Build::EpubBuilder
      LOG_METHODS = %i[log_info log_success log_warn log_error log_action].freeze

      def setup
        skip 'ImageMagick (magick) が必要です' unless system('which magick > /dev/null 2>&1')
        @saved_logs = LOG_METHODS.to_h { [it, Common.method(it)] }
        LOG_METHODS.each { |name| Common.define_singleton_method(name) { |*, **| } }
      end

      def teardown
        @saved_logs&.each { |name, m| Common.define_singleton_method(name, m) }
      end

      # 不透過写真の WebP は JPEG へ変換し、src を staging へ差し替える
      def test_should_transcode_opaque_webp_to_jpeg_and_rewrite_src
        in_temp_project do
          make_webp('images/10-intro/photo.webp', 'xc:red')
          write_html('chapter.html', 'images/10-intro/photo.webp')

          Builder.transcode_webp_images_for_epub!(['chapter.html'])
          updated = File.read('chapter.html')

          assert_match %r{images/_epub_assets/[0-9a-f]{16}\.jpg}, updated
          refute_includes updated, 'photo.webp'
          assert File.exist?(staged_src(updated)), 'staging の JPEG が生成されているべき'
        end
      end

      # 透過のある WebP は PNG へ（透過保持・無劣化）
      def test_should_transcode_transparent_webp_to_png
        in_temp_project do
          make_webp('images/10-intro/icon.webp', 'xc:none')
          write_html('chapter.html', 'images/10-intro/icon.webp')

          Builder.transcode_webp_images_for_epub!(['chapter.html'])
          updated = File.read('chapter.html')

          assert_match %r{images/_epub_assets/[0-9a-f]{16}\.png}, updated
        end
      end

      # 同名の元 PNG が残っていれば、それを変換元に採用し PNG 出力（二重劣化回避）
      def test_should_prefer_original_png_source
        in_temp_project do
          make_webp('images/10-intro/diagram.webp', 'xc:blue')
          system('magick', '-size', '20x20', 'xc:blue', 'images/10-intro/diagram.png',
                 out: File::NULL, err: File::NULL)
          write_html('chapter.html', 'images/10-intro/diagram.webp')

          Builder.transcode_webp_images_for_epub!(['chapter.html'])
          updated = File.read('chapter.html')

          assert_match %r{images/_epub_assets/[0-9a-f]{16}\.png}, updated,
                       '元が PNG のため PNG 出力になるべき'
        end
      end

      # &apos; を含む src でも実ファイルを解決し、アポストロフィのない staging 名へ差し替える
      def test_should_resolve_apostrophe_entity_src
        in_temp_project do
          make_webp("images/94-sample/Einstein's_later_years.webp", 'xc:gray')
          write_html('chapter.html', 'images/94-sample/Einstein&apos;s_later_years.webp')

          Builder.transcode_webp_images_for_epub!(['chapter.html'])
          updated = File.read('chapter.html')

          refute_includes updated, '&apos;'
          refute_includes updated, "Einstein's"
          assert File.exist?(staged_src(updated))
        end
      end

      # cwd に実体が無く、ワークスペース html/images/data/ にある WebP を解決して変換する
      # （DataImageResolver が置いたデータ画像・spec §3.5）
      def test_should_fall_back_to_workspace_for_data_images
        in_temp_project do
          ws_webp = File.join(Common::BUILD_HTML_DIR, 'images', 'data', 'physics_books', 'relativity.webp')
          make_webp(ws_webp, 'xc:green')
          # HTML は消費者 dir 相対の images/data/… を参照する（cwd には実体が無い）
          write_html('chapter.html', 'images/data/physics_books/relativity.webp')
          refute File.exist?('images/data/physics_books/relativity.webp'), 'cwd には実体が無い前提'

          Builder.transcode_webp_images_for_epub!(['chapter.html'])
          updated = File.read('chapter.html')

          assert_match %r{images/_epub_assets/[0-9a-f]{16}\.(jpg|png)}, updated,
                       'ワークスペースの WebP から変換して差し替えるべき'
          refute_includes updated, 'relativity.webp'
          assert File.exist?(staged_src(updated))
        end
      end

      # 2 回実行しても同一ハッシュで、staging の出力が増えない（冪等）
      def test_should_be_idempotent
        in_temp_project do
          make_webp('images/10-intro/photo.webp', 'xc:red')
          write_html('chapter.html', 'images/10-intro/photo.webp')

          Builder.transcode_webp_images_for_epub!(['chapter.html'])
          first = File.read('chapter.html')
          count1 = Dir.glob('images/_epub_assets/*').size

          # 差し替え済みの HTML を再度走査しても WebP 参照は無いので変化しない。
          # 元 HTML を作り直してもう一度走査し、出力数が増えないことを確認する。
          write_html('chapter.html', 'images/10-intro/photo.webp')
          Builder.transcode_webp_images_for_epub!(['chapter.html'])
          second = File.read('chapter.html')
          count2 = Dir.glob('images/_epub_assets/*').size

          assert_equal staged_src(first), staged_src(second), '同一画像は同一ハッシュへ解決すべき'
          assert_equal count1, count2, '冪等: staging 出力が増えないべき'
        end
      end

      private

      def in_temp_project(&)
        Dir.mktmpdir('vs-webp-transcode') do |dir|
          Dir.chdir(dir, &)
        end
      end

      # magick で単色（または透過）の WebP フィクスチャを生成する
      def make_webp(path, color)
        FileUtils.mkdir_p(File.dirname(path))
        system('magick', '-size', '20x20', color, path, out: File::NULL, err: File::NULL)
        assert File.exist?(path), "フィクスチャ生成に失敗: #{path}"
      end

      def write_html(path, src)
        File.write(path, %(<html><body><img src="#{src}" alt="t"></body></html>), encoding: 'utf-8')
      end

      def staged_src(html)
        html[/src="([^"]+)"/, 1]
      end
    end
  end
end
