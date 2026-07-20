# Kindle 用テーマ色のリテラル焼き込み仕様（アクセント色の復活）＋book-settings テスト脆弱性の修正

- 作成日: 2026-07-20
- 対象実装者: Opus 4.8（本仕様のみで実装が完結するよう、根拠・対象・設計・テスト・検証を全て記す）
- 関連: `docs/specs/kindle-css-compatibility-notes.md`（KFX の CSS 非対応・§2）, `stylesheets/theme.css`（アクセントパレットの正典）, `lib/vivlio_starter/cli/pre_process/book_settings_css.rb`（book.yml→CSS 生成）, `lib/vivlio_starter/cli/build/epub_builder.rb`（`resolve_css_color`）
- 背景の経緯: `kindle-simple-header-svg-spec.md`（付録見出しの SVG 化を試みたが 2026-07-20 に却下。代わりに本仕様で「色を付ける」方向へ舵を切る）

本仕様は 2 件を扱う（ユーザー要望でまとめて起こす）:
- **主題**: Kindle でテーマのアクセント色が出ない問題の根治（§0〜§7）。
- **別件**: `book_settings_css_test` が `theme.style: simple` の book.yml で落ちる脆弱性の修正（§8）。

---

## 0. 問題

Kindle(KFX) は **`var()`（CSS カスタムプロパティ）・`color-mix()`・`calc()`・`clamp()` を一切解さない**（`kindle-css-compatibility-notes.md` §2）。本プロジェクトのテーマ色（アクセント）は、すべて `var(--theme-accent)`（→ `var(--accent-yellow)` → `#f0a000`）という**変数チェーンで塗られている**ため、Kindle では色指定が丸ごと無効になる。

結果、本文のアクセント色が**場所ごとにバラバラに劣化**している（実測・CSS 解析）:

| 装飾 | PDF・クリーン EPUB | 現状の Kindle |
| :--- | :--- | :--- |
| 太字強調 `strong` | テーマ色（例 `#f0a000`） | **黒**（`var()` 脱落・フォールバック無し） |
| 強調下線 `em`（`u`） | テーマ色の下線 | **黒の下線**（同上） |
| 見出しマーカー h3/h4（`.vs-h-marker`） | テーマ色 | **黒**（同上） |
| コラム `.column` / `.tip` / `.memo` 枠・ラベル | テーマ色 | **グレー `#888`**（`chapter-common.css` の vs-kindle フォールバックがベタ書き） |
| 付録の章/節見出し（simple ヘッダー） | テーマ色 | **くすんだ金 `#b8860b`**（`simple-header.css` の vs-kindle フォールバックがベタ書き） |

つまり Kindle 版は、本のテーマ色（鮮やかな金）が**どこにも正しく出ておらず、黒・グレー・くすんだ金が混在**している。KFX が `var()` を解さないので「色指定ごと落ちて黒になる」か、「別の固定色でベタ書きされている（テーマに追従しない）」かのどちらかになっているのが原因。

### 0.1 ゴール

**ビルド時にテーマ色を具体的な色コード（リテラル hex）へ解決し、`body.vs-kindle` 配下の規則として焼き込む**ことで、Kindle でも PDF と同じアクセント色を出す。`theme.style = image` / `theme.style = simple` の**両方**、本文・付録の**両方**で機能させる。

## 1. 対象色面（accent surface）

`var(--theme-accent)` 系を消費している宣言の一覧（実測・変更前）。これらが Kindle でリテラル色を必要とする箇所。

| ファイル:行 | セレクタ / 用途 | プロパティ | 解決元 |
| :--- | :--- | :--- | :--- |
| `chapter-common.css:186` | `strong` 太字強調 | `color` | theme-accent |
| `chapter-common.css:174-181` | `em` 強調下線 | `text-decoration-color` | theme-accent |
| `chapter-common.css:56-64,467` | h3 マーカー `.subsection-marker`（**実体 span**・heading_processor 注入） | `color` | color-mark（=theme-accent／付録では appendix-accent） |
| `chapter-common.css:71-76` | h4 マーカー `h4::before`（content が var()） | `color` | color-mark。**ただし Kindle では content:var() が解けずマーカー自体が出ていない**（§2.4 参照・原則対象外） |
| `chapter-common.css:690-696` | Kindle 実体ラベル `.vs-adm-label`（【TIP】等・既定 `#444`） | `color` | PDF の `::before` ラベルは theme-accent 相当。Kindle はここに当てる |
| `chapter-common.css:444` | `.column` 枠 | `border` | color-column-border（=theme-accent） |
| `chapter-common.css:446` | `.column` 地色 | `background` | color-column-bg（=color-mix 15%） |
| `chapter-common.css:455` | `.column::before` ラベル地 | `background` | color-column-border |
| `chapter-common.css:476,487,488` | `.tip` 枠・ラベル | `border`/`color` | theme-accent |
| `chapter-common.css:506,517` | `.memo` 枠・ラベル | `border`/`background` | color-column-border |
| `chapter-common.css:532,533,547` | 引用等の罫・左罫 | `border-*` | color-mark |
| `image-header.css:185` | 画像ヘッダーの章番号色 | `color` | section-number-color |
| `simple-header.css:13` | simple ヘッダーの `--heading-accent` | （変数定義） | theme-accent（付録は appendix.css で appendix-accent 上書き） |
| `preface.css:49` | 前書き/後書き h1 下線 | `border-block-end` | color-preface-accent（既存 vs-kindle 静的 `#4f46e5` 固定・非追従） |
| `preface.css:70` | 前書き/後書き h2 左罫 | `border-inline-start` | color-preface-accent（Kindle で消失） |
| `preface.css:122-130,178` | リンク色/罫・引用左罫 | `color`/`border-*` | color-preface-accent（Kindle で消失） |

補足:
- `image-header.css:185` は **PDF/クリーン EPUB 用**。image テーマの本文章は Kindle では見出しが**画像（JPEG）**になるため、この番号色は Kindle では出番がない（無害・対象外としてよい）。
- `simple-header.css` の vs-kindle フォールバック（`h1/h2` の `border`・`.chapter-number` の `color`・`.section-number` の `background`）は現状 `#b8860b` 固定。ここをテーマ色へ上書きする。
- `chapter-common.css` の admonition vs-kindle フォールバック（`.tip/.memo/.column` を `border: 1px solid #888`）も現状グレー固定。ここをテーマ色へ上書きする。
- **PDF の該当色は全て「アクセント（テーマ色）」**であることを実測確認済み（`.tip`/`.column`/`.memo` の枠は PDF で金）。したがって Kindle でもテーマ色にするのが正しい（グレーは劣化だった）。

## 2. 設計

### 2.1 焼き込み先 = `book-settings.css`（最後に読み込まれる生成 CSS）

章 HTML の CSS link 順は **`[theme.css → {種別}.css → book-settings.css → custom.css]`**（`frontmatter_generator.rb:112` のコメントで確定。`{種別}.css` は `theme.css`・`simple-header.css`・`chapter-common.css` 等を `@import` する）。**`book-settings.css` は静的スタイルシートより後に読み込まれる**ため、同じ（または同等以上の）特異度の規則を置けば、静的な `#888`/`#b8860b` フォールバックを**上書きできる**。これが本設計の核心。

- `book-settings.css` は `book.yml` から**ビルドごとに生成**される（`BookSettingsCss`）。テーマ色の解決結果を焼き込むのに最適な場所（「book.yml → CSS」の唯一の生成物）。
- `book-settings.css` は共通フェーズで**両フレーバに同梱**される（`bundle_book_settings_for_epub!`）。焼き込む規則は **`body.vs-kindle` 配下**にするので、クリーン EPUB（vs-kindle クラス無し）では**不発＝無害**。Kindle だけに効く。
- `sanitize_epub_css!` は @page margin box と webp url() のみ除去し、**色規則には触れない**（確認済み）。焼き込んだ規則は Kindle でも生き残る。

→ **`BookSettingsCss` に、テーマ色をリテラル解決した `body.vs-kindle` アクセント規則ブロックを生成させる。** EpubBuilder 側の新フェーズや後付け書き換えは不要。

### 2.2 色のリテラル解決

`theme.color`（および `theme.appendix_color`）を**リテラル hex** へ解決する。入力は 3 形態:
- 色名（`yellow` 等・`ALLOWED_COLORS`）→ パレットで hex 化（`yellow` → `#f0a000`）。
- hex（`#f0a000` / `0xf0a000` / bare `f0a000`）→ 正規化してそのまま。
- 未指定 → テーマ既定（`yellow` = `#f0a000`）。**付録色未指定 → yellow（`#f0a000`）**——`appendix.css` の静的既定 `--appendix-accent-color: var(--accent-yellow)` に一致させ、PDF/クリーン EPUB の実カスケードと揃える（theme accent へはフォールバックしない。実装で確定 2026-07-20）。

**パレットの正典**: `stylesheets/theme.css` の `--accent-*`（`#f0a000` 等 12 色）。Ruby 側には既に同じ表が **`lib/vivlio_starter/cli/techbook/processor.rb:91` の `THEME_COLOR_HEX`**（`'yellow' => '#f0a000', 'orange' => '#ea580c', …`）として存在する。**この定数を共有定数へ抽出**（例: `Common::THEME_ACCENT_HEX`、または `pre_process` の新モジュール）し、`techbook/processor.rb` と本仕様の両方から参照する（二重管理を作らない）。抽出時は既存の techbook 挙動を変えないこと（同じ値・同じフォールバック `#f0a000`）。

`epub_builder.rb:1098` の `resolve_css_color`（theme.css を読んで var チェーンを辿りリテラル化）と役割が重なるが、**スコープを広げない**:
- **推奨（最小）**: `THEME_COLOR_HEX` を `Common` 等の共有定数へ抽出し、`BookSettingsCss` にローカルな解決ヘルパー（`resolve(color) → hex`・`mix_with_white(hex, ratio) → hex`）を持たせる。`resolve_css_color`（EpubBuilder・ornament 番号色用）はそのまま残す——動いているものを触らない。
- 統合ユーティリティ化（`resolve_css_color` の移行）は別タスク。本仕様では行わない。

**出力前の hex 検証（必須・堅牢性）**: book.yml 由来の値は CSS へそのまま書き出されるため、最終出力は必ず「`#` + 6 桁 hex」に正規化・検証する:
- パレット色名 → hex（6 桁）。
- ユーザー hex は 3 桁 → 6 桁展開、8 桁（alpha 付き）→ 先頭 6 桁を採用（KFX の 8 桁 hex 対応は不明のため）。
- 注意: `CssUpdater.normalize_color_value` は色名に対し **`var(--accent-X)` 形式を返す**ので、その出力をそのまま焼き込んではならない（var が Kindle 規則へ漏れる）。必ずパレットで hex 化する。
- 検証 `/\A#\h{6}\z/` に合格しない値は既定色（theme-accent の解決結果、それも不能なら `#f0a000`）へフォールバック。これで不正な book.yml 値による CSS 注入・構文破壊を構造的に防ぐ（robustness テストの流儀）。

**`color-mix` の事前計算**: `.column` 地色は `color-mix(in srgb, var(--theme-accent) 15%, white)`。KFX は color-mix も解さないため、**Ruby で「accent 15% + white 85%」を計算してリテラル hex 化**する（`mix_with_white(accent_hex, 0.15)`）。sRGB 単純線形混合でよい（`round(c*0.15 + 255*0.85)`）。

### 2.3 style / 付録 の別と、使うアクセント

- **本文の装飾**（strong・em・マーカー・column・tip・memo）は **theme-accent** を使う（`theme.style` によらず共通）。
- **付録**（body に `appendix` クラス）では、`appendix.css` が `--color-mark: var(--appendix-accent-color)`・`--heading-accent: var(--appendix-accent-color)` に上書きするため、**マーカーと見出しは appendix-accent** を使う。strong/em は theme-accent のまま。
- **simple ヘッダー**（`body.vs-header-simple`）の枠・番号色:
  - 付録（`body.appendix.vs-header-simple`）→ **appendix-accent**。
  - simple テーマの本文章（`body.vs-header-simple` かつ非 appendix）→ **theme-accent**。

**最適化**: 解決した `appendix-accent` リテラルが `theme-accent` リテラルと**等しい場合は、付録専用の上書き規則を出さない**（既定構成では両方 yellow=`#f0a000` なので等しく、規則数を減らせる）。

- **前書き/後書き（preface.css）**は `--color-preface-accent`（= `theme.preface_color`）を使う。preface.css は前書き（`body.preface`）と後書き（`body.postface`＝postface.css が preface.css を import）だけに読み込まれるが、本仕様の生成 CSS は**全ページ共通**なので、preface 規則は必ず **`body.preface.vs-kindle` / `body.postface.vs-kindle`** でスコープする（裸の `h1`/`h2` を出すと本文章へ波及する）。**preface_color 未指定時はテーマ色へフォールバック**（`supplemental_color_declarations` が `--color-preface-accent` を `fallback: accent` で常時宣言するのと一致＝PDF と揃う。appendix の yellow 既定とは異なる）。preface 固有要素のため常に出す（base 規則では色が付かない）。

### 2.4 生成する `body.vs-kindle` 規則（焼き込む CSS）

`BookSettingsCss` が `book-settings.css` の末尾に付す（`ACC` = theme-accent リテラル、`APX` = appendix-accent リテラル、`COLBG` = color-mix 結果）。**具体値のみ**・`:is()`/`var()`/`calc()`/`clamp()`/`color-mix` 禁止（`kindle-css-compatibility-notes.md` §6 チェックリスト遵守）。

```css
/* ===== Kindle 用テーマ色リテラル（KFX は var()/color-mix 非対応・本 CSS は最後に読まれ静的フォールバックを上書きする） ===== */
/* 本文テキストのアクセント（セレクタは実コードで確定済み: strong / em / .subsection-marker） */
body.vs-kindle strong { color: ACC; }
body.vs-kindle em { text-decoration-color: ACC; }          /* chapter-common.css L174-181。KFX の対応不明・不発でも黒下線のまま＝無害 */
body.vs-kindle .subsection-marker { color: ACC; }          /* h3 マーカーは実体 span（heading_processor 注入）なので色が効く */

/* コラム・注記枠（静的 vs-kindle の #888 を上書き。PDF は金枠） */
body.vs-kindle .column { border-color: ACC; background: COLBG; }
body.vs-kindle .tip { border-color: ACC; }
body.vs-kindle .memo { border-color: ACC; }
body.vs-kindle .note { border-color: ACC; }                /* PDF は color-mark の二重線。Kindle 囲み枠も色は合わせる */
body.vs-kindle .notice { border-color: ACC; }
/* 注: 幅・style は既存 vs-kindle 規則（1px solid）を活かし、色だけ上書きする */

/* Kindle の実体ラベル【TIP】等（::before は content:none で抑止済み・vs-adm-label が実体。既定 #444 を上書き）。
   .terminal ラベルは既存の白 override（.terminal .vs-adm-label）が特異度で勝つため巻き込まない。
   .output は PDF にラベル無し（Kindle 専用）——アクセント化の対象に含めず #444 のままにする。 */
body.vs-kindle .tip .vs-adm-label,
body.vs-kindle .memo .vs-adm-label,
body.vs-kindle .column .vs-adm-label,
body.vs-kindle .notice .vs-adm-label,
body.vs-kindle .note .vs-adm-label { color: ACC; }

/* simple ヘッダー（付録＝APX / simple テーマ本文＝ACC。#b8860b を上書き） */
body.vs-header-simple.vs-kindle h1 { border-color: ACC; }
body.vs-header-simple.vs-kindle h1 .chapter-number { color: ACC; }
body.vs-header-simple.vs-kindle h2 { border-color: ACC; border-left-color: ACC; } /* 左罫 4px は個別指定のため明示 */
body.vs-header-simple.vs-kindle h2 .section-number { background: ACC; }

/* 付録は appendix-accent（APX≠ACC のときだけこのブロックを出す。特異度が上なので確実に勝つ） */
body.appendix.vs-header-simple.vs-kindle h1 { border-color: APX; }
body.appendix.vs-header-simple.vs-kindle h1 .chapter-number { color: APX; }
body.appendix.vs-header-simple.vs-kindle h2 { border-color: APX; border-left-color: APX; }
body.appendix.vs-header-simple.vs-kindle h2 .section-number { background: APX; }
body.appendix.vs-kindle .subsection-marker { color: APX; }
body.appendix.vs-kindle .tip .vs-adm-label,
body.appendix.vs-kindle .memo .vs-adm-label,
body.appendix.vs-kindle .column .vs-adm-label,
body.appendix.vs-kindle .notice .vs-adm-label,
body.appendix.vs-kindle .note .vs-adm-label { color: APX; }

/* 前書き/後書き（PREF = preface_color リテラル。preface.css を読む body.preface/body.postface に限定）。
   物理プロパティで書く（KFX の border-inline-* 対応は疑わしい）。h1 下線は静的 #4f46e5 を色だけ上書き、
   h2/引用の左罫・リンクは KFX で消えているので border ごと再定義する。 */
body.preface.vs-kindle h1, body.postface.vs-kindle h1 { border-bottom-color: PREF; }
body.preface.vs-kindle h2, body.postface.vs-kindle h2 { border-left: 3px solid PREF; }
body.preface.vs-kindle blockquote, body.postface.vs-kindle blockquote { border-left: 3px solid PREF; }
body.preface.vs-kindle a, body.postface.vs-kindle a { color: PREF; border-bottom: 1px dotted PREF; }
```

実装時の必須事項（実コード調査 2026-07-20 で確定済み）:
- **`::before` へは一切書かない**: Kindle では `body.vs-kindle .tip/.memo/.column::before { content: none }`（chapter-common.css L631-635）で擬似要素ラベルが**抑止**され、EpubBuilder が実体 `<p class="vs-adm-label">`（既定 `color: #444`・L690-696）を注入する。色を当てる正しいターゲットは **`.vs-adm-label`**（上記のとおり 5 種にスコープ）。
- **h4 マーカーは本仕様の対象外**: `h4::before { content: var(--h4-marker) }`（L71-76）は content 自体が var() のため、**Kindle では色以前にマーカーが表示されていない**（既存の欠落・::before 自体も KFX で不安定）。リテラル content フォールバック（`body.vs-kindle h4::before { content: "♦"; color: ACC; }`——マーカー文字列は book-settings 生成器が既に `escape_marker` で持っている）を**試してもよい**が、Previewer で表示確認できた場合のみ採用（できなければ h4 マーカー欠落は既知の制限として KNOWN_ISSUES 行きの別件）。
- **物理プロパティで書く**: 生成規則は `border-left-color` 等の**物理プロパティ**を使う（KFX の論理プロパティ `border-inline-*` 対応は疑わしい。静的 vs-kindle フォールバックも `border-left`/`margin-top` の物理で書かれている）。
- **特異度と順序**: 生成規則は book-settings.css（最後に読まれる）にあるため、同一特異度でも後勝ちで上書きできる。付録規則は `.appendix` が 1 つ多く特異度でも勝つ。
- （任意）`.column h5`（L467・color-mark）も対象にしてよいが優先度低。

## 3. 実装対象ファイル

| ファイル | 変更 |
| :--- | :--- |
| `lib/vivlio_starter/cli/pre_process/book_settings_css.rb` | `body.vs-kindle` アクセント規則ブロックの生成を追加（`ACC`/`APX`/`COLBG` をリテラル解決して出力）。生成 CSS 末尾へ付す |
| （新規 or 既存）色解決ユーティリティ | `THEME_COLOR_HEX` を共有定数へ抽出し、`resolve(color) → hex` ＋ `mix_with_white(hex, ratio) → hex` を提供。`techbook/processor.rb` は共有定数を参照するよう更新（挙動不変） |
| `stylesheets/simple-header.css` | **無変更でよい**（`#b8860b` は book-settings.css 未生成時の安全網として残す。book-settings.css が後勝ちで上書きする）。ただし左罫（`border-left: 4px solid #b8860b`）を色だけ上書きする都合上、生成規則側で `border-left-color` を明示すること |
| `stylesheets/chapter-common.css` | **無変更でよい**（`#888` は安全網として残す。book-settings.css が上書き）。ただし §2.4 の「実セレクタ確定」で必要なら最小修正 |

`lib/project_scaffold/` は直接編集しない。root を編集して `ruby copy_to_scaffold.rb` で同期する（CLAUDE.md）。

## 4. 検討した代替案（不採用）

| 案 | 不採用理由 |
| :--- | :--- |
| Kindle CSS の `var()` を一括でリテラル解決するビルドパス | 強力だが広範・高リスク。`var()` は `calc()`/`clamp()`/`color-mix()` と絡み、KFX はそれらも解さないため「var だけ解決」しても直らない箇所が残る。対象を絞れず回帰面が大きい |
| 静的 CSS に色を直書き（simple-header.css を書き換え） | テーマ色は book.yml 依存でビルドごとに変わる。静的 CSS に固定色を書くと**テーマに追従しない**（まさに現状の #b8860b の問題そのもの） |
| `body.vs-kindle { --theme-accent: #f0a000 }` とカスタムプロパティだけ定義 | **無意味**。KFX は消費側 `color: var(--color-strong)` の `var()` を解さないため、定義をリテラルにしても効かない。消費宣言自体をリテラルに置き換える必要がある |
| EpubBuilder の Kindle フェーズで別 CSS を注入 | 動くが、book-settings.css（既に両フレーバ配信・最後に読まれる）へ出すほうが配信機構を増やさず素直。生成ロジックも「book.yml→CSS」の一箇所に収まる |

## 5. テスト（主題）

Minitest。実装時は ruby-coding-rules skill を適用。

1. **色解決ユーティリティ（新規）**: 色名→hex（`yellow`→`#f0a000`）／hex 透過（`#123abc`→`#123abc`・`0x…`・bare）／3 桁 hex 展開（`#abc`→`#aabbcc`）／8 桁 hex は 6 桁化／不正値（`red;}body{...` 等の注入文字列・未知色名）→ 既定色へフォールバック（§2.2 の検証）／未指定→既定／`mix_with_white('#f0a000', 0.15)` が期待 hex（`round(240*0.15+255*0.85)` 等）を返す。
2. **`book_settings_css_test`（追記）**: `style: image` の統制 config で生成した CSS に `body.vs-kindle strong { color: #… }`・`body.vs-header-simple.vs-kindle h1 { border-color: #… }`・`.column` の COLBG が**リテラル hex**で含まれること（`var(`/`color-mix(` を含まないこと）。`theme.color: blue` の config では青系 hex（`#0ea5e9`）が焼かれること（テーマ追従の確認）。`appendix_color` がテーマ色と異なる config では `body.appendix.…` の APX 規則が出ること・同じなら出ないこと。
3. **クリーン EPUB 非汚染**: 生成規則が全て `body.vs-kindle` 前置であること（`.vs-kindle` を含まない裸の accent 規則を book-settings.css に出さない）。

## 6. 検証（実装後）

1. `bundle exec rubocop` / `rake test` 全緑。
2. `vs build --target=kindle`（`theme.style: image`）→ Kindle Previewer 3 で: 本文の**太字がテーマ色**・コラム/TIP 枠と【TIP】等ラベルが**テーマ色**・h3 マーカー（♣）が**テーマ色**・付録見出しの枠/バッジが**テーマ色**で出ること（黒/グレー/くすんだ金が消えること）。
   あわせて KFX 対応が不明な 2 点を実機判定する: ① `em` 下線の色（`text-decoration-color`。不発なら黒下線のまま＝許容し仕様の注記を更新）② h4 マーカーのリテラル content フォールバックを試した場合はその表示（出なければ採用しない・§2.4）。
3. `theme.style: simple` でも同様に、全章の見出し枠・本文アクセントがテーマ色で出ること。
4. `theme.color` を `blue` 等に変えて再ビルド → Kindle のアクセントが青へ追従すること（固定でないことの確認）。
5. クリーン EPUB（Kobo/Apple）が**無変化**であること（`body.vs-kindle` 規則が不発）。
6. `docs/specs/STATUS.md`・`CHANGELOG` を更新。`kindle-css-compatibility-notes.md` §4 の該当行（strong/枠/付録が黒・グレー・くすんだ金）を「テーマ色リテラルで解決」へ更新。

## 7. 非対象（主題）

- クリーン EPUB・PDF（`var()` を解すので現状のまま）。
- image テーマ本文章の見出し（Kindle では画像＝JPEG。色は画像に焼き込み済み・`image-header.css:185` は対象外）。
- アクセント以外の `var()`/`calc()`/`clamp()` 依存（フォントサイズ等。本仕様はアクセント色のみ）。
- 却下済みの付録 simple ヘッダー SVG 化（`kindle-simple-header-svg-spec.md`。本仕様は「CSS に色を付ける」方向で、SVG 化はしない）。

---

## 8. 別件: `book_settings_css_test` の style 依存脆弱性の修正

### 8.1 問題

`test/vivlio_starter/cli/pre_process/book_settings_css_test.rb` の
`test_should_render_all_public_interface_variables_and_page_size` は、
**live の `Common::CONFIG`（＝リポジトリの `config/book.yml`）**を読んで `BSC.render(Common::CONFIG)` の出力に
`--frontispiece-padding:` 等が含まれることを**無条件に**assert する。

しかし `book_settings_css.rb:125` は `--frontispiece-padding` を **`theme.style == 'image'` のときだけ**出力する（`simple` では出さない・仕様どおり）。そのため、`config/book.yml` を `style: simple` にして作業していると（付録確認等でよくある）、この統合テストが落ちる。**テストが「live book.yml は常に image」という前提をハードコードしている**のが脆さの本体。

### 8.2 修正方針（調査 2026-07-20 で簡素化）

実コード調査の結果、**style 別の挙動は既に統制テストで検証済み**である——同ファイルの
`BookSettingsCssThemeTest` が、手組みの settings ハッシュで `BSC.theme_declarations` を直接叩き、
`simple`（padding 非宣言・画像 2 変数 none）と `image`（padding・URL 組替）の両方をカバーしている。
統制 config を新設する必要はない。

落ちるのは統合テスト `BookSettingsCssRenderIntegrationTest`（L218〜）1 本だけで、その趣旨は
「実 `Common::CONFIG` を通して公開インターフェース変数が全部描画される」こと。この統合価値を保ったまま
live book.yml のどちらの style でも通るよう、**期待変数リストを CONFIG の style に応じて条件化**する:

```ruby
def test_should_render_all_public_interface_variables_and_page_size
  css = BSC.render(Common::CONFIG)

  (PAGE_VARS + THEME_VARS_COMMON).each { |var| assert_includes css, "#{var}:", … }
  if Common::CONFIG.theme.style == 'image'
    assert_includes css, '--frontispiece-padding:'
  else
    assert_includes css, '--frontispiece-image: none;'  # simple では none 宣言が正
    refute_includes css, '--frontispiece-padding:'
  end
  assert_match(/@page \{ size: \d+mm \d+mm; \}/, css)
end
```

（`THEME_VARS` から image 固有の `--frontispiece-padding` を外し `THEME_VARS_COMMON` とする。
`--frontispiece-image`・`--section-bg-image` は両 style で「宣言自体は必ず出る」——simple では値が `none`——ため
共通リストに残してよい。）

注意（本仕様 §5-2 との整合）: 主題側の Kindle アクセント規則テストは、既存の
`BookSettingsCssThemeTest` の流儀（統制 settings ハッシュ）に従い、生成メソッドを直接叩いて書く。

### 8.3 テスト（別件）

- live book.yml が `style: image` / `style: simple` の**どちらでも**統合テストが通る
  （手元で book.yml を simple に切り替えて `ruby -Ilib -Itest test/.../book_settings_css_test.rb` が緑になることを確認）。
- 既存の `BookSettingsCssThemeTest`（統制 settings の style 別テスト）は無変更で緑のまま。

## 9. 完了条件チェックリスト

- [ ] `THEME_COLOR_HEX` を共有定数へ抽出（techbook は挙動不変で参照）／色解決＋color-mix ユーティリティ新設
- [ ] `BookSettingsCss` が `body.vs-kindle` アクセント規則をリテラル hex で生成（`var(`/`color-mix(` を含まない）
- [ ] image / simple の両テーマ・本文/付録でテーマ色が Kindle に出る（Previewer 実機）
- [ ] `theme.color` 変更にアクセントが追従する（固定でない）
- [ ] クリーン EPUB 無変化（規則は全て `body.vs-kindle` 前置）
- [ ] `book_settings_css_test` が live book.yml の `style` に依存せず、image / simple 両方を統制 config で検証
- [ ] rake test / rubocop クリーン、CHANGELOG / STATUS / kindle-css-compatibility-notes を更新
