# vivlio-starter 本体 MIT 化および PDF ワークロード統合仕様書

本書は、以下 4 文書の内容を統合した単一の情報源です。

- `vivlio_starter_purify_spec.md`（本体 MIT 化方針）
- `pdf_reader_spec.md`（`vs pdf:read` 仕様）
- `vivlio_starter_pdf_plan.md`（分離計画とロードマップ）
- `vivlio_starter_pdf_spec.md`（プラグイン API 仕様）

以降、これら個別ファイルは参照不要です。本書のみを最新版として保守します。

---

## 1. プロジェクトの目的

vivlio-starter 本体のライセンスを MIT とし、商用利用や SaaS への組み込みにおける法的な障壁を最小化する。これに伴い、AGPL 依存の HexaPDF 機能を外部プラグイン（`vivlio-starter-pdf`）へ分離し、利用者が Standard / Enhanced の 2 モードから選択できるようにする。

## 2. ライセンスと役割分担

### vivlio-starter (本体)
- **ライセンス**: MIT
- **役割**: Vivliostyle ベースの PDF/print_pdf ビルド、テキスト主体の `vs pdf:read`、CombinePDF/Prawn による簡易ノンブル
- **主な依存**: Prawn / CombinePDF / PDF::Reader

### vivlio-starter-pdf (プラグイン)
- **ライセンス**: AGPL-3.0
- **役割**: HexaPDF を使った隠しノンブル overlay、アウトライン編集、PDF→Markdown 高度変換、OCR、各種ユーティリティ
- **主な依存**: HexaPDF / MiniMagick / ChunkyPNG / RTesseract (任意)

プラグインはオプションであり、未導入でも MIT 本体だけでワークフローは成立する。ただし高度な PDF 後処理・解析・OCR 等はプラグインに委譲する。

---

## 3. PDF ビルド（`vs build` / `print_pdf`）

### 3.1 Standard Mode（MIT 本体）

- **生成フロー**: Vivliostyle で本文 PDF を生成 → CombinePDF で front/back を結合 → Prawn で透明ノンブル PDF を作成しオーバーレイ。
- **実装ポイント**:
  - `Build::Pipeline` で Step6-11 を登録。`pdf_target?` / `print_pdf_target?` は `config/book.yml` の `output.targets` を参照する。@lib/vivlio/starter/cli/build/pipeline.rb#85-165
  - ノンブル：`StandardProvider#stamp_nombre!` が `PDF::Reader` + Prawn + CombinePDF で処理（Odd=左ノド側 90°、Even=右ノド側 -90°）。@lib/vivlio/starter/pdf/standard_provider.rb#36-142
  - アウトライン：Standard Mode では未サポート。Step11 は警告を出してスキップする。@lib/vivlio/starter/pdf/standard_provider.rb#68-77
- **制限**: PDF アウトライン付与／フォント再埋め込み／最適化は不可。必要に応じてプラグイン導入を促すメッセージを表示。

### 3.2 Enhanced Mode（プラグイン）

| 機能 | 詳細 |
| --- | --- |
| 隠しノンブル overlay | HexaPDF overlay canvas で bleed 内へ精密配置。`Vivlio::Starter::PDF::NombreStamper.stamp!` |
| PDF アウトライン付与 | HTML 見出しを基に bookmark ツリーを再構築。`OutlineExtractor.add_outline_from_headings!` |
| メタ情報ユーティリティ | ページ数、ページサイズ、空白ページ生成、アウトライン検査などを HexaPDF ベースで提供 |
| 最適化 | フォント部分埋め込み、PDF/X 準拠チェック、ファイルサイズ圧縮（将来拡張） |

`print_pdf` ステップでは、プラグインがインストールされていれば `Vivlio::Starter::Pdf.provider` が `EnhancedProvider` を返し、Step10/11 で上記機能を呼び出す。プラグイン未導入時は StandardProvider が呼ばれる。

---

## 4. `vs pdf:read` コマンド仕様（Standard & Enhanced）

### 4.1 CLI

```bash
vs pdf:read FILE [--mode=standard|enhanced] [--no-images]
```

- `FILE`: 章トークンまたは PDF パス。TokenResolver で章番号・slug を決定し、`contents/<slug>.md` に出力。
- モードは常に自動判定（プラグインがあれば Enhanced、無ければ Standard）。
- `--no-images`: Enhanced Mode 時に画像埋め込みを抑制。

### 4.2 Standard Mode（MIT）

- `PDF::Reader` でページテキストを抽出し、空行正規化・`---` 区切りを施して Markdown へ変換。
- 出力構造:
  ```
  contents/<slug>.md
  sources/<slug>.pdf (元ファイル保管)
  ```
- 章トークンが未登録の場合は空き番号を払い出し、`catalog.yml` への追記をガイド（実装は CLI 側で制御）。

### 4.3 Enhanced Mode（プラグイン）

- HexaPDF でテキストと画像 XObject を解析し、WebP 変換した画像を `images/<slug>/` へ保存。
- オプションで OCR (Tesseract) やレイアウト保持を行い、Markdown に図版／注釈タグを埋め込む。
- 実行は `Vivlio::Starter::PDF::Reader` に委譲。

### 4.4 アダプタ設計

```ruby
module Vivlio
  module Commands
    class PdfReadCommand
      def call
        adapter.execute
      end

      def adapter
        case resolve_mode
        when :enhanced then EnhancedAdapter.new(pdf_path, options)
        else StandardAdapter.new(pdf_path, options)
        end
      end
    end
  end
end
```

EnhancedAdapter は `require 'vivlio/starter/pdf'` を試行し、失敗すれば `MissingPluginError` を投げて CLI で捕捉→案内文表示。

---

## 5. プラグイン API / CLI 仕様

### 5.0 ディレクトリ配置指針
- PDF 関連の Ruby モジュール（provider, standard/enhanced_provider, adapter 等）は、他の CLI コマンド群と同様に `lib/vivlio/starter/cli/pdf/` 配下へ配置する。
- 既存の `lib/vivlio/starter/pdf` にあるコードは段階的に `cli/pdf` へ移動し、`require_relative` の参照先も合わせて更新する。
- プラグイン側も `lib/vivlio/starter/pdf/...` ではなく、CLI サブコマンド階層と対称になるディレクトリ構成を維持する。

### 5.1 モジュール構成

| クラス | 役割 |
| --- | --- |
| `Vivlio::Starter::PDF::Reader` | PDF→Markdown 変換。画像抽出、OCR、レイアウト保持を担う。 |
| `Vivlio::Starter::PDF::NombreStamper` | HexaPDF overlay による隠しノンブル。 |
| `Vivlio::Starter::PDF::OutlineExtractor` | 見出し情報を受け取り、PDF Outlines を再生成。 |
| `Vivlio::Starter::PDF::Utilities` | ページ数取得、空白ページ生成、アウトライン検査などの共通ユーティリティ。 |
| `Vivlio::Starter::PDF::CLI` | `vs-pdf` サブコマンド（read/nombre/outline/inspect）を提供。 |

### 5.2 API 契約例

```ruby
Vivlio::Starter::PDF::Reader.new(
  pdf_path,
  slug: '01-intro',
  options: { images: true, ocr: false }
).execute
# => { markdown: "...", images: ["images/01-intro/img_001.webp"], warnings: [] }

Vivlio::Starter::PDF::NombreStamper.stamp!(
  'output_print.pdf',
  bleed_mm: 3.0
)

Vivlio::Starter::PDF::OutlineExtractor.add_outline_from_headings!(
  'output_print.pdf',
  headings: [{ level: 1, title: 'Chapter 1', page: 3 }],
  max_level: 3,
  start_page: 1
)
```

### 5.3 CLI（プラグイン同梱）

```bash
vs-pdf read input.pdf --images --ocr
vs-pdf nombre output_print.pdf --bleed=3
vs-pdf outline output_print.pdf headings.json
```

---

## 6. プラグイン開発計画（旧 `vivlio_starter_pdf_plan.md` 相当）

### 6.1 現状の HexaPDF 使用箇所

| 用途 | ファイル | 代替可否 | 備考 |
| --- | --- | --- | --- |
| ページ数取得・空白ページ生成 | `build/utilities.rb` | 可 | MIT ライブラリで代替済み。 |
| 隠しノンブル | `build/nombre_stamper.rb` | 部分的 | Standard は Prawn/CombinePDF、精密版はプラグイン。 |
| PDF アウトライン | `build/outline_extractor.rb` | 不可 | HexaPDF 版をプラグインへ移設。 |
| PDF→Markdown 画像抽出 | `vs pdf:read` | 不可 | プラグイン Reader が担う。 |

### 6.2 ロードマップ

1. **Phase 0**: HexaPDF コード棚卸し（完了）。
2. **Phase 1**: MIT 本体から HexaPDF 依存を削除し、Standard Mode を確立（進行中）。
3. **Phase 2**: `vivlio-starter-pdf` 初期実装（Reader / NombreStamper / OutlineExtractor / Utilities）。
4. **Phase 3**: CLI・ドキュメント整備、`vs-pdf` 配布、ベータ公開。
5. **Phase 4**: OCR・AI 変換等の拡張機能。

### 6.3 今後のタスク

1. `vivlio-starter-pdf` リポジトリ初期化（AGPL LICENSE, CI, テスト基盤）。
2. HexaPDF コードの移設と API 整理。
3. 本体 CLI / ビルドパイプラインのアダプタ実装とメッセージ更新。
4. README / CHANGELOG / THIRD-PARTY-LICENSES の更新。
5. 既存ユーザー向け移行ガイド作成。

---

## 7. 本体（MIT）での実装要件・サンプル

プラグイン非依存で成立させるための実装サンプルは以下のとおり。

### 7.1 プラグイン動的ローダー

```ruby
module Vivlio
  module Starter
    module Pdf
      def self.provider = @provider ||= load_provider

      def self.load_provider
        if ENV['VIVLIO_PDF_PLUGIN'] == 'disable'
          require_relative 'pdf/standard_provider'
          return StandardProvider.new
        end

        require 'vivlio/starter/pdf/enhanced_provider'
        Vivlio::Starter::Pdf::EnhancedProvider.new
      rescue LoadError
        require_relative 'pdf/standard_provider'
        StandardProvider.new
      end
    end
  end
end
```

### 7.2 MIT 代替ライブラリ利用例

- `PDF::Reader` でページ数取得
- `Prawn` で空白ページ生成
- `Prawn + CombinePDF` で簡易ノンブル

（旧 `6.2` 節のコードサンプルをそのまま使用可）

---

## 8. テストとメッセージング

| レイヤー | 観点 |
| --- | --- |
| 本体 (Standard) | `vs build`/`print_pdf` のステップ登録、ノンブル付与、`vs pdf:read` テキスト抽出、モード切替カバレッジ |
| プラグイン | Reader/Nombre/Outline/Utilities の単体テスト、`vs-pdf` CLI、HexaPDF バージョン差分検証 |
| 統合 | プラグイン未導入環境でのフォールバック、`gem install vivlio-starter-pdf` 案内メッセージ、自動モード判定の検証 |

ユーザー向け案内メッセージ（例）:

```
⚠️ 画像抽出や PDF アウトラインを利用するには 'vivlio-starter-pdf' (AGPL) をインストールしてください。
$ gem install vivlio-starter-pdf
```

---

これにより、PDF ビルド・PDF 読み込み・プラグイン開発計画・API 契約がすべて一冊に集約され、MIT 本体と AGPL プラグイン双方の実装/運用をこの文書だけで追跡できる。