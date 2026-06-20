# EPUB Kindle レイアウト改善 仕様書

> 作成日: 2026-06-16
> ステータス: **実装済み・v4 改訂（2026-06-18）** — v3 実機でさらに判明した課題に対応（後述「v4 改訂」）。**重要な知見（v2）: Kindle は外部 CSS の画像サイズ指定を無視し、inline style/属性を尊重する**。**重要な知見（v3）: 数式 SVG は固有寸法を持たず、Kindle が `em`/`ex` を無視すると img 既定の 300×150px で巨大表示される。px の HTML 属性で本文相当に固定できる（ただし読者のフォント拡大には追従しない）。** **重要な知見（v4）: Kindle KFX は `var()`（CSS カスタムプロパティ）も解さず、`var()` を含む宣言を丸ごと破棄する。`border: 0.2mm var(--x)` が破棄され枠が消えていた。具体値を先に置き `var()` で上書きすれば、PDF/Apple Books は従来どおり・Kindle は具体値フォールバックになる。同様に `position:absolute` 非対応を逆用し、注入ラベルを Apple Books でだけ画面外退避して隠せる。** テスト green・Kindle 変換成功（Enhanced Typesetting: Supported / Error 0 / Quality 0）を確認。数値の最終微調整は iPhone/iPad 端末プレビューで別途。

## v4 改訂（2026-06-18）

v3 実機（`kindle_math*.png` / `kindle_tip_memo.png` / `epub_tip_memo_column.png`）で判明した課題と対策:

| 課題 | 原因 | 対策（実装） |
| --- | --- | --- |
| 表内/インライン数式が本文より小さい・読みづらい | px 固定は安定だが**読者のフォント拡大に追従しない**。外部 SVG を `<img>` 参照する方式の本質的限界（em→巨大/不安定、px→固定で拡大時に相対的に小） | **既知の制限**として運用回避を推奨（表内に数式を置かない／本文はそのまま）。`$$` ディスプレイ数式は正常。将来案: SVG をインライン展開して `height:1em` で本文連動（別タスク） |
| Tip/MEMO/COLUMN の囲み枠が Kindle で消える | `border: 0.2mm var(--x)` の **`var()` を Kindle が解さず border 宣言ごと破棄** | `.tip/.memo/.column` の border を「具体値(1px #888)を先に置き `border-width`/`border-color` を `var()` で上書き」する形へ。**PDF/Apple Books は従来どおり 0.2mm・themed**、Kindle のみ 1px #888 |
| Tip ラベルが Kindle で消える／EPUB(Apple Books)では従来の `::before` ラベルを残したい | `::before{position:absolute}` を Kindle が無視 | ラベルは実体 `<p class="vs-adm-label">` を注入。CSS で `position:absolute; left:-9999px` とし、**absolute 対応の Apple Books では画面外退避＝不可視（従来の ::before バッジのみ表示）／absolute 非対応の Kindle では通常フローに残り表示**。`::before` は両環境とも従来のまま（content:none で消さない）→ **EPUB は完全に元のまま** |
| COLUMN も同形式に | 旧版は tip/memo のみ対応 | `ADMONITION_LABELS` に `column` を追加（【COLUMN】注入）。border フォールバックも `.column` に適用 |
| tip と memo が近接して見える | v3 で `body.vs-epub` の `margin-block:1em` 上書きが効いていた | 当該上書きを撤去し**本体既定の `margin-block: 8mm 6mm` に復帰**（枠間に明確なアキ） |

## v3 改訂（2026-06-18）

v2 実機（`kindle_*_v3.png` / `epub_codes_and_tips.png`）で判明した課題と対策:

| 課題 | 原因 | 対策（実装） |
| --- | --- | --- |
| sideimage 画像が依然大きい | inline 45% | `LAYOUT_IMAGE_RULES` の sideimage 系を **25%**（text 3 : image 1）へ。book-card(40%) は据え置き |
| **表内数式（単位 kg/m 等）が巨大化** | 数式 SVG に固有寸法が無く、Kindle が em を無視すると **300px 既定**で描画 | `apply_math_px_fallback!` で em→px（×16）を **`width`/`height` 属性**として付与。表内は `MIN_TABLE_MATH_EM` floor 後の em（1em→16px）で本文相当 |
| コード下の「黒い四角」 | Kindle がコードを「拡大可能な図」とみなし付ける **ズーム虫眼鏡バッジ**（Kindle 標準のテーブル/図のズームアフォーダンス） | 機能上は無害（タップでコード拡大）。完全除去は figure 解体が要るため任意対応（要 GUI 検証） |
| Tip/MEMO の囲み枠が消える | `::before` ラベルが `position:absolute`（Kindle 無視）＋枠線 `0.2mm`（極細で無視されがち） | `body.vs-epub .tip/.memo` に **px 枠線**、ラベルは `decorate_admonitions_for_epub!` が **実体 `<p class="vs-adm-label">【TIP】/【MEMO】</p>` を先頭注入** |
| EPUB コード表に行罫線・ゼブラ | `table.css` の `td,th{border}` ・ `tr:nth-child(even){background}` が全表に適用 | `body.vs-epub table.vs-code-epub` で **行罫線・ゼブラを打ち消し**、外枠（`border:1px`）と番号｜コードの縦仕切りのみ残す |
> 対象: `vs build`（epub ターゲット）が生成する EPUB を Kindle（iPhone/iPad の Kindle アプリ・KFX）で表示したときのレイアウト崩れ
> 起点: 実機スクリーンショット `docs/specs/kindle_books.png` / `kindle_sideimages.png` / `kindle_tables.png` / `kindle_codes.png`（＋PDF版 `kindle_codes_table_layout.png`）
> 関連: `math-frontispiece-svg-spec.md`（扉絵/節絵）, `epub-kindle-webp-transcode-spec.md`（WebP）
> 優先度: 中〜高（変換は成功するが、最重要ターゲット Kindle での見栄えが崩れる）
> スコープ: ① books（book-card 画像の巨大化）② sideimages（挿絵の巨大化）③ tables（数式単位の巨大化）④ codes（行番号の左ガター崩れ→テーブル方式）

---

## 0. 背景と全体方針

EPUB→Kindle 変換自体は成功しているが（`epub-kindle-webp-transcode-spec.md` 実装後）、Kindle のリフロー表示で 4 種の崩れが出る。原因はいずれも **Kindle（KFX / Enhanced Typesetting）のリフローが PDF 向け CSS の一部を非対応**であること:

| 非対応（無視される） | 影響する崩れ |
| --- | --- |
| **CSS Grid**（`grid-template-columns`） | ① book-card・② img-text/text2-img のグリッドが単列に潰れ、列幅指定が消えて画像が全幅化 |
| **`ex` 単位**（`<img>` の寸法） | ③ inline 数式（`$\text{A}$` 等）の高さ指定が効かず、固有寸法のない SVG が巨大表示 |
| **`position: absolute/relative`** | ④ Prism 行番号ガター（`.line-numbers-rows{position:absolute}`）が崩れる |

方針は扉絵・WebP と同じ **「EPUB 専用に是正し、PDF は一切変えない」**:

1. **PDF 経路は不変。** すべての修正は EPUB ビルド（Step E）に閉じる。Step E は PDF 完成後に共有 HTML を書き換えるため PDF へ副作用がない（既存の table align 書き換え・WebP トランスコードと同じ前提）。
2. **CSS で済むものは EPUB マーカー（`body.vs-epub`）ガードの上書きルール**、**マークアップ変更が要るもの（数式 ex→em・コードのテーブル化）は EpubBuilder の HTML 後処理**で行う。
3. **Kindle が確実に解す手段だけを使う**: `max-width`/`max-height`（`%`・`em`）、`float`、`table`、`em` 単位。Grid・absolute・`ex`・`vw/vh`・`transform`・`clamp()`・`Q` は使わない。

---

## 1. 共通機構：EPUB マーカーと適用箇所

### 1-1. `body.vs-epub` マーカーの付与

`EpubBuilder.generate_epub_entries!`（Step E）の HTML 後処理群に、各 EPUB 章 HTML の `<body>` へ `vs-epub` クラスを付与するパスを追加する。PDF 用 HTML にはこのクラスが付かないため、`body.vs-epub` ガードの CSS は **PDF では不発で無害**。

> 既存の EPUB 専用 CSS は要素クラス（`vs-image-heading-epub` 等）でガードしている。本仕様は「ページ全体に効く上書き」が多いため、`body.vs-epub` の単一マーカーを導入してまとめてガードする。

### 1-2. HTML 後処理パス（EpubBuilder）

`generate_epub_entries!` の既存パス（…→ `inject_heading_images_for_epub!` → `transcode_webp_images_for_epub!`）の後に、以下を追加する:

```
mark_body_for_epub!            # §1-1
convert_math_units_for_epub!   # §3（inline 数式 ex→em）
convert_code_blocks_for_epub!  # §4（行番号 → 2 列テーブル）
```

いずれも `PostProcessCommands::HtmlParser`（Nokogiri）で解析・保存する既存作法に合わせる。

### 1-3. CSS の二重管理（重要）

CSS の追加・変更は **`stylesheets/`（リポジトリ直下）と `lib/project_scaffold/stylesheets/`（新規プロジェクト雛形）の両方**へ同一内容で反映する（既存方針）。本仕様の CSS はすべて `body.vs-epub` でガードする。

---

## 2. 画像の暴れ（① books / ② sideimages）

### 2-1. 原因

- `① .book-card`（`components.css`）: `display: grid; grid-template-columns: 1fr 3fr;` ＋ `.book-card img { width: 100%; }`。Kindle で grid が単列化し、img が**ページ全幅**になる。
- `② .img-text / .text-img / .img-text2 / .text2-img / .img-text3 / .text3-img`（`layout-utils.css`）: 同じく grid。横に置いた画像（または図版）が全幅化する。挿絵・アバター・ロゴが巨大になる。

### 2-2. 修正（v2: inline style が主・CSS はフォールバック）

> **v2 改訂（実機で判明）**: Kindle は外部 CSS（stylesheet）の `<img>` サイズ指定（`max-width`/`width`/`float`）を**無視**する（CSS は EPUB に同梱されているのにフルサイズ表示のまま）。一方、要素に直接書いた **inline `style` は尊重**する（数式の inline ex→em は効いた）。よって画像の幅・回り込みは **EpubBuilder が inline style で付与**する（`constrain_layout_images_for_epub!`）。`book-card`・`sideimage(-left/-right)`・`img-text/text-img` 系のコンテナ直下の画像（`figure` 優先・無ければ `img`）に `width`(%)・`float` を inline で課す（figure の場合は内側 `img` も `width:100%`）。クラス→幅/float の対応は `LAYOUT_IMAGE_RULES`（book-card=40%/左、その他=45%、`*-img`/`sideimage-right`=右）。下記 CSS は grid 解除と上限のフォールアウト用に残す（Kindle では無視されるが他リーダー保険）。

#### 旧: 修正（CSS のみ・`body.vs-epub` ガード）— フォールバックとして保持

Kindle はグリッドを解さないので**単列フロー前提**で、画像に上限を課し `float` で本文を横に回り込ませる。

- **book-card**（`components.css` に追記）:
  ```css
  body.vs-epub .book-card { display: block; }
  body.vs-epub .book-card img {
    max-width: 38%;
    max-height: 13em;
    width: auto;          /* width:100% を打ち消す */
    float: left;
    margin: 0 1em 0.5em 0;
  }
  body.vs-epub .book-info { display: block; }
  body.vs-epub .book-card::after { content: ""; display: block; clear: both; }
  ```
- **img-text 系**（`layout-utils.css` に追記）: grid を解除し、画像に上限＋`float`。本文先頭（`img-text*`）は左 float、本文後（`*-img`）は右 float。
  ```css
  body.vs-epub :is(.img-text,.text-img,.img-text2,.text2-img,.img-text3,.text3-img) {
    display: block;
  }
  body.vs-epub :is(.img-text,.text-img,.img-text2,.text2-img,.img-text3,.text3-img) > :is(img,figure) {
    max-width: 45%;
    max-height: 16em;
    width: auto;
    inline-size: auto;    /* img-text3 の inline-size:100% を打ち消す */
    block-size: auto;
  }
  body.vs-epub :is(.img-text,.img-text2,.img-text3) > :is(img,figure) { float: left;  margin: 0 1em 0.5em 0; }
  body.vs-epub :is(.text-img,.text2-img,.text3-img) > :is(img,figure) { float: right; margin: 0 0 0.5em 1em; }
  body.vs-epub :is(.img-text,.text-img,.img-text2,.text2-img,.img-text3,.text3-img)::after {
    content: ""; display: block; clear: both;
  }
  ```
- 数値（`38%` / `45%` / `13em` / `16em`）は実機（iPhone/iPad）プレビューで微調整する初期値。

> 補足: `:is()` は Kindle KFX で概ね解されるが、未対応端末を考慮し、必要なら実装時にセレクタを個別展開する（過剰一致がない素直なリストのため展開は機械的）。

---

## 3. 数式単位の巨大化（③ tables / inline 数式）

### 3-1. 原因

単位（`$\text{A}$` `$\text{kg}$` 等）は前処理で MathJax SVG 画像化され、`<img class="vs-math vs-math-inline" style="vertical-align:…ex; width:…ex; height:…ex">` として埋め込まれる（`math_transformer.rb` §A）。**寸法が `ex` 単位**で、Kindle は `<img>` の `ex` を解さず、SVG ルートは `viewBox` のみで固有 px を持たない（`mathjax_to_svg.mjs` が ex 寸法を `data-vs-*` へ退避済み）ため、**既定の巨大サイズ**で描画される。

### 3-2. 修正（HTML 後処理 `convert_math_units_for_epub!`）

EPUB 章 HTML 内の `img.vs-math-inline` と `figure.vs-math-display img` の inline `style` を走査し、**`ex` 値を `em` へ変換**する（Kindle が解す `em`）。変換係数は CSS 慣用の `1ex ≈ 0.5em`:

```
height: 2.262ex  →  height: 1.131em
vertical-align: -0.566ex  →  vertical-align: -0.283em
width: 1.2ex  →  width: 0.6em
```

- 係数 `EX_TO_EM = 0.5` を定数化（MathJax SVG の ex/em 比の慣用値。視覚的に本文サイズへ収まる近似で、EPUB では許容）。
- `display` 数式の `width`/`height` も同様に ex→em 変換し、既存の `max-width: 100%`（`components.css`）と併せて段幅に収める。
- 単位以外の inline 数式（分数・根号など）にも一律に効く（同じ `vs-math-inline` 経路のため）。

> **v2 改訂（表内の単位記号が小さすぎた）**: Kindle は多列の表を縮小しがちで、単純な ×0.5 だと表セル内の単位記号（`$\text{A}$` 等）が読めないほど小さくなった。**表セル（`td`/`th`）内の inline 数式に限り**、換算後の `height` が `MIN_TABLE_MATH_EM`（=1.0em）未満になる場合は `height` がその値になるよう**全寸法を等比拡大**する（`math_in_table?` で判定）。表外の inline 数式は ×0.5 のまま（本文サイズ維持）。

### 3-3. CSS セーフティネット（`body.vs-epub` ガード・`components.css`）

万一 inline style が無視される端末でも破綻させないため、上限を課す:

```css
body.vs-epub img.vs-math-inline { max-height: 1.8em; width: auto; }
body.vs-epub figure.vs-math-display img { max-width: 100%; height: auto; }
```

> PDF は `ex` を正しく解す（Vivliostyle/Chromium）ため、PDF 経路の inline style（`ex`）は不変のまま。本変換は EPUB の HTML にのみ適用する。

---

## 4. コード行番号（④ codes）→ 2 列テーブル方式

### 4-1. 原因

Prism の行番号は `.line-numbers-rows { position: absolute; left: -3.8em }` ＋ 親 `pre { position: relative; padding-left }`（`prism.css`）で左ガターを作る。Kindle は絶対配置を解さず、ガターが崩れる（番号が消える/積み重なる）。

### 4-2. 採用方式（合意済み）

**2 列テーブル（番号セル｜コードセル、1 論理行 = 1 行）**。Kindle が確実に解す `<table>` で、折り返し時も番号が論理行に上揃えで留まり、iPhone/iPad とも対応が崩れない（PDF のガター挙動に最も忠実）。簡易なインライン番号方式は折り返し続き行の整列とコピー混入が弱点のため不採用。

### 4-3. 変換（HTML 後処理 `convert_code_blocks_for_epub!`）

各 `pre.line-numbers`（`<pre class="language-x line-numbers"><code>…\n 区切りのトークン span…<span class="line-numbers-rows">…</span></code></pre>`）を次へ変換する:

1. 末尾の `.line-numbers-rows`（絶対配置ガター）を**除去**する。
2. `<code>` の中身を**論理行（`\n` 区切り）に分割**する。Prism のトークン `<span class="token …">` を**保持**したまま分割する。複数行に跨るトークン（ブロックコメント・複数行文字列）は、各行で**開いている span を閉じ、次行で開き直す**（行スプリットの定石）。
3. 2 列テーブルを構築する:
   ```html
   <table class="vs-code-epub" aria-label="ソースコード">
     <tbody>
       <tr><td class="vs-code-num">1</td><td class="vs-code-line"><code class="language-x">…1行目（token span 保持）…</code></td></tr>
       …
     </tbody>
   </table>
   ```
4. 言語クラス（`language-x`）・キャプション等の周辺要素は維持する。
5. **フォールバック**: 分割に失敗（トークン整合が取れない等）した場合は当該ブロックを変換せず元のまま残し、警告ログのみ（縮退）。

### 4-4. CSS（`body.vs-epub` ガード・`code.css`）

```css
body.vs-epub table.vs-code-epub {
  width: 100%;
  border-collapse: collapse;
  font-family: var(--code-font, monospace);
  font-size: 0.85em;
}
body.vs-epub .vs-code-num {
  width: 2.5em;
  text-align: right;
  vertical-align: top;          /* 折り返しても番号は上端に留まる */
  padding-right: 0.6em;
  color: #999;
  border-right: 1px solid #ccc;
  user-select: none;
  white-space: nowrap;
}
body.vs-epub .vs-code-line {
  vertical-align: top;
  padding-left: 0.6em;
}
body.vs-epub .vs-code-line code {
  white-space: pre-wrap;        /* 長い行は折り返す（横クリップ回避） */
  word-break: break-word;
}
```

### 4-4b. v2 改訂（行高・揃え・余白）

実機で「行ごとに高さが違う／番号は上揃えだがコードは中央揃え／余白が広い」課題が出たため:
- **上下中央で統一**: `.vs-code-num` / `.vs-code-line` とも `vertical-align: middle`（番号もコードも上下中央）。
- **空行の高さを確保**: 空の論理行は `&#160;`（nbsp）で 1 行ぶんの高さを保ち、行高の不揃い（空セルの潰れ）を防ぐ（`build_code_row`）。
- **余白を圧縮**: `table.vs-code-epub` に `line-height: 1.4` / `margin: 0.4em 0`、セルの上下 `padding` を 0 にして詰める。

### 4-5. 挙動と制約

- **折り返し（例: 38 行目）**: コードセル内で折り返し、番号は上揃えで留まる → iPhone/iPad とも番号↔行の対応が保たれる。
- **制約（明記）**: コピー時に番号列が混ざりうる（リフロー EPUB 共通の制約）。番号をコピーから除く唯一の手段は CSS カウンタだが Kindle で不安定なため採らない。狭画面でのテーブル詰まりは実機プレビューで確認し、`font-size`/`width` を調整する。
- PDF は Prism の絶対配置ガターをそのまま使う（Vivliostyle で正常）。本変換は EPUB の HTML にのみ適用。

---

## 5. 設定と適用範囲

- epub ターゲットで**常時有効**（追加設定なし）。
- CSS は `stylesheets/` と `lib/project_scaffold/stylesheets/` の**両方**に反映（§1-3）。
- `book.yml` での ON/OFF・係数設定は将来拡張点としてコメントを残すに留める（実装しない）。

---

## 6. テスト

### 6-1. 軽量・OS 非依存（`rake test`）

EpubBuilder の各変換を Nokogiri ベースのユニットで検証（フィクスチャ HTML）:
- `mark_body_for_epub!`: `<body>` に `vs-epub` クラスが付く。
- `convert_math_units_for_epub!`: `vs-math-inline` の `style` の `ex` 値が `em`（×0.5）へ変換される。display 数式も同様。
- `convert_code_blocks_for_epub!`: `pre.line-numbers` が `table.vs-code-epub` へ変換され、行数ぶんの `<tr>`・番号 1..N・トークン span 保持・`.line-numbers-rows` 除去を確認。複数行トークンの行スプリットも検証。分割失敗時に元のまま残るフォールバックも検証。

### 6-2. 成果物検査（実ビルド・既存スイートへ追加）

`target_consistency_test`（`rake test:targets`）の EPUB 検査に追加:
- EPUB の本文に `position: absolute` の `.line-numbers-rows` が残っていない（コードはテーブル化されている）。
- `vs-math-inline` の寸法に `ex` が残っていない（`em` 化されている）。

### 6-3. 実機レイアウト確認（手動・opt-in）

Kindle Previewer 3 の**端末プレビュー（iPhone / iPad / Kindle）**で 4 種の見栄えを目視確認する（自動アサート困難なため手動）。`rake test:kindle`（変換成功＋画像系警告ゼロ）は既存のまま回帰ガードとして維持。

---

## 7. 実装順序

1. **§1 機構**: `mark_body_for_epub!` と `generate_epub_entries!` への 3 パス追加。
2. **§2 画像**: `components.css` / `layout-utils.css` に `body.vs-epub` ガード CSS（＋scaffold 反映）。
3. **§3 数式**: `convert_math_units_for_epub!`（ex→em）＋ `components.css` セーフティネット（＋scaffold）。
4. **§4 コード**: `convert_code_blocks_for_epub!`（テーブル化・行スプリット）＋ `code.css`（＋scaffold）。
5. **§6-1/6-2 テスト**。
6. 全章ビルド → Kindle Previewer 端末プレビューで iPhone/iPad の見栄えを確認 → 数値（`%`/`em`/`font-size`）を微調整 → クローズ判定。

---

## 8. 影響と非目標

- **影響**: EPUB の表示のみ。PDF / print_pdf は不変（§0 方針 1）。
- **非目標**:
  - PDF レイアウトの変更（しない）。
  - Kindle 以外のリーダー個別最適化（`float`/`%`/`em`/`table` は汎用的なため不要）。
  - コードのコピー時の行番号除去（リフロー制約・§4-5）。
  - 折り返さない横スクロールコード（Kindle 非対応）。
  - 数式の厳密な ex→em（端末フォント非依存の近似 ×0.5 で十分・§3-2）。
