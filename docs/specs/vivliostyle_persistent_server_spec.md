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

## 4. 実現可能性の評価

| 方策 | 削減効果 | 実装複雑度 | リスク | 推奨度 |
|------|---------|-----------|--------|--------|
| A: Preview 常駐 + Playwright PDF | ~10s | 高 | PDF 出力差異 | △ |
| B: Playwright 事前起動 | ~1s | 低 | 小 | × (効果不足) |
| C: Step 9 並列ビルド | ~3.5s | 中 | entries.js 競合 | ○ |
| D: Preview 常駐デーモン | ~3s | 低 | preview 干渉 | ○ |

## 5. 推奨アプローチ

### 第 1 段階: 方策 C + D の組み合わせ（低〜中リスク、計 ~6.5s 短縮）

1. **Step 9 並列化 (C)**: front と colophon のビルドを並列実行
   - `vivliostyle.config.js` のテンポラリコピーを作成し、出力先を分離
   - 各スレッドで独立した `entries.js` + config を使用
2. **Preview 再利用 (D)**: 既存 preview サーバーがあればスキップ
   - `PageMappingExtractor#start_preview_server!` にポート確認を追加

### 第 2 段階（将来検討）: 方策 A のプロトタイプ

- Playwright `page.pdf()` と `vivliostyle build` の出力を比較検証
- 差異が許容範囲なら段階的に移行
- vivliostyle CLI のソースコード（`@vivliostyle/cli`）から `Page.printToPDF` のパラメータを調査

## 6. 主要な技術的課題

### 6.1 entries.js の排他制御

現行では全ステップが同一の `entries.js` を上書きしながら使用している。
並列化や常駐化を行う場合、以下のいずれかの対策が必要：

- **一時ファイル方式**: `entries_step9_front.js` のような一時ファイルを生成し、
  対応する `vivliostyle_step9_front.config.js` から参照する
- **ディレクトリ分離**: Step ごとの作業ディレクトリを作成（ファイルコピーのコストあり）

### 6.2 vivliostyle preview のリロード信頼性

`vivliostyle preview` は内部でファイル監視（chokidar）を使用しているが、
プログラム的なリロードトリガーの API は公開されていない。
`page.reload()` で強制リロードは可能だが、レンダリング完了の検知に
現行と同じポーリング（`waitForRenderComplete`）が必要となる。

### 6.3 PDF 出力の一貫性

`vivliostyle build` の内部 Chromium 設定と Playwright `page.pdf()` の設定を
完全に一致させるのは困難。特に以下の点で差異が生じる可能性がある：

- `preferCSSPageSize` パラメータの扱い
- フォントレンダリング（同一 Chromium バージョンでも設定差がありうる）
- `@page` マージンの解釈

## 7. 計測ポイント（実装前に確認すべき事項）

1. `npx vivliostyle build` 1 回あたりの起動オーバーヘッド（組版処理を除く純粋な起動時間）
   - 空の `entries.js`（1 ページのみ）でビルドし、所要時間を計測
2. `vivliostyle preview` のリロード所要時間
   - `entries.js` 変更後、レンダリング安定までの時間
3. Playwright `page.pdf()` と `vivliostyle build` の出力比較
   - ピクセル単位の差分検証（ImageMagick `compare` 等）
