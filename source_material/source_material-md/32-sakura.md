# JavaScriptで桜吹雪を舞わせよう

:::{.chapter-lead}
古来より日本人の心をとらえてはなさない「さくら」。
春の桜吹雪は、格別なものがあります。
これまで学んだことを元に、JavaScript を使って実現しましょう。  
:::



## HTML

**▼index.html**

```
<!DOCTYPE html>
<html>
  <head>
    <!-- 略 -->
  </head>

  <body>
    <!-- 略 -->

    <!-- 桜吹雪の効果 -->
    <link rel="stylesheet" href="hanabira.css">
    <script src="hanabira.js"></script>
  </body>
</html>
```

HTMLは今回の主眼ではございませんので省略しておりますが、
`</body>` 直前に桜吹雪のための CSS `hanabira.css`と JavaScript `hanabira.js` を読み込んでいます。


## 桜の花びらの為のCSS

`hanabira.css` は、桜の花びらの色やひらひら回転するCSSアニメーションのためのCSSです。

**▼hanabira.css**

```
/*---------------------------------------------------------------------
  桜吹雪の効果の為のスタイルシート
---------------------------------------------------------------------*/
html,
body {
  overflow-x: clip;
  position: relative;
}

/* さくらの花びらの楕円形 */
.hana {
  position: absolute;
  width:  0;
  height: 0;
  border: 10px solid transparent;
  border-radius: 15px;
  border-top-right-radius: 0;
  border-bottom-left-radius: 0;
}

/* さくらの花びらの楕円形 */
/* 15度回転させることで、花びら形にする */
.hana::after {
  content: "";
  display: block;
  position: absolute;
  top:  -7px;
  left: -7px;
  width:  0;
  height: 0;
  border: 10px solid transparent;
  border-radius: 15px;
  border-top-right-radius: 0;
  border-bottom-left-radius: 0;
  transform: rotate(15deg);
}

/* 淡い櫻色から濃い櫻色まで 五色のテーマ */
.t1, .t1::after { border-color: #fef4f4; }
.t2, .t2::after { border-color: #ffd1d9; }
.t3, .t3::after { border-color: #ffc0cb; }
.t4, .t4::after { border-color: #ffc0cb; }
.t5, .t5::after { border-color: #ffafbd; }

/* アニメーション(動き) を五種類用意する */
.a1 { animation: a1 12s infinite; }
.a2 { animation: a2 10s infinite; }
.a3 { animation: a3  9s infinite; }
.a4 { animation: a4  9s infinite; }
.a5 { animation: a5  8s infinite; }
@keyframes a1 {
  from { transform: rotate(   0deg) scale(.9); }
  50%  { transform: rotate( 270deg) scale(.9); }
  to   { transform: rotate(   1deg) scale(.9); }}
@keyframes a2 {
  from { transform: rotate( -90deg) scale(.8); }
  50%  { transform: rotate(-360deg) scale(.8); }
  to   { transform: rotate( -89deg) scale(.8); }}
@keyframes a3 {
  from { transform: rotate(  30deg) scale(.7); }
  50%  { transform: rotate( 300deg) scale(.7); }
  to   { transform: rotate(  29deg) scale(.7); }}
@keyframes a4 {
  from { transform: rotate(-120deg) scale(.6); }
  50%  { transform: rotate(-390deg) scale(.6); }
  to   { transform: rotate(-119deg) scale(.6); }}
@keyframes a5 {
  from { transform: rotate(  60deg) scale(.5); }
  50%  { transform: rotate( 330deg) scale(.5); }
  to   { transform: rotate(  59deg) scale(.5); }}
```


### 花びらの形

`.hana` で、一枚の花びらの半分(楕円のような形)を作成します。
そして `.hana::after`では、`transform: rotate(15deg);` と書かれている点に着目してください。もう半分を15度傾けて結合することで、一枚の花びらを完成させています。


### 花びらの色

`.t1, .t1::after { border-color: #fef4f4; }` で、花びらの色を設定します。 `.t1` 〜 `.t5` まで、淡い桜色から濃い桜色まで五種類の花びらの色を付けています。


### 花びらがひらひら回転する動き

CSSアニメーションを用いて、回転する動きと少しずつ大きさが変化する動きを実現しています。
`.a1 { animation: a1 12s infinite; }` で、花びらのアニメーションを設定します。 `.a1` 〜 `.a5` まで、五種類の花びらの動きを付けています。


`.a1 { animation: a1 12s infinite; }` は、アニメーション `a1` を `12秒`掛けて実行します。

アニメーション `a1` は、以下の動きをします。

```
@keyframes a1 {
  from { transform: rotate(  0deg) scale(.9); }
  50%  { transform: rotate(270deg) scale(.9); }
  to   { transform: rotate(  1deg) scale(.9); }
}
```

最初(`from`)は、回転角0度(`rotate(  0deg)`)で、<br>
中ほど(`50%`)は、回転角270度(`rotate(  270deg)`)となり、<br>
最後に(`to`)は、回転角1度(`rotate(  1deg)`)になるまで回転します。<br>
そして、`scale(.9)`とありますので、 `.hana` で作成した花びらの大きさより少し小さ目(`90%`)の花びらとなります。


花びらの色が五種類、アニメーションの動きが五種類ありますので、二十五種類の組み合わせで花びらがひらひら舞うことになります。

```
<!-- 桜吹雪の効果の為のスタイルシートを読み込む -->
<link rel="stylesheet" href="hanabira.css">
<div class="hana t1 a1"></div>
```

と書いて、ブラウザを再読み込みさせてください。左上でゆらゆらと回転する一枚の桜の花びらが見られるはずです。`t1` に代えて `t5` にすることで、花びらの色が濃くなります。`a1` に代えて `a5` にすることで、花びらの形が小さく、また回転も変わりますので、確認してみましょう。


## JavaScript の 利点

先ほどは、次のようなコードにより、一枚だけ花びらを表示させました。

```
<!-- 桜吹雪の効果の為のスタイルシートを読み込む -->
<link rel="stylesheet" href="hanabira.css">
<div class="hana t1 a1"></div>
```

もっと沢山の花びらを表示させるためには、次のように書けば良いと発想が浮かびます。

```
<div class="hana t1 a1"></div>
<div class="hana t1 a2"></div>
<div class="hana t1 a3"></div>
(略)
<div class="hana t5 a5"></div>
```

ですが、このように書くのは、とても大変です。またこのように書いても花びらは左上の角で動いているだけで、右に動いたり下に動いたりなど風に揺られて散っているようには見えません。

そこで登場するのが、JavaScript です。JavaScript は、(主に)ブラウザ上で動くプログラミング言語で、HTMLの要素を取得し、追加や編集、削除など様々に制御することができるので、動きのあるウェブサイトを作ることが出来るようになります。

今回の例で言えば、手書きで、五十枚の花びらを `<div class="hana t1 a1"></div>` のように書くのではなく、JavaScriptに 描画させたら良いですし、それぞれの花びらが、一定時間ごとに右や左、下へ動いていくよう、記述できます。

ゆらゆらと風に舞って散っていくように、右へ行ったり、左に行ったりなど左右への揺らぎも表現したいので、一定回数右へ移動したら左へ移動するように、左右どちらかの画面の端に消えてしまったときには、反対側の端から現れるようにします。

また、そのままですと、最初に用意した五十枚の花びらが地面に落ちてしまった後は、画面から花びらが消えて寂しいことになります。そこで、地面に着いて花びらが消えてしまったときには、新しい花びらをまた空から降らせることにします。


## プログラムの設計を考える - 素朴な実装

素朴な実装は、五十枚の花びらのための配列を用意することです。
それぞれの花びらが区別できるように、IDに関する配列、 `X`座標に関する配列、 `Y`座標に関する配列等、それぞれの属性ごとに配列を用意すれば良いでしょう。

つまり以下のようにです。

```
id = [0, 1, 2, ..., 49]
x  = [0, 10, 20, ..., 490]
y  = [0, 0, 0, ..., 0]
```

そして繰り返しのための構文を学習しましたので、以下のように五十枚の花びらに関して繰り返せば、ひとまずの実装はできます。

```
// 五十枚の花びらについて順に繰り返す
for (let id = 0; id < 50; id++) {
  // 乱数で少しだけ左右に動くよう X座標, Y座標の値を増減する
  x[id] = x[id] ± 1 ~ 5 ;
  y[id] = y[id] ＋ 1 ~ 5 ;
}
```

ですが、 このような設計ですと、1枚の花びらに関する情報が、 `X`座標に関する配列、 `Y`座標に関する配列などに分散することとなります。色や動きに関する特性も用意したいですし、落下速度をそれぞれのはなびらに設定しようと思った場合に、また新しい配列を用意することとなります。

素朴に配列で実装すると管理がとても大変になりそうです。


## オブジェクト指向で実装する

もう少し楽にできたらと、先人達の試行錯誤から「オブジェクト指向」という考え方が生まれてきました。

わたくしたちは、すでに「オブジェクト指向」と言う考え方を学習しましたので、せっかくの機会ですので、これに基づいて実装していきましょう。

一枚の花びらが持つ「属性」とそれを「操作する方法（メソッド・機能・関数）」を一まとめにしたもの、それが「オブジェクト（インスタンス・実例とも）」です。

一枚の花びらの雛形となるもの、それが「クラス（分類）」です。 [^150]

[^150]: CSSでも分類分けを行う為にクラスが登場しました。「分類分け」を行うという概念は共通しますが、JavaScript など プログラミング言語におけるクラスと、CSS の クラスとは別物です。

雛形、クラスは、よく鯛焼きの型に例えられます。金属で出来た型、それがクラス・雛形です。そしてこの型から生み出されるたくさんの鯛焼き達、それがオブジェクト（インスタンス・実例）です。個々のオブジェクト（鯛焼き）はあんこが入っている鯛焼きもあり、あるいはクリームが入っていたり、チョコレートが入っていたりする鯛焼きがある、そういった具合です。

先に学んだ四角形クラスの例で言えば、四角形には幅と高さがあり、面積を求める演算（メソッド・機能・関数）が定義されている。それが四角形クラスに共通する性質・雛形・クラスです。

四角形クラスから生み出されてくる四角形には、例えば幅が100ピクセルで高さが20ピクセルものもあるでしょうし、幅が30ピクセルで高さも30ピクセルのものもあるでしょう、そして、それぞれ生み出されたオブジェクト（インスタンス・実例）としての個々の四角形は、面積を求めるための `area`と言うメソッド（機能・関数）を持っていますので、ある四角形の面積は2000平方ピクセルですし、別の四角形の面積は900平方ピクセルといった具合に、個々のオブジェクトに備わっているメソッドを呼び出すことで、求めることができます。


### 「花びらクラス」を設計する

それでは、オブジェクト指向の考え方に基づいて、花びらクラスを設計してみましょう。花びらクラスを鋳型（いがた）として生成される実例（インスタンス）は、自分自身の情報データ(属性)とその属性の操作方法(メソッド・関数) [^151]を持ちます。

[^151]: メソッドとは、方法、方式、手法、やり方、などの意味を持つ英単語で、一般の外来語としては、一定の形式として確立した奏法、教授法、指導法、その他様々な技法のことを「○○メソッド」のように言います。オブジェクト指向プログラミングでは、データと手続きを「オブジェクト」として一体化（カプセル化）して定義し利用しますが、この、オブジェクトに内包された手続き（データに対する処理内容を記述したプログラム）のことをメソッドと言います。出典: IT用語辞典

一枚一枚の花びらはどのような属性を持てば良いでしょうか。

まずたくさんの花びらが作られますので、どの花びらかわかるよう、他の花びらと区別するためのID属性が必要です。次に画面上のどの位置に表示されているのか、横方向(X座標)と縦方向(Y座標)それぞれの位置を表す属性が必要です。 [^152]

[^152]: (通常) 画面の左上がX座標、Y座標ともに0となる点(0, 0)です。X座標は画面の右へ行くほど大きくなります。またY座標は画面の**下**に行くほど大きくなります。

また花びらの重なり順を表すためにZ軸方向つまり画面の手前にあるのか奥にあるのかを表すための属性が必要です。CSS の `z-index` に倣って、手前にあるものほど大きな値を持つとしましょう。

また、動きに関する属性も持つと良さそうです。

現在、右へ動いているのか、左に動いていっているのかを示す、動く方向に関する属性や、一定回数動くと逆の向きに動くようにしたいので、同じ方向に何回動いたかを示す属性、反転するための上限回数の属性がいりそうです。ゆっくり落ちていくのか素早く落ちていくのかを示す落下速度に関する属性も必要でしょう。

最後に、CSSで色とアニメーションに関してクラス名を定義しましたので、CSSで使うクラス名を決めるための属性もいりそうです。

まとめると次のようになるでしょう。


:::{.tip}
**属性 Attribute**

* id 属性: 個々の花びらを区別する為に
* x 属性: x座標を表す為に
* y 属性: y座標を表す為に
* z 属性: z座標を表す為に
* direction 属性: 動いていく方向を示す為に
* tremorCount 属性: 同じ方向に何回動いたのかを保持する為に
* tremorMax 属性: 同じ方向に動ける上限回数を定める為に
* fallingSpeed 属性: 落下速度を示す為に
* cssClassName 属性: CSSのクラス名を指定する為に
:::

続いて、これらの属性を操作するためにどのような関数を用意すればよいでしょうか。

まず、様々な花びらクラスのインスタンス（実例）を生成することになるわけですが、その際に、それぞれの花びらの各属性(id, x, y, z など)の初期値を設定する必要があります。初期値を設定するために、JavaScriptではコンストラクタと呼ばれるメソッド(関数)が用意されています。コンストラクタは日本語では「構築子（こうちくし）」と翻訳されます。

次に左右へゆらゆらと揺れる動きに関してですが、 同じ方向に動く回数が上限に達したか否かを確認できる関数があると便利でしょう。そして上限に達した場合に、左右へ揺れる動きの方向を反転させる操作（関数）も用意してあると良さそうです。

また、花びらが画面の右端に行ったときに、そのままですと花びらが消えてしまいますので、右端に行ったかどうかを確認するための関数や、左端に行ったかを確認するための関数、花びらが空中にあるのか、あるいは地面に着いているのかを調べるための関数もあると良さそうです。

そして、忘れてはならないのは実際に花びらを動かすための操作も必要です。
作成した花びらクラスのインスタンスの各属性を更新する為の関数と、そして実際のHTML上のdiv要素 `<div class="hana t1 a1"></div>` に動いた位置を反映する為の関数を用意しましょう。

まとめると次のようになります。


:::{.tip}
**操作 Method**

* constructor() 関数: 各属性の初期値を設定する機能の為に
* isTremorMax() 関数: 揺らぎの上限回数に達したかを確認する機能の為に
* directionSwitch() 関数: 左右へ揺れる方向を反転させる機能の為に
* isInTheAir() 関数: 空中にあるか確認する機能の為に
* isOnTheGround() 関数: 地面に着いたか確認する機能の為に
* isOnTheRightEdge() 関数: 右端にあるか確認する機能の為に
* isOnTheLeftEdge() 関数: 左端にあるか確認する機能の為に
* move() 関数: JavaScriptインスタンスの位置情報(x座標,y座標)を更新する機能の為に
* applyPositionToDom() 関数: JavaScriptインスタンスの位置情報(x座標, y座標, z座標)を HTMLのdiv要素に反映させる機能の為に
:::

![](UML_Class_Diagram.png)

右は、**UMLクラス図** と呼ばれる図で、システム設計の際などに用いられます。(今回のさくらの花びらが舞い散るプログラムでは、あまり必要となることはありませんが) より大きなプログラムを作成される際には、[cacoo](https://cacoo.com/ja/) などのツールの利用や手書きされるなど、いきなりコードを書く前に、必要となるクラス等を整理する助けにもなってくれることでしょう。

::: {.text-right}
**UMLクラス図　　　　　**
:::


## 桜吹雪の為のコード


### 乱数関数の作成

花びらを不規則に配置し、その位置を変化させる為には「乱数」を用いると便利です。JavaScriptには、 `Math.random()関数` が用意されており、**0以上1未満の浮動小数点数(≒小数)**を取得することが出来ます。

任意の範囲の整数や浮動小数点数が得られる関数を自作すると、プログラムを作り易いので、次のように乱数関数を自作します。

```
let rand = (min, max, type = "integer") => {
  if(type === "integer"){
    return Math.floor(Math.random() * (max-min+1)) + min
  } else {
    return Math.random() * (max-min) + min
  }
}
```

`rand(1, 5)` で、1以上5以下の乱数が得られます。 `rand(0.2, 0.7, "float")` では、0.2以上0.7未満の乱数が得られます。

`=>` が「矢印(arrow)」のように見えることから、「アロー関数」と呼ばれる書き方で、従来の `function` を使うと、以下のようになります。

```
function rand(min, max, type = "integer") {
  if(type === "integer"){
    return Math.floor(Math.random() * (max-min+1)) + min
  } else {
    return Math.random() * (max-min) + min
  }
}
```

整数と浮動小数点数、どちらでも使えるようにしたいのですが、整数を使うことが多いので、 引数に `type="integer"` と書き、整数を既定値にしています。次に `if`文の中で条件判定を行い、整数、浮動小数点数、それぞれの型(`type`)に応じた乱数を返すようにしています。

`Math.floor()`は、「床関数」と呼ばれる、小数点以下を切り捨てるために用意されているJavaScriptの関数です。


### 桜吹雪のソースコードの概要

さて設計も固まりましたので、ソースコードを書いて行きましょう。

いきなりコードを書き始めても良いのですが、大まかな概要を書き、そしてそれぞれの詳細を作り込むようにしていくと、効率よく書けるかと思います。

コードの大まかな概要は、次のようになるでしょう。

```
定数宣言
画面サイズの取得
イベントリスナの設定

自作の乱数関数の用意

花びらクラスの宣言
  コンストラクタや各種メソッドの定義

花びらインスタンスの生成とHTMLへの要素追加

時々刻々、花びらの位置を更新して、ひらひら舞わせる処理
```

- 定数宣言  
  　例えば「50枚」の花びらを舞わせることにします。プログラム中に直接「50」と言う数字をしまってももちろん動きますが、後から「100枚」に変更したい場合、何百行、何千行ものコード中から「50」と言う数字を探し出し、「100」に変更する必要があります。 <br> 　これはとても大変な作業になります。変更漏れがあるかもしれませんし、あるいは誤って、他の意味で使われていた「50」と言う数字を書き換えてしまうかもしれません。 そこで、ソースコード中に「50」と直接書く代わりに、 `NUMBER_OF_HANABIRAS` と定数を使って書くことをお薦めします。枚数を変更したくなったときには、その定数を宣言した行を参照して、 `const NUMBER_OF_HANABIRAS = 50` から `const NUMBER_OF_HANABIRAS = 100` と変更するだけで済みます。 <br> 　修正も容易ですし、プログラムを見たときにも、「50」と言う数字の代わりに `NUMBER_OF_HANABIRAS` と書かれていますので、「花びらの枚数である」と意味がはっきり分かり、詠みやすく理解しやすいコードを書くことが出来ます。

- 画面サイズの取得  
  　どのような端末で見ているかは人によって様々です。iPhoneで見ている方もいるでしょうし、あるいは広いディスプレイで見ている方もいらっしゃるかもしれません。そこで画面の幅や高さを取得する処理が必要です。

- イベントリスナの設定  
  　一般に、ウェブサイトのページが読み込まれた時(load)、画面がスクロールされた時(scroll)、ボタンが押された時(click)など、様々なイベントが発生します。様々なイベントが発生したときにどのような関数・処理を実行するのかを指定できるよう、JavaScriptには、イベントリスナと呼ばれる機能が備わっています。 <br> 　ここでは、画面がスクロールされたときに、花びらが画面のウインドウ内に納まるよう、スクロール位置を取得するイベントリスナを準備します。

- 自作の乱数関数の用意  
  　先に紹介したように、自作の乱数関数を準備するとプログラムが読み書きしやすくなりますので、準備しておきます。

- 花びらクラスの宣言  
  　先に紹介した、花びらクラスのコンストラクタや各種メソッドを宣言します。

- 花びらインスタンスの生成とHTMLへの要素追加  
  　初期配置等を指定した50枚の花びらを作成し、画面に表示されるようHTML文書に div要素として追加します。

- 時々刻々、花びらの位置を更新して、ひらひら舞わせる処理  
  　50枚の花びらそれぞれへの繰り返し処理を行う為には `for文`を用います。また、一定時間ごとに定期的に処理を行えるよう、JavaScript には `setInterval()` 関数が用意されていますので、これを使います。


### hanabira.js のご紹介

それでは、花びらクラスを用いたコードのご紹介です。

`class`構文を用いて、花びらクラスを作成しています。花びらの位置情報などの属性と、それを操作するためのメソッド(関数)が実装されています。また画面表示するには、それぞれの花びらインスタンスが持つ位置情報を、実際の花びらdiv要素(DOM)に反映させるに反映させるようにしています。

紙幅の都合上、詳細は割愛いたしますが、ソースコードにコメントもございますので、大まかには理解できるかとは思いますが、いかがでしょうか。

**▼hanabira.js**

```
/*=====================================================================
 🌸の花びらが舞い散るJavaScript
 https://actyway.com/8351 を元に作成
=====================================================================*/

(
() => {
  // =========================================================================
  // 定数宣言等
  // =========================================================================
  const NUMBER_OF_HANABIRAS = 50 // 花びらの枚数
  const FPS                 = 24 // 一秒間に24回 動かす
  const HANABIRA_HEIGHT     = 30 // 花びらの高さ 回転するので最大値は 30px
  const HANABIRA_WIDTH      = 30 // 花びらの幅 回転するので最大値は 30px
  const HANABIRA_Z_BASE     = 10000 // 花びらの z-index の基準値

  // ウィンドウの高さ
  const windowHeight = window.innerHeight
  // ウィンドウの幅(スクロールバー除く)
  const windowWidth  = document.documentElement.clientWidth
  // スクロール位置とイベントリスナの登録
  // (画面スクロールした鴇に花びらがウィンドウ内に納まるようにする為)
  let scroll         = document.documentElement.scrollTop || document.body.scrollTop
  document.addEventListener('scroll', () => {
    scroll = document.documentElement.scrollTop || document.body.scrollTop
  }, false)

  // =========================================================================
  // 乱数関数
  // min 以上 max 以下の乱数を返す (integer)
  // min 以上 max 未満の乱数を返す (float)
  // =========================================================================
  let rand = (min, max, type = "integer") => {
    if(type === "integer"){
      return Math.floor(Math.random() * (max-min+1)) + min
    } else {
      return Math.random() * (max-min) + min
    }
  }

  // =========================================================================
  // 花びらクラスの宣言
  // =========================================================================
  class Hanabira {
    // コンストラクタ(構築子)
    constructor(id, x, y, z, tremorMax, fallingSpeed, cssClassName) {
      this.id           = id
      this.x            = x
      this.y            = y
      this.z            = z
      this.tremorMax    = tremorMax
      this.tremorCount  = 0
      this.direction    = "right"
      this.fallingSpeed = fallingSpeed
      this.cssClassName = cssClassName
    }

    // 際大揺らぎ回数に達しているか？
    isTremorMax() {
      return (this.tremorCount === this.tremorMax)
    }

    // 揺らぎ方向転換
    directionSwitch() {
      if (this.direction === "right") {
        this.direction = "left"
      } else {
        this.direction = "right"
      }
    }

    // 花びらの位置に関して
    // 空中にいるか？(ウィンドウ内か？)
    isInTheAir() {
      return (this.y < scroll + windowHeight - HANABIRA_HEIGHT)
    }

    // 地面に着いたか？
    isOnTheGround() {
      return !this.isInTheAir()
    }

    // 右端にいるか？
    isOnTheRightEdge() {
      return (this.x + HANABIRA_WIDTH >= windowWidth)
    }

    // 左端にいるか？
    isOnTheLeftEdge() {
      // 花びら幅の半分の位置なら、左端と見做す。
      return (this.x <= HANABIRA_WIDTH / 2)
    }

    // 花びらの x, y 座標を更新する
    move() {
      // 花びらの位置がウィンドウ内なら
      if (this.isInTheAir()) {
        // 同一方向へtremorMax回移動したなら、移動方向を反転させる
        if (this.isTremorMax()) {
          this.directionSwitch()
          this.tremorCount = 0
        }

        // 左右に移動する
        let deltaX   = rand(0.2, 0.7, "float")
        let signFlag = (this.direction === "right" ? +1 : -1)
        this.x      += signFlag * deltaX

        // もし右端にいるなら、左端に移動する
        if (this.isOnTheRightEdge()) {
          this.x = HANABIRA_WIDTH / 2
        }

        // もし左端にいるなら、右端に移動する
        if (this.isOnTheLeftEdge()) {
          this.x = windowWidth - HANABIRA_WIDTH
        }

        // 移動回数を増やす
        this.tremorCount++

        // 落下速度分を加える
        this.y += this.fallingSpeed

      // もし地面に着いているなら、上に戻す
      } else if (this.isOnTheGround()) {
        this.y = scroll
        this.x = rand(0, windowWidth - HANABIRA_WIDTH)
      }
    }

    // 位置情報を DOM に反映させる
    applyPositionToDom(domHanabira) {
      domHanabira.setAttribute('style', `top: ${this.y}px; left: ${this.x}px; z-index: ${this.z};`)
    }
  }

  // =========================================================================
  // 花びらクラスから、50枚の花びらインスタンスを生成、HTML文書に追加する
  // =========================================================================

  // 櫻の花びらのための新しい div 要素を作成し、body の末尾に追加
  const divHanabira = document.createElement("div")
  document.body.after(divHanabira)

  // 花びらインスタンスを生成、
  // それぞれの花びらについて、位置等の初期設定を行う
  let domHanabiras = [] // 花びら要素の配列
  let jsHanabiras  = [] // 花びらjsオブジェクトの配列
  for(let i = 0; i < NUMBER_OF_HANABIRAS; i++){
    // 各種属性の初期値の準備
    let id           = i
    let x            = rand(HANABIRA_WIDTH / 2, windowWidth - HANABIRA_WIDTH)
    let y            = rand(-500, 0) + scroll
    let z            = HANABIRA_Z_BASE + i
    let tremorMax    = rand(15, 50)
    let fallingSpeed = rand(1, 3)
    let cssClassName    = `hana t${rand(1, 5)} a${rand(1, 5)}`
    // 各種属性の初期値を与え、花びらクラスのインスタンスを生成
    let jsHanabira   = new Hanabira(id, x, y, z, tremorMax, fallingSpeed, cssClassName)
    // 生成したインスタンスを、あとから扱いやすいよう、配列に格納する
    jsHanabiras[i]   = jsHanabira

    // 花びらの div を作る
    let domHanabira = document.createElement('div')
    // 初期表示位置を設定する
    jsHanabira.applyPositionToDom(domHanabira)
    // ID や 花びらの色とアニメーションのための css class を設定する
    domHanabira.id = i
    domHanabira.className = jsHanabira.cssClassName
    // 作成した花びらをDOMに追加、ブラウザ画面に表示されるようにする
    divHanabira.appendChild(domHanabira)
    // 扱いやすくするために、花びら要素達を配列に格納
    domHanabiras[i] = domHanabira
  }

  // =========================================================================
  // メイン処理
  // 生成したそれぞれの花びらの位置情報を更新し、画面に反映する。
  // =========================================================================
  setInterval(() => {
    for(let jsHanabira of jsHanabiras) {
      // 各花びらに対し、位置情報の更新処理を行う
      jsHanabira.move()

      // js オブジェクトの位置情報を、dom の位置に反映する。
      let id          = jsHanabira.id
      let domHanabira = domHanabiras[id]
      jsHanabira.applyPositionToDom(domHanabira)
    }
  }, 1000 / FPS)
}
)()
```

---
=== 即時実行関数式

[即時実行関数式](https://developer.mozilla.org/ja/docs/Glossary/IIFE) に概要が記載されておりますので、紹介いたします。

> IIFE (Immediately Invoked Function Expression; 即時実行関数式) は定義されるとすぐに実行される JavaScript の関数です。Self-Executing Anonymous Function (自己実行無名関数) と呼ばれることもあります。

即時実行関数式は、次のように書きます。

```
(function () {
  // コードいろいろ
})()
```

あるいは、アロー関数の形式で書くならば、次のようになります。

```
(() => {
  // コードいろいろ
})()
```

即時実行関数を簡単な例 [^153]で確認してみましょう。

[^153]: ある意味、簡単ではない例となっていますが、https://ja.wikipedia.org/wiki生命、宇宙、そして万物についての究極の疑問の答え に説明がございますので、ご覧ください。

以下のHTMLを書きます。

**▼answer_to_life_the_universe_and_everything.html**

```
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>生命、宇宙、そして万物についての究極の疑問の答え</title>
  </head>
  <body>
    <h1>生命、宇宙、そして万物についての究極の疑問の答え</h1>
    <script src="answer_to_life_the_universe_and_everything.js"></script>
  </body>
</html>
```

`<h1>`で見出しを設定、`<script>`タグで、解答を与えてくれる JavaScript ファイルを読み込んでいます。


読み込まれる JavaScript ファイル は次のように書きます。

**▼answer_to_life_the_universe_and_everything.js**

```
function forty_two() {
  alert("42")
}
```

それではブラウザで、`answer_to_life_the_universe_and_everything.html` を読み込んで、「生命、宇宙、そして万物についての究極の疑問の答え」を見てみましょう。

何か解答が表示されたでしょうか。いえ、そのままです。

`forty_two関数`は、定義されたのみで、実行されてはいません。関数を呼び出すためには、次のように書く必要があります。

**▼answer_to_life_the_universe_and_everything.js**

```
function forty_two() {
  alert("42")
}

forty_two()
```

今度は「生命、宇宙、そして万物についての究極の疑問の答え」として「42」が表示されたはずです。JavaScriptでは、関数を呼び出し実行する為には、関数名 `forty_two` に続けて、関数を呼び出し実行することを示す `()` (丸括弧・関数呼び出し演算子)を付ける必要があります。


さて、1行目から3行目までで定義した関数に`forty_two`と名前が付けられていましたので、5行目で、関数名 `forty_two` に続けて、呼び出し演算子`()`を続けて、 `forty_two()` と書くことで、関数を実行することが出来ました。

もし、`forty_two` と関数名が付けられていなかった場合、つまり以下のように書かれていた場合には、どうやって呼び出せば良いのでしょうか。

**▼answer_to_life_the_universe_and_everything.js**

```
function () {
  alert("42")
}
```

名前の無い関数を「無名関数」と言います。名前を付けておくと、後からいつでも何度でも呼び出せる利点はありますが、一度限りしか使わない関数やすぐに実行してしまう関数も、JavaScript では多用されます。無名関数を呼び出し実行する為には、次のようにします。


`function 〜 }` までの関数全体を、グループ化演算子 `()丸括弧`で囲むことで呼び出したい関数を指し示します。そして、その指し示した関数を呼び出すために、関数呼び出し演算子`()`を適用させることで、指し示した無名関数を実行することができます。

**▼answer_to_life_the_universe_and_everything.js**

```
function () { alert("42") }
~~~~~~~~~~~~~~~~~~~~~~~~~~~
  この部分が関数の本体

 ↓

(function () { alert("42") })
~~                          ~~
 関数本体を()で囲むことで、呼び出したい関数を明示します


 ↓

(function () { alert("42") })()
                            ~~~~
                            関数呼出演算子()を
                            関数本体に適用させることで、
                            関数が実行されます。
```

上のコードでは分かりやすいよう、関数本体を一行に書きました。通常通り改行して書くと次のようになります。「生命、宇宙、そして万物についての究極の疑問の答え」として「42」が表示されますので、ご確認下さい。

**▼answer_to_life_the_universe_and_everything.js**

```
(function () {
  alert("42")
})()
```

最初に紹介した即時実行関数の書き方と同じになっています。

```
(function () {
  // コードいろいろ
})()
```




先に紹介した `hanabira.js` は、次のように書かれていました。

![](Answer_to_Life.png)

```
(
() => {
  const NUMBER_OF_HANABIRAS = 50
  ...
}
)()
```

::: {.text-right}
**生命、宇宙、そして万物についての<br>
:::

![](white_space.png)

今なら

```
(
```

で始まり、

```
)()
```

で終わっている理由が理解できるのではないでしょうか。

