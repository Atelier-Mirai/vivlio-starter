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
# 二つの判定（v2-flat-cascade-consultation.md §5.4）:
#   静的な判定（pairs）— HTML なしで、規則の組を挙げる。vs の CSS を書き換えたときの早めの警報で、
#     css_layer_test.rb が使う。条件は (a)〜(c):
#     (a) 同じ値の入る場所（ロングハンド）を取り合い、値が違う
#     (b) 層ありと平らとで、勝つ側が入れ替わる
#     (c) 選ぶ対象が重なりうる。最後の複合選択子が同じクラスを含むか、どちらもクラスを
#         持たず要素名が両立する（Selector.may_overlap?）
#     (c) はクラスの違う組（`.a` と `.b` が同じ要素に付く場合）を見ない。見ると、著者の指定
#     （`.aki`・`.align-*`）と部品の組がほぼ全部挙がり、手で読める数にならないためである。
#     そのため、実際に起きる組を見落とすことがある。保証は次の判定で行う。
#   要素ごとの判定（inversions）— 組み上がった HTML の要素ごとに、層ありで勝つ宣言と、平らな CSS で
#     勝つ宣言を求めて比べる。組で比べると、同じ要素に当たる第三の宣言（どちらの形でも勝つもの）を
#     見ないので、誤って挙げる（部扉の break-before。同 §5.2）。候補は (c) を外した広い組で絞る。
#     媒体（screen・print）ごとに比べ、疑似要素は同じ疑似要素の宣言どうしで比べる。
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

        # 媒体ごとに比べる。@media の中の宣言は、その媒体でだけ取り合う
        MEDIA = %w[screen print].freeze

        # 静的な判定。
        # @param pieces [Array<Flattener::Piece>] 層の順に並べた規則（出力先のフィルタを掛けた後）
        # @param wide [Boolean] true なら (c) のクラスの条件を外す（要素ごとの判定の候補）
        # @return [Array<Pair>] 宣言の組ごとに 1 つ
        def pairs(pieces, wide: false) = candidates(longhand_groups(Cascade.collect(pieces).first), wide:)

        # 要素ごとの判定。組み上がった文書の要素のうち、層ありで勝つ宣言と平らな CSS で勝つ宣言が
        # 違う（意味も違う）ものを、その二つの宣言の組で返す。
        # Nokogiri が読めない選択子の宣言は当たらないものとして扱い、その選択子の列を unreadable に返す。
        # @param documents [Array<Nokogiri::HTML5::Document>]
        # @return [Array(Array<Pair>, Array<String>)] 組（upper = 層ありで勝つ・lower = 平らで勝つ）と読めない選択子
        def inversions(pieces, documents)
          groups = longhand_groups(Cascade.collect(pieces).first)
          cache = {}
          found = {}
          candidates(groups, wide: true).each do |pair|
            rivals = groups[pair.longhand].select { it.subject.pseudo_element == pair.upper.subject.pseudo_element }
            documents.each do |doc|
              upper = matched(doc, pair.upper.selector, cache)
              lower = matched(doc, pair.lower.selector, cache)
              next unless upper && lower

              upper.each_key.select { lower.key?(it) }.each do |element|
                MEDIA.each do |media|
                  result = winners(pair.longhand, rivals, doc, element, media, cache)
                  found[[result.upper.key, result.lower.key]] ||= result if result
                end
              end
            end
          end
          unreadable = cache.select { |_, nodes| nodes.nil? }.keys.map(&:last).uniq
          [found.values, unreadable]
        end

        # 報告の 1 行
        def describe(pair)
          "#{pair.longhand}: #{decl_text(pair.upper)}（#{layer_name(pair.upper)}）が層ありで勝ち、" \
            "平らな CSS では #{decl_text(pair.lower)}（#{layer_name(pair.lower)}・詳細度が高い）が勝つ"
        end

        def longhand_groups(decls)
          groups = Hash.new { |hash, key| hash[key] = [] }
          decls.each { |decl| decl.longhands.each { groups[it] << decl } }
          groups
        end

        def candidates(groups, wide:)
          found = {}
          groups.each do |longhand, list|
            list.combination(2) do |left, right|
              pair = inverted(longhand, left, right, wide:)
              found[[pair.upper.key, pair.lower.key]] ||= pair if pair
            end
          end
          found.values
        end

        # 一つの要素・一つのロングハンド・一つの媒体で、層ありと平らの勝つ宣言を比べる
        def winners(longhand, rivals, doc, element, media, cache)
          live = rivals.select { in_media?(it, media) && matched(doc, it.selector, cache)&.key?(element) }
          return nil if live.size < 2

          upper = live.max_by { Cascade.layered_precedence(it) }
          lower = live.max_by { Cascade.flat_precedence(it) }
          return nil if upper.equal?(lower) || meaning(upper) == meaning(lower)

          Pair.new(longhand:, upper:, lower:)
        end

        # 宣言の文脈（Decl#key の先頭。@media・@supports の列）が、その媒体で効くか
        def in_media?(decl, media)
          decl.key.first.all? do |context|
            next true unless context.start_with?('@media')

            context.match?(/\b#{media}\b/) || !context.match?(/\b(?:screen|print)\b/)
          end
        end

        # 二つの宣言が (a)〜(c) を満たせば組にする（wide なら (c) のクラスの条件を外す）
        def inverted(longhand, left, right, wide: false)
          return nil if left.rank == right.rank && left.important == right.important
          return nil if meaning(left) == meaning(right)

          layered = Cascade.layered_precedence(left) <=> Cascade.layered_precedence(right)
          flat = Cascade.flat_precedence(left) <=> Cascade.flat_precedence(right)
          return nil if layered == flat
          return nil unless wide ? Selector.may_overlap?(left.subject, right.subject) : same_target?(left.subject, right.subject)

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

        # 選択子に当たる要素の集まり（要素 → true）。読めない選択子は nil
        def matched(doc, selector, cache)
          cache.fetch([doc.object_id, selector]) do
            nodes = doc.css(Selector.nokogiri_selectors(selector).join(', '))
            cache[[doc.object_id, selector]] = nodes.to_h { [it, true] }
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
