# EPUB/Kindle コードブロックの行番号と折返し 仕様書

> 作成日: 2026-06-20 / **方式確定・全面改訂: 2026-07-12**
> ステータス: **実装済み（2026-07-12）**。§4 の Kindle Previewer 実測チェックは未実施（受け入れ時に確認のこと）。旧 A〜E 案は §7 に不採用理由つきで保存
> 実装メモ: `code-include-line-number-spec.md` と同時に実装したため §8 の読み替えは発生していない（`data-start` 伝搬・`--code-font` 修正ともあちら側の実装が同居）
> 対象: リフロー型 EPUB（クリーン EPUB / Kindle）でのソースコード表示。行番号と各論理行の確実な対応、長行折返し時の整列。PDF は不変。
> 決定事項（2026-07-12 ユーザー確認済み）:
> - **テーブル方式（現行 Kindle・旧 A 案）は廃止**。KFX がテーブルセルの `width`/`white-space: nowrap` を尊重しない（kindle-css-compatibility-notes §2 で△実測）土俵では戦わない
> - **F 案採用**: 1 論理行 = 1 ブロック要素＋ぶら下げインデント。番号はクリーン EPUB では `::before`＋CSS カウンタ（コピーに混入しない）、Kindle では nbsp 右詰めの実テキスト注入（既存の実体注入パターン）
> - クリーン EPUB の「長行折返しで番号がずれる」未解決問題（旧 §0）も同じ構造で**同時に解消**する
> 関連: `lib/vivlio_starter/cli/build/epub_builder.rb`（`convert_code_blocks_for_epub!` ほか・行スプリッタ）, `stylesheets/code.css`, `stylesheets/prism.css`, `docs/specs/kindle-css-compatibility-notes.md`, `docs/specs/code-include-line-number-spec.md`（**§8 連携必読**・`data-start` と `--code-font` 修正はあちら側）

## 0. 現状と問題（2026-07-12 時点）

- **PDF**: Prism `.line-numbers-rows`（絶対配置ガター）。ページ幅固定のため崩れない。**本仕様の変更対象外**。
- **クリーン EPUB（Kobo/Apple Books）**: Prism ガター＋`body.vs-epub pre { pre-wrap }`（クリップ対策済み）。**未解決**: ガターは固定行高で番号を並べるため、長行が折り返すと番号と論理行がずれる。
- **Kindle（KFX）**: `convert_code_blocks_for_epub!` が 2 列テーブル（`table.vs-code-epub`）へ変換。番号↔行の対応は保たれるが、(1) **2 桁以上の番号が縦に折り返る**（`1`/`0` の 2 行になる）、(2) **折返し行と非折返し行の行間が不均一**。原因は KFX がセルの `width`/`nowrap` を尊重しないこと（互換性メモ §2 に△実測記録）で、テーブルのままでは是正の見込みが薄い。

## 1. 決定方式（F 案）: 行ブロック＋ぶら下げインデント

### 1.1 構造

`pre.line-numbers > code` を、1 論理行 = 1 ブロックの構造へ変換する（両フレーバ共通）:

```html
<div class="vs-code-epub language-ruby">
  <div class="vs-code-line"><code class="language-ruby">if prime?(n)</code></div>
  <div class="vs-code-line"><code class="language-ruby">  puts n  # 長い行は折り返し…</code></div>
</div>
```

行分割は既存の `split_code_into_lines`（`epub_builder.rb:1575`・Prism トークンの行跨ぎを閉じ／開き直す実装済みスプリッタ）を**そのまま流用**する。空行は現行どおり `&nbsp;` で行高を保つ。

### 1.2 番号の出し方（フレーバで分岐）

- **クリーン EPUB**: 実テキストは注入せず、CSS カウンタで描く。**選択・コピーに番号が混入しない**（旧 C 案の欠点を回避）:
  ```css
  body.vs-epub .vs-code-epub { counter-reset: vs-code-ln; }
  body.vs-epub .vs-code-line { counter-increment: vs-code-ln; }
  body.vs-epub .vs-code-line::before {
    content: counter(vs-code-ln);
    display: inline-block; inline-size: 2.5em; padding-inline-end: 0.6em;
    text-align: right; color: #999;
  }
  ```
  `::before`＋カウンタは Kobo/Apple で実績あり（admonition 角タブ）。
- **Kindle**: `::before` が使えない（互換性メモ §2 ❌実測）ため、**実テキストの番号 span を各行頭へ注入**する（`vs-adm-label`/`vs-li-marker` と同じ実体注入パターン）:
  ```html
  <div class="vs-code-line"><span class="vs-code-ln">&#160;9 </span><code …>…</code></div>
  <div class="vs-code-line"><span class="vs-code-ln">10 </span><code …>…</code></div>
  ```
  番号は **nbsp（` `）で最大桁数に右詰めパディング**する。等幅フォントなので **CSS の幅指定なしで桁が揃い**、nbsp＋数字には分割機会が無いため**縦折返しが原理的に起きない**。

### 1.3 折返しの整列（ぶら下げインデント）

```css
.vs-code-line {
  white-space: pre-wrap;
  overflow-wrap: anywhere;   /* 長トークンの折返し（旧 §6 A 案の継承） */
  padding-left: 3.1em;       /* 番号幅 2.5em ＋ 区切り余白 0.6em */
  text-indent: -3.1em;       /* 1 行目だけ左へ戻す ＝ 番号が行頭・折返し行はコード開始位置へ揃う */
}
```

- 番号は論理行の 1 行目に必ず付き、折り返した 2 行目以降は番号の右（コード開始位置）に揃って字下げされる。
- 全行が同じ `line-height` の通常ブロック——セルの `vertical-align` が存在しないため**行間不均一も原理的に消える**。
- Kindle 側は物理プロパティ・具体値のみで書く（`:is()`/`var()`/論理プロパティ回避。負の `text-indent` は書籍組版の基本機能で KFX でも動作が見込まれるが **§4 で実測必須**）。

### 1.4 なぜテーブルではないのか

KFX の既知欠陥（セル `width`/`nowrap` 不尊重）は回避策の当てがなく、旧 A 案はその欠陥の修正が前提条件だった。F 案が依存するのは**テキスト・padding・text-indent・pre-wrap という KFX が解する最低限の原始機能のみ**で、勝ち目のある土俵に移る。

## 2. 実装設計

### 2.1 構造変換（両フレーバ共通フェーズ）

- `convert_code_blocks_for_epub!` を **Kindle 限定フェーズから両フレーバ共通フェーズへ移動**する（`generate_epub_entries!` の共通 Phase 末尾・`inject_heading_images_for_epub!` の後）。対象セレクタは従来どおり `pre.line-numbers`。
- `convert_code_pre_to_table!`/`build_code_table`/`build_code_row` を `convert_code_pre_to_lines!`/`build_code_lines`（`div.vs-code-epub` 構築）へ置き換える。`split_code_into_lines`・`.line-numbers-rows` 除去・失敗時の warn＆現状維持・空行 `&nbsp;` はそのまま。
- `language-*` クラスは容器 div と各行 `<code>` の両方に付ける（Prism トークン色 CSS の継続適用と、既存 `pre[class*="language-"]` 系セレクタとの互換のため）。
- `pre` の `data-start` 属性（code-include-line-number-spec の伝搬値）があれば容器 div へ**引き継ぎ**、クリーン EPUB 用に `style="counter-reset: vs-code-ln N-1"` を容器へ付与する（§8）。

### 2.2 Kindle 番号注入（Kindle 限定フェーズ）

- 新設 `inject_code_line_numbers_for_kindle!(html_files)` を Kindle 限定フェーズ（`decorate_admonitions_for_epub!` の並び）に追加。
- `div.vs-code-epub` ごとに: 開始値 `start = (div['data-start'] || 1).to_i`、最大桁数 `(start + 行数 - 1).to_s.length` を求め、各 `.vs-code-line` の先頭へ `<span class="vs-code-ln">` を注入（番号を nbsp で右詰め＋末尾に区切り空白 1 つ）。
- 冪等ガード: `line.at_css('.vs-code-ln')` があればスキップ。
- クリーン EPUB にはこの span は存在しない（スナップショット方式 B により混入しない）。

### 2.3 CSS（`stylesheets/code.css`・root 編集→scaffold 同期）

- 既存の `body.vs-kindle table.vs-code-epub` 系ルール（`code.css:190-230`）を**削除**し、置き換える:
  ```css
  /* 両フレーバ共通の外枠・フォント */
  .vs-code-epub {
    font-size: 0.85em; line-height: 1.4; margin: 0.4em 0;
    border: 1px solid #ccc; border-radius: 2px; padding: 0.3em 0.4em;
    font-family: "HackGen35 Console NF", monospace;  /* var() 不使用（Kindle 共用のため具体名。§8-2 と整合） */
  }
  .vs-code-line { /* §1.3 のとおり */ }
  /* クリーン EPUB の番号（§1.2） */
  body.vs-epub …
  /* Kindle の番号テキスト */
  body.vs-kindle .vs-code-ln { color: #999; }
  ```
  ※ セレクタを `body.vs-epub`/`body.vs-kindle` 配下に限定するか素で書くかは実装時に判断（この div は EPUB 経路でしか生成されず PDF に現れないため素でも安全だが、明示する方が既存流儀に合う）。
- 旧 §6 A 案の `body.vs-epub pre[class*="language-"] { pre-wrap … }`（`code.css:241-248`）は、**変換失敗時のフォールバック残存 pre への安全網として温存**する（コメントで役割変更を注記）。
- 編集後 `ruby copy_to_scaffold.rb` で同期。

### 2.4 触らないもの

- PDF の Prism ガター（`prism.css`・`.line-numbers-rows`）と `PrismLinesCommands`。
- `split_code_into_lines` 系の行スプリッタ本体。
- `.terminal` 等 `pre.line-numbers` でない pre。

## 3. 番号↔行の対応が保証される理屈（レビュー用まとめ）

| 症状（旧） | F 案での消滅理由 |
|---|---|
| 番号の縦折返し（Kindle） | 番号は nbsp＋数字の実テキストで分割機会なし。CSS 幅指定に依存しない |
| 行間不均一（Kindle） | セルが存在せず、全行同一 line-height の通常ブロック |
| 折返しで番号ずれ（クリーン EPUB） | 番号が各論理行ブロックに内包される（カウンタは行ブロックで増える）ため、折返しはブロック内で完結 |

## 4. Kindle 実測チェックリスト（Kindle Previewer 3・受け入れ前提）

- [ ] 負の `text-indent`＋`padding-left` のぶら下げが効く（2 行目以降がコード開始位置へ揃う）
- [ ] `white-space: pre-wrap` で行頭インデント（半角空白）が保持される（潰れる場合は変換時に行頭空白を `&#160;` 化するフォールバックを実装）
- [ ] 2 桁・3 桁の番号が折り返さない／行間が均一
- [ ] フォントサイズ最小⇔最大で崩れない
- [ ] コード枠・背景が表示される（具体値 CSS）

## 5. テスト計画

1. **`test/vivlio_starter/cli/epub_builder_test.rb`（改修）**: テーブル化テストを行ブロック化テストへ置換——`div.vs-code-epub > div.vs-code-line` 構造・行数一致・トークン span 保持・空行 `&nbsp;`・失敗時現状維持・`data-start` の容器引き継ぎと `counter-reset` style。
2. **同（追記）**: `inject_code_line_numbers_for_kindle!`——nbsp 右詰め（9→`&#160;9 `、10→`10 `）・`data-start="22"` で 22 始まり・冪等性。
3. **`test/vivlio_starter/cli/build/epub_kindle_layout_test.rb`（追記）**: Kindle フレーバに `span.vs-code-ln` が存在し、クリーン EPUB には存在しない（CLAUDE.md の Kindle 劣化 3 点パターン (3) 準拠）。
4. `rake test` / `bundle exec rubocop`。

## 6. 受け入れ条件

- [ ] クリーン EPUB（Apple Books/Kobo）でウィンドウ幅・フォントサイズを変えても全コードが表示され、行番号が各論理行に対応する（コピーに番号が混入しない）。
- [ ] Kindle で §4 全項目パス。
- [ ] PDF のコード表示（行番号付きガター）はビルド前後でバイト同一。
- [ ] `code-include-line-number-spec.md` 実装済みの場合: 範囲 include の開始行番号が両フレーバで正しい（§8）。未実装の場合: `data-start` なしの従来動作（1 始まり）が保たれる。

## 7. 旧方式候補の棚卸し（2026-06-20 提案 A〜E・不採用理由）

| 案 | 不採用理由 |
|---|---|
| A. テーブル化（現行 Kindle を両フレーバへ） | KFX のセル `width`/`nowrap` 不尊重（△実測）の修正が前提条件で、その回避策に当てがない |
| B. 行番号非表示 | 実装最軽量だが PDF と情報量が非対称になる。F 案が同等の軽さで番号を保てるため不要 |
| C. 番号をテキスト接頭辞に | コピー時の番号混入が全リーダーに及ぶ。F 案はこの発想を「Kindle 限定＋クリーンは CSS カウンタ」に洗練したもの |
| D. 固定レイアウト EPUB | リフロー・文字拡大を失う。別文脈でも見送り済み → `kindle-fixed-layout-ideas.md` |
| E. 折返さず横スクロール | Apple Books が横スクロールを提供せずクリップ再発（§6 A 案導入前に実証済み） |

## 8. `code-include-line-number-spec.md` との連携（実装順序はどちらが先でも可）

両仕様は同じ箇所（コード変換・`code.css`）を触る。責務分担:

1. **`data-start` の生成・伝搬（include 範囲 → `pre[data-start]`）はあちらの責務**（フェンス情報文字列 `#L22-L25` → `prism_lines.rb`）。本仕様は「`pre` の `data-start` を容器 div へ引き継ぎ、クリーンはカウンタ開始値・Kindle は採番開始値として消費する」（§2.1・§2.2）。
2. **`--code-font` 未定義バグの修正（`code.css` 3 箇所＋Techbook 注入削除）はあちらの §1.6/§3.5 の責務**。本仕様の新 CSS（§2.3）は最初から `var()` を使わず具体名＋`monospace` で書くため衝突しない。あちらの §3.5 が挙げる `code.css:193`（`body.vs-kindle table.vs-code-epub`）は本仕様でセレクタごと消滅するので、**本仕様が先に入った場合はその項目は「新セレクタ `.vs-code-epub` を確認して完了」と読み替える**。
3. **あちらの §3.3（Kindle テーブルの採番 `idx + start`）は、本仕様が先に入った場合は `inject_code_line_numbers_for_kindle!` への同変更（採番開始値）と読み替える**（あちら側にも 2026-07-12 付で注記済み）。
4. 受け入れ試験は統合して行ってよい: `include:prime.rb:14-17` が PDF＝ガター 14 始まり／クリーン EPUB＝カウンタ 14 始まり／Kindle＝実テキスト 14 始まり。
