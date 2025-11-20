# 桜吹雪

:::{.chapter-lead}
古来より日本人の心をとらえてはなさない「さくら」。
春の桜吹雪、夏の蛍の乱舞、秋の紅葉、冬のしんしんと降り積もる雪。
季節を彩る演出を、JavaScript を使って実現します。  
:::



## HTML

![](sakura-fubuki.png)

作例例は右のようになります。
さくらの花びらがひらひらと舞う演出効果を、CSS と JavaScript を使って実現しています。

//blankline
`https://actyway.com/8351` (現在リンク切れ) を元に適宜改変いたしました。[動作例](https://wave-improve.netlify.app/sakura_fubuki/index.html)と[ソースコード](https://github.com/Atelier-Mirai/wave-improve/tree/master/sakura_fubuki) です。ご参考になれば幸いです。

**▼index.html**

```
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>桜吹雪</title>
  </head>

  <body>
    <!-- 略 -->

    <!-- 桜吹雪の効果 -->
    <link rel="stylesheet" href="sakura.css">
    <script src="sakura.js"></script>
  </body>
</html>
```

HTMLは今回の主眼ではございませんので省略しておりますが、
`</body>` 直前に桜吹雪のための CSS と JavaScript を読み込んでいます。


## CSS

`sakura.css` は、桜の花びらの色やひらひら回転するCSSアニメーションのためのCSSです。

**▼sakura.css**

```
html,
body {
  overflow-x: hidden;
  overflow-x: clip;
  position: relative;
}

/* 花びらの形 */
.hana {
  position: absolute;
  height: 0;
  width: 0;
  border: 10px solid transparent;
  border-radius: 15px;
  border-top-right-radius: 0;
  border-bottom-left-radius: 0;
}

.hana::after {
  content: "";
  display: block;
  position: absolute;
  top: -7px;
  left: -7px;
  height: 0;
  width: 0;
  border: 10px solid transparent;
  border-radius: 15px;
  border-top-right-radius: 0;
  border-bottom-left-radius: 0;
  transform: rotate(15deg);
}

/* 花びらの色 */
.t1, .t1::after { border-color: #fef4f4; }
.t2, .t2::after { border-color: #ffd1d9; }
.t3, .t3::after { border-color: #ffc0cb; }
.t4, .t4::after { border-color: #ffc0cb; }
.t5, .t5::after { border-color: #ffafbd; }

/* 花びらがひらひら回転する動き */
.a1 { animation: a1 12s infinite; }
.a2 { animation: a2 10s infinite; }
.a3 { animation: a3  9s infinite; }
.a4 { animation: a4  9s infinite; }
.a5 { animation: a5  8s infinite; }

@keyframes a1 {
  from { transform: rotate(  0deg) scale(.9); }
  50%  { transform: rotate(270deg) scale(.9); }
  to   { transform: rotate(  1deg) scale(.9); }
}
@keyframes a2 {
  from { transform: rotate( -90deg) scale(.8); }
  50%  { transform: rotate(-360deg) scale(.8); }
  to   { transform: rotate( -89deg) scale(.8); }
}
@keyframes a3 {
  from { transform: rotate( 30deg) scale(.7); }
  50%  { transform: rotate(300deg) scale(.7); }
  to   { transform: rotate( 29deg) scale(.7); }
}
@keyframes a4 {
  from { transform: rotate(-120deg) scale(.6); }
  50%  { transform: rotate(-390deg) scale(.6); }
  to   { transform: rotate(-119deg) scale(.6); }
}
@keyframes a5 {
  from { transform: rotate( 60deg) scale(.5); }
  50%  { transform: rotate(330deg) scale(.5); }
  to   { transform: rotate( 59deg) scale(.5); }
}
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

最初(`from`)は、回転角0度(`rotate(  0deg)`)で、
中ほど(`50%`)は、回転角270度(`rotate(  270deg)`)となり、
最後に(`to`)は、回転角1度(`rotate(  1deg)`)になるまで回転します。

`scale(.9)`とありますので、 `.hana` で作成した花びらの大きさより少し小さ目(`90%`)の花びらとなります。


## JavaScript

JavaScript は、(主に)ブラウザ上で動くプログラミング言語です。 HTMLの要素を取得し、追加や編集、削除など様々に制御することができるので、動きのあるウェブサイトを作ることが出来るようになります。

今回の桜吹雪の例では、花びら用の `<div>` を50枚生成し、上から下へ落としていきます。左右への揺らぎも表現したいので、一定回数右へ移動したら左へ移動するようにしています。

![](furigana_js.png)

JavaScript に関しては、初心者の方向けに、コードの意味を逐次解説した [スラスラ読める JavaScript ふりがなプログラミング](https://www.amazon.co.jp/dp/4295003859) がございますので、ご一読下さい。

今回作成した `sakura.js` では、`class`構文を用いて、花びら座標計算用オブジェクトを作成し、`花びら<div>`に反映させるようにしています。
せっかくの機会ですので、ここで少し「オブジェクト指向」についてご紹介します。


### オブジェクト指向

**オブジェクト指向**は、ソフトウェア開発とコンピュータプログラミングのために用いられる考え方である。元々は特定のプログラミングパラダイムを説明するために考案された言葉であり、その当時の革新的技術であったGUI（グラフィカル・ユーザーインターフェース）とも密接に関連していた。明確な用語としては1970年代に誕生し、1990年頃にはソフトウェア開発の総合技術としての共通認識を確立している。

**オブジェクト**とは、**データ構造とその専属手続きを一つにまとめたもの** / **情報資源とその処理手順を一つにまとめたもの** を指している。データとプロセスを個別に扱わずに、双方を一体化したオブジェクトを基礎要素にし、メッセージと形容されるオブジェクト間の相互作用を重視して、ソフトウェア全体を構築しようとする考え方がオブジェクト指向である。

オブジェクト指向（object-oriented）という言葉自体は、1972年から80年にかけてプログラミング言語「Smalltalk」を開発したゼロックス社パロアルト研究所の計算機科学者アラン・ケイが、その言語設計を説明する過程で誕生している。大学院時代のケイがプログラミング言語「Simula」に感化されて日夜プログラミング・アーキテクチャの思索に耽っていた1967年頃、今何をしているのかと尋ねてきた知人に対して「object-oriented programmingだよ」とその時の造語で答えたのが原点であるという。

**オブジェクト指向プログラミング(OOP)** とは、「**オブジェクト**」という概念に基づいたプログラミングパラダイムの一つである。 オブジェクトは、任意個数のフィールド （属性、プロパティまたは変数）で構成されるデータと、任意個数の（メソッドまたは関数）で構成されるコードのひとまとまりで構成される。

オブジェクトの特徴として、オブジェクト自身の手続きが自身のデータフィールドを読み書きできることが挙げられる(オブジェクトにはthisやselfという概念がある)。また、OOPでは、相互に作用するオブジェクトを組み合わせてプログラムを設計する。OOP言語のありかたは多様であるが、最も一般的といえるものは、オブジェクトがクラス(型)のインスタンス(実例)であり、また、オブジェクトの型もクラスとして規定されるクラスベースといわれるものである。 [^207]

[^207]: 出典: ウィキペディア


### オブジェクト指向 練習

それでは、理解を深めるために練習していきましょう。

`JavaScript` も、オブジェクト指向言語ですので、クラス(型・雛型)からインスタンス(実例)を作成し、コーディングすることが出来ます。

簡単な例ですが、四角形とその面積を求める例です。

クラスを作成せずに、単純に次のように書いても、面積を求めることが出来ます。

しかしながら、四角形１、四角形２、四角形３・・・とたくさんの図形がある場合にはどうでしょう。
あるいは、三角形や円の面積を求めたい時もあるかもしれません。

クラスを使ったコーディングの有用性が掴めるのではないでしょうか。


### sakura.js のご紹介

それでは、花びらクラスを用いたコードのご紹介です。
花びらの位置情報と、それを操作するためのメソッド(関数)、そして実際に画面表示するには、花びらdiv要素(DOM)に反映させることが必要ですから、そのためのメソッドも備わっています。

紙幅の都合上、詳細は割愛いたしますが、雰囲気だけでも掴んでいただければ幸いです。

**▼sakura.js**

```
/*=====================================================================
 櫻の花びらが舞い散るJavaScript
 https://actyway.com/8351 を元に作成
=====================================================================*/

(
() => {
  // =========================================================================
  // 定数宣言等
  // =========================================================================
  const NUMBER_OF_HANABIRAS = 50; // 花びらの枚数
  const FPS                 = 24; // 一秒間に24回 動かす
  const HANABIRA_HEIGHT     = 30; // 花びらの高さ 回転するので最大値は 30px
  const HANABIRA_WIDTH      = 30; // 花びらの幅 回転するので最大値は 30px
  const HANABIRA_Z_BASE     = 10000; // 花びらの z-index の基準値

  // ウィンドウの高さ
  const windowHeight = window.innerHeight;
  // ウィンドウの幅(スクロールバー除く)
  const windowWidth  = document.documentElement.clientWidth
  // スクロール位置
  let scroll         = document.documentElement.scrollTop || document.body.scrollTop;
  // スクロール時のイベント登録 (スクロール時に花びらがウィンドウ内に納まる為に)
  document.addEventListener('scroll', () => {
    scroll = document.documentElement.scrollTop || document.body.scrollTop;
  }, false);

  // =========================================================================
  // 乱数関数
  // min 以上 max 以下の乱数を返す (integer)
  // min 以上 max 未満の乱数を返す (float)
  // =========================================================================
  let rand = (min, max, type = "integer") => {
    if(type === "integer"){
      return Math.floor(Math.random() * (max-min+1)) + min;
    } else {
      return Math.random() * (max-min) + min;
    }
  };

  // =========================================================================
  // 花びらクラスの宣言
  // =========================================================================
  class Hanabira {
    // コンストラクタ(構築子)
    constructor(id, x, y, z, tremorMax, fallingSpeed, className) {
      this.id           = id;
      this.x            = x;
      this.y            = y;
      this.z            = z;
      this.tremorMax    = tremorMax;
      this.fallingSpeed = fallingSpeed;
      this.className    = className;

      this.direction    = "right";
      this.tremorCount  = 0;
    }

    // 際大揺らぎ回数に達しているか？
    isTremorMax() {
      return (this.tremorCount === this.tremorMax)
    }

    // 揺らぎ方向転換
    directionSwitch() {
      if (this.direction === "right") {
        this.direction = "left";
      } else {
        this.direction = "right";
      }
    }

    // 花びらの位置に関して
    // 空中にいるか？(ウィンドウ内か？)
    isInTheAir() {
      return (this.y < scroll + windowHeight - HANABIRA_HEIGHT);
    }

    // 地面に着いたか？
    isOnTheGround() {
      return !this.isInTheAir();
    }

    // 右端にいるか？
    isOnTheRightEdge() {
      return (this.x + HANABIRA_WIDTH >= windowWidth);
    }

    // 左端にいるか？
    isOnTheLeftEdge() {
      // 花びら幅の半分の位置なら、左端と見做す。
      return (this.x <= HANABIRA_WIDTH / 2);
    }

    // 花びらの x, y 座標を更新する
    move() {
      // 花びらの位置がウィンドウ内なら
      if (this.isInTheAir()) {
        // 同一方向へtremorMax回移動したなら、移動方向を反転させる
        if (this.isTremorMax()) {
          this.directionSwitch();
          this.tremorCount = 0;
        }

        // 左右に移動する
        let deltaX   = rand(0.3, 0.6, "float");
        let signFlag = (this.direction === "right" ? +1 : -1);
        this.x      += signFlag * deltaX;

        // もし右端にいるなら、左端に移動する
        if (this.isOnTheRightEdge()) {
          this.x = HANABIRA_WIDTH / 2;
        }

        // もし左端にいるなら、右端に移動する
        if (this.isOnTheLeftEdge()) {
          this.x = windowWidth - HANABIRA_WIDTH;
        }

        // 移動回数を増やす
        this.tremorCount++;

        // 落下速度分を加える
        this.y += this.fallingSpeed;

      // もし地面に着いているなら、上に戻す
      } else if (this.isOnTheGround()) {
        this.y = scroll;
        this.x = rand(0, windowWidth - HANABIRA_WIDTH);
      }
    }

    // 位置情報を DOM に反映させる
    applyPositionInformation(domHanabira) {
      domHanabira.setAttribute('style', `top: ${this.y}px; left: ${this.x}px; z-index: ${this.z};`);
    }
  }

  // =========================================================================
  // 初期化処理
  // 櫻の花びらのための新しい div 要素を作成し、body の末尾に追加
  // 作業用の 花びらインスタンスも生成する
  // =========================================================================
  const divSakura = document.createElement("div");
  document.body.after(divSakura);

  let domHanabiras = []; // 花びら要素の配列
  let jsHanabiras  = []; // 花びらjsオブジェクトの配列
  // それぞれの花びらについて、位置等の初期設定を行う
  for(let i = 0; i < NUMBER_OF_HANABIRAS; i++){
    let id           = i;
    let x            = rand(HANABIRA_WIDTH / 2, windowWidth - HANABIRA_WIDTH);
    let y            = rand(-500, 0) + scroll;
    let z            = HANABIRA_Z_BASE + i;
    let tremorMax    = rand(15, 50);
    let fallingSpeed = rand(1, 3);
    let className    = `hana t${rand(1, 5)} a${rand(1, 5)}`;
    let jsHanabira   = new Hanabira(id, x, y, z, tremorMax, fallingSpeed, className);
    jsHanabiras[i]   = jsHanabira;

    // 花びらの div を作る
    let domHanabira = document.createElement('div');
    // 初期表示位置を設定する
    jsHanabira.applyPositionInformation(domHanabira);
    // ID 付与
    domHanabira.id = i;
    // ランダムに生成した花びらの色とアニメーションのための css class を設定する
    domHanabira.setAttribute('class', jsHanabira.className);
    // 作成した花びらをDOMに追加、画面に表示されるようにする
    divSakura.appendChild(domHanabira);
    // 扱いやすくするために、花びら要素達を配列に格納
    domHanabiras[i] = domHanabira;
  }

  // =========================================================================
  // メイン処理
  // 生成したそれぞれの花びらの位置情報を更新し、画面に反映する。
  // =========================================================================
  setInterval(() => {
    for(let jsHanabira of jsHanabiras) {
      // 各花びらに対し、位置情報の更新処理を行う
      jsHanabira.move();

      // js オブジェクトの位置情報を、domオブジェクトモデルの位置に反映する。
      let id          = jsHanabira.id;
      let domHanabira = domHanabiras[id];
      jsHanabira.applyPositionInformation(domHanabira);
    }
  }, 1000 / FPS);
}
)();
```


## 春夏秋冬

春の桜吹雪、夏の蛍の乱舞、秋の紅葉、冬のしんしんと降り積もる雪。
日本は、四季折々の豊かな自然に恵まれた豊かな国です。

桜吹雪は上記で実現いたしました。

[particles.js](https://vincentgarreau.com/particles.js/)というライブラリを利用すると、夏の蛍や冬の雪のような効果を簡単に実現できます。


### 夏の蛍

[ホタルが舞う](https://coco-factory.jp/ugokuweb/move02/5-7/) にて紹介されていますので、参考になさってください。


### 秋の紅葉

[JSとCSSで落ち葉をひらひらと舞わせるエフェクトを実装する方法](https://web-dev.tech/front-end/javascript/autumn-leaves-falling-effect/) にて紹介されていますので、参考になさってください。


### 冬の雪

[particles.js【公式】](https://vincentgarreau.com/particles.js/#snow) にて紹介されています。右上 CodePen より、ソースコードも見られますので、参考になさってください。

