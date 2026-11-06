# 補助コマンドとカスタマイズ

:::{.chapter-lead}
原稿を書く作業の周りには、PDF の閲覧・圧縮・画像化、生成物の片づけといった小さな作業があります。本章では、そのときに使う補助コマンドと、紙面の見た目を `custom.css` で調整する方法をまとめます。必要な場面から読んでください。
:::

** 本章で扱うコマンド **

| コマンド | 目的 |
| :--- | :--- |
| `vs --help`・`vs --version` | コマンドの使い方と、Vivlio Starter のバージョンを表示する |
| `vs open` | PDF を開く |
| `vs pdf:compress` | PDF を圧縮する |
| `vs pdf:pages` | PDF のページを画像にする |
| `vs pdf:rasterize` | PDF の全ページを画像にして結合し直す |
| `vs clean` | 生成したファイルやキャッシュを削除する |

## コマンドの使い方を調べる

:::{.section-lead}
コマンドの名前やオプションを忘れたときは、本書を開かなくても端末で確かめられます。
:::

```bash
vs --help          # コマンドの一覧
vs build --help    # vs build のオプション
vs --version       # インストールされている Vivlio Starter のバージョン
```

どのコマンドにも `--help` を付けられます。`vs --version` は、`vs upgrade` で本体が更新されたかを確かめるときに使えます。

:::{.output}
vivlio-starter 1.0.0
:::

## PDF を開く

:::{.section-lead}
ビルドの後に閉じた PDF をもう一度確かめるときは、`vs open` を使います。単章ビルドの PDF も開けます。
:::

```bash
vs open                # 本全体の閲覧用 PDF を開く
vs open 11-intro       # 11-intro.pdf を開く（.pdf は省略可）
```

引数を省略すると、本全体の閲覧用 PDF（`mybook_v0.1.0.pdf`）を開きます。圧縮版（`mybook_v0.1.0_compressed.pdf`）もあるときは、更新日時の新しいほうを開きます。ファイル名を指定したときは、プロジェクト直下、`sources/` の順に探します。

ビルドの後と同じく、`close_existing_windows` が `true` なら、開く前にプレビューのウィンドウをすべて閉じます（@chapref:ch-build）。

## PDF を圧縮する

:::{.section-lead}
`vs pdf:compress` は、レビュー用の PDF を送る前に容量を抑えたいときに使います。Ghostscript で画像の解像度を 150 dpi に下げ、別のファイルに書き出します。元の PDF は変更しません。
:::

```bash
vs pdf:compress                       # 本全体の閲覧用 PDF を圧縮する
vs pdf:compress 11-intro              # 11-intro.pdf を圧縮する（.pdf は省略可）
vs pdf:compress input.pdf output.pdf  # 出力するファイル名も指定する
```

出力するファイル名を省略すると、元のファイル名に `_compressed` を付けた名前になります（`11-intro.pdf` → `11-intro_compressed.pdf`）。

印刷所へは、圧縮していない入稿用 PDF を渡してください。入稿用 PDF を指定すると、印刷所の基準（300〜350 dpi）を下回ることを 🟡 で警告し、圧縮を続けるかを確認します。

ビルドのたびに圧縮版も作るときは、`config/book.yml` の `output.pdf.compress` を `true` にします（@chapref:ch-build）。

## ページを画像にする

:::{.section-lead}
見本のページを画像にして、SNS やイベントの告知に載せるときは、`vs pdf:pages` を使います。
:::

```bash
vs pdf:pages                   # 本全体の閲覧用 PDF の全ページ
vs pdf:pages 95-sample         # 95-sample.pdf の全ページ
vs pdf:pages --pages=1,3,5-8   # 1・3・5〜8 ページだけ
```

引数を省略すると、本全体の閲覧用 PDF を画像にします。画像は `page-001.jpg` のような名前で、`mybook_v0.1.0_images/` のようなフォルダに保存されます。単章ビルドの PDF は、ファイル名を指定したときだけ対象になります。ページ番号は PDF の 1 枚目から数えるので、紙面のノンブルとは一致しないことがあります。

同じ PDF をもう一度画像にすると、保存先のフォルダにある前回の画像（`page-*.jpg`）は削除されます。残す画像は、別のフォルダへ移すか、`--output` で保存先を変えます。

** vs pdf:pages のオプション **

| オプション | 既定値 | 説明 |
| :--- | :---: | :--- |
| `--pages` | （全ページ） | 画像にするページ（`1,3,5-8`） |
| `--dpi` | `350` | 解像度。大きくするほど鮮明になり、ファイルも大きくなる |
| `--quality` | `95` | JPEG の品質（1〜100） |
| `--output` | （自動） | 保存先のフォルダ（`--output=./samples`） |

## 画像だけの PDF を作る

印刷所のシステムが PDF 内のフォントを受け付けない場合は、原因を確認したうえで、ページ全体を画像化する方法もあります。`vs pdf:rasterize` は、**すべてのページを画像にして結合し直した PDF** を作ります。文字を検索できなくなる、ファイルサイズが大きくなるなどのデメリットが発生します。必要に応じて用いてください。

```bash
vs pdf:rasterize
```

元の PDF の各ページを画像にして結合し直し、`<元のファイル名>_rasterized.pdf` を作成します。

**ラスタライズした PDF の性質**

- **フォントに由来する問題を避けられます**: 文字が画像になるので、入稿先がフォントを処理する必要がなくなります。画像の PDF を受け付けるかは、入稿先の条件で確かめてください
- **文字を選択・検索できなくなります**: 印刷の仕上がりには影響しません
- **ファイルサイズが大きくなります**: 元の数倍〜数十倍になることがあります

途中で書き出した各ページの JPEG を、終わったあとに削除するときは `vs pdf:rasterize --clean` とします。

## 生成物を削除する

:::{.section-lead}
ビルドの途中で作る中間ファイルは、ビルドの後に自動で削除されます。`vs clean` は、キャッシュを作り直したいときや、プロジェクト直下に出力した PDF などをまとめて削除したいときに使います。
:::

** vs clean のオプション **

| オプション | 削除するもの |
| :--- | :--- |
| `--cache` / `-C` | キャッシュ（`.cache/vs/`） |
| `--purge` / `-P` | プロジェクト直下に出力したファイル |
| `--cover` | 生成した表紙の画像 |
| `--generated-images` | 生成した扉絵・節絵の画像 |
| `--all` | `--index-dictionaries` 以外の上のすべて |
| `--index-dictionaries` | 索引・用語集の辞書（確認あり） |

キャッシュと生成した画像は、次のビルドで作り直されます。`covers/` に置いた表紙の元の画像は削除しません。

`--purge` は、PDF・EPUB・Kindle 用のファイル・表紙の JPEG に加えて、索引のレビューファイル（`_index_glossary_review.md`）も削除します。レビューファイルを編集している間は、先に `vs index:apply` で辞書へ登録してから実行してください（@chapref:ch-index-glossary）。

`--index-dictionaries` は、索引・用語集に登録した語・除外した語・読みの辞書を削除します。削除の前に確認があります。

:::{.tip}
原稿や設定を直したのに紙面が変わらないときは、`vs clean --cache` の後にビルドし直すと、キャッシュを作り直した紙面で確かめられます。
:::

## 紙面の見た目を調整する @custom-css

:::{.section-lead}
判型・書体・テーマ色は `config/book.yml` で選べます。リンクの色やコードブロックの背景など、`book.yml` に設定のない部分の見た目は、`stylesheets/custom.css` で調整します。
:::

章の HTML には、次の順でスタイルシートが読み込まれます。

1. `theme.css`: テーマ色などの CSS 変数の既定値
2. `chapter.css` など: 章の種類ごとの紙面
3. `book-settings.css`: `book.yml` の設定から、ビルドのたびに作られる
4. `custom.css`: 著者が編集するファイル

`custom.css` は最後に読み込まれるので、同じ詳細度（どの指定を優先するかを決める、セレクタの強さ）の指定なら、ここに書いたものが優先されます。`vs upgrade` は `custom.css` を書き換えません。ほかの CSS は新しい雛形へ更新されるので、直接編集せず、変えたい指定を `custom.css` に書いてください。

### CSS 変数で色を変える

色の多くは CSS 変数で決まっています。`custom.css` の `:root` に同じ名前の変数を書くと、その色に変わります。

```css:stylesheets/custom.css
:root {
  --color-link: #1a73e8;       /* リンクを青に */
  --color-column-bg: #f5f5dc;  /* コラムの背景をベージュに */
}
```

** custom.css で変えられる主な CSS 変数 **

| 変数名 | 既定値 | 色を付ける箇所 |
| :--- | :--- | :--- |
| `--color-link` | `#000` | リンクの文字 |
| `--color-strong` | テーマ色 | 太字（`**強調**`） |
| `--color-em-underline` | テーマ色 | 強意（`*強意*`）の下線 |
| `--color-column-bg` | テーマ色を淡くした色 | コラムの背景 |
| `--color-column-border` | テーマ色 | コラム・メモの枠線 |
| `--color-figure-border` | `#ccc` | 画像の枠線 |

Kindle は CSS 変数に対応していないので、変数で変えた色は Kindle には反映されません。Kindle にも同じ色を使うときは、`body.vs-kindle .column { background: #f5f5dc; }` のように、`body.vs-kindle` を前に付けたセレクタに色を直接書きます。

### 規則を書いて変える

変数のない部分は、CSS の規則を書いて変えます。たとえば、コラムの文字を小さくするときは次のように書きます。

```css:stylesheets/custom.css
.column {
  font-size: 9pt;
}
```

雛形の CSS と同じセレクタで書くと、確実に上書きできます。コードブロックは、雛形の `code.css` が `pre[class*="language-"]` で指定しているので、背景の色も同じセレクタで指定します。`pre { … }` と書くと詳細度が低く、反映されません。

```css:stylesheets/custom.css
pre[class*="language-"] {
  background: #f8f8f8;
}
```

反映されないときは、雛形の CSS から同じ部分のセレクタを探して使います。

CSS 変数やクラスの名前は、今後のバージョンで変わることがあります。バージョンを上げたら、`custom.css` の指定が紙面に反映されているかを確かめてください。
