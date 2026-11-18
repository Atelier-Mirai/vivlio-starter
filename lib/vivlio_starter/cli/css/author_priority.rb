# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/css/author_priority.rb
# ================================================================
# 責務:
#   層の外の宣言（custom.css・章の frontmatter が足した CSS）を、EPUB と Kindle の平らな CSS でも
#   PDF と同じに勝たせる（css-layer-restructure-spec.md §7.1・v2-flat-cascade-consultation.md §5.7）。
#
# なぜ要るか:
#   PDF（層あり）では、層の外の宣言は詳細度に関係なく vs とテーマのどの規則にも勝つ。層を外した
#   平らな CSS では詳細度で勝ち負けが決まるので、著者の `h2 { margin-block-start: 2em }` が vs の
#   `body.vs-header-simple h2` に負ける。著者は vs の選択子を知らないので、生成の段で直す。
#
# 方法:
#   組み上がった HTML の要素ごとに、当たる宣言から「層ありで勝つ宣言」と「平らな CSS で勝つ宣言」を
#   求める（InversionCheck の要素ごとの判定と同じ比べ方）。層ありで勝つのが層の外の宣言で、平らな
#   CSS では負けるとき、その宣言に平らな CSS の中でだけ !important を付ける。層の中に !important は
#   無い（§2.4）ので、付けた宣言は詳細度に関係なく層の中の宣言に勝つ。選択子は変えないので、当たる
#   要素は変わらない。付けるのは実際に負ける宣言だけである（custom.css が空なら何も変えない）。
#
#   付けた結果、層の外の宣言どうしの勝ち負けが変わる要素があれば（詳細度の高い別の宣言に勝って
#   しまう）、層ありで勝つ側にも付ける。全部の要素でそろうまで繰り返す。付ける宣言と付けられない
#   宣言は増える一方なので、必ず止まる。
#
# 付けない場合（Unresolved として返し、呼び出し側が 🟡 で知らせる）:
#   :important  付けると、!important の宣言（著者が自分で付けたもの・vs の h4 の印）に勝ってしまう
#
# style 属性（2026-11-15 ユーザー決定。v2-flat-cascade-consultation.md §5.7 の「解けない場合」の (2) を改めた）:
#   付ける宣言が、style 属性で同じプロパティを指定している要素にも当たるときは、その要素の style 属性の
#   同じプロパティにも !important を付ける（HTML を書き換える）。style 属性の !important は、どの
#   CSS の !important にも勝つので、「style 属性 > custom.css」という PDF の勝ち負けがそのまま保たれる。
#   付けずに知らせる形だと、Kindle 用に vs が組み替えた要素（写真の並びの表の style="width: 100%"）は
#   PDF にも原稿にも無いので、著者には直せない。
#
# 宣言を指す鍵（node）:
#   [CSS の鍵, 規則の位置, 値の終わりの位置]。選択子の並び（`h2, h3 { … }`）を分けた宣言は同じ
#   鍵になり、付けるときは並びごと付く。並びの別の選択子で起きる取り合いは、繰り返しの中で直す。
# ================================================================

require_relative 'cascade'
require_relative 'inversion_check'
require_relative 'selector'

module VivlioStarter
  module CLI
    module Css
      # 層の外の宣言を平らな CSS でも勝たせる
      module AuthorPriority
        # 組み上がった文書 1 つ。sheets は読む CSS の鍵の列（link の順）
        Document = Data.define(:doc, :path, :sheets)

        # !important を付けられなかった宣言。
        #   path・element  付けられない理由のある要素（style 属性の要素・!important と取り合う要素）
        #   rival          取り合う !important の宣言（reason が :important のとき）
        Unresolved = Data.define(:decl, :reason, :path, :element, :rival)

        # sheets は付けた後の規則の列（付けなかった CSS も含む）、promoted は CSS の鍵ごとの付けた数、
        # restyled は style 属性に !important を付けた文書（呼び出し側が保存する）
        Result = Data.define(:sheets, :promoted, :unresolved, :restyled)

        # 一つの要素・ロングハンド・媒体・疑似要素で取り合う宣言（[Decl, node] の列）
        Contest = Data.define(:rivals, :path, :element)

        IMPORTANT = ' !important'

        module_function

        # @param sheets [Hash{String => Array<Flattener::Piece>}] CSS の鍵 → 書き出す規則の列
        # @param documents [Array<Document>]
        # @return [Result]
        def apply(sheets, documents)
          unless sheets.each_value.any? { |pieces| pieces.any? { author_piece?(it) } }
            return Result.new(sheets:, promoted: {}, unresolved: [], restyled: [])
          end

          # --- Phase: 取り合いを集める（読む CSS の組ごと） ---
          contests = []
          clashes = {}
          documents.group_by(&:sheets).each do |keys, docs|
            collect_contests(sheets, keys, docs, contests, clashes)
          end

          # --- Phase: そろうまで付ける ---
          promoted = {}
          blocked = {}
          loop do
            changed = contests.map { settle(it, promoted, blocked) }.any?
            break unless changed
          end

          # --- Phase: 規則の文字列と、当たる要素の style 属性に !important を差し込む ---
          restyled = promoted.keys.flat_map { clashes.fetch(it, []) }.filter_map do |document, element, longhands|
            document if important_style!(element, longhands)
          end
          Result.new(sheets: promote(sheets, promoted.keys), promoted: promoted.keys.map(&:first).tally,
                     unresolved: blocked.values, restyled: restyled.uniq)
        end

        # 層の外の、宣言を持ちうる規則（書体の定義は宣言を取り合わない）
        def author_piece?(piece) = piece.layer.empty? && !piece.text.match?(/\A\s*@font-face/i)

        # 層の外の、!important の無い宣言（付ける候補）
        def author?(decl) = decl.rank == Cascade::UNLAYERED && !decl.important

        # 読む CSS の組 1 つについて、層の外の宣言が当たる要素の取り合いを集める。
        # style 属性で同じプロパティを指定している要素は、どちらの形でも style 属性が勝つので取り合いにせず、
        # 宣言に付けたときに style 属性にも付ける要素として clashes に記す
        def collect_contests(sheets, keys, docs, contests, clashes)
          node_of = {}.compare_by_identity
          pieces = keys.flat_map do |key|
            sheets.fetch(key).each_with_index.map { |piece, index| [piece, [key, index]] }
          end
          decls, = Cascade.collect(pieces.map(&:first))
          decls.each { node_of[it] = [*pieces[it.order.first].last, it.pos] }
          authors = decls.select { author?(it) }
          return if authors.empty?

          groups = InversionCheck.longhand_groups(decls)
          cache = {}
          seen = {}
          docs.each do |document|
            authors.each do |author|
              pseudo = author.subject.pseudo_element
              (InversionCheck.matched(document.doc, author.selector, cache) || {}).each_key do |element|
                fixed = pseudo ? [] : style_longhands(element)
                (clashes[node_of[author]] ||= []) << [document, element, author.longhands] if fixed.intersect?(author.longhands)
                author.longhands.each do |longhand|
                  next if fixed.include?(longhand)

                  InversionCheck::MEDIA.each do |media|
                    next unless InversionCheck.in_media?(author, media)
                    next if seen[[element, longhand, media, pseudo]]

                    seen[[element, longhand, media, pseudo]] = true
                    live = groups[longhand].select do |decl|
                      decl.subject.pseudo_element == pseudo && InversionCheck.in_media?(decl, media) &&
                        plausible?(decl.subject, element) &&
                        InversionCheck.matched(document.doc, decl.selector, cache)&.key?(element)
                    end
                    next if live.size < 2

                    contests << Contest.new(rivals: live.map { [it, node_of[it]] }, path: document.path, element:)
                  end
                end
              end
            end
          end
        end

        # 取り合い 1 つを見て、付ける・付けられないの状態を進める。進めたら true
        def settle(contest, promoted, blocked)
          upper, upper_node = contest.rivals.max_by { |decl, _| Cascade.layered_precedence(decl) }
          lower, lower_node = contest.rivals.max_by { |decl, node| flat_precedence(decl, node, promoted) }
          return false if upper.equal?(lower) || InversionCheck.meaning(upper) == InversionCheck.meaning(lower)

          if author?(upper)
            return false if promoted.key?(upper_node) || blocked.key?(upper_node)

            promoted[upper_node] = true
          elsif promoted.key?(lower_node)
            # 層ありで勝つのは !important の宣言。付けた宣言がそれに勝ってしまうので、付けるのをやめる
            promoted.delete(lower_node)
            blocked[lower_node] = Unresolved.new(decl: lower, reason: :important, path: contest.path,
                                                 element: contest.element, rival: upper)
            true
          else
            false
          end
        end

        # 付けた宣言を !important として数えた、平らな CSS での強さ
        def flat_precedence(decl, node, promoted)
          [decl.important || promoted.key?(node) ? 1 : 0, *decl.specificity, *decl.order]
        end

        # 選択子の対象が、その要素に当たりえないと分かるものを、Nokogiri に問う前に外す（速さのため）
        def plausible?(subject, element)
          name = element.name.downcase
          return false if subject.tags && !subject.tags.include?(name)
          return false if subject.excluded.include?(name)

          classes = element['class'].to_s.split
          subject.classes.all? { classes.include?(it) }
        end

        # 要素の style 属性が指定しているロングハンド
        def style_longhands(element)
          style = element['style'].to_s
          return [] if style.empty?

          style.scan(/(?:\A|;)\s*([-\w]+)\s*:/).flatten.flat_map { Cascade.longhands(it) }
        end

        # style 属性のうち、ロングハンドが重なる宣言に !important を付ける。付けたら true
        def important_style!(element, longhands)
          changed = false
          declarations = Selector.split_top(element['style'].to_s, ';').map do |declaration|
            name = declaration[/\A\s*([-\w]+)\s*:/, 1]
            next declaration if name.nil? || declaration.match?(/!\s*important\s*\z/i)
            next declaration unless Cascade.longhands(name).intersect?(longhands)

            changed = true
            "#{declaration}#{IMPORTANT}"
          end
          element['style'] = "#{declarations.join('; ')};" if changed
          changed
        end

        # 付ける宣言の値の終わりに !important を差し込んだ規則の列
        def promote(sheets, nodes)
          positions = nodes.group_by { |key, index, _| [key, index] }.transform_values { it.map(&:last) }
          sheets.to_h do |key, pieces|
            updated = pieces.each_with_index.map do |piece, index|
              ends = positions[[key, index]]
              next piece unless ends

              text = ends.uniq.sort.reverse.reduce(piece.text) { |memo, pos| memo.dup.insert(pos, IMPORTANT) }
              piece.with(text:)
            end
            [key, updated]
          end
        end
      end
    end
  end
end
