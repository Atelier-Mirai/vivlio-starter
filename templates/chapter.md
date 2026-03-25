# 章タイトル

::: {.chapter-lead}
各章の冒頭に置かれる短い導入文を記述します。この章で扱うテーマや内容の概要を読者に伝えつつ、学びへの期待やワクワク感を高めてください。身近なエピソードや歴史的背景を差し込むと読者が引き込まれます。
:::

ここに本文を記述します。**太字**、*斜体*、***太字+斜体***、~~取り消し線~~、`インラインコード`

バッククォート自身を含む場合: `` ` ``

エスケープ: \*アスタリスク\*、\`バッククォート\`、\# ハッシュ

振り仮名（ルビ）: {相対性理論|そうたいせいりろん}

脚注: 本文中に脚注を付けます[^1]。インライン脚注も使えます^[これはインライン脚注です。]。

[^1]: 脚注の内容をここに記述します。

改行: 1行目<br>
2行目

水平線:

---

## セクション見出し {#section-id}

::: {.section-lead}
章の中の各セクション（節）の冒頭に置かれる導入文を記述します。セクションで扱うトピックの簡潔な紹介と、読者の興味を引きつける導入部を記述してください。
:::

### リスト

箇条書き:

- 項目1
- 項目2
  - 子項目1
  - 子項目2

番号付き:

1. 最初の項目
2. 2番目の項目
   1. 子項目1
   2. 子項目2

### 引用ブロック

> 引用文をここに記述します。

> **引用元**: 著者名
>
> 複数段落の引用も可能です。

> 入れ子の引用
>> 2レベル目の引用

### 表（テーブル）

| 左揃え | 中央揃え | 右揃え |
| :--- | :---: | ---: |
| テキスト | テキスト | 123 |
| テキスト | テキスト | 456 |

::: {.long-table}
| 縦に長い表 | 説明 |
| :--- | :--- |
| 項目1 | 説明1 |
| 項目2 | 説明2 |
:::

---

## コードブロック

### キャプションなし

```ruby
def greet(name)
  "こんにちは、#{name}さん!"
end

puts greet('読者')
```

### キャプション付き（コロン形式）

```ruby:hello.rb
def greet(name)
  "こんにちは、#{name}さん!"
end
```

### キャプション付き（title= 形式）

```ruby title=hello.rb
def greet(name)
  "こんにちは、#{name}さん!"
end
```

### ソースコードの読み込み

```include:sample.rb```

### ソースコードの読み込み（範囲指定）

```include:sample.rb:10-20```

### 入れ子コードブロック（チルダ）

~~~markdown
```ruby
def greet(name)
  puts "Hello, #{name}!"
end
```
~~~

### 入れ子コードブロック（バッククォート4つ）

````markdown
```ruby
def greet(name)
  puts "Hello, #{name}!"
end
```
````

---

## 数式

インライン数式: $E = mc^2$

ディスプレイ数式:

$$
\gamma = \frac{1}{\sqrt{1 - \dfrac{v^2}{c^2}}}
$$

---

## 画像

標準:

![画像の説明](image.png)

幅・配置指定:

![](image.png){width=50%}

![](image.png){width=40% align=right}

![](image.png){width=40% .align-right}

---

## VFM 拡張記法

### セクション化（カスタムID・クラス）

```markdown
# 見出し {#my-id}

# 見出し {.my-class}

## Not Sectionize {.just-a-heading} ##
```

### Frontmatter

```markdown
---
title: 'タイトル'
author: '著者名'
vfm:
  hardLineBreaks: true
  math: true
---
```

### 画像のキャプション（単独行）

![Figure 1](fig1.png)

![Figure 2](fig2.png "Figure 2"){id="fig2" data-sample="sample"}

---

## Vivlio Starter 拡張記法

### テキスト配置

::: {.align-left}
左寄せテキスト
:::

::: {.align-center}
中央寄せテキスト
:::

::: {.align-right}
右寄せテキスト
:::

### コラム

::: {.column}
**💡 コラム見出し**

コラムの本文をここに記述します。補足情報や豆知識を表示するのに便利です。
:::

### 注意書き

::: {.note}
**注意**: 注意事項をここに記述します。
:::

### 画像とテキストの横並び

::: {.img-text}
![画像説明](image.png)
画像の右側に配置されるテキストです。等幅で2分割されます。
:::

::: {.img-text2}
![画像説明](image.png)
テキスト側が2倍の幅になります。
:::

::: {.img-text3}
![画像説明](image.png)
テキスト側が3倍の幅になります。
:::

### テキストと画像の逆配置

::: {.text-img}
テキストが左側に配置されます。
![画像説明](image.png)
:::

::: {.text2-img}
テキスト側が2倍の幅になります。
![画像説明](image.png)
:::

::: {.text3-img}
テキスト側が3倍の幅になります。
![画像説明](image.png)
:::

### 余白の調整

::: {.img-text .gap-s}
![](image.png)
小さな余白（0.5rem）
:::

::: {.img-text .gap-m}
![](image.png)
標準の余白（1rem）
:::

::: {.img-text .gap-l}
![](image.png)
大きな余白（1.5rem）
:::

### サイドイメージ

::: {.sideimage-right}
![画像説明](image.png)
画像の左側にテキストが回り込みます。
:::

::: {.sideimage-left}
![画像説明](image.png)
画像の右側にテキストが回り込みます。
:::

### 写真タイル配置

::: {.pictures}
![説明1](image1.png)
![説明2](image2.png)
:::

::: {.pictures}
![説明1](image1.png)
![説明2](image2.png)
![説明3](image3.png)
:::

### 二段組

::: {.text-2dan}
二段組で表示されるテキストです。長い文章や箇条書きを紙面効率よく配置できます。

- 項目1
- 項目2
- 項目3
:::

### 右寄せ

::: {.text-right}
**右寄せのテキスト**
:::

---

## 相互参照（クロスリファレンス）

### 定義側

**サンプルコード @sample-code**
```ruby
def hello(name)
  puts "Hello, #{name}!"
end
```

**データ表 @data-table**
| 項目 | 値 |
| :--- | ---: |
| A | 100 |
| B | 200 |

**図の定義 @sample-fig**
![サンプル図](image.png)

**自動ID @auto**
```ruby
puts "自動IDのサンプル"
```

### 参照側

```markdown
@sample-code のコードを参照してください。
@data-table にデータをまとめました。
@sample-fig のイメージを確認してください。
```

---

## 索引・用語集

```markdown
[用語|読み]を本文中に記述します。
[相対性理論|そうたいせいりろん]
[Ruby|るびー]
```

::: {.note}
**注意**: 索引・用語集の記法は `[]` を使います。ルビ記法 `{単語|読み}` と混同しないでください。
:::

---

## QueryStream（データ展開）

```markdown
= books                    # 全件展開
= books | tags=ruby        # タグで絞り込み
= books | -year | 3        # 年度降順・3件
= book  | タイトル名       # 一件検索
= books | :full            # fullスタイルで展開
```

`data/books.yml` の例:

```yaml
- title: 書籍タイトル
  author:
    name: 著者名
  desc: 書籍の説明文。
  cover: cover.webp
  tags: [ruby, programming]
  year: 2024
```

`templates/_book.md` の例:

```markdown
::: {.book-card}
![](cover)
**=title**
=author.name 著（=year年）
=desc
:::
```

---

## リンク

インラインリンク: [リンクテキスト](https://example.com)

参照リンク: [リンクテキスト][ref]

[ref]: https://example.com

自動リンク: <https://example.com>

---

## 生のHTML

<div class="custom">
  HTMLタグをそのまま記述することもできます。
</div>
