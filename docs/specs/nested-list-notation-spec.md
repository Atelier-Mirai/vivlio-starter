# 箇条書き拡張（fancy list / 複合番号）仕様書

> 作成日: 2026-07-12
> ステータス: **実装待ち**（`nested-list-notation-ideas.md` からの昇格・実装は Opus 4.8 想定）
> 対象: ①Pandoc `fancy_lists` 互換のマーカー種別（`A.` / `(a)` / `i.` 等）、②`:::{.outline-list}` による複合番号（1.1/1.2）、③Kindle 実体マーカー注入フォールバック
> 決定事項（2026-07-12 ユーザー確認済み）:
> - **vivlio-starter 独自記法は作らない**。マーカー種別は Pandoc `fancy_lists` の記法をそのまま踏襲し、方言で書けないもの（複合番号）だけ既存の `:::{.class}` コンテナに乗せる。新しい sigil（`@` 等）は導入しない
> - ネストした番号リストの**デフォルトは独立採番**（各階層が 1 から数え直す）。Pandoc / LaTeX / HTML と同じ、最も驚きの少ない挙動
> - 複合番号（1.1/1.2）が欲しい著者だけ `:::{.outline-list}` で明示的に囲む
> - 階層ごとに違うマーカー（`1.` の子に `(a)`）は fancy_lists 方式の副産物として自動解決（追加設計なし）
> - Kindle は実体マーカー注入フォールバック必須（§6。`::before` ❌ は実測済み）
> - **番号なし箇条書き（ul）のレベル別マーカーは和文組版寄りの「● ○ ・」をデフォルトとして CSS で明示**（記法なし・著者はネストして書くだけ）。`-`/`*`/`+` のマーカー文字への意味付けはしない（§11）
> 関連: `docs/specs/nested-list-notation-ideas.md`（検討経緯）, `docs/specs/kindle-css-compatibility-notes.md`（KFX 制約の実測記録）, `docs/archives/post-replace-list-retirement-spec.md`（`:::` div 化の現行実装）, `lib/vivlio_starter/cli/pre_process/markdown_transformer.rb`（定義リスト＝実装前例）, `lib/vivlio_starter/cli/build/epub_builder.rb`（ADMONITION_LABELS＝注入前例）

## 0. 背景・目的

現状の箇条書きは CommonMark（VFM）標準のまま。著者が `A. B. C.` / `(a) (b)` / `i. ii.` のようなマーカーや、`1 / 1.1 / 1.2` の複合番号を使う手段がない。Pandoc 既知の記法を取り入れ、書籍組版で定番のリスト表現を「著者がそう書けばそう見える」形で提供する。

## 1. 現状調査結果（2026-07-12 時点）

実装者が前提にすべき現行アーキテクチャ:

1. **VFM/CommonMark の挙動**: `A. foo` `(a) foo` は行頭にあってもリストにならず**ただの段落**になる。`1.` と `1)` のみが順序リストマーカー。よってマーカー種別は**前処理（VFM に渡す前）での変換が必須**。
2. **前処理パイプライン**: `MarkdownPreprocessor#run`（`markdown_preprocessor.rb:74`）が変換ステップを順次実行。コード保護は `MarkdownUtils.extract_code_spans` / `code_line_numbers`（Masking 一元化済み）。
3. **実装前例＝定義リスト**: `MarkdownTransformer.convert_definition_lists`（`markdown_transformer.rb:259`）が「行スキャンでブロック検出 → Kramdown（`MarkdownUtils.render_markdown_to_html`）で HTML 化 → 生成 HTML にクラスをパッチ → 生 HTML としてインライン展開」する方式を確立している。fancy list は**この方式を踏襲**する（§4）。
4. **`:::{.class}` コンテナ**: VFM は `:::` を解さない。**後処理の `ReplacementRules::CONTAINER_RULES`** が `<p>:::{.class}</p>` → `<div class="class">` / `:::` → `</div>` へ置換する（post-replace-list-retirement-spec §1.2）。つまり `:::{.outline-list}` は**新規 Ruby コード不要**で `div.outline-list` になる。
5. **現行 CSS**: `stylesheets/chapter-common.css:208-218` に ul/ol のマージン・太字指定のみ。マーカー種別・カウンタ CSS は皆無。
6. **Kindle(KFX) 制約**（`kindle-css-compatibility-notes.md` §2・**実測済み**）: `::before`/`::after` ❌（ルールごと破棄）、`var()` ❌、`:is()` ❌（ルールごと破棄）。➜ 括弧付きマーカー・複合番号は Kindle で**確実に不可視**になるため、実体注入フォールバックが必須（§6）。`<ol type="A">` 属性の KFX 挙動は未実測のため、安全側で**全様式を注入で統一**する。

## 2. 記法仕様①: fancy list（Pandoc `fancy_lists` 互換サブセット）

### 2.1 マーカー一覧

「最初の項目のマーカー表記でそのリスト全体の様式が決まる」（Pandoc と同じ）。区切りは `.`（ピリオド）/ `)`（片括弧）/ `(x)`（両括弧）の 3 種。

| 様式 \ 区切り | `X.` | `X)` | `(X)` |
|---|---|---|---|
| 数字 `1` | 標準（対象外） | CommonMark ネイティブ（対象外） | ✅ `vs-list-decimal-paren2` |
| 小英字 `a` | ✅ `vs-list-lower-alpha` | ✅ `vs-list-lower-alpha-paren` | ✅ `vs-list-lower-alpha-paren2` |
| 大英字 `A` | ✅ `vs-list-upper-alpha` | ✅ `vs-list-upper-alpha-paren` | ✅ `vs-list-upper-alpha-paren2` |
| 小ローマ `i` | ✅ `vs-list-lower-roman` | ✅ `vs-list-lower-roman-paren` | ✅ `vs-list-lower-roman-paren2` |
| 大ローマ `I` | ✅ `vs-list-upper-roman` | ✅ `vs-list-upper-roman-paren` | ✅ `vs-list-upper-roman-paren2` |

✅＝前処理で変換する fancy マーカー（計 13 種）。セルの値は出力 `<ol>` に付与するクラス名（§3）。

### 2.2 判定規則（Pandoc 互換）

- **様式分類**: マーカー中身のトークンを次の順で分類する。
  1. `/\A\d{1,9}\z/` → 数字（両括弧のみ fancy）
  2. `/\A[ivxlcdm]+\z/` → 小ローマ数字（**単文字 `i.` `v.` `x.` 等もローマ数字優先**＝Pandoc 準拠。「c から始まる英字リスト」は書けない制約をドキュメントに明記）
  3. `/\A[IVXLCDM]+\z/` → 大ローマ数字
  4. `/\A[a-z]\z/` → 小英字（1 文字のみ。`aa.` 等は対象外＝リストにしない）
  5. `/\A[A-Z]\z/` → 大英字
- **大文字＋ピリオドの 2 スペース規則**（誤爆防止・Pandoc 準拠）: 様式が大英字/大ローマかつ区切りがピリオドの場合、**リスト開始行ではマーカー後に空白 2 つ以上**を要求する。`B. Russell は…`（1 スペース）は地の文のまま。2 項目目以降（リスト文脈確立後）は 1 スペースで可。
- **開始値**: 先頭マーカーの値が開始番号（`C.` → 3 から、`(iv)` → 4 から）。ローマ数字は値をパースする。
- **様式はリスト先頭項目で確定**: 同一レベル途中での様式変更は v1 では非サポート。検出したら `Common.log_warn` で**出現箇所＋before→after の修正例を添えて**警告し（[[warning-messages-actionable]] の流儀）、先頭様式で続行する。
- **エスケープ**: 行頭マーカーを `\` でエスケープした場合（`\(1) 地の文…`）は変換せず、`\` を除去して地の文にする。
- **誤爆の既知リスク**: `(1) その理由は…` のような段落書き出しはリスト化される（Pandoc も同じ挙動）。回避はエスケープ。ドキュメントに明記する。
- **コード保護**: フェンス/インラインコード内は `code_line_numbers` で除外（`convert_definition_lists` と同一の作法）。

### 2.3 ネストと「階層ごとに違うマーカー」

```
1. 概要
   (a) 選択肢イ
   (b) 選択肢ロ
2. インストール方法
```

ネストされた子リストにも同じ判定を適用する（子の先頭マーカー `(a)` がそのレベルの様式を決める）。番号リストのネストは**デフォルト独立採番**（各レベルが自分の開始値から数える）。これは追加実装ではなく fancy_lists 判定をレベル別に適用した自然な帰結。

## 3. 記法仕様②: 複合番号 `:::{.outline-list}`

```
:::{.outline-list}
1. 概要
   1. この機能について
   2. インストール方法
2. 使い方
   1. 基本
:::
```

表示: `1. / 1.1 / 1.2 / 2. / 2.1`（JIS 的アウトライン番号）。

- 著者は**標準の番号リストをそのまま**書き、`:::{.outline-list}` で囲むだけ。中身は VFM が通常どおり変換する（fancy 変換は不要＝`vs-fancy-list` を含むブロックは outline-list 内に置けない。併用は v1 非サポートとしてドキュメントに明記）。
- div 化は既存 `CONTAINER_RULES` が担うため **Ruby 実装ゼロ**。実装は CSS（§5.2）と Kindle 注入（§6）のみ。
- `ul` が混在した場合、複合番号は `ol` にのみ適用（`ul` は通常の disc 等のまま）。
- クラス名は `outline-list`（`def-list` / `long-table` と同じ「役割-名詞」系の命名）。

## 4. 実装設計①: 前処理（fancy list 変換）

### 4.1 変換器 `MarkdownTransformer.convert_fancy_lists`

`convert_definition_lists`（`markdown_transformer.rb:259`）と同型のモジュール関数として実装する。

**アルゴリズム**:

1. 行スキャンで**リストブロック**（標準/fancy マーカー行・字下げ継続行・ルーズ形式の内部空行の連続）を抽出する。`code_line_numbers` の行はスキップ。
2. ブロック内に fancy マーカー（§2.1 の ✅）が **1 つも無ければ無変換**で素通し（標準リストは VFM に委ね、ルビ・脚注等の VFM 機能をフルに維持する）。
3. fancy を含むブロックは全体を変換対象にする:
   - インデント幅スタックでレベルを追跡し、**レベルごとに**先頭マーカーから様式・区切り・開始値を確定する（標準 `1.`/`1)` レベルは様式 `nil`）。
   - 全マーカー行を連番の `1.` `2.` … に書き換える（開始値はここでは反映しない。§4.2 のパッチで `start` 属性として付与し、Kramdown の採番挙動へ依存しない）。
   - ネストのインデントを **4 スペース/レベルに正規化**する（Kramdown のネスト認識を確実にするため）。
   - 各非空行に `hard_break_line`（`markdown_transformer.rb:348`）を適用し、本書全体の hardLineBreaks: true と改行挙動を揃える（定義リストと同じ措置）。
4. 正規化済みブロックを `MarkdownUtils.render_markdown_to_html` で HTML 化する。
5. **`<ol>` パッチ**: 手順 3 でリスト開始イベント順に `[様式 or nil, 開始値]` のキューを記録しておき、生成 HTML の `<ol`（出現順＝ソース順）へ shift しながら属性を注入する。`<ul` は素通し。
   - 様式 `nil`（標準）→ 無加工。
   - ピリオド/片括弧様式 → `class="vs-fancy-list vs-list-…"` ＋ `type`（`a`/`A`/`i`/`I`）＋ `start`（開始値 ≠ 1 のとき）。
   - 括弧付き様式（`-paren` / `-paren2`）→ 上記に加えて `style="counter-reset: vs-fancy N"`（N = 開始値 − 1）を**常に**付与する（CSS カウンタの開始値を `start` 属性から読む標準手段が無いため。`counter-reset` のインライン指定なら Vivliostyle でも確実）。
   - キュー残数と `<ol` 出現数が食い違ったら `log_warn` して無加工で返す（防御・ビルドは止めない）。
6. 変換結果（生 HTML ブロック）＋末尾 `"\n\n"` を元の位置に埋め戻す。

### 4.2 パイプラインへの組み込み

`MarkdownPreprocessor` に `transform_fancy_lists!` を追加し、**`transform_definition_lists!` の直前**に置く（`markdown_preprocessor.rb:92`）。理由: `A. 用語` 行が定義リストの用語行と両義になるため、fancy を先に確定させる（1 スペースの `A. 用語` は 2 スペース規則により fancy にならず、従来どおり定義リストへ流れる）。ログは他ステップに合わせ `Common.log_success('fancy list を変換しました')`（変化があったときのみ）。

## 5. 実装設計②: CSS（PDF・クリーン EPUB）

`stylesheets/chapter-common.css` の「リスト」セクション（208 行付近）へ追記する。**root を編集し `ruby copy_to_scaffold.rb` で同期**（[[scaffold-sync-workflow]]・`lib/project_scaffold/` 直編集禁止）。

### 5.1 fancy list

```css
/* fancy list（Pandoc fancy_lists 互換・前処理が ol へクラス付与） */
ol.vs-list-lower-alpha { list-style-type: lower-alpha; }
ol.vs-list-upper-alpha { list-style-type: upper-alpha; }
ol.vs-list-lower-roman { list-style-type: lower-roman; }
ol.vs-list-upper-roman { list-style-type: upper-roman; }

/* 括弧付きマーカーは list-style-type で表現できないため自前描画。
   カウンタ開始値は前処理が ol の style="counter-reset: vs-fancy N" で与える */
ol[class*="-paren"] { list-style: none; }
ol[class*="-paren"] > li { counter-increment: vs-fancy; }
ol.vs-list-lower-alpha-paren  > li::before { content: counter(vs-fancy, lower-alpha) ") "; }
ol.vs-list-upper-alpha-paren  > li::before { content: counter(vs-fancy, upper-alpha) ") "; }
ol.vs-list-lower-roman-paren  > li::before { content: counter(vs-fancy, lower-roman) ") "; }
ol.vs-list-upper-roman-paren  > li::before { content: counter(vs-fancy, upper-roman) ") "; }
ol.vs-list-decimal-paren2     > li::before { content: "(" counter(vs-fancy) ") "; }
ol.vs-list-lower-alpha-paren2 > li::before { content: "(" counter(vs-fancy, lower-alpha) ") "; }
ol.vs-list-upper-alpha-paren2 > li::before { content: "(" counter(vs-fancy, upper-alpha) ") "; }
ol.vs-list-lower-roman-paren2 > li::before { content: "(" counter(vs-fancy, lower-roman) ") "; }
ol.vs-list-upper-roman-paren2 > li::before { content: "(" counter(vs-fancy, upper-roman) ") "; }
```

複数行項目のぶら下げインデント（2 行目以降をマーカー分下げる）は実装時に `vs build` の PDF を目視して調整する（`text-indent` 負値＋`padding` 等。v1 は過度に凝らない）。

### 5.2 outline-list（複合番号）

```css
/* :::{.outline-list} — ネスト番号リストを 1. / 1.1 / 1.2 の複合番号で表示 */
.outline-list ol { list-style: none; counter-reset: vs-outline; }
.outline-list ol > li { counter-increment: vs-outline; }
.outline-list ol > li::before { content: counters(vs-outline, ".") ". "; font-weight: 700; }
```

`counters()`（ネスト連結）は Vivliostyle がネイティブサポート。クリーン EPUB（Kobo/Apple Books）も `::before`＋カウンタを解する（admonition 角タブで実績あり）。

### 5.3 ul のレベル別マーカー（和文組版デフォルト「● ○ ・」）

Vivliostyle の UA スタイルシートには標準の `ul ul { list-style-type: circle }` / `ul ul ul { square }` が既にあり（`@vivliostyle/core` 内で確認済み）、レベル別変化そのものは現状でも効いている。これを UA 任せにせず和文組版寄りの並びで明示する:

```css
/* 番号なし箇条書き — レベル別マーカー（和文組版: ● ○ ・）。
   第3レベルの中黒は list-style-type の標準値に無いため文字列指定（CSS Lists 3） */
ul { list-style-type: disc; }            /* ● */
ul ul { list-style-type: circle; }       /* ○ */
ul ul ul { list-style-type: "・"; }      /* ・ */
```

- **要検証（実装時）**: `list-style-type: "・"`（文字列値）を Vivliostyle が解するか、`vs build` の PDF 目視で確認する。効かない場合のフォールバック: `ul ul ul { list-style: none }` ＋ `ul ul ul > li::before { content: "・" }`（PDF/クリーン EPUB は `::before` 可）。
- ol 内にネストした ul にも同じ深さ規則が効くよう、セレクタは実装時に必要なら `:is(ul, ol)` 系へ調整してよい（クリーン EPUB/PDF 側は `:is()` 使用可。**Kindle 側は不可**）。
- 記法は増えない。著者は標準の字下げネストを書くだけ。

### 5.4 マーカーセットの個別変更（将来・v1 対象外）

✓ / → / ※ など任意記号のリスト単位変更は、需要が確認できたら `:::{.check-list}` のような `:::{.class}` オプトイン＋§6 注入機構の流用で別途追加する（YAGNI・outline-list と同じ流儀）。v1 では実装しない。

## 6. 実装設計③: Kindle 実体マーカー注入（フォールバック必須）

**必須性の根拠（検証結果）**: `kindle-css-compatibility-notes.md` §2 の実測で KFX は `::before` を**ルールごと破棄**する。よって §5 の括弧付きマーカー（9 種）と outline-list の複合番号は Kindle で**マーカーが一切表示されない**。ピリオド様式は `<ol type>` 属性が効く可能性があるが未実測のため、**全 fancy 様式＋outline-list を単一の注入機構で統一**する（検証マトリクスを最小化。type 属性が KFX で効くと実測できたらピリオド様式の注入省略は将来の最適化として可）。

### 6.1 EpubBuilder への注入メソッド

`decorate_admonitions_for_epub!`（`epub_builder.rb:1502`）と同型の `decorate_list_markers_for_epub!(html_files)` を追加し、**Kindle 専用フェーズ**（`epub_builder.rb:267` の `decorate_admonitions_for_epub!` の直後）で呼ぶ。クリーン EPUB・PDF には注入しない。

処理内容（Nokogiri・`HtmlParser.parse_html_document` 経由）:

1. **fancy list**: `doc.css('ol.vs-fancy-list')` を走査。クラス名から様式・区切りを、`start` 属性（無ければ 1）から開始値を復元し、各直下 `li` の先頭へ実体マーカーを注入する:
   ```html
   <span class="vs-li-marker">(a) </span>
   ```
   マーカー文字列は様式どおり（`C. ` / `iv) ` / `(2) ` 等・末尾半角スペース込み）。
2. **outline-list**: `doc.css('div.outline-list')` 内の `ol` ツリーを再帰走査し、各 `li` に複合番号 `1.1 ` 等を計算して同じ `span.vs-li-marker` を注入する（`ul` は素通し）。
3. **冪等ガード**: `li.at_css('.vs-li-marker')` が既にあればスキップ（`vs-adm-label` の二重注入防止と同じ流儀）。
4. 番号文字列の生成ヘルパー（整数→英字、整数→ローマ数字）は EpubBuilder 内の private メソッドでよい（英字は 26 進 `a..z`、範囲超過は数字のままフォールバック）。

### 6.2 body.vs-kindle CSS フォールバック

`chapter-common.css` の `body.vs-kindle` セクション（533 行付近）へ追記。**`:is()`/`var()`/`calc()` 禁止・具体値で記述**（同ファイル §6 チェックリスト遵守）:

```css
/* fancy list / outline-list: Kindle は ::before を破棄するため、
   EpubBuilder が先頭注入する実体マーカー <span class="vs-li-marker"> で番号を出す。
   ネイティブマーカーとの二重表示を防ぐため list-style を消す。 */
body.vs-kindle ol.vs-fancy-list,
body.vs-kindle .outline-list ol {
  list-style: none;
  padding-inline-start: 1em;
}
body.vs-kindle .vs-li-marker {
  font-weight: 700;
}

/* ul 第3レベル: KFX は文字列 list-style-type（"・"）を解さない見込みのため
   ネイティブ値 square（■）へ優雅に劣化させる。●○は disc/circle がそのまま効く */
body.vs-kindle ul ul ul {
  list-style-type: square;
}
```

ul のレベル別マーカーは実体注入の**対象外**（disc/circle/square はネイティブ値なので注入不要。第3レベルだけ表示が「・→■」に変わる劣化を許容する）。Kindle Previewer で disc/circle のネスト変化が既定で効いていることを確認し、効かない場合のみ `body.vs-kindle ul { list-style-type: disc }` 等の明示を追加する。

## 7. 制限事項（既知のトレードオフ・ドキュメント記載必須）

1. **fancy list 項目内では VFM 固有インラインが効かない**: Kramdown 経路のため、ルビ `{漢字|よみ}`・脚注参照 `[^id]`・リンク脚注化が項目内で機能しない（定義リストと同じ制約）。fancy list は短い列挙向け。長文・リッチな項目は標準リストを使う。
2. **標準リストと fancy の混在ブロックは全体が Kramdown 経路に入る**: 親が標準 `1.` でも子に `(a)` があればブロック全体が変換される（構造上分割不可）。
3. **単文字ローマ字優先**: `c.` は英字 3 番目ではなくローマ数字 100 と解釈される（Pandoc 準拠）。
4. **`(1)` 段落書き出しの誤爆**: 地の文を `(1) ` で始めるとリスト化される。`\(1)` でエスケープ。
5. **`1.` 配下のネストは 3 スペース以上のインデントが必要**（CommonMark 規則。2 スペースではネストしない）。標準リスト（VFM 経路）に効く注意としてドキュメントへ。
6. **outline-list と fancy の併用は非サポート**（v1）。

## 8. テスト計画

Minitest。実装時は ruby-coding-rules skill を適用。

1. **`test/vivlio_starter/cli/pre_process/fancy_list_test.rb`（新規・ユニット）** — `MarkdownTransformer.convert_fancy_lists` を直接叩く:
   - 13 様式それぞれの `<ol>` クラス/`type`/`start` 出力
   - 開始値オフセット（`C.` → `start="3"`、`(iv)` → `counter-reset: vs-fancy 3`）
   - 2 スペース規則（`B. Russell` 1 スペース→無変換、`B.  項目` 2 スペース→変換）
   - エスケープ `\(1)` →無変換＋`\` 除去
   - コードフェンス/インラインコード内の不変性
   - 標準リストのみのブロックが**完全無変換**（バイト一致）で素通しされること
   - ネスト混在（`1.` 親＋ `(a)` 子）の構造と属性
   - `ul` 混在時に `ul` が無加工なこと
   - 様式混在時の警告（`log_warn`）と先頭様式継続
2. **`test/vivlio_starter/cli/epub_builder_test.rb`（追記）** — `decorate_list_markers_for_epub!` のユニット: fancy 各様式のマーカー文字列、outline の複合番号計算、冪等性（2 回適用で注入 1 つ）。
3. **`test/vivlio_starter/cli/build/epub_kindle_layout_test.rb`（追記）** — CLAUDE.md の Kindle 劣化 3 点パターン (3) に準拠: Kindle フレーバの生成 HTML に `span.vs-li-marker` が存在し、クリーン EPUB には**存在しない**ことのアサーション。
4. `rake test` 全通過・`bundle exec rubocop` クリーン。

## 9. ドキュメント更新

- `contents/21-markdown-tutorial.md` のリスト節（110〜130 行）: ネストのインデント規則（§7-5）、fancy list 記法の基本、ul のレベル別デフォルトマーカー「● ○ ・」（Kindle では第 3 レベルが ■ になる旨も一言）。
- `contents/22-extentions.md` の「リスト装飾」節（663 行〜）: fancy list 全様式の一覧・`:::{.outline-list}`・制限事項（§7）。
- 更新後 `ruby copy_to_scaffold.rb` で scaffold へ同期（CSS 変更分も同時に同期される）。

## 10. 実装手順（Opus 4.8 向けチェックリスト）

1. [ ] `MarkdownTransformer.convert_fancy_lists` ＋様式判定ヘルパーを実装（§4.1。テスト先行可）
2. [ ] `test/vivlio_starter/cli/pre_process/fancy_list_test.rb` を作成し通す（§8-1）
3. [ ] `MarkdownPreprocessor#transform_fancy_lists!` を `transform_definition_lists!` の直前に組み込む（§4.2）
4. [ ] `stylesheets/chapter-common.css`（root）へ §5.1・§5.2・§5.3 を追記
5. [ ] `vs build` で PDF を目視検証（全様式・ネスト・outline-list・ul 3 レベルのサンプル原稿を一時章で用意。ぶら下げインデント・`list-style-type: "・"` の可否をここで確認）
6. [ ] `EpubBuilder#decorate_list_markers_for_epub!` ＋番号文字列ヘルパーを実装し、Kindle フェーズ（`epub_builder.rb:267` 直後）へ登録（§6.1）
7. [ ] `chapter-common.css` の `body.vs-kindle` セクションへ §6.2 を追記
8. [ ] §8-2・§8-3 のテストを追加して通す
9. [ ] `contents/21` / `contents/22` を更新（§9）
10. [ ] `ruby copy_to_scaffold.rb` で scaffold 同期
11. [ ] `rake test` / `bundle exec rubocop` / `rake test:layout`（余力があれば）
12. [ ] **Kindle Previewer 3 で実機確認**（epubcheck 合格では KFX 表示を保証しない。`kindle-css-compatibility-notes.md` §6 チェックリスト遵守）

## 11. 考慮した代替案（不採用）

| 案 | 不採用理由 |
|---|---|
| VFM 温存のため fancy サブリストを `:::{.class}` で個別に囲む | `:::` の div 化は行単位の後処理置換であり、リスト項目内部のフェンスはリスト構造を分断する。ネスト fancy に対応できない |
| `<ol>` 開きタグのみ生 HTML で出し項目本文は Markdown のまま VFM に処理させる（HTML スケルトン方式） | VFM のセクション化・段落整形との相互作用が VFM バージョン依存で脆く、テストも VFM 込みでしか書けない。定義リストで実績ある Kramdown 方式を優先 |
| 複合番号をデフォルト挙動にする | 独立採番を期待する著者と衝突（ソーステキストから意図を判別不能）。Pandoc/LaTeX/HTML のデフォルトとも食い違う |
| Pandoc `#.`（自動連番）・GFM タスクリストの同時導入 | 今回のスコープ外（需要が確認できたら別仕様で） |
| Kindle でピリオド様式のみ `<ol type>` ネイティブ表示に頼る | KFX での type 属性サポートが未実測。注入機構は括弧様式・outline でどのみち必須なので、全様式統一が検証コスト最小 |
| ul のマーカー文字 `-`/`*`/`+` の書き分けをマーカー種別に対応付ける | CommonMark では 3 文字は完全同義で、著者は意図なく混用する（ファイル間で `-` と `*` が混ざるのは普通）。意味を載せると見た目が不意に揺れる上、同レベル途中でマーカー文字を変えると別リストに分裂する CommonMark の罠まで絡む。番号リストの `A.` と違い書き分けに著者の意図が乗らないため不採用 |
