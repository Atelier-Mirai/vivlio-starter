# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/shared/rewrite_table_align.rb
# ================================================================
# 責務:
#   表の align 属性を style へ移す
# ================================================================

require_relative '../context'

module VivlioStarter
  module CLI
    module Build
      # 表の align 属性を style へ移す
      module Transforms::Shared::RewriteTableAlign
        module_function

        # ================================================================
        # EPUB 用 テーブル align 属性の変換
        # ================================================================
        # VFM はテーブル列の整列（|:--| 等）を <th align="left"> という
        # 廃止済みプレゼンテーション属性で出力する。XHTML5 では align 属性は
        # 不許可で epubcheck の RSC-005 ERROR になるため、EPUB 経路でのみ
        # style="text-align:..." へ変換する。PDF（Vivliostyle）は align を
        # 許容するため PDF 経路は従来どおり（共有 HTML の書き換えは Step E =
        # PDF 完成後のため安全）。
        # ================================================================

        # style へ移す align の値
        CELL_ALIGN_VALUES = %w[left center right justify].freeze

        # th/td の align 属性を style の text-align へ変換する
        #
        # @param doc [Nokogiri::HTML5::Document] 1 ページの HTML（破壊的に書き換える）
        # @param ctx [Transforms::Context]
        def call(doc, ctx)
          cells = doc.css('th[align], td[align]').select { CELL_ALIGN_VALUES.include?(it['align']) }
          return if cells.empty?

          cells.each do |cell|
            # 既にある style の前に足す（後ろの宣言が勝つので、著者や前の段の指定を変えない）
            cell['style'] = cell.key?('style') ? "text-align:#{cell['align']};#{cell['style']}" : "text-align:#{cell['align']}"
            cell.remove_attribute('align')
          end
          Common.log_info("[EPUB] #{ctx.page_name} のテーブル align 属性を style へ変換しました")
        end
      end
    end
  end
end
