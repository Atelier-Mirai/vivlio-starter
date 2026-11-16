# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/kindle/mark_body.rb
# ================================================================
# 責務:
#   body に、Kindle の印 vs-kindle を付ける
# ================================================================

require_relative '../context'
require_relative '../dom'

module VivlioStarter
  module CLI
    module Build
      # body に、Kindle の印 vs-kindle を付ける
      module Transforms::Kindle::MarkBody
        module_function

        # この段が body に足すクラス（出力先の宣言の body_classes と同じ値）
        BODY_CLASS = 'vs-kindle'

        # 各 EPUB 章 HTML の <body> に vs-kindle クラスを付与する。
        # body.vs-kindle ガードの CSS（画像上限・コードテーブル体裁等）を効かせるための目印。
        # PDF 用 HTML には付かないため PDF では当該 CSS が不発で無害。
        #
        # @param doc [Nokogiri::HTML5::Document] 1 ページの HTML（破壊的に書き換える）
        # @param ctx [Transforms::Context]
        def call(doc, _ctx) = Transforms::Dom.mark_body!(doc, BODY_CLASS)
      end
    end
  end
end
