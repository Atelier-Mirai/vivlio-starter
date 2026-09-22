# PDF 読み取りコマンドの使い方

:::{.chapter-lead}
`vs pdf:read` は、PDF からテキストと画像を取り出し、Vivlio Starter の原稿形式である Markdown に変換するコマンドです。既存の書籍 PDF や配布資料を、執筆用の素材として取り込めます。
:::

## 概要と事前準備

`vs pdf:read` には、**Standard Mode** と **Enhanced Mode** の二つの動作モードがあります。

| 項目 | Standard Mode | Enhanced Mode |
| --- | --- | --- |
| ライセンス | MIT | AGPL-3.0 |
| 変換対象 | テキストのみ | テキスト + 画像 + OCR |
| 依存ライブラリ | PDF::Reader | HexaPDF, ruby-vips, Tesseract |
| 主な用途 | 参考資料の粗変換 | 出版クオリティの再利用 |

Standard Mode は `vivlio-starter` 本体に含まれており、追加インストールなしで利用できます。Enhanced Mode には `vivlio-starter-pdf` gem が必要です。

### 必須ツール

```zsh
vs doctor --fix
```

`vs doctor` は次の項目を確認し、必要に応じて案内します。

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

## 使い方

### PDF ファイルを直接指定する

```zsh
vs pdf:read path/to/document.pdf
```

PDF ファイルのパスを指定すると、空いている章番号を自動で割り当て、`contents/` に Markdown を出力します。

### 章トークンで指定する

```zsh
vs pdf:read three-elements
```

`sources/` ディレクトリに `three-elements.pdf` を置き、章トークンで指定する方法です。すでに `catalog.yml` に登録されている章なら、対応する PDF を自動で探索します。

### 実行例

```
$ vs pdf:read three-elements-ocr
[pdf:read] PDF からテキストを抽出します (12-three-elements-ocr, mode=enhanced)
[pdf:read] ページ数: 7
[pdf:read] 変換が完了しました -> contents/12-three-elements-ocr.md
```

### 出力されるファイル

Standard Mode ではテキストのみ、Enhanced Mode ではテキストと画像が出力されます。

```
# Standard Mode
contents/
  └── 12-three-elements-ocr.md

# Enhanced Mode
contents/
  └── 12-three-elements-ocr.md
images/
  └── 12-three-elements-ocr/
      ├── page-003-image-01.webp
      ├── page-004-image-01.webp
      └── ...
```

画像は Markdown 内で `![](page-003-image-01.webp)` のように参照されます。

### 動作モードの切り替え

動作モードは次の優先順位で決まります。

1. 環境変数 `VIVLIO_PDF_PLUGIN=disable` が設定されている場合は強制的に Standard Mode
2. `vivlio-starter-pdf` gem がインストール済みなら Enhanced Mode
3. それ以外は Standard Mode

```zsh
# 強制的に Standard Mode で実行
VIVLIO_PDF_PLUGIN=disable vs pdf:read document.pdf
```

### 既存ファイルの保護

同じ章トークンで `vs pdf:read` を複数回実行しても、既存の Markdown ファイルや画像ディレクトリは**上書きされません**。代わりに新しい章番号が自動で割り当てられます。加筆・修正済みの原稿を誤って失わないためです。

## 設定とカスタマイズ

### `book.yml` の設定

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

### テキスト領域（`text_area`）

PDF のページ端にあるヘッダー・フッター・ノンブルを除外するための余白です。値は mm 単位で指定します。

| 項目 | 説明 | 既定値 |
| --- | --- | --- |
| `top_margin` | 上端から除外する幅 | 18mm |
| `bottom_margin` | 下端から除外する幅 | 20mm |
| `inner_margin` | 綴じ側（ノド）から除外する幅 | 15mm |
| `outer_margin` | 小口側から除外する幅 | 12mm |

`page_separator` を `true` にするとページ境界に Markdown の水平線 `---` が挿入されます。`false` の場合はテキストが連結されます。

### OCR 設定（Enhanced Mode のみ）

| 項目 | 説明 | 既定値 |
| --- | --- | --- |
| `mode` | `auto`（スキャン PDF を自動検出）/ `force`（全ページ OCR）/ `disable`（OCR 無効） | `auto` |
| `languages` | Tesseract に渡す言語。`japanese` は `jpn` に自動変換 | `[japanese]` |
| `dpi` | OCR 前の画像変換解像度。高いほど精度が上がるが処理時間も増える | `300` |
| `psm` | Tesseract のページセグメントモード。`3`（自動）が一般的 | `3` |
| `inline_image_text` | イラスト内テキストの扱い。`include` / `exclude` / `captionize` | `include` |

### OCR テキスト品質の向上

Enhanced Mode では、OCR 後のテキストに次の自動補正を順に適用します。

1. **空白圧縮** --- 日本語文字間の不要な半角スペースを除去（例: `プ ロ グ ラ ミ ン グ` → `プログラミング`）
2. **断片結合** --- OCR が 1 文字ずつ分割してしまった単語を再結合
3. **括弧正規化** --- 日本語を含む半角括弧を全角括弧に変換（例: `(道具)` → `（道具）`）
4. **誤認識の補正** --- `config/ocr_corrections.yml` に定義された読み違いを直す
5. **MeCab 改行補正** --- MeCab が利用可能な場合、形態素解析に基づく改行位置の最適化

### 誤認識を直す

OCR では字形の似た文字を取り違えることがあります。誤認識の傾向は PDF ごとに異なるため、見つけたものを `config/ocr_corrections.yml` に追加してください。書式は校正辞書（`config/textlint_rewrite.yml`）と同じで、`patterns` には文字列または正規表現（`/pattern/` 形式）を指定します。

```yaml
version: 1
rules:
  # 人 → 入
  - expected: 人工知能
    patterns:
      - 入工知能

  # 彙 → 芸。「言語芸術」に当たらないよう、直後の「術」を外す
  - expected: 語彙
    patterns:
      - /語芸(?!術)/

  # 先頭の「プ」が落ちる。「アナログ」等に続く形は除く
  - expected: プログラミング
    patterns:
      - /(?<![ァ-ヶー])ログラミング/
```

この表を適用するのは**PDF から読み取ったページのテキストだけ**で、自分で書いた原稿には影響しません。校正辞書（`textlint_rewrite.yml`）には書かないでください。こちらは全原稿に適用されるため、`Al` を `AI` に直す規則を置くと、アルミニウムの元素記号や人名の Al Gore まで書き換えてしまいます。

:::{.notice}
**一字だけの置き換えは書かないでください。**

OCR がよく取り違えるのは `ロ` と `口`、`力` と `カ`、`一` と `ー` のような字形の近い一字です。しかしこれを表に書くと、正しく読めている箇所まで巻き添えにします（`力 => カ` と書けば「力学」が「カ学」になります）。必ず**語の形**で書いてください。

```yaml
- expected: 協力
  patterns:
    - 協カ # ←「力」が「カ」と読まれた形を、語ごと直す
```
:::

`Al` と `AI` のように、**どちらが正しいかを文脈でしか判断できない組**は、表に追加しないでください。既定の `ocr_corrections.yml` にも含めていません。機械的に置換せず、原稿を読み直して判断します。

## PDF アウトラインの付与

PDF ビューアで「しおり」や「ブックマーク」として表示されるアウトライン（Outlines）は、書籍内を移動するための重要な機能です。`vivlio-starter-pdf` gem がインストールされている場合、`vs build` の仕上げで自動的に付与されます。

### アウトラインの構造

生成されるアウトラインは、HTML の見出し要素（`h1` ～ `h3`）を解析して階層的に構築されます。

| 見出しレベル | アウトラインでの表示 | 例 |
|---|---|---|
| `h1` | 章見出し | 第1章 はじめに |
| `h2` | 節見出し | 1-1 インストール |
| `h3` | 小節見出し | ♣ 基本的な使い方 |

付録は「付録A」「付録B」の形式で、前書き・目次・後書き・索引・用語集もそれぞれ適切なラベルで表示されます。

### ページ番号の特定

アウトラインの各項目には正確なページ番号が必要です。Vivliostyle が生成する PDF にはページ番号のメタデータが含まれないため、`pdftotext` で各ページのテキストを抽出し、見出しテキストを検索してページ番号を特定しています。

見出しテキストが見つからない場合は、章の先頭ページにフォールバックします。`--log=debug` を付けてビルドすると、フォールバックが発生した見出しの一覧が表示されます。

### ビルドログの例

```
[Step 11] PDF ブックマークを付与します…
[OutlineWriter] PDF にアウトラインを 42 件追加しました
```

:::{.note}
アウトラインの付与には `pdftotext`（poppler）が必要です。`vs doctor --fix` でインストールできます。
:::

## トラブルシューティング

### 実行中のログ例

Standard Mode と Enhanced Mode のログ出力例です。問題が起きた場合は、ログから原因を確認できます。

```
# Standard Mode
[pdf:read] PDF からテキストを抽出します (01-intro, mode=standard)
[pdf:read] ページ数: 12
[pdf:read] 変換が完了しました -> contents/01-intro.md

# Enhanced Mode（OCR あり）
[pdf:read] PDF からテキストを抽出します (12-three-elements-ocr, mode=enhanced)
[Reader] ページ 1: テキスト埋め込みなし。OCR を実行します (dpi=300, psm=3)
[Reader] ページ 2: テキスト品質不良。OCR で補完します
[Reader] 画像抽出: page-003-image-01.webp (524x381)
[pdf:read] 変換が完了しました -> contents/12-three-elements-ocr.md
```

### よくある問題と解決策

| 症状 | 原因 | 解決策 |
| --- | --- | --- |
| テキストが空 / 文字化け | スキャン PDF でテキストが埋め込まれていない | Enhanced Mode + OCR を有効にする |
| ヘッダー / フッターが残る | `text_area` の余白設定が不足 | `book.yml` の `pdf_read.text_area` を調整 |
| 画像が抽出されない | Standard Mode で実行している | `vivlio-starter-pdf` gem をインストール |
| OCR 結果が悪い | DPI が低い / 言語設定が不適切 | `ocr.dpi` を `400` に、`languages` を確認 |
| `Tesseract not found` | Tesseract 未インストール | `brew install tesseract tesseract-lang` |
| 日本語の間にスペースが残る | 補正表にない誤読 | `ocr_corrections.yml` にパターンを追加 |
| 画像にテキストが混入する | イラスト領域検出のパラメータ | `inline_image_text: exclude` を試す |

### `vivlio-starter-pdf` のインストール

```zsh
gem install vivlio-starter-pdf
```

インストール後、`vs pdf:read` は自動的に Enhanced Mode で動作します。

:::{.tip}
**ヒント**  
OCR 結果の品質を上げるには、まず `vs pdf:read` で粗変換し、元の PDF と見比べながら `config/ocr_corrections.yml` に誤読パターンを追加します。追加したパターンは以降の読み取りにも適用されます。
:::
