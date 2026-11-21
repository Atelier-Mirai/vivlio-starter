# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/css/cascade.rb
# ================================================================
# 責務:
#   平らにした規則の列（Flattener::Piece）を宣言の列にし、宣言どうしの強さを
#   「層あり」と「層を外して並べたもの」の二通りで比べられるようにする。
#
# なぜ宣言をロングハンドに展開するか:
#   取り合いはプロパティの名前でなく、値の入る場所で起きる。`margin` と
#   `margin-block-start` は同じ場所（横書きでは margin-top）を取り合うので、
#   ロングハンドへ展開した名前で組にする。論理方向は、規則の列の組方向で物理方向へ読み替える。
#   横書き（horizontal-tb・ltr）が既定で、列に base/vertical.css（縦書きの本の、縦に組むページの
#   入口だけが読む）があれば縦書き（vertical-rl）として読む（novel-vertical-spec.md §10.5）。
#
# @page・@font-face などの選択子を持たない規則は宣言にしない（opaque として返す）。
# ================================================================

require 'crass'
require_relative 'entry_writer'
require_relative 'selector'

module VivlioStarter
  module CLI
    module Css
      # 宣言の列と、カスケードの強さ
      module Cascade
        # 宣言 1 つ。
        #   key      同じ宣言を別の版の列と突き合わせる鍵（@media の文脈・選択子・名前・値・出現の回数）
        #   rank     層の位置（EntryWriter::LAYERS の添字。層の外は UNLAYERED）
        #   order    平らにした列の中の位置 [規則の位置, 規則の中の宣言の位置]
        #   pos      規則の文字列（Piece#text）の中で、宣言の値が終わる位置。平らな CSS で宣言に
        #            !important を足す（AuthorPriority）ときの差し込み位置。選択子の並びを分けた宣言どうしは
        #            同じ位置を持つ
        Decl = Data.define(:key, :selector, :subject, :specificity, :longhands, :property, :value,
                           :important, :rank, :order, :source, :pos)

        # 層の外の位置（どの層よりも強い）
        UNLAYERED = EntryWriter::LAYERS.size

        SIDES = { 'top' => 'top', 'right' => 'right', 'bottom' => 'bottom', 'left' => 'left',
                  'block-start' => 'top', 'block-end' => 'bottom', 'inline-start' => 'left',
                  'inline-end' => 'right' }.freeze
        AXES = { 'block' => %w[top bottom], 'inline' => %w[left right] }.freeze
        # 縦書き（vertical-rl）: 行は上から下へ、行の並びは右から左へ進む
        VERTICAL_SIDES = SIDES.merge('block-start' => 'right', 'block-end' => 'left', 'inline-start' => 'top',
                                     'inline-end' => 'bottom').freeze
        VERTICAL_AXES = { 'block' => %w[right left], 'inline' => %w[top bottom] }.freeze
        ALL_SIDES = %w[top right bottom left].freeze
        BORDER_PARTS = %w[width style color].freeze
        SHORTHANDS = {
          'font' => %w[font-style font-variant font-weight font-size line-height font-family font-stretch],
          'background' => %w[background-color background-image background-position background-size
                             background-repeat background-attachment background-origin background-clip],
          'list-style' => %w[list-style-type list-style-position list-style-image],
          'text-decoration' => %w[text-decoration-line text-decoration-color text-decoration-style
                                  text-decoration-thickness],
          'gap' => %w[row-gap column-gap], 'grid-gap' => %w[row-gap column-gap],
          'flex' => %w[flex-grow flex-shrink flex-basis], 'flex-flow' => %w[flex-direction flex-wrap],
          'overflow' => %w[overflow-x overflow-y], 'columns' => %w[column-width column-count],
          'outline' => %w[outline-width outline-style outline-color]
        }.freeze
        # 同じものの別名（論理と物理・新旧の名前）
        ALIASES = {
          'inline-size' => 'width', 'block-size' => 'height', 'max-inline-size' => 'max-width',
          'max-block-size' => 'max-height', 'min-inline-size' => 'min-width', 'min-block-size' => 'min-height',
          'page-break-before' => 'break-before', 'page-break-after' => 'break-after',
          'page-break-inside' => 'break-inside', 'word-wrap' => 'overflow-wrap',
          'text-wrap' => 'white-space', 'text-wrap-mode' => 'white-space', 'white-space-collapse' => 'white-space',
          '-webkit-appearance' => 'appearance'
        }.freeze
        VERTICAL_ALIASES = ALIASES.merge(
          'inline-size' => 'height', 'block-size' => 'width', 'max-inline-size' => 'max-height',
          'max-block-size' => 'max-width', 'min-inline-size' => 'min-height', 'min-block-size' => 'min-width'
        ).freeze

        # 縦書きのページの入口が読む組方向の CSS（Css::EntryWriter::VERTICAL）
        VERTICAL_SOURCE = "stylesheets/#{EntryWriter::VERTICAL}".freeze

        module_function

        # 規則の列を、宣言の列と、選択子を持たない規則の列にする。
        # @param pieces [Array<Flattener::Piece>] 層の順に並べた規則
        # @return [Array(Array<Decl>, Array<Array(Integer, String)>)] 宣言の列と [層の位置, 規則の文字列] の列
        def collect(pieces)
          decls = []
          opaque = []
          seen = Hash.new(0)
          vertical = vertical?(pieces)
          pieces.each_with_index do |piece, piece_index|
            walk(Crass.parse(piece.text), [], piece, piece_index, decls, opaque, seen, vertical)
          end
          [decls, opaque]
        end

        # 層ありのカスケードの強さ。!important は層の順が逆になり、層の外が最も弱い
        def layered_precedence(decl)
          if decl.important
            [1, decl.rank == UNLAYERED ? -1 : UNLAYERED - decl.rank, *decl.specificity, *decl.order]
          else
            [0, decl.rank, *decl.specificity, *decl.order]
          end
        end

        # 層を外して層の順に並べた CSS での強さ。層の位置は効かず、詳細度と並びの位置だけで決まる
        def flat_precedence(decl) = [decl.important ? 1 : 0, *decl.specificity, *decl.order]

        # 規則の列が縦書きのページのものか（組方向の CSS を読んでいるか）
        def vertical?(pieces) = pieces.any? { it.source.to_s.end_with?(VERTICAL_SOURCE) }

        def layer_rank(layer) = layer.empty? ? UNLAYERED : EntryWriter::LAYERS.index(layer.first) || UNLAYERED

        # プロパティの名前を、値の入る場所（ロングハンド）の名前の列にする
        # @param vertical [Boolean] 論理方向を縦書きの向きで読むか
        def longhands(property, vertical: false)
          name = property.downcase
          name = (vertical ? VERTICAL_ALIASES : ALIASES).fetch(name, name)
          sides = vertical ? VERTICAL_SIDES : SIDES
          axes = vertical ? VERTICAL_AXES : AXES
          case name
          when 'margin', 'padding', 'inset' then ALL_SIDES.map { side_name(name, it) }
          when /\A(margin|padding|inset)-(block|inline)\z/
            base = Regexp.last_match(1)
            axes.fetch(Regexp.last_match(2)).map { side_name(base, it) }
          when /\A(margin|padding|inset)-(.+)\z/
            [side_name(Regexp.last_match(1), sides.fetch(Regexp.last_match(2), Regexp.last_match(2)))]
          when 'top', 'right', 'bottom', 'left' then [name]
          when 'border' then ALL_SIDES.product(BORDER_PARTS).map { "border-#{it.join('-')}" }
          when /\Aborder-(block|inline)\z/
            axes.fetch(Regexp.last_match(1)).product(BORDER_PARTS).map { "border-#{it.join('-')}" }
          when /\Aborder-(width|style|color)\z/
            part = Regexp.last_match(1)
            ALL_SIDES.map { "border-#{it}-#{part}" }
          when /\Aborder-(block|inline)-(width|style|color)\z/
            part = Regexp.last_match(2)
            axes.fetch(Regexp.last_match(1)).map { "border-#{it}-#{part}" }
          when /\Aborder-([a-z-]+?)-(width|style|color)\z/
            ["border-#{sides.fetch(Regexp.last_match(1), Regexp.last_match(1))}-#{Regexp.last_match(2)}"]
          when /\Aborder-(top|right|bottom|left|block-start|block-end|inline-start|inline-end)\z/
            side = sides.fetch(Regexp.last_match(1))
            BORDER_PARTS.map { "border-#{side}-#{it}" }
          when /radius/ then ['border-radius']
          else SHORTHANDS.fetch(name, [name])
          end
        end

        def side_name(base, side) = base == 'inset' ? side : "#{base}-#{side}"

        # crass の節をたどる。@media・@supports の中は文脈を足して続ける
        def walk(nodes, context, piece, piece_index, decls, opaque, seen, vertical)
          nodes.each do |node|
            case node
            in { node: :style_rule, selector: { value: selector_list }, children: }
              properties = children.select { it[:node] == :property }
              Selector.split_top(selector_list, ',').each do |raw|
                selector = raw.gsub(/\s+/, ' ')
                properties.each_with_index do |prop, decl_index|
                  decls << decl_of(seen, context, selector, prop, piece, [piece_index, decl_index], vertical)
                end
              end
            in { node: :at_rule, name: /\A(media|supports)\z/i => name, prelude:, block: Array => block }
              inner = "@#{name.downcase} #{Crass::Parser.stringify(prelude).strip}"
              walk(Crass::Parser.parse_rules(block), [*context, inner], piece, piece_index, decls, opaque, seen, vertical)
            in { node: :at_rule }
              opaque << [layer_rank(piece.layer), Crass::Parser.stringify([node]).gsub(/\s+/, ' ').strip]
            else nil
            end
          end
        end

        # 鍵に !important を含めないのは、!important を外した宣言を別の版の列と同じ宣言として
        # 突き合わせ、外したことで勝ち負けが変わる組を数えるためである（S2-3）
        def decl_of(seen, context, selector, prop, piece, order, vertical)
          base = [context, selector, prop[:name].downcase, prop[:value].gsub(/\s+/, ' ')]
          Decl.new(key: [*base, seen[base] += 1], selector:, subject: Selector.subject_of(selector),
                   specificity: Selector.specificity(selector), longhands: longhands(prop[:name], vertical:),
                   property: prop[:name].downcase, value: base[3], important: prop[:important],
                   rank: layer_rank(piece.layer), order:, source: piece.source, pos: value_end(prop))
        end

        # 宣言の値の終わり（!important と後ろの空白を除く）。crass の字句の位置は、@media の中を
        # 読み直しても、元の文字列の中の位置のまま
        def value_end(prop)
          tokens = prop[:tokens].reject { it[:node] == :whitespace || it[:node] == :comment }
          tokens = tokens[0...-2] if prop[:important] && tokens.size >= 2
          tokens.empty? ? nil : token_end(tokens.last)
        end

        # 字句の終わりの位置。関数（calc(…)）と括弧の塊は位置を持たないので、中の最後の字句で求める
        def token_end(token) = token[:raw] ? token[:pos] + token[:raw].length : token_end(token[:tokens].last)
      end
    end
  end
end
