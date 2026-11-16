# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/shared/localize_showcase_images.rb
# ================================================================
# 責務:
#   図解注釈・Mermaid の図の参照を、SVG から PNG へ差し替える
# ================================================================

require_relative '../context'
require_relative '../../../post_process/html_parser'

module VivlioStarter
  module CLI
    module Build
      # 図解注釈・Mermaid の図の参照を、SVG から PNG へ差し替える
      module Transforms::Shared::LocalizeShowcaseImages
        module_function

        # data-vs-raster を持つ <img>（図解注釈 showcase・mermaid 図）の参照を、SVG から
        # 対のラスターへ差し替える（explanatory-diagram-spec §7.9・mermaid-diagram-spec §4.4）。
        # showcase の合成 SVG は元画像を base64 data URI で内包し、mermaid SVG は図中テキストを
        # <text> で持つ——どちらも Kindle（KFX）で確実に運ぶにはラスター化が要る。前処理が
        # SVG とラスターを必ず対で焼き、参照先を data-vs-raster に明示しているため、ここは
        # 参照の書き換えだけで済む（拡張子は推測せず属性の値をそのまま使う）。同梱側は
        # localized_image? が showcase / mermaid の .svg を弾くので、未参照 SVG がパッケージへ
        # 紛れ込むこともない（クリーン EPUB も同じラスターを使い、両フレーバで見た目を揃える）。
        # ラスター実体が無い場合（通常起きない）は参照を変えず警告に留める。
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def call(html_files, _ctx)
          html_files.each do |path|
            doc = PostProcessCommands::HtmlParser.parse_html_document(File.read(path, encoding: 'utf-8'))
            images = doc.css('img[data-vs-raster]')
            next if images.empty?

            images.each { |img| localize_showcase_image!(img, path) }
            PostProcessCommands::HtmlParser.save_html_document(path, doc)
            Common.log_info("[EPUB] #{File.basename(path)} の図版 #{images.size} 件をラスター参照へ差し替えました")
          end
          html_files
        end

        # <img> 1 つを data-vs-raster の参照へ差し替え、EPUB に不要な同属性を取り除く。
        # 実体確認は消費者 dir ではなく生成元（html/images/showcase/）に対して行う——
        # 資産のローカライズ（localize_assets!）はこの書き換えより後に走るため、
        # この時点の消費者 dir にはまだ画像が置かれていない。
        def localize_showcase_image!(img, html_path)
          raster = img['data-vs-raster'].to_s
          img.remove_attribute('data-vs-raster')

          if raster.empty? || !File.exist?(File.join(Common::BUILD_HTML_DIR, raster))
            Common.log_warn(
              "[EPUB] 図解注釈のラスター画像が見つかりません: #{raster}",
              detail: "→ #{File.basename(html_path)} は SVG 参照のまま出力します（Kindle では表示されない可能性があります）"
            )
            return
          end

          img['src'] = raster
        end
      end
    end
  end
end
