# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/targets/pdf.rb
# ================================================================
# 責務:
#   出力先の宣言: 閲覧用 PDF
# ================================================================

require_relative '../output_target'

module VivlioStarter
  module CLI
    module Build
      # 閲覧用 PDF。HTML は共通のものをそのまま読み、CSS は層のあるまま渡す
      # （Type 3 対策の書き換えは、出力先の変換ではなく後処理の段にある）。
      OutputTarget.register(
        OutputTarget.new(
          id: :pdf,
          branch: :pdf,
          workspace: Common::BUILD_PDF_DIR,
          body_classes: [],
          transforms: [],
          css_form: :layered,
          finalizers: [],
          assets: OutputTarget::Assets.new(images: :as_is, svg: true),
          packager: :vivliostyle_pdf
        )
      )
    end
  end
end
