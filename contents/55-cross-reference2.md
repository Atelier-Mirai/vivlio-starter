# Cross Reference2

:::{.chapter-lead}
クロスリファレンス機能のテスト用章です。図・表・コードの定義と参照を確認します。
:::

この章では、クロスリファレンス機能の動作をテストします。

## 図のテスト

**アインシュタインの写真 @einstein**

![](Einstein.png){width=40% align=center}


**テスト図（自動ID） @auto**

![](Einstein.png){width=30% align=right}

本文中で`@einstein`を参照すると、自動的に番号付きリンク@einsteinに変換されます。
また、自動ID（`@fig-55-2`）で指定した図も参照できます。

## 表のテスト

**画像です**
![](Einstein.png){width=30% align=right}

**表です**

| 項目 | 値 | 備考 |
|------|-----|------|
| A | 100 | テスト |
| B | 200 | サンプル |
| C | 300 | データ |

**ソースコードです**
```ruby
def hello(name)
  puts "Hello, #{name}!"
end

hello("World")
```

---

## 画像のテスト

ただの画像です。

![](sample.png){width=30% align=right}

**画像(参照無)**
![](sample.png){width=30% align=right}

**画像(自動ID) @auto**
![](sample.png){width=30% align=right}

**画像(ID指定) @gazou**
![](sample.png){width=30% align=right}

## 画像のテスト その２

30%画像です。

![](sample.png){width=30%}

**30%left**
![](sample.png){width=30% align=left}

**30%center @auto**
![](sample.png){width=30% align=center}

**50%right @gazou2**
![](sample.png){width=50% align=right}

## 画像のテスト その３

サンプル画像です。

![](300x200.png)
![](300x200.png){align=right}
![](300x200.png){width=30%}
![](300x200.png){width=30% align=right}

![](600x400.png){width=15% align=right}
![](600x400.png){width=30% align=right}



---








---
**画像です @auto**
![](sample.png){width=30% align=right}

**表です @auto**

| 項目 | 値 | 備考 |
|------|-----|------|
| A | 100 | テスト |
| B | 200 | サンプル |
| C | 300 | データ |

**ソースコードです @auto**
```ruby
def hello(name)
  puts "Hello, #{name}!"
end

hello("World")
```

**相互参照しない表**

| 項目 | 値 | 備考 |
|------|-----|------|
| A | 100 | テスト |
| B | 200 | サンプル |
| C | 300 | データ |


**基本的な表 @basic-table**

| 名前 | 年齢 | 職種 |
|------|-----|------|
| 太郎 | 25 | エンジニア |
| 花子 | 30 | デザイナー |
| 次郎 | 35 | マネージャー |

**基本的な表 @auto**

| 名前 | 年齢 | 職種 |
|------|-----|------|
| 太郎 | 25 | エンジニア |
| 花子 | 30 | デザイナー |
| 次郎 | 35 | マネージャー |

**複雑な表（自動ID） @omakase**

| 名前 | 年齢 | 職種 | 部署       | 勤続<br>年数 | スキル<br>レベル | リモート<br>勤務 |
|:------:|:------:|:------:|:------------|:------:|:------------:|:------------:|
| 太郎 | 25   | エンジニア | 開発1課     | 2年       | ★★☆☆☆         | 可           |
| 花子 | 30   | デザイナー | UXデザイン部 | 5年       | ★★★★☆         | 一部可       |
| 次郎 | 35   | マネージャー | プロダクト部 | 8年       | ★★★★☆         | 不可         |

**複雑な表 @complex-table**
| 名前 | 年齢 | 職種 | 部署       | 勤続<br>年数 | スキル<br>レベル | リモート<br>勤務 |
|:------:|:------:|:------:|:------------|:------:|:------------:|:------------:|
| 太郎 | 25   | エンジニア | 開発1課     | 2年       | ★★☆☆☆         | 可           |
| 花子 | 30   | デザイナー | UXデザイン部 | 5年       | ★★★★☆         | 一部可       |
| 次郎 | 35   | マネージャー | プロダクト部 | 8年       | ★★★★☆         | 不可         |

**複雑な表 @complex-table-long-table**

:::{.long-table}
| 名前 | 年齢 | 職種 | 部署       | 勤続<br>年数 | スキル<br>レベル | リモート<br>勤務 |
|:------:|:------:|:------:|:------------|:------:|:------------:|:------------:|
| 太郎 | 25   | エンジニア | 開発1課     | 2年       | ★★☆☆☆         | 可           |
| 花子 | 30   | デザイナー | UXデザイン部 | 5年       | ★★★★☆         | 一部可       |
| 次郎 | 35   | マネージャー | プロダクト部 | 8年       | ★★★★☆         | 不可         |
:::

本文中で@basic-tableを参照すると、表番号が表示されます。

本文中で`@einstein`を参照すると、自動的に番号付きリンク@einsteinに変換されます。
また、自動ID（`@fig-55-2`）で指定した図も参照できます。


## コードのテスト

**Rubyサンプルコード @ruby-sample**

```ruby
def hello(name)
  puts "Hello, #{name}!"
end

hello("World")
```

**JavaScriptサンプル @js-sample**

```javascript
function greet(name) {
  console.log(`Hello, ${name}!`);
}

greet('World');
```


**JavaScriptサンプル2 @js-sample2**
```javascript:app2.js
function main() {
    console.log("01234567890123456789012345678901234567890123456789012345678901234567890123456789");
}
```

### サンプルコード


`include`文を用いてコードを埋め込むことができます。

```include:sample1.js```

**Sample1 @include-sample1**
```include:sample1.js```

**Sample2 @include-sample2**
```include:sample2.js```

### サンプルコード 範囲指定
**Sample2範囲指定 @include-sample2-range**
```include:sample2.js:12-16```

@ruby-sampleや@js-sampleのように、コードリストも参照できます。


１２章の最後の文章です。@einstein の参照先、１２章にジャンプします。
@complex-table を参照します。
