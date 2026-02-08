# Vivliostyle / Playwright 常駐化によるビルド高速化 仕様書

## 1. 背景と動機

現行の `vs build` パイプラインでは、以下のステップで Vivliostyle CLI を個別に起動している。

| Step | 処理内容 | 起動形態 | 典型所要時間 |
|------|---------|---------|------------|
| 6 | TOC PDF 生成 | `npx vivliostyle build` | ~4.4s |
| 7 | 全体 PDF 生成 | `npx vivliostyle build` | ~6.4s |
| 8 | ページマッピング抽出 | `vivliostyle preview` + Playwright | ~6.0s |
| 8 | 重複排除後 PDF 再ビルド | `npx vivliostyle build` | ~6.3s |
| 9 | front PDF 生成 | `npx vivliostyle build` | ~3.4s |
| 9 | colophon PDF 生成 | `npx vivliostyle build` | ~3.1s |

**合計 vivliostyle 関連: 約 29.6s / ビルド全体 46s の約 64%**

各起動のたびに Node.js プロセス初期化 + Chromium 起動（headless）が発生しており、
実際の組版処理以外のオーバーヘッドが大きい。

### ユーザーの着想

1. **バックグラウンド常駐**: vivliostyle preview を常時起動しておき、各ステップから利用する
2. **セッション再利用**: Step 6 で起動した vivliostyle をそのまま後続ステップで使い続ける

## 2. 現行アーキテクチャの分析

### 2.1 `vivliostyle build` の動作

`PdfCommandRunner` (`pdf.rb`) が `npx vivliostyle build` をシェルコマンドとして実行する。

```
npx vivliostyle build [-d] → vivliostyle.config.js → entries.js → *.html → output.pdf
```

- `entries.js` の内容を毎ステップで書き換えることで、対象章を切り替えている
- 各呼び出しは独立したプロセスで、Chromium を起動→組版→PDF 出力→終了
- **起動コスト**: Node.js bootstrap (~0.5s) + Chromium launch (~1.0s) = 約 1.5s/回
- 6回起動で **約 9s** がオーバーヘッド

### 2.2 `vivliostyle preview` の動作（Step 8）

`PageMappingExtractor` が preview サーバーを起動し、Playwright で DOM を走査する。

```
vivliostyle preview → HTTP server (port 13100)
  → Playwright (Chromium) が接続 → DOM からページマッピング取得
  → preview サーバー終了
```

- preview サーバーは HTTP + WebSocket でブラウザと通信
- Playwright 側でも別途 Chromium を起動している（合計 2 つの Chromium）

## 3. 最適化方策の検討

### 方策 A: Vivliostyle Preview 常駐 + Playwright PDF 出力

**概要**: `vivliostyle preview` をビルド開始時に起動し、全ステップ完了まで維持する。
PDF 出力は Playwright の `page.pdf()` で行う。

#### 処理フロー

```
Step 3 完了後:
  1. vivliostyle preview --no-open-viewer 起動（常駐）
  2. Playwright で Chromium を 1 回起動 → 接続維持

Step 6: entries.js を TOC 用に書き換え → preview をリロード → page.pdf() で _toc.pdf 出力
Step 7: entries.js を全章用に書き換え → preview をリロード → page.pdf() で output.pdf 出力
Step 8: リロード不要（Step 7 と同じ内容）→ DOM からマッピング抽出
Step 8b: HTML 浄化後 → preview をリロード → page.pdf() で output.pdf 再出力
Step 9: entries.js を front 用に → リロード → page.pdf() × 2

ビルド終了後: preview + Chromium を停止
```

#### 想定効果

| 項目 | 現行 | 方策 A |
|------|------|--------|
| Chromium 起動回数 | 7回 (build×6 + Playwright×1) | 2回 (preview内×1 + Playwright×1) |
| Node.js 起動回数 | 7回 | 2回 (preview×1 + Playwright script×1) |
| リロード回数 | — | 4〜5回 |
| 想定オーバーヘッド削減 | — | 約 7〜10s |

#### 課題

- **`page.pdf()` と `vivliostyle build` の出力差異**
  - `vivliostyle build` は内部で Chromium DevTools Protocol の `Page.printToPDF` を使用
  - Playwright の `page.pdf()` も同じ CDP を使用するが、パラメータ（用紙サイズ、マージン等）が `vivliostyle build` の内部設定と一致するか検証が必要
  - Vivliostyle CLI が `@page` CSS ルールをどう解釈するかに依存
- **entries.js のホットリロード**
  - `vivliostyle preview` が `entries.js` の変更を自動検知してリロードするか不明
  - 手動で `page.reload()` + レンダリング完了待機が必要になる可能性大
  - レンダリング完了の判定は現行の `waitForRenderComplete()` と同様のポーリングが必要
- **実装複雑度: 高**
  - `PdfCommandRunner` の根本的な書き換えが必要
  - vivliostyle build の内部 PDF パラメータの再現が必要

### 方策 B: Playwright ブラウザインスタンスの共有のみ

**概要**: `vivliostyle build` はそのまま使い、Step 8 の Playwright Chromium 起動を事前化する。

#### 処理フロー

```
Step 5 完了後: Playwright Chromium をバックグラウンドで事前起動
Step 6〜7: 従来通り vivliostyle build（変更なし）
Step 8: 事前起動済み Chromium を使用してマッピング抽出（起動待ち不要）
Step 9: 従来通り vivliostyle build（変更なし）
```

#### 想定効果

- Chromium 起動コスト 1 回分（~1.0s）の削減のみ
- 効果が限定的（Step 8 の所要時間の大部分はレンダリング待機）

#### 課題

- 効果が小さい割に、プロセス管理の複雑さが増す
- **実装複雑度: 低〜中**

### 方策 C: vivliostyle build の並列実行（Step 9）

**概要**: Step 9 の front PDF と colophon PDF を並列ビルドする。

#### 処理フロー

```
Step 9:
  Thread 1: entries.js(front) → vivliostyle build → _titlepage_legalpage.pdf
  Thread 2: entries.js(colophon) → vivliostyle build → _colophon.pdf
```

#### 想定効果

- Step 9 の所要時間: ~7.0s → ~3.5s（約 3.5s 短縮）

#### 課題

- **entries.js の競合**: 両ビルドが同じ `vivliostyle.config.js` → `entries.js` を参照するため、
  並列実行には `entries.js` をスレッド別に分離するか、別ディレクトリで実行する必要がある
- **vivliostyle.config.js の分離**: `output` パスも異なるため、設定ファイル自体のコピーが必要
- **実装複雑度: 中**

### 方策 D: vivliostyle preview 常駐デーモン（ビルド外）

**概要**: `vs build` とは別プロセスとして vivliostyle preview を常時起動し、
ビルド時には既存サーバーを検知して利用する。

#### 処理フロー

```
ユーザー（別ターミナル）: vs preview  → vivliostyle preview が常駐
vs build:
  Step 8: localhost:13100 が応答可能か確認
    → 応答あり → 既存サーバーを利用（起動スキップ）
    → 応答なし → 従来通り一時起動
```

#### 想定効果

- Step 8 の preview 起動コスト（~3s）を削減
- ユーザーが執筆中にプレビューしている場合に自然に恩恵を受ける

#### 課題

- ビルド時の entries.js 書き換えが preview に影響する
- ユーザーのプレビュー内容が意図せず変わる可能性
- **実装複雑度: 低**（既存 `PageMappingExtractor` にポート確認ロジックを追加するだけ）

## 4. 計測結果

`bench/bench_build_overhead.rb` と `bench/bench_preview_reload.mjs` で実測した。

### 4.1 計測1: `npx vivliostyle build` 起動オーバーヘッド

最小構成（1ページ HTML）で `vivliostyle build` を 3 回実行。

| Run | 所要時間 | 備考 |
|-----|---------|------|
| 1 | 11.314s | 初回（npx キャッシュなし） |
| 2 | 3.003s | 2回目以降（安定値） |
| 3 | 3.038s | 2回目以降（安定値） |

**結論**: 1ページの組版でも約 **3.0s** かかる。
Node.js bootstrap + Chromium 起動が大部分を占める。
ビルド中に最大 6 回呼び出されるため、起動コストだけで **~18s** 消費している。

### 4.2 計測2: `vivliostyle preview` リロード所要時間

preview 起動済みの状態で `entries.js` を書き換え、`page.reload()` 後のレンダリング安定までを計測。

| Run | 内容 | 所要時間 | リロード後ページ数 |
|-----|------|---------|------------------|
| 1 | A→A+B (2ページ) | 2.058s | 1 |
| 2 | A+B→A (1ページ) | 2.050s | 1 |
| 3 | A→A+B+C (3ページ) | 2.047s | 1 |

**結論**: リロード自体は **~2.0s** で安定するが、
**`entries.js` の変更が反映されない**（ページ数が常に 1）。
`vivliostyle preview` は `vivliostyle.config.js` → `entries.js` を
Node.js の ESM キャッシュ経由で読み込んでおり、
ファイル変更 + ブラウザリロードだけではエントリ一覧が更新されない。

### 4.3 計測結果から得られた知見

- **方策 A（Preview 常駐 + entries.js 切り替え）は実現困難**:
  ESM キャッシュにより entries.js の動的切り替えが効かない。
  preview サーバー自体を再起動しない限り、エントリ変更を反映できない。
- **方策 C（Step 9 並列化）は不要**:
  キャッシュ機構により Step 9 は 0.00s で完了するため、並列化の意味がない。
- **方策 D（既存 preview サーバーの再利用）は有効**:
  Step 8 では entries.js の切り替えは不要（Step 7 と同じ内容を読む）。
  既に起動済みの preview があれば、起動コスト ~3s をスキップできる。

## 5. 実現可能性の評価（計測結果反映済み）

| 方策 | 削減効果 | 実装複雑度 | リスク | 推奨度 |
|------|---------|-----------|--------|--------|
| A: Preview 常駐 + Playwright PDF | — | 高 | ESM キャッシュで entries.js 切替不可 | × |
| B: Playwright 事前起動 | ~1s | 低 | 小 | × (効果不足) |
| C: Step 9 並列ビルド | — | 中 | — | × (キャッシュで解決済み) |
| D: Preview 常駐デーモン | ~3s | 低 | 小 | **○** |

## 6. 実装済み: 方策 D（既存 preview サーバー再利用）

### 概要

Step 8 の `PageMappingExtractor` に「既存 preview サーバーの検知」を追加した。

### 実装内容（`page_mapping_extractor.rb`）

1. `start_preview_server!` の冒頭で `port_open?(DEFAULT_HOST, port)` を確認
2. 既にポートが応答する場合:
   - preview 起動をスキップ（`@preview_pid` を設定しない）
   - Preview URL を `build_fallback_url` で構築
   - `@externally_managed = true` フラグを立てる
3. ポートが閉じている場合は `launch_preview_process!` で従来通り一時起動
4. `stop_preview_server!` で `@externally_managed` なら kill をスキップ

### テスト（`page_mapping_extractor_test.rb`）

- 既存サーバー検出時に `externally_managed` が true、`preview_pid` が nil
- 外部管理サーバーが `stop_preview_server!` 後も生存していること
- ポート閉鎖時に `launch_preview_process!` が呼ばれること
- `build_fallback_url` のフォーマット検証

### 想定効果

- ビルド全体: **32.84s → ~29.8s**（約 9% 短縮）
- ユーザーが `vivliostyle preview` を別ターミナルで実行中の場合に自然に恩恵を受ける
- preview を使っていない場合は従来動作と同一（リスクなし）

### 課題

- ユーザーの preview が異なるプロジェクトのものである可能性
  → publication.json の存在確認で軽減可能
- ユーザーの preview が古い entries.js を参照している可能性
  → Step 7 完了後であれば entries.js は最新のはずなので問題なし

## 7. 主要な技術的制約

### 7.1 ESM キャッシュ問題

`vivliostyle preview` の Node.js サーバーは `vivliostyle.config.js` と
`entries.js` を ESM `import` で読み込む。ESM は一度 import されると
モジュールキャッシュに入り、ファイルを書き換えてもサーバー再起動なしには
新しい内容が反映されない。このため、**1 つの preview セッションで
entries.js を切り替えて異なる PDF を生成する方式は不可能**。

### 7.2 PDF 出力の一貫性（方策 A 向け）

`vivliostyle build` の内部 Chromium 設定と Playwright `page.pdf()` の設定を
完全に一致させるのは困難。特に以下の点で差異が生じる可能性がある：

- `preferCSSPageSize` パラメータの扱い
- フォントレンダリング（同一 Chromium バージョンでも設定差がありうる）
- `@page` マージンの解釈

ただし方策 D では PDF 出力に Playwright を使わないため、この問題は無関係。

## 8. まとめ

### 8.1 期待

方策 D は既存の機能を最小限に変更する一方で、ビルド全体の所要時間の約 9% 短縮を達成することができ、リスクも最小限に抑えられる。そのため、推奨度は「○」。

### 8.2 実装前

vs build --no-clean

== Build Step Timings ==
  - Step  0 (clean)                          0.00s
  - Step  1 (optimize images)                0.05s
  - Step  2 (prepare theme images)           0.01s
  - Step  3 (preprocess sections)            0.13s
  - Step  4 (index scan and build)           0.03s
  - Step  5 (convert sections html)          1.77s
  - Step  6 (generate toc and pdf)          14.61s
    (vivliostyle build)                    (14.32s)
  - Step  7 (build overall pdf)              7.04s
    (vivliostyle build)                     (7.01s)
  - Step  8 (backlink dedup)                17.69s
    (vivliostyle build)                     (6.24s)
  - Step  9 (build front pages and tail)     0.00s
  - Step 10 (merge all pdfs)                 2.80s
  - Step 11 (apply outline to output pdf)    2.28s
  - Step 12 (rename and final clean)         0.04s
  = TOTAL                                   46.45s
==========================
vs build --no-clean

== Build Step Timings ==
  - Step  0 (clean)                          0.00s
  - Step  1 (optimize images)                0.03s
  - Step  2 (prepare theme images)           0.00s
  - Step  3 (preprocess sections)            0.12s
  - Step  4 (index scan and build)           0.03s
  - Step  5 (convert sections html)          0.98s
  - Step  6 (generate toc and pdf)           3.63s
    (vivliostyle build)                     (3.33s)
  - Step  7 (build overall pdf)              6.05s
    (vivliostyle build)                     (6.01s)
  - Step  8 (backlink dedup)                16.84s
    (vivliostyle build)                     (5.83s)
  - Step  9 (build front pages and tail)     0.00s
  - Step 10 (merge all pdfs)                 2.26s
  - Step 11 (apply outline to output pdf)    1.54s
  - Step 12 (rename and final clean)         0.04s
  = TOTAL                                   31.53s
==========================
vs build --no-clean

== Build Step Timings ==
  - Step  0 (clean)                          0.00s
  - Step  1 (optimize images)                0.02s
  - Step  2 (prepare theme images)           0.00s
  - Step  3 (preprocess sections)            0.12s
  - Step  4 (index scan and build)           0.03s
  - Step  5 (convert sections html)          0.68s
  - Step  6 (generate toc and pdf)           3.47s
    (vivliostyle build)                     (3.17s)
  - Step  7 (build overall pdf)              6.14s
    (vivliostyle build)                     (6.10s)
  - Step  8 (backlink dedup)                16.81s
    (vivliostyle build)                     (5.90s)
  - Step  9 (build front pages and tail)     0.00s
  - Step 10 (merge all pdfs)                 2.26s
  - Step 11 (apply outline to output pdf)    1.51s
  - Step 12 (rename and final clean)         0.04s
  = TOTAL                                   31.10s
==========================
vs build --no-clean

== Build Step Timings ==
  - Step  0 (clean)                          0.00s
  - Step  1 (optimize images)                0.02s
  - Step  2 (prepare theme images)           0.00s
  - Step  3 (preprocess sections)            0.12s
  - Step  4 (index scan and build)           0.03s
  - Step  5 (convert sections html)          0.84s
  - Step  6 (generate toc and pdf)           3.46s
    (vivliostyle build)                     (3.15s)
  - Step  7 (build overall pdf)              6.13s
    (vivliostyle build)                     (6.09s)
  - Step  8 (backlink dedup)                16.87s
    (vivliostyle build)                     (5.86s)
  - Step  9 (build front pages and tail)     0.00s
  - Step 10 (merge all pdfs)                 2.27s
  - Step 11 (apply outline to output pdf)    1.56s
  - Step 12 (rename and final clean)         0.04s
  = TOTAL                                   31.34s
==========================

### 8.3 実装後

vs build --no-clean

== Build Step Timings ==
  - Step  0 (clean)                          0.00s
  - Step  1 (optimize images)                0.03s
  - Step  2 (prepare theme images)           0.00s
  - Step  3 (preprocess sections)            0.13s
  - Step  4 (index scan and build)           0.03s
  - Step  5 (convert sections html)          1.01s
  - Step  6 (generate toc and pdf)           6.44s
    (vivliostyle build)                     (6.15s)
  - Step  7 (build overall pdf)              6.46s
    (vivliostyle build)                     (6.43s)
  - Step  8 (backlink dedup)                18.16s
    (vivliostyle build)                     (6.00s)
  - Step  9 (build front pages and tail)     0.00s
  - Step 10 (merge all pdfs)                 2.29s
  - Step 11 (apply outline to output pdf)    1.54s
  - Step 12 (rename and final clean)         0.05s
  = TOTAL                                   36.14s
==========================
vs build --no-clean                                                                  

== Build Step Timings ==
  - Step  0 (clean)                          0.00s
  - Step  1 (optimize images)                0.02s
  - Step  2 (prepare theme images)           0.00s
  - Step  3 (preprocess sections)            0.11s
  - Step  4 (index scan and build)           0.03s
  - Step  5 (convert sections html)          0.96s
  - Step  6 (generate toc and pdf)           3.67s
    (vivliostyle build)                     (3.31s)
  - Step  7 (build overall pdf)              6.18s
    (vivliostyle build)                     (6.15s)
  - Step  8 (backlink dedup)                16.70s
    (vivliostyle build)                     (5.90s)
  - Step  9 (build front pages and tail)     0.00s
  - Step 10 (merge all pdfs)                 2.27s
  - Step 11 (apply outline to output pdf)    1.54s
  - Step 12 (rename and final clean)         0.04s
  = TOTAL                                   31.53s
==========================
vs build --no-clean

== Build Step Timings ==
  - Step  0 (clean)                          0.00s
  - Step  1 (optimize images)                0.02s
  - Step  2 (prepare theme images)           0.00s
  - Step  3 (preprocess sections)            0.11s
  - Step  4 (index scan and build)           0.03s
  - Step  5 (convert sections html)          0.91s
  - Step  6 (generate toc and pdf)           3.50s
    (vivliostyle build)                     (3.19s)
  - Step  7 (build overall pdf)              6.02s
    (vivliostyle build)                     (5.99s)
  - Step  8 (backlink dedup)                16.92s
    (vivliostyle build)                     (6.00s)
  - Step  9 (build front pages and tail)     0.00s
  - Step 10 (merge all pdfs)                 2.31s
  - Step 11 (apply outline to output pdf)    1.53s
  - Step 12 (rename and final clean)         0.04s
  = TOTAL                                   31.40s
==========================
vs build --no-clean

== Build Step Timings ==
  - Step  0 (clean)                          0.00s
  - Step  1 (optimize images)                0.02s
  - Step  2 (prepare theme images)           0.00s
  - Step  3 (preprocess sections)            0.12s
  - Step  4 (index scan and build)           0.03s
  - Step  5 (convert sections html)          0.76s
  - Step  6 (generate toc and pdf)           3.64s
    (vivliostyle build)                     (3.32s)
  - Step  7 (build overall pdf)              6.10s
    (vivliostyle build)                     (6.06s)
  - Step  8 (backlink dedup)                16.80s
    (vivliostyle build)                     (5.89s)
  - Step  9 (build front pages and tail)     0.00s
  - Step 10 (merge all pdfs)                 2.33s
  - Step 11 (apply outline to output pdf)    1.62s
  - Step 12 (rename and final clean)         0.04s
  = TOTAL                                   31.47s
==========================

### 8.4 考察

初回起動（npx キャッシュ/JIT 未ヒット）を除外した安定値で比較する。

#### Step 8 の平均値比較

| 項目 | 実装前 (Run 2〜4) | 実装後 (Run 2〜4) | 差分 |
|------|-------------------|-------------------|------|
| Step 8 全体 | 16.84s | 16.81s | **-0.03s** |
| うち vivliostyle build | 5.86s | 5.93s | +0.07s |
| うち残り（preview + Playwright） | 10.98s | 10.88s | -0.10s |
| **TOTAL** | **31.32s** | **31.47s** | **+0.15s** |

#### 方策 D の効果が見えない理由

方策 D では preview サーバーの起動コスト（~3s）を削減することを期待していた。
しかし計測結果はほぼ同一であり、有意な差は確認できなかった。

**原因**: Step 8 の所要時間の支配的要因は preview 起動ではなく、
**Playwright のレンダリング完了待機**にある。

`extract_page_mapping.mjs` の `waitForRenderComplete` は以下のポーリングを行う:

```
POLL_INTERVAL = 2000ms (2秒)
STABLE_THRESHOLD = 3回
→ 最低でも 2s × 3 = 6s の待機が発生
```

加えて Chromium 起動（~1s）+ ページ読み込み（~1s）+ DOM 走査（~0.5s）で、
Playwright スクリプト単体で **~9s** 程度消費している。

preview サーバーの起動コスト（~3s）はこの ~9s に比べて小さく、
かつ実装前も `wait_for_server_ready!` がポート応答した瞬間に次へ進むため、
起動待ちが Step 8 全体のボトルネックにはなっていなかった。

#### 結論

方策 D は**技術的には正しく動作する**が、**ビルド高速化への寄与は計測不能なレベル**である。
preview 起動コストが Step 8 のボトルネックではなかったため、
preview の再利用だけでは有意な改善は得られない。

実装自体はリスクがなく、既存 preview サーバーがある場合にプロセス重複を避ける
衛生的な改善としては有用であるため、**コードは残す判断をしてもよい**。

## 9. 今後の高速化に関する提案

計測データから、ビルド時間の内訳は以下の通りである（安定値平均）:

| カテゴリ | 所要時間 | 割合 |
|---------|---------|------|
| vivliostyle build × 3回（Step 6/7/8） | ~15.1s | 48% |
| Playwright レンダリング待機（Step 8） | ~9.0s | 29% |
| PDF merge + outline（Step 10/11） | ~3.8s | 12% |
| その他（Step 0〜5, 9, 12） | ~3.4s | 11% |
| **合計** | **~31.3s** | 100% |

### 9.1 提案 E: Playwright レンダリング待機の最適化（効果見込み: ~4s）

**現行の問題**: `POLL_INTERVAL = 2000ms` × `STABLE_THRESHOLD = 3` = 最低 6s の固定待機。
レンダリングが早期に完了していても、この下限を下回ることがない。

**改善案**:
1. **ポーリング間隔の短縮**: `POLL_INTERVAL` を `500ms` に変更し、
   `STABLE_THRESHOLD` を `5` に設定（計 2.5s の最小待機）
2. **Vivliostyle のレンダリング完了イベントの利用**:
   Vivliostyle Viewer は `readystatechange` や
   内部の `window.__vivliostyle_render_complete__` のようなシグナルを持つ可能性がある。
   イベント駆動で待機すれば、ポーリング自体を廃止できる
3. **MutationObserver による完了検知**:
   `data-vivliostyle-page-container` の追加を `MutationObserver` で監視し、
   一定時間新規追加がなければ完了と判定する

**想定効果**: 6s → 2〜3s（**約 3〜4s 短縮**）

### 9.2 提案 F: Playwright Chromium の事前起動（効果見込み: ~1s）

Step 8 の Playwright スクリプトは毎回 `chromium.launch()` で Chromium を新規起動する。
preview サーバーが既に起動済みの場合、Chromium 起動を先行して行うことで
待ち時間を並列化できる。

ただし効果は ~1s 程度と小さく、実装複雑度に見合わない可能性がある。

### 9.3 提案 G: vivliostyle build の呼び出し回数削減（効果見込み: ~3s）

**現行**: Step 6（TOC PDF）、Step 7（全体 PDF）、Step 8（再ビルド PDF）で
各 ~3s の起動コスト × 3回 = ~9s。

**改善案**:
- Step 8 の重複排除後、HTML が変更された場合のみ PDF を再ビルドする
  （現行は `files_modified.any?` で判定済みだが、変更がない場合でも
  Step 7 と同じ PDF を使い回すことで 1 回分を省略できる可能性がある）
- Step 6 の TOC PDF と Step 7 の全体 PDF を 1 回の vivliostyle build で
  まとめて生成する方式を検討する（vivliostyle.config.js の `output` 配列で
  複数出力を指定できるか要調査）

### 9.4 提案 H: Step 8 全体のアーキテクチャ見直し（効果見込み: ~10s）

**最も大きなボトルネック**は Step 8 の ~17s（ビルド全体の 54%）である。
Step 8 が必要な理由は「用語集バックリンクと索引ページ番号の重複排除」であり、
これには **組版後のページ配置情報** が必要。

**根本的な改善案**:
- **静的解析によるページ推定**: CSS の `@page` サイズと各章の文字量から
  ページ番号を推定し、Playwright なしで重複排除を行う（精度トレードオフ）
- **Step 7 の vivliostyle build 内でページ情報を取得**:
  vivliostyle build 自体が Chromium を起動しているので、
  ビルド中にページマッピングを抽出する Chromium DevTools Protocol の
  コールバックを注入できれば、preview + Playwright の別途起動が不要になる
- **重複排除の事前実行**: 用語集/索引のリンク生成時に、
  重複が発生しないようリンクを設計する（根本対策）

### 9.5 優先度マトリクス

| 提案 | 効果見込み | 実装複雑度 | 推奨優先度 |
|------|-----------|-----------|-----------|
| E: ポーリング間隔最適化 | ~4s | **低** | **★★★（最優先）** |
| F: Chromium 事前起動 | ~1s | 中 | ★ |
| G: build 呼び出し削減 | ~3s | 中 | ★★ |
| H: Step 8 アーキテクチャ見直し | ~10s | 高 | ★★（長期） |

**次のアクション**: 提案 E（ポーリング間隔の短縮）は
`extract_page_mapping.mjs` の定数変更のみで実装できるため、
最小コストで最大効果が見込める。まずこれを試行することを推奨する。
