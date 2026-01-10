# JavaScript 後編

:::{.chapter-lead}
この章では、JavaScriptについて、より深く学んでいきます。じゃんけんの為のアルゴリズムを工夫したり、コンピュータの手をアニメーションのように切り替えたり、勝敗表示を行ったりと順次コードを追加し、じゃんけんゲームを創り上げます。
:::



## じゃんけんのアルゴリズム


### リファクタリング（再構成）

さて `janken06.js` ですが、だいぶプログラムが長くなってきました。より見通しの良い、分かりやすいコードとするために、ここで「**リファクタリング**」を行いましょう。

> **リファクタリング**とは、ソフトウェア開発において、プログラムの動作や振る舞いを変えることなく、内部の設計や構造を見直し、コードを書き換えたり書き直したりすること。[^92]


[^92]: 出典: IT用語辞典

主なリファクタリング手法として、

1. **定数**の利用
2. **関数化**
3. **アルゴリズム改善**

などがあります。


定数の利用についてはすでに行っていますね。コンピュータにとって、`0`, `1`, `2` は分かりやすくて扱いやすいですが、人にとっては、`グー,` `チョキ,` `パー` のほうが分かりやすいので、`GUU`、`CHOKI`、`PAA`と、数値に名前を付けて理解しやすくしています。

じゃんけんの勝敗判定部分も長く成っていますので、この部分を取り出して関数化しましょう。

また、より良いアルゴリズムを考えることで、9通りの `if文` を綺麗に書き直していきましょう。


### じゃんけんのアルゴリズム

[じゃんけん勝敗判定アルゴリズムの思い出](https://staku.designbits.jp/check-janken/) というブログがあります。こちらを参考に、より簡潔に書けるよう、じゃんけんのアルゴリズムを考察していきましょう。

素直に `if文` を書くと、プレイヤーが「グー」の時、「チョキ」の時、「パー」の時のそれぞれにつき、コンピュータが「グー」の時、「チョキ」の時、「パー」の時と、全部で9通りの勝敗判定が必要でした。

`if文` を書き連ねず、もう少し簡潔に書けるか調べるために、勝敗表にまとめて見ましょう。

<div class="table">
<p class="caption">じゃんけんの勝敗表</p>
<table>
<tr class="hline"><th></th><th>グー   0</th><th>チョキ 1</th><th>パー   2</th></tr>
<tr class="hline"><td>グー   0</td><td>相子</td><td>勝ち</td><td>負け</td></tr>
<tr class="hline"><td>チョキ 1</td><td>負け</td><td>相子</td><td>勝ち</td></tr>
<tr class="hline"><td>パー   2</td><td>勝ち</td><td>負け</td><td>相子</td></tr>
</table>
</div>
自分の手と相手の手が等しい時に「相子（あいこ）」になることが分かります。
等しいかどうかは、**引き算してその結果が0になるかどうか**で判定できますので、**自分の手から相手の手を引き算**してみます。
すると次の表が得られます。

<div class="table">
<p class="caption">じゃんけんの勝敗表 【引き算】</p>
<table>
<tr class="hline"><th></th><th>グー   0</th><th>チョキ 1</th><th>パー   2</th></tr>
<tr class="hline"><td>グー   0</td><td>相子   0</td><td>勝ち  -1</td><td>負け  -2</td></tr>
<tr class="hline"><td>チョキ 1</td><td>負け   0</td><td>相子   0</td><td>勝ち  -1</td></tr>
<tr class="hline"><td>パー   2</td><td>勝ち   2</td><td>負け   1</td><td>相子   0</td></tr>
</table>
</div>
相子になるのは 0の時、負けになるのは -2か1の時、勝ちになるのは -1か2の時であることが判明しました。これで9通りではなく、5通りの `if文` で良いと分かりました。


もう少し考察を加えます。勝ち負け相子の3通りの判定をする為に「本当に」5通りの `if文` が必要でしょうか。

-2と1は3つ離れており、-1と2も3つ離れていますので、3を足してみます。すると、

* 相子になるのは、0 か 3 の時、
* 負けになるのは、1 か 4 の時、
* 勝ちになるのは、2 か 5 の時となります。

なにか法則性がありそうです。もう少し3を足してみます。

* 相子になるのは、0 か 3 か 6 か  9 の時、
* 負けになるのは、1 か 4 か 7 か 10 の時、
* 勝ちになるのは、2 か 5 か 8 か 11 の時となります。

法則性が見えてきたでしょうか？

* 相子になるのは、3の倍数の時、
* 負けになるのは、3の倍数に1を足した数の時、
* 勝ちになるのは、3の倍数に2を足した数の時 のようです。

3の倍数か否かは、**3で割って余りが0**であることで判定できます。
3の倍数に1を足した数かは、**3で割って余りが1**であること、
3の倍数に2を足した数かは、**3で割って余りが2**であることで判定できますね。


つまり

![](operator.webp)

* 相子になるのは、3で割って余りが0の時、
* 負けになるのは、3で割って余りが1の時、
* 勝ちになるのは、3で割って余りが2の時であることが 分かりました。

余りを求める演算のことを「**剰余演算**」と言い、`JavaScript`では、 `%（パーセント）`演算子で剰余演算ができます。

まとめると勝敗判定には、

* 最初は9通りの `if文` が必要でした。
* `自分の手 - 相手の手`と引き算することで、5通りになりました。
* さらに `(自分の手 - 相手の手 + 3) % 3` と余りを求めることで3通りになりました。

とっても簡潔にまとまりましたね。


それでは、プレイヤーの手とコンピュータの手を渡すと、相子が `0`, 負けが `1`, 勝ちが `2` と、結果を返す関数を作りましょう。

```
// プレイヤーの手とコンピュータの手が与えられると、
// 0: あいこ 1: 負け 2: 勝ち を返す関数
const judge = (player, computer) => {
  return (player - computer + 3) % 3
}
```

この勝敗判定関数 `judge` を使うと、延々と続いていた `if文` がとっても短くなりそうです。

```
// judge関数により、勝敗判定結果を得る。
const result = judge(player, computer)
// 判定できているか、確認する。
console.log(`result:   ${result}`)

if (result === 0) {
  alert("あいこです!")
} else if (result === 1) {
  alert("あなたの負けです!")
} else {
  alert("あなたの勝ちです!")
}
```

せっかくですので「あいこ」「負け」「勝ち」を表す定数も使って、完成したのが `janken07.js` です。

<span class="caption">▼janken07.js</span>

```
// 定数宣言
// プログラム内で共通して使う定数を宣言する。
const DRAW  = 0 // あいこ
const LOSE  = 1 // 負け
const WIN   = 2 // 勝ち

// 乱数関数
// rand(0, 2)と呼ぶと 0, 1, 2 と グーチョキパー の乱数を返す
const rand = (min, max) => {
  return Math.floor(Math.random() * (max - min + 1)) + min
}

// computer の手を 乱数で設定
let computer = rand(0, 2)
// 設定できているか、確認する。
console.log(`computer: ${computer}`)

// プレイヤーの手とコンピュータの手が与えられると、
// 0: あいこ 1: 負け 2: 勝ち を返す関数
const judge = (player, computer) => {
  return (player - computer + 3) % 3
}

// じゃんけんの勝ち負けの結果を表示する関数
const jankenHandler = (event) => {
  // プレイヤーの手の取得
  const player = Number(event.target.value)
  // 取得できているか、確認する。
  console.log(`player:   ${player}`)

  // judge関数により、勝敗判定結果を得る。
  const result = judge(player, computer)
  // 判定できているか、確認する。
  console.log(`result:   ${result}`)

  if (result === DRAW) {
    alert("あいこです!")
  } else if (result === LOSE) {
    alert("あなたの負けです!")
  } else {
    alert("あなたの勝ちです!")
  }
}

// イベントリスナの設定
// グー・チョキ・パー ぞれぞれのボタンが押されたときに、
// jankenHandler関数が呼ばれるように、登録する。
const guuButton   = document.querySelector("#guu")
const chokiButton = document.querySelector("#choki")
const paaButton   = document.querySelector("#paa")
guuButton.addEventListener("click", jankenHandler)
chokiButton.addEventListener("click", jankenHandler)
paaButton.addEventListener("click", jankenHandler)
```

とてもすっきり、分かりやすくなりましたね。 [^93]

[^93]: `janken06.js` では、`GUU`、`CHOKI`、`PAA`の定数宣言も行っていましたが、もう使わなくなったので、削除しています。


::: {.column}
グローバル変数
**グローバル変数**とは、プログラムのどの部分からでも、その値を読み取ったり変更したりできる変数のことです。関数やブロックの外 [^94] で宣言された変数がグローバル変数となります。具体的には次のコードがそうです。

[^94]: 「ブロック」とは、繰り返しや条件分岐の`{}`のことです。

<span class="caption">▼janken07</span>

```
// computer の手を 乱数で設定
let **computer** = rand(0, 2)
```

14行目で宣言された `computer`という変数は、32行目でも呼び出されています。

<span class="caption">▼janken07</span>

```
// judge関数により、勝敗判定結果を得る。
const result = judge(player, **computer**)
```

グローバル変数の利点と欠点をまとめてみましょう。


#### グローバル変数の利点

<dl>
<dt>データの共有</dt>
<dd>
</dd>
</dl>

異なる関数やブロック間でデータを簡単に共有することができます。同じデータを複数の場所で使用する場合に便利です。

<dl>
<dt>コードの簡潔さ</dt>
<dd>
</dd>
</dl>

グローバル変数を使用することで、関数間でのデータの受け渡しが不要になり、コードが簡潔になることがあります。

<dl>
<dt>理解容易さ</dt>
<dd>
</dd>
</dl>

プログラミングを始めたばかりの人にとっては、グローバル変数を使うことでデータの流れを理解しやすくなる場合があります。


#### グローバル変数の欠点

<dl>
<dt>名前の衝突</dt>
<dd>
</dd>
</dl>

グローバル変数はプログラム全体で共有されるため、異なる部分で同じ名前の変数を使うと意図しない動作が発生する可能性があります。これを「名前の衝突」と呼びます。

<dl>
<dt>デバッグの難しさ</dt>
<dd>
</dd>
</dl>

グローバル変数はどこからでもアクセス可能であるため、値がどこで変更されたかを特定するのが難しくなります。これはバグの原因となりやすいです。

<dl>
<dt>モジュール性の低下</dt>
<dd>
</dd>
</dl>

同じコードを何度も書くのは手間です。そこで、他のプログラムでも再利用できるよう部品(モジュール)化を図ります。グローバル変数に依存するコードは、再利用性が低くなり、再利用の際に問題が生じやすくなります。

<dl>
<dt>予期しない副作用</dt>
<dd>
</dd>
</dl>

グローバル変数は変更することが容易です。変更した結果、他の部分の動作に予期しない影響を与えることがあります。これにより、プログラム全体の安定性が低下します。

<dl>
<dt>スコープの拡大による複雑さ</dt>
<dd>
</dd>
</dl>

グローバル変数はスコープ(アクセス可能な範囲)が広いため、プログラムのどこかで変更される可能性が常にあります。これにより、プログラムの全体像を把握するのが難しくなり、特に大規模なプロジェクトでは管理が困難になります。


#### まとめ

グローバル変数は便利な場合もありますが、その欠点を理解し、慎重に使用することが重要です。名前の衝突やデバッグの難しさ、予期しない副作用などを避けるために、できるだけ通常のローカル変数を使用するようにしましょう。

グローバル変数を使わないように書き直すことももちろん可能ですが、プログラム全体が短いことから、欠点よりも利点が勝ると判断し、グローバル変数を用いています。
:::



## コンピュータの手の表示

さてコンピュータの手ですが、内部的には `0`なら「グー」、 `1`なら「チョキ」、 `2`なら「パー」に変わるようになりました。ですが、画面に表示されている絵は「グー」の絵のままです。コンピュータの手に合わせて、表示されている絵も変わるようにしましょう。

`HTML`で次のように書くことで、グーの絵が表示されていました。

<span class="caption">▼index.html</span>

```
<img id="hand" src="images/guu.webp" alt="グー">
```

ですので、コンピュータの手が `1` なら、

<span class="caption">▼index.html</span>

```
<img id="hand" src="images/choki.webp" alt="チョキ">
```

`2` なら、

<span class="caption">▼index.html</span>

```
<img id="hand" src="images/paa.webp" alt="パー">
```

と`HTML`を変更したら、表示される絵を変更できます。


### 動的にHTMLを更新する

`JavaScript`では、書かれた`HTML`をプログラム上から**動的**に書き換えることができます。 [^95]

[^95]: プレイヤーがHTMLのどのボタンを押したのかをJavaScriptで取得しましたが、今回はその反対に、JavaScriptに合わせてHTMLを書き換えます。

そのためのコードは次のようになります。

```
// イメージ要素を取得する
let img = document.querySelector("#hand")
// 取得したイメージ要素のsrc属性を変更する
img.src = "images/choki.webp"
```

1行目の `let img = document.querySelector("#hand")` で、`HTML`ファイルに書いた イメージ要素 を取得します。
`img` 変数には、 `<img id="hand" src="images/guu.webp" alt="グー">` が入っています。

2行目では、取得したイメージ要素の `src` 属性の値を更新します。

`HTML`では `src`属性に指定した画像が表示されるので、`src="images/guu.webp"` と書けばグーの画像が、`src="images/choki.webp"` と書けばチョキの画像を表示させることができます。

ですので `JavaScript`で取得した要素の `src`属性を書き換えてあげれば画像を変更できます。


### 配列

さて、画像の変更方法が分かりましたので、コンピューターの手に応じて画像を変えるようにしましょう。例えば次のコードを書けば動作しそうです。

```
if (computer === 0) {
  img.src = "images/guu.webp"
} else if (computer === 1) {
  img.src = "images/choki.webp"
} else {
  img.src = "images/paa.webp"
}
```

前に学んだ `if` 文を活用したコードで、もちろんこれでも動作します。

**リファクタリング**の考え方を取り入れて、もう少し良いコードが書けないか、考えてみましょう。


![](makunouchi.webp)

**配列**という**データ構造**があります。
グーの画像、チョキの画像、パーの画像 この三つの画像をひとまとめにして扱う時に重宝するデータ構造です。

幕の内弁当を思い浮かべてください。お弁当箱の中にはご飯や美味しいおかずが入っています。プログラミングの世界では、この「容れ物」に当たるものを「配列」と呼び、ご飯やおかずなど「内容物」に当たるものを「要素」と呼びます。

漆塗りの豪華な重箱の中に、「グー」「チョキ」「パー」の画像が入っている幕の内弁当を想像してください。

配列（容れ物）の中の要素（おかず）を取り出すためには**添字（そえじ）**で指定します。一番目のおかずが食べたい、二番目のおかずが欲しいと指示するようなものです。`JavaScript`では、添字は `0` から始まりますので、0番目の要素が欲しい、1番目の要素が欲しいと順に指定します。 [^96]

[^96]: 人にとっては一番目、二番目と、一から数えるのが馴染みがありますが、コンピュータでは添字は0から扱うのが一般的です。


### 配列の作成

それでは `JavaScript` での配列を作ってみましょう。
まず、じゃんけんの手の画像を入れる配列として、 `images` という変数を宣言します。

そして初期値として `"images/guu.webp", "images/choki.webp", "images/paa.webp"` 三つの画像名を表す要素があるようにします。 [^97]

[^97]: 「グー」「チョキ」「パー」三つの画像は、`images`ディレクトリ内に配置しているので、`images/guu.webp`のように、先頭に `images/` を付けています。

つまり、次のようになります。

<span class="caption">▼じゃんけん画像配列の宣言と初期値の設定</span>

```
const images = ["images/guu.webp", "images/choki.webp", "images/paa.webp"]
```


### 添字で配列内の要素を指定する

配列内の各要素を指定するには、配列名の後に `[何番目かを指示する数字]` と書きます。この「何番目かを指示する数字」のことを、**添字(そえじ)**と呼びます。

配列の要素は、 `0, 1, 2` と  `0` から数え始めますので、 `images[0]` と書くと`"images/guu.webp"` を指定でき、`images[1]` と書くと`"images/choki.webp"` を指定できます。逆に、`"images/paa.webp"`が欲しい時には、`images[2]` と書くと取得できます。

配列はとってもよく使う基礎的な**データ構造**で、少し大きなプログラムでは不可欠です。是非、習得なさってください。


[note] <b></a>

配列と並ぶ重要な**データ構造**に、 **連想配列** (ハッシュや辞書とも呼ばれます)があります。配列は添字と呼ばれる番号で要素を取得しますが、連想配列は番号の代わりにキーと呼ばれる文字列で要素を取得するデータ構造です。紙幅の関係上、詳細は割愛いたしますが、さまざまな学習資源がありますので、ぜひ学んでみてください。

[/note]


配列から要素の取得するためには添字を使えば良いことを学びました。この添字が無作為に`0, 1, 2`と変わるならば、「グー」「チョキ」「パー」が表示できます。既にじゃんけん用の乱数を自作したので、添字に使いましょう。

```
// 乱数を利用して、コンピュータの手を無作為に決定する
computer = rand(0, 2)
```

ですので、乱数で選ばれた画像ファイル名は、次のようになります。

```
const filename = images[computer]
```

よって、以下のように書くことで、画像ファイルを都度都度変更することができます。

```
img.src = filename
```

まとめると、次のようなコードになります。

<span class="caption">▼一行ずつ分けて書いたコード</span>

```
computer       = rand(0, 2)
images         = ["images/guu.webp", "images/choki.webp", "images/paa.webp"]
const filename = images[computer]
img            = document.querySelector("#hand")
img.src        = filename
```

これを、それぞれの変数に代入するのではなく、凝縮して書くと次のようになります。

<span class="caption">▼凝縮して書いたコード</span>

```
computer = rand(0, 2)
document.querySelector("#hand").src =
         ["images/guu.webp", "images/choki.webp", "images/paa.webp"][computer]
```

圧縮されているので、最初のうちは分かりにくいかもしれません。最初のうちは一行ずつわけて書かれても構いません。ご自身の分かりやすいと感じる書き方で、少しずつ実践して習得していきましょう。


### alt属性の更新

`alt`属性とは、`HTML`の`<img>`タグに使用される属性で、画像が表示できない場合に表示される代替(**alt**ernative)テキストのことです。
視覚障害を持つ利用者は、読み上げソフトを用いてウェブページを閲覧しますが
、`alt`属性の文字列(テキスト)が読み上げられることで、画像の内容を理解することができます。

じゃんけんゲームでは、あまり活躍することはないのですが、ウェブサイト作成の心得として、`alt`属性も設定するようにしましょう。

以上をまとめると、`computer`の手を乱数で設定するようにしたプログラムは次のようになります。

<span class="caption">▼janken08.js</span>

```
// 定数宣言
// プログラム内で共通して使う定数を宣言する。
const DRAW  = 0 // あいこ
const LOSE  = 1 // 負け
const WIN   = 2 // 勝ち

**// グローバル変数宣言**
**let computer       // コンピュータの手(グー:0, チョキ:1, パー:2)**

// 乱数関数
// rand(0, 2)と呼ぶと 0, 1, 2 と グーチョキパー の乱数を返す
const rand = (min, max) => {
  return Math.floor(Math.random() * (max - min + 1)) + min
}

**// computer の手を 乱数で設定する関数**
**const shuffleHand = () => {**
  **computer = rand(0, 2)**
  // 設定できているか、確認する。
  console.log(`computer: ${computer}`)

  **// コンピュータの手(0, 1, 2)によって、画像(や代替文字列)を変更する**
  **document.querySelector("#hand").src = ["images/guu.webp", "images/choki.webp", "images/paa.webp"][computer]**
  **document.querySelector("#hand").alt = ["グー", "チョキ", "パー"][computer]**
**}**

// プレイヤーの手とコンピュータの手が与えられると、
// 0: 引き分け 1: 負け 2: 勝ち を返す関数
const judge = (player, computer) => {
  return (player - computer + 3) % 3
}
(以下同じ)
**// コンピュータの手を変更する処理を呼び出す**
**shuffleHand()**
```

最後の65行目、`shuffleHand()`はとても大切です。17行目で **computerの手を乱数で設定する関数**として `shuffleHand()` を定義しましたが、関数は呼び出されることで初めて機能します。プログラムの最後に `shuffleHand()` を呼び出すことで、無作為にコンピュータの手が変更され、画像も変わるようになります。


## アニメーション機能

`JavaScript`からコンピュータの手を切り替える方法を実装しましたので、コンピュータの出した手が画面に表示されるようになりました。そしてこのままですと、コンピュータの出した手（＝例えば「チョキ」）がそのまま画面に表示されていますので、プレイヤーは「グー」を出せば勝てることがすぐに分かります。これではちょっと面白くありません。

コンピュータの手が「「グー」「チョキ」「パー」と切り替わるよう、アニメーション機能を実装して行きましょう。


### アニメーションの原理

人間の目は、短時間の間に見た画像を一時的に保持する特性があります。これを「残像効果」と言います。少しずつ異なる静止した画像を連続して表示することで、あたかも動いているように見せることができます。これがアニメーションの原理です。

それでは、1秒間に何枚の画像を表示したら良いのでしょうか。1秒間に表示される画像の枚数をフレームレートと言いますが、一般的な映画やテレビアニメでは、毎秒24フレーム（fps: frames per second）が使用されますが、テレビの標準（NTSC）では30fps、オンラインビデオでは60fpsなどもあります。

ここでは、切り替わっていることがはっきり分かるよう、1秒間に4枚の画像を切り替えることにしましょう。つまり `FPS = 4`に設定しましょう。


### 一定周期ごとに繰り返す

それでは、1秒間に4枚の画像を切り替えるにはどうしたら良いでしょうか。
一定周期ごとに、処理を繰り返したいときに使う関数として、JavaScriptでは、 `setTimeout` という関数が用意されています。使い方は次の通りです。

```
setTimeout(タイマーが満了した後に実行したい関数,
           指定した関数を実行する前に待つ時間をミリ秒単位で指定)
```

**指定した関数を実行する前に待つ時間をミリ秒単位で指定**と書かれています。1秒間に4枚の画像を切り替えるので、`250`と指定すれば良いのですが、これは**マジックナンバー**と呼ばれる書き方で、お勧めできない書き方です。


[note] <b>マジックナンバーとは</a>

マジックナンバー（Magic Number）とは、プログラムの中で特定の意味を持つ数値が、直接コードに埋め込まれているものを指します。コードの可読性や保守性を低下させるため、避けるべきとされています。

[/note]


#### マジックナンバーの問題点

<dl>
<dt>可読性の低下</dt>
<dd>
   「可読性」とは、コードの読みやすさ、理解しやすさのことです。数値が直接埋め込まれていると、その数値が何を意味しているのかが一目では分かりにくくなります。後からコードを読む人や、自分自身が後で見返したときに理解しづらくなります。
</dd>
<dt>保守性の低下</dt>
<dd>
    「保守性」とは、ソフトウェアやシステムが長期的に維持管理しやすい性質のことです。マジックナンバーを用いると、プログラムの仕様が変更された場合（例えばより滑らかにアニメーションする）、どこにその数値が使われているのかを全て見つけ出して変更する必要があります。複数箇所に同じ数値が埋め込まれている場合、変更漏れが発生する虞（おそれ）があります。
</dd>
</dl>

そこで`FPS`という定数を宣言しましょう。
意味が明確になりますし、もう少し滑らかにアニメーションをしたい場合にはこの値を変更するのみで可能になります。

<span class="caption">▼定数宣言</span>

```
const FPS = 4 // 一秒間あたり、4コマ表示する
```

そうすると `250` ではなく `1000 / FPS` と書けば良いですね。

続いて **タイマーが満了した後に実行したい関数**の部分です。
ここでは、コンピュータの手を切り替える関数 `shffleHand` を実行したいので、そのまま書きましょう。

以上をまとめると、次のようになります。

<span class="caption">▼janken09.js</span>

```
**const FPS = 4 // 一秒間あたり、4コマ表示する**

// computer の手を 乱数で設定する関数
const shuffleHand = () => {
  computer = rand(0, 2)
  // 設定できているか、確認する。
  console.log(`computer: ${computer}`)

  // コンピュータの手(0, 1, 2)によって、画像(や代替文字列)を変更する
  document.querySelector("#hand").src = ["images/guu.webp", "images/choki.webp", "images/paa.webp"][computer]
  document.querySelector("#hand").alt = ["グー", "チョキ", "パー"][computer]

  // 一定間隔で、shuffleHand 関数を呼び続ける
  **setTimeout(shuffleHand, 1000 / FPS)**
}
```

先に作成した `janken08.js` をもとに、7行目に `FPS` 定数を追加しています。また、29行目で 一定間隔で、shuffleHand 関数を呼び続けるよう、 `setTimeout` 関数を記述しています。

これで、アニメーションできるようになりました。


## アニメーションを停止する


### 簡潔に書かれたif文の条件式

いつもアニメーション表示中ではなく、「開始」ボタンを押した時に、アニメーションが始まり、プレイヤーが手を選んだら、アニメーションが停止するようにしましょう。

アニメーション実行中か、否かを表す変数として、 `isPause` 変数 [^98] を用いることにしましょう。そうすると、先に作成した `shuffleHand` 関数は、`if文`を用いて、次のように書くことができます。

[^98]: Animation is pause? が 変数名の由来です。真偽値を返す変数を名付ける際に、`is○○` とする慣習があります。 

```
**let isPause = true // 切替アニメが停止中なら真(true)**

// computer の手を 乱数で設定する関数
const shuffleHand = () => {
  **if(!isPause){ // 停止中でなければ**

    computer = rand(0, 2)
    // 設定できているか、確認する。
    console.log(`computer: ${computer}`)

    // コンピュータの手(0, 1, 2)によって、画像(や代替文字列)を変更する
    document.querySelector("#hand").src = ["images/guu.webp", "images/choki.webp", "images/paa.webp"][computer]
    document.querySelector("#hand").alt = ["グー", "チョキ", "パー"][computer]
  @<B{\}}

  // 一定間隔で、shuffleHand 関数を呼び続ける
  setTimeout(shuffleHand, 1000 / FPS)
}
```

`if(!isPause)` という書き方が見慣れないかもしれませんので、解説します。

今の状態がアニメーション停止中なら `true` という意味で、`let isPause = true` と先頭に書きました。ですので普通に `if文`を書くと、`if (isPause === false)` と書くことで、**停止中でないなら** という条件を表すことができます。 `isPause` が `false` の時（停止中の時）には、`if (false === false)` つまり、 `if (true)` となりますので、 `if文` が実行されます。

以上を踏まえ、最初に提示された `if(!isPause)` というコードを見ていきましょう。`isPause` が `false` の時（停止中の時）には、`if(!false)` となります。

`!`(感嘆符・エクスクラメーションマーク) は、真偽値を反転させる演算子(`NOT演算子`)です。真(`true`)なら偽`false`に、偽`false`なら真`true`にします。ちょうど `-`(マイナス)演算子を付けることで、正なら負に、負なら正に反転することに似ています。

ですので `if(!false)` は、`if(true)` となりますので、`if文` が実行されます。

良く使う書き方ですので、習得しましょう。


### アニメーション状態を設定する関数

アニメーション状態を保持する変数として、`isPause` という変数を定義しました。

アニメーションを開始したり、停止したりする都度、`isPause = false`、`isPause = true` と設定しても良いですが、直接、変数を操作するよりは、そのような関数を定義して、関数呼び出して設定することにしましょう。関数化することで、複数の変数を操作する場合や、操作する条件が複雑である場合、複数の箇所で設定が必要な場合などにもプログラムを作ることが楽になります [^99] し、また、プログラム自体も読みやすくなります。 [^100]

[^99]: 言い換えると「保守性」が向上します。

[^100]: 「可読性」が向上します。

切替アニメ停止や再開の為の関数は次のように書くことができます。

<span class="caption">▼切替アニメ停止</span>

```
const pause = () => {
  isPause = true
}
```

<span class="caption">▼切替アニメ再開</span>

```
const resume = () => {
  isPause = false
}
```

`isPause` という状態変数に、`true`, または `false` をセットしているだけの関数ですが、 `pause 停止`、 `resume 再開` と名前を付けることで、コードを読むだけで意図を汲み取ることができ、とても分かりやすくなります。名前はとっても重要です。


### 開始ボタンを押してアニメーション

開始ボタンを押したときに、アニメーションされるようにしましょう。先に定義した `resume`関数を呼ぶと良いです。

「グー」ボタンを押したときに、`jankenHandler` 関数が呼ばれるようにするコードを最初の方で紹介しました。開始ボタンを押したときに `resume`関数が呼ぶのも同様に書くことができます。

<span class="caption">▼開始ボタンを押してアニメ再開する</span>

```
// playボタンがクリックされた時には、resume関数を実行して、
// じゃんけんの切替アニメが再開(resume)されるようにする
const playButton = document.querySelector("#play")
playButton.addEventListener("click", resume)
```


### 勝敗判定でアニメーションを止める

コンピュータの手に対し、プレイヤーが自分の手を選ぶと勝敗判定が行われます。
この時にもコンピュータの手はアニメーションで様々な手が表示され続けています。勝敗判定のときにはアニメーションを止めるようにしましょう。勝敗判定は `jankenHandler` 関数が司っていますから、この中で停止処理を書けば良さそうです。

```
// じゃんけんの勝ち負けの結果を表示する関数
const jankenHandler = (event) => {
  **// 切替アニメ停止処理実行**
  **pause()**
  (以下同じ)
```

以上をまとめたプログラムは次のようになります。

<span class="caption">▼janken10.js</span>

```
// 定数宣言
// プログラム内で共通して使う定数を宣言する。
const DRAW  = 0 // あいこ
const LOSE  = 1 // 負け
const WIN   = 2 // 勝ち

const FPS   = 4 // 一秒間あたり、4コマ表示する

// グローバル変数宣言
let computer       // コンピュータの手(グー:0, チョキ:1, パー:2)
**let isPause = true // 切替アニメが停止中なら真(true)**

**// 切替アニメ停止**
**const pause = () => {**
**  isPause = true**
**}**

**// 切替アニメ再開**
**const resume = () => {**
**  isPause = false**
**}**

// 乱数関数
// rand(0, 2)と呼ぶと 0, 1, 2 と グーチョキパー の乱数を返す
const rand = (min, max) => {
  return Math.floor(Math.random() * (max - min + 1)) + min
}

// computer の手を 乱数で設定する関数
const shuffleHand = () => {
  **if(!isPause){ // 停止中でなければ**
    computer = rand(0, 2)
    // 設定できているか、確認する。
    console.log(`computer: ${computer}`)

    // コンピュータの手(0, 1, 2)によって、画像(や代替文字列)を変更する
    document.querySelector("#hand").src = ["images/guu.webp", "images/choki.webp", "images/paa.webp"][computer]
    document.querySelector("#hand").alt = ["グー", "チョキ", "パー"][computer]
  **}**

  // 一定間隔で、shuffleHand 関数を呼び続ける
  setTimeout(shuffleHand, 1000 / FPS)
}

// プレイヤーの手とコンピュータの手が与えられると、
// 0: 引き分け 1: 負け 2: 勝ち を返す関数
const judge = (player, computer) => {
  return (player - computer + 3) % 3
}

// じゃんけんの勝ち負けの結果を表示する関数
const jankenHandler = (event) => {
  **// 切替アニメ停止処理実行**
  **pause()**

  // プレイヤーの手の取得
  const player = Number(event.target.value)
  // 取得できているか、確認する。
  console.log(`player:   ${player}`)

  // judge関数により、勝敗判定結果を得る。
  const result = judge(player, computer)
  // 判定できているか、確認する。
  console.log(`result:   ${result}`)

  // 勝敗に応じ、メッセージ表示
  if (result === DRAW) {
    alert("あいこです!")
  } else if (result === LOSE) {
    alert("あなたの負けです!")
  } else {
    alert("あなたの勝ちです!")
  }
}

// イベントリスナの設定
// グー・チョキ・パー ぞれぞれのボタンが押されたときに、
// jankenHandler関数が呼ばれるように、登録する。
const guuButton   = document.querySelector("#guu")
const chokiButton = document.querySelector("#choki")
const paaButton   = document.querySelector("#paa")
guuButton.addEventListener("click", jankenHandler)
chokiButton.addEventListener("click", jankenHandler)
paaButton.addEventListener("click", jankenHandler)

**// playボタンがクリックされた時には、resume関数を実行して、**
**// じゃんけんの切替アニメが再開(resume)されるようにする**
**const playButton = document.querySelector("#play")**
**playButton.addEventListener("click", resume)**

// コンピュータの手を変更する処理を呼び出す
shuffleHand()
```


## 必ず違う手を出すようにする

開始ボタンを押すとアニメーションが開始するようになりました。また「グー」「チョキ」「パー」ボタンを押すとアニメーションが停止するようになりました。

しかし、「グー」のあとに「グー」が続いたりすることもあるので、アニメーションの動きが、カクカクして見えます。必ず違う手を出すように工夫しましょう。


### アルゴリズムを考える

どのようなアルゴリズムが良いでしょうか。いろいろ考えることができます。例えば、前の手が「グー」(0)だったとすると、次の手は「チョキ」(1)か「パー」(2)の中から選ぶようにすると言う方法です。あるいは、前の手を覚えておいて、とにかく違う手が出るまでひたすら繰り返すと言う方法もあります。今回はこちらの方法で作ることにしてみましょう。

コンピュータの手を設定する機能は `shuffleHand`関数が担っていますので、この関数を更新しましょう。

<span class="caption">▼janken11.js</span>

```
// computer の手を 乱数で設定する関数
const shuffleHand = () => {
  if(!isPause){ // 停止中でなければ

    **// 現在の手(current_hand)を保持**
    **let current_hand = computer**
    **// 次の手(next_hand)の候補を乱数で決定**
    **next_hand = rand(0, 2) // グー:0, チョキ:1, パー:2**
    **// 次の手の候補と現在の手が同じなら、違う手になるまで繰り返す**
    **while (next_hand === current_hand) {**
    **  next_hand = rand(0, 2)**
    **}**
    **// 乱数で選ばれた次の手を、コンピュータの手として設定する**
    **computer = next_hand**
    // 設定できているか、確認する。
    console.log(`computer: ${computer}`)

    // コンピュータの手(0, 1, 2)によって、画像(や代替文字列)を変更する
    document.querySelector("#hand").src = ["images/guu.webp", "images/choki.webp", "images/paa.webp"][computer]
    document.querySelector("#hand").alt = ["グー", "チョキ", "パー"][computer]
  }

  // 一定間隔で、shuffleHand 関数を呼び続ける
  setTimeout(shuffleHand, 1000 / FPS)
}
```

38行目の`while文`は、繰り返しを実現する基本的な構文です。現在の手を覚えておいて、乱数で選んだ次の手が、現在の手と同じ間、次の手を選ぶことを繰り返します。
違う手になったら、繰り返しから抜けて、42行目の処理に移ります。

それでは、実行してみましょう。滑らかなアニメーションになっているはずです。


## 勝敗更新機能の実装

最後に、勝敗更新機能を実装しましょう。

勝負の結果に応じて、○勝○敗を更新していきたいので、`jankenHandler`内に実装するのが良さそうです。

既に勝敗結果を得る処理は書いていますから、次のように書くと良いでしょう。

```
// 勝敗に応じ、メッセージ表示＆勝敗更新
if (result === DRAW) {
  alert("引き分けです!")
} else if (result === LOSE) {
  alert("あなたの負けです!")
  // 敗数を一つ増やす
  updateScore(LOSE)
} else {
  alert("あなたの勝ちです!")
  // 勝数を一つ増やす
  updateScore(WIN)
}
```

`updateScore` という関数を作って、その引数として、 `LOSE` 敗北か、 `WIN` 勝利を渡しています。実際の処理は、 `updateScore` 内で行っていますが、こうやって字面を読むだけでも処理の内容が分かり、コードの見通しがよくなります。

それでは `updateScore` 関数を次のように書きましょう。

<span class="caption">▼updateScore関数</span>

```
// 勝敗更新処理
const updateScore = (result) => {
  // HTML の勝ち表示要素、敗け表示要素を取得します。
  const win  = document.querySelector("#win")
  const lose = document.querySelector("#lose")

  // 勝ちの場合
  if (result === WIN) {
    // 勝数を一つ増やす
    win.textContent = Number(win.textContent) + 1
  } else if (result === LOSE) {
    lose.textContent = Number(lose.textContent) + 1
  }
}
```

解説していきます。

勝ち数、負け数は、HTML内で `<span id="win">0</span>` のように書いていました。JavaScriptで扱いやすいよう、ID属性を付与したので、 `document.querySelector("#win")` と書けばこの `win` 要素を取得できます。早速 `win` 変数に格納しましょう。

`win.textContent` と書くことで、 `<span id="win">0</span>` と書いていた「`0`」を取得することができます。この「`0`」は、**文字列としての「`"0"`」** です。
一般にプログラミングでは、文字列としての `"0"` と、数値としての `0` は区別されます。


[tip] <b>文字列 "0" と 数値 0 は区別される</a>

"0" + "1" // =>  "01" と文字列の追加が行われます。
0  +  1  // =>   1  と、数値演算が行われます。

[/tip]


`Number関数` を使うと、文字列としての `"0"` から、整数値としての `0` に変換できます。整数値としての `0` が得られたら「`+ 1`」と足し算して、勝ち数を一つ増やします。

これで、`<span id="win">0</span>` と書かれていた元々のHTMLを `<span id="win">1</span>` へと更新することができます。


## じゃんけんプログラム完成

長い道のりを経て、遂に完成したじゃんけんプログラム。
ソースコードは次の通りです。

`janken01.js`から始まって少しずつ機能追加をして参りました。
コメントも含めて125行と比較的短いプログラムですが、今までの歩みがぎっしり詰まった力作です。一行一行、味わってください。

<span class="caption">▼janken12.js</span>

```
// 定数宣言
// プログラム内で共通して使う定数を宣言する。
const DRAW  = 0 // あいこ
const LOSE  = 1 // 負け
const WIN   = 2 // 勝ち

const FPS   = 4 // 一秒間あたり、4コマ表示する

// グローバル変数宣言
let computer       // コンピュータの手(グー:0, チョキ:1, パー:2)
let isPause = true // グー・チョキ・パーの切替アニメを制御する為の変数

// 切替アニメ停止処理
const pause = () => {
  isPause = true
}

// 切替アニメ再開処理
const resume = () => {
  isPause = false
}

// 乱数関数
// rand(0, 2)と呼ぶと 0, 1, 2 と グーチョキパー の乱数を返す
const rand = (min, max) => {
  return Math.floor(Math.random() * (max - min + 1)) + min
}

// computer の手を 乱数で設定する関数
const shuffleHand = () => {
  if(!isPause){ // 停止中でなければ

    // 現在の手(current_hand)を保持
    let current_hand = computer
    // 次の手(next_hand)の候補を乱数で決定
    next_hand = rand(0, 2) // グー:0, チョキ:1, パー:2
    // 次の手の候補と現在の手が同じなら、違う手になるまで繰り返す
    while (next_hand === current_hand) {
      next_hand = rand(0, 2)
    }
    // 乱数で選ばれた次の手を、コンピュータの手として設定する
    computer = next_hand
    // 設定できているか、確認する。
    console.log(`computer: ${computer}`)

    // コンピュータの手(0, 1, 2)によって、画像(や代替文字列)を変更する
    document.querySelector("#hand").src = ["images/guu.webp", "images/choki.webp", "images/paa.webp"][computer]
    document.querySelector("#hand").alt = ["グー", "チョキ", "パー"][computer]
  }

  // 一定間隔で、shuffleHand 関数を呼び続ける
  setTimeout(shuffleHand, 1000 / FPS)
}

// プレイヤーの手とコンピュータの手が与えられると、
// 0: 引き分け 1: 負け 2: 勝ち を返す関数
const judge = (player, computer) => {
  return (player - computer + 3) % 3
}

// 勝敗更新処理
const updateScore = (result) => {
  // HTML の勝ち表示要素、敗け表示要素を取得します。
  const win  = document.querySelector("#win")
  const lose = document.querySelector("#lose")

  // 勝ちの場合
  if (result === WIN) {
    // 勝数を一つ増やす
    win.textContent = Number(win.textContent) + 1
  } else if (result === LOSE) {
    lose.textContent = Number(lose.textContent) + 1
  }
}

// じゃんけんの勝ち負けの結果を表示する関数
const jankenHandler = (event) => {
  // 「開始」ボタンが押された際に、ボタンの表示を「もう一度」に更新する
  const playButton = document.querySelector("#play")
  playButton.textContent = "もう一度"

  // 切替アニメ停止処理実行
  pause()

  // プレイヤーの手の取得
  const player = Number(event.target.value)
  // 取得できているか、確認する。
  console.log(`player:   ${player}`)

  // judge関数により、勝敗判定結果を得る。
  const result = judge(player, computer)
  // 判定できているか、確認する。
  console.log(`result:   ${result}`)

  // 勝敗に応じ、メッセージ表示＆勝敗更新
  if (result === DRAW) {
    alert("あいこです!")
  } else if (result === LOSE) {
    alert("あなたの負けです!")
    // 敗数を一つ増やす
    updateScore(LOSE)
  } else {
    alert("あなたの勝ちです!")
    // 勝数を一つ増やす
    updateScore(WIN)
  }
}

// イベントリスナの設定
// グー・チョキ・パー ぞれぞれのボタンが押されたときに、
// jankenHandler関数が呼ばれるように、登録する。
const guuButton   = document.querySelector("#guu")
const chokiButton = document.querySelector("#choki")
const paaButton   = document.querySelector("#paa")
guuButton.addEventListener("click", jankenHandler)
chokiButton.addEventListener("click", jankenHandler)
paaButton.addEventListener("click", jankenHandler)

// playボタンがクリックされた時には、resume関数を実行して、
// じゃんけんの切替アニメが再開(resume)されるようにする
const playButton = document.querySelector("#play")
playButton.addEventListener("click", resume)

// コンピュータの手を変更する処理を呼び出す
shuffleHand()
```

