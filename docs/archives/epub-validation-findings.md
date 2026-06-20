# EPUB 構造検証（epubcheck）不具合の調査記録

> **位置づけ**: 本書は「修正仕様書」ではなく**調査記録（findings）**です。
> EP-02（`epubcheck` による EPUB 構造検証）を有効化した結果、生成 EPUB に
> 多数の構造 ERROR が見つかりました。後日この記録を土台に
> 「EPUB 生成パイプライン修正仕様書」を起こすための、不具合の分類・根本原因・
> 修正方針のたたき台です。
>
> **2026-06-13 追記**: 本記録を基に修正仕様書 `docs/specs/epub-pipeline-fix-spec.md` を
> 作成した。その際の追加調査で本書の推定 2 件が覆っている — ①雛形 CSS 混入の真因は
> 生成器のパス参照ではなく **`vivliostyle.config.epub.js` に `copyAsset` 指定が無い**こと
> （Vivliostyle CLI が CWD 以下の全アセットを EPUB に同梱していた）、② §3.1 案 B
> （`@media print` で包む）は **epubcheck がマージンボックス構文自体を拒否するため不成立**
> （最小 EPUB 実験で確認）。実装時は仕様書側を正とすること。
>
> - 調査日: 2026-06-13
> - 検証ツール: EPUBCheck v5.3.0（`brew install epubcheck`）
> - 対象: マニュアル（本リポジトリ自身を書籍として）`targets: epub` でフルビルドした
>   `vivlio_starter_v1.0.0.epub`
> - 関連テスト: `test/vivlio_starter/release/epub_validation_test.rb`（EP-01 / EP-02）
> - 関連仕様: `docs/specs/test-suite-expansion-spec.md` §13

---

## 1. 再現手順

```bash
# epubcheck を導入（未導入なら）
brew install epubcheck

# EP-01（epub ビルド）+ EP-02（epubcheck）を実行
ruby -Ilib -Itest test/vivlio_starter/release/epub_validation_test.rb
#   または rake test:manual（EP を含む）
```

EP-01（epub が生成され `.epub` が出力される）は **成功**。
EP-02（`FATAL`/`ERROR` が 0 件）は **失敗**（ERROR 35 件・WARNING 0 件・FATAL 0 件）。

EP-02 のアサーションは「`epubcheck` 出力に `^FATAL` / `^ERROR` 行が無いこと」。
現状はこの検証が EPUB 生成側の実不具合を正しく検出している状態であり、
**EP-02 を緩めるのではなく、生成側を直すべき**段階。

---

## 2. エラー総括

| コード | 件数 | 概要 |
|---|---:|---|
| `CSS-008` | 26 | `@page` のマージンボックス（`@bottom-center` 等）を epubcheck の CSS パーサが拒否 |
| `RSC-005` | 7 | XHTML 構造エラー（脚注 ID `fn1` 重複 4 件 / `<img>` 寸法が非整数 3 件） |
| `RSC-007` | 2 | EPUB 内に存在しないリソース参照（gem 同梱 webp） |
| **合計** | **35** | |

### 2.1 「二重同梱」という横断的な構造問題

CSS-008 と RSC-007 の多くは、**同じスタイルシートが 2 か所に同梱**されていることに起因する。

- `EPUB/stylesheets/page-settings.css`（プロジェクト本来の配置・正）
- `EPUB/lib/project_scaffold/stylesheets/page-settings.css`（**gem 雛形パスが EPUB に混入・誤**）

二重化が確認できたファイル: `page-settings.css` / `colophon.css` / `titlepage.css` /
`part-title.css` / `theme.css`。これらはいずれも**生成される特殊ページ**
（タイトルページ・奥付・パートタイトル）が使う CSS であり、本文章（`chapter.css`）が
読む CSS とは別系統。本文 xhtml の `<link>` は `stylesheets/theme.css` 等の相対参照のみで、
`lib/project_scaffold/...` を参照していない（51-doctor.xhtml で確認済み）。

→ **推定根本原因**: タイトルページ／奥付／パートタイトルの生成器
（`create:titlepage` / `create:colophon` / `create:cover`、`Build::PartTitleGenerator` など）が、
特殊ページの HTML から **gem 同梱の雛形スタイルシートパス（`lib/project_scaffold/stylesheets/...`）**
を参照しているため、EPUB パッケージにその実体が取り込まれている。
（要確認：生成器が参照する CSS パスの解決ロジック）

この 1 点を解消すると、`lib/project_scaffold/...` 側の CSS-008（13 件）と RSC-007（2 件）の
**計 15 件が一掃**される見込み。

---

## 3. クラス別 根本原因と修正方針

### 3.1 CSS-008（26 件）— `@page` マージンボックスを EPUB に流用

**現象**: `@page { @bottom-center { ... } }` 等、CSS Paged Media のマージンボックス記述を
epubcheck の CSS パーサが構文エラーとして拒否する。

```
ERROR(CSS-008): .../page-settings.css(159,3):
  CSSパース中にエラー: トークン "@bottom-center" はここでは使用できません.
```

該当ファイル（プロジェクト本来側）: `page-settings.css`（7 か所）/ `colophon.css`（2）/
`titlepage.css`（2）/ `part-title.css`（2）。

**評価**: `@page` のマージンボックスはノンブル・柱など**印刷組版（PDF）専用**の機構で、
リフロー型 EPUB では意味を持たない。PDF 用 CSS をそのまま EPUB に同梱しているのが原因。

**修正方針（案）**:
1. EPUB ビルド時は `@page { ... }`（特にマージンボックス）を含む宣言を**除外/サニタイズ**する。
   - 案 A: EPUB 専用のスタイルシート集合を用意し、印刷専用ルールを含めない。
   - 案 B: 既存 CSS の `@page` ブロックを `@media print` で囲い、EPUB では効かせない
     （ただし epubcheck が `@media print` 内の `@page` をどう扱うか要確認）。
   - 案 C: EPUB 生成ステップで CSS を後処理し、`@page` マージンボックスを物理的に削る。
2. まず §2.1 の二重同梱を解消し、対象を「プロジェクト本来側の `@page` だけ」に絞ってから着手する。

### 3.2 RSC-005a（4 件）— 脚注 ID `fn1` の重複

**現象**: 1 つの脚注が、インライン参照とページ脚注本体の**両方に同一 `id="fn1"`** を付与している。

```html
<span role="doc-footnote" class="page-footnote page-footnote-inline" id="fn1">…</span>
<aside role="doc-footnote" class="page-footnote page-footnote-print" id="fn1" data-footnote-number="1">…</aside>
```

XHTML では `id` は文書内で一意でなければならず、同一ファイル内の重複は ERROR。
51-doctor.xhtml / 99-postface.xhtml で各 2 件。

**担当実装（推定）**: `cli/post_process/footnote_converter.rb`（章末脚注 → ページ脚注変換）。

**修正方針（案）**: 参照側と本体側で **異なる ID** を振る標準的な脚注パターンへ。
- 参照（インライン）: `id="fnref1"`（本体へ `href="#fn1"`）
- 本体（aside）: `id="fn1"`（参照へ `href="#fnref1"` で戻る）

PDF 出力では従来も両者に同一 id でも実害が無かったため顕在化していなかった
（PDF はアウトライン/リンク解決が緩い）。EPUB（厳密な XHTML）で初めて問題化。
→ PDF 側の挙動に影響しないことを回帰確認しつつ修正する。

### 3.3 RSC-005b（3 件）— `<img>` の width/height が非整数

**現象**: techbook モードで絵文字を画像化した際、`<img>` に CSS 単位付きの寸法属性が付く。

```html
<img src="stylesheets/twemoji/1f501.webp" alt="🔁" class="emoji vs-emoji"
     width="1em" height="1em" style="vertical-align: -0.15em;" />
```

XHTML/HTML の `width`/`height` **属性**は整数ピクセルのみ許容され、`1em` は不正。

**担当実装（推定）**: 絵文字画像化（Twemoji 置換）を行う前処理／後処理
（techbook 関連。`run_techbook_post_process` 周辺、または emoji 置換器）。

**修正方針（案）**: 寸法は**属性ではなく `style` で**指定する。
- 修正例: `style="width:1em;height:1em;vertical-align:-0.15em;"`（`width`/`height` 属性は削除）

→ 同じ絵文字記法は全章に多数あるため、epubcheck が報告したのは一部だが、
**同パターンは横断的**。置換器側で一括修正するのが妥当。

### 3.4 RSC-007（2 件）— gem 同梱 webp の参照欠落

**現象**: 混入した `lib/project_scaffold/stylesheets/theme.css` が、同梱されていない
雛形画像を参照している。

```
ERROR(RSC-007): .../lib/project_scaffold/stylesheets/theme.css(74,3):
  参照リソース ".../images/bundled/sakura_landscape.webp" が EPUB 内に見つかりません.
```

**評価**: §2.1 の二重同梱の副作用。雛形 `theme.css` は gem 内の `images/bundled/...` を
参照するが、その実体は EPUB に入らないため未解決参照になる。
**§2.1（雛形スタイルシート混入）の解消で同時に消える。**

---

## 4. 修正の優先順位（提案）

| 優先 | 対応 | 解消見込み件数 | 想定難度 |
|---|---|---:|---|
| 1 | §2.1 雛形スタイルシート混入の解消（生成器の CSS パス見直し） | 15（CSS-008×13 + RSC-007×2） | 中（生成器のパス解決調査） |
| 2 | §3.3 `<img>` 寸法を `style` 化（属性削除） | 3＋潜在多数 | 低（置換器の出力修正） |
| 3 | §3.2 脚注 ID の参照/本体分離（`fnref` 採番） | 4 | 中（PDF 非回帰の確認込み） |
| 4 | §3.1 プロジェクト本来側 `@page` の EPUB 除外 | 13 | 中〜高（CSS 方針の決定） |

優先 1・2 だけで 18／35 件が解消する見込み。残りは脚注 ID（4）と `@page`（13）。

---

## 5. EP-02 / RC への影響

- ~~当面 **EPUB は RC ゲートから外す**~~ → **2026-06-13 解消・復帰**（§7.4）。
  Fix-1〜7 で ERROR 0 件を達成したため、EP-02（`test:manual`→`test:release` に内包）を
  **RC 品質ゲートへ正式復帰**させた。別途の除外機構は存在せず、ドキュメント記述のみの
  扱いだった。
- EP-02 のアサーション自体は妥当（実不具合を検出）。**テストは緩めなかった**（生成側を直した）。
- 修正は別仕様書 `epub-pipeline-fix-spec.md`（Fix-1〜7）として起こし、クラス単位で
  着手 → 各クラス解消ごとに EP-02 の ERROR 件数が単調減少することを進捗指標にした。

---

## 6. 未確認事項（修正仕様書で詰める）

1. 特殊ページ生成器が `lib/project_scaffold/stylesheets/...` を参照する正確な箇所と理由
   （フォールバック？絶対パス解決？）。
2. epubcheck が `@media print { @page { … } }` を許容するか（§3.1 案 B の可否）。
3. 絵文字 `<img>` の `width="1em"` を出力している正確な実装箇所（前処理か後処理か）。
4. 脚注 ID 変更が PDF のページ脚注リンク・しおり・バックリンク重複排除（Step 8）に
   影響しないか。
5. 322MB という EPUB の肥大（本検証で生成された `.epub`）— 画像最適化が EPUB 経路で
   効いているか。本記録の主題（構造 ERROR）とは別だが、EPUB 品質の課題として併記。

---

## 7. 2026-06-13 追記：Fix-1〜4 実装後の再検証で判明した追加エラー（findings の取りこぼし）

仕様書 `epub-pipeline-fix-spec.md` の Fix-1〜4 を実装し、実ビルド（単章 `vs build 11` /
全章フルビルド）+ `epubcheck v5.3.0` で再検証した結果、**Fix-1〜4 は設計どおり機能**して
いることを確認した（lib/** 混入・RSC-007・脚注 id 重複・絵文字 width 属性・
`@bottom-*`/`@top-*` マージンボックスはすべて解消）。

しかし epubcheck の ERROR は **0 件にならず、全章で 47 件**（単章で 39 件）残った。
内訳を精査したところ、**本 findings の §2 総括（35 件）が当時取りこぼしていた
別カテゴリ**であり、Fix-1〜4 が新たに生んだものではない（数字始まりファイル名・
テーブル整列・`@footnote` はいずれも以前から存在した構造）。

### 7.1 残存エラーの実測内訳（全章フルビルド）

| コード | 件数 | 発生源 | 性質 |
|---|---:|---|---|
| `CSS-008` | 2 | `EPUB/stylesheets/page-settings.css` の `@footnote { … }` at-rule | Fix-2 の `MARGIN_BOX_PATTERN` が `@footnote` を未対応（取りこぼし） |
| `RSC-005`（align） | 35 | `11-workflow.xhtml` 等のテーブル `<th align="left">` / `<td align="…">` | Markdown テーブルの整列指定が XHTML5 で不許可の `align` 属性に変換されている |
| `RSC-005`（NCName） | 10 | `EPUB/content.opf` の `<item id="00-prefacexhtml">` ほか | vivliostyle CLI が**数字始まりのファイル名から id を生成**。NCName は数字で始まれない |
| **合計** | **47** | | |

### 7.2 各カテゴリの根本原因と修正方針

**(A) CSS-008 `@footnote`（2 件）**
`@footnote` は Vivliostyle が `float: footnote` 要素を収めるためのマージン at-rule で、
`@bottom-center` 等と同じく epubcheck の CSS パーサが拒否する。Fix-2 の
`MARGIN_BOX_PATTERN`（`@(top|bottom|left|right)-…`）が `@footnote` を含んでいないため
残存した。→ **Fix-2 の自然な完成**として、サニタイズ対象の at-rule に `@footnote` を加える。

**(B) RSC-005 `align` 属性（35 件）**
VFM（Markdown → HTML）がテーブルの列整列（`|:--|`）を `<th align="left">` /
`<td align="right">` という**プレゼンテーション属性**として出力する。HTML/XHTML5 では
`align` 属性は廃止されており epubcheck が ERROR とする。PDF（Vivliostyle）はこの属性を
許容するため顕在化していなかった。→ **EPUB 経路でのみ** xhtml の `align="x"` を
`style="text-align:x"` へ変換する（Fix-3 と同型の EPUB 専用 HTML 後処理。PDF に無影響）。

**(C) RSC-005 content.opf NCName（10 件）**
vivliostyle CLI が manifest item の id を href から機械生成する際、ファイル名が
`00-preface` のように**数字で始まる**ため、生成 id `00-prefacexhtml` が NCName 規則
（先頭は英字または `_`）に違反する。spine の `idref` も同じ値を参照するため idref 側も
ERROR になる。→ 生成後の `content.opf` に対し、**数字始まりの id とそれを参照する
idref に接頭辞を付与**する後処理（`stabilize_epub_identifier!` と同型の
unzip → 修正 → zip 差し替え。id と idref の整合を保つ）。

### 7.3 再検証コマンド（参考）

```bash
# 全章
ruby -Ilib -Itest test/vivlio_starter/release/epub_validation_test.rb
# 単章（targets を一時的に epub へ）
vs build 11 --no-clean && epubcheck 11-workflow.epub 2>&1 | grep -cE '^(FATAL|ERROR)'
```

→ 上記 (A)(B)(C) を仕様書 `epub-pipeline-fix-spec.md` の **Fix-5〜7** として追記し、
実装する（本追記を受けて仕様書を更新済み）。

### 7.4 解消確認（2026-06-13）

Fix-5〜7 を実装し、最終検証で **DoD を達成**した:

- 全章フルビルド（EP-01/EP-02）: green。`epubcheck` = **FATAL 0 / ERROR 0 / WARNING 0**
- 単章（`vs build 11` → `11-workflow.epub`）: FATAL/ERROR **0 件**（39 → 0）
- EPUB サイズ: 322MB → **59MB**（7,625 ファイル。残量は fonts/twemoji = P2 スコープ）
- `rake test`: 1,088 件 green（EPF-01〜08 含む）

これにより本 findings が追跡してきた EPUB 構造 ERROR（当初 35 件 + 取りこぼし 47 件）は
**すべて解消**。EP-02 は **RC 品質ゲートへ正式復帰**（`test:manual`→`test:release` に内包。
§5）。CHANGELOG「既知の不具合」からも削除済み。

### 7.5 サイズ最適化（P2。2026-06-13 ユーザー判断のうえ実装）

ERROR 0 達成後、ユーザー判断（技術書は 明朝/ゴシック/等幅 の一般フォントで十分・
フォント非埋め込みを既定）を受けて P2 を実装（仕様書 §3）:

- **P2-1 フォント非埋め込み（既定）**: `embed_fonts?`（既定 false）で `stylesheets/fonts/**`
  を除外し、EPUB 内 CSS から `@font-face` と `@import url("fonts/…")` を除去（RSC-007 回避）。
  css_updater が `--font-*` に generic フォールバック（明朝=serif/ゴシック=sans-serif/
  コード=monospace）を付与し category を保つ。v2.0 で book.yml オプション化予定（埋め込み
  経路はコード維持）。**−51MB**。
- **P2-2 twemoji 非同梱（Fix-8）**: 絵文字画像化は **PDF 専用の Type 3 対策**で EPUB には
  不要（EPUB に Type 3 は無くリーダーのカラー絵文字で描画）。EPUB 経路で `<img>` を
  プレーン絵文字へ復元し twemoji マスターを除外。囲み数字は画像維持。

結果: EPUB サイズ **59MB → 25MB**（ERROR 0 維持）。`rake test` 1,098 件 green
（EPF-01〜11・CU-01〜05 含む）。

> §7.4 の「残量は fonts/twemoji = P2 スコープ」は本節で解消済み。
