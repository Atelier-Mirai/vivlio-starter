# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/kindle/align_code_cells.rb
# ================================================================
# 責務:
#   コードだけの表のセルに、ゼロ幅の字を足す
# ================================================================

require_relative '../context'

module VivlioStarter
  module CLI
    module Build
      # コードだけの表のセルに、ゼロ幅の字を足す
      module Transforms::Kindle::AlignCodeCells
        module_function

        # コードで始まるセルの頭へ添える字（Transforms::Kindle::AlignCodeCells）。ゼロ幅の空白。
        CELL_CODE_GLUE = "\u200B"

        # コードで始まるセルの頭へ、ゼロ幅の空白を添える。
        #
        # KFX は、等幅の字が `-` や `.` で始まるセルだけ、1 行目を左へずらす。`:recto` や
        # 地の文の `--plain`、段落や箇条書きの中ではずれない。padding・text-indent・white-space・
        # 折り返しの指定は効かず、前に字を置くと揃う（Previewer の画面で確かめた。2026-11-01）。
        # ずれる字を数え上げなくて済むよう、コードで始まるセルにはすべて添える。
        # 字が既にあれば先頭が code でなくなるので、2 回通しても増えない。
        #
        # @param doc [Nokogiri::HTML5::Document] 1 ページの HTML（破壊的に書き換える）
        # @param ctx [Transforms::Context]
        def call(doc, ctx)
          codes = doc.css('td').filter_map { it.children.reject(&:blank?).first }.select { it.name == 'code' }
          return if codes.empty?

          codes.each { it.add_previous_sibling(Nokogiri::XML::Text.new(CELL_CODE_GLUE, doc)) }
          Common.log_info("[EPUB] #{ctx.page_name} のコードで始まるセル #{codes.size} 件に字を添えました")
        end
      end
    end
  end
end
