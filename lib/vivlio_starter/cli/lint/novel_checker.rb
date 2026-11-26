# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/lint/novel_checker.rb
# ================================================================
# 責務:
#   小説の原稿の書き方の決まりを見る規則（規則の組 novel。novel-vertical-spec.md §6.2）。
#     - novel-ellipsis-pair         「…」が奇数個。「・・・」「。。。」（三点リーダーの代わり）
#     - novel-dash-pair             「―」「—」が 1 つだけ
#     - novel-space-after-mark      全角の「！」「？」の後に全角空白が無い
#     - novel-period-before-bracket 閉じかっこの前の句点（「。」」）
#     - novel-paragraph-indent      段落の頭の全角空白（投稿サイトの記法を読まない本）・
#                                   全角空白のある段落と無い段落の混在（読む本）
#     - novel-halfwidth-digits      縦書きの本の、半角の数字 3 桁以上（横に倒れて組まれる）
#
# 規則の組 technical・minimal は、ここの規則を全部切る（Lint::Rulesets）。
#
# どの規則も**読者が見る字**で見る。ProseChecker が渡す行は NotationGuard.strip_notation を
# 通したもので、投稿サイトの記法・ふりがな・クラスの属性は読み替えてある。ここではさらに、
# 行内のコード・URL・強調・リンク・脚注の合印・角かっこを外す。
# `[えっ！]{.sesame}言った` の「！」の後ろは、読者には「言」が続いて見えるので指摘する。
# ================================================================

require_relative '../masking'

module VivlioStarter
  module CLI
    module Lint
      # 小説の原稿の書き方の決まり（ProseChecker から呼ぶ）
      module NovelChecker
        ELLIPSIS_RULE              = 'novel-ellipsis-pair'
        DASH_RULE                  = 'novel-dash-pair'
        SPACE_AFTER_MARK_RULE      = 'novel-space-after-mark'
        PERIOD_BEFORE_BRACKET_RULE = 'novel-period-before-bracket'
        PARAGRAPH_INDENT_RULE      = 'novel-paragraph-indent'
        HALFWIDTH_DIGITS_RULE      = 'novel-halfwidth-digits'

        RULES = [ELLIPSIS_RULE, DASH_RULE, SPACE_AFTER_MARK_RULE, PERIOD_BEFORE_BRACKET_RULE,
                 PARAGRAPH_INDENT_RULE, HALFWIDTH_DIGITS_RULE].freeze

        # --- 字の並び -----------------------------------------------------------

        ELLIPSIS_RUN    = /…+/
        # 三点リーダーの代わりに打った中黒・句点。2 つまでは区切りや打ち誤りの形が多いので 3 つから
        ELLIPSIS_SUBSTITUTE = /・{3,}|。{3,}/
        DASH_RUN        = /[―—]+/
        # 範囲の表記（`1—3`・`A—B`）。前後が英数字のダッシュは、小説の「――」ではない
        ALNUM           = /[0-9A-Za-z０-９Ａ-Ｚａ-ｚ]/
        EXCLAMATION     = /[！？⁉‼]/
        # 「！」「？」の直後に来てよい字。閉じかっこ・続く感嘆符・三点リーダー・ダッシュ・全角空白
        AFTER_MARK_OK   = /[　」』）〉》】〕］｝”’)\]!?！？⁉‼…―—]/
        PERIOD_BEFORE_BRACKET = /。[」』]/
        # 句点を付けずに閉じたかっこ（前が句読点・約物・空白でない）。句点の付け方の多い側を決めるのに数える
        BARE_CLOSING_BRACKET = /[^。、！？⁉‼…―—」』）\s][」』]/
        HALFWIDTH_DIGITS = /[0-9]{3,}/
        KANSUJI = '〇一二三四五六七八九'

        # 括弧で始まる段落（vs が字下げを 0 にする段落。novel-vertical-spec.md §6.1）
        OPEN_BRACKET = /\A[「『（〈《【〔]/

        # 段落でない行。箇条書き・表・見出し・引用・画像・改ページ・区切り線・HTML
        NON_PARAGRAPH = /\A[ \t]*(?:[-*+][ \t]|\d+[.)][ \t]|\||\#+[ \t]|>|!\[|@pagebreak|<)/
        THEMATIC_BREAK = /\A[ \t]*([-*_])(?:[ \t]*\1){2,}[ \t]*\z/

        # 縦書きの本で横組みの箱になる囲み（stylesheets/parts/vertical.css の並びと同じ）。
        # 箱の中は横書きと同じに組まれるので、数字の向きと字下げの規則は見ない
        HORIZONTAL_CONTAINERS = %w[memo tip note notice column output terminal diagram side-by-side
                                   long-table].freeze
        CONTAINER_OPEN  = /\A[ \t]*:{3,}[ \t]*\{?[ \t]*\.?([\w-]+)/
        CONTAINER_CLOSE = /\A[ \t]*:{3,}[ \t]*\z/
        FRONT_MATTER    = /\A---\r?\n.*?^---\r?\n/m

        # 読者に見えない記法（ProseChecker に来る前に外れていないもの）
        LINK_OR_IMAGE = /!?\[([^\[\]\n]*)\]\(#{Masking::LINK_DESTINATION.source}\)/
        FOOTNOTE_REF  = /\[\^[^\]\n]*\]/
        HTML_TAG      = /<[^<>\n]+>/

        module_function

        # @param text [String] 原稿（囲みの範囲と前付けを読む）
        # @param lines [Array(Integer, String)] ProseChecker の地の文の行（記法を読み替えたもの）
        # @param disabled_rules [Array<String>]
        # @param web_novel [Boolean] notation.web_novel（規則 4 の向きが変わる）
        # @param vertical [Boolean] 縦書きの本か（規則 5 は縦書きの本だけ）
        # @return [Array<ProseChecker::Finding>]
        def findings(text, lines, disabled_rules:, web_novel:, vertical:)
          active = RULES - disabled_rules
          return [] if active.empty?

          boxed = horizontal_box_lines(text)
          readable = lines.filter_map do |lineno, line|
            body = reader_text(line)
            [lineno, body] unless body.strip.empty?
          end

          found = []
          readable.each do |lineno, body|
            found.concat(ellipsis_findings(lineno, body)) if active.include?(ELLIPSIS_RULE)
            found.concat(dash_findings(lineno, body)) if active.include?(DASH_RULE)
            found.concat(space_after_mark_findings(lineno, body)) if active.include?(SPACE_AFTER_MARK_RULE)
            if vertical && active.include?(HALFWIDTH_DIGITS_RULE) && !boxed.include?(lineno)
              found.concat(halfwidth_digit_findings(lineno, body))
            end
          end
          if active.include?(PERIOD_BEFORE_BRACKET_RULE)
            found.concat(period_before_bracket_findings(readable))
          end
          if active.include?(PARAGRAPH_INDENT_RULE)
            heads = lines.reject { |lineno, line| boxed.include?(lineno) || !paragraph_line?(line) }
            found.concat(paragraph_indent_findings(heads, web_novel:))
          end
          found.sort_by(&:line)
        end

        # 読者が見る字だけの行。行内のコード・URL・強調・リンク・脚注の合印・HTML を外し、
        # 角かっこ（索引語・行内の属性の残り）を消す
        def reader_text(line)
          body = Masking.strip_urls(Masking.strip_inline_code(line.chomp))
          body, = Masking.strip_emphasis(body)
          body.gsub(FOOTNOTE_REF, '').gsub(LINK_OR_IMAGE) { ::Regexp.last_match(1) }
              .gsub(HTML_TAG, '').delete('[]')
        end

        # --- 規則 1〜3b: 約物 -----------------------------------------------------

        def ellipsis_findings(lineno, body)
          odd = body.scan(ELLIPSIS_RUN).select { it.length.odd? }.map do |run|
            finding(lineno, ELLIPSIS_RULE, "「#{run}」は三点リーダーが奇数個です（「……」と 2 つずつ続ける）")
          end
          odd + body.scan(ELLIPSIS_SUBSTITUTE).map do |run|
            finding(lineno, ELLIPSIS_RULE, "「#{run}」は三点リーダーで書きます（「#{run}」→「……」）")
          end
        end

        def dash_findings(lineno, body)
          body.to_enum(:scan, DASH_RUN).filter_map do
            match = ::Regexp.last_match
            next unless match[0].length == 1
            next if match.pre_match[-1]&.match?(ALNUM) && match.post_match[0]&.match?(ALNUM)

            finding(lineno, DASH_RULE, "「#{match[0]}」が 1 つです（「――」と 2 つ続ける）")
          end
        end

        # 行末（改行・行末の空白の前）の「！」「？」は、次の行が段落なので空けなくてよい
        def space_after_mark_findings(lineno, body)
          stripped = body.rstrip
          stripped.to_enum(:scan, EXCLAMATION).filter_map do
            match = ::Regexp.last_match
            following = match.post_match[0]
            next if following.nil? || following.match?(AFTER_MARK_OK)

            finding(lineno, SPACE_AFTER_MARK_RULE,
                    "「#{match[0]}」の後に全角空白がありません（「#{match[0]}#{following}」→「#{match[0]}　#{following}」）")
          end
        end

        # 閉じかっこの前の句点は、句点を付けずに閉じたかっこより少ない章でだけ示す。
        # 「。」」と書きそろえる書き方（青空文庫の作品の多く）は著者の選んだ表記で、全部を示すと
        # 1 作品で 50 件を超える（注文の多い料理店 62 件・走れメロス 55 件。novel-vertical-spec.md §10.6）。
        # 句点を付けない書き方の中に混ざった「。」」だけが、直す箇所である
        def period_before_bracket_findings(readable)
          periods = readable.flat_map { |lineno, body| body.scan(PERIOD_BEFORE_BRACKET).map { [lineno, it] } }
          bare = readable.sum { |_lineno, body| body.scan(BARE_CLOSING_BRACKET).size }
          return [] if periods.size >= bare

          periods.map do |lineno, found|
            finding(lineno, PERIOD_BEFORE_BRACKET_RULE, "閉じかっこの前に句点があります（「#{found}」→「#{found[-1]}」）")
          end
        end

        # --- 規則 5: 縦書きの半角の数字 ------------------------------------------

        def halfwidth_digit_findings(lineno, body)
          body.scan(HALFWIDTH_DIGITS).map do |digits|
            kansuji = digits.tr('0-9', KANSUJI)
            fullwidth = digits.tr('0-9', '０-９')
            finding(lineno, HALFWIDTH_DIGITS_RULE,
                    "半角の数字 3 桁以上は横に倒れて組まれます（「#{digits}」→「#{kansuji}」か「#{fullwidth}」）")
          end
        end

        # --- 規則 4: 段落の頭の全角空白 -------------------------------------------

        # 投稿サイトの記法を読まない本では、段落の頭の全角空白は CSS の字下げに足されて 2 字下がる。
        # 読む本では前処理が 1 つ落とすので組み上がりは同じだが、投稿サイトへ出す原稿の
        # 書き忘れを見つけるため、1 つの章の中で混ざっていれば少ない側を示す（同数なら無い側）。
        # 括弧で始まる段落は、どちらの書き方でも全角空白を付けないので数えない
        def paragraph_indent_findings(heads, web_novel:)
          unless web_novel
            return heads.select { |_lineno, line| line.start_with?("　") }.map do |lineno, _line|
              finding(lineno, PARAGRAPH_INDENT_RULE, '段落の頭の全角空白で 2 字下がります（全角空白を消す）')
            end
          end

          counted = heads.reject { |_lineno, line| line.delete_prefix("　").match?(OPEN_BRACKET) }
          spaced, bare = counted.partition { |_lineno, line| line.start_with?("　") }
          return [] if spaced.empty? || bare.empty?

          if spaced.size < bare.size
            spaced.map { |lineno, _| finding(lineno, PARAGRAPH_INDENT_RULE, '段落の頭に全角空白があります（この章のほかの段落にそろえて消す）') }
          else
            bare.map { |lineno, _| finding(lineno, PARAGRAPH_INDENT_RULE, '段落の頭に全角空白がありません（この章のほかの段落にそろえて足す）') }
          end
        end

        def paragraph_line?(line)
          body = line.chomp
          !body.strip.empty? && !body.match?(NON_PARAGRAPH) && !body.match?(THEMATIC_BREAK)
        end

        # --- 内部 -------------------------------------------------------------

        # 横組みの箱になる囲みの中の行と、前付けの行
        def horizontal_box_lines(text)
          boxed = Set.new
          front = text[FRONT_MATTER]
          boxed.merge(1..front.count("\n")) if front
          stack = []
          Masking.each_prose_line(text) do |line, lineno|
            if line.match?(CONTAINER_CLOSE)
              stack.pop
            elsif (name = line[CONTAINER_OPEN, 1])
              stack << name
            end
            boxed << lineno if stack.intersect?(HORIZONTAL_CONTAINERS)
          end
          boxed
        end

        def finding(line, rule, label) = ProseChecker::Finding.new(line:, rule:, label:)
      end
    end
  end
end
