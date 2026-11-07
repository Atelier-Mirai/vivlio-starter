# Re:VIEW Starter からの移行

:::{.chapter-lead}
Re:VIEW Starter で書いた本を Vivlio Starter へ移すには、`vs import` を使います。原稿（`.re`）を直接読み取るため、以前の執筆環境を動かす必要はありません。この章では、取り込み元の確認から変換後の点検まで、移行の順に沿って説明します。Re:VIEW Starter で書いた原稿がなければ、この章は飛ばしてかまいません。
:::

## プロジェクトを取り込む

`vs import` は、Re:VIEW Starter のプロジェクトから原稿・画像・コード・書籍情報を読み取り、Vivlio Starter のプロジェクトへ変換します。まず取り込み元に必要なファイルがあるかを確かめ、次に移行先のプロジェクトで `vs import` を実行します。

### 取り込み元を確かめる

取り込み元（`review_project`）のルートに、次のファイルやディレクトリがあるか確かめます。

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

:::{.memo}
**Re:VIEW で書いた原稿について**

`vs import` が対応しているのは **Re:VIEW Starter 記法**です。たとえば行頭の ` - ` は、Starter では番号付きリストに、Re:VIEW では段落になるなど、両者の記法には違いがあります。Re:VIEW 記法の原稿も取り込める見込みはありますが、検証はしていません。
:::

### `vs import` を実行する

移行先として、取り込み元の `review_project` と同じ階層に新しいプロジェクト `mybook` を作り、そこへ取り込みます。

:::{.diagram}
```text
books/
  review_project/   ← 取り込み元（Re:VIEW Starter）
  mybook/           ← 移行先（vs new で作る）
```
:::

`mybook` の中から見ると、取り込み元は `../review_project` です。

```zsh
vs new mybook
cd mybook
vs import ../review_project
```

`vs import` には、`catalog.yml` がある Re:VIEW Starter プロジェクトのルートを指定します。取り込み元のファイルは読み取るだけで、変更しません。

移行先の `contents/`・`images/`・`codes/` は作り直すので、削除してよいかの確認が表示されます。索引・用語集の辞書（`config/index_glossary_terms.yml` など）も空に戻します。`vs new` で作った直後なら、削除されるのは雛形の見本だけです。取り込み直すときは、取り込んだ後に手を入れた原稿や画像を、先に別の場所へ保存してください。

## 変換の内容

取り込むと、ファイルの置き場所と原稿の記法が Vivlio Starter の形に変わります。ここでは、それぞれの行き先と、段落の改行の扱いを説明します。

### ファイルの行き先

取り込み元のファイルは、移行先の次の場所へ変換されます。

:::{.long-table}
| 取り込み元 | 移行先 |
| --- | --- |
| `contents/*.re` | `contents/*.md` |
| `catalog.yml` | `config/catalog.yml`（部やコメントアウトした章も残ります） |
| `images/` | `images/`（WebP に変換します） |
| `source/` | `codes/` |
| `config.yml` | `config/book.yml` の書名・著者・発行者など |
| `config-starter.yml` | `config/book.yml` の判型（`B5` なら `b5_standard`） |
| 表紙の PDF | `covers/` の表紙の画像（PDF の 1 ページ目） |
:::

### 主な記法の行き先

:::{.long-table}
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
| `@<balloon>{説明}`（コードの行の注釈） | `← 説明` |
:::

ラベル ID はそのまま引き継ぎます。ただし Vivlio Starter のラベルは本全体で一意なので、章をまたいで同じ ID があれば、章名を付けて改名します（`tbl1` → `11-intro-tbl1`）。参照している箇所も合わせて直します。

コードフェンスの言語名は、原稿の指定（`//list[id][キャプション][ruby]`）か、ファイルの拡張子から付けます。どちらもないコードは内容から推定し、確かなものだけに付けます。付かなかったコードは、取り込んだあとに `vs lint` が言語名を提案します（@ch-lint の章の @pageref:lint-code-language）。

### 段落の改行

Re:VIEW Starter は段落内の改行をつなげて組みます。一方、Vivlio Starter は原稿の改行を紙面にも反映します。変換時に改行が増えすぎないよう、**行末の形を見て次のように処理します**。

- `。`・`？`・`」` などで終わる行 — 改行をそのまま残します（一文一行で書いた原稿の形が保たれます）
- 文の途中で折り返している行 — 次の行と連結します（Re:VIEW Starter での組み上がりに戻ります）

## 変換されなかった記法

変換できない記法や、変換で指定や装飾が失われた記法は、実行後にまとめて報告します。表示は次の二段階です。

| 記号 | 意味 | 原文の扱い |
| :---: | --- | --- |
| 🔴 | Vivlio Starter に対応する記法がない。**手で直す必要があります** | そのまま残ります |
| 🟡 | 変換はしたが、指定や装飾が失われた | 変換後の形になります |

記法ごとの件数と、最初の 3 箇所についてファイル名・行番号が表示されます。

:::{.output}
```text
🔴 21-first-html.re:646: @<large>（文字を大きくする指定）は Vivlio Starter に対応する記法がありません。原文を残しましたので、該当箇所を書き換えてください。
🟡 21-first-html.re:233、21-first-html.re:242、21-first-html.re:549、ほか 3 箇所: 行番号の振り方の指定（開始番号・飛び番）は移せないため、1 から続けて振ります。（計 6 箇所）
```
:::

手作業で置き換える必要があるのは、次の 10 種です。

| 記法 | 理由 |
| --- | --- |
| `//embed` `//raw` `@<embed>` `@<raw>` | 出力形式ごとの生データ（LaTeX / HTML）。移行先では意味を持ちません |
| `//graph` | 外部ツールでの作図。Vivlio Starter では `mermaid` フェンスか生成済みの画像を使います |
| `//hr` | 水平線。Vivlio Starter の `---` は**改ページ**なので置き換えられません |
| `@<big>` `@<large>` `@<xlarge>` `@<xxlarge>` | 文字を大きくする指定 |

最後に、変換した件数と確認が必要な件数がまとめて表示されます。

:::{.output}
```text
🔍 変換サマリ（14 章 / 6461 行）
        ブロック命令 579 件を変換
        インライン命令 1194 件を変換
        コードブロック 20 個に、推定した言語名を付与
        コードブロック 2 個は言語名を確かめきれず（vs lint で「〜らしい」と提案します）
        🔴 1 件 / 🟡 10 件 — 詳細は上のログを参照してください
```
:::

## インポート後の確認

取り込みが終わったら、まず 🔴 の箇所を直し、続けてファイルと設定を確認します。

1. 🔴 が出ていたら、その箇所を手で直す
2. `contents/` に Markdown が揃っているか
3. `.webp` 以外の画像が残っていないか
4. `covers/` の表紙の画像が、自分の表紙になっているか
5. `config/book.yml` の書名などが期待どおりか
6. `config/catalog.yml` の章名が `.re` を含んでいないか

確認後に `vs build` を実行し、章の並びや画像、表紙を PDF で見てください。索引・用語集を使う場合は、原稿に合わせて `vs index:auto` で辞書を作り直します。ここまで確かめれば、新しい環境での執筆を続けられます。

## トラブルシューティング

| 症状 | 原因 | 解決策 |
| --- | --- | --- |
| `catalog.yml が見つかりません` | 指定したディレクトリに `catalog.yml` がない | `catalog.yml` のあるディレクトリを指定する |
| `原稿（.re）が見つかりません` | 原稿のディレクトリに `.re` が一つもない | `config.yml` の `contentdir`（既定は `contents/`）のディレクトリを確かめる |
| 章が足りない | 取り込み元の `catalog.yml` に載っていない | `catalog.yml` に章を追加して、取り込み直す |
| 会話の話者名が `avatar-b` のように表示され、アバターも付かない | `config/talk.yml` に話者が登録されていない | 🟡 が挙げた話者を `config/talk.yml` に登録する |
| 判型が雛形のまま | `starter.pagesize` が A5・B5 以外 | `config/book.yml` の `page.use` を指定する |
| `config/book.yml` に書名などが入らない | `config/book.yml` からその項目の行を削除したか、コメントにした | 🟡 が示す行を `config/book.yml` に書き足す |
