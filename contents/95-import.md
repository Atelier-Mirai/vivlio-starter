# Import コマンドの使い方

:::{.chapter-lead}
Re:VIEW Starter で書いた本を Vivlio Starter へ移すには、`vs import` を使います。原稿（`.re`）を直接読み取るため、以前の執筆環境を動かす必要はありません。この章では、取り込み元の確認から変換後の点検まで、移行の順に沿って説明します。
:::

## 事前準備と実行

### 必要ツール

まず必要なツールを確認します。macOS では `vs doctor` で不足を調べ、`vs doctor --fix` で導入できます。

- Ruby 3.4 以上 / Bundler
- node / npm
- ImageMagick / qpdf / pdfinfo / Ghostscript / MeCab
- `waifu2x-ncnn-vulkan`（任意）
- Rouge（コードブロック言語推定用 gem）

:::{.memo}
**Re:VIEW Starter の実行環境は要りません**

`vs import` が読み取るのは `.re` ファイルです。Re:VIEW の gem や Re:VIEW Starter の変換スクリプトは使いません。以前の執筆環境が残っていなくても、原稿ファイルがあれば取り込めます。

対応しているのは **Re:VIEW Starter 記法**です。たとえば行頭の `-` は Starter では番号付きリストですが、Re:VIEW では段落として扱われるなど、記法体系に相違があります(Re:VIEW 記法から Markdown への変換も可能かとは思いますが、未検証です）。
:::

### 取り込み元の確認

取り込み元のルートに、次のファイルやディレクトリがあるか確かめます。

| ファイル | 要否 | 用途 |
| --- | :---: | --- |
| `catalog.yml` | 必須 | 章の一覧と並び |
| `contents/*.re` | 必須 | 原稿 |
| `config.yml` | 任意 | 書名・著者などの書籍情報 |
| `config-starter.yml` | 任意 | 判型・表紙 PDF の指定 |
| `images/` | 任意 | 画像（png/jpg/gif） |
| `source/` | 任意 | 本文から読み込むコード |
| `words.yml` | 任意 | `@<w>{…}` の単語展開に使う辞書 |

**取り込むのは `catalog.yml` に載っている章だけです。** `contents/` に `.re` があっても、catalog に載っていなければ対象になりません。書きかけの章や外した章が残っている場合も、意図せず本に加わることはありません。

### 実行コマンド

移行先として新しいプロジェクトを作り、そこへ取り込みます。

```zsh
vs new mybook
cd mybook
vs import ../review_project            # 通常
vs import --force ../review_project    # 確認を省略したい場合
```

`vs import` には、`catalog.yml` がある Re:VIEW Starter プロジェクトのルートを指定します。

| オプション | 説明 |
| --- | --- |
| `--force` | 既存ディレクトリの削除確認をスキップ |
| `VS_DEBUG=1` | 例外発生時にフルスタックトレースを表示 |

## 処理の流れ

取り込みでは、次の処理が順に行われます。最初に移行先の原稿や画像が作り直されるため、すでに編集したファイルがある場合は実行前に確認してください。

1. **クリーンアップ** — 移行先の `contents/`・`images/`・`codes/` を削除して作り直します。索引・用語集の辞書（`config/index_glossary_terms.yml`・`config/index_glossary_rejected.yml`）も、入れ替わる原稿に合わせて空に戻します。
2. **原稿の変換** — `catalog.yml` に並ぶ `.re` を順に読み、Vivlio Starter の Markdown へ書き出します。
3. **ラベル ID の一意化** — Re:VIEW Starter では章内で重複しなければよかったラベルを、本全体で一意になるよう確認します。章をまたいで重なる ID だけ、章名を付けて改名し（`tbl1` → `01-intro-tbl1`）、参照箇所も合わせて直します。
4. **画像処理** — 取り込み元の `images/` をコピーして WebP 化し、元画像（png/jpg/gif）は削除します。
5. **codes/ へのコピー** — `source/` 配下をそのまま `codes/` へコピーします。
6. **YAML 変換** — `catalog.yml` では `PREDEF`→`PREFACE` などのキーを変え、章名から `.re` を外します。部、コメント、コメントアウトした章は残します。`config.yml` の `book.main_title` などは `book.yml` に反映し、`config-starter.yml` の `starter.pagesize` は同じ判型の標準プリセット（`B5` なら `b5_standard`）へ対応づけます。
7. **表紙の取り込み** — `config-starter.yml` の `frontcover_pdffile`・`backcover_pdffile` にある PDF を `covers/` へコピーし、その 1 ページめを `frontcover_master.png`・`backcover_master.png` へ変換します。あわせて `book.yml` の `output.cover` を `master` に揃えます。

### 主な記法の行き先

| Re:VIEW Starter | Vivlio Starter|
| --- | --- |
| `= 見出し` / `=={id} 見出し` | `# 見出し` / `## 見出し @id` |
| `===[column]` … `===[/column]` | `:::{.column}` … `:::` |
| ` * 項目` | `- 項目` |
| ` - 1. 項目` / ` - (A) 項目` | `1. 項目` / `(A) 項目` |
| ` : 用語` ＋ 字下げした説明 | `用語` の次の行に `: 説明` |
| `//list[id][説明]{ … //}` | `** 説明 @id **` ＋ コードフェンス |
| `//list[][][file=source/a/b.c,1]` | ```` ```include:a/b.c ```` |
| `//image[id][説明][width=40%]` | `** 説明 @id **` ＋ `![](id.webp){width=40%}` |
| `//sideimage[絵][30mm][side=R]{ … //}` | `:::{.sideimage-right}`（幅は版面に対する比率へ換算） |
| `//terminal` / `//output` | `:::{.terminal}` / `:::{.output}` |
| `//abstract` / `//tip` / `//note` / `//notice` | `:::{.chapter-lead}` / `:::{.tip}` / `:::{.note}` / `:::{.notice}` |
| `//table`（タブ区切り・`csv=on`） | Markdown の表 |
| `//talklist` ＋ `//talk[絵][名前]` | `:::{.talk}` に「名前: 発話」 |
| `//footnote[id][本文]` / `@<fn>{id}` | `[^id]: 本文` / `[^id]` |
| `//clearpage` / `//vspace[latex][7mm]` / `//blankline` | `@pagebreak` / `@vspace:7mm` / 段落末の `{.aki}` |
| `@<code>` / `@<B>` / `@<href>` / `@<ruby>` | `` `…` `` / `**…**` / `[…](…)` / `{漢字\|よみ}` |

コードフェンスの言語名は、まず `file=` のパスやキャプションの拡張子から決めます。手がかりがない場合は Rouge が内容から推定します。`$` や `%` で始まる行は `zsh` として扱います。

:::{.note}
**コードは `codes/` に置いたまま参照します**

Re:VIEW Starter の `//list[][hello.c][file=source/star1/hello.c,1]` は、ビルドのたびにコードの内容を紙面へ展開します。取り込み後は ```` ```include:star1/hello.c ```` となり、`codes/` のファイルを参照します。**コードを直した結果を紙面にも反映できる**ので、同じ内容を原稿に書き写す必要はありません。
:::

### 段落の改行

Re:VIEW Starter は段落内の改行をつなげて組みます。一方、Vivlio Starter は原稿の改行を紙面にも反映します。変換時に改行が増えすぎないよう、**行末の形を見て次のように処理します**。

- `。`・`？`・`」` などで終わる行 — 改行をそのまま残します（一文一行で書いた原稿の形が保たれます）
- 文の途中で折り返している行 — 次の行と連結します（Re:VIEW Starter での組み上がりに戻ります）

## 変換されなかった記法

変換できない記法や、見え方が変わる可能性のある記法は、実行後にまとめて報告します。表示は次の三段階です。

| 記号 | 意味 | 原文の扱い |
| :---: | --- | --- |
| 🔴 | Vivlio Starter に対応する記法がない。**手で直す必要があります** | そのまま残ります |
| 🟡 | 変換はしたが、指定や装飾が落ちた | 変換後の形になります |
| 🔵 | 見た目が変わりうるが、作業は要りません | 変換後の形になります |

記法ごとの件数と、最初の 3 箇所についてファイル名・行番号が表示されます。

```
🔴 07-git.re:189、07-git.re:190、07-git.re:247 ほか 42 箇所: @<balloon>（コード内の吹き出し）は
   Vivlio Starter に対応する記法がありません。原文をそのまま残しました。（計 45 箇所）
        対処: 該当箇所を書き換えてください（拡張記法リファレンスの章を参照）。
```

手作業で置き換える必要があるのは、次の 11 種です。

| 記法 | 理由 |
| --- | --- |
| `//embed` `//raw` `@<embed>` `@<raw>` | 出力形式ごとの生データ（LaTeX / HTML）。移行先では意味を持ちません |
| `//graph` | 外部ツールでの作図。Vivlio Starter では `mermaid` フェンスか生成済みの画像を使います |
| `//hr` | 水平線。Vivlio Starter の `---` は**改ページ**なので当てられません |
| `@<balloon>` | コード内の吹き出し |
| `@<big>` `@<large>` `@<xlarge>` `@<xxlarge>` | 文字を大きくする指定 |

最後に、変換した件数と確認が必要な件数がまとめて表示されます。

```
🔍 変換サマリ（7 章 / 1462 行）
        ブロック命令 138 件を変換
        インライン命令 178 件を変換
        ラベル ID 3 件を一意化のため改名
        🔴 45 件 / 🟡 12 件 — 詳細は上のログを参照してください
```

## インポート後の確認

取り込みが終わったら、まず 🔴 の箇所を直し、続けてファイルと設定を確認します。

1. 🔴 が出ていたら、その箇所を手で直す
2. `contents/` に Markdown が揃っているか
3. `.webp` 以外の画像が残っていないか
4. `covers/frontcover_master.png` と `backcover_master.png` が自分の表紙になっているか
5. `config/book.yml` の `book.main_title` などが期待どおりか（コメントが消えていないか）
6. `config/catalog.yml` の章名が `.re` を含んでいないか

確認後に `vs build` を実行し、章の並びや画像、表紙を PDF で見てください。索引・用語集を使う場合は、原稿に合わせて `vs index:auto` で辞書を作り直します。ここまで確かめれば、新しい環境での執筆を続けられます。

:::{.notice}
取り込み後の画像は WebP になります。元の PNG・JPEG・GIF が必要なら、実行前に取り込み元をバックアップしてください。
:::

## トラブルシューティング

| 症状 | 原因 | 解決策 |
| --- | --- | --- |
| `catalog.yml が見つかりません` | 取り込み元の指定が 1 階層ずれている | Re:VIEW Starter プロジェクトのルート（`catalog.yml` のある場所）を指定する |
| `原稿（.re）が見つかりません` | `config.yml` の `contentdir` が既定と違う | `contentdir` の指すディレクトリに `.re` があるか確認する |
| 章が足りない | `catalog.yml` に載っていない | 取り込みたい章を `catalog.yml` へ追加してから実行する |
| 会話に話者の色が付かない | `book.yml` に話者が未登録 | 🟡 が挙げた話者キーを `book.yml` の `characters` に登録する |
| Rouge が見つからない | gem が未インストール | `vs doctor --fix` または `gem install rouge` |
| 表紙 PDF がコピーされない | `frontcover_pdffile` が PNG など PDF 以外 | 取り込みは PDF のみ対応。`covers/frontcover_master.png` を直接置き換える |
| 裏表紙が雛形の見本画像のまま | 取り込み元に `backcover_pdffile` の指定がない | `covers/backcover_master.png` を自分の画像に置き換える |
| 判型が雛形のまま | `starter.pagesize` が A5・B5 以外 | `config/book.yml` の `page.use` を自分で指定する |
| `config/book.yml` の値が更新されない | 対応パスが見つからない | コメントやインデントが崩れていないか確認 |

:::{.column}
**ヒント**  
原因が分からない場合は `VS_DEBUG=1 vs import ...` で詳細なログを確認できます。再実行すると移行先のファイルが作り直されるため、先に残したい変更を退避してください。
:::
