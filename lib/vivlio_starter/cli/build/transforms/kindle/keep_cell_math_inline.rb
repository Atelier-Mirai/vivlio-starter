# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/kindle/keep_cell_math_inline.rb
# ================================================================
# 責務:
#   数式だけの表のセルに、ゼロ幅の字を足す
# ================================================================

require_relative '../context'
require_relative '../../../post_process/html_parser'

module VivlioStarter
  module CLI
    module Build
      # 数式だけの表のセルに、ゼロ幅の字を足す
      module Transforms::Kindle::KeepCellMathInline
        module_function

        # 数式の画像だけのセルへ添える字（Transforms::Kindle::KeepCellMathInline）。ゼロ幅の空白。
        CELL_MATH_GLUE = "\u200B"

        # 数式の画像だけのセルへ、ゼロ幅の空白を添える。
        #
        # KFX はセルの中身が画像だけだと、画像を列の幅いっぱいまで引き伸ばすことがある。
        # 同じ表でも `$\frac14$ 倍` のように文字が並ぶセルは指定の大きさで描かれ、文字さえ
        # あれば起きない。ただし字の種類を選ぶ——NBSP は空白として捨てられて効かず、
        # ゼロ幅の空白は残る（Previewer の画面で確かめた。2026-10-30）。
        # 字が既にあれば text が空にならないので、2 回通しても増えない。
        #
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def call(html_files, _ctx)
          html_files.each do |path|
            doc = PostProcessCommands::HtmlParser.parse_html_document(File.read(path, encoding: 'utf-8'))
            cells = doc.css('td, th').select { it.at_css('img.vs-math-inline') && it.text.strip.empty? }
            next if cells.empty?

            cells.each { it.css('img.vs-math-inline').last.add_next_sibling(Nokogiri::XML::Text.new(CELL_MATH_GLUE, doc)) }
            PostProcessCommands::HtmlParser.save_html_document(path, doc)
            Common.log_info("[EPUB] #{File.basename(path)} の数式だけのセル #{cells.size} 件に字を添えました")
          end
          html_files
        end
      end
    end
  end
end
