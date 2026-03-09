---
description: PDF OCR における図中文字取り扱い仕様
---

# OCR Inline Image Text Spec

## 1. 背景

- `vs pdf:read` の Enhanced Mode は HexaPDF + OCR により本文テキストと図版を Markdown 化する。
- OCR はページ全体をラスタ化するため、図表や挿絵に描かれた文字（以下「図中文字」）も本文として抽出される。
- 利用者によって「図中文字を残したい」「本文から除外したい」というニーズが分かれるため、`book.yml` から制御できる設定を追加する。

## 2. 対象範囲

- vivlio-starter 本体 (`pdf_read` 設定 / CLI)
- vivlio-starter-pdf プラグイン（OCR 結果整形）
- 設定値の伝播およびテスト

## 3. 用語整理

| 用語 | 説明 |
| --- | --- |
| 図中文字 | 画像内に描かれた文字を OCR が抽出した結果。挿絵の吹き出し、図表ラベル、装飾テキストなどを含む |
| inline image text policy | 図中文字を本文に含めるかどうかを制御する設定 | 

## 4. 機能要件

1. `config/book.yml` `pdf_read.ocr.inline_image_text` を追加し、挙動を `include` / `exclude` / `caption_only` の 3 種類から選択できる。
   - 省略時は `include`（現行挙動）
2. vivlio-starter 本体は設定値を `vs pdf:read` Enhanced Mode の CLI パラメータとして JSON でプラグインへ渡す。
3. vivlio-starter-pdf Reader は設定値に応じ、OCR テキストと画像挿入位置を調整する。
4. Standard Mode は従来通り設定を無視（OCR なし）
5. ドキュメント・テストで挙動を保証する。

## 5. 非機能要件

- 設定は YAML シンボルキー（Ruby 4.0 Data オブジェクト）で扱う。
- 既存プロジェクトは `include` 既定値により互換性を維持。
- 処理コストを最小限にするため、画像領域の再解析を行わず、既存の `image_occurrences` / `lines` 情報から判定する。

## 6. 仕様詳細

### 6.1 `book.yml` の設定項目

```yaml
pdf_read:
  ocr:
    mode: auto
    languages:
      - jpn
    dpi: 300
    psm: 3
    inline_image_text: include # include | exclude | captionize
```

- `languages` は Tesseract の traineddata コード（例: `jpn`, `jpn_vert`, `eng`）を受け取る。上級者は `tesseract --list-langs` で確認できる値をそのまま指定可能。
- 一般向けのシンタックスとして `japanese` → `jpn`, `japanese-vertical` → `jpn_vert` のエイリアスを CLI 側で解決し、他は原則として生の Tesseract コードを利用する。
- `include`: 現状通り、OCR が拾った図中文字を本文行として残す。
- `exclude`: 画像境界（`image_occurrences`）に重なる OCR 行を本文から除去する。
- `captionize`: 図中文字を本文から除去し、対応する `![](…)` 参照ブロック直後にキャプションとしてまとめて出力。

| PSM | 特徴・使い時 | 具体的イメージ |
| --- | --- | --- |
| 3 (Default) | 完全自動。レイアウト解析をすべて Tesseract に任せる。 | 一般的な書類やスキャンデータ |
| 4 | 列（カラム）が分かれている場合に有効。 | 新聞や雑誌、2 段組みの資料 |
| 6 | 単一の均一なテキストブロックとして扱う。 | 本の 1 ページ（1 つの段落） |
| 7 | たった「1 行」だけを読み取る。 | 看板の文字、ラベルの品名 |
| 8 | たった「1 単語」だけを読み取る。 | 商品の価格、ロゴの単語 |
| 10 | たった「1 文字」だけを読み取る。 | 1 文字ずつのマニュアル入力チェック |

### 6.2 CLI からプラグインへの引き渡し

- `PdfReadCommand#enhanced_ocr_settings` に `inline_image_text` キーを追加。
- 値は文字列（`"include"` 等）で JSON 化し、`ocr={...}` パラメータに含める。`languages` は前述のエイリアスをノーマライズしてから渡す。
- 不正値は CLI 側で `include` にフォールバック。

### 6.3 プラグイン側の処理

1. `Vivlio::Starter::PDF::Reader#OcrSettings` に `inline_image_text` 属性を追加。正規化ロジックで `include` / `exclude` / `captionize` を象徴値 `:include` などに変換。
2. `extract_page_ocr_content` の戻り値（`PageContent`）は 1 ページ単位の OCR テキスト。`resolve_page_content` で戻ってきた後、`apply_inline_image_text_policy(PageContent, images)` のようなヘルパを追加し、設定に応じたフィルタリングを行う。
3. 判定アルゴリズム
   - OCR 行の y 座標が無い場合は本文扱い（`lines` が空）なので `exclude` でも残す。
   - `lines` 情報が無い OCR（全面スキャン）では `scanned_page_image?` に基づき、図中文字として扱わない（誤除去防止）。
   - `image_occurrences` の y 範囲 ±閾値（例: 12pt）に収まる行を「画像由来」とみなす。
4. `captionize` の場合は該当行を削除した上で、`build_page_chunk` で `![](…)` ブロック直後に `> caption` 形式などで追加。Markdown 表示上の統一を図る。

### 6.4 テスト

- `vivlio-starter-pdf/test/reader_test.rb`
  - `inline_image_text: exclude` で指定ページの図中文字が除去されること。
  - `inline_image_text: captionize` で画像参照直後にキャプションが生成されること。
- `vivlio-starter/test/vivlio/starter/cli/pdf/pdf_read_command_test.rb`
  - `ocr.inline_image_text` が plugin コマンド引数へ渡ること。

## 7. マイグレーション

1. 既存プロジェクトは設定未入力 ⇒ `include` で従来通り。
2. 図中文字が不要な場合は `book.yml` に `inline_image_text: exclude` を追加。
3. キャプション化したい場合は `captionize` を選択し、Markdown 側でスタイル調整する。

## 8. 今後の拡張アイデア

- ページまたはセクション単位で設定を上書きできるようにする（例: 扉ページのみ `include`）。
- キャプション整形時に textlint / MeCab を用いた誤認補正を行う。
- 図中文字の bounding box を JSON で出力し、CSS で重畳表示する。
