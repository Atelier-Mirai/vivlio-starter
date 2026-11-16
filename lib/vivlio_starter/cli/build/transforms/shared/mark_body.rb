# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/transforms/shared/mark_body.rb
# ================================================================
# 責務:
#   body に、EPUB のリフローの文脈の印 vs-epub を付ける
# ================================================================

require_relative '../context'
require_relative '../dom'

module VivlioStarter
  module CLI
    module Build
      # body に、EPUB のリフローの文脈の印 vs-epub を付ける
      module Transforms::Shared::MarkBody
        module_function

        # この段が body に足すクラス（出力先の宣言の body_classes と同じ値）
        BODY_CLASS = 'vs-epub'

        # 各 EPUB 章 HTML の <body> に vs-epub クラスを付与する（クリーン・Kindle 両フレーバ共通）。
        # body.vs-epub は「EPUB リフロー文脈」の目印で、PDF を壊さず EPUB だけに効かせたい
        # 体裁調整（例: コードブロックの折返し・改ページ許容）の足場にする。劣化用途ではない
        # （Kindle 専用の劣化は別途 vs-kindle で行う）。PDF 用 HTML には付かないため PDF では無害。
        #
        # @param doc [Nokogiri::HTML5::Document] 1 ページの HTML（破壊的に書き換える）
        # @param ctx [Transforms::Context]
        def call(doc, _ctx) = Transforms::Dom.mark_body!(doc, BODY_CLASS)
      end
    end
  end
end
