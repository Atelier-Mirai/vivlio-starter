# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/rotate_table_images.rb
# ================================================================
# 責務:
#   回転テーブル（`.rotate-table`）が組まれた PDF ページを切り出して画像化する。
#   Kindle 向けの劣化経路で、成果物は Kindle 枝が `<img>` として差し込む。
#
# なぜ画像なのか:
#   `.rotate-table > table` は `position: absolute` ＋ `transform: rotate(-90deg)` で
#   回転しているが、**KFX はそのどちらも解さない**ため宣言ごと無視され、Kindle では
#   素の表に戻る（列が詰まって折り返し、横長の表は見切れる）。CSS では解決できないので、
#   数式・mermaid・章扉と同じく画像へ劣化させる。
#
# なぜ「生成済み PDF のページを切り出す」のか:
#   回転テーブルは PDF では専用ページに組まれる（`break-before/after: page`）。
#   そのページを画像化すれば **PDF と寸分違わぬ見た目**が手に入り、回転・センタリング・
#   scale の追い込みが PDF 側 1 箇所で完結する。表だけを別レンダリングする案は
#   Chromium の起動が表の数だけ増え、しかも PDF と 1 対 1 の見た目を保証しにくい。
#
# 切り出し元は **dedup 前の 1 回目のレンダ**とする。dedup が消すのは用語集・索引の
# バックリンクと本文の † マークで、回転テーブルの中身は 1 文字も変わらない。
# 変わるのはページ番号だけだが、「id → ページ番号」を引くのと「そのページを切り出す」のを
# **同じ PDF に対して**行う限りずれようがない。dedup 後を待つと Kindle 枝の開始が
# 150 秒遅れ、PDF 枝の陰に収まらなくなる。
#
# 仕様: kindle-rotate-table-image-spec.md
# ================================================================

require 'fileutils'
require 'tmpdir'
require_relative 'pdf_page_map_extractor'
require_relative '../units'

module VivlioStarter
  module CLI
    module Build
      # 回転テーブルのページ画像化（Kindle 専用の劣化経路）
      module RotateTableImages
        # 生成物の置き場（ワークスペース直下）。final clean がまとめて掃除する。
        OUT_DIR_NAME = 'rotate-tables'

        # 版面幅が何 px になるようにラスタライズするか。`HeadingImageComposer::RENDER_WIDTH`
        # と揃えてある（Kindle 端末幅 1072px を上回り、拡大しても粗が出ない）。
        CONTENT_WIDTH_PX = 1400

        # 余白の切り詰め。版面の中で表は centering ＋ scale されており、素のままでは
        # 周囲が大きく空く。Kindle は画像を画面幅へ伸ばすので、詰めるほど字が大きくなる。
        TRIM_FUZZ = '1%'
        BORDER_PX = 12

        module_function

        def output_dir = File.join(Common::BUILD_DIR, OUT_DIR_NAME)

        def image_path(anchor_id) = File.join(output_dir, "#{anchor_id}.png")

        def available?(anchor_id) = File.exist?(image_path(anchor_id))

        # =============================================================
        # 枝をまたぐラッチ
        # =============================================================
        # PDF 枝が画像を用意し終えるまで Kindle 枝を待たせる。
        #
        # 枝は並列に走るので、Kindle 枝は PDF がまだ組まれていない時刻に差し掛かる
        # （実測で 70 秒以上先行する）。待たずに進むと「PDF が無かった」と誤認して
        # 素の表へ縮退し、しかもそれが**静かに**起きる——出来上がった KPF を開くまで
        # 気付けない類の壊れ方なので、明示的に待たせる。
        #
        # arm! されていなければ待たない。PDF を作らないビルド（targets に pdf が無い）で
        # 永久に待つのを避けるため、**「待つ相手がいるか」は呼び出し側が宣言する**。

        # @param enabled [Boolean] PDF 枝が画像化を担うか
        def arm!(enabled)
          @gate = enabled ? Queue.new : nil
        end

        def armed? = !@gate.nil?

        # 待っている枝を解放する。PDF 枝が例外で落ちても必ず呼ぶこと（デッドロック防止）。
        def release! = @gate&.close

        def wait_until_ready!
          return unless @gate

          Common.log_info('[rotate-table] 本文 PDF の完成を待っています…')
          @gate.pop
        end

        # =============================================================
        # 抽出（PDF 枝）
        # =============================================================

        # html/ の全 HTML から回転テーブルの内部 ID を集める。
        # @return [Hash{String => String}] ID → その ID を含む HTML のパス
        def collect_anchor_ids(dir = Common::BUILD_HTML_DIR)
          prefix = PreProcessCommands::TableConverter::ROTATE_ID_PREFIX
          Dir.glob(File.join(dir, '*.html')).each_with_object({}) do |path, found|
            File.read(path, encoding: 'utf-8').scan(/\bid="(#{prefix}[^"]+)"/o).flatten.each do |id|
              found[id] ||= path
            end
          end
        end

        # 回転テーブルのページを切り出して画像化する。
        #
        # @param pdf_path [String] 切り出し元（dedup 前の 1 回目のレンダ）
        # @return [Integer] 生成できた画像の数
        def extract!(pdf_path)
          ids = collect_anchor_ids.keys.sort
          return 0 if ids.empty?

          unless File.exist?(pdf_path)
            warn_missing_pdf(ids)
            return 0
          end

          pages = PdfPageMapExtractor.new(pdf_path).pages_for(ids)
          warn_unresolved(ids - pages.keys) if pages.size < ids.size
          return 0 if pages.empty?

          rasterize_pages(pdf_path, pages)
        end

        # 必要なページだけを 1 本の小さな PDF へ抜いてからラスタライズする。
        # 100MB 級の本文 PDF を表の数だけ開き直すのは無駄が大きいため。
        def rasterize_pages(pdf_path, pages)
          FileUtils.mkdir_p(output_dir)
          geometry = crop_geometry
          return 0 unless geometry

          Dir.mktmpdir('vs-rotate') do |tmp|
            ordered = pages.values.uniq.sort
            subset = File.join(tmp, 'pages.pdf')
            return 0 unless extract_subset(pdf_path, ordered, subset)

            pages.count do |anchor_id, page|
              render_one(subset, ordered.index(page) + 1, anchor_id, geometry, tmp)
            end
          end
        end

        def extract_subset(pdf_path, pages, output)
          command = %(qpdf "#{pdf_path}" --pages "#{pdf_path}" #{pages.join(',')} -- "#{output}" > /dev/null 2>&1)
          return true if system(command) && File.exist?(output)

          Common.log_warn('[rotate-table] 回転テーブルのページを取り出せませんでした（qpdf）')
          false
        end

        # 1 ページを PNG 化し、版面の外（柱・ノンブル）を落として余白を詰める。
        def render_one(subset_pdf, index, anchor_id, geometry, tmp)
          raw = File.join(tmp, "#{anchor_id}-raw")
          rasterize = %(pdftoppm -png -r #{geometry[:dpi]} -f #{index} -l #{index} -singlefile ) +
                      %("#{subset_pdf}" "#{raw}" > /dev/null 2>&1)
          unless system(rasterize) && File.exist?("#{raw}.png")
            Common.log_warn("[rotate-table] ページの画像化に失敗しました: #{anchor_id}")
            return false
          end

          crop("#{raw}.png", image_path(anchor_id), geometry)
        end

        # 版面（柱・ノンブルの内側）だけを切り出し、余白を詰めて細い白縁を付ける。
        #
        # 左右は inner/outer の**狭いほう**で対称に切る。柱とノンブルは天地の余白に
        # 入るので、左右の切り幅は「版面を欠かない」ことだけ満たせばよく、
        # ページの表裏（recto/verso で inner と outer が入れ替わる）を判定しなくて済む。
        def crop(source, destination, geometry)
          command = %(magick "#{source}" ) +
                    %(-crop #{geometry[:width]}x#{geometry[:height]}+#{geometry[:left]}+#{geometry[:top]} +repage ) +
                    %(-fuzz #{TRIM_FUZZ} -trim +repage ) +
                    %(-bordercolor white -border #{BORDER_PX} "#{destination}" > /dev/null 2>&1)
          return true if system(command) && File.exist?(destination)

          Common.log_warn("[rotate-table] 画像の切り出しに失敗しました: #{File.basename(destination, '.png')}")
          false
        end

        # 版面の切り出し寸法（px）と、そのために必要な解像度。
        # @return [Hash, nil] book.yml から版面を決められないときは nil
        def crop_geometry
          page = Common.configured? ? Common::CONFIG.page.to_h : nil
          return nil unless page

          page_w, page_h = Common.resolve_page_size(page).map { Units.length_to_mm(it) }
          side = [mm(page[:margin_inner]), mm(page[:margin_outer])].min
          top = mm(page[:margin_top])
          bottom = mm(page[:margin_bottom])
          return nil unless page_w && page_h

          content_w = page_w - mm(page[:margin_inner]) - mm(page[:margin_outer])
          return nil unless content_w.positive?

          dpi = (CONTENT_WIDTH_PX / (content_w / Units::MM_PER_INCH)).round
          px = ->(value) { (value * dpi / Units::MM_PER_INCH).round }
          { dpi:, left: px.call(side), top: px.call(top),
            width: px.call(page_w - (side * 2)), height: px.call(page_h - top - bottom) }
        end

        def mm(value) = Units.length_to_mm(value) || 0.0

        # =============================================================
        # 縮退の案内（warning-messages-actionable の方針）
        # =============================================================

        def warn_missing_pdf(ids)
          Common.log_warn("回転テーブル #{ids.size} 件を Kindle 用に画像化できませんでした（本文 PDF がありません）",
                          detail: "対処: config/book.yml の output.targets に pdf を足すと画像化されます。\n" \
                                  '（例: targets: pdf, epub, kindle）そのままでも Kindle は素の表として読めますが、' \
                                  '回転せず横長の表は見切れます。')
        end

        def warn_unresolved(ids)
          Common.log_warn("回転テーブルのページ位置を特定できませんでした: #{ids.join(', ')}",
                          detail: '対処: vs build --clean で中間生成物を作り直してください。' \
                                  '解消しない場合は該当の :::{.rotate-table} ブロックをお知らせください。')
        end
      end
    end
  end
end
