# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/dom.rb
# ================================================================
# 責務:
#   変換の段が共用する、要素の属性の小さな操作
# ================================================================

require_relative 'context'

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

        # body にクラスを足す。
        def mark_body!(doc, css_class)
          body = doc.at_css('body')
          add_class(body, css_class) if body
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
