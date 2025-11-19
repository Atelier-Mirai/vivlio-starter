= イベントリスナ

//abstract{
この章では「イベントリスナ」について学びます。これにより、利用者が何か操作をすることにより画面を変化させられるようになります。利用者とシステムとの間での相互作用・インタラクティブなサイトを創ることが出来るようになります。
//}

#@# #@# //sideimage[practisehtml][50mm][sep=5mm,side=R]{
#@#   * 画面に「おはよう」と表示する
#@#   * @<file>{practise.js} を読み込む
#@#
#@#  という、簡潔な HTML で、ブラウザで表示すると、右のようになります。
#@#  JavaScript から HTML を操作できるのですが、今読み込んだ @<file>{practise.js} には、まだ何も書かれていないため、特に変化がない普通の表示になっています。
#@# #@# //}
#@# //vspace[latex][2mm]
#@# それでは、次のように、@<file>{practise.js}を書いてみましょう。
#@#
#@# //list[][practise.js][file=source/practise.js,1]{
#@# //}
#@#
#@# #@# //sideimage[practisejs][50mm][sep=5mm,side=R]{
#@# 「おはよう」とメッセージが表示された後、
#@#
#@#   * 画面が「おはよう」から「こんにちは」に更新された
#@#   * 「ボタン」も追加された
#@#
#@# と変化していることが分かります。
#@# #@# //}
#@#
#@# このように、JavaScript と @<code>{DOM} は ウェブアプリ開発において切り離せない関係で、動的 @<fn>{dynamic} なウェブアプリを作る為には、JavaScriptによる @<code>{DOM} の操作が不可欠です。
#@#
#@# //footnote[dynamic][今から作っていくじゃんけんゲームのように、利用者の操作に応じ様々な変化があることを「動的」と表現します。対義語は「静的」で、通常のウェブサイトのように変化しないものを指して言います。]
#@#
#@# //blankline
#@# 少し難しい説明となりましたが、後ほどまた解説する機会もあります。ここでは「**JavaScriptからHTMLを操作できる**」ということを把握して、先へ進みましょう。
#@#
#@# == イベントリスナと関数

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

=== イベントリスナで 「和風月名」を表示する

早速、使って見ることにしましょう。

ボタン要素上でのマウスクリックを監視（聴取）している @<code>{addEventListener()} の使い方の例です。

@<file>{index.html} は次のように準備します。
//list[][index.html][1]{
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>イベントリスナ</title>
    <script src="eventlistener.js" defer></script>
  </head>

  <body>
    <button id="month">和風月名</button>
  </body>
</html>
//}

6行目で、 @<file>{eventlistener.js} を読み込み、10行目に操作用ボタンがある、とても簡単な例です。
---
@<file>{eventlistener.js} は次のように準備します。

//list[][eventlistener.js][1]{
// 和風月名
const MONTHS = ["", "睦月", "如月", "彌生", "卯月", "皐月", "水無月", "文月", "葉月", "長月", "神無月", "霜月", "師走"]

// 現在何月を表示中か
let currentMonth = 1

// イベントリスナーの設定
// id が month の要素(=ボタン)を取得
const month = document.getElementById("month")
// month が click されたときに、nextMonth が実行されるよう、イベントリスナを設定
month.addEventListener("click", nextMonth)

// 前月操作時の各種更新
function nextMonth() {
  // p要素を新規作成
  let p = document.createElement("p")
  // p要素の文字列として MONTHS[curretnMonth] つまり配列内の和風月名を追加
  p.append(MONTHS[currentMonth])
  // body要素を取得し 作成したp要素を追加する
  document.querySelector("body").append(p)
  // 三項演算子を用いて、次の月へと更新する
  currentMonth = (currentMonth === 12) ? 1 : currentMonth + 1
}
//}

味噌となるのは、7行目から11行目にかけてです。
id が month の要素(=ボタン)を取得し、month が click されたときに、nextMonth が実行されるよう、イベントリスナを設定しています。

14行目からの nextMonth関数は、前章で学んだDOM操作により、body要素に月名を追加する働きをしています。

//sideimage[eventlistener1][20mm][sep=5mm,side=R]{
実行すると、「和風月名」ボタンを押す都度、睦月、如月、彌生と、月名が追加されて行きます。

また、「インスペクタ画面」を見ると、@<code>{<button>}要素の右端に @<code>{event} と表示されています。イベントリスナが設定されていることや、@<code>{click} した際に、@<code>{function nextMonth()} が実行されることも確認できます。
//}

=== イベントリスナで 「和風月名」を表示する その２

もう少し発展させて見ましょう。

@<file>{index.html} は次のようにします。

//list[][index.html][1]{
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Mini Calendar</title>
    <link rel="stylesheet" href="mini_calendar.css">
    <script src="mini_calendar.js" defer></script>
  </head>

  <body>
    <div class="panel">
      <a class="prev" title="前月">&lt;</a>
      <a class="next" title="翌月">&gt;</a>
      <span class="month" data-month="5">皐月</span>
    </div>
  </body>
</html>
//}

@<code>{&lt;} @<code>{&gt;} は文字参照と呼ばれる記述法です。前月に戻る、来月へ進むの意図で、HTML中に @<code>{<} や @<code>{>} と書きたいのですが、タグと紛らわしく、正常に表示が行えません。そこで文字参照を用いています。

また、@<code>{<span class="month" data-month="5">皐月</span>} にも着目してください。 @<code>{data-month="5"} は、「データ属性」 と呼ばれ、ウェブ制作者自身が@<code>{<span>}タグに追加情報を与えたい場合に用いることが出来ます。 ここでは 「皐月」が @<code>{5} 月の事であると、JavaScript から取得する為に、記述しています。

MDN @<href>{https://developer.mozilla.org/ja/docs/Learn/HTML/Howto/Use_data_attributes, データ属性の使用} により詳しく説明されておりますので、ご覧ください。

//blankline

CSS は次のようにしましょう。 CSSグリッドを用いて配置を整えるのみの簡素なCSSとなっています。

//list[][mini_calendar.css][1]{
.panel {
  display: grid;
  grid-template-columns: 1fr 3fr 1fr;
  grid-template-rows: auto;
  width: 100px;
  text-align: center;
}

.prev  { grid-column: 1; grid-row: 1; }
.next  { grid-column: 3; grid-row: 1; }
.month { grid-column: 2; grid-row: 1; }
//}

JavaScript は 次のようにしましょう。

//list[][mini_calendar.js][1]{
// 和風月名
const MONTHS = ["", "睦月", "如月", "彌生", "卯月", "皐月", "水無月", "文月", "葉月", "長月", "神無月", "霜月", "師走"]

// 現在何月を表示中か
let month        = document.querySelector(".month")
let monthString  = month.getAttribute("data-month")
let currentMonth = Number(monthString)

// イベントリスナー
const prev = document.querySelector(".prev")
prev.addEventListener("click", previousMonth)
const next = document.querySelector(".next")
next.addEventListener("click", nextMonth)

// 前月操作時の各種更新
function previousMonth() {
  currentMonth = (currentMonth === 1) ? 12 : currentMonth - 1
  document.querySelector(".month").setAttribute("data-month", currentMonth)
  document.querySelector(".month").innerText = MONTHS[currentMonth]
}

// 前月操作時の各種更新
function nextMonth() {
  currentMonth = (currentMonth === 12) ? 1 : currentMonth + 1
  document.querySelector(".month").setAttribute("data-month", currentMonth)
  document.querySelector(".month").innerText = MONTHS[currentMonth]
}
//}

6行目、7行目に注目してください。 まず6行目でHTML上で設定したデータ属性を取得します。 データ属性は「文字列」として取得されるので、 7行目で @<code>{Number()} を用いて、数値に変換、 @<code>{currentMonth} として用いています。 先に登場したイベントリスナの例では、直接 @<code>{currentMonth = 1} と書いていましたが、このように書くことで、HTML上に記されたデータ属性をJavaScriptから活用することが出来ます。

//blankline

//sideimage[eventlistener3][30mm][sep=5mm,side=R]{
実行した結果は右のようになります。 @<code>{<}をクリックすると前月へ、@<code>{>} で翌月へ月が移り変わって行きます。
//}

=== イベントリスナの削除

=== イベントリスナの削除

MDN @<href>{https://developer.mozilla.org/ja/docs/Web/API/EventTarget/removeEventListener, EventTarget: removeEventListener()} より、抜粋して、ご紹介いたします。

//quote{
@<code>{removeEventListener()} は @<code>{EventTarget} インターフェイスのメソッドで、以前に @<code>{EventTarget.addEventListener()} で登録されたイベントリスナーを取り外します。

//tip{
**構文**@<br>{}
@<code>{removeEventListener(type, listener)}@<br>{}

**引数**@<br>{}

 : @<code>{　　type}
    文字列で、イベントリスナーを取り外すイベントの種類を表します。 @<small>{@<href>{https://developer.mozilla.org/ja/docs/Web/Events, イベントリファレンス} で主要なイベントを確認できます。}

 : @<code>{　　listener}
    イベントターゲットから取り外すイベントリスナー関数です。
//}
//}

使って見ましょう。

以下のコードをコンソール画面から実行すると、その後は @<code>{<} や @<code>{>} をクリックしても、月は移り変わることなく、そのままとなります。

//list[][][1]{
prev.removeEventListener("click", previousMonth)
next.removeEventListener("click", nextMonth)
//}
