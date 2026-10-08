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

### 元の画像に差し替える

自分の本を印刷してスキャンした場合のように、図の元の画像が手元にあるなら、`--images-from` でそのフォルダを渡します（Enhanced Mode のみ）。

```shell-session
$ vs pdf:read 97-sample-ocr --images-from images/97-sample-original
```

取り出した図を、元の画像と見た目（縮めた白黒の画像）で突き合わせ、一致したものは元の画像に差し替えます。スキャンから切り出した図は印刷を撮り直したもので、解像度が半分ほどになり、網点も入ります。差し替えれば元の画像そのものになり、参照も `![](prototype_meter.webp)` のように元のファイル名になります。元の画像は `images/{章}/` へ写すので、渡したフォルダはそのまま残ります。

一致しなかった図は、取り出したまま残します。どの図とも結び付かなかった元の画像は、名前を挙げて知らせます。図を見つけられなかったか、切り出しが図の一部を欠いているので、原本と見比べて書き足してください。

```shell-session
🟡 [pdf:read] 元の画像のうち、紙面の図と結び付かなかったものが 1 枚あります: feynman.webp
```

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
| 論理式の否定の線（Ā） | `$\overline{A}$`・`$\overline{A+B}$`（タグのない PDF で、TeX などの数式の書体の字の上に線が引かれている場合） |
| ルビ・強調・行内コード | ルビの記法・`**…**`・`` `…` `` |
| 画像 | Enhanced Mode は `![代替テキスト](page-003-image-01.webp)`、Standard Mode は `<!-- 画像: 代替テキスト -->` |

構造の読み方は、PDF に応じて自動で決まります。

- **タグ付き PDF**：`vs build` で作った PDF のように、見出しや段落の区切りを「タグ」として持つ PDF です。本文の 9 割以上をタグが覆っていれば、タグから読みます。Word や InDesign が書き出した PDF も、タグが本文を覆っていればここに入ります。
- **タグのない PDF**：文字の大きさ・位置・書体から推定します。本文より大きく別の書体の短い行を見出しに、等幅の書体の行をコードに、縦の隙間で列がそろう行を表にします。推定して組んだ表には、確かめるよう促すコメント（`<!-- pdf:read: 列を推定して組んだ表です。… -->`）が付きます。
- **スキャンした PDF**：Enhanced Mode の OCR で読んだ文字の大きさと位置から、同じように推定します。書体が分からないので、見出しは本文よりはっきり大きな行だけ、コードは行番号の付いたものと、ファイル名の行が上にあるものだけが戻ります。箇条書きの点を英字や記号（`e`・`©`）と読んだ行も、点と文字の位置がそろって 3 行以上並べば箇条書きに戻します。脚注は、本文の側の番号が読めて、同じページに同じ番号の脚注があるものだけが戻ります。

`--log` を付けると、どちらで読んだかが出ます。

```shell-session
🔵 [pdf:read] 構造ツリー（タグ）から、見出し・段落・表・コードを戻します
🔵 [pdf:read] 文字の大きさと位置から、見出し・段落・表・コードを推定します
🔵 [pdf:read] OCR で読んだ文字の大きさと位置から、見出し・段落・表・コードを推定します
```

柱とノンブルは、ページをまたいで同じ位置に繰り返し出る行として見分け、取り込みません。`:::{.memo}` などの囲みは戻らず、紙面のラベル（`MEMO`・`COLUMN`）が 1 行の段落として残ります。囲みに戻すかどうかは、原本を見て決めてください。タグのない PDF では、数式（紙面では図形）と引用の区切りも戻りません。ただし、論理式の否定の線（Ā）は、線が消えると式の意味が変わるので `$\overline{A}$` に戻します。

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

Enhanced Mode では、OCR の前と後に次の処理を自動で行います。

- **二度読み**：囲みや網掛け、絵の多いページだけ、白黒をはっきりさせた画像でも読み、確信度の高い文字の多いほうを採ります。文字だけのページは 1 回で済ませます。
- **読み飛ばした所を読み直す**：罫線で囲んだ表や、色の帯の中の見出しは、ページ全体を読むと文字のない所として読み飛ばされることがあります。そうした範囲を切り出して読み直し、確信度の高い字が読めたときだけ採ります。読み直した表は、列のとおりに Markdown の表へ組みます。
- **図を切り出す**：スキャンしたページから、写真や絵、色の付いた図の範囲を見つけて画像として切り出し、その上の文字（絵の模様を字と読んだもの）を本文から除きます。読めた文字を消してから、濃い所と色の付いた所のまとまりを探すので、本文や囲みは図になりません。白地に線だけで描いた図や、白地に細い枠線だけの表紙は見つけられないので、原本と見比べて補ってください（元の画像があれば `--images-from` で見つからなかったものが分かります）。
- **英語でも読み直す**：英字の語の多いページ（コードのあるページなど）だけ、英語だけでもう一度読みます。日本語と英語を並べて読むと、`@param` を `Gparam` と読むような取り違えが残るためです。英字の語は、確信度の高いほうの読みを語の位置で突き合わせて採り、和文の語は変えません。`languages` に `english` があるときに働きます。
- **傾きを直す**：スキャナに置いた紙の傾き（ページごとに 0.5〜1° ほど）を測り、読めた文字の位置を回して直します。切り出す図もまっすぐにするので、図の縁に三角の余白が付きません。読み取りそのものは傾いたままの画像で行います。回した画像は字がにじみ、かえって読みが落ちるためです。
- **斜体の行を読み直す**：和文には斜体の書体がなく、引用などの斜体は字を傾けて描かれます。傾いた和文は OCR でほとんど読めない（意味のない英字になる）ので、確信度の低い行を切り出し、傾きを戻して読み直します。和文がはっきり読め、傾きを戻さずに読んだときより明らかによいときだけ採ります。
- **字の間の空白を詰める**：OCR が和文の字の間に入れる空白は、字の間隔から見て詰めます。数字と和文の間の空白も詰めます（`1879 年` → `1879年`）。英字の語と和文の間の空白は残すので、本の方針に合わせて `vs lint` で整えてください。
- **形の似た字を直す**：`6` と `も`、`ロ` と `口`、`力` と `カ`、`へ` と `ヘ`、`一` と `ー` などの取り違えを、MeCab で前後の文のつながりを確かめてから直します（`向けて6、` → `向けても、`、`協カ` → `協力`）。「ニュートン力学」や「イタリアへ」のような正しい文は変えません。MeCab が入っていなければ、この処理は飛ばします。
- **英字の語を直す**：コードの識別子や本文の英字の語で、OCR が取り違えた字（`Ftoat` → `Float`、`vetoctty_ratio` → `velocity_ratio`）を、`vs lint` のスペルチェックの辞書（`config/spellcheck_dictionaries/`）と英語の単語表で確かめて直します。辞書に当たる形が一つに決まるときだけ直すので、迷う語はそのまま残ります。この処理はコードの囲みの中にもかけます。
- **括弧をそろえる**：和文を含む半角括弧を全角にします（`(道具)` → `（道具）`）。
- **誤認識の補正**：最後に `config/ocr_corrections.yml` の表を当てます（次の節）。

コードの囲みの中は、英字の語を直す処理のほかは変えません。OCR は 1 ページに数秒かかるので、`--log` を付けると「OCR しています（5/24 ページ）」と経過が出ます。

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
