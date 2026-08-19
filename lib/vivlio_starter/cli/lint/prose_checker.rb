# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/lint/prose_checker.rb
# ================================================================
# 責務:
#   textlint のルールでは扱えない 2 種の指摘を、日本語の文へ直接当てる。
#     - mazegaki             交ぜ書き（「だ円」→「楕円」）。1 対 1 の置換なので --fix できる
#     - ambiguous-comparison 二通りに読める対比（「B は A と同じように X しない」）
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
#   preset-japanese の no-dropping-the-ra が既に検出している（textlint 側）。
#
# 依存:
#   - Masking: コード領域の判定（辞書をコード例へ当てないため）
#   - MazegakiDictionary: 交ぜ書きの語（採否の基準と、落とした語の理由もあちら側）
#   - MazegakiScanner: MeCab があるときだけ足す第 2 層（mazegaki-two-tier-spec.md）
# ================================================================

require 'yaml'

require_relative '../common'
require_relative '../masking'
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

        # 表示する出現行番号の最大件数（超過分は … で省略。textlint 側と揃える）
        MAX_SHOWN_LINES = 10

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
        # @return [Array<Finding>]
        def check(path, disabled_rules: [], allowlist: [])
          text  = File.read(path, encoding: 'UTF-8')
          rules = Array(disabled_rules).map(&:to_s)

          findings = []
          findings.concat(mazegaki_findings(text, allowlist)) unless rules.include?(MAZEGAKI_RULE)
          findings.concat(ambiguous_findings(text))           unless rules.include?(AMBIGUOUS_RULE)
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

        # 複数ファイルの指摘を表示する（textlint 側の集約表示と同じ体裁）。
        # @param findings_by_file [Hash] { path => [Finding] }
        # @return [Boolean] 指摘があれば true
        def print_errors(findings_by_file)
          return false if findings_by_file.empty?

          findings_by_file.each do |path, findings|
            Common.log_always "📄 #{path}  (校正)"
            aggregate(findings).each do |row|
              Common.log_always format('  %3d件  %s', row[:count], row[:label])
              Common.log_always format('         行: %s', row[:lines])
            end
            Common.log_always ''
          end

          print_ambiguous_hint(findings_by_file)
          true
        end

        # 指摘をルール・ラベル単位で集約する（出現数の多い順）。
        # ラベル先頭の [ルール ID] は、著者が lint.disabled_rules へ書く名前をそのまま
        # 読み取れるようにするため（textlint 側の表示と揃える）。
        def aggregate(findings)
          findings.group_by { [it.rule, it.label] }.map do |(rule, label), items|
            lines = items.map(&:line).uniq.sort
            shown = lines.first(MAX_SHOWN_LINES).join(', ')
            shown += ', …' if lines.size > MAX_SHOWN_LINES
            { count: items.size, label: "[#{rule}] #{label}", lines: shown }
          end.sort_by { -it[:count] }
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
