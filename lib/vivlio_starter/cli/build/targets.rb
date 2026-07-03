# frozen_string_literal: true

require_relative 'pdf_merger'

module VivlioStarter
  module CLI
    module Build
      # ================================================================
      # Build::Targets — output.targets の解決結果（ビルド中は不変）
      # ================================================================
      # book.yml の出力ターゲット設定を「ビルド開始時に 1 回だけ」解決した
      # 不変値オブジェクト。従来 pipeline.rb 内で 4 メソッド（pdf_target? 等）が
      # 都度 CONFIG を解析し、判定ロジックが重複していたのを一元化する。
      #
      # 解決規則（現挙動を忠実に維持）:
      #   - pdf / print_pdf は output.targets を見て、空ならレガシー
      #     output.pdf.targets へフォールバックする。両方空なら pdf を既定とする。
      #   - epub / kindle は output.targets のみを見る（フォールバック無し）。
      #     この非対称は現行実装のままで、変更する場合は別途明示する。
      # ================================================================
      Targets = Data.define(:pdf, :print_pdf, :epub, :kindle) do
        def self.resolve(config = Common::CONFIG)
          primary = PdfMerger.extract_targets(config.dig(:output, :targets))
          # pdf / print_pdf のみ output.pdf.targets フォールバックを見る。
          pdf_scoped = primary.empty? ? PdfMerger.extract_targets(config.dig(:output, :pdf, :targets)) : primary

          new(
            # pdf / print_pdf が両方空（フォールバック後も空）なら pdf を既定 true。
            pdf: pdf_scoped.empty? || pdf_scoped.include?('pdf'),
            print_pdf: pdf_scoped.include?('print_pdf'),
            # epub / kindle はフォールバック無し（output.targets のみ）。
            epub: primary.include?('epub'),
            kindle: primary.include?('kindle')
          )
        end

        # EPUB / Kindle のいずれかが対象か（EPUB ビルド経路を起動するか）。
        def epub_or_kindle? = epub || kindle

        # 閲覧用 PDF / 入稿用 PDF のいずれかが対象か（dedup・スナップショット判定）。
        def any_pdf? = pdf || print_pdf
      end
    end
  end
end
