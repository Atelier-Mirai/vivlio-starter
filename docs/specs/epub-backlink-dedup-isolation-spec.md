# EPUB を backlink dedup（Step 8）から隔離する 仕様（⑦）

> 作成日: 2026-06-21
> ステータス: **実装済み（2026-06-22）**。`UnifiedBuildPipeline` に Step 7b（pre-dedup snapshot）を追加、`run_step_epub` 冒頭で復元。実測で `targets: epub` 単体と `targets: pdf, epub` の EPUB が †=200・索引リンク=329・本文完全一致を確認。テスト（§4）も † を除かず完全一致＋† 数一致へ強化済み。
> 対象: `targets` に `pdf`/`print_pdf` と `epub`/`kindle` を同時指定したときの EPUB 出力整合性。
> 関連: `lib/vivlio_starter/cli/build/pipeline.rb`（Step 8 / `run_step_epub` / `snapshot_chapter_htmls`）、`lib/vivlio_starter/cli/build/backlink_dedup_orchestrator.rb`、`lib/vivlio_starter/cli/build/epub_builder.rb`、`test/vivlio_starter/targets/target_consistency_test.rb`、`docs/specs/KNOWN_ISSUES.md`（既知の不具合・冒頭の Step 8 項）

---

## 0. 背景・きっかけ

`@vivliostyle/cli` を 11.0.2 へ更新（Node 26 の Chrome 展開デッドロック回避）後に `rake test:targets`（`TargetConsistencyTest`）を実行したところ 4 件失敗。層別の結果:

| # | テスト | 原因 | 状態 |
|---|---|---|---|
| 3 | `test_pdf_consistent_across_single_and_combined`（p.84） | 索引アンカー ID の非決定性 | **解消済み**（別修正） |
| 4 | `test_print_pdf_consistent_across_single_and_combined`（p.83） | 同上 | **解消済み**（別修正） |
| 1 | `test_epub_consistent_across_single_and_combined`（†除く） | **本仕様の対象（Step 8 汚染）** | **解消済み（2026-06-22・本仕様 §3 実装）** |
| 2 | `test_clean_epub_has_no_kindle_degradation` | EPUB/Kindle 越境（別系統） | 未解消・別タスク |

#3/#4 は `IndexMatchScanner#process_term` のアンカー ID 生成を `String#hash`（プロセス毎にシードがランダム化）から `Digest::SHA1.hexdigest(term_text)[0, 12]` へ変更して決定化することで解消した（`idempotency_test` も同時に緑化）。本仕様は残る **#1** を扱う。

---

## 1. 現象（再現結果）

`config/book.yml` の `output.targets` を切り替えて `vs build --no-clean` を 2 回実行し、生成された `_indexpage.html` を直接比較した（2026-06-21 実測）。

| | `targets: epub`（単体） | `targets: pdf, print_pdf, epub`（結合） |
|---|---|---|
| 索引語数 `<dt>` | 23 | 23（**完全一致**） |
| 索引リンク総数 `<a>` | **99** | **73** |
| 章番号マッピング | 同一（例 33→11, 21→4） | 同一 |

語の集合・章番号マッピングは同一だが、**索引語の「出現箇所リンク」数が単体 99 → 結合 73 に減る**。あわせて用語集脚注記号「†」も、結合時は同一 PDF ページ内の 2 回目以降が除去される。

---

## 2. 根本原因

`backlink_dedup_orchestrator.rb` は **`glossary-link` / `glossary-backlink` / `index-term` を一括収集**し、「**同一 PDF ページ内の重複（2 回目以降）を削除**」する。これは PDF として正しい体裁（同一ページに同じ語の † や索引アンカーが複数並ぶのを避ける）。

問題は、この dedup が**共有の章 HTML を直接書き換える**点。フルモードのステップ順は:

```
Step 4 (index scan & build)   … 章 HTML に <span class="index-term" id="idx-…"> を注入
Step 6-7 (toc / 閲覧用 PDF)
Step 8 (backlink dedup)        … 章 HTML を破壊的に書き換え（†・index-term の同一ページ重複を除去）
Step 9-11 (front pages / merge / outline)
Step E (run_step_epub)         … ★ dedup 済みの章 HTML を再利用して EPUB を生成
```

（`register_print_pdf_only_steps_with_epub` でも Step 8 → Step E の順で同じ。）

リフロー型 EPUB に「ページ」概念は無いため、本来 EPUB は **複数回出現＝複数回 † / 全出現リンク**であるべき。ところが PDF を併せてビルドすると、EPUB は **PDF のページ依存 dedup を施した後の章 HTML** を読むため、† と索引リンクが間引かれた状態になる。これが単体/結合での不整合（#1）の正体。

### 設計上の正しい姿

- `targets: epub` 単体 … Step 8 を実行しない（PDF が無い）→ 全 † / 全出現リンク。**これが EPUB のあるべき出力**。
- `targets: pdf, …, epub` … PDF は dedup 後、**EPUB は dedup 前**の章 HTML を使うべき。

### テストが strip_daggers でも落ちる理由

`test_epub_consistent_across_single_and_combined` は既知の † 差を避けるため `strip_daggers` で † を除いて本文比較する。しかし dedup は † だけでなく **`index-term` の出現アンカーも間引く**ため、† を除いても索引ページのリンク数（99 vs 73）が食い違い、テストは落ちる。KNOWN_ISSUES の記述（「† 数が変わる」）は **index-term も間引かれる**点を追記すべき。

---

## 2.5 冪等性（idempotency_test）との関連 — 仮説を実測で検証（2026-06-22）

当初「`IdempotencyTest` のフレーキー失敗（例 p.83→p.26）は **Step 8 backlink dedup の PDF ページ依存**が真因では」という仮説を立てた。これを **dedup ON/OFF の対照実験**で検証した結果、**仮説は支持されなかった**。

### 実験設計

`config/book.yml` を一時改変し、`vs build`（毎回 Step 0 clean を伴う＝build→clean→build 相当）を連続実行、最終 PDF の各ページ抽出テキスト（`PdfInspector.page_texts`）を突き合わせた。`targets: pdf, print_pdf` は **フル構成（pdf, print_pdf, epub, kindle）の PDF 生成経路と同一**（epub/kindle は PDF 確定後に実行し PDF へ触れない）であり、`find_latest_pdf` が実際に拾う **print_pdf も含めて忠実に再現**している。

| 構成 | dedup | #1 | #2 | #3 | 判定 |
|---|---|---|---|---|---|
| `targets: pdf` | **ON** | 376p | 376p | 376p | **完全一致** |
| `targets: pdf` | **OFF** | 378p | 378p | 378p | **完全一致** |
| `targets: pdf, print_pdf` | ON | viewing 376p / print 374p | 同 | 同 | **両 PDF 完全一致** |

計 6 回のクリーンビルドで**本文・ページ数の非決定性はゼロ**。

### 結論

1. **dedup は決定的**。ON は安定して 376p、OFF は安定して 378p（dedup により 2 ページ縮む）。dedup は毎回まったく同じ †/index-term を除去しており、「ページ割付ゆらぎで残す/消す要素が変わる」現象は観測されない。
2. **idempotency 非決定性は再現しない**。以前の p.83→p.26 差は、**索引アンカー ID の `String#hash` → `Digest::SHA1` 決定化（`index_match_scanner.rb`）で既に解消済み**だったと判断する。「dedup がゆらぎを増幅する」という本節の当初仮説は撤回する。
3. **留意**: フレーキーは本質的に間欠的で、6 ビルドのゼロ差は強い証拠だが絶対証明ではない。万一再発する場合、容疑は dedup ではなく **vivliostyle レンダリング層（サブピクセル/改行ゆらぎ）**へ移る。

> なお本節（idempotency）と §1〜§4（#1: EPUB 単体≠結合のアーキ問題）は別件。#1 は target 整合性の構造問題として依然有効であり、⑦ 実装（EPUB を dedup 前 HTML で生成）の対象である。dedup が決定的であることは #1 の実装方針に影響しない。

---

## 3. 実装（2026-06-22 完了・既存機構の再利用）

> **実装結果**: 本節の方針どおり `pipeline.rb` に実装済み。`snapshot_pre_dedup_htmls`（`@pre_dedup_snapshot = snapshot_chapter_htmls`）を新設し、`register_pdf_build_steps` / `register_print_pdf_only_steps_with_epub` の Step 8 直前に **Step 7b（snapshot pre-dedup html for epub）** を `epub_or_kindle_target?` ガード付きで追加。`run_step_epub` 冒頭で `restore_chapter_htmls(@pre_dedup_snapshot)` を実行し、その後に既存の epub→kindle スナップショットを取り直す。検証: `targets: epub` 単体と `targets: pdf, epub` の EPUB が †=200・索引リンク=329・本文完全一致。

`run_step_epub` には既に **`snapshot_chapter_htmls` / `restore_chapter_htmls`**（パス→内容の退避・書き戻し）が存在し、EPUB（クリーン）→ Kindle の相互非汚染に使われている。これを **「Step 8 の前」**にも適用する。

### 方針

1. **Step 8 の直前**（= Step 7 完了直後・dedup 前）に、章 HTML のスナップショットを取る。
   - 取得対象は `EpubBuilder.collect_epub_htmls('.', entries)`（既存 `snapshot_chapter_htmls` と同一）。
   - `epub_or_kindle_target?` が真のときだけ取得（PDF 専用ビルドでは不要）。
   - 保持先はパイプラインのインスタンス変数（例 `@pre_dedup_snapshot`）。
2. **`run_step_epub` の冒頭**で、EPUB ビルド前にこのスナップショットを章 HTML へ書き戻す（dedup 前状態へ復元）。
   - 既存の epub→kindle 用 snapshot は、この「dedup 前スナップショット」を基準に取り直す（クリーン処理前 = dedup 前から複製）。
3. PDF 系成果物は Step 8 後の dedup 済み HTML で既に生成済みのため影響なし（Step 9-11 は Step 8 の後・Step E の前に完了している）。

### 想定変更箇所

- `pipeline.rb`
  - `register_pdf_build_steps` / `register_print_pdf_only_steps_with_epub`: Step 8 の前に「pre-dedup snapshot」ステップを追加（`epub_or_kindle_target?` 時のみ）。
  - `run_step_epub`: 先頭で `restore_chapter_htmls(@pre_dedup_snapshot)` を実行（snapshot がある場合）。その後、現行どおり epub→kindle 非汚染用の snapshot/restore を行う。
- 既存メソッド `snapshot_chapter_htmls` / `restore_chapter_htmls` はそのまま流用可。

### 留意点

- スナップショットは Step 8 直前（index-term 注入済み・dedup 未適用）の状態であること。Step 4（index scan）より後でなければ index-term が含まれない。
- `single` モード（章プレビュー）は Step 8 を実行しない（724 行コメント参照）ため対象外。
- メモリ: 章 HTML 全文をハッシュ保持する。既存の epub→kindle snapshot と同規模で、実績ありのため許容。

---

## 4. テスト方針

- `target_consistency_test.rb`
  - `test_epub_consistent_across_single_and_combined`: 修正後は **† を除かずに**（または除いても）単体==結合になることを確認できる。少なくとも索引リンク数の一致（99==99 等）を担保。
  - 可能なら「EPUB は dedup されない（複数回 † / 全出現リンク）」を明示する専用アサーションを追加。
- リグレッション: PDF / print_pdf 側は従来どおり dedup 済み（同一ページ重複なし）であることを確認（Step 8 の効果は PDF に残す）。
- フルビルド（`rake test:targets` / `test:manual`）で #1 が緑化することを確認。

---

## 5. スコープ外（別タスク）

- **#2** `test_clean_epub_has_no_kindle_degradation`（クリーン EPUB に `vs-kindle` マーカー混入）: EPUB/Kindle 分離の越境バグ。本仕様とは別系統。
- 索引・用語集の epubcheck（RSC-012 等）。

---

## 付録: 確定済みの周辺事実

- 索引アンカー ID は `IndexMatchScanner#process_term`（`index_match_scanner.rb`）で 1 箇所だけ生成。`Digest::SHA1.hexdigest(term_text)[0, 12]` により決定的（`heading_processor.rb` と同イディオム）。
- EPUB の索引ページ番号は `EpubBuilder#rewrite_index_for_epub!` が `build_sequential_chapter_map`（`collect_epub_htmls` の構成順）で章連番を注入。PDF は `stylesheets/index.css` の `target-counter(attr(href url), page)` で実ページ番号を注入。章マップ自体は単体/結合で同一であり、#1 の原因ではない（当初の仮説は再現により否定）。
