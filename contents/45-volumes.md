# 分冊と合本

:::{.chapter-lead}
一冊を上下巻や上中下巻に分けて刊行するときは、巻ごとの章の構成を `catalog.yml` に書きます。原稿は `contents/` に一つにまとめたまま、各巻を一冊ずつ組むことも、全巻を一冊にまとめた合本を組むこともできます。この章では、各巻の章構成の記述法、各巻と合本の書名と表紙、組み方を順に説明します。
:::

** 本章で扱う設定とコマンド **

| 設定・コマンド | 目的 |
| :--- | :--- |
| `VOLUMES:` | 上下巻ごとの章構成を記述する |
| `chapter_start`<br>`appendix_start` | 各巻の章番号・付録の記号の<br>始まりを決める |
| `whole_toc` | 各巻に全巻目次を載せる |
| `main_title`や`cover` など | 各巻の書名・表紙を書く |
| `vs cover upper` | 上巻の表紙を作る |
| `vs build upper` | 上巻だけを組む |
| `vs build all` | 全巻を一巻ずつ組む |
| `vs build` | 合本を組む |

## 上下巻ごとの章構成を記述する

@pageref:catalog-yml で示した一冊の本の本文を、上巻と下巻に分けると、次のようになります。

```yaml:config/catalog.yml
VOLUMES:
  - name: 上巻               # 各巻の呼び名
    id: upper               # 各巻の識別子（コマンドと出力ファイル名に使う）
    CHAPTERS:
      - 第一部 はじめる:
          - 11-intro
          - 12-basics

  - name: 下巻
    id: lower
    CHAPTERS:
      - 第二部 使いこなす:
          - 21-advanced
          - 22-practice
```

`VOLUMES:` の下に各巻を並べ、各巻ごとに、一冊の本と同じ区分（`PREFACE`・`CHAPTERS`・`APPENDICES`・`POSTFACE`）で原稿を並べます。部も、一冊の本と同じように書けます。各巻の数に制約はありません。本文と付録は、各巻の中に書きます。

各巻には、呼び名の `name` と、識別子の `id` を付けます。`id` は、`vs build upper` のように各巻を選ぶときと、出力ファイル名に使います。半角英字で始め、数字は末尾にだけ使えます（`upper`・`vol1`）。記号は使えず、大文字と小文字は区別しません。`all` は全巻を指す為の予約語です。

### 前書き・後書き

シリーズの紹介や全巻の結びのように、書籍全体の前書き・後書きは、各巻の外に、`VOLUMES:` と同じ字下げで書きます。
各巻の前書き・後書きは、その巻の `PREFACE`・`POSTFACE` に書きます。

```yaml:config/catalog.yml
PREFACE:                    # 書籍全体の前書き
  - 00-preface
POSTFACE:                   # 書籍全体の後書き
  - 99-postface

VOLUMES:
  - name: 上巻
    id: upper
    CHAPTERS:
      - 11-intro
    POSTFACE:
      - 19-to-lower         # 上巻の後書き（下巻への案内）

  - name: 下巻
    id: lower
    PREFACE:
      - 20-preface-lower    # 下巻の前書き
    CHAPTERS:
      - 21-advanced
```

各巻を選んで組むと、書籍全体の前書きは最初の巻に、書籍全体の後書きは最後の巻に載ります。その巻にも前書き・後書きがあるときは、前書きは書籍全体のものが先、後書きは書籍全体のものが後です。合本には書籍全体の前書き・後書きだけが載り、各巻の前書き・後書きは載りません。この例では、次のように載ります。

** 各巻と合本に載る前書き・後書き **

| 組むもの | 前書き | 後書き |
| :--- | :--- | :--- |
| 上巻 | `00-preface` | `19-to-lower` |
| 下巻 | `20-preface-lower` | `99-postface` |
| 合本 | `00-preface` | `99-postface` |

書籍全体の前書きを書かない本の合本には最初の巻の前書きが、書籍全体の後書きを書かない本の合本には最後の巻の後書きが載ります。

### 同じ原稿を二つ以上の巻に書く

同じ原稿を、二つ以上の巻に書けます。下巻だけを手に取る読者のためにインストールの章を両方の巻に載せるときや、付録を共通にするときに使います。合本には一度だけ載ります。

```yaml:config/catalog.yml
VOLUMES:
  - name: 上巻
    id: upper
    CHAPTERS:
      - 11-install          # インストールの章
      - 12-basics
    APPENDICES:
      - 90-cheatsheet

  - name: 下巻
    id: lower
    CHAPTERS:
      - 11-install          # 上巻と同じ章
      - 21-advanced
    APPENDICES:
      - 90-cheatsheet       # 上巻と同じ付録
```

どの巻から読み始めた読者にも読ませたい前書きも、同じように、書籍全体の `PREFACE` と、2 巻目以降の巻の `PREFACE` の両方に書きます。

### 章番号・付録の記号・全巻目次

章番号と付録の記号は、全巻を通して振ります。各巻ごとに振り直すときは、各巻に始めの番号と記号を書きます。

```yaml:config/catalog.yml
VOLUMES:
  - name: 上巻
    id: upper
    CHAPTERS:
      - 11-intro            # 第1章
      - 12-basics           # 第2章
    APPENDICES:
      - 90-cheatsheet       # 付録 A
      - 91-glossary         # 付録 B

  - name: 下巻
    id: lower
    chapter_start: 1        # 省くと第3章から
    appendix_start: A       # 省くと付録 C から
    whole_toc: true         # 全巻目次を載せる
    CHAPTERS:
      - 21-advanced         # 第1章
      - 22-practice         # 第2章
    APPENDICES:
      - 92-links            # 付録 A
```

章番号は、前の巻から続けて振ります。図表番号や `@chapref` の番号も同じです。各巻の最初の章番号を変えるときは、その巻に `chapter_start` を書きます。二つ以上の巻に書いた章には、それぞれの巻の中の位置で番号が付きます。

付録の記号は、各巻を順に並べたときに先に載る付録から A、B と振ります。共通の付録は、どの巻でも同じ記号です。各巻の付録を別の記号から振るときは、その巻の `appendix_start` に、始めの記号を英字一文字で書きます。ページ番号（ノンブル）は、各巻ごとに 1 から振られます。

各巻に `whole_toc: true` を書くと、その巻の目次の前に、全巻の構成を示す「全巻目次」を載せます。今の巻を濃く、ほかの巻を薄く組みます。目次を載せる深さは、その巻の目次と同じく `page.toc_depth` に従い、`2` 以上なら節まで載ります。ページ番号は載せません。

### 各巻をまたぐ参照

<!-- no-lint -->
別の巻の章や図も、同じ巻の章や図と同じ書き方で参照できます。紙面では「上巻 第8章「…」」「上巻 図 8-2」のように巻の名前を添え、リンクにはしません。`@pageref` も、ページ番号を付けずに章で示します。

## 各巻と合本の書名・表紙 @volume-book-values

`book.yml` の `book:` の下の値は、各巻の中に同じ名前で書くと、その巻だけ上書きできます。各巻に書かなかった値は `book.yml` のものを使います。合本はいつも `book.yml` の値で組みます。

** 巻ごとに上書きできる値 **

| キー | 内容 | キー | 内容 |
| :--- | :--- | :--- | :--- |
| `main_title` | 書名 | `publisher` | 発行者 |
| `subtitle` | 副題 | `contact` | 連絡先 |
| `subtitle_style` | 副題の装飾 | `author` | 著者名 |
| `series` | 連載名 | `language` | 言語 |
| `release` | 発行日 | `isbn` | ISBN |
| `cover` | 表紙のテーマ名 | | |

合本も組む本では、`book.yml` に合本の書名と表紙を書き、各巻の書名と表紙は、最初の巻のものも各巻の中に書きます。書名と表紙を書かなかった巻は、合本と同じ書名と表紙で組まれます。次の例では、各巻の原稿の並びを省いています。

```yaml:config/book.yml
book:
  main_title: "はじめての技術書づくり"    # 合本の書名
  cover: complete                      # 合本の表紙
```

```yaml:config/catalog.yml
VOLUMES:
  - name: 上巻
    id: upper
    main_title: "はじめての技術書づくり 上巻"
    cover: upper             # covers/frontcover_upper.png など
    release: "令和八年十一月一日"
    isbn: "978-4-…"
  - name: 下巻
    id: lower
    main_title: "はじめての技術書づくり 下巻"
    cover: lower             # covers/frontcover_lower.png など
    release: "令和九年一月十日"
    isbn: "978-4-…"
```

ISBN は巻ごとに書きます。`book.yml` の ISBN を二つ以上の巻が共有していると、🟡 で警告します。

### 表紙の画像を置く @volume-covers

表紙のテーマ名と画像の名前の付け方は、一冊の本と同じです（@chapref:ch-cover）。各巻の表紙には各巻の `cover` に書いたテーマを、合本の表紙には `book.yml` の `book.cover` に書いたテーマを使います。独自の画像を使うときは、各巻と合本でテーマ名を分け、それぞれの画像を `covers/` に並べます。

:::{.diagram}
```text
covers/
├── frontcover_upper.png       # 上巻（上巻に cover: upper）
├── backcover_upper.png
├── frontcover_lower.png       # 下巻（下巻に cover: lower）
├── backcover_lower.png
├── frontcover_complete.png    # 合本（book.yml に cover: complete）
└── backcover_complete.png
```
:::

`light`・`dark` には、各巻の表紙なら各巻の書名が、合本の表紙なら `book.yml` の書名が入ります。合本の表紙の画像を用意しないときは、`book.yml` を `cover: light` にすれば、合本の書名の入った表紙ができます。

表紙だけを作り直すときは、各巻の `id` を添えて `vs cover upper` のように実行します。`vs cover all` なら全巻の表紙を、`id` を添えない `vs cover` なら合本の表紙を作ります。プロジェクト直下の表紙の名前には、`mybook_upper_frontcover_v0.1.0.pdf` のように各巻の `id` が付きます。合本の表紙は `mybook_frontcover_v0.1.0.pdf` です。

## 各巻と合本を組む @build-volumes

```bash
vs build upper   # 上巻を組む（各巻の id を書く）
vs build all     # 全巻を、巻の順に一巻ずつ組む
vs build         # 全巻を一冊にまとめた合本を組む
```

<!-- no-lint -->
各巻を選んで組むと、出力ファイル名に各巻の `id` が入り（`mybook_upper_v0.1.0.pdf`）、目次の題は「上巻 目次」のように各巻の名前を添えたものになります。合本は、全巻の本文と付録を一冊にまとめて組みます。校正や、電子版の合本に使います。

各巻でも合本でも、`output.targets` に書いた形式をすべて作ります。各巻を選んで組んだときは、印刷入稿用 PDF・EPUB・Kindle 用 KPF の名前にも、各巻の `id` が入ります。

`vs build all` は、途中の巻で組版に失敗すると、そこで止まります。それまでに組んだ巻の出力は残るので、直したら `vs build lower` のように、止まった巻から組み直せます。

章を指定して組むときは、各巻の `id` を添えません（`vs build upper 11` はエラーになります）。組む巻は、指定した章から決まります。

`vs preflight upper`・`vs lint upper`・`vs metrics upper` のように、ほかのコマンドでも各巻を選べます。選ばなければ、すべての巻の原稿を対象にします。

### 各巻に原稿を追加する

`vs create 22-custom` のように番号を書くと、番号が一つ前の章を載せた巻の `CHAPTERS` に原稿を追加します。巻の境目の番号は前の巻に入ります。上巻が `12-basics` まで、下巻が `21-advanced` からなら、`vs create 20-preface-lower` は上巻に入ります。`vs create custom` のように番号を省くと、最後の巻の末尾に追加します。

各巻の前書き・後書きとして作ったときは、追加された行を、その巻の `PREFACE`・`POSTFACE` へ移します。
