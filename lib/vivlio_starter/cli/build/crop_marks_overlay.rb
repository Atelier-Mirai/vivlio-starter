# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/crop_marks_overlay.rb
# ================================================================
# 責務:
#   トンボ（角トンボ・センタートンボ）だけを描いた 1 ページの PDF を Prawn で生成し、
#   入稿用 PDF の全ページへ qpdf --overlay で重畳する。
#
#   全ページでトンボの図形は同一なので、1 ページ生成して `--repeat` で使い回す。
#   幾何はカバー PDF（CreateCommands#add_crop_marks_overlay）で実績のあるものと共通。
# ================================================================

require 'fileutils'
require 'pdf/reader'
require 'prawn'

require_relative '../units'
require_relative 'qpdf_overlay'

module VivlioStarter
  module CLI
    module Build
      module CropMarksOverlay
        module_function

        LINE_WIDTH_PT = 0.24
        CIRCLE_RADIUS_MM = 2.5
        CROSS_ARM_LONG_MM = 10.0
        CROSS_ARM_SHORT_MM = 5.0
        CORNER_LENGTH_MM = 10.0

        # 入稿用ジオメトリへ変換済みの PDF 全ページへトンボを重畳する。
        #
        # 仕上がりサイズは 1 ページ目の MediaBox から逆算する（PrintGeometry 適用後は
        # MediaBox = [0, 0, trim + 2m, trim + 2m]）。book.yml の判型から計算し直すと
        # Chrome 出力の端数と食い違うおそれがあるため、実物のページを基準にする。
        #
        # @param pdf_path [String] 対象 PDF（成功時に上書きされる）
        # @param bleed_mm [Numeric] 塗り足し幅（mm）
        # @param crop_offset_mm [Numeric] トンボ代（mm）
        # @return [Boolean] 重畳に成功したか
        def apply!(pdf_path, bleed_mm:, crop_offset_mm:)
          margin_pt = (bleed_mm.to_f + crop_offset_mm.to_f) * Units::PT_PER_MM
          page_w_pt, page_h_pt = first_page_size(pdf_path)
          return false unless page_w_pt

          marks_pdf = "#{pdf_path}.crop_marks.pdf"
          generate!(marks_pdf,
                    trim_w_pt: page_w_pt - (2 * margin_pt), trim_h_pt: page_h_pt - (2 * margin_pt),
                    bleed_pt: bleed_mm.to_f * Units::PT_PER_MM,
                    crop_offset_pt: crop_offset_mm.to_f * Units::PT_PER_MM)

          success = Build::QpdfOverlay.apply!(pdf_path, marks_pdf, repeat: true)
          FileUtils.rm_f(marks_pdf)

          Common.log_warn('[print pdf] トンボの重畳（qpdf --overlay）に失敗しました') unless success
          success
        end

        # トンボのみを描いた 1 ページの PDF を生成する。
        # ページは「仕上がり ＋ (塗り足し ＋ トンボ代) × 2」の大判、トンボ線は
        # トンボ代の帯（塗り足しの外側）だけに描き、本文へ食い込ませない。
        #
        # @param path [String] 出力先
        # @param trim_w_pt [Float] 仕上がり幅（pt）
        # @param trim_h_pt [Float] 仕上がり高さ（pt）
        # @param bleed_pt [Float] 塗り足し幅（pt）
        # @param crop_offset_pt [Float] トンボ代（pt）
        def generate!(path, trim_w_pt:, trim_h_pt:, bleed_pt:, crop_offset_pt:)
          margin_pt = bleed_pt + crop_offset_pt
          page_w_pt = trim_w_pt + (2 * margin_pt)
          page_h_pt = trim_h_pt + (2 * margin_pt)
          mm2pt = Units::PT_PER_MM

          Prawn::Document.generate(path, page_size: [page_w_pt, page_h_pt], margin: 0) do |pdf|
            pdf.stroke_color '000000'
            pdf.line_width LINE_WIDTH_PT

            # --- Phase: 四隅の角トンボ（仕上がり線位置の二重 L 字） ---
            tx1 = margin_pt
            ty1 = margin_pt
            tx2 = margin_pt + trim_w_pt
            ty2 = margin_pt + trim_h_pt
            corner = CORNER_LENGTH_MM * mm2pt

            draw_corner_crop_mark(pdf, tx1, ty2, -1,  1, corner, bleed_pt)
            draw_corner_crop_mark(pdf, tx2, ty2,  1,  1, corner, bleed_pt)
            draw_corner_crop_mark(pdf, tx1, ty1, -1, -1, corner, bleed_pt)
            draw_corner_crop_mark(pdf, tx2, ty1,  1, -1, corner, bleed_pt)

            # --- Phase: 四辺のセンタートンボ（丸十字 ⊕・トンボ代の帯の中央） ---
            cx = page_w_pt / 2.0
            cy = page_h_pt / 2.0
            mid_crop = crop_offset_pt / 2.0
            radius = CIRCLE_RADIUS_MM * mm2pt
            arm_long = CROSS_ARM_LONG_MM * mm2pt
            arm_short = CROSS_ARM_SHORT_MM * mm2pt

            draw_center_crop_mark(pdf, cx, page_h_pt - mid_crop, arm_long, arm_short, radius)
            draw_center_crop_mark(pdf, cx, mid_crop, arm_long, arm_short, radius)
            draw_center_crop_mark(pdf, mid_crop, cy, arm_short, arm_long, radius)
            draw_center_crop_mark(pdf, page_w_pt - mid_crop, cy, arm_short, arm_long, radius)
          end
          path
        end

        # センタートンボ: ⊕（円＋十字線）
        def draw_center_crop_mark(pdf, cx, cy, half_h, half_v, radius)
          pdf.stroke_line [cx - half_h, cy], [cx + half_h, cy]
          pdf.stroke_line [cx, cy - half_v], [cx, cy + half_v]
          pdf.stroke_circle [cx, cy], radius
        end

        # 角トンボ: 二重 L 字交差型
        # (x, y) は仕上がり線の角。(dx, dy) は外向き符号。bl の分だけ内側を空ける。
        def draw_corner_crop_mark(pdf, x, y, dx, dy, s, bl)
          pdf.move_to(x + (bl * dx), y)
          pdf.line_to(x + ((s + bl) * dx), y)
          pdf.move_to(x, y + (bl * dy))
          pdf.line_to(x, y + ((s + bl) * dy))
          pdf.move_to(x, y + (bl * dy))
          pdf.line_to(x + (s * dx), y + (bl * dy))
          pdf.move_to(x + (bl * dx), y)
          pdf.line_to(x + (bl * dx), y + (s * dy))
          pdf.stroke
        end

        # 1 ページ目の MediaBox から実ページ寸法（pt）を得る
        # @return [Array(Float, Float), nil]
        def first_page_size(pdf_path)
          box = ::PDF::Reader.new(pdf_path).pages.first&.attributes&.fetch(:MediaBox, nil)
          return nil unless box

          [box[2].to_f - box[0].to_f, box[3].to_f - box[1].to_f]
        rescue StandardError => e
          Common.log_warn("[print pdf] ページ寸法の取得に失敗しました: #{e.message}")
          nil
        end
      end
    end
  end
end
