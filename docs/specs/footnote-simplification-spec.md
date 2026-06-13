# 脚注処理の簡素化仕様書（Vivliostyle 11 対応）

- 対象: `@vivliostyle/cli` 10.3.1 → **11.0.2**（core 2.40.0 → **2.43.2**）への更新に伴う脚注処理の簡素化
- 起点資料: `docs/specs/vivliostyle_footnotes_report.md`（コアエンジンの脚注改善5点）、`docs/footnote.md`（現行ハックの導入経緯・解決済み記録）
- 方針: **実測バグ対策として導入されたハックを、実ビルド検証で「不要」を確認してから段階撤去する**。リリースノート要約のみを根拠にコードを消さない。
- 進捗メモ: 本仕様は「検証実験 → 段階実装」の2フェーズ構成。Phase 0（検証）の結果次第で Phase 1〜3 の実施可否が決まる。

---

## 0. 前提と非交渉事項（実装前に必ず読むこと）

### 0.1 現行ハックは「投機」ではなく「実測バグ対策」である

`docs/footnote.md`（2026-06 解決済み記録）が示すとおり、現行の脚注処理に含まれる小細工は、いずれも**実機で観測されたバグ**への対処として段階導入された。最大のものは次の重複描画バグである。

> Vivliostyle は、脚注参照リンク `<a href="#fnN">` の解決先要素が `float: footnote` の `aside` 自体である場合、参照のあるページと `aside` のあるページの**両方**に同じ脚注を描画する。（`docs/footnote.md` L5-9）

一方、起点資料 `vivliostyle_footnotes_report.md` は**リリースノート水準の要約**であり、実挙動の検証記録ではない。したがって本仕様の鉄則は次のとおり。

- **検証なしに撤去しない**: 各ハックは「外した状態で実ビルドし、対応バグが再発しないこと」を確認できて初めて撤去対象になる。
- **再現原稿で測る**: 検証は `00-preface.md` の謝辞・著者紹介セクション（`docs/footnote.md` が指定する既知の再現ケース）を中核に行う。
- **PDF を正とする**: 脚注は PDF の版面に出る要素のため、HTML 構造の机上確認ではなく **PDF の目視 + 既存 page_layout テスト**で判定する。

### 0.2 「Vivliostyle 由来」と「VFM/Markdown 由来」を切り分ける

本仕様が触れてよいのは **Vivliostyle のレンダリング挙動に対するハック（系統A）** のみ。VFM/Markdown パーサの癖への対処（系統B）はレポートと無関係であり、**スコープ外**とする（§6）。

| 系統 | 該当 | 本仕様での扱い |
|---|---|---|
| **A. Vivliostyle レンダリング対策** | 不可視 `span#fnN` 二重ノード、`::footnote-marker` 抑制＋自前採番、`@footnote{list-style:none}` | **簡素化候補** |
| **B. VFM/Markdown 整形** | `normalize_definition_ids!`、`repair_table_footnote_definitions!`、`expose_container_footnotes!`、URL自動脚注化、sideimage 配置 | **据え置き（スコープ外）** |

### 0.3 css_updater による上書きはここでは無関係

`--font-*` 変数とは異なり、脚注関連 CSS（`components.css` / `page-settings.css` の `@footnote`・`.page-footnote*`）は `css_updater.rb` の再生成対象**ではない**ため、CSS 直接編集が保持される。ただし root と `lib/project_scaffold/` の両方を同期させること（§5.4）。

---

## 1. 現行フローと簡素化ポイントの全体図

```
[pre]  transform_links_to_footnotes / expose_container_footnotes!   ← 系統B（据え置き）
   │
[VFM]  section.footnotes に <li id="fnN"> 生成
   │
[post] convert_endnotes_to_page_footnotes!
   ├─ normalize_definition_ids! / repair_table_footnote_definitions!  ← 系統B（据え置き）
   ├─ 各参照に対し:
   │    ├─ 不可視 span#fnN（display:none）を挿入  ★H1: 重複描画対策
   │    └─ aside#fnN（float:footnote）を挿入
   ├─ process_sideimage_footnotes! でも不可視 span を挿入  ★H1
   └─ renumber_footnotes_by_document_order! で出現順採番      ★H2 と関連
   │
[css]  aside.page-footnote::before { content: attr(data-footnote-number) }  ★H2: 自前採番
       aside.page-footnote::footnote-marker { content: none }               ★H2: ネイティブ抑制
       @footnote { list-style: none }                                       ★H2
       .page-footnote-inline { display: none }                              ★H1
```

簡素化候補は 3 つ（H1〜H3）。優先度順に §2 で定義する。

---

## 2. 簡素化項目

各項目は **`検証ID`（Phase 0 で測る）→ `撤去ID`（Phase 1〜3 で実装）** の対で記述する。

### H1（最重要）: 不可視 `span#fnN` 二重ノードの撤廃

**現状**: すべての脚注参照について、解決先となる不可視 `<span class="page-footnote-inline" id="fnN" style="display:none">` を `aside` の手前に挿入している。これは「リンク解決先が `float:footnote` の aside 自体だと二重描画される」バグ（§0.1）を避けるための構造。

**該当コード**
- `footnote_converter.rb`:
  - `insert_inline_footnote!`（段落内参照）
  - `insert_print_footnote_after_anchor!`（段落外参照。L168-180 の span 挿入）
  - `build_inline_footnote_node`（不可視 span 生成本体）
  - `insert_footnote_for_anchor!` の分岐（インライン span + aside の二段挿入）
- `post_process.rb:686-691`: `process_sideimage_footnotes!` 内の `build_inline_footnote_node` 呼び出し
- `components.css:120-123, 131-134`: `.page-footnote-inline { display:none !important }`

**レポート対応**: #2「fragmentation／領域制御の修正」「本文と重なるバグの解消」。`float:footnote` の配置・分割信頼性が向上していれば、解決先を `aside` 自体に戻しても二重描画は起きない見込み。

**検証 V-H1（Phase 0）**
1. `00-preface` を CLI 11 で素ビルドし、**現状の PDF**（基準）で謝辞セクションの脚注が各1回・正しい番号で出ることを確認（回帰の基準点）。
2. `build_inline_footnote_node` 由来の不可視 span 挿入を**一時的に外した**ブランチ／作業コピーでビルドし、`href="#fnN"` の解決先が `aside#fnN` のみになる状態を作る。
3. **PDF を目視**し、謝辞セクション・テーブルセル内脚注（`docs/footnote.md` が「3回重複」と記録した箇所）で**二重描画が再発しないこと**を確認する。

**撤去 R-H1（Phase 1。V-H1 が「再発なし」のときのみ）**
- 不可視 span の挿入を全廃。`insert_footnote_for_anchor!` は aside 挿入のみへ単純化。
- `process_sideimage_footnotes!` の span 挿入も削除。
- `.page-footnote-inline` の CSS（display:none 群）を削除。
- `build_inline_footnote_node` は他参照がなくなれば削除（要 grep 確認。`renumber` 系が `span#fnN` を更新しているため §H2 と連動）。

**V-H1 が「再発あり」のとき**: H1 は撤去せず維持。本仕様の H2/H3 のみ検討し、H1 据え置きを findings に記録して終了。

---

### H2: ネイティブ `::footnote-marker` への回帰（自前採番の撤廃）

**現状**: ネイティブのマーカーを `::footnote-marker { content: none }` で潰し、`data-footnote-number` 属性 + `::before { content: attr(...) }` で番号を自前描画。ol 採番も `@footnote { list-style: none }` で抑制。

**該当コード**
- `components.css:145-153`: `aside.page-footnote::before` / `aside.page-footnote::footnote-marker { content: none }`
- `page-settings.css:171-176`: `@footnote { list-style: none; ... }`
- `footnote_converter.rb` `build_print_footnote_node`: `data-footnote-number` 付与
- `post_process.rb`: `renumber_footnotes_by_document_order!` と `update_aside_footnote`（`data-footnote-number` の更新）

**レポート対応**: #3「`::footnote-marker` のぶら下げインデント修正」「`list-style-position: outside` が `::footnote-marker` に効くようになった」。ネイティブマーカーが正しく描画されるなら、自前採番一式を撤去できる。

**重要な前提依存**: H2 は **採番の主体**を「Ruby の出現順採番」から「エンジンの CSS カウンタ（ソース順）」へ移すことを含む。両者は通常一致するが、**ページ毎リセット採番**や **sideimage で DOM 順とページ出現順がずれるケース**で挙動が変わりうる。よって H2 は H1 撤去後（DOM 構造が単純化された後）に検討するのが安全。

**検証 V-H2（Phase 0 で予備調査、Phase 2 直前で本検証）**
1. `::footnote-marker { content: none }` を外し、`data-footnote-number`/`::before` を無効化した状態でビルド。
2. PDF で **(a) 番号がネイティブに出るか (b) 2行以上の脚注でぶら下げ（2行目が番号右に揃う）になるか (c) 出現順が現状と一致するか** を確認。
3. 出現順がずれる場合、`renumber_footnotes_by_document_order!` の役割（採番 vs 並べ替え）を切り分け、**並べ替えのみ残し採番だけネイティブへ委譲**できるか判断。

**撤去 R-H2（Phase 2。V-H2 全項目 OK のときのみ）**
- `::footnote-marker { content: none }`、`aside.page-footnote::before`、`@footnote { list-style: none }` を削除し、ネイティブマーカー + `list-style-position: outside` のぶら下げに委ねる。
- `data-footnote-number` 付与と更新を削除（採番をネイティブ化できた場合）。`renumber_*` の並べ替え機能が必要なら維持。

---

### H3（将来フェーズ・投機的）: DPUB-ARIA ロールによる構造簡素化

**現状**: `build_inline_footnote_node`/`build_print_footnote_node` は既に `role="doc-footnote"`、`process_sideimage_footnotes!` は `role="doc-noteref"` を付与済み。配置自体は `float: footnote` の明示 CSS に依存。

**レポート対応**: #4「`role="doc-noteref"`／`role="doc-footnote"` をコアが直接認識し、CSS非依存で脚注エリアへ自動配置、`::footnote-call` を自動生成」。本当なら `float:footnote` の明示機構をロールマークアップへ寄せられる。

**位置づけ**: 最も投機的で検証コスト最大。**H1/H2 を固めた後の別フェーズ案件**とし、本仕様では「素地（ロール付与）は既に存在する」ことの記録に留める。本仕様のスコープでは**実装しない**（§6）。Phase 0 の余力で `float` 抜き・ロールのみの最小 HTML を試作し、所感を findings に残す程度。

---

## 3. テスト計画

### 3.1 単体テスト（`rake test`。実ビルドなし）

`test/vivlio_starter/cli/post_process/footnote_converter_test.rb`（既存があれば拡張、なければ新規）に、撤去後の HTML 構造を検証するケースを追加する。

- **FN-H1-a**: 段落内参照 → `aside#fnN`（`role="doc-footnote"`）が1つだけ生成され、**不可視 span が生成されない**（R-H1 後）。
- **FN-H1-b**: テーブルセル内参照 → 同上。重複 aside が出ない。
- **FN-H2-a**: `build_print_footnote_node` の出力に **`data-footnote-number` が無い**（R-H2 後）／在る（R-H2 前）。kind で分岐せず素直な属性集合になっていること。
- 既存の `renumber_*` / sideimage 系テストが**緑のまま**であること（系統B非回帰）。

テストは DAMP で、HTML 文字列入出力をパターンマッチ検証する（ruby-coding-rules §5）。

### 3.2 結合検証（実ビルド。`rake test:manual` / `rake test:layout`）

- **FT 系（PDF 非回帰）**: 既存の page_layout / manual テストが緑であること。
- **再現原稿ビルド**: `vs build 00 --no-clean --log=debug` で `00-preface.pdf` を生成し、謝辞・著者紹介セクションの脚注を**目視**（各1回・番号連番・ぶら下げ）。
- **epubcheck**: EPUB 経路（`epub_builder.rb` の脚注後処理）に波及がないこと。ERROR 0 を維持（既存 EP-01/EP-02）。

### 3.3 検証の合否基準（Phase 0 ゲート）

| 検証 | 合格条件 | 不合格時 |
|---|---|---|
| V-H1 | 不可視 span 撤去後、二重描画ゼロ | H1 据え置き・findings 記録 |
| V-H2 | ネイティブ番号 + ぶら下げ + 出現順一致 | H2 据え置きまたは部分採用 |

---

## 4. 実装順序（推奨）

1. **Phase 0（検証・破壊的変更なしの作業コピー）**: V-H1 → V-H2 を実ビルドで測定。結果を `docs/footnote.md` の追記 or 本仕様 §7 に記録。**ここで撤去可否が確定する。**
2. **Phase 1（R-H1）**: V-H1 合格時のみ。不可視 span 全廃 + 単体テスト FN-H1 + 実ビルド非回帰。
3. **Phase 2（R-H2）**: V-H2 合格時のみ。自前採番撤廃 + 単体テスト FN-H2 + 実ビルド非回帰。
4. **Phase 3（H3）**: 別仕様として切り出し（本仕様では着手しない）。

各 Phase は**独立コミット**。バグ修正とリファクタを混ぜない（ruby-coding-rules §6）。Phase 1 と 2 は連動するため、2 は 1 の後に行う。

---

## 5. スコープと影響範囲

### 5.1 変更してよいファイル（Phase 1〜2）

| ファイル | 想定変更 |
|---|---|
| `lib/vivlio_starter/cli/post_process/footnote_converter.rb` | 不可視 span 挿入の削除、`build_print_footnote_node` の `data-footnote-number` 整理 |
| `lib/vivlio_starter/cli/post_process.rb` | `process_sideimage_footnotes!` の span 挿入削除、`renumber_*` の採番/並べ替え整理 |
| `stylesheets/components.css` | `.page-footnote-inline`、`::before`、`::footnote-marker` 関連の削除 |
| `stylesheets/page-settings.css` | `@footnote { list-style: none }` の削除 |
| `lib/project_scaffold/stylesheets/components.css` | 上の同期 |
| `lib/project_scaffold/stylesheets/page-settings.css` | 上の同期 |
| `test/.../footnote_converter_test.rb` | FN-H1/H2 追加 |
| `CHANGELOG.md` | 各 Phase の記録 |

### 5.2 メソッドシグネチャの扱い

`build_inline_footnote_node` / `build_print_footnote_node` は他モジュール（`post_process.rb`）から `FootnoteConverter.build_*` で参照される public メソッド。撤去・引数変更時は**呼び出し元の影響を確認**してから（ruby-coding-rules §8）。R-H1 で `build_inline_footnote_node` を消すなら `process_sideimage_footnotes!` 側の修正と同一コミットで行う。

### 5.3 リリース同期

リリース時は `copy_to_scaffold.rb` が root のアセットを scaffold へ複製するため、**root を正**として編集し、scaffold 側 CSS は同値に保つ（§5.1 の対）。

---

## 6. スコープ外（明示）

- **系統B**（`normalize_definition_ids!`、`repair_table_footnote_definitions!`、`expose_container_footnotes!`、`transform_links_to_footnotes`、sideimage 配置ロジック）: VFM/Markdown 由来でレポートと無関係。**一切触らない。**
- **H3（DPUB-ARIA ネイティブ配置への全面移行）**: 投機的すぎるため本仕様では実装せず、別仕様に分離。
- **`footnote-display: inline / compact`（レポート #1）の採用**: 新機能であり「簡素化」ではない。本仕様の対象外（採用するなら機能追加仕様として別途）。
- **ページ毎リセット採番（レポート #5）への切替**: 現行は出現順通し採番。採番方針の変更は仕様判断を伴うため対象外。

---

## 7. 参照（実装時に読むべき箇所）

- `docs/specs/vivliostyle_footnotes_report.md` — コア改善5点（#2 が H1、#3 が H2、#4 が H3 に対応）
- `docs/footnote.md` — 重複描画バグの根本原因と解決経緯（H1 の背景）
- `lib/vivlio_starter/cli/post_process/footnote_converter.rb` — 章末→ページ脚注変換の本体
- `lib/vivlio_starter/cli/post_process.rb:638-918` — sideimage 脚注・再番号付け・aside 移動
- `stylesheets/components.css:95-154` — `.page-footnote*` スタイル
- `stylesheets/page-settings.css:171-176, 270-299` — `@footnote` / `section.footnotes`

---

## 8. 検証ログ（Phase 0 実施後に追記する）

> 実ビルドで V-H1 / V-H2 を測定したら、ここに「再発有無・PDF 所感・撤去可否の判定」を記録する。
> 本セクションが空のうちは Phase 1 以降に着手しない。
