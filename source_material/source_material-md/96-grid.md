# CSS グリッドレイアウト

:::{.chapter-lead}
通常、ウェブページは、上から下、左から右に、配置されます。従来、ページ上の要素を自由自在に配置するには大変な苦労が伴いました。CSSグリッドレイアウトを用いると、縦と横の補助線（グリッド・格子）を用いて、自由自在に要素を配置することができます。

(準)公式サイトMDNより、[グリッド](https://developer.mozilla.org/ja/docs/Learn/CSS/CSS_layout/Grids) について書かれた記事がございますので、引用しつつ、ご紹介いたします。[^221]

[^221]: [グリッドレイアウトの基本概念](https://developer.mozilla.org/ja/docs/Web/CSS/CSS_Grid_Layout/Basic_Concepts_of_Grid_Layout)にも分かりやすく説明されており、お勧めです。  
:::



### グリッドとは

CSS グリッドレイアウト（Grid Layout）は、ウェブ用の二次元レイアウトシステムです。これにより、コンテンツ(内容物・出し物)を行と列にレイアウト（配置）することができ、複雑なレイアウトを簡単に構築できるようにする多くの機能があります。
グリッドは、列と行を定義する水平線と垂直線の集合が交差したものです。要素をグリッドの行と列に並べて配置することができます。

グリッドには通常、列（column）、行（row）、そしてそれぞれの行と列の間の間隔（gap）があります。

![](gridlayout.png)


### グリッドを定義する

グリッドレイアウトの練習の為に、`grid.html` と `grid.css` を用意しましょう。

**▼grid.html**

```
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>CSSグリッドレイアウト練習</title>
    <link rel="stylesheet" href="grid.css">
  </head>

  <body>
    <h1>CSSグリッドレイアウト練習</h1>

    <div class="container">
      <div>One</div>
      <div>Two</div>
      <div>Three</div>
      <div>Four</div>
      <div>Five</div>
      <div>Six</div>
      <div>Seven</div>
    </div>

  </body>
</html>
```

**▼grid.css**

```
.container > div {
  border-radius: 5px;
  padding: 10px;
  background: #cfe8dc;
  border: 2px solid #4fb9e3;
}
```

![](grid0.png)

`.container > div` は、`container`クラスの <br>**直下**の`div`タグを選択するためのセレクタです。

`<div>One</div>`、`<div>Two</div>`などが薄い緑地に水色の枠で囲まれるようになります。

---
グリッドを定義するためには、`display` プロパティに `grid` の値を使います。
これによりグリッドレイアウトが有効になり、コンテナの直接の子の全てがグリッド項目(アイテム)になります。
ここでは、コンテナが `<div class="container">` で、グリッド項目が`<div>One</div>`、`<div>Two</div>`などです。

「みかん箱」に「みかん」を入れる、そのような想像をすると分かりやすいかもしれません。
グリッドコンテナ＝「みかん箱」、グリッド項目＝「みかん」です。 [^222]

![](container_mikan.png)

[^222]: 出典: 季節のイベント・動物・子供などのかわいいイラストが沢山見つかるフリー素材サイト [いらすとや](https://www.irasutoya.com/)

それでは、CSS に次を追加してみましょう。

**▼grid.css**

```
.container {
  display: grid;
}
```

ブラウザを再読み込みして確認してみても、特に変化が見られません。
`display: grid` を宣言すると 1 列のグリッドになるので、項目は上下に表示され続けます。

よりグリッドらしく見せるには、グリッドにいくつかの列を追加する必要があります。
ここでは `grid-template-columns` プロパティにより、200 ピクセルの列を 3 つ追加しましょう

以下のように CSS を更新しましょう。

**▼grid.css**

```
.container {
  display: grid;
  grid-template-columns: 200px 200px 200px;
}
```

![](grid1.png)

CSS 規則に 2 番目の宣言を追加してからページを再読み込みすると、作成したグリッドの各セルに項目が 1 つずつ再配置されていることがわかります。


### `fr` 単位での柔軟なグリッド

`fr` は、`fraction(分数)` に由来する、CSS グリッドレイアウトのために生まれた単位です。

`px`などの長さとパーセントを使用してグリッドを作成するだけでなく、この `fr` 単位を使用して柔軟にグリッドの行と列のサイズを変更できます。 この単位は、グリッドコンテナ内の使用可能スペースの割合を表します。

列のリストを次の定義に変更し、`1fr` の列を 3 つ作成します。

**▼grid.css**

```
.container {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr;
}
```

![](grid2.png)

グリッドコンテナ内を三等分して、それぞれの `div` 要素が配置されていることが確認できます。

![](grid3.png)

より柔軟に列幅を変更することもできます。 `fr` 単位はスペースを比例して配分するので、各列には異なる正の値を指定できます。

例えば `grid-template-columns: 2fr 1fr 1fr;` と定義すると、右のようになります。


### 行間や列間の間隔

列の間隔を設定する為には `column-gap` プロパティ、行の間隔を設定する為には `row-gap` プロパティ、列と行を両方設定する為には `gap` プロパティを使用します。

**▼grid.css**

```
.container {
  display: grid;
  grid-template-columns: 2fr 1fr 1fr;
  gap: 20px;
}
```

![](grid4.png)

右のように、行間、列間、それぞれ `20px` の間隔を空けることができました。


### 行指定や列指定の繰り返し

反復記法を使用して、行指定や列指定を繰り返すことができます。

**▼grid.css**

```
.container {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 20px;
}
```

![](grid5.png)

グリッドコンテナ内を四等分して、それぞれの `div` 要素が配置されていることが確認できます。

`grid-template-columns: 1fr 1fr 1fr 1fr;` と同等ですが、繰り返す回数が多いときに便利です。

---
=== グリッドの線番号を使った要素の配置
グリッドの作成から、グリッド上に要素を配置することに移ります。
グリッドは `1` から始まる線番号を持っています。列の 1 線目がグリッドの左側にあり、行の 1 線目が一番上にあります。

開始線と終了線を指定することで、これらの線に従って要素を配置できます。


CSS からそれぞれの要素を扱いやすくするために、`grid.html` を次のように更新します。`<div class="one">One</div>`のように、クラス名「`one`」を付けています。

**▼grid.html**

```
<div class="container">
  <div class="one"  >One</div>
  <div class="two"  >Two</div>
  <div class="three">Three</div>
  <div class="four" >Four</div>
  <div class="five" >Five</div>
  <div class="six"  >Six</div>
  <div class="seven">Seven</div>
</div>
```

CSS は次のように更新します。

**▼grid.css**

```
.container {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr 1fr;
  grid-template-rows:    1fr 1fr 1fr 1fr;
  gap: 20px;
}
```

![](shortcut3.png)

表示結果は先ほどと変わりませんが、四列四行のグリッド（格子）を作成することができました。


「開発者ツール」を使うと、どのようにグリッドが構成されたか、確認することができます。
画面上で、右クリック [^223] して表示される「ショートカットメニュー」から「調査」をクリックしましょう。

[^223]: システム設定 - トラックパッド - ポイントとクリック - 副ボタンのクリック から 「右下隅をクリック」 に設定すると右クリックできます。ショートカットキー `option + command + I` を押すことでも、開発者ツールを開くことができます。

![](grid-kakunin.png)
開発者ツールを表示したので、グリッドの線番号を表示しましょう。


:::{.tip}
- 1. 「インスペクタ」をクリックします。

- 2. 下に HTML コードが表示されています。`<div class="container">` の右側に、「grid」と書かれた小さなボタンがありますので、これをクリックします。または、右側の「レイアウト」欄内の「グリッド」の項目にある「グリッドをオーパーレイ表示」にチェックを入れます。

- 3. 次に、右側の「レイアウト」欄内の「グリッド」の項目にある「グリッドの表示設定」で「線番号を表示」にチェックを入れます。
:::

これで、グリッドの線番号を表示できました。

上部を見ると、左から、1, 2, 3, 4, 5 と番号が振られています（四列作りましたので、線は 1 〜 5 までの五本作られます）。

それでは、次のように CSS を追加して、「One」から「Seven」までの要素を配置してみましょう。

**▼grid.css**

```
.one   { grid-column: 1 / 5;  grid-row: 1;     }
.two   { grid-column: 1;      grid-row: 2 / 4; }
.three { grid-column: 2 / 4;  grid-row: 2;     }
.four  { grid-column: 4;      grid-row: 2;     }
.five  { grid-column: 2 / 4;  grid-row: 3;     }
.six   { grid-column: 4;      grid-row: 3;     }
.seven { grid-column: 1 / 5;  grid-row: 4;     }
```

結果は次のようになります。

![](grid6.png)
`.one { grid-column: 1 / 5; grid-row: 1;}` は、列は一本目の線から五本目の線まで、行は一行目に配置されています。

`.two { grid-column: 1    ; grid-row: 2 / 4;}` は、列は一本目の線に、行は二本目から四本目に配置されています。

このように、グリッドの線を使って、好きなように要素を配置することができます。


また下部を見ると見ると、右から、-1, -2, -3, -4, -5 と番号が振られています。
一番右端の線を指定する際には「左から数えて５本目」と指定するほか、「右から数えて１本目」と指定することもできます。

これを踏まえると、

**▼grid.css**

```
.one   { grid-column: 1 / 5;  grid-row: 1; }
```

と記述する代わりに、

**▼grid.css**

```
.one   { grid-column: 1 / -1;  grid-row: 1; }
```

と記述しても同様の結果が得られます。中央に多くの列数がある場合や列数が可変する場合などには、右端から線番号を数えると楽です。活用していきましょう。


### 要素の左揃え、中央揃え、右揃え

`justify-self`プロパティを使うと、「**水平**」方向での要素の配置を制御できます。

CSSを追加して実験してみましょう。

![](grid7.png)

**左揃え** `.one { justify-self: start; }`

![](grid8.png)

**中央揃え** `.one { justify-self: center; }`

![](grid9.png)

**右揃え** `.one { justify-self: end; }`


### 要素の上揃え、中央揃え、下揃え

`align-self`プロパティを使うと、「**垂直**」方向での要素の配置を制御できます。

CSSを追加して実験してみましょう。

![](grid10.png)

**上揃え** `.two { align-self: start; }`

![](grid11.png)

**中央揃え** `.two { align-self: center; }`

![](grid12.png)

**下揃え** `.two { align-self: end; }`

---
=== 線番号に名前を付ける
線番号に名前を付け、より使いやすくすることができます。

**▼grid.css**

```
.container {
  grid-template-rows: 1fr 1fr 1fr 1fr;
}
```

と記述して、四行作成しましたが、以下のように書くことで、行のそれぞれの線に名前を付けることができます。

**▼grid.css**

```
.container {
  grid-template-rows:
    [head]    1fr  /* 一本目の線に head    と命名 */
    [main]    1fr  /* 二本目の線に main    と命名 */
    [article] 1fr  /* 三本目の線に article と命名 */
    [foot]    1fr; /* 四本目の線に foot    と命名 */
}
```

そして、この線番号に付けた名前を使って、

**▼grid.css**

```
.one   { grid-column: 1 / 5;  grid-row: head;          }
.two   { grid-column: 1;      grid-row: main / span 2; } /* 二行使い、配置する */
.three { grid-column: 2 / 4;  grid-row: main;          }
.four  { grid-column: 4;      grid-row: main;          }
.five  { grid-column: 2 / 4;  grid-row: article;       }
.six   { grid-column: 4;      grid-row: article;       }
.seven { grid-column: 1 / 5;  grid-row: foot  ;        }
```

と書くことができます。

結果は同じですが、それぞれの要素をどの行に配置するのか、より分かりやすくなります。
良く使う線には名前を付けておくと便利です。

