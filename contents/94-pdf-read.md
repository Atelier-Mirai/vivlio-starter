# PDF からの原稿の取り出し

:::{.chapter-lead}
`vs pdf:read` は PDF から文字や画像を取り出して Vivlio Starter の Markdown に変換するコマンドです。既刊の書籍や配布資料をもとに書き直す場合に役立ちます。
:::

## 概要と事前準備

`vs pdf:read` には、テキストを取り出す **Standard Mode** と、画像抽出・OCR も行う **Enhanced Mode** があります。

| 項目 | Standard Mode | Enhanced Mode |
| --- | --- | --- |
| ライセンス | MIT | AGPL-3.0 |
| 変換対象 | テキストのみ | テキスト + 画像 + OCR |
| 依存ライブラリ | PDF::Reader | HexaPDF, ruby-vips, Tesseract |
| 主な用途 | 参考資料の粗変換 | 出版クオリティの再利用 |

Standard Mode は `vivlio-starter` 本体に含まれます。画像の抽出や OCR が必要なら、`vivlio-starter-pdf` gem をインストールして Enhanced Mode を使います。

### 必須ツール

```zsh
vs doctor --fix
```

必要な環境は `vs doctor` で確認できます。ここで関係するのは次のツールです。

- **Ruby 3.4.x, 4.x, Bundler**
- **pdftotext**（poppler に同梱）

### Enhanced Mode の追加要件

画像抽出と OCR を使う場合は、追加の gem とツールを導入します。

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

PDF のパスを直接渡すと、空いている章番号が割り当てられ、変換した Markdown が `contents/` に作られます。

### ファイル名で指定する

```zsh
vs pdf:read three-elements
```

PDF を `sources/three-elements.pdf` に置いた場合は、ファイル名の `three-elements` で指定できます。すでに `catalog.yml` に登録した章なら、対応する PDF が自動で探されます。

### 実行例

```
$ vs pdf:read three-elements
[pdf:read] PDF からテキストを抽出します (12-three-elements, mode=enhanced)
[pdf:read] ページ数: 7
[pdf:read] 変換が完了しました -> contents/12-three-elements.md
```

### 出力されるファイル

出力先は次のとおりです。Standard Mode では Markdown、Enhanced Mode では画像も作られます。

```
# Standard Mode
contents/
  └── 12-three-elements.md

# Enhanced Mode
contents/
  └── 12-three-elements.md
images/
  └── 12-three-elements/
      ├── page-003-image-01.webp
      ├── page-004-image-01.webp
      └── ...
```

取り出した画像は、Markdown から `![](page-003-image-01.webp)` のように参照されます。変換後は原本と見比べ、本文と画像の位置を確かめてください。

### 動作モードの切り替え

どちらのモードで動くかは、次の順で決まります。

1. 環境変数 `VIVLIO_PDF_PLUGIN=disable` が設定されている場合は強制的に Standard Mode
2. `vivlio-starter-pdf` gem がインストール済みなら Enhanced Mode
3. それ以外は Standard Mode

```zsh
# 強制的に Standard Mode で実行
VIVLIO_PDF_PLUGIN=disable vs pdf:read document.pdf
```

### 既存ファイルの保護

同じ章トークンで再実行しても、既存の Markdown や画像ディレクトリは**上書きされません**。新しい章番号が割り当てられるため、前回の変換結果に加筆していても、その原稿は残ります。

## 設定とカスタマイズ

### `book.yml` の設定

変換時の余白や OCR の動作は、`config/book.yml` の `pdf_read` で調整できます。

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

ページ端のヘッダー、フッター、ノンブルを本文として取り込まないための設定です。除外する幅を mm 単位で指定します。

| 項目 | 説明 | 既定値 |
| --- | --- | --- |
| `top_margin` | 上端から除外する幅 | 18mm |
| `bottom_margin` | 下端から除外する幅 | 20mm |
| `inner_margin` | 綴じ側（ノド）から除外する幅 | 15mm |
| `outer_margin` | 小口側から除外する幅 | 12mm |

`page_separator: true` にすると、元の PDF のページ境界に `---` が挿入されます。この記法は Vivlio Starter では改ページになるので、ページを分けて残したい場合に使います。`false` ならページ間のテキストは連結されます。

### OCR 設定（Enhanced Mode のみ）

| 項目 | 説明 | 既定値 |
| --- | --- | --- |
| `mode` | `auto`（スキャン PDF を自動検出）/ `force`（全ページ OCR）/ `disable`（OCR 無効） | `auto` |
| `languages` | Tesseract に渡す言語。`japanese` は `jpn` に自動変換 | `[japanese]` |
| `dpi` | OCR 前の画像変換解像度。高いほど精度が上がるが処理時間も増える | `300` |
| `psm` | Tesseract のページセグメントモード。`3`（自動）が一般的 | `3` |
| `inline_image_text` | イラスト内テキストの扱い。`include` / `exclude` / `captionize` | `include` |

### OCR テキスト品質の向上

Enhanced Mode では、OCR で読み取った文字に次の補正を順に適用します。

1. **空白圧縮** --- 日本語文字間の不要な半角スペースを除去（例: `プ ロ グ ラ ミ ン グ` → `プログラミング`）
2. **断片結合** --- OCR が 1 文字ずつ分割してしまった単語を再結合
3. **括弧正規化** --- 日本語を含む半角括弧を全角括弧に変換（例: `(道具)` → `（道具）`）
4. **誤認識の補正** --- `config/ocr_corrections.yml` に定義された読み違いを直す
5. **MeCab 改行補正** --- MeCab が利用可能な場合、形態素解析に基づく改行位置の最適化

### 誤認識を直す

OCR では、形の似た文字を取り違えることがあります。原本と見比べて繰り返し見つかる誤読は、`config/ocr_corrections.yml` に登録できます。校正辞書（`config/textlint_rewrite.yml`）と同じ形式で、`patterns` に文字列か正規表現（`/pattern/` 形式）を書きます。

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

この補正が適用されるのは**PDF から読み取ったテキストだけ**です。自分で書いた原稿には影響しません。OCR 固有の誤読を校正辞書（`textlint_rewrite.yml`）に登録すると、全原稿が対象になります。たとえば `Al` を `AI` に直す規則は、アルミニウムの元素記号や人名の Al Gore まで書き換えてしまいます。

:::{.notice}
**一字だけの置き換えは書かないでください。**

`ロ` と `口`、`力` と `カ`、`一` と `ー` は、OCR で混同しやすい文字です。ただし、一字だけを補正対象にすると、正しく読めた箇所も変わります。`力 => カ` なら「力学（りきがく）」が「カ学（かがく）」になってしまうため、**語の形**で登録してください。

```yaml
- expected: 協力
  patterns:
    - 協カ # ←「力」が「カ」と読まれた形を、語ごと直す
```
:::

`Al` と `AI` のように、**文脈を読まないと正誤を決められない組**は登録しません。既定の `ocr_corrections.yml` にも含めていません。こうした箇所は、原本と照らして判断してください。

## PDF アウトラインの付与

PDF ビューアーで「しおり」や「ブックマーク」として見える項目を、アウトライン（Outlines）と呼びます。章や節へ移動しやすくなる機能です。`vivlio-starter-pdf` gem が入っていれば、`vs build` の仕上げに自動で付けられます。

### アウトラインの構造

アウトラインは、HTML の見出し要素（`h1` ～ `h3`）を読み取り、章・節・小節の階層で作られます。

| 見出しレベル | アウトラインでの表示 | 例 |
|---|---|---|
| `h1` | 章見出し | 第1章 はじめに |
| `h2` | 節見出し | 1-1 インストール |
| `h3` | 小節見出し | ♣ 基本的な使い方 |

付録には「付録A」「付録B」のような名前が付きます。前書き、目次、後書き、索引、用語集もそれぞれの名前で表示されます。

### ページ番号の特定

アウトラインから該当ページへ移動するには、見出しのページ位置を特定する必要があります。Vivliostyle の PDF にはその情報が含まれないため、`pdftotext` でページごとの文字を取り出し、見出しを探して位置を決めます。

見出しが見つからなければ、その章の先頭ページを指定します。`--log=debug` を付けてビルドすると、先頭ページを代わりに使った見出しを一覧で確認できます。

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

変換中は、処理の進み具合がログに表示されます。Standard Mode と Enhanced Mode で出る内容の違いも、次の例で確かめられます。

```
# Standard Mode
[pdf:read] PDF からテキストを抽出します (01-intro, mode=standard)
[pdf:read] ページ数: 12
[pdf:read] 変換が完了しました -> contents/01-intro.md

# Enhanced Mode（OCR あり）
[pdf:read] PDF からテキストを抽出します (12-three-elements, mode=enhanced)
[Reader] ページ 1: テキスト埋め込みなし。OCR を実行します (dpi=300, psm=3)
[Reader] ページ 2: テキスト品質不良。OCR で補完します
[Reader] 画像抽出: page-003-image-01.webp (524x381)
[pdf:read] 変換が完了しました -> contents/12-three-elements.md
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

インストール後は、`vs pdf:read` が自動で Enhanced Mode を選びます。

:::{.tip}
**ヒント**  
最初の変換結果を元の PDF と見比べ、繰り返し出る誤読を `config/ocr_corrections.yml` に追加すると、次の読み取りにも補正を使えます。一度にすべて直そうとせず、原稿を確認しながら辞書を育てていけます。
:::
