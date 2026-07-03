# P3（CSS 設定注入層）着手前 調査報告

調査日: 2026-07-03 / 調査者: Claude (Opus 4.8) /
対象: [vivlioverso-foundation-workplans.md](vivlioverso-foundation-workplans.md) P3 の着手可否判断

第 2 部 §3（課題 C）= [vivlioverso-foundation-plan.md](vivlioverso-foundation-plan.md)、
第 1 部 §3 = [vivlioverso-build-investigation.md](vivlioverso-build-investigation.md)。

---

## 0. 結論（先出し）

- **P3 仕様は実装と整合している**（記述と実物に食い違いなし）。仕様書の書き直しは不要。
- ただし P3 は P1/P2 と異なり **レイアウト出力に直結**し、回帰リスクの核が
  **実ビルドでしか潰せない 3 点**（カスケード上書き・画像 url() 基準・ヘッダ切替方式）に集中している。
- したがって「各サブステップで出力同一性を検証しながら段階実装」を推奨（詳細は §5）。
- **追補（§7・2026-07-03 検証）**: 上記に加え、仕様・本報告書の双方が見落としていた
  「**書換結果 CSS の読み手**」2 件を特定した——①EPUB 扉絵/節絵合成が theme.css の
  書換結果を正規表現で読んでいる、②copyAsset excludes の `.cache/**` が
  book-settings.css の EPUB 同梱を妨げる。**どちらも P3-2（撤去）の前に対処が必要**。
  実装細目（条件付き書込みの再現・呼出元の引越し等）も §7.3 に固定した。

---

## 1. 現状の CSS 配線（実物）

### 1.1 章 HTML → CSS のリンク

`FrontmatterGenerator#build_base_frontmatter`（`frontmatter_generator.rb:120-130`）が
各章 HTML の frontmatter に以下の `link` 配列を注入する:

```ruby
stylesheets = ['theme.css', chapter_css, 'custom.css']
'link' => stylesheets.map { |css| { 'rel' => 'stylesheet', 'href' => "stylesheets/#{css}" } }
```

- href は **プロジェクトルート基準の相対** `stylesheets/theme.css`（章 HTML はルート直下に生成される）。
- `chapter_css` は種別ごと（`chapter.css` / `appendix.css` / `preface.css` / `part-title.css` / `{種別}.css`）。
- `{種別}.css` が `@import` で base / page-settings / components / chapter-common… を連鎖ロードする。

### 1.2 `{種別}.css` の @import 連鎖（ヘッダ切替）

`chapter.css` は `simple-header.css` **または** `image-header.css` のどちらか一方を `@import` する。
両ファイルは `stylesheets/` 直下に実在（`simple-header.css` / `image-header.css` / `chapter.css` /
`chapter-common.css` / `page-settings.css` / `theme.css`）。

### 1.3 画像 url() の解決基準（★最重要）

`stylesheets/theme.css` の現物:

```css
--section-bg-image:   url("images/bundled/sakura_landscape.webp");
--frontispiece-image: url("images/bundled/sakura_portrait.webp");
```

- url は **CSS ファイル（= `stylesheets/`）基準の相対**。実体は `stylesheets/images/bundled/` に実在
  （`ajisai.webp` / `asagao.webp` 等を確認）。
- **P3 で生成する `.cache/vs/book-settings.css` からは、同じ画像を指すのに
  `../../stylesheets/images/bundled/...` 等へ相対を組み替える必要がある。**
  これが workplan P3-1 の言う「最大の実装注意点」で、実物とも一致。

---

## 2. `CssUpdater`（564 行）の実態

`config/book.yml` の設定を、ビルドのたびに **正規表現で `stylesheets/` の CSS ソースへ in-place 書換**する。
呼び出しは `FrontmatterGenerator#update_all_css_files`（`frontmatter_generator.rb:331-380`）から
`update_css_only!`（Step 2 相当）/ `generate_frontmatter` 経由で毎ビルド実行される。

| メソッド | 対象ファイル | 書換内容 |
|---|---|---|
| `update_theme_css` | `stylesheets/theme.css` | `--theme-accent` / `--color-strong` / `--color-em-underline` / `--section-bg-image` / `--frontispiece-image` / `--frontispiece-padding` / `--frontispiece-heading-width` / `--frontispiece-lead-width` |
| `update_appendix_css` | `stylesheets/appendix.css` | `--appendix-accent-color` |
| `update_preface_css` | `stylesheets/preface.css` | `--color-preface-accent` |
| `update_chapter_css` | `stylesheets/chapter.css` | `@import` を `simple-header.css`⇄`image-header.css` に差替（存在しなければ挿入） |
| `update_chapter_common_css` | `stylesheets/chapter-common.css` | 見出しマーカー（`--h3-marker` 等） |
| `update_page_settings_css` | `stylesheets/page-settings.css`（＋ `awesomebook/stylesheets/page-settings.css` 遺物） | `build_css_variable_mappings` の 22 変数 ＋ `@page { size }` リテラル |

補助（値計算・実証済み資産。P3 では生成器へ流用する）:
`calculate_paper_scale` / `calculate_align_max_width` / `calculate_frontispiece_binding_offset` /
`apply_folio_placement!` / `format_font_value`（フォントスタック整形・Type3 フォールバック）/
`normalize_color_value`。

`build_css_variable_mappings`（`css_updater.rb:535-560`）が返す **22 変数**:

```
--page-width --page-height --paper-scale --align-max-width
--base-font-size --base-line-height --letter-spacing
--page-margin-top --page-margin-bottom --page-margin-inner --page-margin-outer
--frontispiece-binding-offset --column-font-size --folio-font-size
--font-main-text --font-header --font-code --font-column --font-folio
--folio-center-content --folio-left-content --folio-right-content
```

> この変数名一覧＋theme 系（`--theme-accent` / `--section-bg-image` / `--frontispiece-image` /
> `--frontispiece-padding` / `--frontispiece-heading-width` / `--frontispiece-lead-width` /
> `--color-strong` / `--color-em-underline` / `--appendix-accent-color` / `--color-preface-accent` /
> `--h3-marker` 等）が、**P3 で確立するテーマ互換の公開インターフェース**（第 2 部 §3.4）。

### 2.1 `@page { size }` の特殊事情

`update_page_settings_css` は size を **リテラル値**（`182mm 232mm` 等）で書く。
コメントに「`var()` は @page size で使用不可」と明記。生成器（book-settings.css）でも
**リテラルかつカスケードで勝つ位置**に置く必要がある。

### 2.2 `.cache/vs` は実在

`Common::CACHE_DIR = '.cache/vs'`（`common.rb:42`）。workplan の生成先 `.cache/vs/book-settings.css` は妥当。

### 2.3 現状ビルドが stylesheets/ を汚さない理由

同梱 book.yml の値と committed CSS が一致するため、in-place 書換が実質 no-op になり
`git status` 上は無差分（P1/P2 の実ビルドでも stylesheets/ 差分ゼロを実測）。
**ただし book.yml の値を変えれば差分が出る**——この脆さ（＝ソース CSS の可変化）こそ P3 が解消する対象。

---

## 3. 仕様（P3）と実装の突き合わせ

| workplan P3 の主張 | 実物確認 | 判定 |
|---|---|---|
| `.cache/vs/book-settings.css` を全文生成 | `CACHE_DIR` 実在 | ✅ |
| 値計算は現 CssUpdater を流用 | 補助メソッド群が独立関数として存在 | ✅ |
| 変わるのは「正規表現差込」→「テンプレ書出し」だけ | in-place 書換の実態を確認 | ✅ |
| 画像 URL は `.cache/vs/` 基準で相対解決（最大の注意点） | 現状は `stylesheets/` 基準 `images/...` | ✅（要組替） |
| frontmatter link を `[theme, {種別}, book-settings, custom]` 順へ | 現状 `[theme, {種別}, custom]`（`:121`） | ✅（要追加） |
| header import 切替を方式Aで解消（`--header-mode`＋body クラス） | 現状は `@import` in-place 差替（`:194-228`） | ✅（要改修） |
| `sync_vivliostyle_config_*` は現状維持 | JS 書換のまま（`:340-407`） | ✅（P3 では触らない） |
| `awesomebook` 遺物（`:294`）削除 | `update_page_settings_css` に候補として残存 | ✅（削除対象） |

**食い違いなし。** よって仕様書の修正は不要。

---

## 4. 回帰リスクの核（実ビルドでしか潰せない 3 点）

1. **カスケード上書きの確実性**
   book-settings.css が後段で同名変数を再宣言して「既存 theme.css / page-settings.css の値に勝つ」ことが前提。
   特に `@page { size }` はリテラル必須・宣言位置依存。link 順・@import 順・詳細度の実挙動を実ビルドで確認要。

2. **画像 url() の基準（§1.3）**
   `.cache/vs/book-settings.css` からの相対（`../../stylesheets/images/...` か、`file://`/ルート相対か）を
   Vivliostyle の base URL 仕様に照らして実ビルドで確定する必要がある。章 HTML から見たパス整合も要確認。

3. **ヘッダ切替 方式A の同一描画**
   `image-header.css` / `simple-header.css` の規則群を body クラス（`body.vs-header-image` 等）前置へ改修し、
   `BodyClassInjector`（既存機構）でクラス注入。現行の @import 差替と**バイト単位で同一レイアウト**になるか実証要。
   方式B（frontmatter link で header CSS を動的選択）との最終決定も実装時に行う（workplan 容認）。

---

## 5. 推奨する進め方（段階実装・各段で出力同一性を検証）

P2 と同じく「現行から採取した基準」に対し、各サブステップで `rake test:layout`＋実ビルド差分ゼロを確認する:

1. **生成器を追加（既存書換は残す）**: `PreProcessCommands::BookSettingsCss` を新設し
   `.cache/vs/book-settings.css` を生成。この時点では frontmatter link に未追加＝出力不変を確認（安全網）。
   → ここで §4-2（画像パス）を実ビルドで確定。
2. **frontmatter link に book-settings.css を追加**（順序: theme → {種別} → book-settings → custom）。
   既存 CSS の値と生成値が一致するため出力不変を確認。→ §4-1（カスケード）を実証。
3. **CssUpdater の in-place 書換を撤去**（値計算は生成器へ移設済み・`awesomebook` 遺物も削除）。
   出力不変＋ビルド後 stylesheets/ 無差分を確認。→ 課題 C の本丸。
4. **ヘッダ切替を方式A化**（`update_chapter_css` 撤去）。→ §4-3 を実証。
5. **EPUB 側の読み手 2 件を対処**（§7.1 / §7.2）: `read_theme_heading_assets` の参照元切替と、
   EPUB への book-settings.css 同梱（copyAsset `.cache/**` 除外との衝突解消）。
   epubcheck 緑＋Kindle レイアウトテスト緑を確認。
6. **編集自由の実証**（`--theme-accent` 行を消したプロジェクトで book.yml の theme.color が効く）。
   PDF だけでなく **EPUB の扉絵/節絵/節番号色も book.yml に追従**すること（§7.1 の回帰ゲート）。

各段が独立コミット可能で、破綻時の切り分けが容易。方式A/B の最終決定は step 4 の実験で行う。
なお step 3（撤去）は step 5 の対処を済ませてから行うこと（順序を入れ替えると
EPUB の扉絵合成が黙って既定値に落ちる。§7.1）。

---

## 6. 参考: 関与ファイル一覧

- `lib/vivlio_starter/cli/pre_process/css_updater.rb`（564 行・撤去/流用対象）
- `lib/vivlio_starter/cli/pre_process/frontmatter_generator.rb`（link 生成 `:121` / `update_all_css_files` `:331`）
- `lib/vivlio_starter/cli/pre_process/theme_image_resolver.rb`（url 4 形態の返却元。§7.3-1）
- `lib/vivlio_starter/cli/build/image_optimizer.rb`（`update_css_only!` の唯一の呼出元 `:65`。§7.3-3）
- `lib/vivlio_starter/cli/build/epub_builder.rb`（`read_theme_heading_assets` `:788` /
  copyAsset excludes `:356` / `sanitize_epub_css!` `:1508`。§7.1 / §7.2）
- `lib/vivlio_starter/cli/post_process/body_class_injector.rb`（方式 A のクラス注入先。§7.3-5）
- `lib/vivlio_starter/cli/common.rb`（`CACHE_DIR` `:42`）
- `stylesheets/`（`theme.css` / `chapter.css` / `simple-header.css` / `image-header.css` /
  `chapter-common.css` / `page-settings.css` / `appendix.css` / `preface.css` / `images/bundled/`）
- テスト: `test/vivlio_starter/cli/pre_process/css_updater_test.rb`（13 件・値計算）/
  `test/vivlio_starter/page_layout/page_layout_test.rb`（レイアウト＝出力同一性ハーネス・`rake test:layout`）

---

## 7. 追補（2026-07-03 検証）: 調査漏れ 2 件と実装細目

本節は初版報告書のレビューで判明した見落としを固定するもの。§3 の「食い違いなし」は
**仕様の記述と実装の突き合わせ**としては正しいが、仕様・報告書の双方が
「書換結果 CSS を*読む側*」を洗っていなかった。

### 7.1 【P3-2 の前に要対処】EPUB 扉絵/節絵合成が theme.css の書換結果を読んでいる

`EpubBuilder.read_theme_heading_assets`（`epub_builder.rb:788-801`）が **theme.css を
正規表現で読み**、`--frontispiece-image` / `--section-bg-image` / `--section-number-color`
の実値を取得している（色は `var(--theme-accent)` → `var(--accent-*)` → 具体色の連鎖を
theme.css 内で解決。`resolve_css_color` `:821`）。取得値は EPUB の扉絵（h1）・節絵（h2）
合成画像（SVG/JPEG）の生成に使われる。

- **P3 で in-place 書換を撤去すると**、theme.css は committed 既定値（sakura / yellow）の
  まま止まり、book.yml と乖離した設定で EPUB の扉絵・節絵・節番号色が**黙って既定に化ける**。
- **出力同一性検証では検出できない**: 同梱プリセットは committed 値＝book.yml 値なので
  no-op 均衡（§2.3 と同じ罠）。設定を変えたプロジェクトで初めて発現する。
- **対処（推奨）**: CSS を読むのをやめ、生成器と同じソース
  （`FrontmatterGenerator.parse_theme_settings` の計算値）を直接使う。
  「PDF と同一画像を単一の参照元から使う（§B-4）」という現行コメントの意図は、
  P3 後は「単一の参照元＝生成器の計算値」に読み替えるのが自然で、
  編集自由（theme.css から該当行を消しても動く）とも整合する。
  次善は book-settings.css を読む方式だが、url 基準が `.cache/vs/` になる分の
  組替と、`--accent-*` パレットが theme.css 側に残ることによる
  **2 ファイル横断の var() 解決**が必要になる。
- **回帰ゲート**: theme.css を既定のまま book.yml の `theme.color` / `frontispiece` /
  `ornament` を変更 → `vs build --epub` で合成画像の絵柄と節番号色が追従すること。

### 7.2 【P3-2 の前に要対処】copyAsset excludes `.cache/**` と frontmatter link の衝突

`build_copy_asset_excludes_config`（`epub_builder.rb:347-360`）は EPUB 生成時の
copyAsset から **`.cache/**` を除外**している。frontmatter link に
`.cache/vs/book-settings.css` を追加すると、**EPUB では同梱されず参照切れ（RSC-007）**になる。
また、除外を単純に外しても EPUB 内に dot ディレクトリ（`.cache/`）を持ち込むことになり、
OCF / Kindle Previewer の互換懸念がある。

- **対処案（推奨）**: EPUB 経路の共通 rewrite フェーズ（`generate_epub_entries!` 内、
  `mark_body_for_epub!` と同列・`epub_builder.rb:101-114`）で、章 HTML の link href を
  EPUB 用パス（例: ルート直下 `book-settings.css`）へ書き換え、実ファイルをそこへ
  コピーして同梱する。**コピー先で `url("../../stylesheets/images/…")` の相対が
  破綻しない置き場所を選ぶ**（ルート直下なら `stylesheets/images/…` へ書換が必要。
  EPUB 用に url を組み替えた変種を書き出すのが確実）。
- `sanitize_epub_css!`（`:1508`・EPUB 内 `EPUB/**/*.css` 全対象）のマージンボックス除去・
  Kindle の webp url() 除去・フォント非埋込時の @font-face/@import 除去は、
  **同梱さえされれば book-settings.css にも自動適用される**（追加実装不要・テストで確認のみ）。
- **回帰ゲート**: clean EPUB の epubcheck 緑（RSC-007 なし）＋ `epub_kindle_layout_test` 緑。

### 7.3 実装細目（見落としではないが個票の行間。Opus 4.8 向けに固定）

1. **url() の 4 形態**: `ThemeImageResolver` の返却は
   (a) `images/...`（stylesheets/ 基準相対・`theme_relative_path`）
   (b) ユーザー指定 `url(...)` の素通し（`theme_image_resolver.rb:163`）
   (c) `https://` URL、(d) `data:` URI（プレースホルダー SVG）。
   `.cache/vs/` 基準への組替対象は **(a) と (b) 内の相対パス**。(c)(d) は不変。
   (b) は現在 stylesheets/ 基準で解決されており、基準を黙って変えると既存プロジェクトの
   book.yml 指定が壊れるため、組替か「プロジェクトルート相対へ正規化」で吸収する。
2. **条件付き書込みセマンティクスの再現**（出力同一性の要）。生成器は
   「現行 updater が書いたはずの変数**だけ**を、同条件で」宣言する:
   - `theme.style: simple` → `--section-bg-image` / `--frontispiece-image` は `none`、
     `--frontispiece-padding` は**宣言しない**（`update_theme_css` `:86-115`）
   - `appendix_color` 未指定 → `--appendix-accent-color` を**宣言しない**
     （`update_appendix_css` `:147`。既存 CSS 値がカスケードで生きる）
   - preface は**常に宣言**（未指定時は theme accent へフォールバック `:168-169`）
   - markers 未指定 → `♣` / `♦` の既定値（`:238-239`）
   - page-settings 系 22 変数は nil/空値を**宣言しない**（`:303`）
   - `heading_width` / `lead_width` は nil なら**宣言しない**（`:117-127`）

   「宣言しない」の機序は in-place（既存ファイルの値が残る）と生成器（book-settings.css に
   無い→カスケードで既存 CSS 値が有効）で異なるが、結果は同じになる。
3. **生成タイミングと呼出元の引越し**: `update_css_only!` の唯一の呼出元は
   `image_optimizer.rb:65`（'prepare theme images' ステップ）で、full / preflight / single
   **全モードで実行される**——生成器はここへ接続すれば全モードに供給される。
   加えて `generate_frontmatter`（`frontmatter_generator.rb:104`）が**章ごと**に
   `update_all_css_files` を呼んでいる（現在は no-op 反復）——P3 で撤去する。
   その際 `update_all_css_files` 内の `FontManager.ensure_fonts_available`（`:378`）は
   生成器側（または 'prepare theme images'）へ移すこと（フォント準備は CSS 書換と独立に必要）。
4. **`sync_vivliostyle_config_size!` / `title!` の呼出元**: P3-4 で「現状維持」とされるが、
   現在の呼出元は撤去対象の `update_page_settings_css` 末尾（`css_updater.rb:331-334`）。
   撤去時に呼び出しの**引越し**（生成器のステップ末尾等）が必要。
5. **方式 A のクラス注入は PDF 前に効く**: post_process は Vivliostyle PDF の**前**
   （HTML 変換直後・`pipeline.rb` 'convert sections html' → `section_builder.rb:133`）に
   実行されるため、body クラスは PDF 組版にも効く（CLAUDE.md の「after Vivliostyle」という
   要約に惑わされないこと）。実装は `inject_body_class`（`body_class_injector.rb:29-34`）の
   classes 配列へ theme.style 由来クラス（`vs-header-image` 等）を足す。
   同メソッドは literal `<body>` の gsub なので、**別パスで後から追加しようとすると
   `<body class=...>` に一致せず失敗する**（同一注入内で足すこと）。
   part-title は frontmatter class 持ちで `<body>` に一致しない可能性があるが、
   ヘッダ CSS の適用対象が chapter 系のみなら影響なし（実装時に確認）。
6. **特殊ページは自動追従**: `_toc` / `_titlepage` / `_legalpage` / `_colophon` / 部扉は
   すべて Markdown → convert 経路で FrontmatterGenerator を通るため、link 配列の変更は
   **1 箇所で全 HTML に反映**される（個別対応不要）。`vs epub`（`epub.rb`）は
   `npx vivliostyle build --config vivliostyle.config.epub.js` を直接実行する下位ステップで、
   HTML と book-settings.css は先行ステップで生成済みが前提（pipeline 経由なら保証される）。
7. **スコープ外の既知事項**: FontManager は `stylesheets/fonts/google-fonts.css`
   （git 管理下）を毎ビルド生成する。book.yml の typography を変えると stylesheets/ に
   差分が出るが、これは P3 の完了条件「stylesheets/ 無差分」の**対象外**
   （対象は CssUpdater が書いていた 6 ファイル）。生成物の一掃は P4/V2.0 で扱う。
