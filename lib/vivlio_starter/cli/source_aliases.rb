# frozen_string_literal: true

# ================================================================
# Module: SourceAliases
# ================================================================
# 責務:
#   設定ファイルなしのビルド（vs build myawesome.md）の報告で、作業用の原稿の名前と行を、
#   著者が指定した原稿の名前と行へ読み替える。
#
# なぜ要るか:
#   直接ビルドは、原稿を一時ワークスペースへ NN-名前.md（10-myawesome.md）の形で置いて組み、
#   `#` が複数あれば章ごとのファイルに分ける。前処理の 🔴・🟡 はその作業用の名前と、章の中の
#   行で出るので、著者が打った myawesome.md のどこかが分からない。
#
# なぜ出力の出口（Common.emit）で読み替えるか:
#   「ファイル名:行」を組み立てる報告は 30 か所近くあり、書き方もまちまち（`名前:行 - `、
#   `名前: `、`[qr] 名前:行`）。一つずつ直すと漏れ、新しい報告を足すたびにまた漏れる。
#   作業用の名前は直接ビルドの間だけ現れる固有の名前なので、出口で置き換えれば足りる。
#   表が空（通常のビルド）なら何もしない。
# ================================================================

module VivlioStarter
  module CLI
    module SourceAliases
      # workspace … 作業用の原稿の名前（10-myawesome.md）
      # source    … 著者が指定した原稿の名前（myawesome.md）
      # offset    … 作業用の原稿の 1 行目が、元の原稿の何行目の次か（章に分けたときの 2 章目以降）
      Alias = Data.define(:workspace, :source, :offset)

      @aliases = [].freeze

      class << self
        # ブロックの間だけ読み替える。前処理は作業スレッドでも走るので、表はスレッドごとではなく
        # プロセスで 1 つ持つ（直接ビルドは同時に 1 つしか走らない・BuildLock）
        # @param aliases [Array<Alias>]
        def with(aliases)
          previous = @aliases
          @aliases = aliases.freeze
          yield
        ensure
          @aliases = previous
        end

        # 文字列の中の作業用の原稿の名前（contents/ が前に付くものも）を、元の原稿の名前へ置き換える。
        # 名前の後に `:行` があれば、行も元の原稿の行へずらす。作業用の画像の置き場（images/10-myawesome/）は
        # 外す——直接ビルドの画像は原稿と同じ場所からの相対パスで探すので、`画像の場所: foo.png` と示す。
        # @param text [String]
        # @return [String]
        def localize(text)
          return text if @aliases.empty? || !text.is_a?(String)

          @aliases.reduce(text) do |result, item|
            renamed = result.gsub(%r{(?<![\w.-])(?:contents/)?#{Regexp.escape(item.workspace)}(?::(\d+))?}) do
              line = ::Regexp.last_match(1)
              line ? "#{item.source}:#{line.to_i + item.offset}" : item.source
            end
            renamed.gsub(%r{(?<![\w.-])images/#{Regexp.escape(item.workspace.delete_suffix('.md'))}/}, '')
          end
        end
      end
    end
  end
end
