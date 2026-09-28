# データ展開機能

:::{.chapter-lead}
参考書籍の一覧や各地の観測値のように、同じ形の情報が並ぶページを本文へ直接書くと、項目を追加するたびに書式まで繰り返すことになります。**QueryStream 記法**は、内容を YAML のデータへ、見せ方を Markdown のテンプレートへ分け、必要な項目を原稿へ展開する仕組みです。本章では、最小の例から、絞り込み・並べ替え・表示形式の切り替えへ進みます。データファイルとテンプレートを置けば利用でき、設定ファイルの編集は必要ありません。
:::

## 概要

QueryStream は、データ・テンプレート・原稿内の展開指示という三つの要素で構成されます。それぞれに役割を分けることで、情報を更新する作業と、紙面の見せ方を整える作業を独立して行えます。

| 要素 | 置き場所 | 役割 |
| --- | --- | --- |
| データファイル | `data/*.yml` | 展開するデータの実体（YAML 配列） |
| テンプレート | `templates/_[名前].md` | データの表示レイアウト |
| QueryStream 記法 | `contents/*.md` の原稿内 | 展開指示（1 行で完結） |

`vs build` を実行すると、原稿内の QueryStream 記法を起点に、対応するデータとテンプレートが読み込まれます。展開後の Markdown はビルド処理の中で生成され、`contents/` の原稿自体は書き換えられません。原稿には「どのデータを出すか」という短い指示だけが残ります。

## はじめかた

### ステップ 1: データファイルを作る

最初に、内容を記録する YAML ファイルを `data/` ディレクトリへ置きます。一件分のデータを一つのハッシュで表し、それらを配列として並べます。各項目で同じキーを使うと、後のテンプレートから共通の名前で値を取り出せます。

```yaml
# data/books.yml
- title: 楽しいRuby
  author: 高橋征義
  desc: Rubyを楽しく学べる入門書。
  tags: [ruby, beginner]
  cover: ruby-enjoyer.webp

- title: はじめてのC
  author: 椋田 實
  desc: C言語の定番入門書。
  tags: [c, beginner]
```

### ステップ 2: テンプレートを作る

次に、一件分をどのように表示するかを Markdown のテンプレートへ記述します。ファイルは `templates/` ディレクトリへ置き、名前の先頭に `_`（アンダースコア）、続いてデータ名の**単数形**を使います。

```markdown
<!-- templates/_book.md -->
### = title
**著者**: = author
= desc
![](cover){width=40% align=right}
```

テンプレート内で `= title` のように、`=` と空白に続けてキー名を書くと、その位置が各データの値へ置き換わります。周囲は通常の Markdown なので、見出し・太字・画像など、前章までの記法と組み合わせられます。

### ステップ 3: 原稿に記法を書く

最後に、`contents/` の原稿へ QueryStream 記法を一行で書きます。この一行が、使うデータとテンプレートを結びます。

```markdown
<!-- contents/05-references.md -->
# 参考書籍

= books
```

`= books` は、`data/books.yml` の全件を読み、`templates/_book.md` で一件ずつ整形する指示です。データ名の複数形 `books` から、対応する単数形のテンプレート `_book.md` が選ばれます。

### 実際の展開例

三つの要素を、書籍紹介の例でつないでみます。`data/books.yml` には Ruby と C の入門書を用意し、各項目に `title`・`author.name`・`desc`・`cover` を持たせます。

```yaml
# data/books.yml（抜粋）
- title: 楽しいRuby
  author:
    name: 高橋征義
  desc: Rubyを楽しく学べる入門書。
  cover: joyful_ruby.webp

- title: はじめてのC
  author:
    name: 椋田 實
  desc: C言語の定番入門書。
  cover: first_c.webp
```

一件分の見せ方は、データ名の単数形に先頭の `_` を付けた `templates/_book.md` で定義します。ここでは、前章の `.book-card` と組み合わせます。

```markdown
<!-- templates/_book.md -->
:::{.book-card}
![](cover)
**= title**
= author.name 著
= desc
:::
```

原稿側には、書籍データを展開したい位置へ `= books` と書きます。

```markdown
= books
```

ビルドすると、YAML の各項目が同じテンプレートへ順に入り、次のように出力されます。データを増やせばカードも増え、テンプレートを直せば全件の見た目が揃って変わります。{.aki}

= books

## QueryStream 記法

全件をそのまま出すだけでなく、条件に合うデータを選び、順番や件数、見せ方を指定できます。QueryStream は、パイプ `|` で区切る最大五つのステージを左から順に処理します。

```
= [源泉] | [抽出条件] | [並び替え] | [件数] | [スタイル]
```

源泉以外のステージは省略できます。各指定は書式から種類が判別されるため、使わないステージのために空のパイプを残す必要もありません。短い指示は短いまま書き、条件が増えたときだけ右へつないでいけます。

### 源泉

最初のステージでは、読み込むデータファイルを拡張子なしで指定します。複数件を対象にするときは、データ名を複数形で書きます。

```markdown
= books            <!-- data/books.yml -->
= prefectures      <!-- data/prefectures.yml -->
```

データ名を単数形にすると、一覧ではなく**一件を探す指示**として解釈されます。

```markdown
= book | 楽しいRuby   <!-- title で一件検索 -->
= prefecture | 13      <!-- code で一件検索 -->
```

一件検索では、`id` → `no` → `code` → `name` → `title` の順に、検索に使える主キーの候補を調べます。データの種類ごとに検索キーを設定しなくても、一般的なキー名から対象を特定できます。

### 抽出条件

`field=value` の形式で絞り込みます。

```markdown
= books | tags=ruby                       <!-- タグが ruby のもの -->
= books | tags=ruby, javascript           <!-- ruby または javascript（OR） -->
= books | tags=ruby && tags=beginner      <!-- ruby かつ beginner（AND） -->
= books | tags = ruby && beginner         <!-- 2 件目以降のフィールド省略 -->
= prefectures | region=関東, 関西          <!-- 関東 または 関西 -->
```

AND 条件は `&&` / `AND` / `and` のいずれでも書けます。カンマ区切りは同一フィールドへの OR として扱われます。

同じフィールドへ AND 条件を続ける場合は、最初に `field=value` を書けば、二件目以降のフィールド名を省略できます。`tags = ruby && beginner` は、`tags` に `ruby` と `beginner` の両方を含むデータを選びます。

**比較演算子**も使えます。

| 演算子 | 意味 | 例 |
| --- | --- | --- |
| `=` / `==` | 等しい | `region=関東` |
| `!=` | 等しくない | `category!=nonmetal` |
| `>` / `>=` / `<` / `<=` | 比較 | `temp_min_c>=20` |
| `field=20..25` | 20 以上 25 以下 | `atomic_number=1..6` |
| `field=20...25` | 20 以上 25 未満 | `temp_min_c=20...25` |
| `field=20..` | 20 以上 | `population=9000000..` |
| `field=..25` | 25 以下 | `atomic_number=..3` |

### ソート

並べ替えに使うフィールド名の前へ、降順なら `-`、昇順なら `+` を付けます。検索条件と区別するため、**符号は省略できません**。

```markdown
= books | -title                    <!-- title の降順 -->
= weather_reports | +date           <!-- date の昇順 -->
= books | tags=ruby | -title        <!-- 絞り込み＋ソート -->
```

符号のない `= books | title` はソートではなく、**主キーを `title` という値で検索する指示**として扱われます。`= book | 楽しいRuby` と同じ形の記述を区別する基準が、先頭の符号だからです。この例では該当する本がないため、🟡 の警告が表示され、データは展開されません。

ソートを指定しない場合は、YAML に書いた順番（定義順）のまま出力されます。

### 件数

正の整数で件数を制限します。

```markdown
= books | 3                         <!-- 先頭 3 件 -->
= weather_reports | -date | 5       <!-- 日付降順で 5 件 -->
```

### スタイル

同じデータを別のレイアウトで見せたいときは、`:stylename` の形式でテンプレートのバリエーションを指定します。全件一覧は表、個別紹介はカードというように、データを複製せず表示だけを切り替えられます。

```markdown
= books | :full                     <!-- _book.full.md を使用 -->
= book | 楽しいRuby | :standard     <!-- _book.standard.md を使用 -->
```

新しいスタイルは、`templates/_book.my_style.md` のようなテンプレートを追加すると利用できます。原稿側では `= books | :my_style` と指定し、設定ファイルへの登録は行いません。

### 組み合わせ例

```markdown
<!-- 全件・既定のスタイル -->
= books

<!-- タグ絞り込み＋fullスタイル -->
= books | tags=ruby | :full

<!-- 一件検索＋スタイル -->
= book | 楽しいRuby | :standard

<!-- 複合条件＋ソート＋件数＋スタイル -->
= weather_reports | condition=晴, 曇 and temp_min_c>=20 | -date | 5 | :full

<!-- 都道府県のOR絞り込み -->
= prefectures | region=関東, 関西

<!-- 元素のAND絞り込み -->
= elements | category=nonmetal AND phase_at_stp=gas | :full
```

## テンプレートの書き方

### 基本ルール

テンプレートも通常の Markdown ファイルです。文章や装飾はそのまま出力され、`= key` と書いた箇所だけが YAML の値へ置き換わります。

```markdown
### = title
**著者**: = author
= desc
```

著者名（`author`）などの値が設定されていない項目では、そのキーを含む行が省略されます。値のない項目のために空行や「著者:」だけが残らないので、同じテンプレートを情報量の異なるデータへ使えます。

### 画像の記法

画像の位置に `![](key)` と書くと、括弧内のキーが YAML に記録された画像ファイル名へ展開されます。

```markdown
![](cover){width=40% align=right}
```

`cover` キーの値が `ruby-enjoyer.webp` なら `![](ruby-enjoyer.webp){width=40% align=right}` に展開されます。`cover` が `nil` や空文字列なら行ごとスキップされます。

`![](Einstein.png)` のように**拡張子あり**で書いた場合は、変数展開されずそのまま出力されます（リテラル扱い）。

| 記法 | 解釈 |
| --- | --- |
| `![](cover)` | 変数展開（nil なら行スキップ） |
| `![](= cover)` | 明示的な変数展開（同じ結果） |
| `![](photo.png)` | リテラル出力（そのまま） |

:::{.notice}
**画像ファイルの置き場所**：`cover:` などで指定した画像ファイル（例: `joyful_ruby.webp`）は、次のいずれかに置けます。ビルド時にこの順で探索され、最初に見つかった場所が使われます。

1. `images/<章スラッグ>/` — その QueryStream 記法を書く章の画像ディレクトリ（従来どおり。章ごとに差し替えたいとき）
2. `data/<データ名>/` — データファイルと同名のフォルダ（例: `data/books.yml` なら `data/books/`）。データ専用の画像はここに置くとデータ一式が自己完結します
3. `data/images/` — 複数のデータで共有する画像の置き場

`data/` に置いた画像は、`.webp` / `.png` / `.jpg` の拡張子違いも自動で解決されます（`.webp` を優先）。詳しい使い分けは `data/_README.md` を参照してください。
:::

### テーブルスタイル

複数件を比較する場合は、テーブル形式のテンプレートも使えます。`= key` を含むデータ行だけが件数分繰り返され、ヘッダーと区切り行は一度だけ出力されます。

```markdown
<!-- templates/_book.table.md -->
| タイトル | 説明   | 著者     |
| -------- | ------ | -------- |
| = title  | = desc | = author |
```

このテンプレートで二件のデータを展開すると、ビルド処理の中では次の Markdown が生成されます。

```markdown
| タイトル    | 説明                       | 著者     |
| ----------- | -------------------------- | -------- |
| 楽しいRuby  | Rubyを楽しく学べる入門書。 | 高橋征義 |
| はじめてのC | C言語の定番入門書。        | 椋田 實  |
```

### 命名規約

```
templates/
  _book.md              ← 既定のテンプレート
  _book.full.md         ← full スタイル
  _book.table.md        ← table スタイル
  _prefecture.md        ← 都道府県用
  _weather_report.md    ← 気象データ用
```

- 先頭の `_` はパーシャル（部分テンプレート）を意味します
- データ名の**単数形**を使います（`books` → `_book`）
- スタイルはドットで区切ります（`_book.full.md`）

QueryStream は、データ名の英語の複数形を単数形へ変換し、対応するテンプレート名を決めます。`books` → `_book.md` の基本形に加え、末尾に数字やアンダースコアを含む名前でも、複数形の部分だけが変換されます。次の対応から、用意するファイル名を確認できます。

| データファイル | 探索されるテンプレート | 備考 |
| --- | --- | --- |
| `data/books.yml` | `templates/_book.md` | `books` → `book` に自動変換 |
| `data/books2.yml` | `templates/_book2.md` | 末尾の `s` までを単数化し、接尾辞を維持 |
| `data/books_nested.yml` | `templates/_book_nested.md` | `_book_nested.*` 系を用意する |
| `data/books_nested.yml` + `:table` | `templates/_book_nested.table.md` | スタイルを付ける場合 |

## データファイルの書き方

### 基本構造

`data/` ディレクトリに YAML ファイルを置きます。ファイル名がそのままデータ名になります。

```yaml
# data/prefectures.yml
- name: 北海道
  capital: 札幌市
  region: 北海道
  code: 1
  population: 5224614

- name: 東京都
  capital: 新宿区
  region: 関東
  code: 13
  population: 14047594
```

### 複数値フィールド

タグのように複数の値を持つフィールドは、YAML の配列でも、カンマ区切りの文字列でも記述できます。QueryStream では、どちらも複数値として同じように扱われます。

```yaml
# 配列形式
tags: [ruby, beginner]

# カンマ区切り形式（同じ結果）
tags: ruby, beginner
```

### ネスト構造のフィールド

人物の名前と経歴のように、互いに関連する値はネストしたハッシュへまとめられます。テンプレートからは `author.name` のようなドット記法で子要素へアクセスできるため、データのまとまりを保ったまま必要な値を取り出せます。

```yaml
# data/nesteds.yml
- title: 楽しいRuby
  author:
    name: 高橋征義
    bio: Rubyist。
  desc: Rubyを楽しく学べる入門書。
  cover: ruby.webp

- title: はじめてのC
  author:
    name: 椋田 實
    bio: C プログラマ
  desc: C言語の定番入門書。
  cover: c.webp
```

テンプレート側では `= author.name` / `= author.bio` のように書くだけで、各階層の値を展開できます。画像記法も同じ仕組みで、`![](author.avatar)` のようにドット記法へ対応しています。

### 日付フィールド

日付は `2024-01-01` のようにクォートなしで書いても、`"2024-01-01"` のようにクォート付きで書いても問題ありません。内部ではどちらも日付型に正規化され、等値性や大小比較に利用されます。ドキュメントの可読性を優先して、必要に応じてクォートを付けてください。

```yaml
date: 2024-01-01
date: "2024-01-01"  # どちらでも可
```

## 新しいデータ種別を追加する

QueryStream は、設定へ種類を登録する代わりに、ファイル名の対応からデータとテンプレートを結びます。新しいデータ種別にも、データファイルと単数形のテンプレートを一つずつ用意すれば対応できます。

### 例: 元素データを追加する

**1. データファイルを作成**

```yaml
# data/elements.yml
- symbol: H
  name: 水素
  atomic_number: 1
  atomic_mass: 1.008
  category: nonmetal

- symbol: He
  name: ヘリウム
  atomic_number: 2
  atomic_mass: 4.0026
  category: noble_gas
```

**2. テンプレートを作成**

```markdown
<!-- templates/_element.md -->
### = name（= symbol）
**原子番号**: = atomic_number
**原子量**: = atomic_mass
```

**3. 原稿で使う**

```markdown
= elements                                 <!-- 全件 -->
= elements | category=nonmetal             <!-- 非金属のみ -->
= element | 水素                            <!-- 一件検索 -->
= elements | atomic_number=1..10 | :full   <!-- 範囲＋スタイル -->
```

原稿へ展開指示を書けば、設定ファイルを変更せずに元素データを利用できます。同じ手順で、人物・製品・年表など、その本で繰り返し扱う情報を追加できます。

## エラーメッセージ

データ名やスタイル名に誤りがある場合は、`vs build` の実行時に、探したファイルの場所を含むエラーメッセージが表示されます。記法・データ・テンプレートのどこを確認すればよいかを、メッセージからたどれます。

### 雛形ファイルが見つからない場合

```
🔴 05-references.md:123 - 雛形ファイル '_book.fancy.md' が見つかりません（記法: = books | :fancy）
        雛形の場所: templates/_book.fancy.md
        ヒント: templates/_book.md は存在します。スタイル名を確認してください。
```

スタイル名のタイプミスか、テンプレートファイルの配置忘れを確認してください。

### データファイルが見つからない場合

```
🔴 05-references.md:45 - データファイルが見つかりません（記法: = movies）
        データの場所: data/movies.yml
```

データファイル名のタイプミスか、`data/` ディレクトリへの配置忘れを確認してください。

:::{.column}
**ヒント**
データファイルやテンプレートへの変更は、次の `vs build` で展開結果に反映されます。原稿には QueryStream の指示が残るため、情報を直すときはデータへ、全件の見せ方を変えるときはテンプレートへ手を入れます。掲載件数が増えても、本文を一件ずつ探して直す作業は増えません。
:::
