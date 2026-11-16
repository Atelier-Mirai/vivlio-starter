# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/book_traits.rb
# ================================================================
# 責務:
#   本の軸の値（組方向・レイアウト）と、連動して決まる値（綴じの向き・奇数ページの側・
#   原稿の単位）を引く窓口（v2-architecture-spec.md §2.4）
#
# 綴じの向きと原稿の単位は book.yml のキーにしていない（もう一方を選ぶ著者を描けないため）。
# コードは page.writing_mode を直接読んで「縦なら右綴じ」と判断せず、ここの導出値を読む。
# 連動を解いてキーを足すことになっても、直すのはこのファイルだけで済む。
# ================================================================

module VivlioStarter
  module CLI
    # 軸の値と、連動して決まる値。Common.traits で引く
    BookTraits = Data.define(:writing_mode, :layout) do
      # book.yml に書ける値。知らない値は既定（先頭）として組み、
      # 誤りは Guards::TraitCombinationCheck が 🔴 で示す
      const_set(:WRITING_MODES, %i[horizontal vertical].freeze)
      const_set(:LAYOUTS, %i[reflowable fixed].freeze)

      # 設定から軸の値を作る。設定が無い（プロジェクトの外）ときは既定の横書き・リフロー
      #
      # @param config [Data, nil] Common::CONFIG
      # @return [BookTraits]
      def self.resolve(config = Common::CONFIG)
        page = member(config, :page)
        new(writing_mode: normalize(member(page, :writing_mode), self::WRITING_MODES),
            layout: normalize(member(page, :layout), self::LAYOUTS))
      end

      # 節やキーが無い設定（直接ビルドの途中・テストの最小の設定）でも既定で作れるよう、
      # あるときだけ読む
      def self.member(node, key) = node.respond_to?(key) ? node.public_send(key) : nil

      # @param raw [Object] book.yml に書かれた値
      # @param known [Array<Symbol>] 有効な値（先頭が既定）
      # @return [Symbol]
      def self.normalize(raw, known)
        name = raw.to_s.strip.downcase
        known.find { it.to_s == name } || known.first
      end

      def vertical?  = writing_mode == :vertical
      def fixed?     = layout == :fixed
      # ページの進む向き（横書き＝左綴じ・縦書き＝右綴じ）
      def binding    = vertical? ? :rtl : :ltr
      # 奇数ページの側
      def recto_side = vertical? ? :left : :right
      # 原稿の単位
      def unit       = fixed? ? :page : :chapter
    end
  end
end
