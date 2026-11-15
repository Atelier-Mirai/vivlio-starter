# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/css/inversion_check.rb
# ================================================================
# 責務:
#   層を外して層の順に並べると勝ち負けが変わりうる宣言の組を挙げる
#   （css-layer-restructure-spec.md §4.3 の (2)）。
#
# なぜ起きるか:
#   層ありでは上の層の規則が詳細度に関係なく勝つ。平らにすると、詳細度の高い下の層の
#   規則が勝つ。同じ詳細度どうしなら、層の順に並べたので結果は変わらない。
#
# 挙げる条件（§4.3）:
#   (a) 同じ値の入る場所（ロングハンド）を取り合い、値が違う
#   (b) 層ありと平らとで、勝つ側が入れ替わる
#   (c) 選ぶ対象が重なりうる。最後の複合選択子が同じクラスを含むか、どちらもクラスを
#       持たず要素名が両立する（Selector.may_overlap?）
#   (c) はクラスの違う組（`.a` と `.b` が同じ要素に付く場合）を見ない。見ると、著者の指定
#   （`.aki`・`.align-*`）と部品の組がほぼ全部挙がり、手で読める数にならないためである。
#
# 絞り込み:
#   ビルドのときは、組み上がった HTML に「両方の選択子に当たる要素」がある組だけを残す
#   （present）。疑似要素と動的な疑似クラスは外して調べる。
# ================================================================

require_relative 'cascade'
require_relative 'selector'

module VivlioStarter
  module CLI
    module Css
      # 層を外すと勝ち負けが変わる組の検査
      module InversionCheck
        # 組 1 つ。upper は層ありで勝つ宣言、lower は平らにすると勝つ宣言
        Pair = Data.define(:longhand, :upper, :lower)

        # page-break-* の古い値。break-* の値と同じ意味の組を、値の違う組として挙げない
        LEGACY_BREAK_VALUES = { 'always' => 'page' }.freeze

        module_function

        # @param pieces [Array<Flattener::Piece>] 層の順に並べた規則（出力先のフィルタを掛けた後）
        # @return [Array<Pair>] 宣言の組ごとに 1 つ
        def pairs(pieces)
          decls, = Cascade.collect(pieces)
          groups = Hash.new { |hash, key| hash[key] = [] }
          decls.each { |decl| decl.longhands.each { groups[it] << decl } }

          found = {}
          groups.each do |longhand, list|
            list.combination(2) do |left, right|
              pair = inverted(longhand, left, right)
              found[[pair.upper.key, pair.lower.key]] ||= pair if pair
            end
          end
          found.values
        end

        # 組み上がった文書で、両方の選択子に当たる要素がある組だけを残す。
        # Nokogiri が読めない選択子の組は、当たるものとして残す（見落とすより挙げる）。
        # @param documents [Array<Nokogiri::HTML5::Document>]
        def present(pairs, documents)
          cache = {}
          pairs.select do |pair|
            documents.any? do |doc|
              left, right = [pair.upper, pair.lower].map { matched(doc, it.selector, cache) }
              left.nil? || right.nil? || left.intersect?(right)
            end
          end
        end

        # 報告の 1 行
        def describe(pair)
          "#{pair.longhand}: #{decl_text(pair.upper)}（#{layer_name(pair.upper)}）が層ありで勝ち、" \
            "平らな CSS では #{decl_text(pair.lower)}（#{layer_name(pair.lower)}・詳細度が高い）が勝つ"
        end

        # 二つの宣言が (a)〜(c) を満たせば組にする
        def inverted(longhand, left, right)
          return nil if left.rank == right.rank && left.important == right.important
          return nil if meaning(left) == meaning(right)

          layered = Cascade.layered_precedence(left) <=> Cascade.layered_precedence(right)
          flat = Cascade.flat_precedence(left) <=> Cascade.flat_precedence(right)
          return nil if layered == flat
          return nil unless same_target?(left.subject, right.subject)

          upper, lower = layered.positive? ? [left, right] : [right, left]
          Pair.new(longhand:, upper:, lower:)
        end

        # 宣言の意味（同じ意味なら、どちらが勝っても結果は同じ）
        def meaning(decl)
          name = Cascade::ALIASES.fetch(decl.property, decl.property)
          value = decl.value.downcase
          value = LEGACY_BREAK_VALUES.fetch(value, value) if decl.property.start_with?('page-break-')
          [name, value]
        end

        def same_target?(left, right)
          return false unless Selector.may_overlap?(left, right)

          left.classes.intersect?(right.classes) || (left.classes.empty? && right.classes.empty?)
        end

        def matched(doc, selector, cache)
          cache.fetch([doc.object_id, selector]) do
            cache[[doc.object_id, selector]] = doc.css(Selector.nokogiri_selectors(selector).join(', ')).to_a
          end
        rescue Nokogiri::CSS::SyntaxError, Nokogiri::XML::XPath::SyntaxError
          cache[[doc.object_id, selector]] = nil
        end

        def decl_text(decl) = "#{decl.selector} { #{decl.property}: #{decl.value} }"

        def layer_name(decl)
          layer = EntryWriter::LAYERS[decl.rank] || '層の外'
          "#{File.basename(File.dirname(decl.source))}/#{File.basename(decl.source)}・#{layer}"
        end
      end
    end
  end
end
