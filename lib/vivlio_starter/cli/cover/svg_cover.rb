# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/cover/svg_cover.rb
# ================================================================
# 責務:
#   SVG を元にする表紙（同梱テンプレートの light / dark と、著者が置いた
#   covers/<side>cover_<theme>.svg）を組み立て、PDF と電子書籍用の JPEG にする。
#   どちらのソースを使うかは CoverCommands.resolve_source が決める。
#
# SVG テンプレートのプレースホルダー:
#   CSS 変数（<style> の :root）:
#     --vs-text-main, --vs-text-sub, --vs-text-author, --vs-text-label,
#     --vs-grid-stroke, --vs-stroke-outer, --vs-stroke-mid, --vs-stroke-inner,
#     --vs-node-fill, --vs-node-stroke, --vs-icon-color
#   グラデーションの stop-color（rsvg-convert が CSS 変数を読まないため直接置き換える）:
#     {{bg-from}}, {{bg-to}}
#   文字:
#     {{title}}, {{subtitle}}, {{author}}, {{series}}, {{release}}
#
#   同梱テンプレートは light の値を持つ。dark ではパレットを差し替える。
#   著者の SVG には文字だけを当てる（色は著者が決めているため）。
# ================================================================

require 'fileutils'
require 'tmpdir'
require_relative '../common'
require_relative '../units'
require_relative '../build/cmyk_converter'
require_relative '../build/nombre_stamper'

module VivlioStarter
  module CLI
    module CoverCommands
      module SvgCover
        module_function

        # 同梱テンプレートの CSS 変数と stop-color の置き換え表。
        # キーは <style> の CSS カスタムプロパティ名、または {{}} のプレースホルダー。
        LIGHT_PALETTE = {
          '{{bg-from}}' => '#f8f6f2',
          '{{bg-to}}' => '#f0ece4',
          '--vs-text-main' => '#1e3a60',
          '--vs-text-sub' => '#8090a8',
          '--vs-text-author' => '#2a4070',
          '--vs-text-label' => '#7080a0',
          '--vs-grid-stroke' => '#d0d0d0',
          '--vs-stroke-outer' => '#e0e0e0',
          '--vs-stroke-mid' => '#e8e8e8',
          '--vs-stroke-inner' => '#d0d0d0',
          '--vs-node-fill' => '#ffffff',
          '--vs-node-stroke' => '#1e3a60',
          '--vs-icon-color' => '#1e3a60'
        }.freeze

        DARK_PALETTE = {
          '{{bg-from}}' => '#0e1a2e',
          '{{bg-to}}' => '#060d1a',
          '--vs-text-main' => '#f0e8d0',
          '--vs-text-sub' => '#a8b8d0',
          '--vs-text-author' => '#d0c0a0',
          '--vs-text-label' => '#7080a0',
          '--vs-grid-stroke' => '#1e3358',
          '--vs-stroke-outer' => '#1a3560',
          '--vs-stroke-mid' => '#1e4070',
          '--vs-stroke-inner' => '#2a5590',
          '--vs-node-fill' => '#0e2040',
          '--vs-node-stroke' => '#4a80c8',
          '--vs-icon-color' => '#5b9ef5'
        }.freeze

        # 片面の SVG から、targets に応じた成果物を作る。
        #   pdf         → <side>cover_<theme>_<size>_rgb.pdf（仕上がりサイズ）
        #   print_pdf   → <side>cover_<theme>_<size>_cmyk.pdf（塗り足し・トンボ付き）→ 直下へ複製
        #   epub/kindle → cover_<theme>.jpg（表のみ）→ 直下へ複製
        #
        # @param side [String] 'front' / 'back'
        # @param source [String] 元の SVG（同梱テンプレートか著者の SVG）
        # @param bundled [Boolean] 同梱テンプレートか（パレットを当てるか）
        def write_outputs!(side, source, theme, page_size, targets, bundled:)
          # --- Phase: SVG の組み立て（常に作り直す。book.yml とテンプレートの変更を拾うため） ---
          svg = render_svg(source, side, theme, bundled:)
          trim_w_mm, trim_h_mm = CoverCommands::SIZES.fetch(page_size)[:mm]
          cache_dir = Common.cover_cache_dir

          # --- Phase: 成果物 ---
          if targets.include?('pdf')
            pdf = File.join(cache_dir, "#{side}cover_#{theme}_#{page_size}_rgb.pdf")
            convert_svg_to_pdf(svg, pdf, trim_w_mm, trim_h_mm) && Common.log_info("カバーを生成しました: #{File.basename(pdf)}")
          end

          if targets.include?('print_pdf')
            pdf = File.join(cache_dir, "#{side}cover_#{theme}_#{page_size}_cmyk.pdf")
            convert_svg_to_pdf_with_crop_marks(svg, pdf, trim_w_mm, trim_h_mm)
            CoverCommands.publish_print_cover!(side, pdf)
          end

          return unless side == 'front' && CoverCommands.ebook_target?(targets)

          write_ebook_cover(svg, File.join(cache_dir, "cover_#{theme}.jpg"), page_size)
        end

        # 表紙の SVG を組み立ててキャッシュに書き、そのパスを返す。
        # covers/ に書かないのは、著者の SVG（covers/<side>cover_<theme>.svg）と同じ名前になり、
        # 生成物をソースと取り違えるため（generated-assets 移設仕様 §3.5）。
        # rsvg-convert は CSS の var() を読まないので、どちらの SVG も変数を展開してから書く。
        def render_svg(source, side, theme, bundled:)
          svg = File.read(source, encoding: 'utf-8')
          svg = apply_palette(svg, theme == 'dark' ? DARK_PALETTE : LIGHT_PALETTE) if bundled
          svg = expand_css_custom_properties(apply_text_replacements(svg))

          output = File.join(Common.cover_cache_dir, bundled ? "#{side}cover_#{theme}.svg" : "#{side}cover_#{theme}_rendered.svg")
          FileUtils.mkdir_p(File.dirname(output))
          File.write(output, svg, encoding: 'utf-8')
          output
        end

        # パレットを当てる。CSS 変数は "--vs-xxx: <値>;" の値を差し替え、
        # {{bg-from}} などの stop-color のプレースホルダーはそのまま置き換える。
        def apply_palette(svg, palette)
          palette.reduce(svg) do |result, (key, value)|
            if key.start_with?('--')
              result.gsub(/#{Regexp.escape(key)}\s*:\s*[^;]+;/, "#{key}: #{value};")
            else
              result.gsub(key, value)
            end
          end
        end

        # book.yml の書誌を {{title}} などへ埋める。SVG の構造と装飾には触れない。
        # SVG の <text> には文字しか入れられないので、扉で改行させる <br> などのタグは外し
        # （Common.plain_title）、& や < は文字参照にする（そのまま入ると SVG が壊れる）
        def apply_text_replacements(svg)
          placeholders = {
            '{{title}}' => Common.plain_title(Common::CONFIG.dig(:book, :main_title)),
            '{{subtitle}}' => Common.plain_title(Common::CONFIG.dig(:book, :subtitle)),
            '{{author}}' => Common::CONFIG.dig(:book, :author),
            '{{series}}' => Common::CONFIG.dig(:book, :series),
            '{{release}}' => Common::CONFIG.dig(:book, :release)
          }
          placeholders.reduce(svg) { |result, (placeholder, value)| result.gsub(placeholder, CGI.escapeHTML(value.to_s)) }
        end

        # :root で定義した CSS カスタムプロパティを、var(--xxx) の所へ展開する。
        def expand_css_custom_properties(svg_content)
          variables = extract_css_variables(svg_content)
          return svg_content if variables.empty?

          resolve_css_variables(svg_content, variables)
        end

        # <style> の :root { ... } からカスタムプロパティを集める。
        # @return [Hash{String => String}] { "--vs-text-main" => "#f0e8d0", ... }
        def extract_css_variables(svg_content)
          variables = {}
          svg_content.scan(%r{<style[^>]*>(.*?)</style>}m).flatten.each do |block|
            block.scan(/:root\s*\{([^}]*)\}/m).flatten.each do |root_block|
              root_block.scan(/(--[\w-]+)\s*:\s*([^;]+);/) { |name, value| variables[name.strip] = value.strip }
            end
          end
          variables
        end

        # var(--xxx) / var(--xxx, fallback) を解決する。変数が変数を指すこともあるので、
        # 残らなくなるまで繰り返す（循環に備えて 10 回まで）。
        def resolve_css_variables(svg_content, variables, depth: 10)
          return svg_content if depth.zero?

          resolved = svg_content.gsub(/var\((--[\w-]+)(?:\s*,\s*([^)]*))?\)/) do
            variables.fetch(::Regexp.last_match(1), ::Regexp.last_match(2)&.strip || 'unset')
          end

          resolved.include?('var(') ? resolve_css_variables(resolved, variables, depth: depth - 1) : resolved
        end

        # 電子書籍用の JPEG を作る（ebook-cover-jpeg-spec.md §3）。判型の比のまま縦 2,560 px の
        # PNG に焼き、あとは PNG の表紙と同じ作り方（CoverCommands.write_ebook_cover!）に渡す。
        def write_ebook_cover(svg_path, jpg_path, page_size)
          trim_w_mm, trim_h_mm = CoverCommands::SIZES.fetch(page_size, CoverCommands::SIZES[:b5])[:mm]
          h_px = CoverCommands::EPUB_SIZE[:height]
          w_px = (h_px * trim_w_mm / trim_h_mm.to_f).round

          Dir.mktmpdir('ebook-cover') do |tmp|
            png = File.join(tmp, 'cover.png')
            rasterize_svg_to_png(svg_path, png, w_px, h_px) && CoverCommands.write_ebook_cover!(png, jpg_path)
          end
        end

        # SVG → PDF（仕上がりサイズ）。rsvg-convert でページの寸法をぴったり合わせる。
        # rsvg-convert が無ければ ImageMagick で 350dpi に焼く。
        def convert_svg_to_pdf(input, output, w_mm, h_mm)
          if Common.external_command_available?('rsvg-convert')
            return Common.run_svg_converter!(
              ['rsvg-convert', '-f', 'pdf',
               '--page-width', "#{w_mm}mm", '--page-height', "#{h_mm}mm",
               '-w', "#{w_mm}mm", '-h', "#{h_mm}mm",
               '-o', output, input],
              input_path: input, output_path: output, purpose: 'カバー PDF 変換'
            )
          end

          convert_cmd = CoverCommands.imagemagick_convert_command
          unless convert_cmd
            Common.log_error('rsvg-convert も ImageMagick も見つかりません')
            return false
          end
          dpi = CoverCommands::DPI
          w_px = (w_mm / Units::MM_PER_INCH * dpi).round
          h_px = (h_mm / Units::MM_PER_INCH * dpi).round
          Common.run_svg_converter!(
            [*convert_cmd, '-density', dpi.to_s, input, '-resize', "#{w_px}x#{h_px}!", output],
            input_path: input, output_path: output, purpose: 'カバー PDF 変換 (ImageMagick)'
          )
        end

        # SVG → PDF（入稿用・塗り足しとトンボ付き）
        #
        # 内容は等倍（閲覧用と 1:1）でレンダし、塗り足しの帯はテンプレートの背景
        # （仕上がりの外まで描いた矩形と pad のグラデーション）を viewBox を広げて見せて埋める。
        # かつて SVG を仕上がり＋塗り足しへ拡大していたため内容が約 +2.86% 大きくなり、
        # 閲覧用と入稿用で絵柄がずれていた。
        # 1. viewBox を塗り足しぶん外へ広げ、rsvg-convert で大判のページへ等倍で置く
        # 2. トンボを重ね（CoverCommands.add_crop_marks!）、ICC があれば PDF/X-1a にする
        def convert_svg_to_pdf_with_crop_marks(input, output, trim_w_mm, trim_h_mm)
          bleed_mm = Build::NombreStamper.bleed_mm_from_config
          crop_offset_mm = CoverCommands::CROP_MARK_OFFSET_MM
          margin_mm = bleed_mm + crop_offset_mm

          unless Common.external_command_available?('rsvg-convert')
            Common.log_warn('rsvg-convert が見つかりません。トンボなしで生成します')
            convert_svg_to_pdf(input, output, trim_w_mm, trim_h_mm)
            return
          end

          expanded = expand_svg_viewbox_for_bleed(
            expand_css_custom_properties(File.read(input, encoding: 'utf-8')), bleed_mm, trim_w_mm, trim_h_mm
          )
          tmp = "#{input}.bleed.svg"
          File.write(tmp, expanded, encoding: 'utf-8')

          # 置く寸法は仕上がり＋塗り足し×2（トンボ代の帯は白のまま）
          success = Common.run_svg_converter!(
            ['rsvg-convert', '-f', 'pdf',
             '--page-width', "#{trim_w_mm + (2 * margin_mm)}mm",
             '--page-height', "#{trim_h_mm + (2 * margin_mm)}mm",
             '-w', "#{trim_w_mm + (2 * bleed_mm)}mm",
             '-h', "#{trim_h_mm + (2 * bleed_mm)}mm",
             '--left', "#{crop_offset_mm}mm",
             '--top', "#{crop_offset_mm}mm",
             '-o', output, tmp],
            input_path: input, output_path: output, purpose: 'カバー PDF（トンボ付き）変換'
          )
          FileUtils.rm_f(tmp)
          return unless success

          CoverCommands.add_crop_marks!(output, bleed_mm:, crop_offset_mm:)

          # rsvg-convert の出力は RGB。ICC が使えるなら Japan Color 2001 Coated で CMYK の PDF/X-1a にする
          # （ICC の無い環境では RGB のまま）。
          return unless Build::CmykConverter.available?

          Build::CmykConverter.to_pdfx!(output, bleed_mm:, crop_offset_mm:, title: File.basename(output, '.pdf'))
        end

        # viewBox を塗り足しぶん外へ広げ、広げた viewBox でクリップする。
        #
        # 内容の座標は変えず、viewBox の原点を塗り足しぶん負の方向へずらして全体を広げる。
        # これで閲覧用（仕上がりの viewBox）と入稿用が同じ倍率で描かれ、内容が 1:1 に一致する。
        # テンプレートは塗り足しを埋めたい要素（背景・上下の金のバーなど）を仕上がりの外まで
        # 描いておき、ここで広げた viewBox ちょうどのクリップを全体に掛ける。rsvg-convert は
        # 大判に置くとき viewBox の外を切らないので、これが無いとトンボ代の白い帯まではみ出す。
        # viewBox か <defs> の無い SVG はそのまま返す。
        def expand_svg_viewbox_for_bleed(svg, bleed_mm, trim_w_mm, trim_h_mm)
          return svg unless bleed_mm.positive?

          m = svg.match(/<svg\b[^>]*viewBox\s*=\s*"(-?[\d.]+)\s+(-?[\d.]+)\s+([\d.]+)\s+([\d.]+)"/m)
          return svg unless m

          min_x, min_y, vb_w, vb_h = m.captures.map(&:to_f)
          bx = (bleed_mm * vb_w / trim_w_mm).round(3)
          by = (bleed_mm * vb_h / trim_h_mm).round(3)
          new_x = (min_x - bx).round(3)
          new_y = (min_y - by).round(3)
          new_w = (vb_w + (2 * bx)).round(3)
          new_h = (vb_h + (2 * by)).round(3)

          # --- Phase: ルートの <svg> の viewBox / width / height を広げる ---
          svg = svg.sub(/<svg\b[^>]*>/m) do |tag|
            tag = tag.sub(/viewBox\s*=\s*"[^"]*"/, %(viewBox="#{new_x} #{new_y} #{new_w} #{new_h}"))
            tag = tag.sub(/\bwidth\s*=\s*"[^"]*"/, %(width="#{new_w}"))
            tag.sub(/\bheight\s*=\s*"[^"]*"/, %(height="#{new_h}"))
          end

          # --- Phase: 広げた viewBox ちょうどのクリップを全体へ掛ける ---
          clip = %(<clipPath id="vs-print-bleed-clip">) +
                 %(<rect x="#{new_x}" y="#{new_y}" width="#{new_w}" height="#{new_h}"/></clipPath>)
          svg.sub(%r{</defs>(.*)</svg>}m) do
            %(#{clip}</defs><g clip-path="url(#vs-print-bleed-clip)">#{::Regexp.last_match(1)}</g></svg>)
          end
        end

        # SVG を指定の画素数の PNG へ焼く。
        #
        # rsvg-convert を優先する。ImageMagick に SVG を直接読ませると、環境によっては SVG の
        # 読み込みを inkscape に任せ、壊れた inkscape（中身の無い Homebrew のラッパーなど）を踏んで
        # 失敗するため。PDF と同じエンジンになり、表紙の PDF と JPEG の絵柄もそろう。
        def rasterize_svg_to_png(input, output_png, w_px, h_px)
          if Common.external_command_available?('rsvg-convert')
            return Common.run_svg_converter!(
              ['rsvg-convert', '-f', 'png', '-w', w_px.to_s, '-h', h_px.to_s, '-o', output_png, input],
              input_path: input, output_path: output_png, purpose: 'カバー画像 (SVG→PNG) 変換'
            )
          end

          # --- Phase: rsvg-convert が無いときは ImageMagick に任せる ---
          convert_cmd = CoverCommands.imagemagick_convert_command
          unless convert_cmd
            Common.log_error('ImageMagick（magick/convert）が見つかりません')
            return false
          end
          Common.run_svg_converter!(
            [*convert_cmd, '-density', '300', input, '-resize', "#{w_px}x#{h_px}!", output_png],
            input_path: input, output_path: output_png, purpose: 'カバー画像 (SVG→PNG) 変換'
          )
        end
      end
    end
  end
end
