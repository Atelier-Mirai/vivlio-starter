# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/nombre_stamper.rb
# ================================================================
# 責務:
#   PDF 結合後の入稿用 PDF に隠しノンブル（通しページ番号）を書き込む。
#
# 隠しノンブルとは:
#   印刷所が製本工程で乱丁・落丁を検出するための通しページ番号。
#   読者には見えないノド側（綴じ側）の裁ち落とし領域内に配置する。
#
# 配置仕様:
#   - 位置: ノド側（綴じ側）の中央付近
#   - 方向: 90° 回転（右ページ: 時計回り、左ページ: 反時計回り）
#   - フォント: 同梱 HackGen35ConsoleNF（TTF・サブセット埋め込み）6pt
#     ※ 非埋め込みの標準 14 フォント（Helvetica）は入稿で事故になるため使わない（FT-02）
#   - 色: 黒
#
# 実装:
#   Prawn（MIT）で全ページ分のノンブル PDF を生成し、qpdf --overlay で 1:1 に重畳する。
#   かつては PDF プロバイダ（CombinePDF / HexaPDF）へ委譲していたが、
#   CombinePDF は保存時に named destinations（`/Dests`）を再構築しないため、
#   Standard モードではノンブル書き込みが入稿用 PDF のリンクを全損させていた。
#   構造保存型の qpdf overlay に置換することでこの潜在バグを解消し、
#   ノンブルはプロバイダ非依存の MIT 共通実装になった（プラグインは outline のみ担当）。
# ================================================================

require 'fileutils'
require 'pdf/reader'
require 'prawn'
require_relative '../units'
require_relative 'qpdf_overlay'
require_relative 'utilities'

module VivlioStarter
  module CLI
    module Build
      module NombreStamper
        module_function

        MM_TO_PT = Units::PT_PER_MM
        FONT_SIZE = 6

        # 隠しノンブルに使う埋め込み可能フォント（TTF）。
        # Prawn の標準 14 フォント 'Helvetica' は PDF に埋め込まれず、印刷所入稿で
        # 「非埋め込みフォント」事故になる（FT-02）。同梱の HackGen35ConsoleNF（TTF）を
        # 使えば Prawn が使用グリフ（数字のみ）をサブセット埋め込みするため極小で済む。
        NOMBRE_FONT_RELATIVE = File.join('stylesheets', 'fonts', 'hackgen35', 'HackGen35ConsoleNF-Regular.ttf')

        # 入稿用 PDF に隠しノンブルを書き込む
        # 結合済み PDF のすべてのページに通し番号（1〜N）を付与する。
        #
        # @param pdf_path [String] 対象 PDF のパス（成功時に上書きされる）
        # @param bleed_mm [Numeric] 塗り足し幅（mm）。ノンブルの X 座標に使う
        # @return [Boolean] 書き込み成功なら true
        def stamp!(pdf_path, bleed_mm: 3)
          # --- Phase: 検証 ---
          unless File.exist?(pdf_path)
            Common.log_warn("[NombreStamper] PDF が見つかりません: #{pdf_path}")
            return false
          end

          total_pages = Build::Utilities.page_count(pdf_path).to_i
          return false unless total_pages.positive?

          # --- Phase: ノンブル PDF の生成（Prawn） ---
          Common.log_action("[NombreStamper] 隠しノンブルを書き込みます（#{total_pages} ページ）…")
          nombre_pdf = "#{pdf_path}.nombre.pdf"
          create_nombre_pdf!(nombre_pdf, pdf_path, bleed_mm.to_f * MM_TO_PT)

          # --- Phase: 重畳（qpdf・構造保存・等倍） ---
          success = Build::QpdfOverlay.apply!(pdf_path, nombre_pdf)
          FileUtils.rm_f(nombre_pdf)

          if success
            Common.log_success("[NombreStamper] 隠しノンブル書き込み完了（#{total_pages} ページ）")
          else
            Common.log_error('[NombreStamper] 隠しノンブルの重畳（qpdf --overlay）に失敗しました')
          end
          success
        rescue StandardError => e
          Common.log_error("[NombreStamper] 隠しノンブル書き込みに失敗: #{e.message}")
          FileUtils.rm_f("#{pdf_path}.nombre.pdf")
          false
        end

        # 対象 PDF と同じページ数・同じページサイズで、ノンブルだけを描いた PDF を生成する。
        # ページサイズを 1 ページずつ元 PDF から読み取るのは、空白ページ挿入や
        # 前付・奥付の混在でページサイズが揃わない場合にも重畳位置をずらさないため。
        #
        # @param output_path [String] 出力先
        # @param source_pdf [String] ページ数・ページサイズの参照元
        # @param bleed_pt [Float] 塗り足し幅（pt）
        def create_nombre_pdf!(output_path, source_pdf, bleed_pt)
          reader = ::PDF::Reader.new(source_pdf)
          font = nombre_font

          Prawn::Document.generate(output_path, skip_page_creation: true, margin: 0) do |pdf|
            reader.pages.each_with_index do |page, idx|
              box = page.attributes[:MediaBox] || [0, 0, 595.28, 841.89]
              width  = box[2].to_f - box[0].to_f
              height = box[3].to_f - box[1].to_f

              pdf.start_new_page(size: [width, height], margin: 0)
              # フォントはページ作成後に設定する（skip_page_creation のため最初のページ前は不可）。
              # 数字のみのため TTF はサブセット埋め込みされ極小で済む。
              pdf.font(font, size: FONT_SIZE)
              pdf.fill_color('000000')

              draw_page_number(pdf, idx + 1, width, height, bleed_pt)
            end
          end
        end

        # 隠しノンブルのフォントを解決する。
        # プロジェクト（cwd）→ gem 同梱 の順に同梱 TTF を探し、いずれも無ければ
        # 'Helvetica'（非埋め込み）へフォールバックして従来どおりビルドは継続する。
        # @return [String] Prawn に渡すフォント（TTF パス or 'Helvetica'）
        def nombre_font
          gem_bundled = File.expand_path(File.join('../../../..', NOMBRE_FONT_RELATIVE), __dir__)
          [NOMBRE_FONT_RELATIVE, gem_bundled].find { File.exist?(it) } || 'Helvetica'
        end

        # 個別ページにノンブルを描画する
        # 奇数ページ（右ページ）はノド側 = 左端、偶数ページ（左ページ）はノド側 = 右端
        def draw_page_number(pdf, page_number, width, height, bleed_pt)
          x_offset = bleed_pt / 2.0
          y_center = height / 2.0
          text = page_number.to_s

          if page_number.odd?
            # 右ページ → ノド = 左端、時計回り 90°
            draw_rotated_text(pdf, text, x: x_offset, y: y_center, angle: 90)
          else
            # 左ページ → ノド = 右端、反時計回り -90°
            draw_rotated_text(pdf, text, x: width - x_offset, y: y_center, angle: -90)
          end
        end

        # テキストを回転して描画する（translate → rotate → draw_text）
        def draw_rotated_text(pdf, text, x:, y:, angle:)
          text_width  = pdf.width_of(text)
          text_height = pdf.font.height

          pdf.save_graphics_state do
            pdf.translate(x, y)
            pdf.rotate(angle) do
              pdf.draw_text(text, at: [-text_width / 2.0, -text_height / 2.0])
            end
          end
        end

        # 塗り足し幅を book.yml から取得する（mm 単位の数値を返す）
        # "3mm" → 3.0, "5mm" → 5.0, nil → 3.0
        #
        # @return [Float] 塗り足し幅（mm）
        def bleed_mm_from_config
          raw = Common::CONFIG.output.print_pdf.bleed
          parse_bleed_mm(raw)
        end

        # 塗り足し文字列を mm 数値に変換する
        # @param raw [String, Numeric, nil] 塗り足し幅の生値
        # @return [Float] mm 単位の数値（既定: 3.0）
        def parse_bleed_mm(raw)
          case raw
          in NilClass then 3.0
          in Numeric => n then n.to_f
          in String => s
            s.strip.downcase.sub(/mm\z/, '').to_f.then { it.positive? ? it : 3.0 }
          else 3.0
          end
        end
      end
    end
  end
end
