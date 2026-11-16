# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/epub/images.rb
# ================================================================
# 責務:
#   WebP への変換・著者の SVG の派生・ラスター化
# ================================================================

require 'cgi'
require 'digest'
require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative '../derived_image'
require_relative '../derived_svg'
require_relative 'workspace'

module VivlioStarter
  module CLI
    module Build
      # WebP への変換・著者の SVG の派生・ラスター化
      module Epub::Images
        module_function

        # クリーン EPUB 用に、PNG / JPEG の `<img>` 参照を WebP へ変換して差し替える。
        #
        # **EPUB では WebP がもっとも小さい。** ZIP へ素材のまま入るうえ、同じ絵で
        # WebP 280KB / JPEG 441KB という開きがある（実測）。EPUB 3.3 では image/webp が
        # コアメディアタイプなので、変換して困る読者はいない。
        #
        # 効くのは**素材を PNG / JPEG で置いている本**だけである。素材が既に WebP なら
        # 対象が 1 件も無く、何も起きない（本書がこれに当たる）。Kindle は WebP 非対応
        # なので通さない——あちらは逆向きに JPEG / PNG へ落とす。
        # ================================================================
        # 著者の SVG 図版を、書体を抱かせた派生へ差し替える（両フレーバ）
        # ================================================================
        # `<img>` 参照の SVG は独立文書なので、本文の @font-face も CSS 変数も届かない
        # （`type3-font-embedding-notes.md` §4）。この事情は PDF だけの話ではなく、
        # **EPUB でも図の書体は解決されない**。しかも EPUB は本文書体を埋め込まない
        # （`embed_fonts?` は false・本文は読者の書体で組まれる）ので、図が拠れる書体は
        # 図自身が持つものしかない。
        #
        # そこで PDF と同じ `DerivedSvg` の派生をそのまま配る。ラスタライズして逃げる手は
        # 採らない——librsvg は data: URI の @font-face を読まず（実測: 埋め込み前後の PNG が
        # バイト一致）、macOS では fontconfig に登録した書体も見ないため、**焼いた機械の
        # OS 書体**が焼き付いて成果物が再現しなくなる。ベクタのまま運べば決定論で、
        # 高精細画面でも鮮明で、しかも軽い。
        #
        # Kindle だけは KFX が SVG を扱えないのでここで焼く。書体が OS のものになるのは
        # 見出し画像（`heading_image_src`）が既に受け入れている割り切りと同じで、
        # この経路で新たに悪くなるものはない。
        #
        # **ローカライズより後に呼ぶこと。** 差し替えた元 SVG をパッケージから落とすので、
        # コピーが済んでいないと空振りし、未参照の重複が残る（`Epub::Images.transcode_to_webp!`
        # と同じ理由）。
        # ================================================================
        def stage_author_svgs!(html_files, flavor:)
          cache = {}
          html_files.each { |path| stage_author_svg_in_file!(path, flavor, cache) }
          html_files
        end

        # 1 ファイル分の SVG 参照を派生へ差し替える。
        def stage_author_svg_in_file!(path, flavor, cache)
          html = File.read(path, encoding: 'utf-8')
          changed = false

          updated = html.gsub(/<img\b[^>]*>/i) do |tag|
            src = tag[/\ssrc="([^"]*)"/i, 1]
            svg_data_uri = flavor == :kindle && src&.start_with?(SVG_DATA_URI_PREFIX)
            next tag unless svg_data_uri || src&.match?(/\.svg\z/i)

            staged = cache.fetch(src) do
              cache[src] = svg_data_uri ? stage_svg_data_uri(src, File.dirname(path)) : stage_author_svg(src, File.dirname(path), flavor)
            end
            next tag unless staged

            changed = true
            tag.sub(/(\ssrc=")[^"]*(")/i, "\\1#{staged}\\2")
          end
          return unless changed

          File.write(path, updated, encoding: 'utf-8')
          # Kindle は文字を持たない図も焼くので、「書体入りの派生」では言い過ぎになる。
          kind = flavor == :kindle ? 'ラスタ' : '書体入りの派生'
          Common.log_info("[EPUB] #{File.basename(path)} の SVG 図版を#{kind}へ差し替えました")
        end

        # src の SVG を派生へ差し替え、staging の相対パスを返す。できなければ nil（src 据え置き）。
        # 変換元は cwd（ルート）の著者資産を読み、出力は base_dir（消費者 dir）配下の
        # images/_epub_assets/ に置く（著者 dir を汚さない・P4 §5.3）。
        def stage_author_svg(src_attr, base_dir, flavor)
          source = decode_html_entities(src_attr)
          unless File.exist?(source)
            candidate = File.join(Common::BUILD_HTML_DIR, source)
            source = candidate if File.exist?(candidate)
          end
          return nil unless File.exist?(source)

          embedded = DerivedSvg.prepare(source)
          # 文字を持たない図・既に書体を抱えた生成 SVG は派生を作らない。
          # クリーン EPUB は素材のまま運ぶ（ベクタの利点が残る）。
          #
          # **Kindle は派生が無くても原本を焼く。** Previewer 4 は同梱された SVG を
          # KVG へ変換しようとし、1 枚でも躓くと Enhanced Typesetting ごと無効にして
          # KPF ではなく Mobi を出す（`kindle-css-compatibility-notes.md` §5.5）。
          # 文字が無い図——ロゴや QR——も例外ではない。
          return nil if embedded.nil? && flavor != :kindle

          place_author_svg(embedded || source, src_attr, base_dir, flavor)
        rescue StandardError => e
          Common.log_warn("[EPUB] SVG 図版の差し替えに失敗（#{src_attr}）: #{e.message}")
          nil
        end

        # 本文に data: URI で埋め込んだ SVG。見つからない画像の代わりに置く代替画像
        # （ImagePathNormalizer#placeholder_image_path）がこの形になる。
        SVG_DATA_URI_PREFIX = 'data:image/svg+xml'

        # data: URI の SVG を Kindle 用に画像ファイルへ焼き、参照用の相対パスを返す（できなければ nil）。
        # Kindle Previewer は data: URI の SVG を「無効な datauri」（W14224）とし、内部エラーで変換を
        # 止めて KPF を出さない。焼く元の SVG はパッケージの外（一時ディレクトリ）に書く——
        # 同梱された SVG は 1 枚でも Enhanced Typesetting を落とすため（stage_author_svg と同じ事情）。
        def stage_svg_data_uri(src_attr, base_dir)
          header, data = decode_html_entities(src_attr).split(',', 2)
          svg = header.include?(';base64') ? data.to_s.unpack1('m') : CGI.unescape(data.to_s)
          dir = File.join(base_dir, Common.images_dir, Epub::Workspace::EPUB_ASSETS_REL_SUBDIR)
          FileUtils.mkdir_p(dir)

          Dir.mktmpdir('vs-svg-data-uri') do |tmp|
            source = File.join(tmp, 'image.svg')
            File.write(source, svg)
            rasterize_author_svg(source, dir, Digest::SHA256.hexdigest(src_attr)[0, 16])
          end
        rescue StandardError => e
          Common.log_warn("[EPUB] data: URI の SVG を画像にできませんでした: #{e.message}")
          nil
        end

        # 派生を消費者 dir へ置き、参照用の相対パスを返す。
        def place_author_svg(embedded, src_attr, base_dir, flavor)
          ext = flavor == :kindle ? 'raster' : 'svg'
          key = Digest::SHA256.hexdigest(
            [File.expand_path(embedded), File.mtime(embedded).to_i, ext].join('|')
          )[0, 16]
          dir = File.join(base_dir, Common.images_dir, Epub::Workspace::EPUB_ASSETS_REL_SUBDIR)
          FileUtils.mkdir_p(dir)

          rel = flavor == :kindle ? rasterize_author_svg(embedded, dir, key) : copy_author_svg(embedded, dir, key)
          return nil unless rel

          drop_packaged_original(base_dir, decode_html_entities(src_attr))
          rel
        end

        # クリーン EPUB: ベクタのまま置く。
        def copy_author_svg(embedded, dir, key)
          abs = File.join(dir, "#{key}.svg")
          FileUtils.cp(embedded, abs) unless File.exist?(abs)
          "#{Common.images_dir}/#{Epub::Workspace::EPUB_ASSETS_REL_SUBDIR}/#{key}.svg" if File.size?(abs)
        end

        # Kindle: PNG へ焼いてから、透過の有無で PNG / JPEG を選ぶ。
        #
        # 形式の選び分けは WebP 経路（`epub_image_extension_for`）と同じ規則にする——
        # Kindle 端末のダークモードは背景を黒にするが画像は反転しないため、透過を白へ
        # 潰すと図の矩形が地の上に浮く。透過が無ければ JPEG のほうが小さい。
        def rasterize_author_svg(embedded, dir, key)
          png = File.join(dir, "#{key}.tmp.png")
          return nil unless system('rsvg-convert', '-w', Epub::Workspace::KINDLE_IMAGE_MAX_EDGE.to_s, '-f', 'png',
                                   embedded, '-o', png, out: File::NULL, err: File::NULL) && File.size?(png)

          ext = image_has_alpha?(png) ? 'png' : 'jpg'
          abs = File.join(dir, "#{key}.#{ext}")
          converted = File.exist?(abs) || convert_image(png, abs, ext)
          "#{Common.images_dir}/#{Epub::Workspace::EPUB_ASSETS_REL_SUBDIR}/#{key}.#{ext}" if converted && File.size?(abs)
        ensure
          FileUtils.rm_f(png) if png
        end

        def transcode_to_webp!(html_files)
          cache = {}
          html_files.each { |path| transcode_to_webp_in_file!(path, cache) }
          html_files
        end

        # 1 ファイル分の PNG / JPEG 参照を WebP へ差し替える。
        def transcode_to_webp_in_file!(path, cache)
          html = File.read(path, encoding: 'utf-8')
          changed = false

          updated = html.gsub(/<img\b[^>]*>/i) do |tag|
            src = tag[/\ssrc="([^"]*)"/i, 1]
            next tag unless src&.match?(/\.(png|jpe?g)\z/i)

            staged = cache.fetch(src) { cache[src] = stage_webp_derivative(src, File.dirname(path)) }
            next tag unless staged

            changed = true
            tag.sub(/(\ssrc=")[^"]*(")/i, "\\1#{staged}\\2")
          end
          return unless changed

          File.write(path, updated, encoding: 'utf-8')
          Common.log_info("[EPUB] #{File.basename(path)} の PNG/JPEG を WebP へ差し替えました")
        end

        # src の PNG / JPEG を WebP へ変換し、staging の相対パスを返す。できなければ nil。
        # 置き場と鍵の作り方は Kindle 側（`stage_webp_replacement`）と揃える。
        def stage_webp_derivative(src_attr, base_dir)
          source = decode_html_entities(src_attr)
          unless File.exist?(source)
            candidate = File.join(Common::BUILD_HTML_DIR, source)
            source = candidate if File.exist?(candidate)
          end
          return nil unless File.exist?(source)

          key = Digest::SHA256.hexdigest(
            [File.expand_path(source), File.mtime(source).to_i, 'webp'].join('|')
          )[0, 16]
          dir = File.join(base_dir, Common.images_dir, Epub::Workspace::EPUB_ASSETS_REL_SUBDIR)
          abs = File.join(dir, "#{key}.webp")
          rel = "#{Common.images_dir}/#{Epub::Workspace::EPUB_ASSETS_REL_SUBDIR}/#{key}.webp"
          return rel if File.exist?(abs)

          FileUtils.mkdir_p(dir)
          return nil unless convert_to_webp(source, abs)

          drop_packaged_original(base_dir, decode_html_entities(src_attr))
          rel
        rescue StandardError => e
          Common.log_warn("[EPUB] WebP 変換に失敗（#{src_attr}）: #{e.message}")
          nil
        end

        # 差し替えた元ファイルを、パッケージから落とす（未参照のまま太らせない）。
        #
        # **`localized_image?` で png / jpg を丸ごと外す手は採らない。** Kindle が WebP を
        # 外すのは KFX が読めないからで、外さなければ壊れる。クリーン EPUB にとって
        # png / jpg の除去は最適化にすぎず、著者の CSS が `images/` の画像を参照していれば
        # 壊す側に回る。**実際に差し替えたものだけ**を落とせば、その危険がない。
        def drop_packaged_original(base_dir, relative_src)
          packaged = File.join(base_dir, relative_src)
          FileUtils.rm_f(packaged) if File.file?(packaged)
        end

        # PNG / JPEG → WebP。透過はそのまま保つ（EPUB は紙ではないので白へ落とさない）。
        # 画面幅に対して過剰な画素数はここでも落とす。
        def convert_to_webp(source, dest)
          edge = target_edge_for(source, Epub::Workspace::EPUB_IMAGE_MAX_EDGE)
          cmd = ['magick', source, '-resize', "#{edge}x#{edge}>", '-strip',
                 '-quality', '85', '-define', 'webp:method=4', dest]
          system(*cmd, out: File::NULL, err: File::NULL) && File.size?(dest)
        rescue StandardError
          false
        end

        # 画像がアルファチャンネルを持つか（magick identify %A）。判定不能時は false。
        def image_has_alpha?(path)
          out, status = Open3.capture2('magick', 'identify', '-format', '%A', path)
          status.success? && %w[true blend].include?(out.strip.downcase)
        rescue StandardError
          false
        end

        # 変換元 → 出力（JPEG は白フラット化、PNG は透過保持）。成否を返す。
        #
        # 縮小先は端末の画面幅そのものではなく、**紙面で占めていた割合を掛けた値**にする
        # （`DerivedImage.viewport_target`）。版面の半分に並べた見本は Kindle でも画面の
        # 半分を占めるので、画面幅いっぱいの画素数は要らない。PDF を組んでいなければ
        # 従来どおり画面幅が上限になる。
        #
        # 写真を横に並べる囲み（.pictures・.image-group）の画像は `full: true` で、割合を掛けない。
        # PDF では 3 枚並びで版面の 3 分の 1 弱だったが、Kindle では 1 行 2 枚で画面の半分を占める
        # （Transforms::Kindle::ComposePictures）。割合で縮めると長辺 322 px ほどになり、画面の半分に
        # 広げるには画素数が足りない。
        def convert_image(source, dest, ext, full: false)
          edge = full ? Epub::Workspace::KINDLE_IMAGE_MAX_EDGE : target_edge_for(source, Epub::Workspace::KINDLE_IMAGE_MAX_EDGE)
          resize = ['-resize', "#{edge}x#{edge}>"]
          cmd = if ext == 'png'
                  ['magick', source, *resize, '-strip', dest]
                else
                  ['magick', source, '-background', 'white', '-flatten',
                   *resize, '-strip', '-quality', '90', dest]
                end
          system(*cmd, out: File::NULL, err: File::NULL)
        rescue StandardError
          false
        end

        # 画面幅に対して要る長辺（px）。寸法が読めなければ画面幅をそのまま返す。
        def target_edge_for(source, viewport_px)
          width, height = Common.image_size(source)
          return viewport_px unless width&.positive?

          DerivedImage.viewport_target(width, height, viewport_px)
        end

        # HTML 実体参照をデコードしてディスク上のパスへ戻す（&apos; を含む src の解決・§5-4）。
        # &amp; は最後に展開し二重デコードを避ける。
        def decode_html_entities(str)
          str.gsub('&apos;', "'").gsub('&quot;', '"').gsub('&lt;', '<').gsub('&gt;', '>').gsub('&amp;', '&')
        end
      end
    end
  end
end
