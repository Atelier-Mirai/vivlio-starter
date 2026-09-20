# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/textlint_formatter.rb
# ================================================================
# 責務:
#   textlint --format json の出力を、ルール（メッセージ先頭行）単位に集約して整形する。
#   同じ指摘を 1 行へ畳む（スペルチェック側 SpellChecker.aggregate と体裁を揃える）。
#
#   **ルールや語で指摘を落とすのは、ここの仕事ではない。** book.yml の lint.disabled_rules と
#   lint.trim_long_vowel は、実行時 textlintrc（LintRunner#generate_runtime_config）が効かせる。
#   以前はここでも落としていたが、表示から落とすだけでは `vs lint --fix` に効かず、「表示には
#   出ないのに --fix が直す」食い違いを 6 回生んだ（lint-false-positive-notes.md §7）。設定で
#   取りこぼしたものは、ここで隠さずに表示へ出す——出れば --fix と一致し、著者が気づける。
#   ここで落とすのは次行抑止の行だけで、これは修正パスも同じ行を退避している。
#
#   語単位で指摘を黙らせたい場合は config/textlint_allowlist.yml を使う
#   （textlint 本来のフィルタ。原稿の語を全ルールから除外する）。
#
# 用途:
#   - LintCommands（vs lint の textlint 集約表示）から呼び出される
# ================================================================

require 'json'

module VivlioStarter
  module CLI
    # textlint --format json 出力の集約フォーマッター
    class TextlintFormatter
      # --- Public API ---

      # textlint --format json の出力を、メッセージ（先頭行）＋ルール単位で集約する。
      # スペルチェック側（SpellChecker.aggregate）と同様、同じ指摘を 1 行へ畳んで見やすくする。
      # @param json_string [String] textlint --format json の生出力
      # @param base_dir [String] ファイルパスの相対化基準
      # @param suppressed_lines [Hash] { 絶対パス => 行番号の集合 }。その行の指摘を丸ごと落とす
      # @return [Hash, nil] { files: [{ path:, rows: }], total:, fixable: } / JSON 解釈失敗時 nil
      #   rows: [{ count:, label:, lines: [Integer] }]（label は "[ルール] 指摘先頭行"）。
      #   **並べ替えも行番号の整形もここではしない**——独自校正の指摘と混ぜて 1 つの表へ
      #   並べるため、順序が決まるのは両方が揃ってから（Lint::FindingRows.arrange）。
      def self.aggregate_json(json_string, base_dir: Dir.pwd, suppressed_lines: {})
        data = JSON.parse(json_string.to_s)
        return nil unless data.is_a?(Array)

        total = 0
        fixable = 0
        files = data.filter_map do |file|
          # 行単位の抑止は集約より前に当てる（集約後は行番号が畳まれて選り分けられない）
          hushed = suppressed_lines[File.expand_path(file['filePath'].to_s)] || []
          messages = Array(file['messages']).reject { |m| hushed.include?(m['line']) }
          next if messages.empty?

          total += messages.size
          fixable += messages.count { |m| m['fix'] }
          { path: relative_md_path(file['filePath'], base_dir), rows: aggregate_messages(messages) }
        end
        { files: files, total: total, fixable: fixable }
      rescue JSON::ParserError
        nil
      end

      # ルールの表示文を固定の見出しへ置き換える表。
      #
      # `no-mix-dearu-desumasu` は表示文が判定の実態より広く聞こえる。判定を担う
      # analyze-desumasu-dearu は常体を「で」＋「ある」の並びだけで数えるのに、
      # 「"である"調」と言うと「〜だ」「〜する」まで見ているように読める。先頭の
      # 「箇条書き:」「本文:」も外す——場所の区別を残すと、箇条書き専用の機能に見えるため。
      # ここに置いた文は**挙がった語を読み取れなかったときの受け皿**で、ふだんは
      # mixed_style_head が語を添えた見出しを組み立てる。
      # **本物の敬体・常体検出を実装したら、この行ごと削除する**（PLANNED.md の
      # 「文体（敬体・常体）の混在を実際に見張る独自ルール」）。
      MIXED_STYLE_RULE = 'no-mix-dearu-desumasu'

      RULE_SUMMARIES = {
        MIXED_STYLE_RULE => '「である」と「です・ます」が混在しています。'
      }.freeze

      # no-mix-dearu-desumasu の 2 行目から、挙がった語と多数派の文体を取り出す。上流はこう書く:
      #   => "ですます"調 の文体に、次の "である"調 の箇所があります: "である。"
      #
      # **どの語が挙がったのかを落とさない。** 固定の要約に畳んでいた頃は「混在しています」と
      # しか出ず、直す手がかりを得るのに textlint --format json を手で叩く必要があった（実測）。
      # 上流が最初から持っている情報を、要約の段で捨てていたことになる。
      #
      # 多数派と少数派を文言から読むので、逆向き（である調の中の「です。」）も同じ形で出る。
      # 読み取れなければ固定文に戻す——上流が文言を変えても、指摘そのものは落とさない。
      MIXED_STYLE_DETAIL = /"(?<majority>[^"]+)"調 の文体に、次の "[^"]+"調 の箇所があります: "(?<found>[^"]+)"/

      # 文体の名前。上流の「ですます」は、本書の書き方（です・ます）へ直して見せる。
      MIXED_STYLE_NAMES = { 'ですます' => 'です・ます' }.freeze

      def self.mixed_style_head(message)
        matched = MIXED_STYLE_DETAIL.match(message.to_s)
        return RULE_SUMMARIES[MIXED_STYLE_RULE] unless matched

        majority = MIXED_STYLE_NAMES.fetch(matched[:majority], matched[:majority])
        "「#{matched[:found]}」が「#{majority}」の中に混在しています"
      end

      # 上流ルールの英文メッセージを日本語に差し替える表（ルール => [照合, 差し替え文]）。
      #
      # 日本語の原稿を書いている著者に英文だけが返るのは、それだけで指摘が読み飛ばされる。
      # 上限値のような**意味のある数値は差し替え文へ持ち越す**——`Maximum is 3` を
      # 「多すぎます」に丸めると、あと何個減らせばよいのかが分からなくなるためである。
      #
      # max-comma が数えるのは半角カンマだけで、和文の読点は max-ten が別に見ている。
      # 和文に半角カンマが並ぶのは数字の桁区切り（`2,894 × 4,092 px`）か欧文の語の並びで、
      # 実際この 2 つしか本書では当たらない。何を数えられたのか著者には分からないので、
      # 桁区切りも数に入ることを文言へ書いた（warning-messages-actionable）。
      #
      # ここは**表示だけ**を差し替える。指摘そのものは消さないので、--fix との食い違いは
      # 起きない（lint-false-positive-notes.md §7 が戒めているのは、表示の段で
      # 黙らせて --fix に効かない状態を作ることである）。
      MESSAGE_TRANSLATIONS = {
        'max-comma' => [
          /\AThis sentence exceeds the maximum count of comma\. Maximum is (\d+)\.?\z/,
          '一つの文に半角カンマが多すぎます（上限 %<max>s 個）。' \
          '読点「、」で区切るか文を分けてください（数字の桁区切りも数えます）'
        ]
      }.freeze

      # メッセージ配列を [集約見出し, ルール] 単位で集約する。
      # 通常はメッセージ先頭行ごと（prh の置換などは別グループ）だが、RULE_SUMMARIES に
      # 載せたルールは固定の見出しで 1 つに畳む。
      # 並べ替えと出現行の表示は呼び出し側（Lint::FindingRows）に任せる。
      def self.aggregate_messages(messages)
        messages.group_by { |m| [grouping_head(m['message'], m['ruleId']), short_rule(m['ruleId'])] }
                .map do |(head, rule), items|
          { count: items.size, label: "[#{rule}] #{head}", lines: items.filter_map { it['line'] } }
        end
      end

      # 集約見出し：RULE_SUMMARIES のルールは要約ラベルで 1 つに畳み、
      # それ以外は先頭行そのまま（"一つ => 1つ" の数字など、意味のある数値を保つ）。
      # 英文のまま返ってくるルールは、ここで日本語へ差し替える。
      def self.grouping_head(message, rule_id)
        rule = short_rule(rule_id)
        return mixed_style_head(message) if rule == MIXED_STYLE_RULE

        RULE_SUMMARIES[rule] || translate_message(rule, message_head(message))
      end

      # 英文メッセージを MESSAGE_TRANSLATIONS の文言へ差し替える。
      # 表に無いルールと、表にあっても文面が変わった（上流の更新）ものは素通しにする——
      # 訳し損ねた英文が出るほうが、指摘そのものを取り落とすよりずっとよい。
      def self.translate_message(rule, head)
        pattern, template = MESSAGE_TRANSLATIONS[rule]
        return head unless pattern && (m = pattern.match(head))

        format(template, max: m[1])
      end

      # 指摘の頭に付くパターン番号（`ja-no-redundant-expression` の `【dict2】`）。
      # ルールが内部で持つ 6 つのパターンの名前で、2 行目に添えられる解説 URL の
      # アンカー（`…#dict2`）でもある。`vs lint` は先頭行だけを見せるので、
      # 著者の手元には意味の読み取れない記号だけが残る。
      DICTIONARY_TAG = /\A【dict\d+】[ 　]*/

      # メッセージの先頭行（actionable な指摘部分。prh の置換や ja-spacing の本文）。
      # 「実際 => 期待」の違いが空白や字幅だけのものは、違いを見える形にして注記を添える。
      # **先に切り詰めない**——先頭の空白こそが直す対象のことがある（difference_head）。
      def self.message_head(message)
        line = message.to_s.lines.first.to_s.chomp
        difference_head(line) || line.strip.sub(DICTIONARY_TAG, '')
      end

      # 「実際 => 期待」の区切り
      ARROW = ' => '

      # 違いとして数える空白（半角・全角・タブ）
      BLANKS = " 　\t"

      # 「実際 => 期待」の違いが空白や字幅だけで、端末では同じ字が並んで見えてしまう指摘に
      # 注記を添えた見出しを返す。当たらなければ nil（呼び出し側が素の見出しを使う）。
      #
      # 実測: 上流の「全角かっこの前後の空白を消せ」は `" ） => ）"` を出すが、先頭の空白が
      # 切り詰められて「） => ）」と表示され、何を直せばよいか読めなかった。半角かっこを
      # 全角へ直す指摘も、`(2026年) => （2026年）` の違いが字幅だけで見分けにくい。
      #
      # 実際側にも ` => ` が現れうる（`(token => count) => （token => count）`）ので、
      # 区切りの候補を順に試し、空白か字幅の違いとして説明がつく切り方を採る。
      def self.difference_head(line)
        arrow_positions(line).each do |at|
          actual   = line[0...at]
          expected = line[(at + ARROW.size)..]

          if blank_only_difference?(actual, expected)
            note = actual.count(BLANKS) > expected.count(BLANKS) ? '空白を削除' : '空白を追加'
            return "#{show_blanks(actual)}#{ARROW}#{show_blanks(expected)}（#{note}）"
          end
          if width_only_difference?(actual, expected)
            note = fullwidth_count(expected) > fullwidth_count(actual) ? '半角 → 全角' : '全角 → 半角'
            return "#{actual.strip}#{ARROW}#{expected.strip}（#{note}）"
          end
        end
        nil
      end

      def self.arrow_positions(line)
        positions = []
        at = -1
        positions << at while (at = line.index(ARROW, at + 1))
        positions
      end

      def self.blank_only_difference?(actual, expected)
        actual != expected && !actual.delete(BLANKS).empty? && actual.delete(BLANKS) == expected.delete(BLANKS)
      end

      # 互換分解（NFKC）で同じになる＝違いは字幅だけ
      def self.width_only_difference?(actual, expected)
        actual.strip != expected.strip &&
          actual.strip.unicode_normalize(:nfkc) == expected.strip.unicode_normalize(:nfkc)
      end

      # 全角の英数記号（NFKC で半角に畳まれる字）の数
      def self.fullwidth_count(text) = text.each_char.count { it != it.unicode_normalize(:nfkc) }

      # 空白を見える記号にする（半角 `␣`・全角 `□`）
      def self.show_blanks(text) = text.gsub(' ', '␣').gsub("　", '□').gsub("\t", '→')

      # ルール ID を短縮（"ja-spacing/ja-space-around-code" → "ja-space-around-code"）
      def self.short_rule(rule_id) = rule_id.to_s.split('/').last.to_s

      # textlint の絶対パスを base_dir 相対へ
      def self.relative_md_path(path, base_dir)
        rel = path.to_s.sub(%r{\A#{Regexp.escape(base_dir.to_s)}/?}, '')
        rel.empty? ? path.to_s : rel
      end
    end
  end
end
