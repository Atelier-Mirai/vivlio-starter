# EPUB / Kindle ターゲット分離 仕様書

> 作成日: 2026-06-18
> ステータス: **策定中（未実装）** — 本仕様で合意後に実装する。
> 対象: `vs build` の出力ターゲット体系。`output.targets` に **`kindle` を新設**し、`epub`（Kobo/Apple Books 向けクリーン EPUB）と分離する。
> 関連: `epub-kindle-layout-spec.md`（Kindle レイアウト是正）, `epub-kindle-webp-transcode-spec.md`（WebP）, `math-frontispiece-svg-spec.md`（扉絵/節絵）
> 統合: 旧 `epub-glossary-index-xhtml-report.md`（用語集・索引の epubcheck ERROR 調査報告）を本書へマージした（§1-8 ＋ 付録 A）。
> 優先度: 高（Kindle 対応のために EPUB 本体を劣化させ続ける構造を解消する）

---

## 0. 背景と目的

EPUB→Kindle 変換のために、これまで **1 つの EPUB に Kobo/Apple Books と Kindle の両立を強いて**きた。しかし両者の CSS サポートは大きく異なる:

| 機能 | Kobo / Apple Books | Kindle（KFX / Enhanced Typesetting） |
| --- | --- | --- |
| CSS Grid | ○ | ✗（単列化） |
| `position: absolute`（`::before` 角タブ等） | ○ | ✗（通常フローに落ちる） |
| `var()`（カスタムプロパティ） | ○ | ✗（宣言ごと破棄） |
| 外部 CSS の画像サイズ | ○ | ✗（inline/属性のみ尊重） |
| `<img>` の `ex`/`em` 寸法 | ○ | △（不安定。固有寸法なし SVG は 300px 既定） |
| WebP 画像 | ○ | ✗ |

このため Kindle 用の是正（`body.vs-epub` ガード CSS・画像 inline 制約・数式 px 化・コードのテーブル化・admonition ラベル注入・WebP→JPEG・`::before` 抑止）を共有 EPUB にかけると、**Kobo/Apple Books 向けの品質が劣化**する（角タブバッジが消える、WebP の二重圧縮、等）。

**目的**: ターゲットを 2 系統に分け、各ストアに最適な成果物を独立に生成する。

| target | 想定ストア | 中身 | 表紙 `embed` |
| --- | --- | --- | --- |
| `epub`（既存・無改変） | 楽天 Kobo / Apple Books | **劣化なしのクリーン EPUB**。`::before` 角タブ・`var()` テーマ色・WebP すべて維持 | `true`（楽天/Apple 向け） |
| `kindle`（新設） | Amazon Kindle | クリーン EPUB を**複製 → Kindle 用に CSS/HTML を書き換え（劣化）** → `kindlepreviewer -convert` で **`.kpf` まで自動生成** | `false`（Kindle 向け） |

---

## 1. 設計

### 1-1. `body.vs-kindle` という「Kindle 専用マーカー」を導入（最重要）

現状 `mark_body_for_epub!` は **すべての** EPUB 章 `<body>` に `vs-epub` を付与している。本仕様では:

- クラス名を **`vs-epub` → `vs-kindle` に改名**する（意味を正確に表す。Kindle 専用であることを明示）。
- 付与は **`kindle` フレーバのときだけ**行う（メソッドも `mark_body_for_kindle!` に改名）。

結果として共有スタイルシートの `body.vs-kindle …` ガード CSS は **Kindle ビルドでのみ発火**し、クリーン EPUB（`vs-kindle` 無し）には一切効かない。これにより:

- Kindle 専用の劣化 CSS（画像上限・コードテーブル・コラム枠書き換え等）を **1 つのスタイルシートに同居させたまま**、クリーン EPUB を無傷に保てる。
- 「同一ファイルで Apple Books と Kindle を出し分ける」ための `var()`/`absolute` ハックが**不要**になる。Kindle 側は `body.vs-kindle` 配下で堂々と `::before` を消し、ラベルを差し替えられる。

> 改名対象: 既存の `body.vs-epub …` ルール（`chapter-common.css` / `code.css` / `components.css` / `layout-utils.css` の root・scaffold 両方）、`mark_body_for_epub!`、関連テストを `vs-kindle` / `mark_body_for_kindle!` へ一括改名する。

### 1-2. EPUB ビルドのフレーバ化

`EpubBuilder.generate_epub_entries!(base_dir, entries, flavor:)` に `flavor`（`:epub` / `:kindle`）を追加。HTML 後処理を以下に振り分ける。

| 後処理 | `:epub`（クリーン） | `:kindle` | 備考 |
| --- | :---: | :---: | --- |
| `post_process_index_glossary_for_epub!` | ○ | ○ | XHTML 整合。**§1-8 で RSC-005/RSC-012 是正を追加** |
| `strip_inline_footnote_ids_for_epub!` | ○ | ○ | XHTML 妥当性 |
| `rewrite_table_align_for_epub!` | ○ | ○ | XHTML 妥当性 |
| `restore_plain_emoji_for_epub!` | ○ | ○ | twemoji 非同梱・軽量化 |
| `inject_heading_images_for_epub!`（扉絵/節絵） | ○（**合成 SVG のまま**） | ○（**JPEG ラスタライズ**） | クリーンは高画質 SVG、Kindle のみラスタライズ |
| `transcode_webp_images_for_epub!`（WebP→JPEG） | **✗** | ○ | クリーンは WebP 維持（高画質）。Kindle のみ JPEG 化 |
| `mark_body_for_kindle!`（`vs-kindle` 付与） | **✗** | ○ | §1-1 |
| `constrain_layout_images_for_epub!`（画像 inline 制約） | **✗** | ○ | book-card 40% / sideimage 25% 等 |
| `convert_math_units_for_epub!`（数式 px 属性） | **✗** | ○ | クリーンは em/SVG のまま（§3） |
| `convert_code_blocks_for_epub!`（コードのテーブル化） | **✗** | ○ | |
| `decorate_admonitions_for_epub!`（ラベル注入） | **✗** | ○ | §1-5 |

`:epub` は **XHTML 妥当性に必要な最小処理のみ**＝**Kindle 対応を入れる前のきれいな EPUB に戻す**。扉絵/節絵もクリーン側は合成 SVG（高画質）を維持し、JPEG ラスタライズは Kindle 専用とする。

### 1-3. 共有 HTML を壊さない処理順

`generate_epub_entries!` は章 HTML を**その場で書き換える**。`epub` と `kindle` を同時指定した場合、Kindle の rewrite がクリーン用 HTML を破壊しないよう、次のいずれかを取る:

- **方式A（採用）**: クリーン EPUB を先に確定（パッケージ化）→ その後 Kindle 用に章 HTML を別ディレクトリへ複製してから rewrite。
- 方式B: 章 HTML のスナップショットを保持し、フレーバごとに復元してから処理。

実装は方式A を基本とする（パイプラインの段階分けが明快）。

### 1-4. 出力ファイル名

`generate_output_filename` に `kindle` を追加。**出力はプロジェクトルート直下**。

| target | 成果物 | ファイル名（例・`include_version: true`） |
| --- | --- | --- |
| `epub`（Kobo/Apple Books） | EPUB | `vivlio_starter_v1.0.0.epub`（**いままで通り**） |
| `kindle` | KPF（**最終成果物**） | `vivlio_starter_v1.0.0.kpf` |

`kindle` フレーバの Kindle 最適化 EPUB は `kindlepreviewer` への入力にすぎないため、**中間ファイル**として扱う（一時ディレクトリ等に生成し、KPF 生成後に削除。`--no-clean` 時のみ `…-kindle.epub` として残し検証可能にする）。最終的にルート直下に残るのは `…​.kpf` のみ。

### 1-5. Kindle のコラム枠（tip / memo / column）

§1-1 により `body.vs-kindle` が Kindle 専用になるので、Kindle 側だけで以下を行い、**利用者の期待図どおり「ラベルが枠上・枠間に空行・重複なし」**を実現する:

```
期待（Kindle）:
┌────────────────┐
│ 【TIP】         │
│ 表A-1 に示した… │
└────────────────┘
（空行）
┌────────────────┐
│ 【MEMO】        │
│ 特殊相対性理論… │
└────────────────┘
```

- `body.vs-kindle .tip::before, .memo::before, .column::before { content: none; }` … Kindle で生き残る `::before`（tip は濃色で重複表示）を抑止。
- 実体ラベル `<p class="vs-adm-label">【TIP】/【MEMO】/【COLUMN】</p>` を `decorate_admonitions_for_epub!` が先頭注入し、`body.vs-kindle` 配下で**通常表示**（前回の `position:absolute` 退避ハックは不要になり撤去）。
- `body.vs-kindle .tip/.memo/.column { padding-block-start: <通常値>; }` … 角タブ用に空けていた上部余白（`6mm`）を詰め、ラベル上の「空行」を解消。
- 枠線は `body.vs-kindle` 配下で `border: 1px solid <具体色>`（Kindle は `var()` 不可のため具体値）。
- 枠間の空行は本体既定の `margin-block`（`8mm 6mm`）で確保。

**クリーン EPUB（Apple Books）はこれらの影響を受けず、従来の `::before` 角タブ・テーマ色のまま**。前回 base 規則（`.tip` 等）へ入れた `var()` フォールバックは不要になるため**撤去し、base 規則を元の `border: solid 0.2mm var(--…)` に戻す**（クリーン EPUB / PDF を完全復元）。同様に、直近で root・scaffold の `code.css` 等へ入れた劣化 CSS は `body.vs-kindle` ガード配下に統一し、クリーン EPUB に影響しないことを保証する。

### 1-6. 表紙の扱い（本フェーズでは保留）

表紙には未解決の課題がある:
- `epub.embed: false` … Kindle に表紙が付かない。
- `epub.embed: true` … Kindle で表紙が**二重**になる。

**本フェーズのスコープは「Kindle 本文（KPF）が正しく出力できる」こと**に絞り、表紙は保留する。当面 `kindle` フレーバは `embed: false`（表紙なし）で KPF 化し、変換成功を最低ラインとする。Kindle 実機での最適な表紙の渡し方（KPF 表紙メタ／KDP カバー設定との関係）は、**本文出力が固まってから別途調査・対応**する（§4 TODO）。

### 1-7. KPF 自動変換

`kindle` 指定時、Kindle 最適化 EPUB の生成後に:

```
kindlepreviewer <book>-kindle.epub -convert -output <out_dir> -locale <locale>
```

を実行し `.kpf` を出力ディレクトリから回収・リネームする。

- `kindlepreviewer` 未インストール時は **警告して `-kindle.epub` を残し、KPF 生成のみスキップ**（ビルド全体は失敗にしない）。
- `-locale` は当面 `en` 固定（または `book.yml` から取得可能なら言語設定に追従。要検討）。
- 変換ログ（`Summary_Log.csv` / `Logs/*_log.csv`）の Error/Quality 件数を解析し、`log_summary` で要約表示する。

### 1-8. epubcheck ERROR 0 の回復（用語集・索引）— 両フレーバ共通

用語集（`_glossarypage.xhtml`）・索引（`_indexpage.xhtml`）に残る epubcheck ERROR（RSC-005 / RSC-012）に本フェーズで対応する（調査の詳細は**付録 A** に統合）。**用語集・索引は PDF と EPUB で共有 HTML を使う**ため、PDF レイアウトへ影響させないよう **EPUB 後処理（`post_process_index_glossary_for_epub!`）内で EPUB の DOM だけ是正**する（既存の table align 変換等と同じ安全設計）。**クリーン EPUB・Kindle EPUB の双方に適用**（XHTML 妥当性は両ストア検証で必須）。

#### RSC-005（用語集）: `<dl>` 直下の見出し `<div>`
`<dl class="glossary-list">` 直下にテキストだけの `<div class="glossary-group-header">A-Z</div>` があり、XHTML5 の `<dl>` 内容モデル違反。

- **方針（報告書 §2-4 案 1 を EPUB 後処理で実施）**: 単一の `<dl>` を走査し、グループ見出しごとに **「見出し（`<p class="glossary-group-header" role="heading" aria-level="2">` 等）＋ その頭文字の `<dt>`/`<dd>` だけを含む `<dl>`」のセットに分割**する。見出しは `<dl>` の外へ出すため内容モデル違反が解消する。
- 生成元（`index/unified_page_builder.rb:309`）は **PDF 用にそのまま**（PDF は `<dl>` 内 `<div>` を問題なく描く）。`.glossary-group-header` の CSS はクラスセレクタなので分割後も適用され、見た目は不変。
- 別解（案 2: 見出しと当該グループの `dt/dd` を 1 つの `<div>` に内包）も妥当だが入れ子が深くなるため、案 1 を採用。

#### RSC-012（索引）: 未定義フラグメント
索引のバックリンク `…#idx-<hash>-<n>` が、当該 EPUB に存在しない id を指すと ERROR。章サブセットビルドで顕在化。

- **存在チェック（恒常対策）**: 索引 EPUB 後処理で、**全章 HTML から実在する id 集合を収集**し、参照先 id が集合に無いバックリンクは **`<a>` を素のテキストへフォールバック**（リンク解除）する。これによりサブセット／全章いずれのビルドでも RSC-012 を出さない。
- **検証方針**: リリースは全章ビルドで epubcheck を取り（§5）、恒常エラーが無いことを保証。

> 本対応で、本文・扉絵/節絵・数式に続き **用語集・索引も epubcheck ERROR 0** に戻し、`epub-pipeline-fix-spec.md` で一度達成した品質基準を回復する。

---

## 2. 実装方針（パイプライン）

- `kindle_target?` を追加（`output.targets` に `kindle` を含むか）。`epub_target?` と独立。
- `register_epub_only_steps` 系を拡張、または `run_step_epub` を `run_step_epub(flavor:)` 化し、`epub`/`kindle` でそれぞれ呼ぶ。
  - `epub` のみ: クリーン EPUB を生成。
  - `kindle` のみ: Kindle EPUB を生成 → KPF 変換。
  - 両方: クリーン EPUB 確定 → Kindle EPUB（複製 rewrite）→ KPF 変換。
- `run_step_kpf`（新規）: `kindlepreviewer` 実行・ログ解析・KPF 回収。
- `generate_epub_config!` は `embed` をフレーバで上書きできるよう引数化（`kindle` は false）。
- `extract_targets` は値検証をしていないため、`kindle` は自然に通る。ただし `doctor`/`build` の help と `cover.rb`・`create.rb` のターゲット分岐に `kindle` を追記し、未知ターゲット扱いされないようにする。

### 既存への影響（後方互換）
- `targets: pdf, epub`（現行デフォルト）の挙動は**不変**。`generate_epub_entries!` のデフォルト `flavor:` は `:epub`。
- `targets: pdf, epub, kindle` で 3 種出力。`targets: kindle` 単独も可。

---

## 3. 数式の既知の制限（本仕様では未解決）

表内・インライン数式（外部 SVG を `<img>` 参照）は Kindle で本文フォントに追従しない（`em`→巨大/不安定、`px`→固定で拡大時に相対的に小）。`kindle` フレーバでは **px 固定で安定化**しつつ、**既知の制限**として扱う（`$$` ディスプレイ数式は正常）。表内に数式を置かない運用回避を引き続き推奨。根治案（SVG のインライン展開で `height:1em` 本文連動）は別タスク。

---

## 4. 決定事項 / 残 TODO

**決定済み（本仕様で確定）**
- マーカーは `body.vs-kindle`（`vs-epub` から改名）。
- クリーン EPUB は扉絵/節絵を**合成 SVG のまま**（高画質）。JPEG ラスタライズは Kindle 専用。
- クリーン EPUB は WebP 維持。WebP→JPEG は Kindle 専用。
- 出力名: `epub`→`vivlio_starter_v1.0.0.epub`（従来通り）、`kindle`→`vivlio_starter_v1.0.0.kpf`。**ともにプロジェクトルート直下**。
- 表紙は本フェーズ保留（`kindle` は当面 `embed:false`）。

**残 TODO（本文出力が固まってから）**
1. **Kindle 表紙の最適な渡し方**: `embed:false`=表紙なし／`embed:true`=二重、の課題を解消する方式を実機調査（§1-6）。
2. **`-locale`**: 言語設定との連動可否（当面 `en` 固定）。
3. **`vs open` / クリーン処理**: 新規成果物（`.kpf`、`--no-clean` 時の `-kindle.epub`）のクリーン対象・open 対象への追加。

---

## 5. テスト方針

### 5-1. ユニット（OS 非依存・`rake test`）
- `extract_targets` に `kindle` を渡したときのパイプライン分岐（`kindle_target?`）。
- `generate_epub_entries!(flavor: :epub)` が **Kindle 専用 rewrite を行わない**こと（`vs-kindle` 非付与・WebP 維持・数式 em のまま・コード非テーブル化・ラベル非注入・扉絵 SVG 維持）。
- `generate_epub_entries!(flavor: :kindle)` が**全 rewrite を行う**こと（既存 `epub_kindle_layout_test.rb` のケースを `:kindle` 前提に整理し、`vs-epub`→`vs-kindle` へ更新）。
- `kindle` フレーバで `embed=false` の config が生成されること。
- KPF 変換ステップ: `kindlepreviewer` 未インストール時に警告のみで継続すること（コマンド存在チェックを DI で差し替え）。
- **用語集（RSC-005）**: 是正後の DOM で、`<dl>` 直下に見出し `<div>` が無く、見出しは `<dl>` の外（兄弟）に出ていること／頭文字ごとに `<dl>` が分割されていること。
- **索引（RSC-012）**: 実在しない id を指すバックリンクが素のテキスト化され、`<a href="#...">` が残らないこと（実在 id へのリンクは保持）。

### 5-2. 全ターゲット統合（`targets: pdf, print_pdf, epub, kindle`）
`vs build` を実際に走らせる統合テスト。`kindlepreviewer` 等の外部依存・実行時間が大きいため、**`rake test:layout`（page_layout 相当の opt-in スイート）側に配置**し、`rake test` からは除外する。

- **成果物の存在**: ルート直下に `…​.pdf` / `…_print.pdf` / `…​.epub` / `…​.kpf` の 4 つが揃うこと（`kindlepreviewer` 未導入環境では `.kpf` のみ skip 扱い）。
- **相互非汚染（§1-3 の回帰防止・最重要）**: 同時ビルドで、
  - クリーン `…​.epub` には `vs-kindle` / `vs-code-epub` / 数式 px 属性 / `_epub_assets` への WebP→JPEG 痕跡が **現れない**（＝劣化していない）。
  - Kindle 側（`-kindle.epub` 中間物 or `.kpf` 展開）には上記が **現れる**。
  - クリーン EPUB は扉絵/節絵が **SVG**、Kindle 側は **JPEG** であること。
- **Kindle 変換成功**: `kindlepreviewer` 導入時、`Summary_Log.csv` が Conversion=Success / Error 0 であること（導入時のみ）。
- **epubcheck ERROR 0**: 全章ビルドのクリーン `…​.epub`・Kindle 中間 `-kindle.epub` の双方を epubcheck（導入時）で検証し、RSC-005/RSC-012 を含め ERROR 0 であること（§1-8）。

### 5-3. スナップショット（`target_consistency_test`）
- クリーン EPUB に `vs-kindle`/`vs-code-epub`/数式 px 属性が**現れない**こと、Kindle EPUB には**現れる**ことの双方を検査（`EpubSnap` を flavor 別に拡張）。
- combo セットは「各単体＋ epub+kindle ＋全部入り」の最小セット。`kindle` ターゲット未実装の間は kindle を除いた 4 ビルド、実装後（`pipeline` に `kindle_target?` が入った時点）に自動で 6 ビルドへ拡張される（`FORMATS` 駆動）。

---

## 付録 A. 用語集・索引 epubcheck ERROR 調査（旧 `epub-glossary-index-xhtml-report.md` を統合）

> 初出: 2026-06-15 の調査報告。EPUB を epubcheck 3.3（EPUB 3.3 ルール）で検証すると、**用語集・索引に合計 4〜6 件の ERROR** が出る。本文・扉絵/節絵・数式 SVG の XHTML は ERROR 0 で、本件は用語集・索引ページに限定。Kindle 変換（WebP 非対応等）とは別系統。対応方針は §1-8。

| コード | ファイル | 概要 |
| --- | --- | --- |
| RSC-005 | `_glossarypage.xhtml` | `<dl>` 直下に**テキストを持つ `<div>`**（グループ見出し）があり、XHTML5 の `<dl>` 内容モデル違反 |
| RSC-012 | `_indexpage.xhtml` | バックリンクの**フラグメント識別子が未定義**（参照先 id が当該ビルドに存在しない） |

### A-1. RSC-005（用語集）— `<dl>` 直下の見出し `<div>`

実際のエラー:

```
ERROR(RSC-005): _glossarypage.xhtml(89,75): テキストはここには書けません.
                ここに書かれるべきものは 要素 "dt", "script" または "template" です.
ERROR(RSC-005): _glossarypage.xhtml(89,81): 要素 "div" の内容が不完全です. 必要な要素 "dt" がありません.
ERROR(RSC-005): _glossarypage.xhtml(90,40): 要素 "dt" をここに書いてはいけません.
ERROR(RSC-005): _glossarypage.xhtml(93,33): 要素 "dd" をここに書いてはいけません.
```

該当マークアップ:

```html
<dl class="glossary-list">
  <div class="glossary-group-header" role="heading" aria-level="2">A-Z</div>  <!-- ← 問題 -->
  <dt id="gls-pdf" class="glossary-term">…</dt>
  <dd class="glossary-definition">…</dd>
  …
</dl>
```

原因: XHTML5 の `<dl>` の内容モデルは「`<dt>`/`<dd>` の並び」または「それらを**グループ化する `<div>`**」のみを許す。`<dl>` 直下に `<div>` を置くこと自体は許されるが、その `<div>` は **`<dt>`/`<dd>` を内包するグループ**でなければならない。本件の `<div class="glossary-group-header">` は **テキスト「A-Z」だけを持つ見出し**で `<dt>` を含まないため不正。これにより「div の内容が不完全（dt が無い）」「div の後の dt/dd がここに書けない」の連鎖エラーになる。

生成元: `lib/vivlio_starter/cli/index/unified_page_builder.rb:309`

```ruby
entries << %(<div class="glossary-group-header" role="heading" aria-level="2">#{initial}</div>)
```

頭文字（A-Z / あ行…）ごとのグループ見出しを `<dl>` の中に直接差し込んでいる。

想定された修正案（採用は §1-8 = 案 1 を EPUB 後処理で実施）:
1. **グループ見出しを `<dl>` の外に出す**（推奨・採用）: 頭文字ごとに「見出し（`<h2>` か `<p role="heading">`）＋ その文字の用語だけを含む `<dl>`」を 1 セットにして繰り返す。最も素直で妥当。
2. **グループ化 `<div>` を正しく使う**: `<dl>` 直下の `<div>` に見出しと当該グループの `<dt>`/`<dd>` を**すべて内包**させる。見出しを `<dt>`/`<dd>` 以外の要素にすれば妥当。ただし入れ子が深くなる。
3. **PDF 経路への影響に注意**: 用語集は PDF・EPUB で共有 HTML を使うため、PDF レイアウトへの影響を確認したうえで変更する。EPUB 専用後処理で EPUB 側だけ組み替える方法もある（PDF 無影響・既存の align 変換等と同じ安全設計）→ **§1-8 はこの方式を採用**。

### A-2. RSC-012（索引）— 未定義フラグメント

実際のエラー（例）:

```
ERROR(RSC-012): _indexpage.xhtml(92,179): フラグメント識別子が定義されていません.
```

原因: 索引の各項目は本文中の出現箇所へ `…#idx-<hash>-<n>` でリンクするが、**そのフラグメント（id）が当該 EPUB に含まれない**場合に RSC-012 になる。今回の検出は **章のサブセットビルド**（4 章のみ）で発生しており、リンク先 id が「ビルド対象外の章」や「未生成のアンカー」を指していたためと考えられる。全章をそろえる通常のリリースビルドでは発生しない可能性が高いが、確証のため次を確認する:
- 全章ビルドの EPUB で RSC-012 が出ないか（サブセット固有か恒常か）。
- 索引アンカー（`#idx-…`）が本文 HTML 側に確実に出力されているか（出現箇所の id 付与漏れの有無）。

想定された修正案（採用は §1-8）:
- 恒常的に出る場合: 索引リンク生成時に、**参照先 id が実在するエントリだけをリンク化**する（存在しない参照は素のテキストへフォールバック）。
- サブセット固有の場合: 「索引付き EPUB は全章ビルドで検証する」旨を明記し、リリーステストで全章ビルドを対象にする。

### A-3. 影響と優先度

- **出版可否**: epubcheck ERROR は厳密には規格違反。多くのリーダーは寛容に表示するが、Amazon/Apple へ出稿する際の検証で弾かれ得るため、RC までに ERROR 0 へ戻すのが望ましい（`epub-pipeline-fix-spec.md` で一度達成済みの品質基準の回復）。
- **本件は用語集・索引に限定**。本文・扉絵/節絵・数式の XHTML は妥当（ERROR 0）。
