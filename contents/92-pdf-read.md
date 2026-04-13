# PDF 読み取りコマンドの使い方

:::{.chapter-lead}
`vs pdf:read` は PDF ファイルからテキストと画像を抽出し、Vivlio Starter の原稿形式（Markdown）に変換するコマンドです。既存の書籍 PDF や配布資料を執筆素材として再利用したい場合に活用できます。
:::

---

## 1. 概要

`vs pdf:read` は **Standard Mode** と **Enhanced Mode** の 2 段階で機能を提供します。

| 項目 | Standard Mode | Enhanced Mode |
| --- | --- | --- |
| ライセンス | MIT | AGPL-3.0 |
| 変換対象 | テキストのみ | テキスト + 画像 + OCR |
| 依存ライブラリ | PDF::Reader | HexaPDF, ruby-vips, Tesseract |
| 主な用途 | 参考資料の粗変換 | 出版クオリティの再利用 |

Standard Mode は vivlio-starter 本体に組み込まれており、追加インストール不要で動作します。Enhanced Mode を利用するには `vivlio-starter-pdf` gem が必要です。

---

## 2. 事前準備

### 必須ツール

```zsh
vs doctor --fix
```

`vs doctor` が以下を自動で確認・案内します。

- **Ruby 4.x** / Bundler
- **pdftotext**（poppler に同梱）

### Enhanced Mode の追加要件

Enhanced Mode（画像抽出・OCR 付き）を利用する場合は、以下を追加でインストールしてください。

```zsh
gem install vivlio-starter-pdf
brew install tesseract tesseract-lang poppler vips
```

| ツール | 用途 |
| --- | --- |
| `vivlio-starter-pdf` | HexaPDF ベースの高度な PDF 解析 |
| `tesseract` + `tesseract-lang` | OCR エンジン（日本語対応） |
| `poppler`（pdftoppm） | PDF→画像変換（OCR 前処理） |
| `vips` | 高速画像処理（イラスト領域検出） |

---

## 3. 基本的な使い方

### PDF ファイルを直接指定する

```zsh
vs pdf:read path/to/document.pdf
```

PDF ファイルのパスを指定すると、空いている章番号が自動で割り当てられ、`contents/` に Markdown が出力されます。

### 章トークンで指定する

```zsh
vs pdf:read three-elements
```

`sources/` ディレクトリに `three-elements.pdf` を配置しておき、章トークンで指定する方法です。既に `catalog.yml` に登録済みの章であれば、対応する PDF を自動的に探索します。

### 実行例

```
$ vs pdf:read three-elements-ocr
[pdf:read] PDF からテキストを抽出します (12-three-elements-ocr, mode=enhanced)
[pdf:read] ページ数: 7
[pdf:read] 変換が完了しました -> contents/12-three-elements-ocr.md
```

---

## 4. 出力構造

コマンドを実行すると、以下のファイルが生成されます。

### Standard Mode

```
contents/
  └── 12-three-elements-ocr.md    # 抽出テキスト
```

### Enhanced Mode

```
contents/
  └── 12-three-elements-ocr.md    # 抽出テキスト + 画像参照
images/
  └── 12-three-elements-ocr/
      ├── page-003-image-01.webp   # 抽出画像（WebP）
      ├── page-004-image-01.webp
      └── ...
```

画像は Markdown 内で次のように参照されます。

```markdown
![](page-003-image-01.webp)
```

---

## 5. 動作モードの切り替え

モードは以下の優先順位で自動決定されます。

1. 環境変数 `VIVLIO_PDF_PLUGIN=disable` が設定されている場合は強制的に Standard Mode
2. `vivlio-starter-pdf` gem がインストール済みなら Enhanced Mode
3. それ以外は Standard Mode

```zsh
# 強制的に Standard Mode で実行
VIVLIO_PDF_PLUGIN=disable vs pdf:read document.pdf
```

---

## 6. `book.yml` の設定

`config/book.yml` の `pdf_read` セクションで変換の挙動を細かく制御できます。

```yaml
pdf_read:
  text_area:
    top_margin: 18        # 上端からの除外幅 (mm)
    bottom_margin: 20     # 下端からの除外幅 (mm)
    inner_margin: 15      # 綴じ側の除外幅 (mm)
    outer_margin: 12      # 小口側の除外幅 (mm)
  page_separator: false   # ページ間に "---" を挿入するか
  ocr:
    mode: auto            # auto / force / disable
    languages:
      - japanese          # japanese / japanese_vertical / eng
    dpi: 300              # OCR 用の解像度
    psm: 3                # Tesseract の PSM (ページセグメントモード)
    inline_image_text: include  # include / exclude / captionize
```

### 設定項目の説明

#### `text_area`（テキスト領域）

PDF のページ端にあるヘッダー・フッター・ノンブルを除外するための余白設定です。値は mm 単位で指定します。版面サイズに合わせて調整してください。

| 項目 | 説明 | 既定値 |
| --- | --- | --- |
| `top_margin` | 上端から除外する幅 | 18mm |
| `bottom_margin` | 下端から除外する幅 | 20mm |
| `inner_margin` | 綴じ側（ノド）から除外する幅 | 15mm |
| `outer_margin` | 小口側から除外する幅 | 12mm |

#### `page_separator`

`true` にするとページ境界に Markdown の水平線 `---` が挿入されます。`false` の場合はテキストが連結されます。

#### `ocr`（Enhanced Mode のみ）

| 項目 | 説明 | 既定値 |
| --- | --- | --- |
| `mode` | OCR 動作モード。`auto` はスキャン PDF を自動検出、`force` は全ページ OCR、`disable` は OCR 無効 | `auto` |
| `languages` | Tesseract に渡す言語。`japanese` は `jpn` に、`japanese_vertical` は `jpn_vert` に自動変換される | `[japanese]` |
| `dpi` | OCR 前の画像変換解像度。高いほど精度が上がるが処理時間も増える | `300` |
| `psm` | Tesseract のページセグメントモード。`3`（自動）が一般的。章扉など大きな見出しには `6` が有効 | `3` |
| `inline_image_text` | イラスト内テキストの扱い。`include`（本文に含める）、`exclude`（除外）、`captionize`（キャプション化） | `include` |

---

## 7. OCR テキスト品質の向上

Enhanced Mode では OCR 後のテキストに対して、以下の自動補正パイプラインが適用されます。

### 自動補正の流れ

1. **空白圧縮** --- 日本語文字間の不要な半角スペースを除去（例: `プ ロ グ ラ ミ ン グ` → `プログラミング`）
2. **断片結合** --- OCR が 1 文字ずつ分割してしまった単語を再結合
3. **括弧正規化** --- 日本語を含む半角括弧を全角括弧に変換（例: `(道具)` → `（道具）`）
4. **prh 辞書置換** --- `config/textlint_prh.yml` に定義された表記ゆれ・誤読パターンを自動修正
5. **MeCab 改行補正** --- MeCab が利用可能な場合、形態素解析に基づく改行位置の最適化

### prh 辞書によるカスタム修正

`config/textlint_prh.yml` に OCR 固有の誤認識パターンを追記できます。

```yaml
rules:
  # OCR が AI を Al と誤読する
  - expected: AI
    patterns:
      - /\bAl\b/

  # OCR が「人工」を「入工」と誤読する
  - expected: 人工知能
    patterns:
      - '入工知能'

  # OCR が先頭の「プ」を欠落させる
  - expected: プログラミング
    patterns:
      - /(?<![ァ-ヶー])ログラミング/
```

`patterns` には文字列リテラルまたは正規表現（`/pattern/` 形式）を指定できます。プロジェクト固有の専門用語や誤読パターンを辞書に追加することで、OCR 精度を段階的に改善できます。

---

## 8. 既存ファイルの保護

`vs pdf:read` を同じ章トークンで複数回実行した場合、既存の Markdown ファイルや画像ディレクトリは**上書きされません**。代わりに新しい章番号が自動で割り当てられます。

```
$ vs pdf:read three-elements-ocr
[pdf:read] 10-three-elements-ocr.md を上書きしないため、
           新しい章番号を割り当てます。
[pdf:read] 変換が完了しました -> contents/12-three-elements-ocr.md
```

これにより、著者が加筆・修正した既存原稿が誤って消えることを防ぎます。

---

## 9. PDF アウトラインの付与

`vs build` で生成される PDF には、Enhanced Mode がインストールされている場合、自動的にアウトライン（しおり・ブックマーク）が付与されます。

HTML の見出し要素（`h1` ～ `h3`）を解析し、PDF の Outlines ツリーに階層的なブックマークとして書き込みます。

```
[Step 11] PDF ブックマークを付与します…
[OutlineWriter] PDF にアウトラインを 15 件追加しました
```

### スタンドアロンでの利用

`vivlio-starter-pdf` gem を単体で使い、既存の PDF にアウトラインを付与することもできます。

```zsh
vivlio-starter-pdf outline output.pdf *.html --max-level=3
```

---

## 10. 実行中のログ例

### Standard Mode

```
[pdf:read] PDF からテキストを抽出します (01-intro, mode=standard)
[pdf:read] ページ数: 12
[pdf:read] 変換が完了しました -> contents/01-intro.md
```

### Enhanced Mode（OCR あり）

```
[pdf:read] PDF からテキストを抽出します (12-three-elements-ocr, mode=enhanced)
[Reader] ページ 1: テキスト埋め込みなし。OCR を実行します (dpi=300, psm=3)
[Reader] ページ 2: テキスト品質不良。OCR で補完します
[Reader] 画像抽出: page-003-image-01.webp (524x381)
[Reader] 画像抽出: page-004-image-01.webp (612x459)
[pdf:read] ページ数: 7
[pdf:read] 変換が完了しました -> contents/12-three-elements-ocr.md
```

---

## 11. トラブルシューティング

| 症状 | 原因 | 解決策 |
| --- | --- | --- |
| テキストが空 / 文字化け | スキャン PDF でテキストが埋め込まれていない | Enhanced Mode + OCR を有効にする |
| ヘッダー / フッターが残る | `text_area` の余白設定が不足 | `book.yml` の `pdf_read.text_area` を調整 |
| 画像が抽出されない | Standard Mode で実行している | `vivlio-starter-pdf` gem をインストール |
| OCR 結果が悪い | DPI が低い / 言語設定が不適切 | `ocr.dpi` を `400` に、`languages` を確認 |
| `Tesseract not found` | Tesseract 未インストール | `brew install tesseract tesseract-lang` |
| 日本語の間にスペースが残る | prh 辞書で補正対象外の誤読 | `textlint_prh.yml` にパターンを追加 |
| 画像にテキストが混入する | イラスト領域検出のパラメータ | `inline_image_text: exclude` を試す |

---

## 12. `vivlio-starter-pdf` のインストール

### gem としてインストール

```zsh
gem install vivlio-starter-pdf
```

### ローカルビルド

```zsh
cd vivlio-starter-pdf
gem build vivlio-starter-pdf.gemspec
gem install vivlio-starter-pdf-0.1.0.gem
```

### 確認

```zsh
vivlio-starter-pdf --version
# => 0.1.0
```

インストール後、`vs pdf:read` は自動的に Enhanced Mode で動作します。

---

:::{.column}
**ヒント**  
OCR 結果の品質を段階的に向上させるには、まず `vs pdf:read` で粗変換を行い、元の PDF と見比べながら `config/textlint_prh.yml` に誤読パターンを追記していくのが効率的です。一度辞書に登録したパターンは以降のすべての変換で自動適用されるため、プロジェクトが進むほど精度が上がります。
:::
