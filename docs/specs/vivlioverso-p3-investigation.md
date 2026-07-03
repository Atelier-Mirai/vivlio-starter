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
5. **編集自由の実証**（`--theme-accent` 行を消したプロジェクトで book.yml の theme.color が効く）＋
   EPUB 同梱配線（`collect_epub_htmls`/copy_asset が `.cache/vs/book-settings.css` を含む）確認。

各段が独立コミット可能で、破綻時の切り分けが容易。方式A/B の最終決定は step 4 の実験で行う。

---

## 6. 参考: 関与ファイル一覧

- `lib/vivlio_starter/cli/pre_process/css_updater.rb`（564 行・撤去/流用対象）
- `lib/vivlio_starter/cli/pre_process/frontmatter_generator.rb`（link 生成 `:121` / `update_all_css_files` `:331`）
- `lib/vivlio_starter/cli/common.rb`（`CACHE_DIR` `:42`）
- `stylesheets/`（`theme.css` / `chapter.css` / `simple-header.css` / `image-header.css` /
  `chapter-common.css` / `page-settings.css` / `appendix.css` / `preface.css` / `images/bundled/`）
- テスト: `test/vivlio_starter/cli/pre_process/css_updater_test.rb`（13 件・値計算）/
  `test/vivlio_starter/page_layout/page_layout_test.rb`（レイアウト＝出力同一性ハーネス・`rake test:layout`）
