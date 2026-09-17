# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/lint/prose_checker.rb
# ================================================================
# 責務:
#   textlint のルールでは扱えない指摘を、原稿へ直接当てる。
#     - mazegaki             交ぜ書き（「だ円」→「楕円」）。1 対 1 の置換なので --fix できる
#     - ambiguous-comparison 二通りに読める対比（「B は A と同じように X しない」）
#     - stray-index-markup   索引語のつもりでない `[g]`（markdown-notation-collision-spec.md §5）
#     - indented-code-block  非対応の 4 スペース字下げコードブロック（同 §6）
#     - setext-heading       改ページのつもりが見出しになる `---` / `===`（同 §7）
#     - slash-between-japanese 和文どうしを半角スラッシュで並べた箇所
#     - space-around-brackets  かっこの隣の空白。区切り記号（`） — `）や強調の閉じの隣は許容
#     - long-parenthetical   長すぎる補足（丸かっこの中の和文が 60 字を超える）
#     - kanji-lookalike      漢字に見える康煕部首（`⽇本` の `⽇`）。1 対 1 の置換なので --fix できる
#     - kansuji-counter-suffix 数と「つ」の表記。数は漢数字（`2 つ` → `二つ`）、記号の個数は算用数字
#
# なぜ prh 辞書ではなく Ruby なのか:
#   交ぜ書きは 1 対 1 の置換なので config/textlint_rewrite.yml（prh）へ書けば
#   済むように見えるが、(1) config/ は著者が編集するファイルで vs upgrade が
#   上書きできず、既刊の原稿を抱えた著者へ届かない、(2) prh の指摘はすべて
#   ruleId: prh なので lint.disabled_rules で切ると表記揺れ辞書ごと死ぬ、
#   (3) 対比の書き換えは文脈依存で、prh の expected は --fix が機械的に当てて
#   しまう——の 3 点で採れない。gem 本体に置けば gem の更新だけで届く。
#   仕様: lint-japanese-prose-rules-spec.md §2
#
# 「ら抜き言葉」はここにない:
#   preset-ja-technical-writing の no-dropping-the-ra が既に検出している（textlint 側）。
#
# 依存:
#   - Masking: コード領域の判定（辞書をコード例へ当てないため）
#   - MazegakiDictionary: 交ぜ書きの語（採否の基準と、落とした語の理由もあちら側）
#   - MazegakiScanner: MeCab があるときだけ足す第 2 層（mazegaki-two-tier-spec.md）
# ================================================================

require 'yaml'

require_relative '../common'
require_relative '../index_markup'
require_relative '../masking'
require_relative 'notation_guard'
require_relative 'mazegaki_dictionary'
require_relative 'mazegaki_scanner'

module VivlioStarter
  module CLI
    module Lint
      # 日本語の文へ当てる独自校正ルール（textlint の外側）。
      module ProseChecker
        module_function

        # 1 件の指摘。rule は book.yml の lint.disabled_rules に書く名前と同じ。
        Finding = Data.define(:line, :rule, :label)

        MAZEGAKI_RULE  = 'mazegaki'
        AMBIGUOUS_RULE = 'ambiguous-comparison'
        STRAY_INDEX_RULE     = 'stray-index-markup'
        INDENTED_CODE_RULE   = 'indented-code-block'
        SETEXT_RULE          = 'setext-heading'
        SLASH_RULE           = 'slash-between-japanese'
        BRACKET_SPACE_RULE   = 'space-around-brackets'
        LONG_PARENTHETICAL_RULE = 'long-parenthetical'
        KANJI_LOOKALIKE_RULE = 'kanji-lookalike'
        KANSUJI_COUNTER_RULE = 'kansuji-counter-suffix'
        MISSING_PERIOD_RULE  = 'missing-period'

        # --fix で直せるルール。どちらも「この文字列はこう書く」が 1 つに決まる。
        FIXABLE_RULES = [MAZEGAKI_RULE, KANJI_LOOKALIKE_RULE].freeze

        # --- 記法の取り違え -----------------------------------------------------

        # 4 スペース以上の字下げで始まる行。CommonMark では字下げコードブロックだが、
        # Vivlio Starter は非対応（§6）。
        INDENTED_LINE = /\A {4,}\S/

        # リスト項目の先頭。字下げ行がリストの続きなら指摘しない。
        LIST_ITEM_HEAD = /\A[ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]/

        # Setext 見出しの下線。`=` なら h1、`-` なら h2 になる。
        # **行末の改行まで見込む。** prose_lines が渡すのは chomp していない生の行で、
        # `\z` だけで閉じると "---\n" に当たらず、指摘が 1 件も出ない（実測で踏んだ）。
        SETEXT_UNDERLINE = /\A {0,3}(=+|-+)[ \t]*\r?\n?\z/

        # 交ぜ書き辞書の第 1 層。MeCab が無くても動く語だけが入っている。
        # 語の採否と、誤検出で落とした語の理由は辞書側に置く。
        # 第 2 層（MeCab 必須の 1,921 語）は MazegakiScanner が持つ。
        MAZEGAKI = MazegakiDictionary::ALL

        # --- 二通りに読める対比 -----------------------------------------------

        # 比較を表す表現。この後ろに否定が来ると「比較対象も否定側なのか」が読めない。
        #
        # **「のように」を入れてはならない。** 実測で 10 件検出し、10 件すべてが誤検出だった
        # （2026-08-18・本書 27 ファイル）。「`@titlepage` のように文字が続く場合は展開され
        # ません」「金のように仕事関数が大きい金属は…」のように、日本語の「のように」は例示・
        # 限定・様態に広く使われ、比較の意味だけを正規表現で切り出す手立てがない。
        # ここに残した 3 つは比較の格助詞「と」を伴うため、構文として比較であることが確定する。
        # 「スレッドのように共有しない」のような形は見逃すが、無視される lint になるよりよい。
        COMPARISON = /と同じよう[にな]|と同様[にのな、]|と同じく/

        # 否定。文末に限らないのは「共有しないため、〜」のように文中へ来るため。
        NEGATION = /ない|ませ[んぬ]|ずに|ず[、。」）]|ぬ[。」）]/

        # Markdown のブロックが始まる行（箇条書き・番号付き・表・見出し・引用）。
        #
        # **段落の切れ目として要る。** これが無いと箇条書きの項目どうしが 1 文へ連結され、
        # 隣り合うだけの行で「比較 → 否定」が成立して誤検出になる（実測で 5 件。
        # 「複数章は `主要参照: …`（カンマ区切り）」という比較表現の無い行が、前の項目の
        # 「と同様の」と繋がって挙がっていた）。表のセルどうしでも同じことが起きる。
        BLOCK_START = /\A[ \t]*(?:[-*+][ \t]|\d+[.)][ \t]|\||\#+[ \t]|>)/

        # --- 文末の句点 ---------------------------------------------------------

        # 段落がひらがなで終わっている＝用言（動詞・形容詞・助動詞）の終止形で終わっている。
        #
        # 日本語の用言は終止形が必ずひらがなになる（`…する` `…ない` `…した` `…です` `…ます`）。
        # 逆に体言止めは名詞で終わるので、漢字・カタカナ・英数字・閉じかっこになる。
        # **末尾 1 文字の種類だけで、句点を求めるべき文と、求めてはいけない書き方が分かれる。**
        #
        # 長音記号 `ー` を入れてはならない——`…のメンバー` のようなカタカナ語の末尾に付き、
        # 体言止めを用言と読み違える。範囲は U+3041〜U+3096 に限る。
        HIRAGANA_END = /[ぁ-ゖ]\z/

        # 小見出しとして書かれた段落（`**独自の装飾を追加する**` のように、段落全体が強調ひとつ）。
        # 組版でも小見出しとして組まれるもので（`PostProcess.mark_strong_headings!` が
        # strong-heading クラスを付ける。本書で 98 件）、見出しに句点は付けない。
        # **強調を外す前の行で判定する**——外すと地の文と見分けが付かなくなる。
        STRONG_HEADING = /\A\*\*[^*\n]+\*\*\z/

        # 文の区切り。句点のほかに表のセル境界（`|`）でも切る——1 行の中で隣り合う
        # だけのセルが 1 文として読まれ、「Kindle と同じく PDF ページを切り出す」と
        # 「文字が選択できず…」が繋がって挙がっていた（実測 1 件）。
        SENTENCE_BREAK = /(?<=。)|(?<=\|)/

        # 指摘を抑止するコメント（textlint 側と同じ vs-lint 記法）。
        # `-next-line` を先に判定する必要はない——`vs-lint-disable` のパターンは直後に
        # `-->` を求めるため、`vs-lint-disable-next-line` には当たらない。
        DISABLE_NEXT_LINE   = /<!--\s*vs-lint-disable-next-line\s*-->/
        DISABLE_RANGE_OPEN  = /<!--\s*vs-lint-disable\s*-->/
        DISABLE_RANGE_CLOSE = /<!--\s*vs-lint-enable\s*-->/

        # 「ない」で終わるが否定ではない語。先に落としてから NEGATION を当てる。
        NOT_NEGATION = /少ない|危ない|もったいない|情けない|切ない|はかない|あどけない|
                        だらしない|とんでもない|さりげない|何気ない|違いない|他ならない/x

        # --- 除外リスト（config/textlint_allowlist.yml） ------------------------

        # 正規表現で書かれたエントリ（`"/(プロジェクト|プロダクト)マネージャ/"`）。
        ALLOWLIST_REGEXP_FORM = %r{\A/(.+)/([imx]*)\z}

        # 除外リストを読んで正規表現の配列にする。
        #
        # **窓口を増やさないために textlint と同じファイルを読む。** 語単位で指摘を
        # 黙らせる窓口はここに一本化されており（`book.yml` の `lint.disabled_terms` は
        # 「指摘したくない語句は config/textlint_allowlist.yml に書きます」という理由で
        # 廃止済み）、独自ルールだけ別の場所を見ると著者が二度学ぶことになる。
        # @return [Array<Regexp>]
        def allowlist_from(path)
          return [] unless path && File.file?(path)

          raw     = YAML.safe_load_file(path, aliases: true)
          entries = raw.is_a?(Hash) ? Array(raw['allow']) : Array(raw)
          entries.filter_map { compile_allowlist_entry(it) }
        rescue StandardError => e
          Common.log_warn("[lint] 除外リストを読み込めませんでした: #{path} (#{e.message})")
          []
        end

        # 除外リストの 1 行を正規表現へ。壊れた正規表現は黙って捨てる
        # （textlint 側が同じファイルを読んで別途エラーにするので、二重に騒がない）。
        def compile_allowlist_entry(entry)
          text = entry.to_s.strip
          return nil if text.empty?

          if (matched = text.match(ALLOWLIST_REGEXP_FORM))
            Regexp.new(matched[1], matched[2].include?('i') ? Regexp::IGNORECASE : nil)
          else
            Regexp.new(Regexp.escape(text))
          end
        rescue RegexpError
          nil
        end

        # 指摘語が除外リストに覆われているか。
        #
        # **語全体が覆われたときだけ黙らせる**（textlint の allowlist と同じ判定）。
        # 部分一致で黙らせると、「括弧」という 1 行が「かぎ括弧 => 鉤括弧」まで消してしまう
        # ——除外リストには実際に「括弧」があり、あれは「括弧 => カッコ」を止めるためのもので、
        # 交ぜ書きの指摘まで止める意図ではない。
        def allowed?(word, patterns)
          patterns.any? do |pattern|
            matched = pattern.match(word)
            matched && matched[0] == word
          end
        end

        # --- 検査 -------------------------------------------------------------

        # 1 ファイルを検査する。
        # @param path [String] 対象の原稿パス
        # @param disabled_rules [Array<String>] book.yml lint.disabled_rules
        # @param allowlist [Array<Regexp>] allowlist_from が返す除外パターン
        # @param parenthetical_max [Integer, :off, nil] book.yml lint.parenthetical_length_max
        # @return [Array<Finding>]
        def check(path, disabled_rules: [], allowlist: [], parenthetical_max: nil)
          text  = File.read(path, encoding: 'UTF-8')
          rules = Array(disabled_rules).map(&:to_s)

          findings = []
          findings.concat(mazegaki_findings(text, allowlist))  unless rules.include?(MAZEGAKI_RULE)
          findings.concat(ambiguous_findings(text))            unless rules.include?(AMBIGUOUS_RULE)
          findings.concat(stray_index_findings(text))          unless rules.include?(STRAY_INDEX_RULE)
          findings.concat(indented_code_findings(text))        unless rules.include?(INDENTED_CODE_RULE)
          findings.concat(setext_findings(text))               unless rules.include?(SETEXT_RULE)
          findings.concat(slash_findings(text))                unless rules.include?(SLASH_RULE)
          findings.concat(bracket_space_findings(text))        unless rules.include?(BRACKET_SPACE_RULE)
          findings.concat(missing_period_findings(text))       unless rules.include?(MISSING_PERIOD_RULE)
          unless rules.include?(LONG_PARENTHETICAL_RULE) || parenthetical_max == :off
            findings.concat(long_parenthetical_findings(text, parenthetical_max || PARENTHETICAL_MAX))
          end
          findings.concat(kanji_lookalike_findings(text))      unless rules.include?(KANJI_LOOKALIKE_RULE)
          findings.concat(kansuji_counter_findings(text))      unless rules.include?(KANSUJI_COUNTER_RULE)
          findings
        rescue Errno::ENOENT => e
          Common.log_warn("[lint] ファイルを読み込めませんでした: #{path} (#{e.message})")
          []
        end

        # 交ぜ書きの指摘。コード領域は Masking が除くので、コード例の中の語は拾わない。
        #
        # 除外リストが効くのは交ぜ書きだけである。あれは「この語はこのままでよい」という
        # 語彙の宣言なので、構文の指摘（二通りに読める対比）には当てはまらない。
        # 対比を黙らせるときは `<!-- vs-lint-disable -->` か `lint.disabled_rules` を使う。
        def mazegaki_findings(text, allowlist = [])
          prose_lines(text).flat_map do |lineno, line|
            protected_line, = Masking.protect_code(line)
            # 辞書は**読者が見る文字列**に当てる。生の行に当てると、語の途中に入った
            # 強調で両方向に壊れる（`結**合し**直した` の誤検出、`だ**円**` の取りこぼし）。
            # 仕様: inline-emphasis-word-split-spec.md
            body, = Masking.strip_emphasis(protected_line)
            hits = MAZEGAKI.filter_map do |pattern, expected|
              found = body[pattern]
              next unless found && !allowed?(found, allowlist)

              [found, expected]
            end
            hits.concat(scanner_hits(body, allowlist))

            drop_subsumed(hits.uniq).map do |found, expected|
              Finding.new(line: lineno, rule: MAZEGAKI_RULE, label: "#{found} => #{expected}")
            end
          end
        end

        # 第 2 層（MeCab の形態素境界を見る語）の指摘。MeCab が無ければ常に空になり、
        # 第 1 層だけで動く。仕様: mazegaki-two-tier-spec.md §2
        def scanner_hits(body, allowlist)
          MazegakiScanner.scan(body).filter_map do |found, expected, _start, _finish|
            [found, expected] unless allowed?(found, allowlist)
          end
        end

        # 同じ行で長い語が当たっているなら、その一部でしかない語は出さない。
        # 「障がい者」の行は「障がい」にも当たるので、放っておくと 1 箇所に 2 件並ぶ。
        # 残すのは長いほう——「障がい者 => 障碍者」のほうが、著者が直す形に近い。
        #
        # 限界: 「障がい者手帳。障がいのある方」のように 1 行へ両方が出ると、
        # 短いほうの指摘まで畳まれる（検出は語ごとに行 1 件なので、2 つ目の
        # 「障がい」を別に数える術がない）。`--fix` は両方とも置換するため実害は小さい。
        def drop_subsumed(hits)
          hits.reject do |(word, _)|
            hits.any? { |(other, _)| other != word && other.include?(word) }
          end
        end

        # --- 和文どうしの並列スラッシュ ----------------------------------------

        # 和文の 1 文字。並列の両側が和文かどうかの判定に使う。
        JAPANESE_CHAR = /[ぁ-んァ-ヴー々〆一-龥]/

        # スラッシュで隣り合う 2 語。表のセル境界（`|`）と、括弧・句読点は越えない——
        # 越えると地の文を巻き込み、`生成された扉絵/装飾などの画像を削除` のように
        # どこが問題なのか読み取れない見出しになる（実測）。
        SLASH_BOUNDARY = %r{[^\s/|（）()「」『』【】、。，．]}
        SLASH_PAIR = /(#{SLASH_BOUNDARY}{1,6})([ \t]*\/[ \t]*)(#{SLASH_BOUNDARY}{1,6})/

        # 和文どうしを半角スラッシュで並べた箇所（`メリット / デメリット`・`有効/無効`）。
        #
        # **両側が和文のときだけ**を見る。片側でも欧文なら黙る理由は 2 つあり、どちらも
        # 本書の原稿から出た実例である。
        #   - `EPUB / Kindle` のような欧文の並列は、詰めると一語に見えて読みにくい。
        #     日本語の技術書で広く使われる書き方なので、叩くべきではない（実測 270 件）。
        #   - `しきい周波数 / Hz` は**単位を表す除算**で、`・` に置き換えると意味が変わる。
        # textlint の `ja-no-space-around-slash` はこの区別を持たず、空きの有無だけで
        # 叩くため、本ルールで置き換えている（切り替えは lint.rb の SUPERSEDED_TEXTLINT_RULES）。
        #
        # 直し方を著者に委ねる（`--fix` しない）のは、`・` と全角 `／` のどちらが合うかが
        # 文脈で決まるため。記法の取り違えルールと同じ方針である。
        def slash_findings(text)
          prose_lines(text).flat_map do |lineno, line|
            protected_line, = Masking.protect_code(line)
            slash_pairs(protected_line).map do |left, separator, right|
              Finding.new(line: lineno, rule: SLASH_RULE,
                          label: "#{left}#{separator}#{right} は和文どうしの並列です" \
                                 '（`/` を `・` か全角 `／` に）')
            end
          end
        end

        # 1 行から、両側が和文のスラッシュだけを拾う
        def slash_pairs(line)
          pairs = []
          line.scan(SLASH_PAIR) do
            left, separator, right = ::Regexp.last_match(1), ::Regexp.last_match(2), ::Regexp.last_match(3)
            next unless left[-1].match?(JAPANESE_CHAR) && right[0].match?(JAPANESE_CHAR)

            pairs << [left, separator, right]
          end
          pairs
        end
        private_class_method :slash_pairs

        # --- 長すぎる補足 -----------------------------------------------------

        # 丸かっこの中身（入れ子は追わない。原稿では入れ子のかっこを使わない）
        PARENTHETICAL = /（([^（）]*)）/

        # 補足として許す和文の長さの既定値（book.yml の lint.parenthetical_length_max で変えられる）。
        # **本書での最長は 39 字**なので、60 字は「読みながら本筋を見失う」ほど
        # 伸びた補足だけに当たる高さである。
        PARENTHETICAL_MAX = 60

        # 和文の長さを測るときに落とすもの。インラインコードの目印と、欧文の連なり。
        # `（yellow / orange / red / magenta / …）` のような値の列挙は**補足ではなく一覧**で、
        # 字数で叩いても直しようがない（実測: 生の長さで並べると上位はすべてこの形だった）。
        LATIN_RUN = %r{[A-Za-z0-9_.:#@%\-/ ]+}

        # 長すぎる補足の指摘。
        #
        # `sentence-length` は丸かっこの中を数えない設定にしてある（`.textlintrc.yml`）。
        # 読者はかっこを読み飛ばして本筋を追えるので、一文の読みにくさを測るには外すのが
        # 実態に合う——本書では 66 件の指摘のうち 30 件が、補足のぶんで上限を超えていた。
        # そのぶん「かっこの中だけが伸びる」書き方を見張る役がいるので、こちらで受ける。
        #
        # **句点で区切って数える。** `（…など。単位を省略すると mm 扱い）` のように、
        # 補足の中に 2 文入ることがある。まとめて数えると、短い文の集まりが長い補足に見える。
        def long_parenthetical_findings(text, limit = PARENTHETICAL_MAX)
          prose_lines(text).flat_map do |lineno, line|
            protected_line, spans = Masking.protect_code(line)
            long_parentheticals(protected_line, limit).map do |part, length|
              snippet = Masking.restore_code(part, spans).strip[0, 20]
              Finding.new(line: lineno, rule: LONG_PARENTHETICAL_RULE,
                          label: "（#{snippet}…）は補足として長すぎます" \
                                 "（和文 #{length} 字。文を分けるか、かっこの外へ出してください）")
            end
          end
        end

        # 文末に句点が無い段落を指摘する。textlint の `ja-no-mixed-period` の置き換え。
        #
        # **体言止めは指摘しない。** あちらは段落の末尾が句点でなければ一律に叩くが、
        # 日本語には句点を付けない書き方がある。実測（本書 39 件）では 12 件がそれで、
        # `**用途**: PDF閲覧、電子配布` のような定義、図に添えるキャプション、読点で
        # 終えて次のブロックへ続ける書き方まで「句点を付けよ」と言っていた。見分けは
        # 末尾 1 文字で付く（HIRAGANA_END）。
        #
        # 記法を先に中和するのは、`:::{.output}` の実行結果を文として読ませないため
        # （G1。機械が出した文字列に句点を求めても著者は直しようがない）。行数は
        # 保存されるので、指摘の行番号は原稿のままになる。
        #
        # 箇条書き・見出し・表・引用で始まる段落は見ない。項目や見出しに句点を付けない
        # のは一般の作法で、textlint 側も `ListItem` を最初から除外している。
        #
        # 助詞で終わる形（`…という自然な習慣で` `…用語集へ`）は残る。文ではないので
        # 指摘は正しくないが、助詞の一覧を抱えるより `<!-- vs-lint-disable-next-line -->`
        # で抑えるほうが軽いと判断した（実測で本書 2 件）。
        #
        # `--fix` はしない——句点を足すのか体言止めに直すのかは、著者にしか決められない。
        def missing_period_findings(text)
          guarded = NotationGuard.strip_notation(text)
          sources = prose_lines(guarded).to_h { |lineno, line| [lineno, line.strip] }

          prose_paragraphs(guarded).filter_map do |paragraph|
            body = paragraph[:text]
            next if body.match?(BLOCK_START) || !body.match?(HIRAGANA_END)
            next if strong_heading?(paragraph, sources)

            Finding.new(line: paragraph[:last], rule: MISSING_PERIOD_RULE,
                        label: '文末に句点「。」がありません')
          end
        end

        # 段落が小見出し（`**…**` 1 行）か。強調を外す前の原文で見る。
        def strong_heading?(paragraph, sources)
          paragraph[:start] == paragraph[:last] &&
            STRONG_HEADING.match?(sources[paragraph[:last]].to_s)
        end
        private_class_method :strong_heading?

        # 1 行から、上限を超える補足を [文, 和文の長さ] で拾う
        def long_parentheticals(line, limit)
          line.to_enum(:scan, PARENTHETICAL).flat_map do
            ::Regexp.last_match(1).split('。').filter_map do |part|
              length = japanese_length(part)
              [part, length] if length > limit
            end
          end
        end
        private_class_method :long_parentheticals

        # 和文としての長さ。コードと欧文は読む負担が字数に比例しないので数えない。
        def japanese_length(part)
          part.gsub(/#{Masking::CODE_SPAN_PLACEHOLDER_PREFIX}\d+__/, '').gsub(LATIN_RUN, '').length
        end
        private_class_method :japanese_length

        # --- かっこの隣の空白 -------------------------------------------------

        OPENING_BRACKETS = %w[（ ［ 「 『].freeze
        CLOSING_BRACKETS = %w[） ］ 」 』].freeze

        # 空白の反対側にあれば、その空白は区切りのために置いたものと見なす記号。
        # `**DTP ソフト**（InDesign） — 紙面を…` のダッシュ、`` `@prop-list` → 「表 4-2」 `` の矢印、
        # `**五十音順ソート** - 「あ行」` のハイフン、`**文体の統一**: 「です・ます調」` のコロン、
        # `高品質 / 標準（既定） / 軽量` の並列のスラッシュ（`EPUB / Kindle` と同じ書き方）。
        # `|` は表のセル境界で、textlint（セルの文字列を切り出して見る）も指摘しなかった。
        BRACKET_SPACE_SEPARATORS = %w[— – → - : ： / |].freeze

        # 強調記法の記号。空白の手前にあれば閉じ（`**参照:** 「…」`）なので許容する。
        # 空白の後ろにあるのは開き（`「引用」 **太字**`）で、こちらは許容しない。
        EMPHASIS_MARKS = %w[* _ ~].freeze

        # 行頭のブロック記法（字下げ・箇条書き・番号・引用・見出し・定義リスト）。
        # ここに含まれる空白は記法の一部で、かっこの隣でも指摘しない（`- 「あ行」`）。
        BLOCK_PREFIX = /\A[ \t　]*(?:(?:[-*+>:]|\d{1,9}[.)]|\#{1,6})[ \t　]+)*/

        BRACKET_SPACE = /[ \t　]+/

        # インラインコードを埋める文字。私用領域の 1 文字なので原稿には現れず、
        # コードの長さぶん並べるので、行の中の位置は元の行とずれない。
        BRACKET_CODE_MARK = 0xE001.chr(Encoding::UTF_8)

        # かっこの隣に入った空白の指摘。
        #
        # textlint の `ja-no-space-around-parentheses` は「かっこの隣に空白があれば指摘」
        # としか言えず、本書では 18 件すべてが区切りのために置いた空白だった（`） — ` `**参照:** 「`
        # など）。しかも textlint は自動修正を持つので、`vs lint --fix` がその空白を削って
        # `（Word・Pages）— 画面で` のように詰めてしまう。そこで本ルールで置き換え、
        # 空白の反対側が区切り記号・強調の閉じ・行末のときは黙る（切り替えは lint.rb の
        # SUPERSEDED_TEXTLINT_RULES）。
        #
        # 半角の `[` `]` は見ない。Markdown ではリンク・脚注・タスクリスト・索引語の記法で、
        # 前後に空白が入るのが正しい書き方である。
        #
        # 空白を詰めるか区切り記号を足すかは文脈で決まるので、`--fix` しない。
        def bracket_space_findings(text)
          prose_lines(text).flat_map do |lineno, line|
            original = line.chomp
            masked   = original.gsub(Masking::INLINE_CODE_SPAN) { BRACKET_CODE_MARK * it.length }
            bracket_spaces(masked).map do |start, finish|
              before = original[0...start][/\S{1,8}\z/]
              after  = original[finish..][/\A\S{1,8}/]
              Finding.new(line: lineno, rule: BRACKET_SPACE_RULE,
                          label: "#{before}#{original[start...finish]}#{after} => #{before}#{after}" \
                                 '（かっこの隣の空白）')
            end
          end
        end

        # 1 行から、指摘すべき空白を [開始, 終了] で拾う
        def bracket_spaces(line)
          prefix_end = line[BLOCK_PREFIX].length
          spaces = []
          line.to_enum(:scan, BRACKET_SPACE).each do
            matched = ::Regexp.last_match
            next if matched.begin(0) < prefix_end

            left  = matched.begin(0).positive? ? line[matched.begin(0) - 1] : nil
            right = line[matched.end(0)]
            spaces << [matched.begin(0), matched.end(0)] if bracket_space?(left, right)
          end
          spaces
        end
        private_class_method :bracket_spaces

        # 空白の左右の文字から、指摘すべきかを決める。行末の空白（改行の手前）は見ない。
        def bracket_space?(left, right)
          return false if right.nil?

          case [OPENING_BRACKETS.include?(left), CLOSING_BRACKETS.include?(right)]
          in [true, true] then false # `「 」` は空白そのものを示している
          in [true, _] | [_, true] then true # かっこの内側
          else
            (OPENING_BRACKETS.include?(right) && !spacing_left?(left)) ||
              (CLOSING_BRACKETS.include?(left) && !BRACKET_SPACE_SEPARATORS.include?(right))
          end
        end
        private_class_method :bracket_space?

        # 開きかっこの手前の空白を許容する左側の文字（区切り記号か強調の閉じ）
        def spacing_left?(left) = BRACKET_SPACE_SEPARATORS.include?(left) || EMPHASIS_MARKS.include?(left)
        private_class_method :spacing_left?

        # --- 数と助数詞「つ」 -------------------------------------------------

        # 漢数字（添字が数）
        KANSUJI = %w[〇 一 二 三 四 五 六 七 八 九].freeze

        # ひらがなで開いた数。4 以上は書かれることがまず無く、`やっつける` `むっつり` の
        # ように別の語へ紛れるので拾わない。`ひとつづき` は「一続き」という別の語。
        WAGO_NUMERALS = { 'ひとつ' => 1, 'ふたつ' => 2, 'みっつ' => 3 }.freeze

        # 数＋「つ」。算用数字（`2つ` `2 つ`）・漢数字（`二つ`）・ひらがな（`ふたつ`）の 3 通り。
        # 直前が数字や小数点のもの（`12つ` `1.5つ`）は数え方の「つ」ではないので除く。
        COUNTER_SUFFIX = /
          (?<![0-9０-９.])(?<arabic>[1-9])[ \t]?つ
          | (?<![一二三四五六七八九十〇])(?<kansuji>[一二三四五六七八九])つ
          | (?<wago>ひとつ(?!づき)|ふたつ|みっつ)
        /x

        # 記号の名前。数の隣にあれば「記号をいくつ書くか」の話なので、算用数字で書く。
        #
        # **記号の意味しか持たない名前だけを載せる。** `ハッシュ`（Ruby の Hash）・`パイプ`
        # （Unix のパイプ）・`ドット`（ドット記法）・`文字`・`記号` は、載せると記号でない
        # 数まで黙らせる——「1 つのハッシュで」を実際に黙らせた（本書 25 章）。
        # 文脈で決まる箇所（「直前の 1 つだけ」が `---` を指すなど）は判定できないので、
        # 著者が `<!-- vs-lint-disable-next-line -->` で黙らせる。
        COUNTER_SYMBOL_NAMES = %w[
          空白 空行 改行 タブ スペース 半角スペース 全角スペース
          バッククォート バックティック ダブルクォート シングルクォート 引用符
          かっこ 括弧 丸かっこ 角かっこ 波かっこ 山かっこ かぎかっこ
          丸括弧 角括弧 波括弧 山括弧 かぎ括弧 ブレース ブラケット
          縦棒 ハイフン アスタリスク アンダースコア アンダーバー チルダ キャレット
          コロン セミコロン スラッシュ バックスラッシュ イコール 等号
          シャープ 感嘆符 疑問符 アットマーク
        ].sort_by { -it.length }.freeze

        # 記号だけを書いたインラインコード（`---` `**`）。記号の名前と同じく扱う。
        # 中身に英数字があるもの（`_index_glossary_review.md`）はファイル名などなので、
        # 「`foo.md` は 4 つのセクション」を記号の個数と取らないよう除く（本書 33 章で実際に誤った）。
        SYMBOL_ONLY_CODE = /\A`+[^\p{Alnum}`]+`+\z/

        # 記号だけのコードを置き換える目印。私用領域の 1 文字なので原稿には現れず、
        # 強調記法の除去（strip_emphasis）にも削られない。
        SYMBOL_CODE_MARK = 0xE000.chr(Encoding::UTF_8)

        COUNTER_SYMBOL = /(?:#{COUNTER_SYMBOL_NAMES.join('|')}|#{SYMBOL_CODE_MARK})/

        # 名前が数の前にある形（`空白 2 つ` `バッククォートを 2 つ`）と、後ろにある形
        # （`3 つのバッククォート` `3 つ以上のハイフン`）
        SYMBOL_BEFORE_COUNT = /#{COUNTER_SYMBOL}[ \t]*[をがは]?[ \t]*\z/
        SYMBOL_AFTER_COUNT  = /\A(?:以上の|以上|の)?[ \t]*#{COUNTER_SYMBOL}/

        # 数と「つ」の表記の指摘。本書の方針（数は漢数字、記号の個数は算用数字）に
        # 合わない書き方を拾う。
        #
        # **--fix しない。** 記号の個数かどうかは名前が隣にあるかで見ているだけで、文の
        # 意味は読んでいない。自動で直すと、判定を外した箇所に「空白二つ」が黙って入る。
        #
        # 文体の選択なので、別の方針（JTF の「1つ」など）を採る著者は `disabled_rules` で切る。
        def kansuji_counter_findings(text)
          prose_lines(text).flat_map do |lineno, line|
            protected_line, spans = Masking.protect_code(line)
            spans.each do |placeholder, code|
              protected_line = protected_line.sub(placeholder, SYMBOL_CODE_MARK) if code.match?(SYMBOL_ONLY_CODE)
            end
            body, = Masking.strip_emphasis(protected_line)
            counter_suffixes(body).filter_map do |found, value, symbol|
              kansuji_counter_finding(lineno, found, value, symbol)
            end
          end
        end

        # 1 行から [書かれた形, 数, 記号の個数か] を拾う
        def counter_suffixes(body)
          hits = []
          body.to_enum(:scan, COUNTER_SUFFIX).each do
            matched = ::Regexp.last_match
            value = counter_value(matched)
            symbol = body[0...matched.begin(0)].match?(SYMBOL_BEFORE_COUNT) ||
                     body[matched.end(0)..].match?(SYMBOL_AFTER_COUNT)
            hits << [matched[0], value, symbol]
          end
          hits
        end
        private_class_method :counter_suffixes

        def counter_value(matched)
          return matched[:arabic].to_i if matched[:arabic]
          return KANSUJI.index(matched[:kansuji]) if matched[:kansuji]

          WAGO_NUMERALS.fetch(matched[:wago])
        end
        private_class_method :counter_value

        # 方針どおりなら nil。記号の個数は算用数字、それ以外は漢数字が正しい形。
        def kansuji_counter_finding(lineno, found, value, symbol)
          arabic = found.match?(/\A[1-9]/)
          if symbol
            return nil if arabic

            Finding.new(line: lineno, rule: KANSUJI_COUNTER_RULE,
                        label: "#{found} => #{value} つ（記号の個数は算用数字で）")
          else
            return nil if found.start_with?(*KANSUJI)

            Finding.new(line: lineno, rule: KANSUJI_COUNTER_RULE,
                        label: "#{found} => #{KANSUJI[value]}つ（数は漢数字で）")
          end
        end
        private_class_method :kansuji_counter_finding

        # --- 康煕部首 --------------------------------------------------------

        # 康煕部首（U+2F00〜U+2FD5）。字形は漢字と見分けがつかないが別の文字で、
        # 検索・索引・読み上げで漢字として扱われない。PDF からコピーした文に紛れ込む。
        KANGXI_RADICAL = /[\u2F00-\u2FD5]/

        # 対応する漢字は NFKC 正規化で得られるが、2 字だけ旧字体（戶・黑）が返る。
        # 日本語の文では新字体が正しいので、そこだけ差し替える。
        KANGXI_JAPANESE_FORMS = { '⼾' => '戸', '⿊' => '黒' }.freeze

        # 康煕部首の指摘。もとは textlint の preset-japanese にあった no-kanji-lookalikes で、
        # そのプリセットを外した（残り 11 ルールは preset-ja-technical-writing と重複していた）
        # ときにこちらへ移した。単体の npm パッケージとして足さなかったのは、`vs upgrade` で
        # 設定だけが先に届くと、未導入のルールを読めずに textlint ごと止まるため。
        def kanji_lookalike_findings(text)
          prose_lines(text).flat_map do |lineno, line|
            protected_line, = Masking.protect_code(line)
            protected_line.scan(KANGXI_RADICAL).uniq.map do |radical|
              Finding.new(line: lineno, rule: KANJI_LOOKALIKE_RULE,
                          label: "#{radical} => #{kangxi_ideograph(radical)}（漢字に見える康煕部首です）")
            end
          end
        end

        # 康煕部首を漢字へ置換したテキストを返す。行数は入力と必ず一致する。
        # 置換は 1 文字を 1 文字へ替えるだけなので、強調記法をまたぐ心配はない。
        def fix_kanji_lookalike(text)
          prose = prose_lines(text).to_h

          text.each_line.with_index(1).map do |line, lineno|
            next line unless prose.key?(lineno)

            protected_line, spans = Masking.protect_code(line)
            Masking.restore_code(protected_line.gsub(KANGXI_RADICAL) { kangxi_ideograph(it) }, spans)
          end.join
        end

        def kangxi_ideograph(radical) = KANGXI_JAPANESE_FORMS.fetch(radical) { radical.unicode_normalize(:nfkc) }
        private_class_method :kangxi_ideograph

        # --- 記法の取り違え（markdown-notation-collision-spec.md §5〜§7）--------

        # 索引語のつもりでない `[g]` の指摘。
        #
        # **すべての `[語]` は叩けない。** 手動マークアップは正しい記法で、本書でも
        # `[五十音順|ごじゅうおんじゅん]` が現役である。事故が起きるのは、著者が
        # 索引語を書いたつもりのない短い綴りに限られるので、そこだけを見る。
        # 参照リンクとタスクリストは IndexMarkup が既に除いている（T-1・T-2）。
        def stray_index_findings(text)
          labels = IndexMarkup.link_labels(Masking.strip_code(text))

          prose_lines(text).flat_map do |lineno, line|
            protected_line, = Masking.protect_code(line)
            stray_terms(protected_line, labels).map do |term|
              Finding.new(line: lineno, rule: STRAY_INDEX_RULE,
                          label: "[#{term}] は索引語として登録されます" \
                                 "（コードなら `[#{term}]` と囲む／索引に載せるなら [#{term}|よみ] と仮名の読みを添える）")
            end
          end
        end

        # 1 行から、索引語として疑わしい短い綴りだけを拾う。
        def stray_terms(line, labels)
          line.to_enum(:scan, IndexMarkup::TERM_PATTERN).filter_map do
            match = ::Regexp.last_match
            term  = match[1]
            next if IndexMarkup.skip_term?(term)
            next if IndexMarkup.other_notation?(match, labels)
            next unless IndexMarkup.short_ascii_term?(term)

            term
          end
        end

        # 4 スペース字下げコードブロックの指摘（非対応・§6）。
        #
        # 報告するのは**ブロックの先頭 1 行だけ**にする。字下げが続くかぎり何行でも
        # 出すと、貼り付けた 30 行のコードに 30 件並んで読めなくなる。
        #
        # リストの続きは指摘しない。CommonMark で字下げコードかどうかを決めるには
        # リストの中にいるかを追う必要があり、行単位の走査では「4 スペース＝コード」と
        # 言い切れない（実測: 本書の 4 字下げ 2 行はどちらも非コードだった）。
        def indented_code_findings(text)
          lines = text.lines

          prose_lines(text).filter_map do |lineno, line|
            next unless line.match?(INDENTED_LINE)
            next if line.match?(/\A[ \t]+(?:[-*+]|\d{1,9}[.)])[ \t]/) # 字下げした箇条書き
            next unless lines[lineno - 2].to_s.strip.empty?             # ブロックの先頭だけ
            next if list_continuation?(lines, lineno)

            Finding.new(line: lineno, rule: INDENTED_CODE_RULE,
                        label: '4 スペースの字下げはコードブロックになりません' \
                               '（コードならバッククォート 3 つのフェンスで囲んでください）')
          end
        end

        # その字下げ行はリストの続きか。空行を挟んだ段落もリスト項目の一部になりうるので、
        # **空行を読み飛ばして**直近の中身のある行を見る。
        def list_continuation?(lines, lineno)
          index = lineno - 2
          index -= 1 while index >= 0 && lines[index].to_s.strip.empty?
          return false if index.negative?

          previous = lines[index].to_s
          previous.match?(LIST_ITEM_HEAD) || previous.match?(INDENTED_LINE)
        end

        # 改ページのつもりが見出しになる `---` / `===` の指摘（§7）。
        #
        # 本書は「`---` は改ページ」と教えているが、直前に文が続いていると
        # CommonMark の規則で Setext 見出しが優先される。`===` なら h1 になり、
        # 章題と同じ階層なので目次と PDF アウトラインまで汚れる。
        def setext_findings(text)
          lines = text.lines

          prose_lines(text).filter_map do |lineno, line|
            next if lineno < 2
            next unless (matched = line.match(SETEXT_UNDERLINE))
            next if lines[lineno - 2].to_s.strip.empty? # 前が空行なら改ページ（正しい書き方）

            level = matched[1].start_with?('=') ? '第 1 レベル' : '第 2 レベル'
            Finding.new(line: lineno, rule: SETEXT_RULE,
                        label: "直前の行に続いているため、改ページではなく#{level}の見出しになります" \
                               '（改ページにするなら前に空行を入れる／見出しにするなら ## を使う）')
          end
        end

        # 二通りに読める対比の指摘。
        # 段落単位で見るのは、段落内改行で折り返した文を 1 文として読むため
        # （本書の原稿は 1 文が複数行にまたがる）。
        def ambiguous_findings(text)
          prose_paragraphs(text).flat_map { findings_in_paragraph(it) }
        end

        # --- 自動修正（--fix） ------------------------------------------------

        # 交ぜ書きを置換したテキストを返す。行数は入力と必ず一致する。
        # 書き込みは呼び出し元（LintRunner#atomic_write）が担う——原稿を掴むのは
        # 1 箇所に留めたい（中断時に半端な原稿を残さないため）。
        # @return [String] 置換後のテキスト（対象が無ければ入力と等しい）
        def fix_mazegaki(text, allowlist = [])
          prose = prose_lines(text).to_h

          text.each_line.with_index(1).map do |line, lineno|
            prose.key?(lineno) ? replace_mazegaki(line, allowlist) : line
          end.join
        end

        # 行の中の交ぜ書きを置換する。
        # 地の文が記法を「解説している」インラインコード（`ろ過` の綴りを説明する行など）を
        # 壊さないよう、コードを退避してから置換する（NotationGuard と同じ流儀）。
        #
        # 除外リストの語は置換もしない。指摘しないと決めた語を直すのは筋が通らないうえ、
        # 「黙っているのに原稿が書き換わる」のは著者にとって最も分かりにくい壊れ方になる。
        def replace_mazegaki(line, allowlist = [])
          protected_line, spans = Masking.protect_code(line)
          plain, map = Masking.strip_emphasis(protected_line)
          replaced = apply_edits(protected_line, map, mazegaki_edits(plain, allowlist))
          Masking.restore_code(replaced, spans)
        end

        # 記法を外した文字列の上で当たった [開始, 終了, 置換後, 見出し] を、
        # 重なりを解いて位置の昇順で返す。長い語を優先する（`障がい者` と `障がい`）。
        def mazegaki_edits(plain, allowlist)
          hits = []
          MAZEGAKI.each do |pattern, expected|
            plain.to_enum(:scan, pattern).each do
              matched = ::Regexp.last_match
              hits << [matched.begin(0), matched.end(0), expected, matched[0]]
            end
          end
          MazegakiScanner.scan(plain).each { |found, expected, start, finish| hits << [start, finish, expected, found] }

          hits.reject { |_s, _e, _x, found| allowed?(found, allowlist) }
              .sort_by { |start, finish, _x, _f| [start, start - finish] }
              .each_with_object([]) do |hit, chosen|
                chosen << hit unless chosen.any? { |kept| hit[0] < kept[1] && kept[0] < hit[1] }
              end
        end

        # 元の行へ置換を当てる。添字がずれないよう後ろから置く。
        #
        # **語の内側に強調記法があるときは置換しない。** `だ**円**` を `楕円` にすると
        # `**` が黙って消える——著者の書いた記法を lint が勝手に落とすのは、
        # 交ぜ書きを直さないより悪い。指摘は出るので、著者が手で直せばよい。
        # 仕様: inline-emphasis-word-split-spec.md §3
        def apply_edits(original, map, edits)
          edits.reverse_each.reduce(original.dup) do |text, (start, finish, expected, _found)|
            from = map[start]
            to   = map[finish - 1]
            next text if from.nil? || to.nil? || to - from != finish - start - 1

            text[0...from] + expected + text[(to + 1)..]
          end
        end

        # --- 表示 -------------------------------------------------------------

        # 指摘をルール・ラベル単位で集約する。
        # ラベル先頭の [ルール ID] は、著者が lint.disabled_rules へ書く名前をそのまま
        # 読み取れるようにするため（textlint 側の表示と揃える）。
        #
        # **並べ替えも行番号の整形もここではしない。** 著者から見れば textlint の指摘と
        # 区別する理由がないので、表示は 1 つの表へ混ぜる（LintRunner#print_prose_report）。
        # 順序が決まるのは両方が揃ってからで、それを決めるのは FindingRows.arrange。
        # @param findings [Array<Finding>]
        # @return [Array<Hash>] { count:, label:, lines: [Integer] }
        def aggregate(findings)
          findings.group_by { [it.rule, it.label] }.map do |(rule, label), items|
            { count: items.size, label: "[#{rule}] #{label}", lines: items.map(&:line) }
          end
        end

        # 対比の指摘は「どう直すか」が自明でないので、直し方を 1 度だけ添える。
        def print_ambiguous_hint(findings_by_file)
          return unless findings_by_file.each_value.any? { |fs| fs.any? { it.rule == AMBIGUOUS_RULE } }

          Common.log_always '💡 対比は文を分けて書きます:「A は X する。一方 B は X しない」'
          Common.log_always ''
        end

        # --- 内部 -------------------------------------------------------------

        # コード領域でない（＝地の文の）行を [行番号, 行] で返す。
        #
        # `<!-- vs-lint-disable -->` 系で抑止された行は落とす。textlint 側はコメントを
        # textlint 記法へ変換して渡している（LintRunner#rewrite_vs_lint_to_textlint）ので、
        # 独自ルールも同じ指示に従わないと、著者から見て「同じコメントが片方にしか効かない」
        # という不可解な振る舞いになる。校正について書いた章は自らの例文が指摘されるため、
        # 抑止の手段は実際に要る。
        def prose_lines(text)
          disabled  = false
          skip_next = false
          lines     = []

          Masking.each_prose_line(text) do |line, lineno|
            case line
            when DISABLE_NEXT_LINE   then skip_next = true
            when DISABLE_RANGE_OPEN  then disabled  = true
            when DISABLE_RANGE_CLOSE then disabled  = false
            else
              lines << [lineno, line] unless disabled || skip_next
              skip_next = false
            end
          end

          lines
        end
        private_class_method :prose_lines

        # 地の文を段落へまとめる。切れ目は空行・コード領域による行番号の飛び・
        # Markdown のブロック開始（箇条書き／表／見出し／引用）の 3 つ。
        # @return [Array<Hash>] { start:, text:, lines: [[段落内オフセット, 行番号], …] }
        def prose_paragraphs(text)
          paragraphs = []
          buffer = nil

          prose_lines(text).each do |lineno, line|
            # **行ごとに強調記法を外してから段落へ積む。** 交ぜ書きと同じ理由で、
            # 比較表現も読者の見る文字列に当てなければ当たらない——
            # `スレッド**と同様**にメモリを共有しない` は `と同様*` になって
            # COMPARISON をすり抜ける。行の中で外すので、段落内の位置と行番号の
            # 対応（paragraph[:lines]）はそのまま保たれる。
            # 仕様: inline-emphasis-word-split-spec.md §4
            body, = Masking.strip_emphasis(line.strip)
            if body.empty? || body.match?(BLOCK_START) || (buffer && lineno != buffer[:last] + 1)
              paragraphs << buffer if buffer
              buffer = nil
            end
            next if body.empty?

            buffer ||= { start: lineno, text: +'', lines: [], last: nil }
            buffer[:lines] << [buffer[:text].length, lineno]
            buffer[:text] << body
            buffer[:last] = lineno
          end

          paragraphs << buffer if buffer
          paragraphs
        end
        private_class_method :prose_paragraphs

        # 段落を文へ分け、比較 → 否定の順で現れる文を指摘にする。
        def findings_in_paragraph(paragraph)
          offset = 0

          paragraph[:text].split(SENTENCE_BREAK).filter_map do |sentence|
            start = offset
            offset += sentence.length
            comparison = ambiguous_comparison(sentence)
            next unless comparison

            Finding.new(line: line_at(paragraph, start), rule: AMBIGUOUS_RULE,
                        label: "「〜#{comparison}…ない」は二通りに読めます")
          end
        end
        private_class_method :findings_in_paragraph

        # 文の中で「比較表現 → 否定」がこの順に現れれば、その比較表現を返す。
        def ambiguous_comparison(sentence)
          found = nil

          sentence.scan(COMPARISON) do
            match = Regexp.last_match
            next unless negative?(sentence[match.end(0)..].to_s)

            found = match[0]
            break
          end

          found
        end
        private_class_method :ambiguous_comparison

        # 否定を含むか。「少ない」のような「ない」で終わる形容詞は先に落とす。
        def negative?(tail) = tail.gsub(NOT_NEGATION, '').match?(NEGATION)
        private_class_method :negative?

        # 段落内オフセットから、それを含む行の番号を引く。
        def line_at(paragraph, offset)
          entry = paragraph[:lines].reverse_each.find { |start, _| start <= offset }
          entry ? entry.last : paragraph[:start]
        end
        private_class_method :line_at
      end
    end
  end
end
