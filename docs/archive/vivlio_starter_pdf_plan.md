# vivlio-starter PDF 分離計画書

## 1. 背景と目的

- vivlio-starter 本体を MIT ライセンスで提供し続けるため、HexaPDF (AGPL) に依存する処理をすべて外部プラグインへ移す。  
- PDF 関連機能を「標準（MIT）」「拡張（AGPL）」の 2 レイヤーに明確分離し、利用者が必要に応じて `gem install vivlio-starter-pdf` を選択できるようにする。  
- 本体はテキスト抽出・簡易 PDF ビルドなど MIT で実現できる範囲のみに集中し、HexaPDF 依存処理（画像抽出、アウトライン編集、ノンブル overlay 等）はプラグインが担う。

## 2. 現状の HexaPDF 使用箇所（洗い出し）

| 用途 | ファイル | 主な処理 |
| --- | --- | --- |
| PDF メタ情報取得・空白ページ生成 | `lib/vivlio/starter/cli/build/utilities.rb` | `page_count` のフォールバック、`ensure_blank_page_pdf` など |
| 入稿用 PDF への隠しノンブル書き込み | `lib/vivlio/starter/cli/build/nombre_stamper.rb` | overlay canvas で通しページ番号を描画 |
| 入稿用 PDF へのアウトライン付与 | `lib/vivlio/starter/cli/build/outline_extractor.rb` | 既存アウトラインの削除と新規追加 |
| Print PDF パイプライン呼び出し | `lib/vivlio/starter/cli/build/pipeline.rb` | Step13 で上記モジュールを実行 |
| PDF アウトライン検査スクリプト | `scripts/check_pdf_outlines.rb` | PDF を開いてアウトライン構造を列挙 |
| 仕様書（print_pdf / pdf_reader） | `docs/specs/print_pdf_spec.md` など | HexaPDF 前提の機能記述 |

### 2.1 HexaPDF 依存の代替可否

| 機能 | 代替可否 | 代替案 / 理由 |
| --- | --- | --- |
| ページ数取得 (`page_count`) / 空白 PDF 生成 (`ensure_blank_page_pdf`) | **可** | `PDF::Reader` でページカウント可能。空白 PDF は `Prawn` や `CombinePDF` など MIT 系ライブラリで生成できる。 |
| 隠しノンブル書き込み (`NombreStamper`) | **不可** | 既存 PDF に任意のテキストをオーバーレイする機能を持つ MIT ライブラリが無く、HexaPDF の overlay API に依存。 |
| PDF アウトライン編集 (`OutlineExtractor`) | **不可** | Bookmark ツリー編集をサポートする MIT ライブラリが見当たらず、HexaPDF による直接編集が必要。 |
| PDF→Markdown の画像抽出 (HexaPDF でストリーム解析) | **不可** | 画像ストリーム列挙・フィルタ判定・CCITT デコードを Ruby で提供する MIT ライブラリが無く、HexaPDF が前提。 |
| PDF アウトライン検査スクリプト | **難** | `qpdf` 等の外部ツールに置き換え可能だが、Ruby から Outline をたどるなら HexaPDF が最短。 |

## 3. vivlio-starter / vivlio-starter-pdf の役割分担

| コンポーネント | ライセンス | 役割 |
| --- | --- | --- |
| `vivlio-starter` | MIT | テキスト抽出中心の `vs pdf:read`、Vivliostyle ベースの pdf/print_pdf ビルド、CombinePDF/Prawn による簡易ノンブルなど。 |
| `vivlio-starter-pdf` | AGPL-3.0 | HexaPDF による画像抽出、アウトライン編集、隠しノンブル overlay、OCR、PDF メタ情報ユーティリティを提供。 |

標準機能を本体 `adapter_standard.rb`・拡張機能をプラグイン `adapter_enhanced.rb` へ実装し、CLI からはプラグイン検出によって呼び分ける（詳細は `vivlio_starter_purify_spec.md` を参照）。

## 4. vivlio-starter-pdf の初期スコープ

1. **PDF → Markdown 変換（Enhanced Mode）**
   - HexaPDF で XObject/文字列を解析し、画像抽出 + WebP 変換 + Markdown への埋め込みを行う。
   - OCR オプション（Tesseract 連携）やレイアウト情報保持、図版メタ情報をサポート。
   - TokenResolver との連携は vivlio-starter 本体が行い、プラグインにはファイルパス・slug・章番号を渡す API を用意する。

2. **print_pdf パイプライン拡張**
   - `NombreStamper`（HexaPDF overlay 版）: 高精度な位置制御と塗り足し計算を提供。  
   - `OutlineExtractor`: HTML 見出し → PDF Outlines injection。  
   - `Utilities`: ページ数取得、空白ページ生成、PDF メタ情報解析を HexaPDF 準拠で提供。

3. **CLI / API 提供**
   - `vs pdf:read --mode=enhanced` 実行時に直接呼ばれる `Vivlio::Starter::PDF::Reader` クラスを提供。  
   - 単体利用者向けに `vs-pdf` CLI も同梱し、独立したワークフローでも使えるようにする。

## 5. 実装方針（高レベル設計）

1. プラグイン gem の雛形を作成（AGPL ライセンス、CI、Rubocop、Minitest 等）。
2. 既存 HexaPDF コードをモジュール単位で移植し、`Vivlio::Starter::PDF::*` 名前空間へ整理。
3. vivlio-starter 本体にはアダプタ層を実装し、プラグイン検出で Enhanced Mode を呼び出す。  
   - 優先は `require 'vivlio/starter/pdf'`。ロードできない場合は Standard Mode にフォールバック。
4. CLI / ドキュメント / メッセージを更新し、プラグイン導入を案内。
5. テスト: HexaPDF 依存のユニットテストは新 gem に集約し、本体側はアダプタ境界をモックで検証。

## 6. ロードマップ

1. **Phase 0**: 現状の HexaPDF コードを棚卸し（完了）。
2. **Phase 1**: vivlio-starter 本体から HexaPDF 依存を削除し、Standard Mode を確立（`pdf_reader_spec.md` 更新済み）。
3. **Phase 2**: `vivlio-starter-pdf` の初期実装（Reader / NombreStamper / OutlineExtractor）と API 公開。
4. **Phase 3**: CLI / ドキュメント整備、`vs-pdf` サブコマンド提供、beta 配布。
5. **Phase 4**: OCR・AI 変換などの拡張機能を追加。

## 7. 今後のタスク

1. `vivlio-starter-pdf` リポジトリ初期化（AGPL LICENSE, Gemfile, GitHub Actions）。
2. 既存 HexaPDF コードの移設と、`Vivlio::Starter::PDF::Reader/Nomb reStamper/OutlineExtractor` の API 定義。
3. 本体 CLI・ビルドパイプラインのアダプタ実装とメッセージ更新。
4. ドキュメント群（README / pdf_reader_spec / print_pdf_spec / THIRD-PARTY-LICENSES）を新体制に合わせて改訂。  
5. ベータユーザー向けの移行ガイド作成。

---

この計画書をベースに、MIT 本体の純化と AGPL プラグイン開発を並行して進める。
