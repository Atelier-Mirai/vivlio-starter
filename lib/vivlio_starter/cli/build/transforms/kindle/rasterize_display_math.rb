# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/kindle/rasterize_display_math.rb
# ================================================================
# 責務:
#   ディスプレイ数式を PNG へ焼く
# ================================================================

require 'open3'
require_relative '../context'
require_relative '../../../post_process/html_parser'
require_relative '../../../pre_process/generated_asset_cache'

module VivlioStarter
  module CLI
    module Build
      # ディスプレイ数式を PNG へ焼く
      module Transforms::Kindle::RasterizeDisplayMath
        module_function

        # ディスプレイ数式のラスター化（Kindle 限定・§3-2.4）。
        # SVG は viewBox しか持たないので、焼く幅を <img> の ex 値から見積もる。
        # 1ex ≒ 8px（本文 16px 相当）に 3 倍のスケールを掛け、高 DPI でも粗く見えないようにする。
        DISPLAY_MATH_RASTER_KIND = 'math-png'
        DISPLAY_MATH_EX_PX = 8
        DISPLAY_MATH_SCALE = 3
        DISPLAY_MATH_FALLBACK_EX = 30 # style に ex が無いとき（通常起きない）の見積もり
        DISPLAY_MATH_MIN_PX = 200
        DISPLAY_MATH_MAX_PX = 2000

        # ディスプレイ数式（figure.vs-math-display の <img>）を PNG へ差し替える。
        # Kindle 限定（plain-math-notation-spec.md §3-2.4）。
        #
        # なぜテキスト化でなくラスターか: ディスプレイ数式は `Σ` や `∫` を含む大きな式を
        # 独立行に組むための記法で、組版を保つことに意味がある。行を占有するので px 固定でも
        # 破綻しない。加えて KFX の SVG 対応は不確実（kindle-inline-math-textify-spec.md §1-4）
        # なので、PNG のほうが確実に運べる。日本語を含む式の `<text>` 問題もここで消える
        # ——ラスターはビルド機で焼くのでフォントが必ず在る。
        #
        # **クリーン EPUB はラスター化しない。** 数式 SVG はパスだけで安全であり、
        # Kobo・Apple では拡大に強いベクタの利点が残る（§3-2.2）。
        # rsvg-convert 不在・変換失敗時は SVG のまま残して警告する（ビルドは止めない）。
        def call(html_files, _ctx)
          return html_files unless rsvg_available?

          html_files.each do |path|
            doc = PostProcessCommands::HtmlParser.parse_html_document(File.read(path, encoding: 'utf-8'))
            images = doc.css('figure.vs-math-display img')
            next if images.empty?

            replaced = images.count { rasterize_display_math_image!(it, path) }
            next if replaced.zero?

            PostProcessCommands::HtmlParser.save_html_document(path, doc)
            Common.log_info("[EPUB] #{File.basename(path)} のディスプレイ数式 #{replaced} 件を PNG へ差し替えました")
          end
          html_files
        end

        # <img> 1 つを PNG へ差し替える。差し替えたら true。
        def rasterize_display_math_image!(img, html_path)
          src = img['src'].to_s
          return false unless src.end_with?('.svg')

          svg_path = File.join(Common::BUILD_HTML_DIR, src)
          return false unless File.exist?(svg_path)

          png = "#{File.basename(src, '.svg')}.png"
          out_dir = File.dirname(svg_path)
          ok = PreProcessCommands::GeneratedAssetCache.fetch(DISPLAY_MATH_RASTER_KIND, [png], out_dir:) do |cache|
            write_display_math_png(svg_path, File.join(cache, png), img)
          end
          unless ok
            Common.log_warn(
              "[EPUB] ディスプレイ数式をラスター化できませんでした: #{src}",
              detail: "→ #{File.basename(html_path)} は SVG 参照のまま出力します（Kindle で表示されない可能性があります）"
            )
            return false
          end

          img['src'] = "#{File.dirname(src)}/#{png}"
          true
        end

        # SVG を PNG へ焼く。幅は <img> の style に写された ex 値から見積もる
        # （SVG 本体は viewBox だけで固有寸法を持たないため、指定しないと既定値で小さく焼ける）。
        def write_display_math_png(svg_path, png_path, img)
          ex = img['style'].to_s[/width:\s*([\d.]+)ex/, 1].to_f
          width = ((ex.positive? ? ex : DISPLAY_MATH_FALLBACK_EX) * DISPLAY_MATH_EX_PX * DISPLAY_MATH_SCALE).round
          width = width.clamp(DISPLAY_MATH_MIN_PX, DISPLAY_MATH_MAX_PX)
          png, status = Open3.capture2('rsvg-convert', '-w', width.to_s, '-f', 'png', svg_path, binmode: true)
          return false unless status.success? && !png.empty?

          File.binwrite(png_path, png)
          true
        rescue StandardError => e
          Common.log_debug("[EPUB] rsvg-convert に失敗しました: #{e.class}: #{e.message}")
          false
        end

        def rsvg_available?
          return @rsvg_available unless @rsvg_available.nil?

          @rsvg_available = system('rsvg-convert', '--version', out: File::NULL, err: File::NULL) || false
          Common.log_warn('[EPUB] rsvg-convert が無いため、ディスプレイ数式は SVG のまま出力します') unless @rsvg_available
          @rsvg_available
        end
      end
    end
  end
end
