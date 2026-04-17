# 拡張記法リファレンス

:::{.chapter-lead}
Vivlio Starter では、標準 Markdown に加えて、技術書制作に特化した独自の拡張記法を利用できます。本章では、コラム・注記・レイアウト・表など、よく使う拡張コンテナを一覧で解説します。いずれも `:::` で囲むだけで使えます。
:::

## 拡張記法の基本

Vivlio Starter の拡張記法は、VFM（Vivliostyle Flavored Markdown）のカスタムコンテナ構文を使います。

```markdown
:::{.クラス名}
ここに内容を書く
:::
```

`:::` の開始行にクラス名を指定するだけで、対応するスタイルが自動的に適用されます。

## リード文

### `.chapter-lead` — 章リード

章の冒頭に配置する導入文です。本文より大きめのフォントで表示され、章の内容を簡潔に紹介します。

```markdown
:::{.chapter-lead}
本章では〇〇について解説します。
:::
```

### `.section-lead` — 節リード

節（h2）の直後に配置する短い導入文です。節の内容を一言で補足したいときに使います。

```markdown
## インストール

:::{.section-lead}
3ステップで完了します。
:::
```

## 注記・補足

### `.column` — コラム

本文の補足情報や豆知識を枠で囲んで表示します。丸ゴシック体で表示され、本文と視覚的に区別されます。

```markdown
:::{.column}
##### コラムタイトル

ここにコラムの内容を書きます。
:::
```

### `.tip` — Tip

読者へのヒントや便利な情報を表示します。薄い背景色で囲まれます。

```markdown
:::{.tip}
`vs preflight` を使うと、ビルド前にエラーを素早く確認できます。
:::
```

### `.note` — Note

補足説明や注意事項を上下の罫線で区切って表示します。

```markdown
:::{.note}
この設定は `book.yml` の `theme` セクションで変更できます。
:::
```

### `.notice` — Notice

重要な注意事項を左側のアクセントラインで強調して表示します。

```markdown
:::{.notice}
`--force` オプションは既存ファイルを上書きします。実行前にバックアップを取ってください。
:::
```

## 書籍紹介カード

### `.book-card` — 参考書籍カード

参考文献や推薦書籍をカード形式で表示します。左に表紙画像、右に書籍情報を並べます。

```markdown
:::{.book-card}
![](images/ruby.webp)
**Ruby入門**
初心者でも楽しみながらプログラミングを学べる一冊。
:::
```

## 画像レイアウト

### 画像単体の属性指定（width / align）

標準の画像記法に `{}` で属性を付けると、サイズと配置を制御できます。

```markdown
![](image.png){width=30% align=left}
![](image.png){width=50% align=center}
![](image.png){width=70% align=right}

# サイズのみ指定
![](image.png){width=50%}

# 配置のみ指定
![](image.png){align=right}

# 標準の画像（拡張なし）
![代替テキスト](画像パス)
```

### `.pictures` — 写真グリッド

複数の画像をグリッド状に並べます。画像数に応じて列数が自動調整されます。

```markdown
:::{.pictures}
![alt](images/a.webp)
![alt](images/b.webp)
![alt](images/c.webp)
:::
```

### `.image-group` — 2枚横並び

2枚の画像を横に並べます。最初の画像に `{width=30%}` を指定すると比率を調整できます。

```markdown
:::{.image-group}
![before](images/before.webp){width=40%}
![after](images/after.webp)
:::
```

### `.img-text` / `.text-img` — 画像＋本文の横並び

画像と本文を横に並べます。列幅のバリエーションがあります。

| クラス名 | 配置 | 列比率 |
|---|---|---|
| `.img-text` | 左:画像 / 右:本文 | 1:1 |
| `.img-text2` | 左:画像 / 右:本文 | 1:2 |
| `.img-text3` | 左:画像 / 右:本文 | 1:3 |
| `.text-img` | 左:本文 / 右:画像 | 1:1 |
| `.text2-img` | 左:本文 / 右:画像 | 2:1 |
| `.text3-img` | 左:本文 / 右:画像 | 3:1 |

```markdown
:::{.img-text2}
![](images/screenshot.webp)

ここに説明文を書きます。画像の右側に表示されます。
:::
```

### `.sideimage-right` / `.sideimage-left` — サイドイメージ

本文の横に画像を配置します。`figure` タグを使った回り込みレイアウトです。

```markdown
:::{.sideimage-right}
説明文がここに入ります。画像の左側に表示されます。

![](images/sample.webp)
:::
```

### 余白の調整（`.gap-s` / `.gap-m` / `.gap-l`）

`.img-text` などのレイアウトクラスに、余白調整クラスを併記できます。

```markdown
:::{.img-text .gap-s}
![画像説明](image.png)

小さな余白（0.5rem）で配置
:::

:::{.img-text .gap-m}
![画像説明](image.png)

標準の余白（1rem）で配置
:::

:::{.img-text .gap-l}
![画像説明](image.png)

大きな余白（1.5rem）で配置
:::
```

## 段組

### `.two-col` — 2段組

内容を2列に分けて表示します。用語集や短い項目の一覧に便利です。

```markdown
:::{.two-col}
- 項目A
- 項目B
- 項目C
- 項目D
:::
```

### `.text-2dan` — 二段組テキスト

長いテキストを雑誌風の二段組で表示します。`column-count: 2` / `column-gap: 1.2em` で設定されます。

```markdown
:::{.text-2dan}
これは二段組で表示されるテキストです。長い文章を効率的に配置でき、雑誌のようなレイアウトを実現できます。

各要素は break-inside: avoid で段をまたいで分割されるのを防ぎます。
:::
```

## 表のレイアウト

### `.long-table` — 長い表

行数の多い表に適用します。フォントサイズが少し小さくなり、セルが詰まって表示されます。

```markdown
:::{.long-table}
| 列1 | 列2 | 列3 |
|---|---|---|
| ... | ... | ... |
:::
```

### `.table-scroll` — 横スクロール表

列数が多く横幅が広い表に適用します。HTML プレビュー時に横スクロールが有効になります（PDF では折り返し）。

```markdown
:::{.table-scroll}
| 列1 | 列2 | 列3 | 列4 | 列5 | 列6 |
|---|---|---|---|---|---|
| ... | ... | ... | ... | ... | ... |
:::
```

### `.table-rotate` — 表を90度回転

横幅が非常に広い表を、専用ページで90度回転して表示します。前後に自動的に改ページが入ります。

```markdown
:::{.table-rotate}
| 列1 | 列2 | 列3 | ... |
|---|---|---|---|
| ... | ... | ... | ... |
:::
```

## テキストの配置

### `.align-left` / `.align-center` / `.align-right` — 寄せ

ブロック単位でテキストを寄せて表示します。

```markdown
:::{.align-left}
左寄せで表示されるテキストブロックです。
:::

:::{.align-center}
中央寄せで表示されるテキストブロックです。
:::

:::{.align-right}
右寄せで表示されるテキストブロックです。
:::
```

## 参照・インクルード

### 相互参照（クロスリファレンス）

図・表・コードブロックにラベルを付け、本文中から参照できます。

#### 定義側

````markdown
**サンプルコード @sample-code**
```ruby
def hello(name)
  puts "Hello, #{name}!"
end
```

**データテーブル @data-table**
| 項目 | 値 |
|------|-----|
| A | 100 |
| B | 200 |
````

#### 参照側

```markdown
@sample-code のコードを参照してください。
@data-table にデータをまとめました。
```

### コードインクルード

外部ファイルからコードを読み込みます。

````markdown
ファイル全体:
```include:sample.rb```

範囲指定:
```include:sample.rb:10-20```

言語指定:
```include:sample.rb:ruby```
````

## 索引・用語集

Vivlio Starter では、索引と用語集を自動生成する機能があります。

### 手動マークアップ

原稿中で索引や用語集に登録したい単語を明示的に指定します。

```markdown
[Ruby|るびー]は[まつもとゆきひろ|松本幸弘]氏によって開発されました。
[Vivliostyle|びぶりおすたいる]は電子書籍出版のためのフレームワークです。
```

- `[用語|読み]` — 用語と読み（ひらがな）を指定
- `[用語]` — 用語のみ（読みは MeCab で自動推測）

:::{.note}
**注意**: 索引・用語集の記法は `{}` ではなく `[]` を使用します。ルビ記法 `{単語|読み}` と混同しないでください。
:::

### 自動抽出とレビュー

`vs index:auto` コマンドで、原稿から索引候補を自動的に抽出できます。

```bash
# 1. 索引候補の自動抽出
vs index:auto

# 2. レビューファイルの編集
# _index_glossary_review.md を開いて [i]=索引, [g]=用語集, [ig]=両方, [r]=棄却

# 3. レビュー結果の適用
vs index:apply

# 4. PDF生成（索引ページを含む）
vs build
```

## ルビ（振り仮名）

日本語の読み仮名をルビとして指定できます。

```markdown
{相対性理論|そうたいせいりろん}は、{Albert Einstein|アルバート・アインシュタイン}が1905年に発表しました。
{光電効果|こうでんこうか}の研究でノーベル賞を受賞しています。
```

## 定義リスト

用語とその説明を箇条書き形式で記述します。

```markdown
- **用語1**
    用語1の説明

- **用語2**
    用語2の説明

- **Ruby**
    まつもとゆきひろが開発したプログラミング言語です。
    動的型付けとオブジェクト指向の特徴を持っています。
```

**記述のポイント:**

- 用語は太字（`**用語**`）で記述
- 説明は4スペースでインデント
- 説明が複数行になる場合は、すべての行をインデント

## データ展開（QueryStream）

`data/` ディレクトリの YAML ファイルからデータを展開できます。

```markdown
# 全件展開
= books

# 条件付き展開
= books | tags=ruby | -title | 3

# 一件検索
= book | 楽しいRuby

# スタイル指定
= books | :full
```

**QueryStream 記法の構成:**

```
= [源泉] | [抽出条件] | [並び替え] | [件数] | [スタイル]
```

- **源泉**: データファイル名（例: `books`, `prefectures`）
- **抽出条件**: `field=value`, `field=value1,value2`, `field=value1 && value2`
- **並び替え**: `-field`（降順）, `+field`（昇順）
- **件数**: 正の整数で制限
- **スタイル**: `:stylename` でテンプレート指定

## 余白・改ページ

拡張コンテナではありませんが、よく使うユーティリティです。

### `.aki` / `.aki2` — 段落後の余白

段落の末尾にクラスを付けると、その段落の下に余白を追加します。図や表の前後など、少し間を空けたいときに使います。

```markdown
ここで少し間を空けたい。 {.aki}

次の段落はここから始まります。
```

| クラス名 | 余白量 |
|---|---|
| `.aki` | 本文1行分 |
| `.aki2` | 本文2行分 |

### 改ページ・空行

```markdown
<!-- 改ページ -->
---{.pagebreak}

<!-- 空行（1行分の余白） -->
---{.blankline}
```

## クラスの組み合わせ

複数のクラスを組み合わせることもできます。

```markdown
:::{.column .align-center}
##### 中央寄せのコラム

内容がここに入ります。
:::
```

## 実践的な記述例

### 技術的な章の構成

````markdown
# API リファレンス

:::{.chapter-lead}
本章では、システムの主要な API について解説します。基本的な使い方から応用的な活用方法までを網羅します。
:::

## 基本的な使い方

まず、最もシンプルな例から見ていきましょう。

**基本的なリクエスト @basic-request**
```javascript
const response = await fetch('/api/data');
const data = await response.json();
console.log(data);
```

@basic-request のコードは、API からデータを取得する基本的なパターンです。

## 応用的な使い方

### エラーハンドリング

**エラーハンドリング例 @error-handling**
```javascript
try {
  const response = await fetch('/api/data');
  if (!response.ok) {
    throw new Error(`HTTP error! status: ${response.status}`);
  }
  const data = await response.json();
} catch (error) {
  console.error('API request failed:', error);
}
```

@error-handling では、ネットワークエラーや HTTP エラーに対応しています。

### パラメータ指定

**パラメータ指定の例 @with-params**
```javascript
const params = new URLSearchParams({
  page: 1,
  limit: 20,
  sort: 'date'
});

const response = await fetch(`/api/data?${params}`);
```

@with-params のように、URL パラメータを指定できます。

## API 一覧

**主要なエンドポイント @api-endpoints**
| エンドポイント | メソッド | 説明 |
|-------------|----------|------|
| /api/data | GET | データ一覧取得 |
| /api/data/:id | GET | 個別データ取得 |
| /api/data | POST | データ作成 |
| /api/data/:id | PUT | データ更新 |
| /api/data/:id | DELETE | データ削除 |

@api-endpoints のように、RESTful な設計になっています。
````
