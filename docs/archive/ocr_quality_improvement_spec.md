---
description: vivlio-starter-pdf の OCR 精度向上に関する軽量追加仕様
---

# OCR Quality Improvement Spec

## 1. 背景と目的

- `vs pdf:read` Enhanced Mode は HexaPDF + Tesseract による OCR を提供しているが、章扉・挿絵・写植 PDF などで誤認識が残る。
- 本 gem は OCR エンジンそのものではないため、**過大な実装コストを避けつつ**精度を底上げする指針を定義する。
- 既存資産（MeCab, textlint, prh 辞書, did_you_mean など）を流用し、設定とポストプロセスを最小限の追加で拡張する。

## 2. スコープ

- vivlio-starter 本体 (`vs pdf:read` CLI, textlint/prh 設定)
- vivlio-starter-pdf プラグイン（Reader, OCR ヒューリスティック）
- 外部ツール（Tesseract, pdftoppm, ImageMagick）の追加設定
- **非スコープ**: 新規 OCR エンジン導入、ディープラーニングモデル学習、GUI の提供

## 3. 成果物

1. 本仕様書（当ドキュメント）
2. `book.yml` + CLI + Reader で共有する設定項目（DPI/PSM、言語エイリアス、図中文字制御）
3. OCR 後フィルタと自動置換のための再利用ルール（textlint/prh, MeCab 連携）
4. テストとドキュメント更新

## 4. 方針

| レイヤー | 目的 | 優先度 |
| --- | --- | --- |
| 1. Tesseract/画像チューニング | 基礎精度の底上げ (DPI/PSM/言語/前処理) | 高 |
| 2. ポストプロセス | 誤変換を textlint/prh + MeCab で自動修正 | 高 |
| 3. OCR トリガー制御 | 再 OCR 判断の精緻化、複数パラメータ比較 | 中 |
| 4. 辞書リソース | 専門語や縦書き対応を強化 | 中 |

## 5. 詳細仕様

### 5.1 Tesseract / 画像チューニング

1. **DPI / PSM の動的切替**
   - `book.yml` に `ocr.psm_presets` を追加し、ページ種別ごとに `psm` を上書き可能にする（例: `front_matter: 6`, `default: 3`).
   - Reader はページ index / 章扉検出（例: 大見出し + 空行多数）でプリセットを選択。
2. **言語セットの柔軟化**
   - 仕様の通り `japanese` / `japanese_vertical` エイリアスを CLI で `jpn` / `jpn_vert` に変換。
   - `ocr.languages_per_page`（任意）: 英数字比率が高いページは自動で `+eng` を付与する簡易ロジックを検討。
3. **画像前処理（任意設定）**
   - `ocr.preprocess.command` / `enabled` を追加し、`magick -colorspace Gray -deskew 40% -sharpen 0x1` などユーザー定義コマンドを挟めるようにする。
   - 既定は `disabled`。環境に ImageMagick がある場合のみ opt-in。
4. **画像抽出の精度向上**
   - 現状、OCR 実行時に HexaPDF がページ全体を 1 枚の画像として抽出してしまうケースがある（例: `/images/12-three-elements-ocr/page-001-image-01.webp`）。
   - `image_occurrences` 解析を見直し、`/images/10-three-elements-pages/page-001-image-01.webp` のようにページ内に埋め込まれた実画像のみを抽出対象とする。
   - 具体的には「フルページ占有率 >= 0.72 の画像は OCR 用サンプルとして扱い、Markdown への出力対象から除外する」「小さな図版のみ WebP 化する」といったフィルタを追加する。

### 5.2 OCR 後テキストクリーニング

1. **textlint + did_you_mean**
   - `vs pdf:read` 実行後、`vivlio-starter` 側で textlint を optional で走らせる `ocr_post.lint: true` 設定を追加。
   - `did_you_mean` で頻出誤変換候補を集計し、`config/ocr_prh.yml` に自動追記できる CLI サブコマンドを検討。
2. **prh 辞書流用**
   - 既存 `config/prh.yml` へ `category: ocr` を追加し、OCR 固有の置換ルール（例: `ログラミング`→`プログラミング`）を記述。
   - Reader で `sanitize` 後に prh 互換のシンプルな置換機構を呼び出せるようにする（textlint 無しでも有効）。
3. **MeCab 連携**
   - `mecab_newline_cleaner` と同様の設定を流用し、OCR 結果に対して形態素解析。
   - 未知語率 > 閾値 (例: 0.35) の行を「再 OCR 候補」としてログに提示、`--debug` 時のみ詳細を表示。
4. **空白圧縮**
   - `プ ロ グ ラ ミ ン グ` 等を検出する正規表現を `sanitize` に追加。
   - MeCab の品詞情報を利用できる場合は名詞・動詞単位でスペースを除去。

### 5.3 OCR トリガー / 再実行

1. **辞書スコア**
   - `poor_text_extraction?` に `dictionary_score` を追加し、prh/MeCab 結果をもとに再 OCR 判定に寄与。
2. **複数パラメータ比較**
   - `ocr.multi_pass` 設定: `[{ psm: 3 }, { psm: 6 }]` のように指定された複数パラメータで OCR を実行し、`score(text)` が最良のものを採用。
   - スコアは `未知語率 + 断片スコア` の加重和。実行コストを考慮し最大 2 パターンまで。
3. **PDF テキストとのマージ**
   - HexaPDF の素テキストと OCR 結果をマージする `merge_pdf_text: true` 設定を追加。漢字ブロックは OCR、英数字は PDF のまま保持。

### 5.4 辞書リソース

1. **UniDic / Sudachi**
   - 追加辞書は optional。`vs doctor --fix` での導入対象には含めず、ドキュメントにインストール手順を記載。
2. **カスタム語彙 YAML**
   - `config/ocr_vocab.yml` に `correct: 
