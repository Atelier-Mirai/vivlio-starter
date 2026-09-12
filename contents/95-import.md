# Import コマンドの使い方

:::{.chapter-lead}
Vivlio Starter の `vs import` コマンドを使うと、Re:VIEW Starter で書いた本を丸ごと Vivlio プロジェクトへ移せます。原稿（`.re`）を直接読んで変換するので、Re:VIEW も Re:VIEW Starter も動かす必要がありません。本章では前提条件から実行手順、変換されなかった記法の直し方まで、自力で移行を完了できるよう手順をまとめました。
:::

## 事前準備と実行

### 必要ツール

下記が揃っているか `vs doctor --fix` で確認・自動インストールしてください。

- Ruby 3.4 以上 / Bundler
- node / npm
- ImageMagick, qpdf, pdfinfo, Ghostscript, mecab
- `waifu2x-ncnn-vulkan`（任意）
- Rouge（コードブロック言語推定用 gem）

:::{.memo}
**Re:VIEW の実行環境は要りません**

取り込みは `.re` を直接読みます。Re:VIEW の gem も、Re:VIEW Starter に同梱された変換スクリプトも動かしません。何年も前に書いた原稿でも、`.re` さえ手元にあれば取り込めます。

対応しているのは **Re:VIEW Starter の記法**です。Re:VIEW 本体だけで書いたプロジェクトは動作を確かめていません——たとえば行頭の `-`（番号つきリスト）は Starter の拡張で、Re:VIEW 本体では段落になります。取り込みたい場合はご相談ください。
:::

### 取り込み元の確認

取り込み元のディレクトリ直下に、次のファイルがあるか確認してください。

| ファイル | 要否 | 用途 |
| --- | :---: | --- |
| `catalog.yml` | 必須 | 章の一覧と並び |
| `contents/*.re` | 必須 | 原稿 |
| `config.yml` | 任意 | 書名・著者などの書籍情報 |
| `config-starter.yml` | 任意 | 判型・表紙 PDF の指定 |
| `images/` | 任意 | 画像（png/jpg/gif） |
| `source/` | 任意 | 本文から読み込むコード |
| `words.yml` | 任意 | `@<w>{…}` の単語展開に使う辞書 |

**`catalog.yml` に載っている章だけを取り込みます。** Re:VIEW では `contents/` に置いただけの `.re` は原稿として扱われません。書きかけや没にした章がそのまま残っていても、本に混ざる心配はありません。

### 実行コマンド

まず `vs new` で空のプロジェクトを作成し、そこへ取り込みます。

```zsh
vs new mybook
cd mybook
vs import ../review_project            # 通常
vs import --force ../review_project    # 確認を省略したい場合
```

取り込み対象には、Re:VIEW Starter プロジェクトのルートを指定します。

| オプション | 説明 |
| --- | --- |
| `--force` | 既存ディレクトリの削除確認をスキップ |
| `VS_DEBUG=1` | 例外発生時にフルスタックトレースを表示 |

## 処理の流れ

`vs import` を実行すると、以下の処理が順に走ります。

1. **クリーンアップ** — Vivlio 側の `contents/`・`images/`・`codes/` を削除して作り直します。索引・用語集の辞書（`config/index_glossary_terms.yml`・`config/index_glossary_rejected.yml`）も空に戻します。いま消した原稿を説明するデータだからです。
2. **原稿の変換** — `catalog.yml` に並ぶ `.re` を順に読み、Vivlio の Markdown へ書き出します。
3. **ラベル ID の一意化** — Re:VIEW のラベルは章の中で一意ならよいのですが、Vivlio では本全体で一意である必要があります。章をまたいで重複した ID だけ、章名を前に付けて改名します（`tbl1` → `01-intro-tbl1`）。参照している箇所もあわせて書き換わります。
4. **画像処理** — 取り込み元の `images/` をコピーして WebP 化し、元画像（png/jpg/gif）は削除します。
5. **codes/ へのコピー** — `source/` 配下をそのまま `codes/` へコピーします。
6. **YAML 変換** — `catalog.yml` は行単位で書き換えます（`PREDEF`→`PREFACE` などのキー変換と `.re` の除去だけ）。部・コメント・コメントアウトした章は原文のまま残ります。`config.yml` は `book.main_title` などを `book.yml` へ反映し、`config-starter.yml` の `starter.pagesize` は同じ判型の標準プリセット（`B5` なら `b5_standard`）へ対応づけます。
7. **表紙の取り込み** — `config-starter.yml` の `frontcover_pdffile`・`backcover_pdffile` にある PDF を `covers/` へコピーし、その 1 ページめを `frontcover_master.png`・`backcover_master.png` へ変換します。あわせて `book.yml` の `output.cover` を `master` に揃えます。

### 主な記法の行き先

| Re:VIEW | Vivlio |
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

コードフェンスの言語名は、`file=` のパスかキャプションの拡張子から決めます。どちらも無いときは Rouge が内容から推定します（`$`・`%` で始まる行があれば `zsh`）。

:::{.note}
**コードは `codes/` に置いたまま参照します**

Re:VIEW の `//list[][hello.c][file=source/star1/hello.c,1]` は、ビルドのたびにコードの中身を紙面へ展開していました。取り込みではこれを ```` ```include:star1/hello.c ```` に変えます。コードの置き場所が `codes/` の 1 箇所に保たれるので、**コードを直せば紙面にそのまま反映されます**。
:::

### 段落の改行

Re:VIEW は段落の中の改行を連結して組みますが、Vivlio は改行をそのまま紙面の改行にします。そのまま移すと改行が増えてしまうので、**行の終わりを見て分けています**。

- `。`・`？`・`」` などで終わる行 — 改行をそのまま残します（一文一行で書いた原稿の形が保たれます）
- 文の途中で折り返している行 — 次の行と連結します（Re:VIEW での組み上がりに戻ります）

## 変換されなかった記法

取り込みは **知らない記法を黙って通しません**。3 段階でお知らせします。

| 記号 | 意味 | 原文の扱い |
| :---: | --- | --- |
| 🔴 | Vivlio に対応する記法がない。**手で直す必要があります** | そのまま残ります |
| 🟡 | 変換はしたが、指定や装飾が落ちた | 変換後の形になります |
| 🔵 | 見た目が変わりうるが、作業は要りません | 変換後の形になります |

どの記法が何箇所あり、最初の 3 箇所がどのファイルの何行めかを添えて出します。

```
🔴 07-git.re:189、07-git.re:190、07-git.re:247 ほか 42 箇所: @<balloon>（コード内の吹き出し）は
   Vivlio に対応する記法がありません。原文をそのまま残しました。（計 45 箇所）
        対処: 該当箇所を書き換えてください（拡張記法リファレンスの章を参照）。
```

対応する記法が無いのは次の 11 種です。

| 記法 | 理由 |
| --- | --- |
| `//embed` `//raw` `@<embed>` `@<raw>` | 出力形式ごとの生データ（LaTeX / HTML）。移行先では意味を持ちません |
| `//graph` | 外部ツールでの作図。Vivlio では `mermaid` フェンスか生成済みの画像を使います |
| `//hr` | 水平線。Vivlio の `---` は**改ページ**なので当てられません |
| `@<balloon>` | コード内の吹き出し |
| `@<big>` `@<large>` `@<xlarge>` `@<xxlarge>` | 文字を大きくする指定 |

最後に、何をどれだけ変換したかをまとめて出します。

```
🔍 変換サマリ（7 章 / 1462 行）
        ブロック命令 138 件を変換
        インライン命令 178 件を変換
        ラベル ID 3 件を一意化のため改名
        🔴 45 件 / 🟡 12 件 — 詳細は上のログを参照してください
```

## インポート後の確認

インポートが完了したら、以下の点を確認してください。

1. 🔴 が出ていたら、その箇所を手で直す
2. `contents/` に Markdown が揃っているか
3. `.webp` 以外の画像が残っていないか
4. `covers/frontcover_master.png` と `backcover_master.png` が自分の表紙になっているか
5. `config/book.yml` の `book.main_title` などが期待どおりか（コメントが消えていないか）
6. `config/catalog.yml` の章名が `.re` を含んでいないか

確認が済んだら `vs build` を実行して、章構成・画像・表紙が意図どおりか PDF で確かめてください。索引・用語集を使う本なら、そのあと `vs index:auto` で辞書を作り直します。

:::{.notice}
画像は WebP のみ残るため、元画像が必要な場合は事前にバックアップを取ってください。
:::

## トラブルシューティング

| 症状 | 原因 | 解決策 |
| --- | --- | --- |
| `catalog.yml が見つかりません` | 取り込み元の指定が 1 階層ずれている | Re:VIEW プロジェクトのルート（`catalog.yml` のある場所）を指定する |
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
問題があれば `VS_DEBUG=1 vs import ...` で再実行し、ログから原因を特定するのが近道です。
:::
