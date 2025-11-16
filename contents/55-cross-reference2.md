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
また、自動ID（@fig-55-2）で指定した図も参照できます。

## 表のテスト

**基本的な表 @basic-table**

| 項目 | 値 | 備考 |
|------|-----|------|
| A | 100 | テスト |
| B | 200 | サンプル |
| C | 300 | データ |

**複雑な表（自動ID） @omakase**

| 名前 | 年齢 | 職業 |
|------|------|------|
| 太郎 | 25 | エンジニア |
| 花子 | 30 | デザイナー |
| 次郎 | 35 | マネージャー |

本文中で@basic-tableを参照すると、表番号が表示されます。

本文中で`@einstein`を参照すると、自動的に番号付きリンク@einsteinに変換されます。
また、自動ID（@fig-55-2）で指定した図も参照できます。


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

@ruby-sampleや@js-sampleのように、コードリストも参照できます。


１２章の最後の文章です。@einstein の参照先、１２章にジャンプします。