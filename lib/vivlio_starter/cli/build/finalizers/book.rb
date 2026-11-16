# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/finalizers/book.rb
# ================================================================
# 責務:
#   本全体の段へ渡す「本」（ページの並びと平らな CSS の表）と、finalizers/ の名前空間
# ================================================================

module VivlioStarter
  module CLI
    module Build
      # 本の全部のページと CSS を見て書き直す段（v2-architecture-spec.md §4.1・§4.3）。
      # 変換（transforms）が全部のページに当たった後、梱包の前に走る。変換は 1 ページだけを見るのが
      # 決まりで、本全体を見る段はここへ分ける。どの出力先でどの順に走るかは、出力先の宣言の
      # finalizers: が決める。
      module Finalizers
        # @!attribute pages [Array<String>] 出力先のワークスペースの HTML のパス（本の順）
        # @!attribute sheets [Hash{String => Css::Bundle::Sheet}] 平らな CSS の表（link の href → 書いた CSS）
        Book = Data.define(:pages, :sheets)
      end
    end
  end
end
