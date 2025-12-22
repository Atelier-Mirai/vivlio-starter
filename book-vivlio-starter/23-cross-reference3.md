# Cross Reference3

:::{.chapter-lead}
クロスリファレンス機能の章間参照テスト用章です。他の章で定義されたラベルを参照します。
:::

この章では、他の章で定義されたラベルを参照するテストを行います。

## 章間参照のテスト

前章で定義した@einsteinや@basic-tableを参照してみます。
また、@ruby-sampleや@js-sampleも参照できるはずです。

このように、章をまたいだ相互参照が可能です。

## この章独自の要素

**この章のサンプルコード @sample-code-56**

```python
def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n-1) + fibonacci(n-2)

print(fibonacci(10))
```

**この章のデータ表 @data-table-56**

| ID | 名前 | スコア |
|----|------|--------|
| 1 | Alpha | 95 |
| 2 | Beta | 87 |
| 3 | Gamma | 92 |

**この章の図 @diagram-56**

![](Einstein.png){width=50%}

## 相互参照のまとめ

- 前章の図: @einstein
- 前章の表: @basic-table
- 前章のコード: @ruby-sample, @js-sample
- この章の要素: @sample-code-56, @data-table-56, @diagram-56

すべての参照が正しく番号付きリンクに変換されるはずです。


１３章の最後の文章です。@einstein の参照先、１２章にジャンプします。