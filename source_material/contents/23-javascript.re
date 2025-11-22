= JavaScript 後編

//abstract{
この章では、JavaScriptについて、より深く学んでいきます。じゃんけんの為のアルゴリズムを工夫したり、コンピュータの手をアニメーションのように切り替えたり、勝敗表示を行ったりと順次コードを追加し、じゃんけんゲームを創り上げます。
//}

== じゃんけんのアルゴリズム


=== リファクタリング（再構成）

さて @<file>{janken06.js} ですが、だいぶプログラムが長くなってきました。より見通しの良い、分かりやすいコードとするために、ここで「**リファクタリング**」を行いましょう。

//quote{
//noindent
**リファクタリング**とは、ソフトウェア開発において、プログラムの動作や振る舞いを変えることなく、内部の設計や構造を見直し、コードを書き換えたり書き直したりすること。@<fn>{fn-it}
//}

//footnote[fn-it][出典: IT用語辞典]

主なリファクタリング手法として、

  1. **定数**の利用
  2. **関数化**
  3. **アルゴリズム改善**

などがあります。

//blankline

定数の利用についてはすでに行っていますね。コンピュータにとって、@<code>{0}, @<code>{1}, @<code>{2} は分かりやすくて扱いやすいですが、人にとっては、@<code>{グー,} @<code>{チョキ,} @<code>{パー} のほうが分かりやすいので、@<code>{GUU}、@<code>{CHOKI}、@<code>{PAA}と、数値に名前を付けて理解しやすくしています。

じゃんけんの勝敗判定部分も長く成っていますので、この部分を取り出して関数化しましょう。
#@# にすることにより、全体を見やすくしましょう。
#@#
#@# //quote{
#@# 関数とは、ある一連の手続き（文の集まり）を1つの処理としてまとめる機能です。 関数を利用することで、同じ処理を毎回書くのではなく、一度定義した関数を呼び出すことで同じ処理を実行できます。また、一度しか行わない処理でも、適切な命名を行って、処理の詳細に関する部分をプログラムの呼び出し元から分離することで、コード全体の見通しが良くなる利点が得られます。
#@# //}

また、より良いアルゴリズムを考えることで、9通りの @<code>{if文} を綺麗に書き直していきましょう。

#@# 「コンピュータプログラミングにおいて、プログラムの外部から見た動作を変えずにソースコードの内部構造を整理すること」を、「**リファクタリング**」 @<fn>{fn-r}と言います。
#@# //footnote[fn-r][出典：Wikipedia]


=== じゃんけんのアルゴリズム

@<href>{https://staku.designbits.jp/check-janken/, じゃんけん勝敗判定アルゴリズムの思い出} というブログがあります。こちらを参考に、より簡潔に書けるよう、じゃんけんのアルゴリズムを考察していきましょう。

素直に @<code>{if文} を書くと、プレイヤーが「グー」の時、「チョキ」の時、「パー」の時のそれぞれにつき、コンピュータが「グー」の時、「チョキ」の時、「パー」の時と、全部で9通りの勝敗判定が必要でした。

@<code>{if文} を書き連ねず、もう少し簡潔に書けるか調べるために、勝敗表にまとめて見ましょう。

//table[][じゃんけんの勝敗表]{
.	グー   0	チョキ 1	パー   2
-----------------
グー   0	相子	勝ち	負け
チョキ 1	負け	相子	勝ち
パー   2	勝ち	負け	相子
//}

自分の手と相手の手が等しい時に「@<ruby>{相子,あいこ}」になることが分かります。
等しいかどうかは、**引き算してその結果が0になるかどうか**で判定できますので、**自分の手から相手の手を引き算**してみます。
すると次の表が得られます。

//table[][じゃんけんの勝敗表 【引き算】]{
.	グー   0	チョキ 1	パー   2
-----------------
グー   0	相子   0	勝ち  -1	負け  -2
チョキ 1	負け   0	相子   0	勝ち  -1
パー   2	勝ち   2	負け   1	相子   0
//}


相子になるのは 0の時、負けになるのは -2か1の時、勝ちになるのは -1か2の時であることが判明しました。これで9通りではなく、5通りの @<code>{if文} で良いと分かりました。
//blankline
もう少し考察を加えます。勝ち負け相子の3通りの判定をする為に「本当に」5通りの @<code>{if文} が必要でしょうか。

-2と1は3つ離れており、-1と2も3つ離れていますので、3を足してみます。すると、

  * 相子になるのは、0 か 3 の時、
  * 負けになるのは、1 か 4 の時、
  * 勝ちになるのは、2 か 5 の時となります。

なにか法則性がありそうです。もう少し3を足してみます。

  * 相子になるのは、0 か 3 か 6 か  9 の時、
  * 負けになるのは、1 か 4 か 7 か 10 の時、
  * 勝ちになるのは、2 か 5 か 8 か 11 の時となります。

法則性が見えてきたでしょうか？

#@# つまり

 * 相子になるのは、3の倍数の時、
 * 負けになるのは、3の倍数に1を足した数の時、
 * 勝ちになるのは、3の倍数に2を足した数の時 のようです。

3の倍数か否かは、**3で割って余りが0**であることで判定できます。
3の倍数に1を足した数かは、**3で割って余りが1**であること、
3の倍数に2を足した数かは、**3で割って余りが2**であることで判定できますね。

#@# 3の倍数に1を足した数であるか調べるにはどうしたら良いでしょうか？
#@#
#@#  * 3で割ってみて、余りが1であれば、3の倍数に1を足した数です。
#@#
#@# 3の倍数に2を足した数であるか調べるにはどうしたら良いでしょうか？
#@#
#@#  * 3で割ってみて、余りが2であれば、3の倍数に2を足した数です。

//blankline
つまり
#@# 以上の考察から、
#@# まとめると

//sideimage[operator][25mm][sep=5mm,side=R]{

 * 相子になるのは、3で割って余りが0の時、
 * 負けになるのは、3で割って余りが1の時、
 * 勝ちになるのは、3で割って余りが2の時であることが 分かりました。

余りを求める演算のことを「**剰余演算**」と言い、@<code>{JavaScript}では、 @<code>{@<ruby>{%,パーセント}}演算子で剰余演算ができます。
//}


まとめると勝敗判定には、

 * 最初は9通りの @<code>{if文} が必要でした。
 * @<code>{自分の手 - 相手の手}と引き算することで、5通りになりました。
 * さらに @<code>{(自分の手 - 相手の手 + 3) % 3} と余りを求めることで3通りになりました。

とっても簡潔にまとまりましたね。

#@# //tsize[latex][|c|c|]
#@# //table[][演算子の種類]{
#@# .	演算子
#@# -----------------
#@# 加算	@<code>{+}
#@# 減算	@<code>{-}
#@# 乗算	@<code>{*}
#@# 除算	@<code>{/}
#@# 剰余	@<code>{%}
#@# //}


//blankline

それでは、プレイヤーの手とコンピュータの手を渡すと、相子が @<code>{0}, 負けが @<code>{1}, 勝ちが @<code>{2} と、結果を返す関数を作りましょう。

//list[][]{
// プレイヤーの手とコンピュータの手が与えられると、
// 0: あいこ 1: 負け 2: 勝ち を返す関数
const judge = (player, computer) => {
  return (player - computer + 3) % 3
}
//}

この勝敗判定関数 @<code>{judge} を使うと、延々と続いていた @<code>{if文} がとっても短くなりそうです。

//list[][][]{
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
//}

せっかくですので「あいこ」「負け」「勝ち」を表す定数も使って、完成したのが @<file>{janken07.js} です。

//list[][janken07.js][1]{
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
//}

とてもすっきり、分かりやすくなりましたね。 @<fn>{fn-sukkiri}
//footnote[fn-sukkiri][@<file>{janken06.js} では、@<code>{GUU}、@<code>{CHOKI}、@<code>{PAA}の定数宣言も行っていましたが、もう使わなくなったので、削除しています。]


===[column] グローバル変数


**グローバル変数**とは、プログラムのどの部分からでも、その値を読み取ったり変更したりできる変数のことです。関数やブロックの外 @<fn>{fn-block} で宣言された変数がグローバル変数となります。具体的には次のコードがそうです。
//footnote[fn-block][「ブロック」とは、繰り返しや条件分岐の@<code>{{\}}のことです。]

//list[][janken07][lineno=13,linenowidth=3]{
// computer の手を 乱数で設定
let **computer** = rand(0, 2)
//}

14行目で宣言された @<code>{computer}という変数は、32行目でも呼び出されています。

//list[][janken07][lineno=31,linenowidth=3]{
// judge関数により、勝敗判定結果を得る。
const result = judge(player, **computer**)
//}

グローバル変数の利点と欠点をまとめてみましょう。

==== グローバル変数の利点
 : データの共有
異なる関数やブロック間でデータを簡単に共有することができます。同じデータを複数の場所で使用する場合に便利です。

 : コードの簡潔さ
グローバル変数を使用することで、関数間でのデータの受け渡しが不要になり、コードが簡潔になることがあります。

 : 理解容易さ
プログラミングを始めたばかりの人にとっては、グローバル変数を使うことでデータの流れを理解しやすくなる場合があります。

==== グローバル変数の欠点
 : 名前の衝突
グローバル変数はプログラム全体で共有されるため、異なる部分で同じ名前の変数を使うと意図しない動作が発生する可能性があります。これを「名前の衝突」と呼びます。

 : デバッグの難しさ
グローバル変数はどこからでもアクセス可能であるため、値がどこで変更されたかを特定するのが難しくなります。これはバグの原因となりやすいです。

 : モジュール性の低下
同じコードを何度も書くのは手間です。そこで、他のプログラムでも再利用できるよう部品(モジュール)化を図ります。グローバル変数に依存するコードは、再利用性が低くなり、再利用の際に問題が生じやすくなります。

 : 予期しない副作用
グローバル変数は変更することが容易です。変更した結果、他の部分の動作に予期しない影響を与えることがあります。これにより、プログラム全体の安定性が低下します。

 : スコープの拡大による複雑さ
グローバル変数はスコープ(アクセス可能な範囲)が広いため、プログラムのどこかで変更される可能性が常にあります。これにより、プログラムの全体像を把握するのが難しくなり、特に大規模なプロジェクトでは管理が困難になります。

==== まとめ
グローバル変数は便利な場合もありますが、その欠点を理解し、慎重に使用することが重要です。名前の衝突やデバッグの難しさ、予期しない副作用などを避けるために、できるだけ通常のローカル変数を使用するようにしましょう。

グローバル変数を使わないように書き直すことももちろん可能ですが、プログラム全体が短いことから、欠点よりも利点が勝ると判断し、グローバル変数を用いています。

===[/column]



== コンピュータの手の表示
さてコンピュータの手ですが、内部的には @<code>{0}なら「グー」、 @<code>{1}なら「チョキ」、 @<code>{2}なら「パー」に変わるようになりました。ですが、画面に表示されている絵は「グー」の絵のままです。コンピュータの手に合わせて、表示されている絵も変わるようにしましょう。

@<code>{HTML}で次のように書くことで、グーの絵が表示されていました。
//list[][index.html][51]{
<img id="hand" src="images/guu.webp" alt="グー">
//}

ですので、コンピュータの手が @<code>{1} なら、
//list[][index.html][51]{
<img id="hand" src="images/choki.webp" alt="チョキ">
//}

@<code>{2} なら、
//list[][index.html][51]{
<img id="hand" src="images/paa.webp" alt="パー">
//}

と@<code>{HTML}を変更したら、表示される絵を変更できます。

#@#
#@#
#@# 今までは、コンピュータの手は表示されていませんでしたので、
#@#
#@# //emlist[][html]{
#@# <img id="computer_hand_type" src="guu.png">
#@# //}
#@# 出来ればこれも、無作為に変わるようにしたいものです。

=== 動的にHTMLを更新する

@<code>{JavaScript}では、書かれた@<code>{HTML}をプログラム上から**動的**に書き換えることができます。 @<fn>{fn-te}
//footnote[fn-te][プレイヤーがHTMLのどのボタンを押したのかをJavaScriptで取得しましたが、今回はその反対に、JavaScriptに合わせてHTMLを書き換えます。]

そのためのコードは次のようになります。

//list[][]{
// イメージ要素を取得する
let img = document.querySelector("#hand")
// 取得したイメージ要素のsrc属性を変更する
img.src = "images/choki.webp"
//}

#@# 1行目は以前に触れた乱数でコンピュータの手を決定しています。6行目と7行目がポイントとなるところです。

1行目の @<code>{let img = document.querySelector("#hand")} で、@<code>{HTML}ファイルに書いた イメージ要素 を取得します。
@<code>{img} 変数には、 @<code>{<img id="hand" src="images/guu.webp" alt="グー">} が入っています。

2行目では、取得したイメージ要素の @<code>{src} 属性の値を更新します。

@<code>{HTML}では @<code>{src}属性に指定した画像が表示されるので、@<code>{src="images/guu.webp"} と書けばグーの画像が、@<code>{src="images/choki.webp"} と書けばチョキの画像を表示させることができます。

#@# @<code>{const img = document.getElementById("computer_hand_type")} として、取得した要素を @<code>{img} という変数に格納します。
#@#
#@# そして取得した @<code>{img} 要素の @<code>{src} 属性を @<code>{choki.png} にすればチョキの画像を、 @<code>{paa.png} にすればパーの画像を表示させることができます。

ですので @<code>{JavaScript}で取得した要素の @<code>{src}属性を書き換えてあげれば画像を変更できます。

#@# //list[][]{
#@# img.src = "images/choki.webp"
#@# //}

=== 配列

さて、画像の変更方法が分かりましたので、コンピューターの手に応じて画像を変えるようにしましょう。例えば次のコードを書けば動作しそうです。

//list[][]{
if (computer === 0) {
  img.src = "images/guu.webp"
} else if (computer === 1) {
  img.src = "images/choki.webp"
} else {
  img.src = "images/paa.webp"
}
//}

前に学んだ @<code>{if} 文を活用したコードで、もちろんこれでも動作します。

**リファクタリング**の考え方を取り入れて、もう少し良いコードが書けないか、考えてみましょう。








//blankline
//sideimage[makunouchi][40mm][sep=5mm,side=R]{
**配列**という**データ構造**があります。
グーの画像、チョキの画像、パーの画像 この三つの画像をひとまとめにして扱う時に重宝するデータ構造です。

幕の内弁当を思い浮かべてください。お弁当箱の中にはご飯や美味しいおかずが入っています。プログラミングの世界では、この「容れ物」に当たるものを「配列」と呼び、ご飯やおかずなど「内容物」に当たるものを「要素」と呼びます。

漆塗りの豪華な重箱の中に、「グー」「チョキ」「パー」の画像が入っている幕の内弁当を想像してください。
//}

配列（容れ物）の中の要素（おかず）を取り出すためには**@<ruby>{添字,そえじ**}で指定します。一番目のおかずが食べたい、二番目のおかずが欲しいと指示するようなものです。@<code>{JavaScript}では、添字は @<code>{0} から始まりますので、0番目の要素が欲しい、1番目の要素が欲しいと順に指定します。 @<fn>{fn-index}
//footnote[fn-index][人にとっては一番目、二番目と、一から数えるのが馴染みがありますが、コンピュータでは添字は0から扱うのが一般的です。]

=== 配列の作成

それでは @<code>{JavaScript} での配列を作ってみましょう。
まず、じゃんけんの手の画像を入れる配列として、 @<code>{images} という変数を宣言します。

そして初期値として @<code>{"images/guu.webp", "images/choki.webp", "images/paa.webp"} 三つの画像名を表す要素があるようにします。 @<fn>{fn-images}
//footnote[fn-images][「グー」「チョキ」「パー」三つの画像は、@<code>{images}ディレクトリ内に配置しているので、@<code>{images/guu.webp}のように、先頭に @<code>{images/} を付けています。]

つまり、次のようになります。
//list[][じゃんけん画像配列の宣言と初期値の設定]{
const images = ["images/guu.webp", "images/choki.webp", "images/paa.webp"]
//}

#@# @<code>{const images = [];} と書くと、中身が空っぽの配列を作成することができます。
#@# @<code>{const images = ["guu.png", "choki.png", "paa.png"]} と書くと、 @<code>{配列 images} の中に、 @<code>{"guu.png", "choki.png", "paa.png"} の三つの要素があるようになります。

=== 添字で配列内の要素を指定する

配列内の各要素を指定するには、配列名の後に @<code>{[何番目かを指示する数字]} と書きます。この「何番目かを指示する数字」のことを、**添字(そえじ)**と呼びます。

配列の要素は、 @<code>{0, 1, 2} と  @<code>{0} から数え始めますので、 @<code>{images[0]} と書くと@<code>{"images/guu.webp"} を指定でき、@<code>{images[1]} と書くと@<code>{"images/choki.webp"} を指定できます。逆に、@<code>{"images/paa.webp"}が欲しい時には、@<code>{images[2]} と書くと取得できます。

配列はとってもよく使う基礎的な**データ構造**で、少し大きなプログラムでは不可欠です。是非、習得なさってください。

//note[]{
配列と並ぶ重要な**データ構造**に、 **連想配列** (ハッシュや辞書とも呼ばれます)があります。配列は添字と呼ばれる番号で要素を取得しますが、連想配列は番号の代わりにキーと呼ばれる文字列で要素を取得するデータ構造です。紙幅の関係上、詳細は割愛いたしますが、さまざまな学習資源がありますので、ぜひ学んでみてください。
//}

配列から要素の取得するためには添字を使えば良いことを学びました。この添字が無作為に@<code>{0, 1, 2}と変わるならば、「グー」「チョキ」「パー」が表示できます。既にじゃんけん用の乱数を自作したので、添字に使いましょう。

//list[][]{
// 乱数を利用して、コンピュータの手を無作為に決定する
computer = rand(0, 2)
//}

ですので、乱数で選ばれた画像ファイル名は、次のようになります。

//list[][]{
const filename = images[computer]
//}

よって、以下のように書くことで、画像ファイルを都度都度変更することができます。

//list[][]{
img.src = filename
//}

まとめると、次のようなコードになります。
//list[][一行ずつ分けて書いたコード]{
computer       = rand(0, 2)
images         = ["images/guu.webp", "images/choki.webp", "images/paa.webp"]
const filename = images[computer]
img            = document.querySelector("#hand")
img.src        = filename
//}

これを、それぞれの変数に代入するのではなく、凝縮して書くと次のようになります。
//list[][凝縮して書いたコード]{
computer = rand(0, 2)
document.querySelector("#hand").src =
         ["images/guu.webp", "images/choki.webp", "images/paa.webp"][computer]
//}

圧縮されているので、最初のうちは分かりにくいかもしれません。最初のうちは一行ずつわけて書かれても構いません。ご自身の分かりやすいと感じる書き方で、少しずつ実践して習得していきましょう。

=== alt属性の更新
@<code>{alt}属性とは、@<code>{HTML}の@<code>{<img>}タグに使用される属性で、画像が表示できない場合に表示される代替(**alt**ernative)テキストのことです。
視覚障害を持つ利用者は、読み上げソフトを用いてウェブページを閲覧しますが
、@<code>{alt}属性の文字列(テキスト)が読み上げられることで、画像の内容を理解することができます。

じゃんけんゲームでは、あまり活躍することはないのですが、ウェブサイト作成の心得として、@<code>{alt}属性も設定するようにしましょう。

以上をまとめると、@<code>{computer}の手を乱数で設定するようにしたプログラムは次のようになります。

//list[][janken08.js][lineno=1-31&64-65]{
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
**\**}

// プレイヤーの手とコンピュータの手が与えられると、
// 0: 引き分け 1: 負け 2: 勝ち を返す関数
const judge = (player, computer) => {
  return (player - computer + 3) % 3
}
(以下同じ)
**// コンピュータの手を変更する処理を呼び出す**
**shuffleHand()**
//}

最後の65行目、@<code>{shuffleHand()}はとても大切です。17行目で **computerの手を乱数で設定する関数**として @<code>{shuffleHand()} を定義しましたが、関数は呼び出されることで初めて機能します。プログラムの最後に @<code>{shuffleHand()} を呼び出すことで、無作為にコンピュータの手が変更され、画像も変わるようになります。


== アニメーション機能

@<code>{JavaScript}からコンピュータの手を切り替える方法を実装しましたので、コンピュータの出した手が画面に表示されるようになりました。そしてこのままですと、コンピュータの出した手（＝例えば「チョキ」）がそのまま画面に表示されていますので、プレイヤーは「グー」を出せば勝てることがすぐに分かります。これではちょっと面白くありません。

コンピュータの手が「「グー」「チョキ」「パー」と切り替わるよう、アニメーション機能を実装して行きましょう。

#@# 「グー、チョキ、パー」と1秒間に24回絵が切り替わるとアニメーションの完成です。
=== アニメーションの原理

人間の目は、短時間の間に見た画像を一時的に保持する特性があります。これを「残像効果」と言います。少しずつ異なる静止した画像を連続して表示することで、あたかも動いているように見せることができます。これがアニメーションの原理です。

それでは、1秒間に何枚の画像を表示したら良いのでしょうか。1秒間に表示される画像の枚数をフレームレートと言いますが、一般的な映画やテレビアニメでは、毎秒24フレーム（fps: frames per second）が使用されますが、テレビの標準（NTSC）では30fps、オンラインビデオでは60fpsなどもあります。

ここでは、切り替わっていることがはっきり分かるよう、1秒間に4枚の画像を切り替えることにしましょう。つまり @<code>{FPS = 4}に設定しましょう。

#@# //quote{
#@# //noindent
#@# fps 【frames per second】 フレーム毎秒
#@# fpsとは、動画のなめらかさを表す単位の一つで、画像や画面を1秒間に何回書き換えているかを表したもの。24fpsの動画は1秒あたり24枚の静止画で構成され、約0.041秒（41ミリ秒）ごとに画像を切り替えて再生される。 @<fn>{fn-fps}
#@# //}
#@# //footnote[fn-fps][出典：IT用語辞典]

=== 一定周期ごとに繰り返す

それでは、1秒間に4枚の画像を切り替えるにはどうしたら良いでしょうか。
一定周期ごとに、処理を繰り返したいときに使う関数として、JavaScriptでは、 @<code>{setTimeout} という関数が用意されています。使い方は次の通りです。

//list[][]{
setTimeout(タイマーが満了した後に実行したい関数,
           指定した関数を実行する前に待つ時間をミリ秒単位で指定)
//}

**指定した関数を実行する前に待つ時間をミリ秒単位で指定**と書かれています。1秒間に4枚の画像を切り替えるので、@<code>{250}と指定すれば良いのですが、これは**マジックナンバー**と呼ばれる書き方で、お勧めできない書き方です。

//note[マジックナンバーとは]{
マジックナンバー（Magic Number）とは、プログラムの中で特定の意味を持つ数値が、直接コードに埋め込まれているものを指します。コードの可読性や保守性を低下させるため、避けるべきとされています。
//}

==== マジックナンバーの問題点

 : 可読性の低下
   「可読性」とは、コードの読みやすさ、理解しやすさのことです。数値が直接埋め込まれていると、その数値が何を意味しているのかが一目では分かりにくくなります。後からコードを読む人や、自分自身が後で見返したときに理解しづらくなります。

 : 保守性の低下
    「保守性」とは、ソフトウェアやシステムが長期的に維持管理しやすい性質のことです。マジックナンバーを用いると、プログラムの仕様が変更された場合（例えばより滑らかにアニメーションする）、どこにその数値が使われているのかを全て見つけ出して変更する必要があります。複数箇所に同じ数値が埋め込まれている場合、変更漏れが発生する@<ruby>{虞,おそれ}があります。

そこで@<code>{FPS}という定数を宣言しましょう。
意味が明確になりますし、もう少し滑らかにアニメーションをしたい場合にはこの値を変更するのみで可能になります。

//list[][定数宣言][]{
const FPS = 4 // 一秒間あたり、4コマ表示する
//}

そうすると @<code>{250} ではなく @<code>{1000 / FPS} と書けば良いですね。

続いて **タイマーが満了した後に実行したい関数**の部分です。
ここでは、コンピュータの手を切り替える関数 @<code>{shffleHand} を実行したいので、そのまま書きましょう。

以上をまとめると、次のようになります。

//list[][janken09.js][lineno=7&18-30]{
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
//}

先に作成した @<file>{janken08.js} をもとに、7行目に @<code>{FPS} 定数を追加しています。また、29行目で 一定間隔で、shuffleHand 関数を呼び続けるよう、 @<code>{setTimeout} 関数を記述しています。

これで、アニメーションできるようになりました。


== アニメーションを停止する

=== 簡潔に書かれたif文の条件式

いつもアニメーション表示中ではなく、「開始」ボタンを押した時に、アニメーションが始まり、プレイヤーが手を選んだら、アニメーションが停止するようにしましょう。

アニメーション実行中か、否かを表す変数として、 @<code>{isPause} 変数 @<fn>{is} を用いることにしましょう。そうすると、先に作成した @<code>{shuffleHand} 関数は、@<code>{if文}を用いて、次のように書くことができます。

//footnote[is][Animation is pause? が 変数名の由来です。真偽値を返す変数を名付ける際に、@<code>{is○○} とする慣習があります。 ]

//list[][]{
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
//}

@<code>{if(!isPause)} という書き方が見慣れないかもしれませんので、解説します。

今の状態がアニメーション停止中なら @<code>{true} という意味で、@<code>{let isPause = true} と先頭に書きました。ですので普通に @<code>{if文}を書くと、@<code>{if (isPause === false)} と書くことで、**停止中でないなら** という条件を表すことができます。 @<code>{isPause} が @<code>{false} の時（停止中の時）には、@<code>{if (false === false)} つまり、 @<code>{if (true)} となりますので、 @<code>{if文} が実行されます。

以上を踏まえ、最初に提示された @<code>{if(!isPause)} というコードを見ていきましょう。@<code>{isPause} が @<code>{false} の時（停止中の時）には、@<code>{if(!false)} となります。

@<code>{!}(感嘆符・エクスクラメーションマーク) は、真偽値を反転させる演算子(@<code>{NOT演算子})です。真(@<code>{true})なら偽@<code>{false}に、偽@<code>{false}なら真@<code>{true}にします。ちょうど @<code>{-}(マイナス)演算子を付けることで、正なら負に、負なら正に反転することに似ています。

ですので @<code>{if(!false)} は、@<code>{if(true)} となりますので、@<code>{if文} が実行されます。

良く使う書き方ですので、習得しましょう。

=== アニメーション状態を設定する関数

アニメーション状態を保持する変数として、@<code>{isPause} という変数を定義しました。

アニメーションを開始したり、停止したりする都度、@<code>{isPause = false}、@<code>{isPause = true} と設定しても良いですが、直接、変数を操作するよりは、そのような関数を定義して、関数呼び出して設定することにしましょう。関数化することで、複数の変数を操作する場合や、操作する条件が複雑である場合、複数の箇所で設定が必要な場合などにもプログラムを作ることが楽になります @<fn>{fn-hoshusei} し、また、プログラム自体も読みやすくなります。 @<fn>{fn-kadokusei}

//footnote[fn-hoshusei][言い換えると「保守性」が向上します。]
//footnote[fn-kadokusei][「可読性」が向上します。]

切替アニメ停止や再開の為の関数は次のように書くことができます。

//list[][切替アニメ停止][]{
const pause = () => {
  isPause = true
}
//}

//list[][切替アニメ再開][]{
const resume = () => {
  isPause = false
}
//}

#@# 状態変数 @<code>{isPause} の値を変更するのみですので、簡単ですね。
@<code>{isPause} という状態変数に、@<code>{true}, または @<code>{false} をセットしているだけの関数ですが、 @<code>{pause 停止}、 @<code>{resume 再開} と名前を付けることで、コードを読むだけで意図を汲み取ることができ、とても分かりやすくなります。名前はとっても重要です。

=== 開始ボタンを押してアニメーション

開始ボタンを押したときに、アニメーションされるようにしましょう。先に定義した @<code>{resume}関数を呼ぶと良いです。

「グー」ボタンを押したときに、@<code>{jankenHandler} 関数が呼ばれるようにするコードを最初の方で紹介しました。開始ボタンを押したときに @<code>{resume}関数が呼ぶのも同様に書くことができます。

//list[][開始ボタンを押してアニメ再開する][]{
// playボタンがクリックされた時には、resume関数を実行して、
// じゃんけんの切替アニメが再開(resume)されるようにする
const playButton = document.querySelector("#play")
playButton.addEventListener("click", resume)
//}

=== 勝敗判定でアニメーションを止める

コンピュータの手に対し、プレイヤーが自分の手を選ぶと勝敗判定が行われます。
この時にもコンピュータの手はアニメーションで様々な手が表示され続けています。勝敗判定のときにはアニメーションを止めるようにしましょう。勝敗判定は @<code>{jankenHandler} 関数が司っていますから、この中で停止処理を書けば良さそうです。

//list[][][]{
// じゃんけんの勝ち負けの結果を表示する関数
const jankenHandler = (event) => {
  **// 切替アニメ停止処理実行**
  **pause()**
  (以下同じ)
//}

以上をまとめたプログラムは次のようになります。

//list[][janken10.js][1]{
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
**\**}

**// 切替アニメ再開**
**const resume = () => {**
**  isPause = false**
**\**}

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
  **\**}

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
//}

== 必ず違う手を出すようにする

開始ボタンを押すとアニメーションが開始するようになりました。また「グー」「チョキ」「パー」ボタンを押すとアニメーションが停止するようになりました。

しかし、「グー」のあとに「グー」が続いたりすることもあるので、アニメーションの動きが、カクカクして見えます。必ず違う手を出すように工夫しましょう。

=== アルゴリズムを考える

どのようなアルゴリズムが良いでしょうか。いろいろ考えることができます。例えば、前の手が「グー」(0)だったとすると、次の手は「チョキ」(1)か「パー」(2)の中から選ぶようにすると言う方法です。あるいは、前の手を覚えておいて、とにかく違う手が出るまでひたすら繰り返すと言う方法もあります。今回はこちらの方法で作ることにしてみましょう。

コンピュータの手を設定する機能は @<code>{shuffleHand}関数が担っていますので、この関数を更新しましょう。

//list[][janken11.js][29]{
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
    **\**}
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
//}

38行目の@<code>{while文}は、繰り返しを実現する基本的な構文です。現在の手を覚えておいて、乱数で選んだ次の手が、現在の手と同じ間、次の手を選ぶことを繰り返します。
違う手になったら、繰り返しから抜けて、42行目の処理に移ります。

それでは、実行してみましょう。滑らかなアニメーションになっているはずです。

== 勝敗更新機能の実装
最後に、勝敗更新機能を実装しましょう。

勝負の結果に応じて、○勝○敗を更新していきたいので、@<code>{jankenHandler}内に実装するのが良さそうです。

既に勝敗結果を得る処理は書いていますから、次のように書くと良いでしょう。

//list[][]{
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
//}

@<code>{updateScore} という関数を作って、その引数として、 @<code>{LOSE} 敗北か、 @<code>{WIN} 勝利を渡しています。実際の処理は、 @<code>{updateScore} 内で行っていますが、こうやって字面を読むだけでも処理の内容が分かり、コードの見通しがよくなります。

それでは @<code>{updateScore} 関数を次のように書きましょう。

//list[][updateScore関数][1]{
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
//}

解説していきます。

勝ち数、負け数は、HTML内で @<code>{<span id="win">0</span>} のように書いていました。JavaScriptで扱いやすいよう、ID属性を付与したので、 @<code>{document.querySelector("#win")} と書けばこの @<code>{win} 要素を取得できます。早速 @<code>{win} 変数に格納しましょう。

@<code>{win.textContent} と書くことで、 @<code>{<span id="win">0</span>} と書いていた「@<code>{0}」を取得することができます。この「@<code>{0}」は、**文字列としての「@<code>{"0"**」} です。
一般にプログラミングでは、文字列としての @<code>{"0"} と、数値としての @<code>{0} は区別されます。

//tip[文字列 "0" と 数値 0 は区別される]{
"0" + "1" // =>  "01" と文字列の追加が行われます。
 0  +  1  // =>   1  と、数値演算が行われます。
//}

@<code>{Number関数} を使うと、文字列としての @<code>{"0"} から、整数値としての @<code>{0} に変換できます。整数値としての @<code>{0} が得られたら「@<code>{+ 1}」と足し算して、勝ち数を一つ増やします。

これで、@<code>{<span id="win">0</span>} と書かれていた元々のHTMLを @<code>{<span id="win">1</span>} へと更新することができます。


== じゃんけんプログラム完成

長い道のりを経て、遂に完成したじゃんけんプログラム。
ソースコードは次の通りです。

@<file>{janken01.js}から始まって少しずつ機能追加をして参りました。
コメントも含めて125行と比較的短いプログラムですが、今までの歩みがぎっしり詰まった力作です。一行一行、味わってください。

//list[][janken12.js][1]{
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
//}
