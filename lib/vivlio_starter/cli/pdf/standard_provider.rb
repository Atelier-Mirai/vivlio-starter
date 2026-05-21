# frozen_string_literal: true

require 'pdf/reader'
require 'prawn'
require 'combine_pdf'
require 'vivlio_starter/cli/common'

module VivlioStarter
  module Pdf
    # MITライセンス互換の標準プロバイダ
    class StandardProvider
      # PDF のページ数を取得する
      # @param pdf_path [String] 対象PDFファイルのパス
      # @return [Integer, nil] ページ数、取得失敗時は nil
      def page_count(pdf_path)
        return nil unless File.exist?(pdf_path)

        ::PDF::Reader.new(pdf_path).page_count
      rescue StandardError
        nil
      end

      # 空白ページのPDFを生成する
      # @param path [String] 出力先PDFファイルのパス
      # @param width_pt [Float] ページの幅 (pt)
      # @param height_pt [Float] ページの高さ (pt)
      # @return [String] 出力先PDFファイルのパス
      def ensure_blank_page_pdf(path, width_pt, height_pt)
        return path if File.exist?(path)

        Prawn::Document.generate(path, page_size: [width_pt, height_pt]) {}
        path
      end

      # 入稿用 PDF に隠しノンブルを書き込む
      # @param original_pdf_path [String] 対象のPDFファイルパス
      # @param bleed_pt [Float] 塗り足し幅 (pt)
      # @return [Boolean] 成功したか
      def stamp_nombre!(original_pdf_path, bleed_pt: 3.0 * (72.0 / 25.4))
        # --- Phase: Validation ---
        unless File.exist?(original_pdf_path)
          CLI::Common.log_warn("[NombreStamper] PDF が見つかりません: #{original_pdf_path}")
          return false
        end

        total_pages = page_count(original_pdf_path) || 0
        return false if total_pages.zero?

        # --- Phase: Preparation ---
        CLI::Common.log_action("[NombreStamper] 隠しノンブルを書き込みます（#{total_pages} ページ）[MIT Mode]…")
        nombre_pdf_path = "#{original_pdf_path}.nombre.pdf"

        # --- Phase: Generate & Merge ---
        create_nombre_pdf(nombre_pdf_path, original_pdf_path, bleed_pt)
        merge_nombre(original_pdf_path, nombre_pdf_path)

        # --- Phase: Cleanup ---
        FileUtils.rm_f(nombre_pdf_path)
        CLI::Common.log_success("[NombreStamper] 隠しノンブル書き込み完了（#{total_pages} ページ）")

        true
      rescue StandardError => e
        CLI::Common.log_error("[NombreStamper] 隠しノンブル書き込みに失敗: #{e.message}")
        false
      end

      # PDF アウトラインを付与する (Standard モードではスキップ)
      # @param original_pdf_path [String] 対象のPDFファイルパス
      # @param items [Array<Hash>] アウトラインの項目配列
      # @param max_level [Integer] 最大階層
      # @return [Boolean]
      def add_outline!(_original_pdf_path, _items, max_level:) # rubocop:disable Lint/UnusedMethodArgument
        CLI::Common.log_warn('PDF しおり（アウトライン）の付与は Standard モード(MIT) ではサポートされていません。')
        CLI::Common.log_info('  => 拡張機能が必要な場合は `gem install vivlio-starter-pdf` を検討してください。')
        false
      end

      private

      # Prawn でノンブルのみを描画した透明な PDF を生成する
      # @param output_path [String] 出力先PDFファイルパス
      # @param original_pdf_path [String] 元となるPDFファイルパス
      # @param bleed_pt [Float] 塗り足し幅 (pt)
      def create_nombre_pdf(output_path, original_pdf_path, bleed_pt)
        reader = ::PDF::Reader.new(original_pdf_path)

        Prawn::Document.generate(output_path, skip_page_creation: true, margin: 0) do |pdf|
          reader.pages.each_with_index do |page, idx|
            bbox = page.attributes[:MediaBox] || [0, 0, 595.28, 841.89]
            width = bbox[2] - bbox[0]
            height = bbox[3] - bbox[1]

            pdf.start_new_page(size: [width, height], margin: 0)
            pdf.font('Helvetica', size: 6)
            pdf.fill_color('000000')

            draw_page_number(pdf, idx + 1, width, height, bleed_pt)
          end
        end
      end

      # ノンブルを指定位置に回転して描画する
      # @param pdf [Prawn::Document] Prawnドキュメントインスタンス
      # @param page_number [Integer] ページ番号
      # @param width [Float] ページ幅
      # @param height [Float] ページ高さ
      # @param bleed_pt [Float] 塗り足し幅
      def draw_page_number(pdf, page_number, width, height, bleed_pt)
        x_offset = bleed_pt / 2.0
        y_center = height / 2.0
        text = page_number.to_s

        if page_number.odd?
          # 右ページ: ノド = 左端、時計回り 90°
          draw_rotated_text(pdf, text, x: x_offset, y: y_center, angle: 90)
        else
          # 左ページ: ノド = 右端、反時計回り -90°
          draw_rotated_text(pdf, text, x: width - x_offset, y: y_center, angle: -90)
        end
      end

      def draw_rotated_text(pdf, text, x:, y:, angle:)
        text_width = pdf.width_of(text)
        text_height = pdf.font.height

        pdf.save_graphics_state do
          pdf.translate(x, y)
          pdf.rotate(angle) do
            pdf.draw_text(text, at: [-text_width / 2.0, -text_height / 2.0])
          end
        end
      end

      # CombinePDF で元PDFとノンブルPDFを合成する
      # @param target_pdf [String] ベースとなるPDFのパス（上書きされる）
      # @param nombre_pdf [String] ノンブルが描画されたPDFのパス
      def merge_nombre(target_pdf, nombre_pdf)
        original = CombinePDF.load(target_pdf)
        nombre = CombinePDF.load(nombre_pdf)

        original.pages.each_with_index do |page, idx|
          page << nombre.pages[idx] if nombre.pages[idx]
        end

        original.save(target_pdf)
      end
    end
  end
end
