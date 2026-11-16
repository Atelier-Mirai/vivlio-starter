# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/finalizers/inversion_report.rb
# ================================================================
# 責務:
#   層を外すと勝ち負けが変わる組の報告（--log=debug のときだけ）
# ================================================================

require_relative 'book'
require_relative '../epub/stylesheets'
require_relative '../../css/bundle'

module VivlioStarter
  module CLI
    module Build
      # 層を外すと勝ち負けが変わる組の報告（--log=debug のときだけ）
      module Finalizers::InversionReport
        module_function

        # 層を外すと勝ち負けが変わる組を --log=debug で一覧にする（css-layer-restructure-spec.md §4.3）。
        # HTML の書き換え（vs-kindle の印・合成画像・コードの行ブロックなど）が全部終わった後の DOM で
        # 判定する。平らにする段（Epub::Stylesheets.bundle_flat!）ではまだ印が付いておらず、Kindle の規則が
        # どの要素にも当たらない
        #
        # @param book [Finalizers::Book]
        # @param ctx [Transforms::Context]
        # @return [Finalizers::Book] そのままの book
        def call(book, ctx)
          return book unless Common.current_log_level >= Common::LEVELS['debug']

          linked = Epub::Stylesheets.linked_styles(book.pages)
          Css::Bundle.report_epub_inversions!(book.sheets, linked, target: ctx.flavor)
          book
        end
      end
    end
  end
end
