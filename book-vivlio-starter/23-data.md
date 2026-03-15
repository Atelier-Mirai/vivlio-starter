# データ展開機能の使い方

:::{.chapter-lead}
原稿の中に外部データを埋め込む **QueryStream 記法** の使い方を解説します。参考書籍の一覧、都道府県データ、気象観測データなど、繰り返し登場する情報を YAML で一元管理し、テンプレートに従って自動展開できます。データファイルとテンプレートを置くだけで使えるため、設定ファイルの編集は不要です。
:::

---

## 1. 概要

Vivlio Starter のデータ展開機能は、3 つの要素で構成されています。

| 要素 | 置き場所 | 役割 |
| --- | --- | --- |
| データファイル | `data/*.yml` | 展開するデータの実体（YAML 配列） |
| テンプレート | `templates/_[名前].md` | データの表示レイアウト |
| QueryStream 記法 | `contents/*.md` の原稿内 | 展開指示（1 行で完結） |

`vs build` を実行すると、原稿内の QueryStream 記法が自動的にデータとテンプレートを使って展開されます。原稿ファイル（`contents/` 内）は書き換えられません。

---

## 2. はじめかた

### ステップ 1: データファイルを作る

`data/` ディレクトリに YAML ファイルを置きます。1 件のデータは 1 つのハッシュで、ファイル全体は配列です。

```yaml
# data/books.yml
- title: 楽しいRuby
  author: 高橋征義
  desc: Rubyを楽しく学べる入門書。
  tags: [ruby, beginner]
  cover: ruby-enjoyer.webp

- title: はじめてのC
  author: 柴田望洋
  desc: C言語の定番入門書。
  tags: [c, beginner]
```

### ステップ 2: テンプレートを作る

`templates/` ディレクトリにテンプレートファイルを置きます。ファイル名の先頭に `_`（アンダースコア）を付け、データ名の**単数形**を使います。

```markdown
<!-- templates/_book.md -->
### = title
**著者**: = author
= desc
![](cover){width=40% align=right}
```

`= title` のように `=` の後にスペースを空けてキー名を書くと、YAML の値に置き換わります。

### ステップ 3: 原稿に記法を書く

`contents/` 内の原稿ファイルに QueryStream 記法を 1 行で書きます。

```markdown
<!-- contents/05-references.md -->
# 参考書籍

= books
```

`= books` と書くだけで、`data/books.yml` の全件が `templates/_book.md` を使って展開されます。

---

## 3. QueryStream 記法

QueryStream はパイプ（`|`）で区切られた最大 5 ステージのパイプラインです。

```
= [源泉] | [抽出条件] | [並び替え] | [件数] | [スタイル]
```

各ステージは省略可能です。途中のパイプも省略でき、トークンの形式からパーサーが自動判別します。

### 3.1 源泉

データファイル名（拡張子なし）を指定します。複数形で書きます。

```markdown
= books            <!-- data/books.yml -->
= prefectures      <!-- data/prefectures.yml -->
```

単数形で書いた場合は**一件検索**の文脈になります。

```markdown
= book | 楽しいRuby   <!-- title で一件検索 -->
= prefecture | 13      <!-- code で一件検索 -->
```

一件検索では、`id` → `no` → `code` → `name` → `title` の優先順位で主キー候補を自動走査します。

### 3.2 抽出条件

`field=value` の形式で絞り込みます。

```markdown
= books | tags=ruby                       <!-- タグが ruby のもの -->
= books | tags=ruby, javascript           <!-- ruby または javascript（OR） -->
= books | tags=ruby && tags=beginner      <!-- ruby かつ beginner（AND） -->
= books | tags = ruby && beginner         <!-- 2 件目以降のフィールド省略 -->
= prefectures | region=関東, 関西          <!-- 関東 または 関西 -->
```

AND 条件は `&&` / `AND` / `and` のいずれでも書けます。カンマ区切りは同一フィールドへの OR として扱われます。

同じフィールドで AND 条件を連結するときは、最初の条件で `field=value` を書けば、2 件目以降は値だけ書いても認識されます（`tags = ruby && beginner`）。複数値の組を自然な語順で並べたいときに便利です。

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

### 3.3 ソート

フィールド名の前に `-`（降順）または `+`（昇順）を付けます。`+` は省略できます。

```markdown
= books | -title                    <!-- title の降順 -->
= weather_reports | +date           <!-- date の昇順 -->
= books | tags=ruby | -title        <!-- 絞り込み＋ソート -->
```

ソートを指定しない場合は、YAML に書いた順番（定義順）のまま出力されます。

### 3.4 件数

正の整数で件数を制限します。

```markdown
= books | 3                         <!-- 先頭 3 件 -->
= weather_reports | -date | 5       <!-- 日付降順で 5 件 -->
```

### 3.5 スタイル

`:stylename` の形式でテンプレートのバリエーションを指定します。

```markdown
= books | :full                     <!-- _book.full.md を使用 -->
= book | 楽しいRuby | :standard     <!-- _book.standard.md を使用 -->
```

スタイルを追加したい場合は、`templates/_book.my_style.md` を 1 つ作るだけで `= books | :my_style` が有効になります。

### 3.6 組み合わせ例

```markdown
<!-- 全件・デフォルトスタイル -->
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

---

## 4. テンプレートの書き方

### 基本ルール

テンプレートは Markdown ファイルです。`= key` と書くと YAML のキーの値に置き換わります。

```markdown
### = title
**著者**: = author
= desc
```

値が `nil` または空文字の場合、その行は**丸ごとスキップ**されます。著者が `nil` チェックを意識する必要はありません。

### 画像の記法

`![](key)` と書くと、YAML の値（画像ファイル名）に展開されます。

```markdown
![](cover){width=40% align=right}
```

`cover` キーの値が `ruby-enjoyer.webp` なら `![](ruby-enjoyer.webp){width=40% align=right}` に展開されます。`cover` が `nil` や空文字なら行ごとスキップされます。

`![](Einstein.png)` のように**拡張子あり**で書いた場合は、変数展開されずそのまま出力されます（リテラル扱い）。

| 記法 | 解釈 |
| --- | --- |
| `![](cover)` | 変数展開（nil なら行スキップ） |
| `![](= cover)` | 明示的な変数展開（同じ結果） |
| `![](photo.png)` | リテラル出力（そのまま） |

### テーブルスタイル

テーブル形式のテンプレートも作れます。`= key` を含む行だけが反復され、ヘッダー行や区切り行は 1 度だけ出力されます。

```markdown
<!-- templates/_book.table.md -->
| タイトル | 説明 | 著者 |
|---|---|---|
| = title | = desc | = author |
```

上記で 2 件のデータを展開すると、次のような Markdown が生成されます。

```markdown
| タイトル | 説明 | 著者 |
|---|---|---|
| 楽しいRuby | Rubyを楽しく学べる入門書。 | 高橋征義 |
| はじめてのC | C言語の定番入門書。 | 柴田望洋 |
```

### 命名規約

```
templates/
  _book.md              ← デフォルトテンプレート
  _book.full.md         ← full スタイル
  _book.table.md        ← table スタイル
  _prefecture.md        ← 都道府県用
  _weather_report.md    ← 気象データ用
```

- 先頭の `_` はパーシャル（部分テンプレート）を意味します
- データ名の**単数形**を使います（`books` → `_book`）
- スタイルはドットで区切ります（`_book.full.md`）

---

## 5. データファイルの書き方

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

複数の値を持つフィールドは、配列でもカンマ区切り文字列でも書けます。どちらも同じように扱われます。

```yaml
# 配列形式
tags: [ruby, beginner]

# カンマ区切り形式（同じ結果）
tags: ruby, beginner
```

### 日付フィールド

日付は文字列として記述してください。YAML の自動型変換を避けるため、クォートで囲むことを推奨します。

```yaml
date: "2024-01-01"
```

---

## 6. 新しいデータ種別を追加する

データ展開機能は**設定より規約**の方針で設計されています。新しいデータ種別を追加するのに必要なのは、2 つのファイルを置くだけです。

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

これだけで、設定ファイルの変更なしに新しいデータ種別が使えるようになります。

---

## 7. エラーメッセージ

QueryStream 記法に誤りがある場合、`vs build` の実行時に分かりやすいエラーメッセージが表示されます。

### テンプレートが見つからない場合

```
❌ テンプレートファイルが見つかりません(05-references.md:123)
❌   記法: = books | :fancy
❌   期待: templates/_book.fancy.md
❌   ヒント: templates/_book.md は存在します。スタイル名を確認してください。
```

### データファイルが見つからない場合

```
❌ データファイルが見つかりません(05-references.md:45)
❌   記法: = movies
❌   期待: data/movies.yml
```

### テンプレートに存在しないキーがある場合

```
❌ テンプレートに存在しないキーが記述されています(05-references.md:45)
❌   キー: publisher
❌   利用可能なキー: title, author, desc, tags, cover
```

---

## 8. ビルドパイプラインでの位置(開発者向け)

QueryStream の展開は `vs build` の前処理パイプラインで、フロントマター生成の直後に実行されます。展開された Markdown（画像記法など）は、後続の画像パス正規化やリンク脚注化で正しく処理されます。

```
① フロントマター生成
② HTML コメント除去
③ QueryStream 展開 ← ここ
④ 画像パス正規化
⑤ コードインクルード展開
⑥ 以降の変換処理…
```

原稿ファイル（`contents/` 内）は一切変更されません。展開結果はプロジェクトルート直下に書き出され、後段の処理へ渡されます。

---

:::{.column}
**ヒント**
データファイルやテンプレートを追加・変更したら、`vs build` を実行するだけで展開結果に反映されます。原稿ファイルの QueryStream 記法はそのまま保持されるため、データの修正やテンプレートのデザイン変更を気軽に試すことができます。
:::
