# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/kindle/restore_h3_markers.rb
# ================================================================
# 責務:
#   h3 の印を、実体の字へ戻す
# ================================================================

require_relative '../context'
require_relative '../../../post_process/html_parser'

module VivlioStarter
  module CLI
    module Build
      # h3 の印を、実体の字へ戻す
      module Transforms::Kindle::RestoreH3Markers
        module_function

        # Kindle 専用: h3 の印を文字へ戻す。Techbook は印を WebP の背景で描くために
        # span を空にするが、Kindle には WebP も var() も届かず、印だけが消えて字下げが残る。
        # ::before に頼らず実体の文字を入れるのは、Techbook でない本は span に印が残っていて
        # 二重になるため（KFX が :empty を解するかに賭けない）。
        def call(html_files, _ctx)
          marker = Common::CONFIG.theme.markers.h3 || '♣'
          html_files.each do |path|
            doc = PostProcessCommands::HtmlParser.parse_html_document(File.read(path, encoding: 'utf-8'))
            empty = doc.css('span.subsection-marker').select { it.text.empty? }
            next if empty.empty?

            empty.each { it.content = marker }
            PostProcessCommands::HtmlParser.save_html_document(path, doc)
          end
          html_files
        end
      end
    end
  end
end
