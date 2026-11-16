# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/dom.rb
# ================================================================
# 責務:
#   変換の段が共用する、要素の属性の小さな操作
# ================================================================

require_relative 'context'
require_relative '../../post_process/html_parser'

module VivlioStarter
  module CLI
    module Build
      # 変換の段が共用する、要素の属性の小さな操作
      module Transforms::Dom
        module_function

        # 要素へ CSS クラスを追加（重複は付けない）。
        def add_class(node, klass)
          classes = node['class'].to_s.split
          return if classes.include?(klass)

          node['class'] = (classes << klass).join(' ')
        end

        # 各 HTML の body にクラスを足す。
        def mark_body!(html_files, css_class)
          html_files.each do |path|
            html = File.read(path, encoding: 'utf-8')
            doc = PostProcessCommands::HtmlParser.parse_html_document(html)
            body = doc.at_css('body')
            next unless body

            add_class(body, css_class)
            PostProcessCommands::HtmlParser.save_html_document(path, doc)
          end
          html_files
        end

        # 既存 style を保ったまま CSS 宣言を追記する。
        def add_inline_style(node, css)
          existing = node['style'].to_s.strip
          existing += ';' unless existing.empty? || existing.end_with?(';')
          node['style'] = "#{existing}#{css}"
        end
      end
    end
  end
end
