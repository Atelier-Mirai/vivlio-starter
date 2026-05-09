# 実装仕様書：`vs pdf:pages` / `vs pdf:rasterize`

**バージョン**: 1.0.0-draft  
**対象**: Vivlio Starter Gem  
**作成日**: 2026-05-08

---

## 1. 概要

### 1.1 コマンド一覧

| コマンド | 目的 |
|---|---|
| `vs pdf:pages` | PDFをページ単位でJPEG画像に切り出す（技術書典掲載用等） |
| `vs pdf:rasterize` | PDFをラスタライズして再結合する（Type3フォント対策） |

### 1.2 処理フロー

```
vs pdf:pages
  PDF → [pdftoppm] → JPEG × n枚（任意ページ指定可）

vs pdf:rasterize
  PDF → [pdftoppm] → JPEG × 全ページ → [JpegToPdf 独自実装] → ラスタライズPDF
```

**PDF→JPEG変換**は両コマンドで共通処理。内部モジュール `PdfToJpeg` として実装し、両コマンドから呼び出す。

---

## 2. コマンド仕様

### 2.1 `vs pdf:pages`

#### 使用法

```
vs pdf:pages [PDF_FILE] [options]
```

`PDF_FILE` 省略時は、`config/book.yml` に定義された（導かれる）出力PDFを使用する。

#### オプション

| オプション | デフォルト | 説明 |
|---|---|---|
| `--dpi=VALUE` | `350` | 解像度（dpi）|
| `--quality=VALUE` | `95` | JPEG品質（1〜100） |
| `--output=DIR` | `<basename>_images/` | 出力ディレクトリ |
| `--pages=SPEC` | 全ページ | ページ指定（例: `"1,3,5-8"`） |

この内、`--dpi`、`--quality`、`--output` は共通オプションで、`--pages` は `pdf:pages` 固有のオプション。

#### ページ指定の書式

```
"1"        # 1ページのみ
"1,3,5"    # 1・3・5ページ
"1-4"      # 1〜4ページ
"1,3,5-8"  # 1・3・5〜8ページ（複合指定）
```

#### 出力

```
<basename>_images/
  page-001.jpg
  page-002.jpg
  ...
```

- **常に全ページを自前で生成する**。`vs pdf:rasterize` の成果物（dpiやqualityが異なる可能性あり）は参照しない。
- 作業ディレクトリ `<basename>_images/` が既に存在する場合は**削除して新規作成する**。これにより前回実行の残留ファイルが混入しない。

ファイル名の桁数は `pdftoppm` がページ総数に応じて自動で決定する（例: 99ページ以下なら2桁、100ページ以上なら3桁）。`--pages` 指定時は、指定したページのみ出力される。ファイル名はオリジナルのページ番号を維持する（例: 3ページ目は `page-003.jpg`）。

#### 実行例

```bash
# 全ページ切り出し（デフォルト350dpi）
vs pdf:pages vivlio_starter_v1.0.0.pdf

# 技術書典掲載用：指定ページのみ高解像度で切り出し
vs pdf:pages vivlio_starter_v1.0.0.pdf --pages="1,3,5-8" --dpi=600

# 出力先を指定
vs pdf:pages vivlio_starter_v1.0.0.pdf --output=./thumbnails
```

---

### 2.2 `vs pdf:rasterize`

#### 使用法

```
vs pdf:rasterize [PDF_FILE] [options]
```

`PDF_FILE` 省略時は `vs pdf:pages` と同様。

#### オプション

| オプション | デフォルト | 説明 |
|---|---|---|
| `--dpi=VALUE` | `350` | 解像度（dpi） |
| `--quality=VALUE` | `95` | JPEG品質（1〜100） |
| `--output=DIR` | `<basename>_images/` | 中間ファイルの出力ディレクトリ |
| `--clean` | false（残す） | 中間JPEGを処理後に削除する |

この内、`--dpi`、`--quality`、`--output` は共通オプションで、`--clean` は `pdf:rasterize` 固有のオプション。


#### 動作仕様

- **常に全ページを自前で生成する**。`vs pdf:pages` の成果物（部分指定JPEGの可能性あり）は参照しない。
- 作業ディレクトリ `<basename>_images/` が既に存在する場合は**削除して新規作成する**。これにより前回実行の残留ファイルが混入しない。
- 中間JPEGはデフォルトで残す。削除したい場合は `--clean` を指定する。
- 出力PDFファイル名は `<basename>_rasterized.pdf` とする。

#### 出力

```
<basename>_images/          ← 中間JPEG（--clean 未指定時は残る）
  page-001.jpg
  page-002.jpg
  ...
<basename>_rasterized.pdf   ← ラスタライズ済みPDF
```

#### 実行例

```bash
# ラスタライズPDFを生成（中間JPEGも残す）
vs pdf:rasterize vivlio_starter_v1.0.0.pdf

# 中間JPEGを削除して生成
vs pdf:rasterize vivlio_starter_v1.0.0.pdf --clean

# 高解像度でラスタライズ
vs pdf:rasterize vivlio_starter_v1.0.0.pdf --dpi=600
```

---

## 3. 内部実装

### 3.1 ファイル構成

```
lib/vivlio_starter/
  pdf/
    pdf_to_jpeg.rb      # 共通モジュール：PDF→JPEG変換
    jpeg_to_pdf.rb      # pdf:rasterize 専用：JPEG→PDF結合
  commands/
    pdf_pages.rb        # vs pdf:pages コマンド
    pdf_rasterize.rb    # vs pdf:rasterize コマンド
```

### 3.2 共通モジュール `PdfToJpeg`

```ruby
# lib/vivlio_starter/pdf/pdf_to_jpeg.rb
# frozen_string_literal: true

module VivlioStarter
  module Pdf
    module PdfToJpeg
      # PDF を JPEG に変換し、画像パスの配列を返す
      #
      # @param pdf_path   [String]       入力PDFのパス
      # @param output_dir [String]       出力ディレクトリ
      # @param dpi        [Integer]      解像度（デフォルト 350）
      # @param quality    [Integer]      JPEG品質（デフォルト 95）
      # @param pages      [String, nil]  ページ指定文字列（例: "1,3,5-8"）
      # @return           [Array<String>] 生成されたJPEGパスの配列（ソート済み）
      def self.convert(pdf_path, output_dir:, dpi: 350, quality: 95, pages: nil)
        FileUtils.mkdir_p(output_dir)
        prefix = File.join(output_dir, "page")

        command = build_command(pdf_path, prefix, dpi, quality)
        execute!(command)

        all_images = Dir.glob(File.join(output_dir, "page-*.jpg")).sort
        filter_pages(all_images, pages)
      end

      private

      def self.build_command(pdf_path, prefix, dpi, quality)
        [
          "pdftoppm",
          "-jpeg",
          "-jpegopt", "quality=#{quality}",
          "-r", dpi.to_s,
          pdf_path,
          prefix
        ]
      end

      def self.execute!(command)
        return if system(*command)

        raise VivlioStarter::Error, "pdftoppm の実行に失敗しました: #{command.join(' ')}"
      end

      def self.filter_pages(images, pages)
        return images if pages.nil?

        indices = parse_page_spec(pages)
        images.select.with_index(1) { |_, i| indices.include?(i) }
      end

      def self.parse_page_spec(spec)
        # "1,3,5-8" → [1, 3, 5, 6, 7, 8]
        spec.split(",").flat_map do |part|
          if part.include?("-")
            start_page, end_page = part.split("-").map(&:to_i)
            (start_page..end_page).to_a
          else
            [part.to_i]
          end
        end.uniq.sort
      end
    end
  end
end
```

### 3.3 `JpegToPdf` モジュール（独自実装）

外部コマンド・gem への依存なし。PDFフォーマットを直接生成する。
AGPLライセンスのHexaPDF、およびPython依存のimg2pdfをいずれも使用しない。

JPEGデータはそのままPDFのストリームに埋め込む（`/Filter /DCTDecode`）。ページ寸法はJPEGのSOFマーカーから取得する。

```ruby
# lib/vivlio_starter/pdf/jpeg_to_pdf.rb
# frozen_string_literal: true

module VivlioStarter
  module Pdf
    module JpegToPdf
      # JPEG 画像群を1つの PDF に結合する（外部依存なし・独自実装）
      #
      # @param images     [Array<String>] JPEGパスの配列（ソート済みであること）
      # @param output_pdf [String]        出力PDFのパス
      def self.convert(images, output_pdf)
        raise VivlioStarter::Error, "結合対象の画像がありません" if images.empty?

        PdfBuilder.new(images).write(output_pdf)
      end

      # --- 内部クラス ---

      class PdfBuilder
        def initialize(image_paths)
          @image_paths = image_paths
          @xref        = {}   # obj_id => byte offset
          @body        = +""
          @obj_count   = 0
        end

        def write(output_pdf)
          page_obj_ids  = []
          image_obj_ids = []

          @image_paths.each do |path|
            jpeg_data      = File.binread(path)
            width, height  = JpegInfo.dimensions(jpeg_data)

            img_id  = emit_image_obj(jpeg_data, width, height)
            page_id = emit_page_obj(img_id, width, height)

            image_obj_ids << img_id
            page_obj_ids  << page_id
          end

          pages_id  = emit_pages_obj(page_obj_ids)
          catalog_id = emit_catalog_obj(pages_id)

          # pages オブジェクトに親参照を埋め込むため、後から parent を書き換える
          # （シンプル実装のため、ここでは pages_id を各 page に直接渡している）

          pdf = build_pdf
          File.binwrite(output_pdf, pdf)
        end

        private

        def next_id
          @obj_count += 1
        end

        def emit_image_obj(jpeg_data, width, height)
          id = next_id
          header = "#{id} 0 obj\n" \
                   "<< /Type /XObject /Subtype /Image\n" \
                   "   /Width #{width} /Height #{height}\n" \
                   "   /ColorSpace /DeviceRGB /BitsPerComponent 8\n" \
                   "   /Filter /DCTDecode /Length #{jpeg_data.bytesize} >>\n" \
                   "stream\n"
          @body << record_offset(id) { header + jpeg_data + "\nendstream\nendobj\n" }
          id
        end

        def emit_page_obj(img_id, width, height)
          id      = next_id
          content = "q #{width} 0 0 #{height} 0 0 cm /Im#{img_id} Do Q"
          @body << record_offset(id) do
            "#{id} 0 obj\n" \
            "<< /Type /Page /Parent 1 0 R\n" \
            "   /MediaBox [0 0 #{width} #{height}]\n" \
            "   /Resources << /XObject << /Im#{img_id} #{img_id} 0 R >> >>\n" \
            "   /Contents #{id} 0 R >>\nendobj\n"
          end
          id
        end

        def emit_pages_obj(page_ids)
          # pages オブジェクトは obj id=1 固定
          kids = page_ids.map { "#{_1} 0 R" }.join(" ")
          @body << record_offset(1) do
            "1 0 obj\n<< /Type /Pages /Kids [#{kids}] /Count #{page_ids.size} >>\nendobj\n"
          end
          1
        end

        def emit_catalog_obj(pages_id)
          id = next_id
          @body << record_offset(id) do
            "#{id} 0 obj\n<< /Type /Catalog /Pages #{pages_id} 0 R >>\nendobj\n"
          end
          id
        end

        def record_offset(id, &block)
          content = block.call
          @xref[id] = @body.bytesize
          content
        end

        def build_pdf
          header   = "%PDF-1.4\n"
          xref_pos = header.bytesize + @body.bytesize

          xref = build_xref
          trailer = "trailer\n<< /Size #{@obj_count + 1} /Root #{@obj_count} 0 R >>\n" \
                    "startxref\n#{xref_pos}\n%%EOF\n"

          header + @body + xref + trailer
        end

        def build_xref
          lines = @xref.sort.map { |_, offset| format("%010d 00000 n \n", offset) }
          "xref\n0 #{@obj_count + 1}\n0000000000 65535 f \n" + lines.join
        end
      end

      module JpegInfo
        # SOF0（FFC0）または SOF2（FFC2）マーカーから幅・高さを取得する
        SOF_MARKERS = ["\xFF\xC0", "\xFF\xC2"].freeze

        def self.dimensions(data)
          i = 2
          while i < data.bytesize - 4
            marker = data[i, 2]
            length = data[i + 2, 2].unpack1("n")

            if SOF_MARKERS.include?(marker)
              height = data[i + 5, 2].unpack1("n")
              width  = data[i + 7, 2].unpack1("n")
              return [width, height]
            end

            i += 2 + length
          end
          raise VivlioStarter::Error, "JPEG の寸法を取得できませんでした: SOFマーカーが見つかりません"
        end
      end
    end
  end
end
```

> **前提**: 入力JPEGは `pdftoppm` が出力したRGB JPEGのみを想定する。グレースケール・CMYKへの対応は行わない。

### 3.4 `PdfPages` コマンド

```ruby
# lib/vivlio_starter/commands/pdf_pages.rb
# frozen_string_literal: true

module VivlioStarter
  module Commands
    class PdfPages
      def run(pdf_path, dpi:, quality:, pages:, output:)
        validate_tools!
        validate_input!(pdf_path)

        output_dir = output || "#{File.basename(pdf_path, '.*')}_images"
        images = Pdf::PdfToJpeg.convert(pdf_path, output_dir:, dpi:, quality:, pages:)

        puts "完了: #{images.size} ページ → #{output_dir}/"
      end

      private

      def validate_tools!
        missing = []
        missing << "pdftoppm (brew install poppler)" unless system("which pdftoppm > /dev/null 2>&1")
        return if missing.empty?

        raise VivlioStarter::Error, "必要なツールが見つかりません: #{missing.join(', ')}"
      end

      def validate_input!(pdf_path)
        raise VivlioStarter::Error, "ファイルが見つかりません: #{pdf_path}" unless File.exist?(pdf_path)
      end
    end
  end
end
```

### 3.5 `PdfRasterize` コマンド

```ruby
# lib/vivlio_starter/commands/pdf_rasterize.rb
# frozen_string_literal: true

module VivlioStarter
  module Commands
    class PdfRasterize
      def run(pdf_path, dpi:, quality:, clean:)
        validate_tools!
        validate_input!(pdf_path)

        base       = File.basename(pdf_path, ".*")
        work_dir   = "#{base}_images"
        output_pdf = "#{base}_rasterized.pdf"

        # 既存の作業ディレクトリを削除して新規作成（前回の残留ファイルを排除）
        if Dir.exist?(work_dir)
          FileUtils.rm_rf(work_dir)
          puts "既存ディレクトリを削除しました: #{work_dir}"
        end
        FileUtils.mkdir_p(work_dir)

        puts "--- Phase 1: PDF → JPEG (#{dpi}dpi / quality #{quality}) ---"
        images = Pdf::PdfToJpeg.convert(pdf_path, output_dir: work_dir, dpi:, quality:)
        puts "#{images.size} ページを生成しました"

        puts "--- Phase 2: JPEG → PDF ---"
        Pdf::JpegToPdf.convert(images, output_pdf)

        size_mb = (File.size(output_pdf) / 1024.0 / 1024.0).round(1)
        puts "完了: #{output_pdf} (#{size_mb} MB)"

        if clean
          FileUtils.rm_rf(work_dir)
          puts "中間ファイルを削除しました: #{work_dir}"
        else
          puts "中間ファイルを保存しました: #{work_dir}/"
        end
      end

      private

      def validate_tools!
        missing = []
        missing << "pdftoppm (brew install poppler)" unless system("which pdftoppm > /dev/null 2>&1")
        return if missing.empty?

        raise VivlioStarter::Error, "必要なツールが見つかりません: #{missing.join(', ')}"
      end

      def validate_input!(pdf_path)
        raise VivlioStarter::Error, "ファイルが見つかりません: #{pdf_path}" unless File.exist?(pdf_path)
      end
    end
  end
end
```

---

## 4. `vs --help` への追記

```
  ビルド・出力・プレビュー:
    preflight        ビルド前の原稿エラーチェックを高速実行します
    build            書籍全体または指定章をビルドします
    open             生成されたPDFを開きます
    pdf:compress     生成済みPDFを圧縮します
    pdf:pages        PDFをページ単位でJPEG画像に切り出します
    pdf:rasterize    PDFをラスタライズして再結合します（Type3フォント対策）
```

---

## 5. 外部依存ツール

| ツール | 用途 | インストール |
|---|---|---|
| `pdftoppm` | PDF → JPEG変換 | `brew install poppler` |

JPEG → PDF結合は独自実装（`JpegToPdf`）のため、外部ツール・gemへの依存なし。

`vs doctor` による事前チェック対象：`pdftoppm` のみ。

---

## 6. 設計上の判断メモ

| 項目 | 決定内容 | 理由 |
|---|---|---|
| `pdf:pages` と `pdf:rasterize` の関係 | 独立したコマンド | 目的が異なる。`--pages` 部分指定との整合性を保証できない |
| `pdf:rasterize` の中間JPEG | デフォルトで残す | 処理コストが高く、技術書典用途との兼用が可能 |
| `pdf:rasterize` のJPEG再利用 | しない（自前で再生成） | `pdf:pages` 側が部分指定されている可能性があり、全ページの保証ができない |
| `pdf:rasterize` の作業ディレクトリ | 既存があれば削除して新規作成 | 前回実行の残留ファイルの混入を防ぐ |
| PDF→JPEG変換の実装 | `PdfToJpeg` モジュールに共通化 | コードの重複排除・単体テストの容易化 |
| JPEG→PDF結合の実装 | `JpegToPdf` 独自実装 | HexaPDFはAGPLのためライセンス感染リスクがある。img2pdfはPython依存で導入コストが高い。PDFへのJPEG埋め込みはフォーマット仕様がシンプルで独自実装が現実的 |
| オプション表記 | `--option=VALUE` 形式に統一 | `vs build --log=debug` など既存コマンドとの一貫性。|
| ページ番号の桁数 | `pdftoppm` に委ねる | ページ総数に応じた自動桁数調整が `pdftoppm` の既定動作であり、独自に制御する必要がない |
