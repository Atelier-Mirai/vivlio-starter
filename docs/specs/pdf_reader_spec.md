# PDF to Markdown 仕様書（MIT 本体 & プラグイン連携）

**機能名**: `vs pdf:read`

**対象ドキュメント**: vivlio-starter 本体（MIT）と vivlio-starter-pdf プラグイン（AGPL）の役割分担に基づく PDF→Markdown 変換仕様。

**最終更新**: 2026-02-21（purify 計画反映版）

---

## 1. 概要

### 1.1 目的

PDF を vivlio-starter の原稿フォーマット（Markdown）に変換し、既存資料を執筆素材として再利用できるようにする。ライセンス方針（MIT 本体 + AGPL プラグイン）に合わせ、機能を 2 段階で提供する。

### 1.2 方針

| 項目 | MIT 本体 (Standard Mode) | vivlio-starter-pdf プラグイン (Enhanced Mode) |
| --- | --- | --- |
| ライセンス | MIT | AGPL-3.0 |
| 変換対象 | テキストのみ | テキスト + 画像 + OCR + レイアウト情報 |
| 依存ライブラリ | PDF::Reader | HexaPDF, MiniMagick, ChunkyPNG など |
| 主な用途 | 参考資料の粗変換、ドラフト作成 | 出版クオリティのコンテンツ再利用 |

---

## 2. コマンド仕様

### 2.1 基本コマンド

```bash
vs pdf:read FILE [OPTIONS]
```

### 2.2 動作モード

1. **Standard Mode (デフォルト)**  
   - vivlio-starter 本体のみで動作。PDF::Reader を使いテキストを抽出し Markdown 化。画像やOCR処理は行わない。

2. **Enhanced Mode (オプション)**  
   - `vivlio-starter-pdf` がインストール済みの場合のみ有効。HexaPDF を使用した画像抽出・OCR・構造化出力を提供。

CLI 実行時、以下の順でモードを決定する。

1. `ENV['VIVLIO_PDF_PLUGIN']` が `disable` の場合は強制的に Standard。
2. `require 'vivlio/starter/pdf'` が成功したら Enhanced。失敗すれば Standard。
3. `--mode=standard|enhanced` オプションを用意し、利用者が明示的に切り替え可能にする（enhanced 指定でプラグイン未導入ならエラーを返す）。

### 2.3 引数 & オプション

| 名称 | 必須 | 説明 |
| --- | --- | --- |
| `FILE` | ○ | 章トークンまたは PDF パス。TokenResolver で章決定。

| オプション | 説明 |
| --- | --- |
| `--mode=standard` | 強制的に Standard Mode を使う。
| `--mode=enhanced` | プラグインが無い場合はガイド付きエラーを表示。
| `--no-images` | Enhanced Mode 時でも画像埋め込みを抑制。

#### 章トークン解決

1. `TokenResolver` で `FILE` を解決。
2. 既存章があればその slug で出力先を決定。
3. 見つからなければ任意 PDF とみなし、`sources/` などから該当ファイルを探索。
4. 任意 PDF であれば `01-98` の空き番号を払い出し、`catalog.yml` に追記する（`vs create` と同一ルール）。

---

## 3. 機能要件（Standard Mode）

1. **テキスト抽出**: PDF::Reader で各ページのテキストストリームを取得。
2. **Markdown 整形**: 連続改行の正規化、空白削除、ページ境界に `---` を挿入。
3. **出力構造**:
   ```
   contents/
     └── <slug>.md
   sources/
     └── (元 PDF を保存)
   ```
4. **ログ**: 変換成否、アクセスされた PDF、プラグイン有無を表示。
5. **制限**: 画像・OCR・表検出などは非対応として明示。

---

## 4. 機能要件（Enhanced Mode＝プラグイン任せ）

プラグインに委譲する責務。ここでは振る舞いのみを記述し、詳細は `vivlio_starter_pdf_plan.md` へ委譲。

| 項目 | 内容 |
| --- | --- |
| 画像抽出 | HexaPDF で XObject を列挙し、WebP へ統一。ディレクトリ: `images/<slug>/` |
| OCR | スキャン PDF を検知し、外部 OCR（Tesseract 等）と連携する。
| Markdown 拡張 | 画像参照、図番号、位置情報、注釈などを Markdown に埋め込む。
| エラー処理 | 画像抽出失敗などは警告ログを出しつつ続行。重大な失敗時のみ例外。

---

## 5. 実装仕様（Standard Mode）

### 5.1 依存ライブラリ

```ruby
# vivlio-starter.gemspec
spec.add_dependency 'pdf-reader', '~> 2.12'
```

（画像/HexaPDF 系ライブラリは本体から削除し、プラグインでのみ使用。）

### 5.2 ファイル構成

```
lib/vivlio/
├── commands/
│   └── pdf_read_command.rb
└── cli/pdf.rb
```

### 5.3 クラス構成

```ruby
module Vivlio
  module Commands
    class PdfReadCommand
      def initialize(pdf_path, mode: :auto)
        @mode = resolve_mode(mode)
        @adapter = build_adapter(@mode)
      end

      def execute
        adapter.execute
      end

      private

      def build_adapter(mode)
        case mode
        when :enhanced then EnhancedAdapter.new(pdf_path)
        else StandardAdapter.new(pdf_path)
        end
      end
    end
  end
end
```

### 5.4 StandardAdapter サンプル

```ruby
require 'pdf/reader'

module Vivlio
  module Commands
    class StandardAdapter
      def initialize(pdf_path)
        @pdf_path = pdf_path
        @slug = Common.build_slug(File.basename(pdf_path, '.pdf'))
        @output_path = File.join('contents', "#{@slug}.md")
      end

      def execute
        validate_input!
        FileUtils.mkdir_p(File.dirname(@output_path))

        markdown = extract_text
        File.write(@output_path, markdown)
        Common.log_success("Converted #{@pdf_path} -> #{@output_path}")
      end

      def extract_text
        reader = PDF::Reader.new(@pdf_path)
        chunks = reader.pages.map { |page| sanitize(page.text) }
        chunks.join("\n\n---\n\n") + "\n"
      rescue PDF::Reader::MalformedPDFError => e
        raise "Invalid PDF: #{e.message}"
      end

      def sanitize(text)
        text.gsub(/\u00A0/, ' ').gsub(/\s+$/, '').gsub(/\n{3,}/, "\n\n").strip
      end

      def validate_input!
        raise "File not found: #{@pdf_path}" unless File.exist?(@pdf_path)
        raise "Not a PDF: #{@pdf_path}" unless File.extname(@pdf_path).casecmp('.pdf').zero?
      end
    end
  end
end
```

### 5.5 EnhancedAdapter 呼び出し契約

```ruby
class EnhancedAdapter
  def initialize(pdf_path, options = {})
    require 'vivlio/starter/pdf'
    @impl = Vivlio::Starter::PDF::Reader.new(pdf_path, **options)
  rescue LoadError
    raise MissingPluginError
  end

  def execute = @impl.execute
end
```

---

## 6. テスト

| テスト観点 | 内容 |
| --- | --- |
| Standard モード単体 | テキスト抽出と Markdown 出力、章自動払い出し。 |
| モード切替 | `--mode` やプラグイン有無で正しく adapter が切り替わるか。 |
| デグレ防止 | プラグイン未導入環境で `vs pdf:read` が失敗しないこと。 |

Enhanced Mode のテストは `vivlio-starter-pdf` 側で担保し、ここではアダプタ境界のみを検証する。

---

## 7. 制限事項 & 今後

1. 標準モードでは画像・表・数式を扱わない。
2. OCR やレイアウトを必要とする場合はプラグインを案内するメッセージを表示。
3. プラグインは将来的に API キー連携・AI 変換などの高度機能を追加予定。

---

## 8. ユーザーへの案内メッセージ例

```
⚠️ 画像抽出や OCR を利用するには 'vivlio-starter-pdf' (AGPL) を追加インストールしてください。
$ gem install vivlio-starter-pdf
```

---

これにより、MIT 本体はテキスト抽出に専念し、ライセンス上の制約を避けつつ、必要なユーザーだけが AGPL プラグインで高度機能を利用できる。
