# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/css/nesting.rb
# ================================================================
# 責務:
#   CSS の入れ子（CSS Nesting Module Level 1）を開き、入れ子の無い規則の並びにする。
#
# なぜ要るか:
#   入れ子は正当な CSS で、公式テーマ（theme-base の basic.css）も著者の custom.css も使う。
#   ところが vs が CSS を読むのに使う crass は入れ子より前の仕様で作られていて、規則の中の
#   `& { … }` を読めない字句として扱う。Kindle（KFX）も入れ子の中の宣言を捨てる
#   （kindle-css-compatibility-notes.md §2）。そこで読み取りの段（Stylesheet）でここを通し、
#   以降の段（層を外す・Kindle 用に解く・勝ち負けの判定）には入れ子の無い規則だけを渡す。
#
# 開き方（仕様と、p_css の CSS.desugar と同じ）:
#   - 入れ子の選択子の `&` は親の選択子に置き換える。親が一つの複合選択子（`.a`・`h1.b`）なら
#     そのまま埋め込み、親が並び（`a, b`）なら `:is(…)` にまとめる。`:is()` は中の最も高い
#     詳細度を持つので、仕様の `&` と同じ詳細度になる。結合子を含む親（`.a .b`）は、`&` が
#     選択子の先頭にあるときだけ埋め込む。`.x &` を `.x .a .b` と埋め込むと、祖先の順が変わって
#     選ぶ要素が変わるので、そのときは `:is(.a .b)` にする。
#   - `&` を書かない入れ子の選択子（`.b`・`> .b`）は、前に `& ` を補ってから置き換える。
#   - 入れ子の @media・@supports などは、親の選択子の規則をその条件の中に置く形に開く。
#   - 入れ子の規則の後に書いた宣言は、書いた順を保って別の規則に分ける（仕様の
#     nested declarations rule。前の宣言と一つにまとめると、間の入れ子の規則との勝ち負けが変わる）。
#   字句（crass のトークン）の上で置き換えるので、文字列や属性の値の中の `&` は置き換えない。
# ================================================================

require 'crass'

module VivlioStarter
  module CLI
    module Css
      # CSS の入れ子を開く
      module Nesting
        # 中の規則も入れ子を開く条件つきの規則
        CONDITIONAL = /\A(?:media|supports|container|layer|scope|starting-style)\z/i

        # 親の選択子が複合選択子でなくなる字（子孫・子・兄弟の結合子）
        COMBINATOR = /[\s>+~]/

        module_function

        # crass の qualified rule（consume_rules の返す節）が入れ子を含むか
        def nested?(rule) = rule[:block].any? { block?(it) }

        # 条件つきの規則（@media など）の中に、入れ子を含む規則があるか
        def nested_inside?(at_rule)
          at_rule[:name].match?(CONDITIONAL) && at_rule[:block] &&
            rules_of(at_rule[:block]).any? { it[:node] == :qualified_rule && nested?(it) }
        end

        # 入れ子を含む規則を、入れ子の無い規則の CSS にする
        # @param rule [Hash] crass の qualified rule
        # @return [String]
        def expand(rule)
          out = []
          emit(selector_list(rule[:prelude]), rule[:block], [], out)
          out.join("\n")
        end

        # 条件つきの規則の中の規則を開き、同じ条件で包み直した CSS にする
        # @param at_rule [Hash] crass の at rule
        # @return [String]
        def expand_inside(at_rule)
          inner = rules_of(at_rule[:block]).map do |node|
            case node
            in { node: :qualified_rule } if nested?(node) then expand(node)
            in { node: :qualified_rule } then Crass::Parser.stringify([parser.create_style_rule(node)])
            else Crass::Parser.stringify([node])
            end
          end
          "@#{at_rule[:name]}#{Crass::Parser.stringify(at_rule[:prelude])}{#{inner.join("\n")}}"
        end

        # 字句の列を規則の列にする（qualified rule は中身を字句のまま持つ）
        def rules_of(input) = Crass::Parser.new(input).consume_rules

        # qualified rule を crass の style rule にするための入れ物（状態を持たない）
        def parser = Crass::Parser.new([])

        # 規則の中身を、宣言のまとまりと入れ子の規則に分けて、順に書き出す。
        # 宣言は入れ子の規則が現れるまでためておき、親の選択子の規則として書く
        # @param selectors [Array<String>] 親の選択子の並び（`&` を解いた後）
        # @param wrappers [Array<String>] 外側の条件（`@media screen` など）。内側ほど後ろ
        def emit(selectors, block, wrappers, out)
          pending = []
          flush = lambda do
            next if pending.empty?

            out << wrap(wrappers, "#{selectors.join(', ')} { #{pending.join('; ')}; }")
            pending.clear
          end

          segments(block).each do |segment|
            case segment
            in [:declaration, tokens] then pending << Crass::Parser.stringify(tokens).strip
            in [:rule, prelude, inner]
              flush.call
              head = prelude.drop_while { blank?(it) }
              if head.first&.dig(:node) == :at_keyword
                condition = Crass::Parser.stringify(head.drop(1)).strip
                emit(selectors, inner, [*wrappers, "@#{head.first[:value]} #{condition}".strip], out)
              else
                emit(resolve(prelude, selectors), inner, wrappers, out)
              end
            end
          end
          flush.call
        end

        # 規則の中身の字句を、[:declaration, 字句] と [:rule, 前置き, 中身] の並びにする。
        # 中身の無い宣言（空白・最後の `;` の後）は捨てる
        def segments(block)
          segments = []
          buffer = []
          block.each do |token|
            case token
            in { node: :semicolon }
              segments << [:declaration, buffer]
              buffer = []
            in { node: :simple_block, start: '{', value: }
              segments << [:rule, buffer, value]
              buffer = []
            else buffer << token
            end
          end
          segments << [:declaration, buffer]
          segments.reject { |kind, tokens, *| kind == :declaration && tokens.all? { blank?(it) } }
        end

        # 入れ子の選択子の並びの `&` を、親の選択子で置き換える。
        # 親が一つなら、複合選択子のときと、`&` が選択子の先頭に一つだけあるとき（`& .c`・`&.y`・
        # `&` を書かない子孫）は埋め込む。先頭の `&` は祖先の側の端なので、`.a .b` を埋め込んでも
        # 選ぶ要素が変わらない。Kindle は :is() を開くのに手間が要るので、埋め込める形は埋め込む
        def resolve(prelude, parents)
          inline = parents.first if parents.size == 1
          wrapped = ":is(#{parents.join(', ')})"
          split_list(prelude).map do |tokens|
            tokens = tokens.drop_while { blank?(it) }
            tokens = [{ node: :delim, value: '&' }, { node: :whitespace, raw: ' ' }, *tokens] if tokens.none? { ampersand?(it) }
            leading = ampersand?(tokens.first) && tokens.count { ampersand?(it) } == 1
            parent = inline && (leading || compound?(inline)) ? inline : wrapped
            tokens.map { ampersand?(it) ? parent : Crass::Parser.stringify([it]) }.join.strip
          end
        end

        # 選択子の並びを、上の段の `,` で分けた字句の列の並びにする（関数の中の `,` では分けない）
        def split_list(prelude)
          prelude.slice_when { |token, _| token[:node] == :comma }
                 .map { |tokens| tokens.reject { it[:node] == :comma } }
                 .reject { |tokens| tokens.all? { blank?(it) } }
        end

        def selector_list(prelude) = split_list(prelude).map { Crass::Parser.stringify(it).strip }

        # 括弧の外に結合子が無い選択子（`:is(.a .b)` は括弧の中なので複合選択子）
        def compound?(selector)
          depth = 0
          selector.each_char do |char|
            case char
            when '(', '[' then depth += 1
            when ')', ']' then depth -= 1
            else return false if depth.zero? && char.match?(COMBINATOR)
            end
          end
          true
        end

        def block?(token) = token[:node] == :simple_block && token[:start] == '{'
        def ampersand?(token) = token[:node] == :delim && token[:value] == '&'
        def blank?(token) = %i[whitespace comment].include?(token[:node])

        # 外側の条件で包む（内側の条件ほど内側に）
        def wrap(wrappers, text) = wrappers.reverse.reduce(text) { |inner, wrapper| "#{wrapper} { #{inner} }" }
      end
    end
  end
end
