# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/targets/print_pdf.rb
# ================================================================
# 責務:
#   出力先の宣言: 入稿用 PDF
# ================================================================

require_relative '../output_target'

module VivlioStarter
  module CLI
    module Build
      # 入稿用 PDF。HTML と CSS は閲覧用 PDF と同じで、閲覧用 PDF から導出するか、組み直す
      # （PrintPdfBuilder）。本文の画像は、今は閲覧用 PDF と同じものをそのまま使う
      # （CMYK への変換は表紙だけで、本文は未実装。v2-architecture-spec.md §4.2）。
      OutputTarget.register(
        OutputTarget.new(
          id: :print_pdf,
          branch: :pdf,
          workspace: Common::BUILD_PDF_DIR,
          body_classes: [],
          transforms: [],
          css_form: :layered,
          finalizers: [],
          assets: OutputTarget::Assets.new(images: :as_is, svg: true),
          packager: :print_pdf
        )
      )
    end
  end
end
