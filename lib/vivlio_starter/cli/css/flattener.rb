# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/css/flattener.rb
# ================================================================
# 責務:
#   入口の CSS の `@import` を解き、層の順に並べた 1 枚の CSS にする
#   （css-layer-restructure-spec.md §4.2 の 1・2）。
#
# なぜ要るか:
#   KFX は `@layer` の囲みを中身ごと捨てる（v2-feasibility-notes.md）。EPUB と Kindle には、
#   層を外し、層ありのときと同じ勝ち負けになる順に並べた CSS を渡す。
#
# 並べ方:
#   層ありの CSS では、後の層が前の層に勝ち、層の外の規則がどの層にも勝つ。同じ層の中は
#   後に書いた規則が勝つ。そこで「層の宣言の順に層を並べ、最後に層の外を置き、同じ層の中は
#   出現の順を保つ」と、同じ詳細度の規則どうしの勝ち負けは層ありと同じになる。
#   下位の層（`theme.base`）は親の層の中で宣言の順に並び、親の層に直に書いた規則は
#   下位の層より後に置く（下位の層に勝つ）。
#   詳細度が違う規則の取り合いは並べ方では保てない。その検査は §4.3（S3）で行う。
#
# url() の引き直し:
#   規則の中の相対の url() は、その規則を書いたファイルの位置から解いた絶対パスを
#   `rebase` に渡し、返った文字列に置き換える。出力の置き場（EPUB のパッケージの中など）は
#   呼び出し側だけが知っているので、引き直しの決まりは呼び出し側が渡す。
# ================================================================

require_relative '../common'
require_relative 'stylesheet'

module VivlioStarter
  module CLI
    module Css
      # 層を外した 1 枚の CSS を作る
      module Flattener
        # 平らにした規則 1 つ。layer は層の名前の列（層の外なら空の列）、source は書かれたファイル
        Piece = Data.define(:layer, :text, :source)

        # 層の外の規則と、層に直に書いた規則の並びの位置（どの下位の層よりも後）
        DIRECT = Float::INFINITY

        # 引き直さない url()。外部・data URI・絶対パス・ページ内の参照
        ABSOLUTE_URL = %r{\A(?:[a-z][a-z0-9+.-]*:|/|#)}i

        # url("…")・url('…')・url(…)
        URL_PATTERN = /url\(\s*(?:"([^"]*)"|'([^']*)'|([^\s'")]+))\s*\)/i

        module_function

        # 入口を平らにした CSS の全文。
        # @param entry_path [String] 入口の CSS
        # @param rebase [#call] 絶対パスを受け、出力の位置から見た url の文字列を返す
        # @return [String]
        def flatten(entry_path, rebase:)
          body = pieces(entry_path, rebase:).chunk_while { |a, b| a.source == b.source && a.layer == b.layer }
                                            .map { "#{source_comment(it.first)}\n#{it.map(&:text).join("\n")}" }
          ["@charset \"utf-8\";\n", *body].join("\n") << "\n"
        end

        # 入口から読んだ規則を、層の順に並べた列。
        # @return [Array<Piece>]
        def pieces(entry_path, rebase:)
          order = {}
          collected = []
          collect(File.expand_path(entry_path), [], order, collected, rebase, [])
          collected.each_with_index
                   .sort_by { |(piece, index)| [sort_key(piece.layer, order), index] }
                   .map(&:first)
        end

        # 1 ファイルを読み、規則を集める。@import は読み込んだ位置で中を集める
        # （同じ層の中で出現の順を保つため）。
        # @param context [Array<String>] いま読んでいる層の名前の列（層の外なら空）
        # @param order [Hash{Array<String> => Array<String>}] 親の層 → 子の層の宣言の順
        # @param visiting [Array<String>] 読んでいる途中のファイル（循環する @import を止める）
        def collect(path, context, order, collected, rebase, visiting)
          unless File.file?(path)
            Common.log_debug("[css] 読み込む CSS がありません: #{path}")
            return
          end
          return if visiting.include?(path)

          items = Stylesheet.parse(File.read(path, encoding: 'utf-8'))
          walk(items, path, context, order, collected, rebase, [*visiting, path])
        end

        # 項目の列をたどる。@layer の囲みは同じファイルのまま層を一段深くする
        def walk(items, path, context, order, collected, rebase, visiting)
          items.each do |item|
            case item
            in Stylesheet::LayerStatement[names:]
              names.each { declare(context + it.split('.'), order) }
            in Stylesheet::Import[href:, layer:]
              layered = layer ? context + layer.split('.') : context
              declare(layered, order) if layer
              collect(File.expand_path(href, File.dirname(path)), layered, order, collected, rebase, visiting)
            in Stylesheet::LayerBlock[name:, items: inner]
              layered = context + name.to_s.split('.')
              declare(layered, order)
              walk(inner, path, layered, order, collected, rebase, visiting)
            in Stylesheet::Rule[text:]
              collected << Piece.new(layer: context, text: rebase_urls(text, File.dirname(path), rebase), source: path)
            end
          end
        end

        # 層を宣言の順に登録する。`a.b` の登録は `a` の登録も兼ねる
        def declare(layer, order)
          layer.each_index do |depth|
            siblings = order[layer.take(depth)] ||= []
            siblings << layer[depth] unless siblings.include?(layer[depth])
          end
        end

        # 並びの鍵。各段の宣言の位置を並べ、最後に DIRECT を置く。
        # 配列の比較は前から順に行うので、下位の層（[i, j, DIRECT]）は親に直に書いた規則
        # （[i, DIRECT]）より前に、層の外（[DIRECT]）はどの層よりも後に並ぶ。
        def sort_key(layer, order)
          positions = layer.each_index.map { |depth| order.fetch(layer.take(depth)).index(layer[depth]) }
          [*positions, DIRECT]
        end

        # 規則の中の相対の url() を、書かれたファイルの位置から解いて引き直す
        def rebase_urls(text, base_dir, rebase)
          text.gsub(URL_PATTERN) do |match|
            url = Regexp.last_match(1) || Regexp.last_match(2) || Regexp.last_match(3)
            next match if url.empty? || url.match?(ABSOLUTE_URL)

            path, suffix = url.split(/(?=[?#])/, 2)
            %(url("#{rebase.call(File.expand_path(path, base_dir))}#{suffix}"))
          end
        end

        # 規則のまとまりの前に置く、出どころの注記（平らにした CSS を読む人のため）
        def source_comment(piece)
          layer = piece.layer.empty? ? '層の外' : "layer #{piece.layer.join('.')}"
          "/* #{relative_source(piece.source)} — #{layer} */"
        end

        def relative_source(path)
          root = "#{Dir.pwd}/"
          path.start_with?(root) ? path.delete_prefix(root) : File.basename(path)
        end
      end
    end
  end
end
