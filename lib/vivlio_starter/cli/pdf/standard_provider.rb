# frozen_string_literal: true

require 'pdf/reader'
require 'prawn'
require 'vivlio_starter/cli/common'

module VivlioStarter
  module Pdf
    # MITライセンス互換の標準プロバイダ
    #
    # 隠しノンブルの合成は本体（Build::NombreStamper: Prawn + qpdf --overlay）へ移設したため、
    # プロバイダの責務は「ページ数取得・空白ページ生成・アウトライン付与」に縮小した。
    # 拡張プラグイン（vivlio-starter-pdf / HexaPDF）が担うのはアウトライン付与のみ。
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
    end
  end
end
