# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/kindle/align_code_cells.rb
# ================================================================
# 責務:
#   コードだけの表のセルに、ゼロ幅の字を足す
# ================================================================

require_relative '../context'
require_relative '../../../post_process/html_parser'

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
        # @param html_files [Array<String>] HTML ファイルパスの配列
        # @return [Array<String>] そのままの配列（パス変更なし）
        def call(html_files, _ctx)
          html_files.each do |path|
            doc = PostProcessCommands::HtmlParser.parse_html_document(File.read(path, encoding: 'utf-8'))
            codes = doc.css('td').filter_map { it.children.reject(&:blank?).first }.select { it.name == 'code' }
            next if codes.empty?

            codes.each { it.add_previous_sibling(Nokogiri::XML::Text.new(CELL_CODE_GLUE, doc)) }
            PostProcessCommands::HtmlParser.save_html_document(path, doc)
            Common.log_info("[EPUB] #{File.basename(path)} のコードで始まるセル #{codes.size} 件に字を添えました")
          end
          html_files
        end
      end
    end
  end
end
