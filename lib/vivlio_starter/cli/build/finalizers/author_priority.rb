# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/finalizers/author_priority.rb
# ================================================================
# 責務:
#   custom.css の宣言を、平らな CSS でも PDF と同じに勝たせる（CSS と style 属性）
# ================================================================

require_relative 'book'
require_relative '../epub/stylesheets'
require_relative '../../css/bundle'

module VivlioStarter
  module CLI
    module Build
      # custom.css の宣言を、平らな CSS でも PDF と同じに勝たせる（CSS と style 属性）
      module Finalizers::AuthorPriority
        module_function

        # custom.css などの層の外の宣言のうち、平らな CSS で vs の規則に負けるものに !important を付ける
        # （css-layer-restructure-spec.md §7.1）。要素ごとの判定なので、HTML の書き換え（vs-kindle の印・
        # Kindle の style 属性など）が全部終わった後に呼ぶ
        #
        # @param book [Finalizers::Book]
        # @param ctx [Transforms::Context]
        # @return [Finalizers::Book] 付けた後の CSS に差し替えた book
        def call(book, ctx)
          linked = Epub::Stylesheets.linked_styles(book.pages)
          book.with(sheets: Css::Bundle.prioritize_author_css!(book.sheets, linked, target: ctx.flavor))
        end
      end
    end
  end
end
