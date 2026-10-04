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

```shell-session
$ vs pdf:read three-elements
✅ Markdown に変換しました: contents/12-three-elements.md
```

`--log` を付けると、どちらのモードで読んだかとページ数も表示されます。

```shell-session
$ vs pdf:read three-elements --log
🔧 [pdf:read] PDF からテキストを抽出します (12-three-elements, mode=enhanced)
🔵 [pdf:read] ページ数: 7
✅ Markdown に変換しました: contents/12-three-elements.md
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

### 見出し・表・コードまで戻る

文字の層のある PDF からは、文字だけでなく原稿の構造も戻ります。どちらのモードでも同じです。

| 原本 | 戻る Markdown |
| --- | --- |
| 見出し | `#`・`##`・`###` |
| 段落・箇条書き・番号付きリスト | 段落・`-`・`1.` |
| 表 | パイプの表。ページで分かれた表は一つにつなぐ |
| コード | ```` ```ruby:ファイル名 ```` の囲み。行番号は外し、途中から始まる抜粋には `#L28` を添える |
| 脚注 | `[^1]` と `[^1]: …` |
| 数式 | `$…$`・`$$…$$`（タグ付き PDF で、図の代替テキストに TeX が入っている場合） |
| ルビ・強調・行内コード | ルビの記法・`**…**`・`` `…` `` |
| 画像 | Enhanced Mode は `![代替テキスト](page-003-image-01.webp)`、Standard Mode は `<!-- 画像: 代替テキスト -->` |

構造の読み方は、PDF に応じて自動で決まります。

- **タグ付き PDF**：`vs build` で作った PDF のように、見出しや段落の区切りを「タグ」として持つ PDF です。本文の 9 割以上をタグが覆っていれば、タグから読みます。Word や InDesign が書き出した PDF も、タグが本文を覆っていればここに入ります。
- **タグのない PDF**：文字の大きさ・位置・書体から推定します。本文より大きく別の書体の短い行を見出しに、等幅の書体の行をコードに、縦の隙間で列がそろう行を表にします。推定して組んだ表には、確かめるよう促すコメント（`<!-- pdf:read: 列を推定して組んだ表です。… -->`）が付きます。
- **スキャンした PDF**：文字の層がないので構造は戻らず、Enhanced Mode の OCR で文字を読みます。

`--log` を付けると、どちらで読んだかが出ます。

```shell-session
🔵 [pdf:read] 構造ツリー（タグ）から、見出し・段落・表・コードを戻します
🔵 [pdf:read] 文字の大きさと位置から、見出し・段落・表・コードを推定します
```

柱とノンブルは、ページをまたいで同じ位置に繰り返し出る行として見分け、取り込みません。`:::{.memo}` などの囲みは戻らず、紙面のラベル（`MEMO`・`COLUMN`）が 1 行の段落として残ります。囲みに戻すかどうかは、原本を見て決めてください。タグのない PDF では、数式（紙面では図形）と引用の区切りも戻りません。

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
    top_margin:           # 上端からの除外幅 (mm)。既定では書かない
    bottom_margin:        # 下端からの除外幅 (mm)
    inner_margin:         # 綴じ側の除外幅 (mm)
    outer_margin:         # 小口側の除外幅 (mm)
  page_separator: false   # ページ間に "---" を挿入するか
  ocr:
    mode: auto            # auto / force / disable
    languages:
      - japanese          # japanese / japanese_vertical / english
      - english
    dpi: 300              # OCR 用の解像度
    psm: 3                # Tesseract の PSM (ページセグメントモード)
    inline_image_text: include  # include / exclude / captionize
```

### テキスト領域（`text_area`）

柱とノンブルは繰り返しから見分けるので、既定では書きません。見分けが外れて柱やノンブルが本文に混ざるときだけ、除く幅を mm 単位で書きます。書いた辺だけが効きます。

| 項目 | 説明 | 既定値 |
| --- | --- | --- |
| `top_margin` | 上端から除外する幅 | なし |
| `bottom_margin` | 下端から除外する幅 | なし |
| `inner_margin` | 綴じ側（ノド）から除外する幅 | なし |
| `outer_margin` | 小口側から除外する幅 | なし |

`page_separator: true` にすると、元の PDF のページ境界に `---` が挿入されます。この記法は Vivlio Starter では改ページになるので、ページを分けて残したい場合に使います。`false` ならページ間のテキストは連結されます。文字の層のある PDF では、ページをまたぐ段落を構造からつなぐので、この設定は使いません（スキャンした PDF を OCR で読むときだけ効きます）。

### OCR 設定（Enhanced Mode のみ）

| 項目 | 説明 | 既定値 |
| --- | --- | --- |
| `mode` | `auto`（スキャン PDF を自動検出）/ `force`（全ページ OCR）/ `disable`（OCR 無効） | `auto` |
| `languages` | Tesseract に渡す言語。`japanese` は `jpn`、`english` は `eng` に自動変換。英語を並べると、コードや英字の語の読み違いが大きく減る | `[japanese, english]` |
| `dpi` | ページを画像に描き直して読むときの解像度。スキャンした画像はそのまま読む（幅が 1,600px に満たなければ拡大する）ので、この値は使わない | `300` |
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

付録には「付録 A」「付録 B」のような名前が付きます。前書き、目次、後書き、索引、用語集もそれぞれの名前で表示されます。

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

`--log` を付けると、処理の進み具合が表示されます。どちらのモードで読んだかもここで確かめられます。

```
# Standard Mode
🔧 [pdf:read] PDF からテキストを抽出します (11-intro, mode=standard)
🔵 [pdf:read] ページ数: 12
✅ Markdown に変換しました: contents/11-intro.md

# Enhanced Mode
🔧 [pdf:read] PDF からテキストを抽出します (12-three-elements, mode=enhanced)
🔵 [pdf:read] ページ数: 7
✅ Markdown に変換しました: contents/12-three-elements.md
```

文字を一つも取り出せなかったときは、原稿も `catalog.yml` も書かずに止まります。スキャンした PDF を Standard Mode で読むと、次のように案内されます。

```
🔴 [pdf:read] 実行中にエラー: PDF から文字を一つも取り出せませんでした（24 ページ）。原稿と catalog.yml には何も書いていません。
スキャンした PDF のように文字の層が無いと、Standard Mode では読めません。
OCR で読む Enhanced Mode を使うには、次を入れてから実行し直してください。
  gem install vivlio-starter-pdf
  brew install tesseract tesseract-lang poppler vips
```

### よくある問題と解決策

| 症状 | 原因 | 解決策 |
| --- | --- | --- |
| テキストが空 / 文字化け | スキャン PDF でテキストが埋め込まれていない | Enhanced Mode + OCR を有効にする |
| ヘッダー / フッターが残る | 繰り返しから見分けられなかった | `book.yml` の `pdf_read.text_area` に除く幅を書く |
| 画像が抽出されない | Standard Mode で実行している | `vivlio-starter-pdf` gem をインストール |
| OCR 結果が悪い | 言語設定が不適切 / スキャンの解像度が低い | `languages` を確認（英字が多い本は `eng` を足す）。スキャンし直すなら 300dpi 以上で |
| `Tesseract not found` | Tesseract 未インストール | `brew install tesseract tesseract-lang` |
| 日本語の間にスペースが残る | 補正表にない誤読 | `ocr_corrections.yml` にパターンを追加 |
| 画像にテキストが混入する | イラスト領域検出のパラメータ | `inline_image_text: exclude` を試す |

### `vivlio-starter-pdf` のインストール

```zsh
gem install vivlio-starter-pdf
```

インストール後は、`vs pdf:read` が自動で Enhanced Mode を選びます。Enhanced Mode には 1.2.0 以降が要ります。それより古い版が入っていると、`vs pdf:read` が `gem update vivlio-starter-pdf` を案内します。

:::{.tip}
**ヒント**  
最初の変換結果を元の PDF と見比べ、繰り返し出る誤読を `config/ocr_corrections.yml` に追加すると、次の読み取りにも補正を使えます。一度にすべて直そうとせず、原稿を確認しながら辞書を育てていけます。
:::
