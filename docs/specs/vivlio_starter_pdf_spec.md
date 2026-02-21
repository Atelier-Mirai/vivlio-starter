# vivlio-starter-pdf 仕様書（Enhanced Mode）

## 1. 概要

- **目的**: HexaPDF を活用した高度な PDF 解析・後処理機能を vivlio-starter へ統合するための AGPL プラグイン。
- **対象コマンド**: `vs pdf:read --mode=enhanced`, `vs build` (print_pdf 拡張), `vs-pdf *` サブコマンド。
- **位置づけ**: vivlio-starter 本体（MIT）が提供する Standard Mode を拡張し、画像抽出・OCR・アウトライン編集・隠しノンブルなど出版向け機能を提供する。

## 2. 提供機能

| 分類 | 機能 | 概要 |
| --- | --- | --- |
| PDF→Markdown | 画像抽出 (WebP 化), テキストレイアウト保持, 図表タグ挿入 | HexaPDF でページ内 XObject / 位置情報を解析し、Markdown に埋め込む。 |
| PDF→Markdown | OCR 連携 | スキャンページを検出し、Tesseract など外部 OCR を実行してテキスト化。 |
| PDF→Markdown | 構造化オプション | ページ番号、セクション区切り、脚注・注釈を Markdown に反映。 |
| print_pdf 拡張 | 隠しノンブル overlay | HexaPDF overlay canvas で bleed 内にページ番号を描画。 |
| print_pdf 拡張 | PDF アウトライン付与 | HTML 見出しを解析し、PDF の Outlines ツリーへ書き込み。 |
| 共通ユーティリティ | ページ数・サイズ取得、空白ページ生成、アウトライン検査 | HexaPDF ベースのユーティリティを提供し、build パイプラインや `vs pdf:*` コマンドから利用可能。 |

## 3. アーキテクチャ

```
vivlio-starter (MIT)
│
├── Commands::PdfReadCommand
│     ├── StandardAdapter (PDF::Reader)
│     └── EnhancedAdapter → vivlio-starter-pdf
│
└── Build Pipeline (print_pdf)
      ├── StandardNombre (CombinePDF/Prawn)
      └── EnhancedNombre (vivlio-starter-pdf)
```

- `vivlio-starter-pdf` は `Vivlio::Starter::PDF` 名前空間で API を公開。
- 本体は `require 'vivlio/starter/pdf'` が成功した場合のみ EnhancedAdapter を使用。
- プラグイン単体で `vs-pdf` CLI を提供し、外部ツールとしても利用可能。

## 4. モジュール構成

| モジュール | 役割 | 主要依存 |
| --- | --- | --- |
| `Vivlio::Starter::PDF::Reader` | PDF→Markdown 変換エンジン。画像抽出、OCR、構造化を担当。 | HexaPDF, MiniMagick, ChunkyPNG, RTesseract (オプション) |
| `Vivlio::Starter::PDF::NombreStamper` | 隠しノンブル overlay。bleed 計算と座標制御。 | HexaPDF |
| `Vivlio::Starter::PDF::OutlineExtractor` | HTML > PDF Outlines 書き込み。 | HexaPDF, Nokogiri |
| `Vivlio::Starter::PDF::Utilities` | ページ数、ページサイズ、空白ページ生成、アウトライン検査。 | HexaPDF |
| `Vivlio::Starter::PDF::CLI` | `vs-pdf` サブコマンドの定義（read/nombre/outline）。 | Samovar |

## 5. API 契約

### 5.1 Reader

```ruby
module Vivlio
  module Starter
    module PDF
      class Reader
        def initialize(pdf_path, slug:, options: {})
          # options: images: true/false, ocr: false, layout: :rich 等
        end

        # @return [Hash] { markdown: "...", images: [<path>], warnings: [] }
        def execute
          # 1. HexaPDF::Document.open(pdf_path)
          # 2. ページごとに text + image を抽出
          # 3. Markdown を組み立てる
        end
      end
    end
  end
end
```

- Input: PDF パス、slug、章番号。  
- Output: Markdown テキスト、生成画像パス一覧、警告ログ。  
- 例外: HexaPDF エラー時は `Vivlio::Starter::PDF::Errors::ReadError` を送出。

### 5.2 NombreStamper

```ruby
Vivlio::Starter::PDF::NombreStamper.stamp!(pdf_path, bleed_mm: 3.0)
```

- 既存 PDF 全ページにノンブルを追加。奇数/偶数ページで回転方向を切り替える。  
- 完了後は同一パスへ上書き保存。失敗時は false を返し、ログに理由を出力。

### 5.3 OutlineExtractor

```ruby
Vivlio::Starter::PDF::OutlineExtractor.add_outline_from_headings!(
  pdf_path,
  headings: [
    { level: 1, title: 'Chapter 1', page: 3 },
    ...
  ],
  max_level: 3,
  start_page: 1
)
```

- `headings` は vivlio-starter 本体で計算した章情報を受け取る。  
- PDF から既存アウトラインを削除後、階層ツリーを再生成。

## 6. CLI エントリ

### 6.1 vs pdf:read --mode=enhanced

1. vivlio-starter 本体が EnhancedAdapter を選択すると、下記フローを実行。
2. プラグイン Reader から戻った Markdown/画像を本体の `contents/` / `images/` に保存。
3. 画像出力先の整合性（相対パス）と TokenResolver 連携は本体側で担保。

### 6.2 vs build (print_pdf)

- `output.targets` に `print_pdf` を含む場合、Step13 以降で以下を利用。
  1. `Vivlio::Starter::PDF::NombreStamper.stamp!`
  2. `Vivlio::Starter::PDF::OutlineExtractor.add_outline_from_headings!`
  3. Utilities でページ数検証や空白ページ生成を行う。

### 6.3 vs-pdf CLI（プラグイン同梱）

```bash
vs-pdf read input.pdf --images --ocr
vs-pdf nombre output_print.pdf
vs-pdf outline output_print.pdf headings.json
```

- vivlio-starter 非依存でも動作できるよう、章情報は JSON で渡す。

## 7. ファイル構成（プラグイン側）

```
vivlio-starter-pdf/
├── lib/
│   ├── vivlio/starter/pdf/
│   │   ├── reader.rb
│   │   ├── nombre_stamper.rb
│   │   ├── outline_extractor.rb
│   │   ├── utilities.rb
│   │   └── cli.rb
│   └── vivlio/starter/pdf.rb  # エントリポイント
├── bin/vs-pdf
├── spec/ または test/
└── LICENSE (AGPL-3.0)
```

## 8. テスト方針

| レイヤー | 内容 |
| --- | --- |
| Unit | Reader（画像抽出、OCRフラグ）、NombreStamper（座標）、OutlineExtractor（ツリー構築）、Utilities。 |
| Integration | `vs-pdf read` や `vs build` との連携テスト（サンプル PDF を用意）。 |
| Regression | HexaPDF バージョン差異の吸収、CCITT/JPX など各フィルタの検証。 |

## 9. ドキュメント & メッセージ

- README: インストール手順 (`gem install vivlio-starter-pdf`) と使用例。  
- 本体 CLI: プラグイン未導入時に以下メッセージを表示。
  ```
  ⚠️ 画像抽出や PDF アウトラインを利用するには 'vivlio-starter-pdf' (AGPL) をインストールしてください。
  $ gem install vivlio-starter-pdf
  ```
- CHANGELOG: MIT 本体と AGPL プラグインのリリースノートを分離。

---

この仕様に沿って `vivlio-starter-pdf` を実装することで、MIT 本体のシンプルさを保ちながら、必要なユーザーに出版レベルの PDF 変換・後処理機能を提供できる。
