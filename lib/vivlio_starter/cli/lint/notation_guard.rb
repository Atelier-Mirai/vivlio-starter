# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/lint/notation_guard.rb
# ================================================================
# 責務:
#   VFM 記法（機械データ）を中和したテキストを返す。vs lint（textlint・
#   スペルチェック）が記法を日本語の文として読んでしまう誤検出を、
#   設定ファイルではなく lint システムの内部で断つ。
#
# なぜ設定ファイルではないのか:
#   従来は config/textlint_allowlist.yml の「VFM 記法」エントリ（正規表現）で
#   抑え込んでいたが、allowlist は本来「この語は正しい日本語として扱え」という
#   語彙辞書であり、記法は語彙ではない。しかも allowlist はマッチした文字列を
#   消すだけで「この行はブロックの中だ」という文脈を持てないため、ブロック全体を
#   1 文と数える sentence-length の誤検出は原理的に消せなかった。記法を知って
#   いるのは lint システム自身なのだから、システム内部でガードする。
#
# なぜ Masking と別モジュールなのか:
#   Masking.each_prose_line は前処理・索引・メトリクスなど 10 箇所以上から
#   「コード領域解釈の唯一の実装」として使われている。記法の知識をそこへ混ぜると
#   lint と無関係な前処理まで意味が変わる（例: showcase ブロック内の画像行を
#   ImagePathNormalizer が見なくなる）。記法の中和は lint 系だけの要求なので、
#   知識はこのモジュールへ集約し、Masking はコード領域の解釈に徹させる。
#
# 不変条件:
#   I1 行数を必ず保存する（指摘の行番号表示がずれると実用に耐えないため）
#   I3 地の文は 1 文字も落とさない（ふりがなの親文字は地の文なので残す）
#   -- コード領域には触れない（textlint はコード前後のスペース等、コードの
#      存在自体を検査する。消すと検査に穴が開く）
#   -- 文書構造を変えない: HTML コメントの開閉 `<!--`/`-->` を巻き込んで消さない。
#      判定に迷う行はガードしない（素のまま渡す＝ガード導入前と同じ扱いが常に安全側）
#
# 仕様: lint-notation-guard-spec.md §3
# ================================================================

require_relative '../masking'
require_relative '../pre_process/markdown_transformer'
require_relative '../pre_process/math_transformer'
require_relative '../pre_process/cross_reference_processor'

module VivlioStarter
  module CLI
    module Lint
      # VFM 記法の中和（lint 系専用）。
      module NotationGuard
        module_function

        # 中身が地の文でないコンテナ名。記法を追加するときはここへ 1 語加えればガードが追従する。
        #
        # `showcase` は機械データ（座標・オプション）を本文として持つ。`output`（実行結果・ログ）と
        # `terminal`（`$ コマンド`）は**機械が出した文字列**で、著者が書いた日本語ではない。
        # 校正の指摘は「著者が直せること」でなければ意味がないが、出力例の句点や表記を著者が
        # 直すわけにはいかない（実測: 本書で 3 件。`:::{.output}` に置いた変換結果の例が
        # `ruby => Ruby`・`"表示を行う"は冗長` と叩かれていた。しかも同じ文字列がすぐ上の
        # フェンスにも書いてあり、そちらは除外されるので、**片方だけ指摘される**状態だった）。
        #
        # 囲みでも `column` / `note` / `tip` などは入れない——普通の文章を書く場所であり、
        # 一律に外すと本物の誤りを見逃す。用途が「機械の出力」に限られるものだけを並べる。
        MACHINE_DATA_CONTAINERS = %w[showcase output terminal].freeze

        # 機械データ・ブロックの開始行（例: `:::{.showcase}`）。
        # ShowcaseTransformer::BLOCK_PATTERN の開始側と揃える（行末に本文が続く
        # `:::{.showcase} foo` は同 PATTERN が消費しない＝ブロックではないため、
        # ガードもブロックとして扱わない）。
        MACHINE_BLOCK_OPEN =
          /\A:::\s*\{\s*\.(?:#{Regexp.union(MACHINE_DATA_CONTAINERS).source})\s*\}[ \t]*\r?\n?\z/

        # 機械データ・ブロックの終了行（例: `:::`）。
        MACHINE_BLOCK_CLOSE = /\A:::[ \t]*\r?\n?\z/

        # コンテナのマーカー行（開始・終了とも）。コロン 3 つ以上＋任意の属性ブレースで
        # **行全体が構成される**ものだけをマーカーとみなす。
        #
        # 「:::" で始まる行」まで広げてはならない: コメントアウトされたコンテナの閉じ
        # `:::-->` を空行化すると HTML コメントの `-->` が消え、コメントが永久に閉じず、
        # その中身（表・数式）を読んだ textlint が暴走する実害があった（94 章で CPU 99%）。
        # マーカーでないものはガードの対象外＝素のまま textlint へ渡す（現状維持が正しい）。
        CONTAINER_MARKER = /\A[ \t]*:{3,}[ \t]*(?:\{[^{}\n]*\})?[ \t]*\r?\n?\z/

        # ふりがな記法 `{親文字|ふりがな}`。
        FURIGANA = /\{([^{}|]*)\|[^{}]*\}/

        # クラス属性記法 `{.classname}`。
        CLASS_ATTRIBUTE = /\{\.[-\w]+\}/

        # 値つきの属性記法 `{width=20%}`（`{.bordered width=20%}` のような併記も含む）。
        # 画像の幅指定などの機械データであって地の文ではない。放っておくと中身の半角記号を
        # 日本語の表記ゆれ規則が全角へ「直し」、`![](logo.webp){width=20%}` が
        # `{width=20％}` になって**幅指定が効かなくなる**（実測: 本書の前書きで 4 件）。
        # ふりがな `{親文字|ふりがな}` と食い違わないよう、`|` を含む波括弧は対象外にする。
        VALUE_ATTRIBUTE = /\{[^{}|\n]*=[^{}|\n]*\}/

        # 相互参照のラベル（`@ruby-sample`・`@pageref:heading-label`）。識別子であって地の文ではない。
        # 放っておくと `@ruby-sample` の `ruby` が「Ruby」へ、`@pageref:javascript-intro` の
        # `javascript` が「JavaScript」へ直され、**参照先が見つからなくなる**（実測）。
        #
        # 綴りは**ビルドの置換器と同じ定義**を使う（数式と同じ流儀）。ここで別に書くと、lint が
        # 守る範囲とビルドが参照として扱う範囲がずれる。`@pageref:` を先に置くのは、汎用の参照が
        # コロンの手前までしか見ないため（ReferenceReplacer と同じ順序）。
        LABEL_REFERENCE = Regexp.union(
          PreProcessCommands::CrossReferenceProcessor::ReferenceReplacer::PAGEREF_PATTERN,
          PreProcessCommands::CrossReferenceProcessor::ReferenceReplacer::REFERENCE_PATTERN
        )

        # 解析パスでラベルの代わりに置く語。消さずに形の同じ語へ置き換える理由は neutralize_inline に
        LABEL_STAND_IN = '@label'

        # 記法を中和したテキストを返す。行数は入力と必ず一致する（I1）。
        # @param text [String] 原稿の内容
        # @return [String] 記法を中和した内容
        # 数式の退避に使う目印。`--fix` に触られず、textlint の指摘も生まないことを実測で選んだ
        # （インラインコード化は `spaceAroundCode` を誘発し、`X` のような 1 文字は
        # 全角と半角の間のスペース規則に触れる）。
        MATH_PLACEHOLDER = 'VSMATH'

        # 数式の綴りは**変換器と同じ定義**を使う。ここで別に書くと、lint が守る範囲と
        # ビルドが数式として扱う範囲がずれる。
        MATH_PATTERNS = [
          PreProcessCommands::MathTransformer::DISPLAY_DOLLAR,
          PreProcessCommands::MathTransformer::DISPLAY_BRACKET,
          PreProcessCommands::MathTransformer::INLINE_DOLLAR,
          PreProcessCommands::MathTransformer::INLINE_PAREN
        ].freeze

        # 数式を目印へ退避する。**lint は数式を日本語の文として読むべきではない。**
        #
        # 放置すると、数式の中の半角括弧が prh に「全角にせよ」と指摘され、`--fix` が
        # 当たれば `$(1/2)πr³$` が `$（1/2）πr³$` になって**数式が壊れる**（実測）。
        # コードスパンは textlint が Code ノードとして飛ばすのに、数式は素の文として
        # 読まれるための穴で、素の表記を数式として組む機能が入って表面化した。
        #
        # 行数は保存する（I1）——複数行のディスプレイ数式は、落とした改行を目印の後ろへ足す。
        # @return [Array(String, Hash)] 退避後テキストと { 目印 => 原文 }
        def mask_math(text)
          protected_text, code = Masking.protect_code(text)
          spans = {}
          masked = MATH_PATTERNS.reduce(protected_text) do |acc, pattern|
            acc.gsub(pattern) do
              original = ::Regexp.last_match(0)
              # **桁は固定幅にする。** `VSMATH1` は `VSMATH10` の頭に一致してしまい、
              # 10 個以上の数式がある章で目印が食い違って残骸が出る（実測: 本書 92 章）。
              key = format("%s%04d", MATH_PLACEHOLDER, spans.size)
              spans[key] = original
              "#{key}#{"\n" * original.count("\n")}"
            end
          end
          [Masking.restore_code(masked, code), spans]
        end

        # 退避した記法を戻す（目印の作り方が同じなので、数式・属性の区別なく戻せる）。
        #
        # **退避した逆の順に剥がす。** 退避は重なる——数式を目印にしたあとで、その行ごと
        # 出力例の囲みや `vs-lint-disable-next-line` の行として退避する。退避した順に戻すと、
        # 内側の数式の目印は外側の退避に隠れていて空振りし、外側を戻した時点で原稿に
        # 目印が残る（実測: 守る行の「面積は $\pi r^2$ です」が「面積は VSMATH0000 です」に
        # なって書き戻された）。spans は退避した順に積まれているので、末尾から戻せばよい。
        def restore_masked(text, spans)
          spans.to_a.reverse.reduce(text) do |acc, (key, original)|
            acc.sub(/#{Regexp.escape(key)}\n{0,#{original.count("\n")}}/) { original }
          end
        end

        # 属性の退避に使う目印。数式（VSMATH）と同じ作りにする。
        ATTRIBUTE_PLACEHOLDER = 'VSATTR'

        # 指摘を抑止するコメント。**短い形が正典**で、`vs-lint-*` は後方互換のために残す。
        #
        # いちばん書く「次の行だけ」をいちばん短い形にした（本書の実績で 24 回に対し
        # 範囲指定は 7 回）。区間の指定は Prettier と同じ `-start` / `-end` で揃える——
        # `disable` / `enable` は状態の切り替えに読め、閉じ忘れても名前が違和感を残さない。
        #
        # **行全体がマーカーのときだけ効かせる。** 部分一致で見ていた頃は、記法を説明する
        # 文の中の `` `<!-- vs-lint-disable -->` ``（インラインコードの例示）を本物と
        # 取り違え、31 章の 201 行から先で独自ルールが黙っていた（実測）。
        SUPPRESS_NEXT_LINE = /\A\s*<!--\s*(?:no-lint|vs-lint-disable-next-line)\s*-->\s*\R?\z/
        SUPPRESS_START     = /\A\s*<!--\s*(?:no-lint-start|vs-lint-disable)\s*-->\s*\R?\z/
        SUPPRESS_END       = /\A\s*<!--\s*(?:no-lint-end|vs-lint-enable)\s*-->\s*\R?\z/

        # textlint へ渡す間だけ使う変換表（著者の記法 => textlint ネイティブ記法）。
        # 多対一の変換なので、書き戻すときは文字列からは戻せない——原稿の該当行を
        # 行番号で控えておき、そちらから戻す（LintRunner#restore_marker_lines）。
        SUPPRESS_TO_TEXTLINT = {
          SUPPRESS_NEXT_LINE => '<!-- textlint-disable-next-line -->',
          SUPPRESS_START     => '<!-- textlint-disable -->',
          SUPPRESS_END       => '<!-- textlint-enable -->'
        }.freeze

        # textlint ネイティブ記法のマーカー行（書き戻しで元の綴りへ戻す目印）
        TEXTLINT_MARKER_LINE = /\A\s*<!--\s*textlint-(?:disable-next-line|disable|enable)\s*-->\s*\R?\z/

        # 行全体が抑止コメントか
        def suppression_marker?(line)
          SUPPRESS_NEXT_LINE.match?(line) || SUPPRESS_START.match?(line) || SUPPRESS_END.match?(line)
        end

        # `<!-- vs-lint-disable-next-line -->` が守る行の退避に使う目印
        # （退避と復元は LintRunner#mask_hushed_lines! が行う。restore_masked で戻せるよう、
        # 目印の作り方だけをここで揃えている）。
        HUSHED_PLACEHOLDER = 'VSHUSH'

        # 出力例の囲み（G1）の行の退避に使う目印
        MACHINE_PLACEHOLDER = 'VSMACH'

        # ふりがな（G3）と相互参照のラベルの退避に使う目印
        FURIGANA_PLACEHOLDER = 'VSRUBY'
        LABEL_PLACEHOLDER    = 'VSLABL'

        # 修正パスで守る記法をまとめて退避する。`--fix` は textlint に原稿を直接
        # 直させるので、**解析パスの中和（strip_notation）は効かない**——守りたいものは
        # ここで目印へ逃がすしかない。守る対象は「地の文ではないのに素の文として
        # 読まれるもの」＝数式、値つきの属性記法、ふりがな、相互参照のラベル、出力例の囲み（G1）。
        #
        # **出力例の囲みを守らないと、見えない指摘が当たる。** 解析パスは G1 を中和するので
        # 指摘は表示に出ないが、`--fix` は textlint の修正をそのまま当てる（実測:
        # `:::{.output}` の中の `@ruby-sample` が `@Ruby-sample` にされ、相互参照の
        # ラベルが壊れた）。出力例は実物の出力と一字一句合っていなければならない。
        #
        # **ふりがなは記法ごと守る。** 解析パスは親文字を地の文として残すので（I3）、
        # 「沢山 => たくさん」のような指摘は表示に出る。だが修正を記法の内側へ当てると
        # `{沢山|たくさん}` が `{たくさん|たくさん}` になる（実測）。ふりがなを振った時点で
        # 著者は漢字を選んでいるので、直すなら著者が記法ごと書き換えるしかない。
        #
        # spans は退避した順に積む（restore_masked が逆順に剥がす前提）。
        # @return [Array(String, Hash)] 退避後テキストと { 目印 => 原文 }
        def mask_for_fix(text)
          masked, math = mask_math(text)
          protected_text, code = Masking.protect_code(masked)
          inline = {}
          stash = lambda do |prefix|
            original = ::Regexp.last_match(0)
            key = format('%s%04d', prefix, inline.size)
            inline[key] = original
            key
          end
          replaced = protected_text
                     .gsub(VALUE_ATTRIBUTE) { stash.call(ATTRIBUTE_PLACEHOLDER) }
                     .gsub(FURIGANA)        { stash.call(FURIGANA_PLACEHOLDER) }
                     .gsub(LABEL_REFERENCE) { stash.call(LABEL_PLACEHOLDER) }
          guarded, machine = mask_machine_blocks(Masking.restore_code(replaced, code), text)
          [guarded, math.merge(inline).merge(machine)]
        end

        # 出力例の囲み（G1）の中にある地の文の行番号。
        #
        # 解析パス（strip_notation）・修正パス（mask_for_fix）・独自校正（ProseChecker の
        # 自動修正を持つ規則）が同じ答えを使うために公開している。判定には数式を落とした
        # 原文を使う——数式の退避は改行を保つので、行番号は原文と揃っている。
        # @return [Set<Integer>]
        def machine_data_lines(text)
          layout = blank_math(text)
          machine_block_lines(layout, prose_lines(layout))
        end

        # 出力例の囲み（G1）の地の文の行を、行ごと目印へ退避する。
        #
        # 行番号は退避前の原文（original）で決める。囲みの中のコードフェンスは退避しない
        # （prose_lines に入らない）。フェンスの行まで目印にすると、textlint がコードブロックと
        # 認識できず中身を地の文として直しにかかる。
        def mask_machine_blocks(text, original)
          targets = machine_data_lines(original)
          return [text, {}] if targets.empty?

          spans = {}
          lines = text.each_line.with_index(1).map do |line, lineno|
            next line unless targets.include?(lineno)

            key = format('%s%04d', MACHINE_PLACEHOLDER, spans.size)
            spans[key] = line
            "#{key}#{line[/\R\z/]}"
          end
          [lines.join, spans]
        end
        private_class_method :mask_machine_blocks

        # 解析パス用: 数式を**目印を残さず**落とす。
        #
        # mask_math の目印（VSMATH0）をそのまま残すと、**スペルチェックが未知語として拾う**
        # ——`Tokenizer.tokenize` も記法判定を一本化するために strip_notation を通るため
        # （実測: `VSMATH => smith` が本書 21 章で 5 件）。解析パスは復元しないので、
        # 目印を置く必要がない。行数は mask_math が足した改行で保たれる。
        def blank_math(text)
          masked, spans = mask_math(text)
          spans.keys.reduce(masked) { |acc, key| acc.sub(key, '') }
        end

        def strip_notation(text)
          text = blank_math(text)
          prose   = prose_lines(text)
          machine = machine_block_lines(text, prose)

          text.each_line.with_index(1).map do |line, lineno|
            if !prose.include?(lineno)          then line          # コード領域は不変
            elsif machine.include?(lineno)      then blank(line)   # G1 機械データ・ブロック
            elsif line.match?(CONTAINER_MARKER) then blank(line)   # G2 コンテナのマーカー行
            else neutralize_inline(delist_fancy_marker(line))      # G6 fancy list → G3 ふりがな → G4 クラス属性
            end
          end.join
        end

        # コード領域でない（＝地の文の）行番号の集合。判定は Masking へ委ねる。
        def prose_lines(text)
          prose = Set.new
          Masking.each_prose_line(text) { |_line, lineno| prose << lineno }
          prose
        end
        private_class_method :prose_lines

        # 機械データ・ブロックに属する行番号の集合（開始行・内容行・終了行を含む）。
        #
        # 終了行が無いままファイル末尾に達したブロックは「無かったもの」として扱う。
        # ShowcaseTransformer::BLOCK_PATTERN は閉じが無ければ一致せず、その中身は
        # 原稿にそのまま残って本文として組まれる。ガードだけが先に消すと、実在する
        # 文が textlint の目から消えて検査に穴が開く（未終了フェンスを退避しない
        # Masking の方針とも揃う）。
        def machine_block_lines(text, prose)
          lines   = Set.new
          pending = nil

          text.each_line.with_index(1) do |line, lineno|
            next unless prose.include?(lineno)

            if pending.nil?
              pending = [lineno] if line.match?(MACHINE_BLOCK_OPEN)
            else
              pending << lineno
              if line.match?(MACHINE_BLOCK_CLOSE)
                lines.merge(pending)
                pending = nil
              end
            end
          end

          lines
        end
        private_class_method :machine_block_lines

        # fancy list のマーカー（`(1)` `a.` `(iv)` など）を、標準リストの `-` へ読み替える。
        #
        # textlint の Markdown パーサは Pandoc 由来のこの記法を知らないため、**リストが
        # 段落として読まれていた**。すると箇条書きのために外してある検査が素通りし、
        # `ja-no-mixed-period` が項目の末尾に句点を要求する（実測: 本書 21 章で 2 件。
        # 同ルールは 3.0.2 で `ListItem` を最初から除外しており、標準の `-` や `1.` なら黙る）。
        # 文体の混在を見る `no-mix-dearu-desumasu` も、箇条書き用の判定器へ回らない。
        #
        # マーカーの綴りは**前処理の `parse_list_marker` が正典**で、ここで別に書かない
        # ——lint が見る範囲とビルドがリストとして組む範囲がずれるため（数式と同じ流儀）。
        # 読み替えるのは fancy マーカーだけ（標準のマーカーは textlint が解釈できる）で、
        # 大文字＋ピリオドに空白 1 つの `B. Russell は…` は前処理もリストにしないので素のまま渡す。
        # 本文は 1 文字も変えない（I3）。行番号も動かない（I1）。
        def delist_fancy_marker(line)
          transformer = PreProcessCommands::MarkdownTransformer
          marker = transformer.parse_list_marker(line)
          return line unless marker && transformer.fancy_marker?(marker) && transformer.acceptable_list_start?(marker)

          "#{' ' * marker.indent}- #{marker.body}#{line[/\R\z/]}"
        end
        private_class_method :delist_fancy_marker

        # 行内の記法を中和する（G3 → G4 → G5 → ラベル）。
        # 地の文が記法を「解説している」インラインコード（例: `{.aki}` の書き方を
        # 説明する行）を壊さないよう、コードを退避してから置換する。
        #
        # ラベルは識別子なので中身を見せない。見せると `@ruby-sample` が「ruby => Ruby」と
        # 指摘され、著者が直せば参照が壊れる。修正パスは mask_for_fix が同じ定義で守るので、
        # 表示と修正は食い違わない。
        #
        # **消さずに、形の同じ無害な語へ置き換える。** 消すと周りの空白の形が変わり、原稿に
        # 無い指摘が生まれる（実測: `（@auto / @omakase）` が `（ /  ）` になり、上流の
        # 「全角かっこの前の空白を消せ」に当たった）。`@` で始まる半角の 1 語という形を保てば、
        # 空白やかっこの規則から見た姿は原稿と同じになる。`label` はどの辞書にも当たらない。
        def neutralize_inline(line)
          protected_line, spans = Masking.protect_code(line)
          neutralized = protected_line
                        .gsub(FURIGANA) { ::Regexp.last_match(1) } # 親文字は地の文なので残す（I3）
                        .gsub(CLASS_ATTRIBUTE, '')
                        .gsub(VALUE_ATTRIBUTE, '')
                        .gsub(LABEL_REFERENCE, LABEL_STAND_IN)
          Masking.restore_code(neutralized, spans)
        end
        private_class_method :neutralize_inline

        # 行の中身を落として改行だけ残す（行数保存 = I1）。
        # 末尾に改行が無い最終行は空文字になり、行数も末尾の形状も変わらない。
        def blank(line) = line.end_with?("\n") ? "\n" : ''
        private_class_method :blank
      end
    end
  end
end
