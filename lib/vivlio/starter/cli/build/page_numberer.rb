# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/build/page_numberer.rb
# ================================================================
# 責務:
#   PDF のページ番号を描画し、ページラベルを設定する。
#
# 処理内容:
#   - 前書き・目次ページにローマ数字（i, ii, iii...）を描画
#   - ページラベル辞書の設定（PDF リーダーで表示される番号）
#
# 描画オプション:
#   - フォント: typography.folio.font（デフォルト: Noto Sans JP）
#   - 配置: typography.folio.placement（center/sides）
#   - 色: グレー (#777777)
#
# 依存:
#   - HexaPDF: PDF 操作
#   - Common::CONFIG: フォント・配置設定
# ================================================================

require 'hexapdf'

module Vivlio
  module Starter
    module CLI
      module Build
        # ページ番号描画・ラベル設定モジュール
        module PageNumberer
          module_function

          # 指定PDFの全ページ下部にローマ小を描画（紙面上オーバーレイ）
          def overlay_roman_page_numbers!(pdf_path, options = {})
            return false unless File.exist?(pdf_path)

            cfg = Common::CONFIG || {}
            typo_cfg = cfg['typography'] || {}
            page_cfg = cfg['page'] || {}

            folio_font = typo_cfg.dig('folio', 'font') || 'Noto Sans JP'
            base_font_size_str = page_cfg['base_font_size'] || '12pt'
            base_font_size = base_font_size_str.to_s.gsub(/[^\d.]/, '').to_f
            folio_size = base_font_size * 0.75
            folio_color = [119.0 / 255.0, 119.0 / 255.0, 119.0 / 255.0]
            placement = typo_cfg.dig('folio', 'placement') || 'center'
            placement = 'center' unless %w[center sides].include?(placement)

            doc = HexaPDF::Document.open(pdf_path)
            total = doc.pages.count
            mm = 72.0 / 25.4

            font_path = File.join(Common::STYLESHEETS_DIR, 'fonts', 'Noto_Sans_JP', 'NotoSansJP-VariableFont_wght.ttf')
            font_name = if File.exist?(font_path)
                          doc.fonts.add(font_path)
                        else
                          Common.log_warn("フォントファイルが見つかりません: #{font_path}。Helveticaを使用します。")
                          'Helvetica'
                        end

            page_margin_bottom_str = page_cfg['margin_bottom'] || '30mm'
            page_margin_outer_str = page_cfg['margin_outer'] || '22mm'
            page_margin_inner_str = page_cfg['margin_inner'] || '28mm'
            margin_bottom_mm = page_margin_bottom_str.to_s.gsub(/[^\d.]/, '').to_f
            margin_outer_mm = page_margin_outer_str.to_s.gsub(/[^\d.]/, '').to_f
            margin_inner_mm = page_margin_inner_str.to_s.gsub(/[^\d.]/, '').to_f

            (0...total).each do |i|
              page = doc.pages[i]
              media_box = page.box(:media)
              width = media_box.width
              text = Common.to_roman_lower(i + 1)
              y = media_box.bottom + (margin_bottom_mm * mm * 0.45)

              canvas = page.canvas(type: :overlay)
              canvas.font(font_name, size: folio_size, variant: :none)
              canvas.fill_color(*folio_color)

              band_height = margin_bottom_mm * mm
              if band_height.positive?
                canvas.save_graphics_state do
                  canvas.fill_color(1.0, 1.0, 1.0)
                  canvas.rectangle(media_box.left, media_box.bottom, width, band_height)
                  canvas.fill
                end
                canvas.fill_color(*folio_color)
              end

              x = calculate_folio_x_position(placement, i, media_box, folio_size, text, margin_inner_mm, margin_outer_mm, mm)
              canvas.text(text, at: [x, y])
            end

            doc.write(pdf_path, optimize: true)
            Common.log_info("ノンブル描画: フォント=#{folio_font}, サイズ=#{folio_size.round(1)}pt, 配置=#{placement}")
            true
          rescue StandardError => e
            Common.log_warn("ローマ数字描画中にエラー: #{e.message}")
            false
          end

          # ノンブルのX座標計算
          def calculate_folio_x_position(placement, page_index, media_box, folio_size, text, margin_inner_mm, margin_outer_mm, mm)
            case placement
            when 'center'
              est_char_width = folio_size * 0.45
              text_width = text.length * est_char_width
              if (page_index + 1).odd?
                text_area_left = media_box.left + (margin_inner_mm * mm)
                text_area_right = media_box.right - (margin_outer_mm * mm)
              else
                text_area_left = media_box.left + (margin_outer_mm * mm)
                text_area_right = media_box.right - (margin_inner_mm * mm)
              end
              text_area_center = text_area_left + ((text_area_right - text_area_left) / 2.0)
              text_area_center - (text_width / 2.0)
            when 'sides'
              if (page_index + 1).odd?
                est_char_width = folio_size * 0.3
                text_width = text.length * est_char_width
                text_area_right = media_box.right - (margin_outer_mm * mm)
                text_area_right - text_width
              else
                media_box.left + (margin_outer_mm * mm)
              end
            end
          end

          # HexaPDF で PageLabels を設定
          def apply_page_labels_hexapdf(pdf_path, body_pages)
            return false unless File.exist?(pdf_path)

            doc = HexaPDF::Document.open(pdf_path)
            total = doc.pages.count
            bp = body_pages.to_i
            nums = if bp <= 0
                     [0, { S: :r, St: 1 }]
                   else
                     result = [0, { S: :D, St: 1 }]
                     result += [bp, { S: :r, St: 1 }] if bp < total
                     result
                   end
            doc.catalog[:PageLabels] = doc.add({ Type: :NumberTree, Nums: nums })
            doc.write(pdf_path, optimize: true)
            true
          end
        end
      end
    end
  end
end
