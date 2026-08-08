# わたしの本

このディレクトリは [Vivlio Starter](https://github.com/Atelier-Mirai/vivlio-starter) で作った書籍プロジェクトです。
Markdown で原稿を書き、`vs build` で PDF・EPUB・Kindle 用ファイルを組み上げます。

このファイルはあなたの本の README です。書名や進捗など、好きなように書き換えてください。

## まず動かしてみる

```bash
vs build
```

数十秒で PDF ができ、macOS なら自動で開きます。まだ何も書いていなくても、サンプル原稿がそのまま 1 冊の本として組み上がります。**「動くものが最初からある」状態から始められる**ので、レイアウトや記法を試しながら少しずつ自分の本へ置き換えていけます。

## 書き始める

`contents/` に入っているのは Vivlio Starter のガイドブックの原稿です。記法の実例が一通り揃っているので、しばらくは見本として残しておき、必要なくなったら消してください。

```bash
vs create 11-intro      # 章ファイルと画像ディレクトリを作る
vs build 11-intro       # その章だけ組んで確認する（速い）
vs delete 21-markdown-tutorial   # いらない見本を消す
```

書籍の情報（書名・著者・判型・テーマ色など）は `config/book.yml` に書きます。章の並びは `config/catalog.yml` です。どちらも `vs create` / `vs delete` が自動で面倒を見るので、ふだん手で開くのは `book.yml` だけです。

## ディレクトリ

| 場所 | 中身 |
| :--- | :--- |
| `contents/` | 原稿（`NN-slug.md`。数字が並び順を決めます） |
| `images/` | 画像。章ごとのディレクトリに分けます |
| `covers/` | 表紙・裏表紙の元画像 |
| `codes/` | 本文へ取り込むサンプルコード |
| `data/` | 本文へ展開するデータ（YAML） |
| `templates/` | 章の雛形とデータ展開テンプレート |
| `stylesheets/` | CSS。手を入れるなら `custom.css` へ |
| `config/` | 設定ファイル一式 |
| `sources/` | 執筆資料の置き場（ビルド対象外） |

ビルドの生成物とキャッシュは `.cache/vs/` に出ます。PDF はプロジェクト直下に置かれます。

## よく使うコマンド

```bash
vs build              # 書籍全体をビルド
vs build 21           # 21 章だけ素早く確認
vs preflight          # ビルド前に原稿のエラーを数秒で洗う
vs lint               # 文章を校正する（表記揺れ・冗長表現・綴り）
vs metrics            # 章ごとの分量と読みやすさを見る
vs open               # できた PDF を開く
vs doctor             # 環境を診断する（--fix で不足ツールを導入）
```

一覧は `vs --help`、個々の使い方は `vs build --help` のように確認できます。

## 出力形式を選ぶ

`config/book.yml` の `output.targets` で決めます。カンマ区切りで併記できます。

| 指定する値 | 生成されるもの | 主な用途 |
| :--- | :--- | :--- |
| `pdf` | 閲覧用 PDF | 手元での確認・ダウンロード配布 |
| `print_pdf` | トンボ・塗り足し付き PDF | 印刷所への入稿 |
| `epub` | EPUB | 楽天 Kobo・Apple Books |
| `kindle` | KPF | Amazon KDP |

## 困ったとき

まず `vs doctor` を実行してください。ビルドや校正が突然失敗するときは、外部ツールが足りていないか壊れていることがほとんどです。`vs doctor --fix` で自動的に導入・修復できます。

記法や設定の詳しい解説は、同梱のガイドブック『はじめての技術書づくり』にあります。`vs build` すればそのまま読める PDF になりますし、原稿を `contents/` で直接読んでも構いません。

環境をまとめて新しくしたいときは `vs upgrade` です。Vivlio Starter 本体・プロジェクトの雛形・外部ツールを 1 コマンドで最新化します。**あなたの原稿・画像・辞書には手を触れません。**

## 執筆の進めかた

書いては整え、また書く——この往復が読みやすい本を作ります。

1. `vs create` で章を足し、Markdown で書く
2. `vs build 章番号` で体裁を確かめる
3. `vs lint` と `vs metrics` で文章を整える
4. ひととおり書けたら `vs build` で全体を組む
5. 表紙を用意し、`output.targets` を目的に合わせて入稿・配布

焦らず、ひとつずつ。あなたの本ができあがるのを楽しみにしています。
