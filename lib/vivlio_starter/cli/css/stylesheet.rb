# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/css/stylesheet.rb
# ================================================================
# 責務:
#   CSS を読み、層の付け方が分かる項目の列にする（crass を包む）。
#   css-layer-restructure-spec.md §4.1 の `stylesheet.rb`。
#
# 項目は 4 種類だけにする。層を解く処理（Flattener）が知りたいのは
# 「どのファイルを・どの層で読むか」と「どの規則が・どの層にあるか」だけで、
# 規則の中身（選択子や宣言）は書かれたとおりの文字列で足りる。
#   - Import         `@import url(...) layer(...)`
#   - LayerStatement `@layer a, b;`（層の順の宣言）
#   - LayerBlock     `@layer a { ... }`（中身も同じ 4 種類の列）
#   - Rule           それ以外の規則（style rule・@font-face・@page・@media など）
#
# `@charset` とコメントは捨てる。平らにした CSS は 1 枚に 1 つの `@charset` を
# 先頭に置けば足り、コメントは出力の大きさを増やすだけだからである。
# ================================================================

require 'crass'

module VivlioStarter
  module CLI
    module Css
      # CSS の読み取り
      module Stylesheet
        # @import。layer は層の名前（`theme.base` のような点の区切り）、層を付けないなら nil
        Import = Data.define(:href, :layer)
        # @layer a, b; — 層の順の宣言
        LayerStatement = Data.define(:names)
        # @layer a { ... } — items は中身の項目の列
        LayerBlock = Data.define(:name, :items)
        # それ以外の規則。text は書かれたとおりの文字列
        Rule = Data.define(:text)

        module_function

        # @param css [String]
        # @return [Array<Import, LayerStatement, LayerBlock, Rule>]
        def parse(css) = items_of(Crass.parse(css))

        # crass の節の列を項目の列にする。@layer の囲みは中をもう一度読む
        # （crass は囲みの中身を字句の列のまま返す）。
        def items_of(nodes)
          nodes.filter_map do |node|
            case node
            in { node: :at_rule, name: /\Acharset\z/i } then nil
            in { node: :at_rule, name: /\Aimport\z/i, prelude: } then import_of(prelude)
            in { node: :at_rule, name: /\Alayer\z/i, prelude:, block: Array => block }
              LayerBlock.new(name: layer_names(prelude).first, items: items_of(Crass::Parser.parse_rules(block)))
            in { node: :at_rule, name: /\Alayer\z/i, prelude: } then LayerStatement.new(names: layer_names(prelude))
            in { node: :at_rule | :style_rule } then Rule.new(text: Crass::Parser.stringify([node]).strip)
            else nil # 空白・コメント・読めなかった字句
            end
          end
        end

        # @import の前置き（url と layer()）を読む。
        # 名前の無い `layer`（無名の層）は vs の CSS では使わないので、層の外として扱う。
        def import_of(prelude)
          href = nil
          layer = nil
          prelude.each do |token|
            case token
            in { node: :url, value: } then href ||= value
            in { node: :string, value: } then href ||= value
            in { node: :function, name: /\Aurl\z/i, value: args }
              href ||= args.find { it[:node] == :string }&.dig(:value)
            in { node: :function, name: /\Alayer\z/i, value: args } then layer = Crass::Parser.stringify(args).strip
            else nil
            end
          end
          href && Import.new(href:, layer:)
        end

        # `a, b.c` を ["a", "b.c"] にする
        def layer_names(prelude)
          Crass::Parser.stringify(prelude).split(',').map(&:strip).reject(&:empty?)
        end
      end
    end
  end
end
