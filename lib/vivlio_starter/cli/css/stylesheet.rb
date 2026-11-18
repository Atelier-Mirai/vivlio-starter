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
# CSS の入れ子（`&`）は、読むときに Nesting が開く。crass は入れ子より前の仕様で作られていて、
# 規則の中身を宣言として読むと入れ子を読めない字句にしてしまうので、規則の中身を字句のまま返す
# 口（consume_rules）で読み、入れ子のある規則だけを開いてから読み直す。以降の段に渡る規則には
# 入れ子が無い。
#
# `@charset` とコメントは捨てる。平らにした CSS は 1 枚に 1 つの `@charset` を
# 先頭に置けば足り、コメントは出力の大きさを増やすだけだからである。
# ================================================================

require 'crass'
require_relative 'nesting'

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
        # それ以外の規則。text は書かれたとおりの文字列（入れ子は開いた後のもの）
        Rule = Data.define(:text)

        module_function

        # @param css [String]
        # @return [Array<Import, LayerStatement, LayerBlock, Rule>]
        def parse(css) = items_of(Nesting.rules_of(css))

        # crass の節の列を項目の列にする。@layer の囲みは中をもう一度読む
        # （crass は囲みの中身を字句の列のまま返す）。入れ子のある規則は開いてから読み直す
        # （開いた結果に @layer の囲みが出ることがあるので、項目の列として読む）。
        def items_of(nodes)
          nodes.flat_map do |node|
            case node
            in { node: :at_rule, name: /\Acharset\z/i } then []
            in { node: :at_rule, name: /\Aimport\z/i, prelude: } then [import_of(prelude)].compact
            in { node: :at_rule, name: /\Alayer\z/i, prelude:, block: Array => block }
              [LayerBlock.new(name: layer_names(prelude).first, items: items_of(Nesting.rules_of(block)))]
            in { node: :at_rule, name: /\Alayer\z/i, prelude: } then [LayerStatement.new(names: layer_names(prelude))]
            in { node: :qualified_rule } if Nesting.nested?(node) then items_of(Nesting.rules_of(Nesting.expand(node)))
            in { node: :qualified_rule } then [rule(Nesting.parser.create_style_rule(node))]
            in { node: :at_rule } if Nesting.nested_inside?(node) then [Rule.new(text: Nesting.expand_inside(node).strip)]
            in { node: :at_rule } then [rule(node)]
            else [] # 空白・コメント・読めなかった字句
            end
          end
        end

        def rule(node) = Rule.new(text: Crass::Parser.stringify([node]).strip)

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
