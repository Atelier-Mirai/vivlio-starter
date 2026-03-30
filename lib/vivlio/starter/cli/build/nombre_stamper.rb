# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/build/nombre_stamper.rb
# ================================================================
# 責務:
#   PDF 結合後の入稿用 PDF に隠しノンブル（通しページ番号）を書き込む。
#
# 隠しノンブルとは:
#   印刷所が製本工程で乱丁・落丁を検出するための通しページ番号。
#   読者には見えないノド側（綴じ側）の塗り足し領域内に配置する。
#
# 配置仕様:
#   - 位置: ノド側（綴じ側）の中央付近
#   - 方向: 90° 回転（右ページ: 時計回り、左ページ: 反時計回り）
#   - フォント: Helvetica 6pt
#   - 色: 黒
#   - 領域: 塗り足し領域内（仕上がり線の外側）
#
# 依存:
#   - Provider (Prawn + CombinePDF): PDF overlay によるテキスト描画（MIT互換）
# ================================================================

module Vivlio
  module Starter
    module CLI
      module Build
        module NombreStamper
          module_function

          MM_TO_PT = 72.0 / 25.4
          FONT_NAME = 'Helvetica'
          FONT_SIZE = 6

          # 入稿用 PDF に隠しノンブルを書き込む
          # 結合済み PDF のすべてのページに通し番号（1〜N）を付与する。
          #
          # @param pdf_path [String] 対象 PDF のパス
          # @param bleed_mm [Numeric] 塗り足し幅（mm）。ノンブルの X 座標に使う
          # @return [Boolean] 書き込み成功なら true
          def stamp!(pdf_path, bleed_mm: 3)
            bleed_pt = bleed_mm.to_f * MM_TO_PT

            # 新実装 (MIT版 Provider への委譲)
            require 'vivlio/starter/cli/pdf/provider'
            Vivlio::Starter::Pdf.provider.stamp_nombre!(pdf_path, bleed_pt:)

            # --- 旧実装（MIT化動作確認後に削除予定） ---
            # unless File.exist?(pdf_path)
            #   Common.log_warn("[NombreStamper] PDF が見つかりません: #{pdf_path}")
            #   return false
            # end
            #
            # doc = HexaPDF::Document.open(pdf_path)
            # total = doc.pages.count
            #
            # Common.log_action("[NombreStamper] 隠しノンブルを書き込みます（#{total} ページ）…")
            #
            # doc.pages.each_with_index do |page, idx|
            #   stamp_page!(page, idx + 1, bleed_pt:)
            # end
            #
            # doc.write(pdf_path, optimize: true)
            # Common.log_success("[NombreStamper] 隠しノンブル書き込み完了（#{total} ページ）")
            # true
          # rescue StandardError => e
          #   Common.log_error("[NombreStamper] 隠しノンブル書き込みに失敗: #{e.message}")
          #   false
          end

          # 個別ページにノンブルを描画する
          # 奇数ページ（右ページ）はノド側 = 左端、偶数ページ（左ページ）はノド側 = 右端
          #
          # @param page [HexaPDF::Type::Page] 対象ページ
          # @param page_number [Integer] 通しページ番号（1〜）
          # @param bleed_pt [Float] 塗り足し幅（pt）
          def stamp_page!(page, page_number, bleed_pt:)
            canvas = page.canvas(type: :overlay)
            box = page.box(:media)

            canvas.font(FONT_NAME, size: FONT_SIZE)
            canvas.fill_color(0) # 黒

            # ノド側の X 座標: 塗り足し領域の中央
            x_offset = bleed_pt / 2.0
            y_center = box.height / 2.0

            if page_number.odd?
              # 右ページ → ノド = 左端、時計回り 90°
              draw_rotated_text(canvas, page_number.to_s, x: x_offset, y: y_center, angle: 90)
            else
              # 左ページ → ノド = 右端、反時計回り -90°
              draw_rotated_text(canvas, page_number.to_s, x: box.width - x_offset, y: y_center, angle: -90)
            end
          end

          # テキストを回転して描画する
          # translate → rotate → text の順に変換を適用
          #
          # @param canvas [HexaPDF::Content::Canvas] 描画対象キャンバス
          # @param text [String] 描画テキスト
          # @param x [Float] X 座標（pt）
          # @param y [Float] Y 座標（pt）
          # @param angle [Numeric] 回転角度（度）
          def draw_rotated_text(canvas, text, x:, y:, angle:)
            canvas
              .save_graphics_state
              .translate(x, y)
              .rotate(angle)
              .text(text, at: [0, 0])
              .restore_graphics_state
          end

          # 塗り足し幅を book.yml から取得する（mm 単位の数値を返す）
          # "3mm" → 3.0, "5mm" → 5.0, nil → 3.0
          #
          # @return [Float] 塗り足し幅（mm）
          def bleed_mm_from_config
            raw = Common::CONFIG.dig(:output, :print_pdf, :bleed)
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
end
