# PDF からの原稿の取り出し

:::{.chapter-lead}
`vs pdf:read` は PDF から文字や画像を取り出して Vivlio Starter の Markdown に変換するコマンドです。既刊の書籍や配布資料をもとに書き直す場合に役立ちます。元にする PDF がなければ、この章は飛ばしてかまいません。
:::

## 概要と事前準備

`vs pdf:read` には、テキストを取り出す **Standard Mode** と、画像抽出・OCR も行う **Enhanced Mode** があります。

| 項目 | Standard Mode | Enhanced Mode |
| --- | --- | --- |
| ライセンス | MIT | AGPL-3.0 |
| 変換対象 | テキストのみ | テキスト + 画像 + OCR |
| 依存ライブラリ | PDF::Reader | HexaPDF, ruby-vips, Tesseract |
| 主な用途 | 参考資料の粗変換 | 出版クオリティの再利用 |

Standard Mode は `vivlio-starter` 本体に含まれ、`vs doctor --fix` で入る pdftotext（poppler に同梱）があれば動きます。スキャンした PDF のように文字の層がない PDF は、Standard Mode では読めません。

画像の抽出や OCR が必要なら、`vivlio-starter-pdf` gem（1.2.0 以降）とツールを導入します。インストール後は、`vs pdf:read` が自動で Enhanced Mode を選びます。

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

gem を入れたまま Standard Mode で読みたいときは、環境変数 `VIVLIO_PDF_PLUGIN=disable` を付けて実行します。

## 使い方

### PDF を指定する

```zsh
vs pdf:read gitlab.pdf
```

資料の PDF は `sources/` に置きます。`sources/` の中の PDF は、ファイル名だけで指定できます（`.pdf` も省けます）。ほかの場所の PDF は、`/` を含むパスで指定します。

| 打つコマンド | 読む PDF |
|---|---|
| `vs pdf:read gitlab` | `sources/gitlab.pdf` |
| `vs pdf:read ~/Downloads/gitlab.pdf` | `~/Downloads/gitlab.pdf` |
| `vs pdf:read ./gitlab.pdf` | プロジェクト直下の `gitlab.pdf` |

ファイル名に空白・半角の `&`・括弧があると、シェルが名前を分けてしまい、そのままでは読めません。英字で始まる半角の英小文字・数字・ハイフン・アンダースコアだけの名前に変えてから読んでください（`2026-06-10 at 10-08-42 AI活用講座.pdf` → `ai-course.pdf`）。

### 章の名前を付ける

PDF を読むと、`contents/` に章の Markdown ができます。章の名前は PDF のファイル名から作り、番号は本文の最後の章の次にします。この本なら、`51-doctor` の次の `52-gitlab.md` です。大文字とアンダースコアは、小文字とハイフンに整えます（`Hajimete_no_Rust.pdf` → `52-hajimete-no-rust.md`）。ダウンロードや複製で付く `(1)`・`のコピー`・`copy` は外します。

二つ目の引数で、章の名前を決めることもできます。番号を付ければその番号の章に、番号だけなら名前はファイル名から作ります。付録にしたいときは、付録の番号（90〜98）を付けてください。

```zsh
vs pdf:read gitlab.pdf git       # contents/52-git.md
vs pdf:read gitlab.pdf 21-git    # contents/21-git.md
vs pdf:read gitlab.pdf 90        # contents/90-gitlab.md
```

日本語の名前や論文の番号のようなファイル名（`コンピュータネットワークのエッセンス.pdf`・`245.pdf`）からは、章の名前を作りません。番号かスラッグがほかの章と重なるときも、章を作らずに止まります。どちらの場合も、名前を添えた打ち直しのコマンドが示されるので、それを使ってください。

```text
🔴 [pdf:read] ファイル名から章の名前を作れません: sources/コンピュータネットワークのエッセンス.pdf
        使える名前: 英字で始まる半角の英小文字・数字・ハイフン（-）・アンダースコア（_）（例: awesome、my-reference_2047）
        → ファイル名を変える: awesome.pdf にしてから vs pdf:read awesome.pdf
        → 章の名前を添える:   vs pdf:read コンピュータネットワークのエッセンス.pdf 52-awesome
        （番号を省くと 52 番になります）
```

### 一部のページだけ読む

```zsh
vs pdf:read gitlab.pdf 21-git-basics --pages 12-30
vs pdf:read gitlab.pdf 22-git-branch --pages 31-48,52
vs pdf:read gitlab.pdf 23-git-appendix --pages 238-
```

`--pages` で、読むページを指定できます。書き方は `vs pdf:pages` と同じで、範囲の端は省けます（`-11` は 1〜11 ページ、`238-` は 238 ページから最後まで）。ページ番号は PDF の 1 枚目から数えた番号なので、表紙や前付けのある本では、紙面に印刷されたノンブルとずれます。ページを指定するときは、章の名前を必ず添えます（ファイル名から作ると、どの範囲も同じ名前になるためです）。

### 実行例と出力されるファイル

```shell-session
$ vs pdf:read three-elements --log
🔧 [pdf:read] PDF からテキストを抽出します (52-three-elements, mode=enhanced)
🔵 [pdf:read] ページ数: 7
✅ Markdown に変換しました: contents/52-three-elements.md
```

`--log` を付けると、どちらのモードで読んだかとページ数が表示されます。Standard Mode では Markdown だけ、Enhanced Mode では画像も作られます。

:::{.diagram}
```text
contents/
  └── 52-three-elements.md
images/                         # Enhanced Mode のみ
  └── 52-three-elements/
      ├── page-003-image-01.webp
      └── ...
```
:::

取り出した画像は、Markdown から `![](page-003-image-01.webp)` のように参照されます。

### 見出し・表・コードまで戻る

文字の層のある PDF からは、文字だけでなく原稿の構造も戻ります。どちらのモードでも同じです。

| 原本 | 戻る Markdown |
| --- | --- |
| 見出し | `#`・`##`・`###` |
| 段落・箇条書き・番号付きリスト | 段落・`-`・`1.` |
| 表 | パイプの表。ページで分かれた表は一つにつなぐ |
| コード | ```` ```ruby:ファイル名 ```` の囲み。行番号は外す |
| 脚注 | `[^1]` と `[^1]: …` |
| 数式 | `$…$`・`$$…$$`（代替テキストに TeX が入ったタグ付き PDF のほか、否定の線・平方根・筆算） |
| ルビ・強調・行内コード | ルビの記法・`**…**`・`` `…` `` |
| 画像 | Enhanced Mode は `![代替テキスト](page-003-image-01.webp)`、Standard Mode は `<!-- 画像: 代替テキスト -->` |

`vs build` で作った PDF のように見出しや段落を「タグ」として持つ PDF は、タグから読みます。タグのない PDF やスキャンした PDF は、文字の大きさ・位置・書体から推定します。推定して組んだ表には、確かめるよう促すコメントが付きます。柱とノンブルは、ページをまたいで同じ位置に繰り返し出る行として見分け、取り込みません。

### 原本と見比べて仕上げる

`vs pdf:read` は、資料を原稿の叩き台にするための道具です。次の所は戻らないか、推定が原本どおりにならないことがあるので、原本と見比べて仕上げてください。

- **囲み**：`:::{.memo}` などの囲みは戻らず、紙面のラベル（`MEMO`・`COLUMN`）が 1 行の段落として残ります。
- **線で描いた図のラベル**：図の範囲に入らなかったラベルが、本文に残ることがあります。
- **2 段組みの読む順**：片方の段に図があるページでは、左右の段の段落の順が前後することがあります。
- **脚注**：表の番号付きの行やグラフの目盛りの数字を、脚注と取り違えることがあります。
- **スキャンに文字を重ねた PDF**：文字の層をそのまま読むので、その層の誤り（「ACM」が `A(2M`）も原稿に入ります。字の正確さが要る資料は、OCR 専用のソフトで文字の層を作り直してから渡すと、見出しや段組みの推定も確かになります。

### 元の画像に差し替える

自分の本を印刷してスキャンした場合のように、図の元の画像が手元にあるなら、`--images-from` でそのフォルダを渡します（Enhanced Mode のみ）。

```shell-session
$ vs pdf:read 95-sample-ocr 96-sample-ocr --images-from images/95-sample
```

取り出した図を元の画像と見た目で突き合わせ、一致したものは元の画像に差し替えます。参照も `![](prototype_meter.webp)` のように元のファイル名になります。一致しなかった図は取り出したまま残し、どの図とも結び付かなかった元の画像は 🟡 で名前を挙げて知らせます。原本と見比べて書き足してください。

### 同じ章を読み直す

同じ章を読み直そうとすると、既存の Markdown を上書きせずに止まります。前回の変換結果に加筆していても、その原稿は残ります。置き換えるときは `--force` を付けます。前回の画像（`images/52-gitlab/`）は、今回の画像と混ざらないよう、消してから書き出します。

```text
🔴 [pdf:read] 52-gitlab は既にあります（前回 sources/gitlab.pdf から読みました）
        → 読み直して置き換えるなら: vs pdf:read gitlab.pdf --force
        → 別の章として読むなら: vs pdf:read gitlab.pdf 53-gitlab-2
```

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

- **`text_area`**：柱とノンブルは繰り返しから見分けるので、既定では書きません。見分けが外れて柱やノンブルが本文に混ざるときだけ、除く幅を mm 単位で書きます。書いた辺だけが効きます。
- **`page_separator`**：`true` にすると、元の PDF のページ境界に `---`（改ページ）が入ります。スキャンした PDF を OCR で読むときだけ効きます（文字の層のある PDF は、ページをまたぐ段落を構造からつなぎます）。

### OCR 設定（Enhanced Mode のみ）

| 項目 | 説明 | 既定値 |
| --- | --- | --- |
| `mode` | `auto`（スキャン PDF を自動検出）/ `force`（全ページ OCR）/ `disable`（OCR 無効） | `auto` |
| `languages` | Tesseract に渡す言語。英語を並べると、コードや英字の語の読み違いが大きく減る | `[japanese, english]` |
| `dpi` | ページを画像に描き直して読むときの解像度（スキャンした画像はそのまま読む） | `300` |
| `psm` | Tesseract のページセグメントモード。`3`（自動）が一般的 | `3` |
| `inline_image_text` | イラスト内テキストの扱い。`include` / `exclude` / `captionize` | `include` |

OCR の結果には、傾きの補正や、形の似た字（`力` と `カ`）・英字の語の取り違えの補正が自動でかかります。形の似た字の補正は、MeCab が入っているときに働きます。OCR は 1 ページに数秒かかるので、`--log` を付けると経過が出ます。

### 誤認識を直す

原本と見比べて繰り返し見つかる誤読は、`config/ocr_corrections.yml` に登録できます。校正辞書（`config/textlint_rewrite.yml`）と同じ形式で、`patterns` に文字列か正規表現（`/pattern/` 形式）を書きます。

```yaml
version: 1
rules:
  - expected: 人工知能      # 人 → 入
    patterns:
      - 入工知能
  - expected: 語彙          # 彙 → 芸。「言語芸術」に当たらないよう、直後の「術」を外す
    patterns:
      - /語芸(?!術)/
```

この補正が適用されるのは**PDF から読み取ったテキストだけ**で、自分で書いた原稿には影響しません。OCR 固有の誤読を校正辞書に登録すると、全原稿が対象になってしまいます。

**一字だけの置き換えは書かないでください。** `力 => カ` と書くと「力学」が「カ学」になるので、`協カ => 協力` のように**語の形**で登録します。`Al` と `AI` のように、文脈を読まないと正誤を決められない組は登録せず、原本と照らして判断してください。

## よくある問題と解決策

| 症状 | 原因 | 解決策 |
| --- | --- | --- |
| `PDF が見つかりません` | `/` を含まない指定は `sources/` の中だけを探す | PDF を `sources/` に置く。ほかの場所なら `./gitlab.pdf` のように `/` を含むパスで指定する |
| `PDF から文字を一つも取り出せませんでした` | スキャン PDF を Standard Mode で読んだ | `vivlio-starter-pdf` を入れて Enhanced Mode（OCR）で読む。原稿と `catalog.yml` には何も書かれていない |
| ヘッダー / フッターが残る | 繰り返しから見分けられなかった | `book.yml` の `pdf_read.text_area` に除く幅を書く |
| 画像が抽出されない | Standard Mode で実行している | `vivlio-starter-pdf` gem をインストール |
| OCR 結果が悪い | 言語設定が不適切 / スキャンの解像度が低い | `languages` を確認（英字が多い本は `english` を足す）。スキャンし直すなら 300dpi 以上で |
| `Tesseract not found` | Tesseract 未インストール | `brew install tesseract tesseract-lang` |
| 日本語の間にスペースが残る | 補正表にない誤読 | `ocr_corrections.yml` にパターンを追加 |
| 画像にテキストが混入する | イラスト領域検出のパラメータ | `inline_image_text: exclude` を試す |

:::{.tip}
最初の変換結果を元の PDF と見比べ、繰り返し出る誤読を `config/ocr_corrections.yml` に追加すると、次の読み取りにも補正を使えます。一度にすべて直そうとせず、原稿を確認しながら辞書を育てていけます。
:::
