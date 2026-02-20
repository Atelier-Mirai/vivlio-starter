# PDF to Markdown変換機能 仕様書

**プロジェクト**: vivlio-starter  
**機能名**: PDF to Markdown Converter  
**コマンド**: `vs pdf:read`  
**バージョン**: 1.0  
**作成日**: 2026-02-21

---

## 1. 概要

### 1.1 目的

著者が手元に持つPDF形式の参考資料を、vivlio-starter で扱えるMarkdown形式に変換する機能を提供する。これにより、既存のドキュメントを電子書籍執筆の素材として活用できるようにする。

### 1.2 基本方針

- **シンプルさ優先**: 完璧な変換よりも、80%の精度で実用的な結果を提供
- **gem配布対応**: 外部APIに依存せず、Rubyエコシステム内で完結
- **画像抽出**: PDFに埋め込まれた画像を個別ファイルとして抽出
- **手動修正前提**: 変換結果は著者が最終調整することを想定

---

## 2. コマンド仕様

### 2.1 基本コマンド

```bash
vs pdf:read FILE [OPTIONS]
```

> **出力先の既定挙動**
>
> - 入力 `10-awesome.pdf` → `contents/10-awesome.md` を生成
> - 同階層に `images/10-awesome/` ディレクトリを作成し、抽出した画像を WebP 形式で保存
>
> `vs create 10-awesome` と同様に、エントリ名は PDF ベース名をスラッグ化したものを用いる。

### 2.2 引数

| 引数 | 必須 | 説明 |
|------|------|------|
| FILE | ○ | 章トークンまたは PDF パス。TokenResolver で章を解決し、見つからなければ sources/ 配下の PDF を探索する |

#### 章トークン解決フロー

1. `FILE` が `10-awesome`/`10-awesome.pdf` のように章トークンと一致する場合、TokenResolver で既存章を取得。
2. 既存章が見つかればそのスラッグ（例: `10-awesome`）を出力先として使用し、PDF ファイルは `sources/10-awesome.pdf` → `sources/pdfs/10-awesome.pdf` → 現在ディレクトリ相対の順で探索。
3. トークンが見つからない場合は「任意PDFモード」とし、`FILE` をファイルパスとして扱って存在確認。
4. 任意PDFの場合は章番号を自動払い出し（`01`〜`98` の最小空き番号）。全て埋まっている場合はエラーで終了。
5. 新規払い出し時は TokenResolver と同じルールでスラッグ化し、`catalog.yml` の 01〜98 で空いている番号（例: 10 が未使用なら `10-awesome`）に `vs create` 同等の手順で章エントリを追記したうえで Markdown を生成する。

### 2.3 オプション

| オプション | 短縮形 | 型 | デフォルト | 説明 |
|-----------|--------|-----|-----------|------|
| `--no-images` | - | Boolean | `false` | 画像抽出を明示的に無効化（デフォルトは抽出する） |

### 2.4 使用例

```bash
# 基本的な変換（pdf名=10-awesome.pdf）
vs pdf:read 10-awesome.pdf
# → contents/10-awesome.md
# → images/10-awesome/*.webp

# 拡張子の省略も可能（pdf名=10-awesome.pdf）
vs pdf:read 10-awesome

# 画像抽出を無効化（本文のみ）
vs pdf:read 10-awesome.pdf --no-images

# 章トークンを省略し、sources/awesome.pdf を指定
vs pdf:read awesome
# → 未使用の章番号を自動払い出し（例: 11-awesome）

# sources/ 内をサブディレクトリで整理している場合
vs pdf:read pdfs/awesome.pdf
# → sources/pdfs/awesome.pdf を探索し、同様に取り込む
```

---

## 3. 機能要件

### 3.1 テキスト抽出

- PDFの各ページからテキストを抽出
- レイアウト情報を可能な限り保持
- 連続する空行を整理（3行以上 → 2行）
- 行末の不要な空白を削除

### 3.2 画像抽出

#### 3.2.1 対応形式

| PDF内フィルタ | 入力形式 | 変換後拡張子 | 処理方法 |
|--------------|----------|--------------|---------|
| DCTDecode | JPEG | .webp | 元データを再圧縮して WebP 保存 |
| JPXDecode | JPEG2000 | .webp | 元データを再圧縮して WebP 保存 |
| FlateDecode | PNG相当 | .webp | ピクセルデータを WebP に変換 |
| CCITTFaxDecode | TIFF (G3/G4) | .webp | ImageMagick 経由でラスタライズ → WebP へ再圧縮 |

#### 3.2.2 画像ファイル命名規則

```
page{ページ番号}_fig{連番}.{拡張子}
```

例: `page1_fig1.webp`, `page3_fig2.webp`

#### 3.2.3 Markdown内の画像参照

```markdown
![Figure N](相対パス)
```

例:
```markdown
![Figure 1](page1_fig1.webp)
```

### 3.3 出力ディレクトリ構造

```
contents/
└── awesome.md              # 変換されたMarkdown
images/
    └── awesome/            # PDF名に対応するディレクトリ
        ├── page1_fig1.webp
        ├── page3_fig2.webp
        └── page5_fig3.webp
```

### 3.4 エラーハンドリング

- ファイルが存在しない → エラーメッセージ表示、終了コード1
- PDFファイルでない → エラーメッセージ表示、終了コード1
- 画像抽出失敗 → 警告を表示、処理継続
- 不明な画像形式 → 警告を表示、その画像はスキップ

### 3.5 PDF / 資料置き場

- プロジェクトルートに `sources/` ディレクトリを設け、執筆に利用する PDF / Word / Excel / 画像などを格納できるようにする。
- `vs pdf:read` は以下の順で PDF を探索する:
  1. `sources/<slug>.pdf`
  2. `sources/<ユーザー指定パス>.pdf`（例: `sources/pdfs/awesome.pdf`）
  3. CLI で明示指定されたパス（絶対パス / 相対パス）
- 利用者が `sources/words/`, `sources/pdfs/` などサブディレクトリで整理する場合、`vs pdf:read pdfs/awesome` のように `sources/` 以下のパスを渡せば該当ファイルが参照される。
- 新規章へ払い出した際は、`sources/` 配下に元の PDF を残しておくことで、再取り込みや diff 追跡が容易になる。

---

## 4. 実装仕様

### 4.1 依存gem

```ruby
# vivlio-starter.gemspec
spec.add_dependency 'pdf-reader', '~> 2.12'
spec.add_dependency 'hexapdf', '~> 1.0'
spec.add_dependency 'chunky_png', '~> 1.4'   # PNG変換用
spec.add_dependency 'mini_magick', '~> 4.12' # WebP 変換用
```

### 4.2 ファイル構成

```
lib/vivlio/
├── commands/
│   └── pdf_read_command.rb  # メインコマンド実装
└── cli.rb                   # Samovarコマンド定義
```

### 4.3 主要クラス

#### 4.3.1 PdfReadCommand クラス

```ruby
module Vivlio
  module Commands
    class PdfReadCommand
      def initialize(pdf_path, options = {})
        @pdf_path = pdf_path
        @output_path = options[:output] || default_output_path
        @extract_images = options.fetch(:images, true)
        @image_dir = options[:image_dir] || default_image_dir
      end

      def execute
        # メイン処理
      end

      private

      def validate_input!
        # 入力検証
      end

      def prepare_directories!
        # ディレクトリ作成
      end

      def convert_to_markdown
        # PDF → Markdown変換
      end

      def extract_text_from_page(page)
        # ページからテキスト抽出
      end

      def extract_images_from_page(page, page_num)
        # ページから画像抽出
      end

      def save_image(stream, output_path)
        # 画像保存
      end

      def convert_to_png(stream, output_path)
        # PNG形式に変換
      end

      def post_process_markdown(text)
        # Markdown後処理
      end
    end
  end
end
```

---

## 5. サンプルコード

### 5.1 メイン処理実装

```ruby
# lib/vivlio/commands/pdf_read_command.rb
require 'hexapdf'
require 'mini_magick'
require 'pathname'
require 'fileutils'

module Vivlio
  module Commands
    class PdfReadCommand
      def initialize(pdf_path, images: true)
        @pdf_path = pdf_path
        @extract_images = images
        @slug = build_slug(File.basename(pdf_path, '.pdf'))
        @output_path = File.join('contents', "#{@slug}.md")
        @image_dir = File.join('images', @slug)
      end

      def execute
        validate_input!
        prepare_directories!

        markdown = convert_to_markdown
        File.write(@output_path, markdown)

        Common.log_success("Converted #{@pdf_path} -> #{@output_path}")
        Common.log_info("Images stored in #{@image_dir}") if @extract_images
      end

      private

      def convert_to_markdown
        doc = HexaPDF::Document.open(@pdf_path)
        image_index = 0

        chunks = doc.pages.each_with_index.map do |page, idx|
          text = extract_text(page)

          if @extract_images
            extract_images(page, idx).each do |relative_path|
              image_index += 1
              text += "\n\n![Figure #{image_index}](#{relative_path})\n"
            end
          end

          text
        end

        post_process(chunks.join("\n\n---\n\n"))
      end

      def extract_text(page)
        page.to_text
      rescue StandardError => e
        Common.log_warn("[pdf:read] テキスト抽出に失敗したため空文字を返します: #{e.message}")
        ''
      end

      def extract_images(page, page_index)
        return [] unless @extract_images

        extracted = []

        page.each_xobject do |name, stream|
          next unless stream[:Subtype] == :Image

          basename = format('page%<page>d_fig%<fig>d.webp', page: page_index + 1, fig: extracted.length + 1)
          absolute_path = File.join(@image_dir, basename)

          begin
            write_webp(stream, absolute_path)
            relative = Pathname.new(absolute_path).relative_path_from(Pathname.new(File.dirname(@output_path))).to_s
            extracted << relative
          rescue StandardError => e
            Common.log_warn("[pdf:read] 画像抽出に失敗しました (#{name}): #{e.message}")
          end
        end

        extracted
      end

      def write_webp(stream, output_path)
        case stream[:Filter]
        when :DCTDecode, :JPXDecode
          MiniMagick::Image.read(stream.stream).tap do |img|
            img.format 'webp'
            img.write(output_path)
          end
        when :FlateDecode
          write_webp_from_raw(stream, output_path)
        when :CCITTFaxDecode
          write_webp_from_ccitt(stream, output_path)
        else
          raise "Unsupported image filter: #{stream[:Filter]}"
        end
      end

      def write_webp_from_raw(stream, output_path)
        width  = stream[:Width]
        height = stream[:Height]
        color_space = Array(stream[:ColorSpace]).first

        Tempfile.create(['pdfraw', '.png']) do |tmp|
          png = ChunkyPNG::Image.new(width, height)
          data = stream.stream
          bytes_per_pixel = (color_space == :DeviceGray ? 1 : 3)

          height.times do |y|
            width.times do |x|
              offset = (y * width + x) * bytes_per_pixel
              if bytes_per_pixel == 1
                gray = data[offset].ord
                png[x, y] = ChunkyPNG::Color.grayscale(gray)
              else
                r, g, b = data[offset, 3].bytes
                png[x, y] = ChunkyPNG::Color.rgb(r, g, b)
              end
            end
          end

          png.save(tmp.path)
          MiniMagick::Image.open(tmp.path).format('webp').write(output_path)
        end
      end

      def write_webp_from_ccitt(stream, output_path)
        Tempfile.create(['ccitt', '.tiff']) do |tmp|
          decoded = HexaPDF::Filter.set_filter(:CCITTFaxDecode).decode(stream.stream, stream.hash)
          tmp.write(decoded)
          tmp.flush
          MiniMagick::Tool::Convert.new do |convert|
            convert << tmp.path
            convert << output_path
          end
        end
      end

      def post_process(text)
        text.gsub(/\n{3,}/, "\n\n").gsub(/[ \t]+$/, '').strip + "\n"
      end

      def validate_input!
        raise "File not found: #{@pdf_path}" unless File.exist?(@pdf_path)
        raise "Not a PDF file: #{@pdf_path}" unless File.extname(@pdf_path).casecmp('.pdf').zero?
      end

      def prepare_directories!
        FileUtils.mkdir_p(File.dirname(@output_path))
        FileUtils.mkdir_p(@image_dir) if @extract_images
      end

      def build_slug(base)
        base.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')
      end
    end
  end
end
```

### 5.2 CLI定義（Samovar）

```ruby
# lib/vivlio/starter/cli/pdf.rb
module Vivlio
  module Starter
    module CLI
      class PdfCommand < Samovar::Command
        self.description = 'PDFをMarkdownへ変換する'

        options do
          option '--no-images', type: :boolean, default: false, description: '画像抽出を無効化'
        end

        parameter 'FILE', '変換対象のPDFファイルパス'

        def call
          generator = Vivlio::Commands::PdfReadCommand.new(file, images: images?)
          generator.execute
        rescue StandardError => e
          Common.log_error("PDF conversion failed: #{e.message}")
          exit 1
        end

        private

        def file
          parameters[:file]
        end

        def images?
          !options[:'no-images']
        end
      end
    end
  end
end
```

### 5.3 テストコード例（Minitest）

```ruby
# test/vivlio/commands/test_pdf_convert.rb
require 'test_helper'
require 'vivlio/commands/pdf_convert'

class PdfConvertTest < Minitest::Test
  SAMPLE_PDF = 'test/fixtures/sample.pdf'

  def setup
    FileUtils.mkdir_p('tmp')
    @output_path = 'tmp/test_output.md'
    @image_dir   = 'tmp/images/sample'
  end

  def teardown
    FileUtils.rm_rf('tmp')
  end

  def test_execute_generates_markdown
    converter = Vivlio::Commands::PdfConvert.new(SAMPLE_PDF)
    converter.stub :default_output_path, @output_path do
      converter.execute
    end

    assert File.exist?(@output_path), '変換後のMarkdownが生成される'
  end

  def test_execute_extracts_images_by_default
    converter = Vivlio::Commands::PdfConvert.new(SAMPLE_PDF)
    converter.stub :default_output_path, @output_path do
      converter.execute
    end

    assert Dir.exist?(@image_dir), '画像ディレクトリが作成される'
  end

  def test_execute_skips_images_when_disabled
    converter = Vivlio::Commands::PdfConvert.new(SAMPLE_PDF, images: false)
    converter.stub :default_output_path, @output_path do
      converter.stub :default_image_dir, @image_dir do
        converter.execute
      end
    end

    refute Dir.exist?(@image_dir), '--no-images 相当で画像を生成しない'
  end

  def test_execute_raises_when_pdf_missing
    converter = Vivlio::Commands::PdfConvert.new('missing.pdf')
    assert_raises(RuntimeError) { converter.execute }
  end
end
```

---

## 6. 制限事項と将来の拡張

### 6.1 現在の制限事項

1. **表の検出**: 罫線情報がないPDFでは表を正確に検出できない
2. **画像の意味**: 図の内容説明は不可能（代替テキストなし）
3. **数式**: MathJax/LaTeX形式への自動変換は未対応
4. **レイアウト**: 2カラムレイアウト等は崩れる可能性あり
5. **色情報**: CMYKカラーモデルの画像は未対応
6. **フォント**: 特殊フォントの文字化けの可能性あり

### 6.2 将来の拡張候補

#### 6.2.1 AI変換オプション（Phase 2）

ユーザーが自身のAPIキーを設定することで、Claude APIを使った高品質変換を有効化:

```bash
# 設定
vs config set anthropic_api_key sk-ant-...

# AI変換使用
vs pdf:read reference.pdf --engine=ai
```

#### 6.2.2 表検出の改善

テキストの座標情報から表構造を推測する機能を追加:

```ruby
# lib/vivlio/pdf/table_detector.rb
module Vivlio
  module Pdf
    class TableDetector
      def detect_tables(page)
        # 実装予定
      end
    end
  end
end
```

#### 6.2.3 OCR対応

スキャンされたPDFのテキスト抽出:

```bash
vs pdf:read scanned.pdf --ocr
```

必要なgem: `tesseract-ocr`

メモ:
- Tesseract OCR を組み込む想定。CLI 連携（`tesseract-ocr`）または `RTesseract`/`tesseract-ocr` gem 経由。
- 精度は入力品質に大きく依存（300dpi 以上・水平・英数字中心なら 95〜99% 程度、紙焼けや傾き・縦書きでは 80% 台まで低下しうる）。
- 高精度を目指す場合は、前処理（傾き補正・二値化・ノイズ除去）、適切な言語データ（`jpn`/`jpn_vert` 等）、領域ごとの OCR（段組み／図表切り分け）の組み合わせが必要。
- 「手動清書前提の下書きテキスト取得」が主目的。

---

## 7. 出力例

### 7.1 入力PDF

- ページ1: タイトルとテキスト、図1
- ページ2: テキストのみ
- ページ3: テキストと図2

### 7.2 出力Markdown

```markdown
# PDFドキュメントのタイトル

ここに本文のテキストが入ります。段落が続きます。

![Figure 1](page1_fig1.webp)

---

次のページのテキストがここに続きます。
複数の段落がある場合も適切に分割されます。

---

最後のページです。

![Figure 2](page3_fig1.webp)

さらにテキストが続きます。
```

### 7.3 ディレクトリ構造

```
contents/
├── sample.md
└── images/
    └── sample/
        ├── page1_fig1.webp
        └── page3_fig1.webp
```

---

## 8. 参考情報

### 8.1 PDF内部構造

PDFの画像は以下のようなストリームオブジェクトとして格納されています:

```
/Type /XObject
/Subtype /Image
/Width 800
/Height 600
/ColorSpace /DeviceRGB
/BitsPerComponent 8
/Filter /DCTDecode
/Length 45678
```

### 8.2 HexaPDF vs pdf-reader

| 機能 | HexaPDF | pdf-reader |
|------|---------|-----------|
| テキスト抽出 | ◎ レイアウト保持 | ○ 基本的な抽出 |
| 画像抽出 | ◎ 詳細情報取得可 | ○ 基本的な抽出 |
| PDF編集 | ◎ 対応 | × 非対応 |
| パフォーマンス | ○ やや遅い | ◎ 高速 |
| ライセンス | AGPL/商用 | MIT |

vivlio-starterでは、両方を組み合わせてフォールバック戦略を採用します。

---

## 9. まとめ

この仕様に基づいて実装することで、vivlio-starterユーザーは手元のPDFファイルを簡単にMarkdown形式に変換し、電子書籍執筆に活用できるようになります。

完璧な変換ではなく実用的な変換を目指し、著者が最終調整することを前提とした設計としています。

---

**Document Version**: 1.0  
**Last Updated**: 2026-02-21
