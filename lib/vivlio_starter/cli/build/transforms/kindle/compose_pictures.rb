# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/kindle/compose_pictures.rb
# ================================================================
# 責務:
#   並べた画像を、1 行 1 枚の画像へ合成する
# ================================================================

require 'cgi'
require 'digest'
require 'fileutils'
require_relative '../../epub/images'
require_relative '../../epub/workspace'
require_relative '../context'

module VivlioStarter
  module CLI
    module Build
      # 並べた画像を、1 行 1 枚の画像へ合成する
      module Transforms::Kindle::ComposePictures
        module_function

        # 写真を横に並べる囲み（.pictures）の、Kindle での 1 行の枚数の上限。
        # PDF とクリーン EPUB は 1 枚を 12em 以上にして、画面の幅に合わせて折り返す（A4 の本文では
        # 3 枚）。KFX は画面の幅で組み方を変えられないので、スマートフォンでも小さくなりすぎない
        # 2 枚を上限にする（3 枚なら 2 枚と 1 枚の 2 行。2026-11-07 ユーザー判断）
        KINDLE_PICTURES_MAX_COLUMNS = 2

        # 合成する 1 行の画像の幅（px）と、写真の間（幅に対する割合）。
        # どの行も同じ幅のキャンバスに焼き、Kindle では本文の幅いっぱいに表示する
        KINDLE_PICTURES_ROW_WIDTH = Epub::Workspace::KINDLE_IMAGE_MAX_EDGE
        KINDLE_PICTURES_GAP_RATIO = 0.02

        # 写真を横に並べる囲み（.pictures・.image-group）を、Kindle では 1 行ずつ 1 枚の画像に
        # 合成して差し替える（:::{.showcase} の注釈と同じ考え方）。
        #
        # PDF は .pictures を flex、.image-group を grid で組むが、KFX はどちらも解さず、写真が
        # 1 枚ずつ本文の幅いっぱいに並んでいた。CSS で横に並べる手はどれも端末で崩れた
        # （Previewer で確かめた 2026-11-07・kindle-css-compatibility-notes.md）:
        # inline-block の箱に幅を付けると行の左の箱が約 1 字分狭くなり、img に幅を付けると
        # Phone で幅が守られず縦に並び、1 行の表は 1 ページに 1 枚になる。画像に焼けば、
        # どの端末でも PDF と同じ並びになる。
        #
        # 組み方は PDF に合わせる。.pictures は同じ幅で、行の高さはいちばん高い写真に合わせ、
        # ほかは中央で切り抜く（object-fit: cover）。1 枚だけの行も同じ幅で中央に置く。
        # .image-group は {width=40%} から作った比の幅で、上をそろえる（align-items: start）。
        #
        # @param doc [Nokogiri::HTML5::Document] 1 ページの HTML（破壊的に書き換える）
        # @param ctx [Transforms::Context]
        def call(doc, ctx)
          containers = doc.css('div.pictures, div.image-group')
          return if containers.empty?

          composed = containers.count { compose_picture_container!(it, ctx.page_dir) }
          return if composed.zero?

          Common.log_info("[EPUB] #{ctx.page_name} の写真の並び #{composed} か所を 1 行 1 枚の画像に合成しました")
        end

        # 囲み 1 つを、行ごとの合成画像に差し替える。合成できなければ何もせず false を返す
        # （写真は 1 枚ずつ縦に並ぶ。欠けるよりよい）。
        def compose_picture_container!(container, html_dir)
          images = container.css('figure img')
          return false if images.size < 2

          sources = images.map { resolve_picture_source(it['src'].to_s, html_dir) }
          return false if sources.any?(&:nil?)

          group = container['class'].to_s.split.include?('image-group')
          rows = sources.zip(images.map { it['alt'].to_s }).each_slice(group ? 2 : KINDLE_PICTURES_MAX_COLUMNS).to_a
          ratio = group ? image_group_ratio(container['style'].to_s) : nil
          figures = rows.map do |row|
            rel = compose_picture_row(row.map(&:first), html_dir, ratio:)
            return false unless rel

            alt = CGI.escapeHTML(row.map(&:last).reject(&:empty?).join('・'))
            %(<figure style="margin: 0 0 0.5em 0;"><img src="#{rel}" alt="#{alt}" style="width: 100%; height: auto; margin: 0;" /></figure>)
          end
          container.children.each(&:remove)
          container.add_child(container.document.fragment(figures.join))
          true
        end

        # 画像の実体のパス。変換済みの画像は HTML の隣、原稿の画像はルートからの相対で探す。
        def resolve_picture_source(src, html_dir)
          path = Epub::Images.decode_html_entities(src)
          [File.join(html_dir, path), path, File.join(Common::BUILD_HTML_DIR, path)].find { File.file?(it) }
        end

        # .image-group の 2 列の比（post_process が {width=40%} から書いた --image-group-col1/2）。
        def image_group_ratio(style)
          %w[col1 col2].map { style[/--image-group-#{it}:\s*([\d.]+)fr/, 1]&.to_f || 1.0 }
        end

        # 1 行を合成し、HTML から見た相対パスを返す。失敗したら nil。
        def compose_picture_row(sources, html_dir, ratio: nil)
          layout = picture_row_layout(sources, ratio:)
          return nil unless layout

          key = Digest::SHA256.hexdigest(
            (sources.map { [File.expand_path(it), File.mtime(it).to_i] } + [ratio, KINDLE_PICTURES_ROW_WIDTH]).inspect
          )[0, 16]
          rel = "#{Common.images_dir}/#{Epub::Workspace::EPUB_ASSETS_REL_SUBDIR}/pictures-#{key}.jpg"
          dest = File.join(html_dir, rel)
          return rel if File.exist?(dest)

          FileUtils.mkdir_p(File.dirname(dest))
          cmd = ['magick', '-size', "#{KINDLE_PICTURES_ROW_WIDTH}x#{layout[:height]}", 'xc:white']
          layout[:cells].each do |cell|
            fit = if ratio
                    ['-resize', "#{cell[:width]}x"]
                  else
                    ['-resize', "#{cell[:width]}x#{layout[:height]}^", '-gravity', 'center',
                     '-extent', "#{cell[:width]}x#{layout[:height]}", '+gravity']
                  end
            cmd += ['(', cell[:source], '-background', 'white', '-flatten', *fit, ')',
                    '-geometry', "+#{cell[:x]}+0", '-composite']
          end
          cmd += ['-strip', '-quality', '90', dest]
          system(*cmd, out: File::NULL, err: File::NULL) && File.exist?(dest) ? rel : nil
        end

        # 1 行の各写真の幅と左端（px）と、行の高さ。
        # .pictures（ratio なし）は同じ幅で、高さはいちばん高い写真に合わせる。枚数が上限に
        # 満たない行も同じ幅のまま中央に置く。.image-group は比の幅で、高さは高いほう。
        def picture_row_layout(sources, ratio: nil)
          sizes = sources.map { Common.image_size(it) }
          return nil if sizes.any?(&:nil?)

          gap = (KINDLE_PICTURES_ROW_WIDTH * KINDLE_PICTURES_GAP_RATIO).round
          columns = ratio ? 2 : KINDLE_PICTURES_MAX_COLUMNS
          available = KINDLE_PICTURES_ROW_WIDTH - (gap * (columns - 1))
          widths = if ratio
                     ratio.first(sources.size).map { (available * it / ratio.sum).floor }
                   else
                     Array.new(sources.size, available / columns)
                   end
          height = sizes.zip(widths).map { |(w, h), cell| (cell * h.to_f / w).round }.max
          used = widths.sum + (gap * (widths.size - 1))
          x = (KINDLE_PICTURES_ROW_WIDTH - used) / 2
          cells = sources.zip(widths).map do |source, width|
            cell = { source:, width:, x: }
            x += width + gap
            cell
          end
          { height:, cells: }
        end
      end
    end
  end
end
