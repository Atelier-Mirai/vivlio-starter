# 数式 SVG 化・扉絵/節絵 画像化 修正仕様書

> 作成日: 2026-06-14
> ステータス: **A 承認済み（2026-06-14）・実装待ち／B 合成 SVG 方式で再提案（要承認）**
> 対象不具合: `build-output-bugfix-spec.md` ④-A（EPUB 数式露出）／④-B（表セル内数式）／③-a（EPUB 扉絵・節絵未表示）
> 関連調査: `docs/specs/epub-kindle-compatibility-report.md`

`build-output-bugfix-spec.md` で「Kindle 互換性のため別途検討」として保留した 3 件
（④-A・④-B・③-a）について、**数式を SVG 画像化**し、**扉絵（h1 frontispiece）・節絵（h2 ornament）を
インライン画像化**することで恒久対応する方針をまとめる。

この方針は、保留時点の懸念（Kindle の MathML / 背景画像非対応）を回避する。
SVG・`<img>` は Kindle を含む全リーダーで確実に描画されるためである
（`epub-kindle-compatibility-report.md` §3・§6 の「Kindle で確実なのはインライン `<img>`」に合致）。

---

## 0. 全体方針

| 項目 | 現状 | 本仕様の方針 | 効果 |
| --- | --- | --- | --- |
| 数式（インライン `\(…\)` / ブロック `$$…$$`） | Vivliostyle の MathJax が **PDF のみ**組版。EPUB は生 LaTeX 露出 | **前処理で LaTeX→SVG 化**し `<img>` として埋め込む | ④-A 解消（PDF・EPUB 共に SVG で同一描画） |
| 数式（GFM 表セル内 `$…$`） | VFM が span 化せず、**PDF・EPUB とも**生 LaTeX 露出 | 同上（前処理は VFM より前なので表セルにも効く） | ④-B 解消 |
| 扉絵（h1 frontispiece） | CSS 背景（`@page` + `background-attachment: fixed`）。EPUB 非表示 | **EPUB 専用後処理で「画像＋見出しを焼き込んだ合成 SVG」を注入** | ③-a 解消（PDF は現状の背景を維持） |
| 節絵（h2 ornament） | CSS 背景（`.section-topic h2::before`）。EPUB 非表示 | 同上 | ③-a 解消 |

設計上の二本柱:

1. **数式は「前処理（pre_process）」に一本化する。** 前処理は VFM（Markdown→HTML）より前に走り、
   PDF・EPUB の両経路が共有する Markdown を変換するため、**1 箇所の修正で PDF・EPUB・表セルを同時に解決**できる。
   Vivliostyle の MathJax 依存（PDF のみ・EPUB 非焼込）から脱却する。
2. **扉絵・節絵は「EPUB 専用後処理（post_process for epub）」に閉じる。** PDF の見栄え（全面背景の扉絵）は
   現状の CSS のまま維持し、リフロー EPUB だけ `<img>` 化する。PDF 経路へ副作用を出さない。

---

## A. 数式の SVG 化（④-A / ④-B）

### A-1. 現状の問題（再掲）

- **④-A**: VFM は `<span class="math" data-math-typeset>` に生 LaTeX を残し、Vivliostyle CLI 内蔵の
  MathJax が **レンダリング時に組版**する設計。PDF は描画されるが、`vivliostyle build --format epub` は
  MathJax の結果を XHTML に焼き込まないため、EPUB には生 LaTeX（`\(E=mc^2\)` / `$$…$$`）が露出する
  （生成 EPUB に `<math>` タグ 0 件）。
- **④-B**: GFM 表セル内の `$…$` は VFM が数式 span で包まないため `data-math-typeset` が付かず、
  **PDF でも** MathJax の対象外になり生 LaTeX が残る（表 94-1 で確認済み）。現状はサンプル原稿を
  Unicode 表記へ置換して回避している。

### A-2. 設計判断 — なぜ「前処理での SVG 化」か

| 案 | 対象範囲 | Kindle | 表セル | 備考 |
| --- | --- | --- | --- | --- |
| (現状) MathJax 実行時組版 | PDF のみ | — | ✗ | EPUB 焼込なし・表セル不可 |
| (1) EPUB 後処理で MathML 化（temml 等） | EPUB | △ 端末差で崩れ | ✗ | Kindle で不安定（report §6）。PDF・表セルは別対応が必要 |
| (2) **前処理で SVG 化（本仕様）** | **PDF・EPUB 共通** | **◎** | **◎** | 1 箇所で全解決。MathJax 依存を撤廃 |

- (2) は **PDF・EPUB・表セル内**の数式を **同一の SVG** で描画でき、Kindle を含む全リーダーで崩れない。
- SVG は数式をパス（ベクター）で表現するため、**フォント埋め込み不要**で EPUB に同梱でき、
  非埋め込みフォント方針（`epub_builder.rb` の `@font-face` 除去）とも干渉しない。
- 前処理は `MarkdownPreprocessor#run` のパイプライン内にあり、**コードブロック／インラインコードを
  `MarkdownUtils.extract_code_spans` で退避**してからテキスト変換する既存の枠組みに素直に乗る
  （`$` を含むコード例を誤変換しない）。

### A-3. 変換ツール — Node の MathJax（mathjax-full）※当初の `mathematical` から変更

LaTeX→SVG 変換は **Node 上の MathJax（npm パッケージ `mathjax-full`）を「ビルド時 SVG 生成器」として**用いる。
前処理（Ruby）から Node スクリプト `mathjax_to_svg.mjs` を呼び、LaTeX をまとめて SVG 化する。

- 入力: `[{ id, latex, display }]`（章内の全数式を 1 回の Node 呼び出しに束ねる）。
- 出力: `{ id: "<svg …>…</svg>" }`。`fontCache: 'none'` で各 SVG にグリフのパスを内包させ、
  外部フォント参照のない**自己完結 SVG**にする（EPUB 同梱・epubcheck で安全）。
- MathJax は SVG ルートに `style="vertical-align: …ex"`・`width="…ex"`・`height="…ex"` を付すため、
  これをそのまま `<img>` に写すと**本文フォント相対で正しいサイズ・ベースライン整列**が得られる。

> **当初 `mathematical` gem（lasem）を採用したが撤回した（2026-06-14）。** 理由は二つ。
> (1) **描画不具合**: lasem は `\langle`・`\rangle`・`\sqrt` 等（cmsy10/cmex10 系の記号・大型括弧・
>     根号）のグリフ対応付けを誤り、`⟨⟩` を `¿À`、根号を大きな `S` として出力する。
>     `FONTCONFIG_PATH` を正しく設定し同梱 Computer Modern フォントを解決できる状態でも直らず、
>     PDF・EPUB・rsvg の 3 レンダラすべてで同一の化けを確認（lasem 本体の限界）。
> (2) **配布性**: プリコンパイル版が Ruby 4.0 で配布元 CI の libruby 絶対パスを直リンクし dlopen 失敗。
> MathJax は記号を含む標準 LaTeX を正しく描画し（実機確認済み）、Node は Vivliostyle で既に必須、
> `mathjax-full` は純 JS（ネイティブビルド不要・数秒で導入）のため、配布性でも優れる。
> リーダー実行時の MathJax（EPUB 非対応＝④-A の元凶）とは別物で、ここでは**ビルド時に静的 SVG を焼き込む**点に注意。

### A-4. 出力形態 — 外部 SVG ファイル + `<img>`

数式は **外部 SVG ファイルに書き出し、`<img>` で参照**する（インライン `<svg>` 直挿しは採らない）。

```html
<!-- インライン数式 -->
<img class="vs-math vs-math-inline" src="images/math/<chapter>/<hash>.svg"
     alt="\(E=mc^2\)" style="vertical-align: -0.30ex; height: 1.05em;">

<!-- ディスプレイ数式（中央寄せブロック） -->
<figure class="vs-math vs-math-display">
  <img src="images/math/<chapter>/<hash>.svg" alt="$$\nu_0 = \frac{\phi}{h}$$">
</figure>
```

選定理由:

- **XHTML 妥当性（epubcheck）**: 外部 `<img>` は XHTML として安全。インライン `<svg>` は名前空間や
  属性の取り扱いで epubcheck ERROR を招きやすく、共有 HTML を肥大化させる。本 gem は
  epubcheck ERROR 0 を達成済み（`epub-pipeline-fix-spec.md`）でありこれを崩さない。
- **表セル内**: GFM 表セルにも `<img>` は問題なく入る（インラインブロックを避けられる）。
- **アクセシビリティ / Kindle フォールバック**: `alt` に元 LaTeX を残し、読み上げ・検索・万一の画像非表示時に資する。
- **同梱**: SVG を `stylesheets/images/` 配下（または `images/math/`）へ出力すれば、
  EPUB の `copyAsset`（`stylesheets/images` を除外していない）で同梱され得る（パスは実装時に確定）。

**ベースライン整列**: インライン数式は本文ベースラインに揃える必要がある。`mathematical` の
SVG 由来の高さ／深さ（viewBox）から `vertical-align`（ex 単位）と `height`（em 単位）を算出して
`style` に付与する。ディスプレイ数式は `figure` でブロック中央寄せにする。
（整列の微調整は実装時に PDF・主要リーダーで目視確認。**主要なリスク箇所**として A-7 に記載。）

**キャッシュ**: LaTeX 原文（＋表示種別 inline/display）の **ハッシュをファイル名**にし、同一式は再生成しない。
ビルド間の再利用も可能。`clean` 対象に含める（A-5）。

### A-5. 実装スコープ

1. **新規 `pre_process/math_transformer.rb` ＋ `pre_process/mathjax_to_svg.mjs`**
   - `$…$` / `$$…$$` / `\(…\)` / `\[…\]` を検出（コード退避済みテキストに対して適用）。
   - 章内の全数式をプレースホルダ化して収集 → Node スクリプト `mathjax_to_svg.mjs`（MathJax）へ
     **1 回の subprocess でまとめて渡し** SVG 化 → ファイル出力 → `<img>`（または `<figure><img>`）へ置換。
   - インライン/ディスプレイの判定（`$$`・`\[` はディスプレイ、`$`・`\(` はインライン）。
   - SVG 出力先ディレクトリ・相対パス・キャッシュを担う。整列は MathJax SVG の ex 値（vertical-align/
     width/height）をそのまま `<img>` へ写す（lasem のような自前ベースライン推定は不要）。
   - node / mathjax-full 未導入・描画失敗時は **本文を変えず元の記法を維持**してグレースフル縮退
     （生 LaTeX は Vivliostyle の MathJax 経路（PDF のみ）へ委ねる）。`log_warn` で通知。
2. **`MarkdownPreprocessor#run` にステップ追加**
   - `transform_math!` を新設し、`extract_code_spans` で退避 → 変換 → `restore_code_spans` の枠組みで実行
     （`transform_text_right_inlines!` 等と同パターン）。
   - 挿入位置: コードインクルード確定後（表セル内数式を確実に処理するため全文走査で効かせる）。
3. **`clean.rb`**: 生成 SVG ディレクトリ（`images/math/`）をクリーン対象に追加。
4. **`gemspec`**: ネイティブ拡張の gem 依存は不要（mathematical は撤回）。描画は Node の `mathjax-full`。
5. **`doctor`**: `mathjax` チェックを追加し、`vs doctor --fix` が `npm install -g mathjax-full` で導入
   （playwright と同方式）。「表セル内でも数式が使える」旨に更新（④-B の回避メモを置換）。

### A-6. 既存仕様との関係

- ④-B の「表セル内では数式を避ける／Unicode 化で回避」という暫定方針は **不要になる**
  （表セルでも SVG で描画されるため）。サンプル原稿（表 94-1）の Unicode 置換は元に戻してよい
  （戻すか否かは原稿側判断。コードは両対応）。
- `data-math-typeset` span を前処理段階で消費するため、Vivliostyle の MathJax は数式に対して無作用になる
  （MathJax 設定自体は他用途がなければ撤去可能だが、フォールバック経路を残すため**当面は温存**）。

### A-7. 影響範囲・リスク・テスト方針

- **影響範囲**: 前処理に閉じる（PDF・EPUB 双方に同一 SVG が乗る）。Vivliostyle 設定・後処理は不変。
- **リスク**:
  1. **PDF の見た目変化**（MathJax 組版 → SVG 画像）。フォント・サイズ・行内整列が変わるため、
     `rake test:layout` の実ビルドで PDF を目視確認する。**最大の検証ポイント**。
  2. **インライン整列**（ベースライン）。式ごとに `vertical-align` を正しく出せるか。代表式で検証。
  3. **ネイティブ依存**のビルド失敗。CI / 開発者環境での導入確認。失敗時フォールバックの動作確認。
  4. SVG 数（式が多い書籍）でのビルド時間・ファイル数増。キャッシュで緩和。
- **テスト**:
  - 単体: `math_transformer` がインライン/ディスプレイ/表セル/コード退避（`$` を含むコード非変換）を
    正しく扱うこと。`mathematical` 未導入時に span へフォールバックすること。
  - 統合: `test:layout` で PDF に数式 SVG が描画されること、EPUB（XHTML）に `<img>` が入り
    生 LaTeX が残らないこと（`<span data-math-typeset>` が EPUB に出ないこと）。
  - epubcheck ERROR 0 維持。表セル内数式（旧 ④-B 再現原稿）が PDF・EPUB とも描画されること。

---

## B. 扉絵（h1）・節絵（h2）の EPUB 画像化（③-a）

### B-1. 現状の問題（再掲）

- 扉絵は `@page :nth(1)` の `background-image: var(--frontispiece-image)` ＋
  `background-attachment: fixed`（`stylesheets/image-header.css:12-18`）で、固定ページ寸法前提のフルブリード背景。
- 節絵は `.section-topic h2::before` の `background-image: var(--section-bg-image)`（同 `:134-143`）。
- いずれも **リフロー型 EPUB では `fixed`・固定寸法背景が描画されない**（report §3・§4）。画像実体は EPUB に同梱されるが見えない。
- 著者希望は「h1＝全面の扉絵に見出しを重ねる／h2＝上部に飾り画像」。

**当初案（インライン `<img>` を見出しと別に置く＝report §4 案 C）の却下理由**:
飾り画像と見出しテキストが**上下に分離**すると、その絵が「どの章・節の扉なのか」が伝わらず、
**見出しの役割を果たさない**（単に桜の絵が置いてあるだけになる）。
報告書 §3 のとおり Kindle は CSS の重ね合わせ（`position`）も背景も非対応のため、
HTML/CSS 側で「絵の上に見出しを重ねる」ことはできない。

### B-2. 設計判断 — 「画像＋見出しを焼き込んだ合成 SVG」を生成して注入する

絵の上に見出しを重ねた状態を Kindle でも確実に出すには、**重ね合わせを SVG の中で完結させ、
単一の画像として配置する**のが現実解。利用者提案のとおり、次の構造の合成 SVG を章・節ごとに生成する:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 W H" role="img" aria-label="第1章 春のお花見">
  <!-- 飾り画像を raster のまま data URI で埋め込む（外部参照は不可・B-4 参照） -->
  <image href="data:image/webp;base64,…" x="0" y="0" width="W" height="H"/>
  <!-- 見出しを text タグとして絵の上に重ねる -->
  <text class="vs-chapter-number" x="…" y="…">第1章</text>
  <text class="vs-chapter-title"  x="…" y="…">春のお花見</text>
</svg>
```

- **絵と見出しが 1 枚の画像として一体化**するので、Kindle を含む全リーダーで「飾り絵に見出しが重なった扉」が
  そのまま描画される。重ね合わせ・背景の非対応を**完全に回避**する。
- ベクター（SVG）なので拡大しても見出し文字が劣化しない（埋め込み raster は元解像度どおり）。
- 「力技で美しくはない」が、リーダー間差を最小化できる堅牢な方式。

HTML への配置（**見出しの意味と目次生成を両立**させる）:

```html
<h1 class="vs-image-heading-epub">
  <span class="vs-visually-hidden">第1章 春のお花見</span>   <!-- nav 生成・読み上げ用の実テキスト -->
  <img src="<chapter>/_frontispiece.svg" alt="" />            <!-- 視覚は合成 SVG が担う -->
</h1>
```

- 見出しは依然 `<h1>`/`<h2>` 要素で、**テキスト内容（番号＋タイトル）を保持**する。
  EPUB のナビゲーション（nav.xhtml）は Vivliostyle が**見出しのテキスト内容から**生成するため、
  これが無いと目次タイトルが空になる。実テキストは `.vs-visually-hidden`（clip 法）で視覚的にのみ隠す。
- `<img alt="">`（合成 SVG 側の `aria-label` と重複させない。視覚は SVG、機械可読テキストは span）。
- 万一リーダーが `.vs-visually-hidden` を無視した場合は、見出しテキストが SVG の近傍に素のテキストとして
  出る（＝当初案 C 相当へ自然劣化）。**「意味の無い飾り絵だけ」よりは劣化として許容できる**安全側設計。

### B-3. 設計判断 — なぜ raster を SVG に埋め込むか（data URI 必須）

`<img src="...svg">` として読み込まれた SVG の内部から**外部リソース（画像・フォント）を参照すると、
多くのリーダー／ブラウザはセキュリティ上それをロードしない**。したがって飾り画像は SVG 内に
**base64 data URI で埋め込む**（利用者の言う「実体は jpg 埋め込み画像」）。これにより合成 SVG は
自己完結し、参照切れ（RSC-007）も起きない。

- 埋め込む raster は既存の扉絵 portrait／節絵 landscape バリアント（`*_portrait.webp` / `*_landscape.webp`）。
- 見出し文字は `<text>` タグ。フォントは book の見出しフォントを `font-family` に指定しつつ、
  リーダーにフォントが無い場合のためにフォントスタック（フォールバック）を併記する。
- **フォントは埋め込まず、リーダー標準フォントに委ねる（2026-06-14 決定）。** これは EPUB の現行方針
  （本文含めフォント非埋め込み・レンダリングはリーダーに委ねる）と一貫させるもの。
  リーダーにより字形が変わり得るが許容する（B-7 リスク参照）。
- 字形の完全一致が要る場合は見出しの**ベクターパス化**または**フォントサブセット埋め込み**が必要だが、
  本件は **v2.0 で予定するフォント埋め込みオプション**に合わせて実装する。そのオプション有効時に、本文・見出しの
  埋め込みとあわせて合成 SVG の見出しもパス化／フォント埋め込みへ切り替える。**現段階では `<text>`＋標準フォントで足りる。**

### B-4. 画像・見出しテキストの取得元

- **画像**: 扉絵 portrait／節絵 landscape の実体は解決済みで、`css_updater.rb#update_theme_css` が
  theme.css の `--frontispiece-image` / `--section-bg-image` に `url("images/…webp")` として埋めている。
  合成 SVG 生成時は**この解決結果（または ThemeImageResolver）を単一の参照元**として raster を読み、base64 化する
  （PDF と同じ画像を使う・二重解決を避ける）。
- **見出しテキスト**: 対象 HTML の `<h1>`/`<h2>` から番号（`.chapter-number` / `.section-number`）と
  タイトル（`.chapter-title` 等）を抽出して `<text>` に流し込む。レイアウト（座標・改行・揃え）は
  PDF の `image-header.css` の意図（番号を上、タイトルを中央 等）を SVG 座標で再現する。
- **適用対象**は **PDF で image-header を使う章・節と同一**（`theme.style == 'image'`）。
  前付・奥付など扉絵を持たないページには注入しない（PDF の `@page :nth(1)` / `.section-topic` 適用範囲と整合）。

### B-5. フォールバック（`theme.style=image` でも EPUB は simple 扱い）

利用者提案のとおり、**画像解決や合成に失敗した場合は、EPUB のみ `simple` 相当**として扱う
（合成 SVG を作らず、通常の見出しテキストのみの簡素表示）。安全側の既定の退避とする。

- 実装上は「対象画像が無い／合成に失敗したら注入をスキップし `log_warn`」で自然に simple 表示へ縮退する。
- 設定で明示制御したい場合は `book.yml` に EPUB 用切替（例: `epub.frontispiece: image | simple`）を将来追加可能
  （RC では自動縮退で足り、設定追加は任意）。

### B-6. 実装スコープ

1. **新規 合成 SVG 生成器**（`build/` か `pre_process/` に `heading_image_composer.rb` 等）
   - 入力: 飾り画像パス、見出し番号・タイトル、種別（frontispiece=portrait / ornament=landscape）。
   - 処理: raster を base64 data URI 化 → `<image>`＋`<text>` の SVG を文字列生成 → ファイル出力（キャッシュ可）。
   - レイアウト座標と `<text>` のフォント／フォールバック指定を内包。
2. **`epub_builder.rb` に注入ステップ追加**（`generate_epub_entries!` 内、`*_for_epub!` と同列・**Step E**）
   - `inject_frontispiece_images_for_epub!`: 対象 h1 に合成 SVG `<img>` を入れ、実テキストを `.vs-visually-hidden` 化。
   - `inject_ornament_images_for_epub!`: `section.level2` 直下 h2 に同様の合成 SVG を適用。
   - PDF 完成後に共有 HTML を書き換えるため **PDF 経路へ副作用なし**（③-b/③-c と同じ安全設計）。
3. **EPUB 用 CSS**: `.vs-image-heading-epub img { display:block; max-width:100%; margin:auto; }` と
   `.vs-visually-hidden`（clip 法）を EPUB パッケージ内 CSS に追加（背景前提の `image-header.css` は EPUB で無効）。
4. **クリーン**: 生成した合成 SVG をクリーン対象に追加。
5. **パス整合の確認**: data URI 埋め込みにより外部参照が無いことを前提に、epubcheck ERROR 0 を維持。

### B-7. 影響範囲・リスク・テスト方針

- **影響範囲**: EpubBuilder ＋ 合成 SVG 生成器に閉じる。PDF は CSS 背景のまま不変。
- **リスク**:
  1. **見出しフォントの差**: リーダーに該当フォントが無いと `<text>` の字形が変わる（B-3）。
     EPUB の現行方針（フォント非埋め込み）に従い**許容する**。完全一致は v2.0 のフォント埋め込みオプションで対応。
  2. **`.vs-visually-hidden` の無視**: 一部リーダーで見出しテキストが二重表示になり得る（案 C 相当へ劣化）。許容範囲。
  3. **SVG-in-img の `<text>` レンダリング差**: data URI raster は確実だが `<text>` の描画はリーダー差があり得る。
     Kindle Previewer / Apple Books / Kobo で確認。
  4. EPUB サイズ増（raster を base64 で各章に埋め込むため）。同一画像は使い回す（章で共通なら 1 ファイルを共有）。
- **テスト**:
  - 単体: 合成 SVG 生成器が `<image>`（data URI）＋ `<text>`（番号・タイトル）を正しく組むこと。画像欠落時に nil 返却（縮退）。
  - 統合: EPUB の対象章 XHTML に合成 SVG `<img>` が入り、`<h1>`/`<h2>` の実テキストが残る（nav タイトルが空でない）こと。
  - epubcheck ERROR 0 維持。画像未解決時に simple 縮退すること。PDF 側の扉絵・節絵（背景）が従来どおりであること。

---

## 未決事項

1. **数式 SVG の出力先**（`stylesheets/images/math/` か `images/math/` か）と EPUB 内相対パス。実機 epubcheck で確定。
2. ~~**`mathematical` のバージョン制約**と、ネイティブビルド失敗環境での扱い（フォールバック既定か、必須化か）。~~
   **決定済み（2026-06-14・mathematical を撤回し MathJax へ変更）**: 描画エンジンは Node の `mathjax-full`。
   gem の依存（mathematical / base64）は削除。`vs doctor` は `mathjax_full_available?`（node 存在＋
   mathjax-full がローカル/グローバル node_modules にあるか）で判定し、`vs doctor --fix`（`vs new` 初回に
   自動実行）が `npm install -g mathjax-full` で導入する（playwright と同じ npm グローバル方式）。
   利用者の `vs` は mybook/ の Gemfile 配下で `bundle exec` 実行されるが、数式描画は **Ruby から Node を
   subprocess 起動**するため bundler のグラフ非依存で、グローバル/ローカルの mathjax-full を NODE 側で解決できる。
   未導入時は数式が SVG 化されず Vivliostyle の MathJax 経路（PDF のみ）へグレースフル縮退する。
3. **MathJax 経路の去就**: SVG 化後にフォールバック用として残すか、将来撤去するか。
4. ~~合成 SVG の見出し描画方式~~ **決定済み（2026-06-14）**: `<text>`＋リーダー標準フォント（フォント非埋め込み）。
   字形の完全一致（パス化／フォント埋め込み）は **v2.0 のフォント埋め込みオプション**に合わせて実装（B-3）。
5. **節絵の適用範囲**: 全 h2 か、特定レベル/特定章のみか（PDF の `.section-topic` 付与範囲と整合させる）。
6. **合成 SVG の出力先・キャッシュ粒度**（章で画像共通なら 1 ファイル共有か、見出しごとに別ファイルか）。

## 実装順序の提案

1. **A. 数式 SVG 化**（④-A・④-B を一挙解決・前処理に閉じる・効果大・**承認済み**）。
   - A-1: `math_transformer` 実装 ＋ `MarkdownPreprocessor` 連結 ＋ フォールバック。
   - A-2: `gemspec`・`clean`・ドキュメント。
   - A-3: `test:layout` で PDF/EPUB 目視＋ epubcheck。
2. **B. 扉絵・節絵の合成 SVG 化（EPUB）**（③-a・EpubBuilder ＋ 合成 SVG 生成器に閉じる）。
   - B-1: 合成 SVG 生成器（raster の data URI 埋め込み＋見出し `<text>`）。
   - B-2: `inject_*_for_epub!` ＋ EPUB 用 CSS（`.vs-visually-hidden` 含む）。
   - B-3: epubcheck・実機（Kindle Previewer / Apple Books / Kobo）で見出しフォント・`<text>` 描画を確認。

両者は独立しており、合意の取れたものから着手できる。
A は PDF にも見た目変化が及ぶため `test:layout` の目視確認を最重要とする。
B は `<text>` のリーダー間描画差が読めないため、早期に Kindle Previewer での実機確認を行う。
本仕様書は提案時点のスナップショットであり、実装時に再検証する。
