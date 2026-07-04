# P4（ワークスペース分離）着手前 調査報告＋詳細仕様

調査日: 2026-07-03 / 調査者: Claude (Fable 5) /
対象: [vivlioverso-foundation-workplans.md](vivlioverso-foundation-workplans.md) P4 の詳細仕様策定
（個票に「P1〜P3 完了後に詳細仕様を別途起こす」と定められた成果物が本書）。

第 2 部 §4（課題 D）= [vivlioverso-foundation-plan.md](vivlioverso-foundation-plan.md)、
第 1 部 §4 = [vivlioverso-build-investigation.md](vivlioverso-build-investigation.md)。

---

## 0. 結論（先出し）

- **workplan の行番号・所在は P2/P3 で陳腐化している**（snapshot 3 メソッドは pipeline.rb では
  なく `EpubFlow` へ移設済み・`.keep` 退避は `run_final_clean` `pipeline.rb:383-390`・
  entries.js 再生成問題は `PrintPdfBuilder#build_sections!` のコメントに現存）。
  **完了条件の実体はすべて健在**であり、P4 の必要性は変わらない。
- ワークスペースは `.cache/vs/build/{html,pdf,epub,kindle}/` の **4 兄弟・同一深度**構成とする。
  同一深度が本仕様の要：資産への相対プレフィックスが全消費者で共通（`../../../../`）になり、
  html/ から消費者 dir への**コピーが無加工**（バイト同一）で成立する。
- 回帰リスクの核は P3 と同型の「**相対パスの基準**」1 点に、
  「**EPUB パッケージルートの決定**」を加えた 2 点。着手前に **5 つの実験（§6）で確定**する。
  → **実験 E1〜E5 は 2026-07-04 に完了（§6.1）**。config のパスは全て cwd 基準・
  EPUB は「ローカライズ＋entryContext」案で確定・pdf/ 移設のレンダリングは完全一致。
- entries.js の上書き衝突は「dir 分離」だけでは解けない——**固定名 `entries.js` 単一資源の廃止**
  （用途別 entries ファイル＋用途別 config を `--config` で渡す）が本質。EPUB 経路が既に
  この方式（`entries.epub.js` ＋ `vivliostyle.config.epub.js`）で実証済み。PDF 側を揃える。
- ルートの `vivliostyle.config.js` は**著者向け手動フロー（`vs pdf` / `vs entries`）用として残す**
  （P3-4 の `sync_vivliostyle_config_*` 現状維持と整合）。パイプラインは生成 config を使う。

---

## 1. 現状の中間生成物マップ（誰が・どこへ・誰が読むか）

### 1.1 プロジェクトルートに生まれる中間物

| 生成物 | 書き手 | 読み手 | 備考 |
|---|---|---|---|
| `{NN}-slug.md` | `MarkdownPreprocessor`（`output_path = filename`＝ルート直下） | `ConvertCommands`（VFM）、クロスリファレンス Phase 3 が**再書換**（`pre_process.rb:400-404`） | contents/ の写し＋変換 |
| `{NN}-slug.html` | `ConvertCommands`（md と同 dir）→ `PostProcess` が in-place 加工 | PDF/EPUB/Kindle/dedup/outline/toc/techbook **全消費者が共有** | **課題 D の本丸** |
| `_toc.md` / `_toc.html` | `TocGenerator`（base_dir='.'） | PDF 結合・outline | |
| `_indexpage.html` / `_glossarypage.html` | `Index::UnifiedPageBuilder` | PDF・dedup（破壊的書換）・EPUB | |
| `_titlepage/_legalpage/_colophon` | **.md は `.cache/vs/` 済み**（`CACHED_SYSTEM_FILES`）、.html はルート | PDF 前付・print・EPUB | .md 側は分離の先行事例 |
| `_part{N}` | .md は `.cache/vs/`、.html はルート（`part_title_generator.rb`） | PDF・EPUB | 同上 |
| `entries.js` | `EntriesCommands.write_entries`（**固定名・ルート単一**） | `npx vivliostyle build`（ルート config 経由） | §3.2 の衝突源 |
| `entries.epub.js` / `vivliostyle.config.epub.js` | `EpubBuilder` | `vs epub`（`--config` 指定） | **用途別 config の先行事例** |
| `output.pdf` `_sections.pdf` `_titlepage_legalpage.pdf` `_colophon.pdf` `_blank_before_colophon.pdf` | PdfBuilder / PdfMerger | merge・outline・print の min_pages 参照 | |
| `output_print.pdf` `_sections_print.pdf` `_titlepage_legalpage_print.pdf` `_colophon_print.pdf` | PrintPdfBuilder | merge・nombre・outline | |
| `output.epub` → リネーム | vivliostyle → `EpubFlow` | sanitize 群（zip 手術） | |
| `book-settings.css`（EPUB 変種） | `EpubBuilder.bundle_book_settings_for_epub!`（P3） | EPUB copyAsset | P4 で配置再考（§5.4） |
| `.vivliostyle/` | Vivliostyle CLI 自身 | 同 CLI | `workspaceDir` で移設可（§5.6） |

### 1.2 著者資産ディレクトリへ書き込まれる中間物（追補・課題 D の亜種）

- `images/math/`（数式 SVG・前処理が生成）— PDF/EPUB の HTML から参照される
- `images/headings/`（EPUB 扉絵/節絵合成・`HEADINGS_REL_SUBDIR`）
- `images/_epub_assets/`（Kindle の WebP→JPEG 変換先）
- `stylesheets/fonts/google-fonts.css`（FontManager・P3 §7.3-7 で既知）

いずれも clean.rb が個別掃除している。P4 本体のスコープは workplan の 4 完了条件とし、
これらは **P4b（任意・§7.3）**として切り出す（clean 簡素化の恩恵は P4b まで含めて最大化する）。

### 1.3 ルートに残すべきもの（著者向け・移設しない）

最終成果物（`書名.pdf` / `書名_print.pdf` / `書名.epub` / `.kpf`・単章ビルドの
`{basename}.pdf`＝`11-workflow.pdf` 等、複数章指定時は `54-56.pdf`）、
`covers/`、`vivliostyle.config.js`（手動フロー用）、`_index_review.md` 等の著者レビュー用生成物。
※ `pipeline.rb:241/250/260` のコメントは「54.pdf」と記すが実装は `{basename}.pdf` を生成する
（陳腐化コメント・P4 実装時に修正）。

---

## 2. 破壊的書換とハックの現在地（完了条件の実体）

| workplan 完了条件 | 現在の所在 | 実態 |
|---|---|---|
| snapshot 3 メソッド削除 | `EpubFlow`（`epub_flow.rb:36-38, 104-113`）。**メモリ上 Hash** 退避に P2 で改良済み | dedup 隔離（⑦）＋ epub⇄kindle フレーバ隔離の 2 系統。共有 HTML が単一実体である限り消せない |
| `.keep` 退避ハック削除 | `run_final_clean`（`pipeline.rb:383-390`） | 単章最終 PDF が clean パターンに巻き込まれる防御。中間物がルートから消えれば clean が成果物に触れる理由自体が消滅 |
| entries.js 再生成の解消 | `PrintPdfBuilder#build_sections!`（`print_pdf_builder.rb:53-56`）＋ `pdf_builder.rb:80-82` | 前付/奥付ビルドが固定名 entries.js を上書き→本文用を再生成。**固定名単一資源が真因**（dir 分離＋用途別ファイル名で解消） |
| ルートに中間 HTML / `_sections*.pdf` が無い | §1.1 全域 | 本仕様 §4〜5 で移設 |

加えて（workplan 外だが同根で自然解消するもの）:
- **Kindle `--no-clean` の画像汚染**（[test-targets-flaky-issues] で combo 隔離により対処済みの件）
  — 消費者 dir 分離により**構造的に不可能**になる。テストを「隔離運用」から「構造検証」へ格上げできる。
- dedup の破壊的書換は **pdf/ 配下のコピーに閉じる**ため、「dedup 前スナップショット」概念が消える。

---

## 3. 設計仕様

### 3.1 ワークスペース構成

```
.cache/vs/build/
  html/     # 共通 prep の成果（清潔な .md 中間＋章/特殊ページ HTML）。全消費者の複製元
  pdf/      # PDF 消費者（閲覧用＋入稿用）: HTML コピー・dedup はここだけ・中間 PDF 一式
  epub/     # クリーン EPUB 消費者: HTML コピー＋ EPUB rewrite・entries/config・中間 .epub
  kindle/   # Kindle 消費者: HTML コピー（html/ 直系＝dedup 非通過）＋ Kindle rewrite
```

- **4 dir は同一深度（ルートから 4 階層）**。資産への相対プレフィックスが
  `../../../../` で共通になり、html/ → 消費者 dir のコピーは**無加工**で成立する（§3.3）。
- 閲覧用と入稿用は「dedup 済み HTML」を共有するため pdf/ に同居。両者の分離は
  HTML ではなく **entries/config のファイル名**で行う（§3.2）。
- kindle/ は html/ から直接コピー → **dedup 前の全 † / 全索引リンクを自然に保持**
  （現行の snapshot ⑦ と同値。EpubFlow の「復元してから退避」ダンスが消える）。
- print_pdf 単独ビルド（`!t.pdf && t.print_pdf`）も pdf/ を使う（dedup は現行どおり
  `t.any_pdf?` で実行される。経路差なし）。

### 3.2 entries / config の用途別化（固定名単一資源の廃止）

EPUB 経路の既存方式（`entries.epub.js` ＋ `vivliostyle.config.epub.js` を生成し `--config` で
指定）を PDF 側へ一般化する:

| 用途 | entries | config | 出力 |
|---|---|---|---|
| 本文（閲覧用） | `pdf/entries.sections.js` | `pdf/vivliostyle.config.sections.js` | `pdf/_sections.pdf` |
| 前付（title+legal） | `pdf/entries.front.js` | `pdf/vivliostyle.config.front.js` | `pdf/_titlepage_legalpage.pdf` |
| 奥付 | `pdf/entries.colophon.js` | `pdf/vivliostyle.config.colophon.js` | `pdf/_colophon.pdf` |
| 本文（入稿用） | `pdf/entries.sections.js`（共用） | `…config.sections_print.js`（crop/bleed 差分） | `pdf/_sections_print.pdf` |
| EPUB / Kindle | 現行方式を epub/・kindle/ へ移設 | 同 | 同 |

- これにより「上書きされたから再生成」（`print_pdf_builder.rb:53-56` のコメントが記す病理）が
  **概念ごと消滅**する（完了条件 3）。dedup 後の再ビルド（`BacklinkDedupOrchestrator#rebuild_pdf!`）も
  sections 用 config を再実行するだけになる。
- config 生成は `EpubBuilder.generate_epub_config!` を汎化した `Build::VivliostyleConfigWriter`
  （仮称）へ寄せる。title/author/size 等の解決ロジックは 1 箇所になる。
- **ルートの `vivliostyle.config.js` と固定名 `entries.js` は著者向け手動フロー
  （`vs entries` → `vs pdf`）用に現状維持**。`sync_vivliostyle_config_size!/title!`（P3-4）も
  引き続きルート config を保守する。パイプラインだけが生成 config を使う。

### 3.3 相対パスの基準（★最大の実装注意点・P3 §1.3 と同型）

HTML が `.cache/vs/build/{consumer}/` に置かれると、現行の相対参照はすべて破綻する:

| 参照 | 現行（ルート基準） | P4（消費者 dir 基準） | 書き手（choke point） |
|---|---|---|---|
| テーマ CSS | `stylesheets/theme.css` | `../../../../stylesheets/theme.css` | `FrontmatterGenerator.build_base_frontmatter`（1 箇所・P3 で確立） |
| book-settings.css | `.cache/vs/book-settings.css` | `../../book-settings.css` | 同上 |
| 本文画像 | `images/{章}/x.webp` | `../../../../images/{章}/x.webp` | `ImagePathNormalizer`（1 箇所） |
| 数式 SVG | `images/math/…` | 同上プレフィックス | `MathTransformer` |
| techbook インライン style / twemoji | `stylesheets/twemoji/…` 等 | 同上 | `Techbook::Processor` |
| EPUB 合成画像 | `images/headings/…` | 消費者 dir 内へ（§5.4） | `EpubBuilder` |
| 章間リンク | `11-workflow.html#…` | **不変**（同一 dir 内） | — |

- 方針: **生成時に正しいプレフィックスで書く**（コピー時 gsub ではなく）。プレフィックスは
  `Common.asset_prefix`（仮称・ワークスペース有効時 `../../../../`、無効時 `''`）へ一元化し、
  上表の choke point がこれを参照する。段階 1（§7）で prefix `''` のまま配線し出力不変を確認
  →段階 3 で workspace へ切替、という 2 段安全網が組める。
- html/ と消費者 dir が同一深度なので、**コピー後の書換はゼロ**。EPUB/Kindle だけ §5.4 の
  独自事情（パッケージルート）があり、実験 E2 の結果で確定する。
- P3 の `BookSettingsCss` は `.cache/vs/` に留まり **url("../../stylesheets/…") は不変**
  （CSS 相対は CSS ファイル基準のため）。変わるのは HTML 側 link href のみ。

### 3.4 パイプラインの変更点（ステップ表視点）

P2 のステップ表（`full_mode_step_table`）の**行構成は不変**。各ハンドラの読み書き先が変わる:

1. 共通 prep（`preprocess`〜`generate toc html`）: 出力先を html/ へ。
   クロスリファレンス Phase 3 の「ルート直下 .md」走査（`pre_process.rb:340-404`）も html/ へ。
2. `build overall pdf` / `generate entries.js`: html/ → pdf/ へコピーしてから pdf/ で実行。
3. `snapshot pre-dedup html for epub` 行: **削除**（kindle/ ・epub/ が html/ から直接コピーするため不要）。
4. `backlink dedup`: pdf/ 配下のみを書き換える（`PageMappingExtractor` も pdf/ を読む）。
5. `build front pages …`: 特殊ページ HTML を html/ に生成→ pdf/ へコピー、front/colophon config で実行。
6. `merge` / `outline` / `print pdf`: 入出力を pdf/ へ。**最終成果物のリネーム時のみルートへ移動**。
7. `generate epub`: epub/（と kindle/）へ html/ からコピー→各フレーバの rewrite →ビルド。
   `EpubFlow` の snapshot/restore **3 メソッド削除**（完了条件 1）。
8. `final clean`: `.keep` ハック**削除**（完了条件 2）。ワークスペースの掃除は
   `rm_rf .cache/vs/build`（`--no-clean` なら残す＝デバッグ資材が 1 箇所に揃う利点）。
   clean.rb のルート `*.html` / `[0-9][0-9]-*.md` / `_*.pdf` パターンは**旧バージョンの残骸掃除**
   として 1 リリース残し、V2.0 で撤去。

single モード（単章）も同構成（html/ → pdf/）。`rename_single_mode_pdf` はルートへ mv するだけになり、
final clean が成果物に触れる経路が消える。

---

## 4. 回帰リスクの核（実ビルドでしか潰せない 2 点）

1. **EPUB パッケージルート**: vivliostyle は entry と参照資産の共通祖先からパッケージ構造を
   決める。epub/ の HTML が `../../../../images/…` を参照すると共通祖先がプロジェクトルートに
   なり、**EPUB 内に `.cache/…` の dot ディレクトリが混入**する恐れ（P3 §7.2 と同じ OCF/Kindle
   互換問題）。対策候補は §5.4。実験 E2 で確定。
2. **`--config` 指定時の基準ディレクトリ**: entry・output・workspaceDir が config ファイル基準か
   cwd 基準かで、生成 config 内のパス表記が変わる（node_modules 解決のため実行 cwd はルート固定）。
   実験 E1 で確定。

（P3 で最大リスクだったカスケード・画像 url は、今回 CSS 側が不変のため対象外。）

---

## 5. 消費者別の詳細

### 5.1 pdf/（閲覧用＋入稿用）

- コピー: html/ の全 HTML（無加工・同深度）。
- dedup: pdf/ のみ。`dedup_target_exists?` 等のベタ書きパス（`_glossarypage.html` 等）を
  pdf/ 前提へ。`OutlineExtractor` / `PdfMerger.add_outline_to_output_pdf!` の `Dir.glob('*.html')` も。
- 中間 PDF 一式（`_sections.pdf` 等）は pdf/ 内。`sections_min_pages` の既知良参照も pdf/ 内で完結。
- カバー PDF は covers/（著者資産）から読むだけ——不変。

### 5.2 epub/（クリーン）

- コピー: html/ から（dedup 非通過）。既存の共通 rewrite（`mark_body_for_epub!` ほか）を
  epub/ 内で適用。`vivliostyle.config.epub.js` / `entries.epub.js` も epub/ に生成。
- **資産のローカライズ（推奨・E2 の結果次第で確定）**: EPUB が参照する画像・CSS を
  epub/ 配下へコピーし、HTML の参照を epub/ 基準（`images/…` / `stylesheets/…`）へ戻す
  （html/ → epub/ コピー時に `../../../../` プレフィックスを剥がす決定的 gsub）。
  これで (a) パッケージルート＝epub/ になり dot-dir 混入が構造的に消え、
  (b) `images/_epub_assets/` `images/headings/` の著者 dir 汚染も epub/ 内へ移り（P4b 前倒し）、
  (c) P3 の book-settings.css EPUB 変種（ルート直下コピー）も epub/ 内へ引っ越して
  ルートを汚さなくなる。copyAsset excludes は「epub/ 内の必要物」前提へ全面書き直し。
- 代替案（E2 で本案が通る場合のみ）: entryContext 指定でルート祖先のまま dot-dir を回避できる
  なら、資産コピー無しの軽量案を採る。**実験で決める**（workplan の方式 A/B 決定と同じ運用）。

### 5.3 kindle/

- epub/ と同構成（html/ からコピー→ Kindle rewrite → 中間 .epub → KPF）。
- WebP→JPEG 変換先は kindle/ 内（`images/_epub_assets/` 汚染の解消）。
- epub⇄kindle のフレーバ間スナップショットは**不要**（別 dir なので相互汚染が構造的に不可能）。

### 5.4 P3 成果物との整合

- `BookSettingsCss.output_path`＝`.cache/vs/book-settings.css` は**不変**（build/ の外＝
  「設定注入層」と「ビルド作業場」の分離を保つ）。`vs clean --cache` の掃除単位とも整合。
- `FrontmatterGenerator` の link href だけ `../../book-settings.css`（workspace 有効時）へ。
- `bundle_book_settings_for_epub!` は「ルート直下へコピー」→「epub/ 直下へコピー」へ変更
  （クリーン対象パターン `book-settings.css` はルート legacy 掃除として残置）。

### 5.5 テスト影響

- `page_layout_test` / `test:targets`: 最終成果物はルートのまま → **無修正で通るはず**
  （`VsBuilder.find_latest_pdf` はルート glob）。
- `test:targets` の「kindle --no-clean 画像汚染」隔離テスト: 構造検証
  （「kindle ビルド後に images/ 配下へ *_epub_assets が存在しない」等）へ格上げ。
- `--no-clean` 前提で**ルートの中間 HTML を覗くテスト**（robustness / epub_kindle_layout の一部）:
  参照先を `.cache/vs/build/{consumer}/` へ更新。
- 新設: ワークスペース構造の保証テスト（4 dir 生成・ビルド後のルート無汚染・
  `git status` クリーン——P3 の「stylesheets/ 無差分」の拡張版）。

### 5.6 付随整理（同時にやると安い）

- `workspaceDir: '.cache/vs/build/.vivliostyle'` を生成 config に指定し、ルートの
  `.vivliostyle/` を撤去（clean.rb の該当処理も削減）。E1 で挙動確認。

---

## 6. 着手前実験（スパイク・結果を本書へ追記して仕様確定）

| # | 実験 | 確定させる事項 |
|---|---|---|
| E1 | ルート cwd から `npx vivliostyle build --config .cache/vs/build/pdf/config.js` | entry/output/workspaceDir の解決基準（config 基準 or cwd 基準）と node_modules 解決 |
| E2 | epub/ 配下 entry ＋ (a) `../../../../` 参照 (b) ローカライズ参照 の 2 案で EPUB 生成 | パッケージルート決定則・dot-dir 混入有無・copyAsset の挙動 → §5.2 の案選定 |
| E3 | pdf/ 配下 HTML で target-counter / 章間リンク / `@page :nth(1)` 扉絵 | 同一 dir 移設でレンダリング不変か（不変のはず・確認のみ） |
| E4 | `PageMappingExtractor` を pdf/ の HTML で実行 | headless 抽出のパス依存有無 |
| E5 | 単章ビルド（`vs build 11`）を workspace 経由で | single モードの entries/config 経路と `-d`（single-doc）判定の整合 |

### 6.1 実験結果（2026-07-04 実施・全 5 件完了）

環境: vivliostyle CLI 11.0.2 / core 2.43.2。実素材（25 章・394 ページ・リンク注釈 2,414 件）で実施。

#### E1: `--config` のパス解決基準 —— すべて cwd 基準

- config 内の **entry / output / workspaceDir / entryContext は cwd 基準**（config ファイル基準では
  ない）。config と同 dir に置いた entry は解決されず
  `Specified input does not exist: <cwd>/11-workflow.html` で失敗することを確認。
- config 内の ESM `import`（entries ファイル読込）だけは config ファイル基準
  → **entries ファイルは config と同居**でよい（§3.2 の表どおり）。
- 本命案（cwd=ルート固定・生成 config に `.cache/vs/build/pdf/...` の cwd 相対パスを記述）で
  完走。出力も pdf/ 内に着地。node_modules 解決も問題なし。
- **entryContext を pdf/ へ向ける案は PDF では不成立**: dev サーバのルートが entryContext になり
  `../../../../` の上方参照が全 404。しかも 404 でも build は SUCCESS で完走する
  （様式欠落 PDF が黙って生まれる）ため、この経路は封じる。
- workspaceDir ミラーは context（ルート）全体から画像資産を走査コピーする（covers/docs/lib/test
  まで）。現行ルートビルドの `.vivliostyle/` と同一挙動であり新規コストではない。

#### E2: EPUB パッケージルート —— (a) 上方参照案は不成立・(b) ローカライズ＋entryContext で確定

- (a) `../../../../` 参照＋dot-dir パス entry: **ビルド自体が失敗**
  （`ENOENT: .../EPUB/.cache/vs/build/epub/00-preface.html`）。EPUB 内部パスは entry の
  cwd 相対パスがそのまま使われ（共通祖先方式ではない）、資産コピー段が dot ディレクトリを
  スキップするため transpile 段が開けない。§4-1 の懸念「dot-dir 混入」は
  「そもそもビルド不能」というより強い形で確定。
- (b) 資産ローカライズのみ（entry パスに dot-dir が残る）でも同エラー。
- **(b') ローカライズ＋ `entryContext: '.cache/vs/build/epub'` ＋ entries `./xx.html`: 成功**。
  パッケージルート＝epub/・dot-dir 混入ゼロ（`EPUB/00-preface.xhtml` 等のクリーン構造・
  mimetype/META-INF 正常）。**§5.2 の推奨案をこの形（entryContext 併用）で採用**。
  軽量代替案（上方参照＋entryContext・資産コピー無し）は不成立につき棄却。
- 注意: copyAsset 既定は entryContext 配下の資産を**全同梱**する（spike では stylesheets/ を
  丸ごと置いたため twemoji 7,497 ファイル＝46MB が混入）。ローカライズは
  「参照される資産だけの選択コピー」が必須（§5.2 の「excludes 全面書き直し」は
  「必要物だけを epub/ に置く」方式として確定）。

#### E3: pdf/ 移設のレンダリング不変 —— 完全一致

- 全 32 HTML を `../../../../` プレフィックス書換で pdf/ へ複製し、
  entries.sections.js＋config.sections.js（cwd 相対表記）でビルド。
- 基準（ルートビルド）と比較: **394 ページ数・全ページテキスト・MediaBox・
  リンク注釈 2,414 件・画像 XObject 562 件すべて一致**。
  target-counter / 章間リンク / `@page :nth(1)` 扉絵とも差異なし（確認のみ、の想定どおり）。

#### E4: PageMappingExtractor —— パス依存なし・変更点は `-c` の差し替えのみ

- preview は `-c .cache/vs/build/pdf/config.sections.js` で起動可能。フォールバック URL
  `http://localhost:13100/vivliostyle/publication.json` は **workspaceDir を移設しても有効な
  仮想ルート**（readingOrder は `.cache/vs/build/pdf/...` を正しく反映）。
- glossary-link / glossary-backlink / index-term をテスト注入し、3 種とも正しい
  page_index / spine_index（エントリ順と整合）で抽出できた。
- 抽出結果の href には `.cache/vs/build/pdf/` セグメントが入るが、dedup のマッチングは
  anchor_id（fragment）のみで行われるため無害（`backlink_deduplicator.rb:232`）。
- 実装変更点は `launch_preview_process!` のハードコード `-c vivliostyle.config.js` を
  sections 用生成 config へ差し替える 1 点のみ（`page_mapping_extractor.rb:112`）。
- 補足（原稿側の発見）: 現原稿には `config/index_glossary_terms.yml` が無く、
  index_glossary.enabled=true でも glossary-link は実 0 件（辞書なしスキップ）。
  本実験はアンカー注入で検証した。

#### E5: 単章ビルド —— 同方式で成立・`-d` は生成 config と併用不可

- single-mode 生成物の単章 HTML を pdf/ へ複製し entries.single.js＋config.single.js で
  ビルド → ルート単章ビルド（`vs build 11` の 11-workflow.pdf）と
  **5 ページ・全テキスト・MediaBox 一致**。
- `-d` を生成 config と併用すると、**XML パースエラーページ 1 枚の PDF が SUCCESS として
  生成される**（single-doc モードは entry を XML として直読みし、VFM 生成 HTML は
  well-formed XML でないため）。⇒ パイプラインは `-d` を使わない。
  `SingleDocDecider`（env ゲート・ルート config/entries.js 前提）は著者手動フロー専用として
  現状維持（P4 の変更対象外）。
- single モードも full と同じ「html/ → pdf/ コピー＋用途別 entries/config」経路で成立。
  `rename_single_mode_pdf` は pdf/ からルートへの mv になる（§3.4 どおり）。

#### 実験による仕様確定事項（§3〜5 への反映）

1. 生成 config のパス表記は**すべて cwd（ルート）相対**・実行 cwd はルート固定（§4-2 確定）。
   entries ファイルの path も `.cache/vs/build/{consumer}/...` の cwd 相対で書く。
2. PDF 消費者（pdf/）は entryContext 不使用・上方参照 `../../../../` のまま（§3.3 どおり）。
3. EPUB/Kindle 消費者（epub/・kindle/）は**資産ローカライズ＋entryContext 指定**が必須
   （§5.2 の推奨案を entryContext 併用で確定・§4-1 解消）。html/ → epub/ コピー時に
   プレフィックスを剥がす決定的 gsub＋参照資産の選択コピー。
4. copyAsset は「epub/ 内に必要資産だけを置く」前提（excludes 方式の全面書き直し確定）。
5. PageMappingExtractor は preview の `-c` 差し替えのみ・URL パターン不変（§5.1 に追記）。
6. `-d`（single-doc）はパイプラインでは使用しない（生成 config との併用は不可を実証）。

---

## 7. 段階実装（各段で出力同一性を検証・独立コミット可能）

P2/P3 と同じく「現行から採取した基準」に対し各段で `rake test`＋実ビルド突き合わせ
（PDF はページボックス＋テキスト抽出、EPUB は epubcheck＋内部構造）を行う:

1. **プレフィックス配線（出力不変）**: `Common.asset_prefix`（`''`）と workspace パス定数を導入し、
   §3.3 の choke point を prefix 参照へ置換。全成果物バイト同一を確認（安全網）。
   → **完了（2026-07-04）**。閲覧用 400p・入稿用 398p の全ページテキスト一致・
   クリーン EPUB バイト同一・KPF 生成成功を実測（コミット 1b11d778）。
2. **実験 E1〜E5** を実施し、§5.2 の案と config 生成仕様を本書へ追記・確定。
   → **完了（2026-07-04・§6.1）**。
3. **prep 出力を html/ へ移設**＋PDF 消費経路を pdf/ 化（コピー＋用途別 entries/config）。
   → 完了条件 3（entries.js 再生成の解消）・E1/E3/E4 の実証。**最大差分のゲート**。
   → **完了（2026-07-04）**。段階 1（prefix `''` 配線・出力不変実測）と合わせて実装。
   `Build::VivliostyleConfigWriter` 新設・dedup は pdf/ に閉じ
   `snapshot pre-dedup html for epub` ステップを撤去（完了条件 1 の前半）。
   EPUB/Kindle は暫定ブリッジ（html/ → ルートへ prefix 剥がし展開・`EpubFlow`）で
   現行経路のまま。検証: rake test 全緑＋実ビルド突き合わせ（PDF 全ページテキスト一致・
   単章 5p＝E5 一致・ルート無汚染）。
4. **EPUB/Kindle を epub/・kindle/ 化**（E2 の確定案）。`EpubFlow` の snapshot 3 メソッド削除
   → 完了条件 1。epubcheck 緑＋`epub_kindle_layout_test` 緑＋KPF 生成確認。
   → **完了（2026-07-04）**。`stage_consumer_htmls!`（prefix 剥がしコピー）＋
   `localize_assets!`（選択コピー＝旧 copyAsset.excludes の知識を移設・config から
   copyAsset ブロック撤去）＋ `entryContext` 指定の生成 config（entries は `./xx.html`）で
   実装。暫定ブリッジとフレーバ間スナップショットを撤去し、headings 合成画像・
   `_epub_assets` 変換物・book-settings 変種も消費者 dir 内へ（§5.2-b の著者 dir 汚染解消を
   前倒し）。カバーは埋め込み対象の 1 枚だけを dir/covers/ へローカライズ
   （未参照の表 1/表 4 PNG 同梱が消え約 5.7MB 減）。検証: rake test 全緑（1,453）・
   epubcheck 0/0・KPF 生成成功（Error 0）・段階 3 成果物との突き合わせで EPUB 内
   4,128 ファイル全てバイト同一（差分は dcterms:modified と外した PNG 2 点の manifest のみ）・
   PDF 2 点の全ページテキスト一致・ルート無汚染を実測。
   （補足: EPUB 生成 config は E2 スパイクどおり workspaceDir 未指定＝ルート `.vivliostyle`
   が一時生成され final clean が掃除する。移設は段階 5 以降の任意課題とする。）
5. **final clean 刷新**: `.keep` ハック削除（完了条件 2）・ワークスペース一括掃除・
   clean.rb のルートパターンを legacy 掃除へ縮退 → 完了条件 4（ルート無汚染）。
6. **テスト前提更新＋構造保証テスト新設**（§5.5）。`rake test:release` 全緑。

破綻時の切り分けは段階単位。段階 3 が最重量のため、必要なら「章 HTML のみ先行・特殊ページ後続」に
さらに分割して良い。

---

## 8. スコープ外（明示）

- 縦書き・novel テーマ・テーマ CSS セット差し替え（P3 の変数語彙の上に V2.0 で構築）
- `vs pdf` / `vs entries` 等の著者向け単体コマンドの workspace 化（ルート運用のまま）
- `vivliostyle.config.js` 全文生成化（P3-4 の残課題・V2.0）
- P4b（`images/math` 等の prep 段生成物の workspace 化）——§5.2 の資産ローカライズで
  EPUB/Kindle 分は解消するが、PDF が参照する `images/math/` の移設は E3 の結果を見て判断
