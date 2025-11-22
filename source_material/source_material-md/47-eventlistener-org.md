# イベントリスナ

:::{.chapter-lead}
この章では「イベントリスナ」について学びます。これにより、利用者が何か操作をすることにより画面を変化させられるようになります。利用者とシステムとの間での相互作用・インタラクティブなサイトを創ることが出来るようになります。  
:::



## イベントリスナ


### イベントリスナとは

JavaScriptには、**イベントリスナ** と呼ばれる仕組みが有り、「何か操作を行った時」に指定した動作をする機能が備わっています。

それでは、**イベント**、**リスナー** とはなんでしょうか。それぞれの用語の意味を調べてみましょう。

> プログラミングにおけるイベント (英: event) は、プログラム内で発生した動作・出来事、またそれらを表現する信号である。 メッセージあるいはアクション（動作）とも呼ばれる。
> イベントの例としてウェブブラウザにおける「ページが読み込まれた時」、「クリック動作」、「スクロール操作」などさまざまなイベントがある。 [^174]

[^174]: 出典：Wikipedia

> リスナーとは、聞く人、聞き手、聴取者、聴講生、などの意味を持つ英単語。一般の外来語としてはラジオ（局/番組）の聴取者を意味する用法が有名である。
>
> プログラミングの分野では、何らかのきっかけに応じて起動されるよう設定されたサブルーチンや関数、メソッドなどをイベントリスナー（event listener）あるいは単にリスナーという。例えば、「マウスがクリックされると起動するよう指定された関数」のことを「マウスクリックを待ち受けるリスナー」といったように呼ぶ。 [^175]

[^175]: 出典：IT用語辞典

つまり、**イベントリスナー**とは次のようになります。

> 「ページ読み込みやクリック動作など、ウェブページで行われる様々な動作を常時起動し待ち受けて(聴取し続けて)、イベントが起きた時に指定された処理を行う関数のこと」[^176]

[^176]: 参考：フロントエンドエンジニアを目指す! JavaScript講座(9)イベントリスナーを使用する

この**イベントリスナー** の仕組みを利用すると、「利用者」が「ボタン」を押したときに、何か処理を行うなど、利用者と相互作用を持てる、対話できるインタラクティブなサイトを作ることが出来ます。


### イベントリスナの構文

MDN [EventTarget: addEventListener()](https://developer.mozilla.org/ja/docs/Web/API/EventTarget/addEventListener) より、抜粋して、ご紹介いたします。

> `addEventListener()` は `EventTarget` インターフェイスのメソッドで、ターゲットに特定のイベントが配信されるたびに呼び出される関数を設定します。
>
> 対象としてよくあるものは `Element`、`Document`、`Window` ですが、イベントに対応したあらゆるオブジェクトが対象になることができます。
>
>
> [tip] <b></a>
>
> **構文**<br>
> `addEventListener(type, listener)`<br>
>
> **引数**<br>
>
> 
>
> [/tip]
> 

### イベントリスナで 「和風月名」を表示する

早速、使って見ることにしましょう。

ボタン要素上でのマウスクリックを監視（聴取）している `addEventListener()` の使い方の例です。

`index.html` は次のように準備します。

**▼index.html**

```
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
```

6行目で、 `eventlistener.js` を読み込み、10行目に操作用ボタンがある、とても簡単な例です。
---
`eventlistener.js` は次のように準備します。

**▼eventlistener.js**

```
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
```

味噌となるのは、7行目から11行目にかけてです。
id が month の要素(=ボタン)を取得し、month が click されたときに、nextMonth が実行されるよう、イベントリスナを設定しています。

14行目からの nextMonth関数は、前章で学んだDOM操作により、body要素に月名を追加する働きをしています。

<img src="">

実行すると、「和風月名」ボタンを押す都度、睦月、如月、彌生と、月名が追加されて行きます。

また、「インスペクタ画面」を見ると、`<button>`要素の右端に `event` と表示されています。イベントリスナが設定されていることや、`click` した際に、`function nextMonth()` が実行されることも確認できます。


### イベントリスナで 「和風月名」を表示する その２

もう少し発展させて見ましょう。

`index.html` は次のようにします。

**▼index.html**

```
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
      <a class="prev" title="前月"><</a>
      <a class="next" title="翌月">></a>
      <span class="month" data-month="5">皐月</span>
    </div>
  </body>
</html>
```

`<` `>` は文字参照と呼ばれる記述法です。前月に戻る、来月へ進むの意図で、HTML中に `<` や `>` と書きたいのですが、タグと紛らわしく、正常に表示が行えません。そこで文字参照を用いています。

また、`<span class="month" data-month="5">皐月</span>` にも着目してください。 `data-month="5"` は、「データ属性」 と呼ばれ、ウェブ制作者自身が`<span>`タグに追加情報を与えたい場合に用いることが出来ます。 ここでは 「皐月」が `5` 月の事であると、JavaScript から取得する為に、記述しています。

MDN [データ属性の使用](https://developer.mozilla.org/ja/docs/Learn/HTML/Howto/Use_data_attributes) により詳しく説明されておりますので、ご覧ください。


CSS は次のようにしましょう。 CSSグリッドを用いて配置を整えるのみの簡素なCSSとなっています。

**▼mini_calendar.css**

```
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
```

JavaScript は 次のようにしましょう。

**▼mini_calendar.js**

```
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
```

6行目、7行目に注目してください。 まず6行目でHTML上で設定したデータ属性を取得します。 データ属性は「文字列」として取得されるので、 7行目で `Number()` を用いて、数値に変換、 `currentMonth` として用いています。 先に登場したイベントリスナの例では、直接 `currentMonth = 1` と書いていましたが、このように書くことで、HTML上に記されたデータ属性をJavaScriptから活用することが出来ます。


<img src="">

実行した結果は右のようになります。 `<`をクリックすると前月へ、`>` で翌月へ月が移り変わって行きます。


### イベントリスナの削除


### イベントリスナの削除

MDN [EventTarget: removeEventListener()](https://developer.mozilla.org/ja/docs/Web/API/EventTarget/removeEventListener) より、抜粋して、ご紹介いたします。

> `removeEventListener()` は `EventTarget` インターフェイスのメソッドで、以前に `EventTarget.addEventListener()` で登録されたイベントリスナーを取り外します。
>
>
> [tip] <b></a>
>
> **構文**<br>
> `removeEventListener(type, listener)`<br>
>
> **引数**<br>
>
> 
>
> [/tip]
> 

使って見ましょう。

以下のコードをコンソール画面から実行すると、その後は `<` や `>` をクリックしても、月は移り変わることなく、そのままとなります。

```
prev.removeEventListener("click", previousMonth)
next.removeEventListener("click", nextMonth)
```

