# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/kindle/transcode_webp_images.rb
# ================================================================
# 責務:
#   <img> の WebP を JPEG・PNG へ変換する
# ================================================================

require 'digest'
require 'fileutils'
require 'open3'
require_relative '../../epub/images'
require_relative '../../epub/workspace'
require_relative '../context'
require_relative '../../../post_process/html_parser'

module VivlioStarter
  module CLI
    module Build
      # <img> の WebP を JPEG・PNG へ変換する
      module Transforms::Kindle::TranscodeWebpImages
        module_function

        # ================================================================
        # EPUB 用 WebP → JPEG/PNG トランスコード（§5-1）
        # ================================================================
        # Kindle は WebP 非対応のため、EPUB の <img> 参照 WebP を JPEG/PNG へ変換し
        # src を差し替える（epub-kindle-webp-transcode-spec.md）。PDF 経路は
        # WebP のまま（無影響）。出力は images/_epub_assets/<hash>.{jpg,png} に集約し、
        # 元の png/jpg ソースの上書き・問題のあるファイル名（アポストロフィ等）の同梱を
        # 同時に避ける。CSS 背景の WebP は EPUB で描画されないため対象外（除外する）。
        # 劣化方針: 元画像が残っていれば WebP を経由せず元から変換（二重劣化回避）。
        # 出力形式: 透過/可逆は PNG（無劣化）、不透過写真は JPEG(q90)。
        # ================================================================

        # 各 HTML の <img src="*.webp"> を JPEG/PNG へ変換し src を差し替える。
        # 変換結果はソース src 文字列でメモ化し、同一画像の重複変換を避ける。
        #
        # @param html [String] 1 ページの HTML
        # @param ctx [Transforms::Context]
        # @return [String] 書き換えた HTML（変えなければ html のまま）
        def rewrite(html, ctx)
          # 変換の結果は、本の全部のページで使い回す（同じ画像を二度変換しない）
          cache = ctx.remember(:webp_replacements) { {} }
          transcode_webp_in_html(html, ctx, cache)
        end

        # 1 ページ分の <img> WebP 参照を変換・差し替える。
        # タグの文字列のまま src を置き換える（src の実体参照を保ち、変換の表の鍵にするため）。
        def transcode_webp_in_html(html, ctx, cache)
          changed = false
          gallery = gallery_image_srcs(html)

          updated = html.gsub(/<img\b[^>]*>/i) do |tag|
            src = tag[/\ssrc="([^"]*)"/i, 1]
            next tag unless src&.match?(/\.webp\z/i)

            full = gallery.include?(Epub::Images.decode_html_entities(src))
            staged = cache.fetch([src, full]) { cache[[src, full]] = stage_webp_replacement(src, ctx.page_dir, full:) }
            next tag unless staged

            changed = true
            tag.sub(/(\ssrc=")[^"]*(")/i, "\\1#{staged}\\2")
          end
          Common.log_info("[EPUB] #{ctx.page_name} の WebP 画像を JPEG/PNG へ差し替えました") if changed
          updated
        end

        # 写真を横に並べる囲み（.pictures・.image-group）の中にある画像の src。
        def gallery_image_srcs(html)
          return [] unless html.match?(/class="(?:pictures|image-group)\b/)

          doc = PostProcessCommands::HtmlParser.parse_html_document(html)
          doc.css('div.pictures img, div.image-group img').filter_map { it['src'] }.uniq
        end

        # src の WebP を変換し、staging の相対パスを返す。変換不能なら nil（src 据え置き）。
        # 変換元は cwd（ルート）の著者資産を読み、出力は base_dir（消費者 dir）配下の
        # images/_epub_assets/ に置く（著者 dir を汚さない・P4 §5.3）。
        #
        # full: 写真を横に並べる囲みの画像は、紙面での割合で縮めない（Epub::Images.convert_image）。
        def stage_webp_replacement(src_attr, base_dir, full: false)
          webp_path = Epub::Images.decode_html_entities(src_attr)
          # 著者資産（cwd 相対）で見つからない場合はワークスペース生成物（html/images/data/ 等）を
          # フォールバックで探す。DataImageResolver が置いた data 画像は cwd に実体が無い（spec §3.5）。
          unless File.exist?(webp_path)
            candidate = File.join(Common::BUILD_HTML_DIR, webp_path)
            webp_path = candidate if File.exist?(candidate)
          end
          return nil unless File.exist?(webp_path)

          source = transcode_source_for(webp_path)
          ext = epub_image_extension_for(source)
          key = Digest::SHA256.hexdigest(
            [File.expand_path(source), File.mtime(source).to_i, ext, (full ? 'full' : nil)].compact.join('|')
          )[0, 16]

          dir = File.join(base_dir, Common.images_dir, Epub::Workspace::EPUB_ASSETS_REL_SUBDIR)
          abs = File.join(dir, "#{key}.#{ext}")
          rel = "#{Common.images_dir}/#{Epub::Workspace::EPUB_ASSETS_REL_SUBDIR}/#{key}.#{ext}"
          return rel if File.exist?(abs)

          FileUtils.mkdir_p(dir)
          Epub::Images.convert_image(source, abs, ext, full:) ? rel : nil
        rescue StandardError => e
          Common.log_warn("[EPUB] WebP 変換に失敗（#{src_attr}）: #{e.message}")
          nil
        end

        # 変換元を決める。同名の元画像（png/jpg）が残っていれば二重劣化回避のため優先する。
        def transcode_source_for(webp_path)
          base = webp_path.sub(/\.webp\z/i, '')
          %w[.png .jpg .jpeg].each do |ext|
            candidate = "#{base}#{ext}"
            return candidate if File.exist?(candidate)
          end
          webp_path
        end

        # EPUB 用の出力拡張子を決める。透過/PNG/可逆 WebP は PNG（無劣化）、それ以外は JPEG。
        def epub_image_extension_for(source)
          return 'png' if File.extname(source).casecmp?('.png')
          return 'png' if Epub::Images.image_has_alpha?(source)
          return 'png' if webp_lossless?(source)

          'jpg'
        end

        # WebP が可逆圧縮か（magick identify -verbose の Compression 行）。webp 以外は false。
        def webp_lossless?(path)
          return false unless File.extname(path).casecmp?('.webp')

          out, status = Open3.capture2('magick', 'identify', '-verbose', path)
          status.success? && out.match?(/Compression:\s*Lossless/i)
        rescue StandardError
          false
        end
      end
    end
  end
end
