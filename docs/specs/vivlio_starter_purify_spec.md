# vivlio-starter 本体 MIT 化および機能分割仕様書

## 1. プロジェクトの目的

vivlio-starter 本体のライセンスを MIT とし、商用利用や SaaS への組み込みにおける法的な障壁を最小化する。これに伴い、強力だがライセンス制約の強い AGPL ライブラリ（HexaPDF）を本体から完全に分離し、オプショナルなプラグインとして再構成する。

## 2. ライセンスと役割分担

### 2.1 vivlio-starter (本体)

- **ライセンス**: MIT
- **基本方針**: 電子書籍執筆のコアロジックと、MIT ライブラリのみで完結する標準的な出力を提供する。
- **依存関係**: Prawn, CombinePDF, PDF::Reader 等（いずれも MIT または Apache-2.0 互換）。

### 2.2 vivlio-starter-pdf (プラグイン)

- **ライセンス**: AGPL-3.0
- **基本方針**: HexaPDF の高度な機能を活用し、出版クオリティの PDF 後処理や高度な解析機能を提供する。
- **依存関係**: HexaPDF (AGPL-3.0), vivlio-starter。

## 3. 具体的な機能実装案

### 3.1 PDF 生成・編集 (PDF Generation/Edit)

#### 本体 (MIT)

- **コマンド**: `vs pdf:build` (または `print_pdf`)
- **生成**: Vivliostyle 経由での標準出力。
- **ノンブル**: HexaPDF 依存を排除し、CombinePDF を用いたレイヤー合成、または Prawn によるオーバーレイ処理で自前実装。
- **制限**: PDF アウトライン（しおり）の付与は行わない。

#### プラグイン (AGPL)

- **役割**: 本体が生成した PDF に対する「プロ向け後処理」。
- **アウトライン編集**: 目次構造（Markdown/HTML）から PDF アウトラインを生成し、HexaPDF を用いて PDF オブジェクトに注入。
- **最適化**: PDF の構造最適化、フォントの部分埋め込み、ファイルサイズ圧縮。

### 3.2 PDF 読み込み (PDF Reading)

#### 本体 (MIT)

- **コマンド**: `vs pdf:read`
- **モード**: テキスト抽出モード。
- **実装**: PDF::Reader を用いてテキストストリームを解析し、プレーンな Markdown へ変換。
- **制限**: 画像抽出、OCR 連携、複雑なレイアウト解析は行わない。

#### プラグイン (AGPL)

- **コマンド**: `vs pdf:read --full`
- **高機能モード**:
  - 画像抽出: HexaPDF のリソース管理機能で PDF 内の全画像をオリジナル形式で抽出。
  - OCR 連携: 画像化されたページを検出し、外部 OCR ツールと連携してテキスト化。
  - 構造解析: テキストの位置情報を精密に計算し、図版とテキストの配置関係を保持した Markdown を生成。

## 4. アーキテクチャ設計

### 4.1 プラグイン・ローダーの実装

本体側に以下を導入する。

1. 起動時に `vivlio-starter-pdf` がインストールされているか確認。
2. インストール済みなら PDF 処理クラスを HexaPDFAdapter に差し替える（Dependency Injection）。
3. 未導入の場合、アウトライン付与等の機能を「利用不可（要プラグイン）」としてスキップ。

### 4.2 ユーザーインターフェース

- プラグイン未導入時に AGPL 依存機能が呼び出された場合、以下のメッセージを表示する。
  > "Advanced PDF features require 'vivlio-starter-pdf' (AGPL license). To enable, run: gem install vivlio-starter-pdf"

## 5. 移行のメリット

- **ユーザー層の拡大**: SaaS 開発者が vivlio-starter をエンジンとして組み込みやすくなる。
- **保守性の向上**: PDF 生成の基本処理と、HexaPDF を駆使した後処理が分離され、コードの見通しが良くなる。
- **ライセンスの透明性**: ユーザーが「自由（MIT）」か「多機能（AGPL）」かを明確に選択できる。

## 6. 本体MIT化に向けた実装設計とサンプルコード

本体を純粋なMITライセンスで実装・稼働させるため、以下の設計パターンおよびMIT互換ライブラリ（`pdf-reader`, `prawn`, `combine_pdf`）の活用を基本とする。

### 6.1 プラグイン動的ローダー (Adapter Pattern)

本体側（MIT）では、実行時に `vivlio-starter-pdf` プラグインの存在を確認し、プロバイダを切り替える設計とする。

```ruby
# lib/vivlio/starter/pdf/provider.rb
module Vivlio
  module Starter
    module Pdf
      def self.provider
        @provider ||= load_provider
      end

      def self.load_provider
        begin
          # AGPLプラグインのロードを試行
          require 'vivlio/starter/pdf/enhanced_provider'
          Vivlio::Starter::Pdf::EnhancedProvider.new
        rescue LoadError
          # 見つからない場合はMIT版の標準プロバイダを使用
          require 'vivlio/starter/pdf/standard_provider'
          Vivlio::Starter::Pdf::StandardProvider.new
        end
      end
    end
  end
end
```

### 6.2 MIT代替ライブラリによる基本機能の実装案

HexaPDFに依存していた基本機能（メタ情報取得、空白ページ、簡易ノンブル）をMITライブラリで代替するアプローチ。

#### 1. ページ数の取得 (`pdf-reader`)
```ruby
require 'pdf/reader'

def get_page_count(pdf_path)
  reader = PDF::Reader.new(pdf_path)
  reader.page_count
end
```

#### 2. 空白ページの生成 (`prawn`)
HexaPDFの `ensure_blank_page_pdf` などの代替として、Prawnを用いて指定サイズの空PDFを生成する。
```ruby
require 'prawn'

def create_blank_page(output_path, width, height)
  # mm単位などをptに変換して指定
  Prawn::Document.generate(output_path, page_size: [width, height]) do
    # 何も描画せずに保存することで空白ページを作成
  end
end
```

#### 3. 簡易ノンブルの付与 (`prawn` + `combine_pdf`)
MITライブラリには「既存PDFに直接テキストを描画する」単純な機能がないため、①Prawnで透過背景の「ノンブルのみを描画したPDF」を生成し、②CombinePDFで元PDFと合成（オーバーレイ）する。
```ruby
require 'prawn'
require 'combine_pdf'

def stamp_nombre(original_pdf_path, output_pdf_path, page_count)
  # 1. ノンブルだけを描画した透明PDFをPrawnで作る
  nombre_pdf_path = "tmp_nombre.pdf"
  Prawn::Document.generate(nombre_pdf_path, skip_page_creation: true) do |pdf|
    (1..page_count).each do |i|
      pdf.start_new_page
      # フッター位置にページ番号を描画
      pdf.draw_text "#{i}", at: [pdf.bounds.width / 2, 10]
    end
  end

  # 2. CombinePDFで元PDFの各ページに重ね合わせる
  original = CombinePDF.load(original_pdf_path)
  nombre   = CombinePDF.load(nombre_pdf_path)

  original.pages.each_with_index do |page, index|
    page << nombre.pages[index] if nombre.pages[index]
  end

  original.save(output_pdf_path)
end
```

※ **制限事項**: CombinePDFを使った合成では、目次（アウトライン）や一部の複雑なメタデータが欠落する可能性がある。アウトライン保持や高度な編集が必須のユーザーにはAGPLプラグインへの誘導（警告メッセージ等）を行う。