= イベントリスナ

//abstract{
この章では「イベントリスナ」について学びます。これにより、利用者が何か操作をすることにより画面を変化させられるようになります。利用者とシステムとの間での相互作用・インタラクティブなサイトを創ることが出来るようになります。
//}

== イベントリスナ

=== イベントリスナとは
JavaScriptには、**イベントリスナ** と呼ばれる仕組みが有り、「何か操作を行った時」に指定した動作をする機能が備わっています。

それでは、**イベント**、**リスナー** とはなんでしょうか。それぞれの用語の意味を調べてみましょう。

//quote{
//noindent
プログラミングにおけるイベント (英: event) は、プログラム内で発生した動作・出来事、またそれらを表現する信号である。 メッセージあるいはアクション（動作）とも呼ばれる。
イベントの例としてウェブブラウザにおける「ページが読み込まれた時」、「クリック動作」、「スクロール操作」などさまざまなイベントがある。 @<fn>{fn-51}
//}
//footnote[fn-51][出典：Wikipedia]

//quote{
//noindent
リスナーとは、聞く人、聞き手、聴取者、聴講生、などの意味を持つ英単語。一般の外来語としてはラジオ（局/番組）の聴取者を意味する用法が有名である。

プログラミングの分野では、何らかのきっかけに応じて起動されるよう設定されたサブルーチンや関数、メソッドなどをイベントリスナー（event listener）あるいは単にリスナーという。例えば、「マウスがクリックされると起動するよう指定された関数」のことを「マウスクリックを待ち受けるリスナー」といったように呼ぶ。 @<fn>{fn-52}
//}
//footnote[fn-52][出典：IT用語辞典]

つまり、**イベントリスナー**とは次のようになります。

//quote{
//noindent
「ページ読み込みやクリック動作など、ウェブページで行われる様々な動作を常時起動し待ち受けて(聴取し続けて)、イベントが起きた時に指定された処理を行う関数のこと」@<fn>{fn-53}
//}
//footnote[fn-53][参考：フロントエンドエンジニアを目指す! JavaScript講座(9)イベントリスナーを使用する]

この**イベントリスナー** の仕組みを利用すると、「利用者」が「ボタン」を押したときに、何か処理を行うなど、利用者と相互作用を持てる、対話できるインタラクティブなサイトを作ることが出来ます。

=== イベントリスナの構文

MDN @<href>{https://developer.mozilla.org/ja/docs/Web/API/EventTarget/addEventListener, EventTarget: addEventListener()} より、抜粋して、ご紹介いたします。

//quote{
@<code>{addEventListener()} は @<code>{EventTarget} インターフェイスのメソッドで、ターゲットに特定のイベントが配信されるたびに呼び出される関数を設定します。

対象としてよくあるものは @<code>{Element}、@<code>{Document}、@<code>{Window} ですが、イベントに対応したあらゆるオブジェクトが対象になることができます。

//tip{
**構文**@<br>{}
@<code>{addEventListener(type, listener)}@<br>{}

**引数**@<br>{}

 : @<code>{　　type}
    対象とするイベントの種類を表す文字列です。 @<small>{@<href>{https://developer.mozilla.org/ja/docs/Web/Events, イベントリファレンス} で主要なイベントを確認できます。}

 : @<code>{　　listener}
    指定された種類のイベントが発生するときに通知を受け取るオブジェクト(JavaScriptの関数)。
//}
//}

=== イベントリスナで 「挨拶」を表示する

早速、使って見ることにしましょう。

@<code>{addEventListener()}コードによりイベントリスナを登録します。そして「挨拶」ボタンがクリックされると、「おはよう」と挨拶が表示されるようにします。

@<file>{greeting.html} は次のように準備します。
//list[][greeting.html][1]{
<!DOCTYPE html>
<html>
	<head>
		<meta charset="utf-8">
		<meta name="viewport" content="width=device-width">
		<title>挨拶</title>
		<script src="greeting.js" defer></script>
	</head>

	<body>
		<h1>挨拶</h1>

    <!-- 挨拶ボタン -->
    <button type="button" id="greeting">挨拶</button>
	</body>
</html>
//}

7行目で、 @<file>{greeting.js} を読み込み、14行目に挨拶操作用ボタンがある、とても簡単な例です。
---
@<file>{greeting.js} は次のように準備します。

//list[][eventlistener.js][1]{
// HTML中の挨拶ボタン要素を取得
const GREETING_BUTTON = document.getElementById("greeting")

// 挨拶する為の関数を定義
const GREETING = () => {
  // body 要素を取得
  const BODY = document.querySelector("body")

  // 挨拶文の為のp要素を作成
  let p = document.createElement("p")
  p.textContent = "おはよう"

  // body 要素に 生成した p 要素を追加
  BODY.append(p)
}

// 挨拶ボタンにイベントリスナを設定、
// クリックされたらGREETING関数が呼ばれ、実行される
GREETING_BUTTON.addEventListener("click", GREETING)
//}

//sideimage[greeting2][25mm][sep=5mm,side=R,border=on]{

コードの解説を行ってまいりましょう。

まず2行目では、@<code>{getElementById}メソッドを使って、HTML中に書かれた挨拶ボタン要素@<code>{button}を取得、JavaScript中で扱いやすいよう、@<code>{GREETING_BUTTON}という変数に格納しています。

5行目から15行目は、挨拶(GREETING)を表示するための関数を定義しています。7行目でまずHTML中の@<code>{body}要素を取得します。もともとのHTMLの@<code>{body}には@<code>{p}要素はありませんが、10行目でJavaScriptで@<code>{p}要素を**創り出します!!** @<code>{p}要素を創っただけでは中身（コンテンツ）がないので、11行目では中身を「おはよう」としています。これで@<code>{p}要素ができ上がりましたので、14行目では、画面に現れるよう、先に取得した@<code>{body}要素に追加(append)しています。
//}
//vspace[latex][2mm]
関数は定義しただけでは機能することはありません。先に定義した@<code>{GREETING}関数を呼び出すことではじめて機能し実行されます。19行目では@<code>{GREETING_BUTTON}がクリックされたときに@<code>{GREETING}関数が呼ばれるよう、イベントリスナーを登録しています。

これにより、「挨拶ボタン」を押すと、右のように「おはよう」と表示されるようになりました。

慣習的に「定数」は「大文字」で書きますが、ボタン名や関数名が大文字なのは違和感を感じるかもしれません。まったく同じ内容ですが、以下のように小文字で書くこともあります。読者の皆様はどちらがお好みでしょうか。

//list[][greeting10.js][1]{
// HTML中の挨拶ボタン要素を取得
const greetingButton = document.getElementById("greeting")

// 挨拶する為の関数を定義
const greeting = () => {
  // body 要素を取得
  const body = document.querySelector("body")

  // 挨拶文の為のp要素を作成
  let p = document.createElement("p")
  p.textContent = "おはよう"

  // body 要素に 生成した p 要素を追加
  body.append(p)
}

// 挨拶ボタンにイベントリスナを設定、
// クリックされたらgreeting関数が呼ばれ、実行される
greetingButton.addEventListener("click", greeting)
//}


=== イベントリスナで 「挨拶」を表示する - 無名関数の使用

まったく同じ働きをするコードですが、次のように書くこともできます。

//list[][greeting20.js][1]{
// HTML中の挨拶ボタン要素を取得
const greetingButton = document.getElementById("greeting")

// 挨拶ボタンにイベントリスナを設定、
// クリックされたらgreeting関数が呼ばれ、実行される
greetingButton.addEventListener("click", () => {
  // body 要素を取得
  const body = document.querySelector("body")

  // 挨拶文の為のp要素を作成
  let p = document.createElement("p")
  p.textContent = "おはよう"

  // body 要素に 生成した p 要素を追加
  body.append(p)
})
//}

先ほどまでのコードは、5行目で挨拶関数greetingを定義し、19行目で挨拶ボタンgreetingButtonがクリックされたときにgreeting関数が実行されるよう、イベントリスナを登録していました。

今回のコードは、6行目で挨拶ボタンgreetingButtonがクリックされたときにイベントリスナを登録していますが、greeting関数を定義してそれを呼び出すのではなく、直接greeting関数の中身を記しています。

注意深く見比べてもらうと、@<code>{greetingButton.addEventListener("click", greeting)}の@<code>{greeting}が、greeting関数の中身である @<code>{() => { ... \}} に入れ替わっていることが見て取れます。

あちらこちらに「挨拶ボタン」があり、さまざまなタイミングで押されるような状況であったり、一度限りの表示であっても、挨拶文を表示する処理がとても複雑で長いコードが必要となる場合には、挨拶関数greetingとして名前を付けると、プログラミングしやすくコードの見通しも良くなりますが、今回の例のように、単純に「おはよう」と表示させるような短いコードの場合、わざわざ関数名を付けるのも面倒ですので、直接、その関数の処理の内容のみを記すことがよくあります。名前が無い関数ですので、無名関数（匿名関数）と言いますが、JavaScriptでは、よく使われる書き方です。手軽に短い処理を書くことに適していますので、ご活用下さい。

=== イベントリスナで「時刻に応じた挨拶」を表示する

今までのコードは朝でも昼でも夜でも「おはよう」と挨拶しました。もう少し改良して、朝ならばおはよう、昼ならばこんにちは、夜ならばこんばんはと、時刻に応じた挨拶をするようにしてみましょう。

コードの例は次のようになります。

//list[][greeting30.js][1]{
// HTML中の挨拶ボタン要素を取得
const greetingButton = document.getElementById("greeting")

// 挨拶する為の関数を定義
const greeting = () => {
  // body 要素を取得
  const body = document.querySelector("body")

  // 挨拶文の為のp要素を作成
  let p = document.createElement("p")

  // 現在時刻を取得
  let today = new Date()
  let hour  = today.getHours()

  // 時間帯に応じた挨拶にする
  if (6 <= hour && hour < 12) {
    p.textContent = "おはよう"
  } else if (12 <= hour && hour < 18) {
    p.textContent = "こんにちは"
  } else {
    p.textContent = "こんばんは"
  }

  // body 要素に 生成した p 要素を追加
  body.appendChild(p)
}

// 挨拶ボタンにイベントリスナを設定、
// クリックされたらgreeting関数が呼ばれ、実行される
greetingButton.addEventListener("click", greeting)
//}

//sideimage[greeting3][25mm][sep=5mm,side=R,border=on]{

実行結果は、時刻に応じて変わりますが、お昼に実行すると、右のようになります。

コードの解説ですが、先にご紹介した無名関数を使って、イベントリスナ登録時に直接処理内容を記述しても良いですが、少し処理内容が長くなります。そこで最初に学んだ例に戻って、挨拶関数greetingを定義、イベントリスナへはgreeting関数を登録するようにしています。
greeting関数では、時刻に応じた挨拶をするようにしたいので、まず今何時であるのかを知る必要があります。それを行っているのが13行目と14行目のコードです。

13行目の @<code>{new Date()} は、@<code>{new}演算子により、現在の日時を得ることが出来るので、変数@<code>{today}に格納しています。14行目は @<code>{getHours()}メソッドにより、時刻を取得、変数@<code>{hours}に格納しています。@<small>{(ちなみに グレゴリオ暦年は@<code>{getFullYear()})、月は@<code>{getMonth()}、日は@<code>{getDate()}、時は@<code>{getHours()}、分は@<code>{getMinutes()}、秒は@<code>{getSeconds()}、ミリ秒は@<code>{getMilliseconds()}で取得できます)}
//}
//vspace[latex][2mm]

17行目から23行目は時刻に応じた挨拶用の条件分岐です。
以前に学習した @<code>{if}文を用います。

17行目の @<code>{6 <= hour && hour < 12} は 「6以上12未満」を表す定型句です。
@<code>{hour >= 6} と書くことで、「6以上」ならばという条件を、
@<code>{hour < 12} と書くことで、「12未満」という条件を示します。

「6以上12未満」としたいので、論理演算子「@<code>{&&}(かつ)」を用いると、
@<code>{hour >= 6 && hour < 12} と書くことができ「6以上12未満」という条件になります。
このままでも良いのですが、数式として馴染ある範囲「6 <= hour < 12」のように見えるよう @<code>{6 <= hour && hour < 12} と順序を入れ替えて書くことで、コードを読みやすくしています。
