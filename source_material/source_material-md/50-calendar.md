# カレンダーを創る

:::{.chapter-lead}
この章では、これまで学習したことを踏まえて、カレンダーを作成します。
JavaScript を活用し、それぞれの月の暦を「動的」に生成します。

また、月ごとに美しい写真が表示されるようにし、簡易的なブログ機能も備えるようにします。  
:::



## カレンダーの完成形

まずは、完成形から見て見ましょう。

**▼index.html**

```
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Calendar</title>

    <!-- Font Awesome -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.2/css/all.min.css">

    <!-- Google Fonts 佑字 朴 -->
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Yuji+Boku&display=swap" rel="stylesheet">

    <!-- 暦の為の CSS & JS 読み込み -->
    <link rel="stylesheet" href="calendar.css">
    <script src="calendar.js" defer></script>
  </head>

  <body>
    <!-- JavaScript により 暦要素を生成 -->
    <div id="wallpaper">
      <div id="calendar"></div>
    </div>
  </body>
</html>
```

![](calendar0.png)
春の美しい桜の写真に、卯月・四月の暦が表示されています。


HTML に関しては特筆すべき点は特にありません。装飾は全てCSS に、カレンダー要素の作成は JavaScript に委ねています。


:::{.tip}
暦 & 簡易ブログ のための HTML / CSS に関しては、https://codepen.io/daliannyvieira/pen/EgvbKB を、 JavaScript に関しては、 https://www.cssscript.com/basic-calendar-view/ を参考に実装しました。厚く御礼申し上げます。

カレンダーの実装例は https://shichiyouhyou.netlify.app/ にて、簡易ブログは https://wave-example.netlify.app/r05-04-01 にて、公開いたしております。
:::

---

**▼calendar.css**

```
/* 暦 & 簡易ブログ のための CSS
-------------------------------------------------------------------------*/

/* 色
---------------------------------------------------------------------*/
:root {
  --wakakusairo: #abc900;
  --sorairo: #a0d8ef;
  --tokiiro: #f4b3c2;
  --botaniro: #e7609e;
  --hinomaru: #bc012d;
  --kinariiro: #fbfaf5;
  --kurobeni: #302833;
  --kurobeni_8: #30283380;
}

/* リセットCSS
---------------------------------------------------------------------*/
* {
  box-sizing: border-box;
  margin: 0;
}

/* 暦の背景写真
---------------------------------------------------------------------*/
#wallpaper {
  width: 100vw;
  height: 100vh;

  display: grid;
  grid-template-columns: 1fr auto 1fr;
  grid-template-rows:    1fr auto 1fr;

  background-attachment: fixed;
  background-position: center center;
  background-repeat: no-repeat;
  background-size: cover;
  &[data-month= "1"] { background-image: url("images/snow.webp"); }
  &[data-month= "2"] { background-image: url("images/grasslands.webp"); }
  &[data-month= "3"] { background-image: url("images/hoursetail.webp"); }
  &[data-month= "4"] { background-image: url("images/cherry.webp"); }
  &[data-month= "5"] { background-image: url("images/leaves.webp"); }
  &[data-month= "6"] { background-image: url("images/water.webp"); }
  &[data-month= "7"] { background-image: url("images/sea.webp"); }
  &[data-month= "8"] { background-image: url("images/sky.webp"); }
  &[data-month= "9"] { background-image: url("images/light.webp"); }
  &[data-month="10"] { background-image: url("images/deodora.webp"); }
  &[data-month="11"] { background-image: url("images/maple.webp"); }
  &[data-month="12"] { background-image: url("images/night.webp"); }
}

/* 暦
---------------------------------------------------------------------*/
#calendar {
  grid-column: 2;
  grid-row: 2;

  width: clamp(375px, 100vw, 480px);
  background: var(--kinariiro);
  color: var(--kurobeni);
  border-radius: 10px;
  box-shadow: 0 20px 35px var(--kurobeni_8), 0 15px 10px var(--kurobeni_8);
  font-family: 'Yuji Boku', serif;
  font-size: 1.2em;

  /* 月ごとの暦の写真 */
  .photograph {
    aspect-ratio: 16 / 9; /* 横16楯9に設定 */
    background-position: center center;
    background-size: cover;
    &[data-month= "1"] { background-image: url("images/suisen.webp"); }
    &[data-month= "2"] { background-image: url("images/nanohana.webp"); }
    &[data-month= "3"] { background-image: url("images/momo.webp"); }
    &[data-month= "4"] { background-image: url("images/sakura.webp"); }
    &[data-month= "5"] { background-image: url("images/fuji.webp"); }
    &[data-month= "6"] { background-image: url("images/ajisai.webp"); }
    &[data-month= "7"] { background-image: url("images/hanabi.webp"); }
    &[data-month= "8"] { background-image: url("images/himawari.webp"); }
    &[data-month= "9"] { background-image: url("images/higanbana.webp"); }
    &[data-month="10"] { background-image: url("images/kosumosu.webp"); }
    &[data-month="11"] { background-image: url("images/susuki.webp"); }
    &[data-month="12"] { background-image: url("images/tsubaki.webp"); }
  }

  /* 操作盤 */
  .panel {
    display: grid;
    grid-template-columns: 1fr 3fr 3fr 1fr;
    grid-template-rows: auto;
    text-align: center;
    vertical-align: middle;
    padding: 30px 30px 0px;
    .prev  { grid-column: 1;  grid-row: 1; }
    .year  { grid-column: 2;  grid-row: 1; }
    .month { grid-column: 3;  grid-row: 1; }
    .next  { grid-column: 4;  grid-row: 1; }
    .prev,
    .next  { color: var(--kurobeni_8); width: 2em; }
    .prev:hover { transform: translateX(-5px); }
    .next:hover { transform: translateX( 5px); }
    .year,
    .month { font-size: larger; }
  }

  /* 日付欄 */
  & table {
    width: 100%;
    height: 346px;
    padding: 20px 30px;
    text-align: center;

    & thead { color: var(--kurobeni_8); }
    & th,
    & td { padding-bottom: .4em; }

    /* 日付のリンク */
    & a {
      /* 日付を円形にする */
      width: 30px;
      height: 30px;
      line-height: 30px;
      border-radius: 50%;

      /* 色 */
      color: #333;
      text-decoration: none;
      display: block;
      margin: 0 auto;
      cursor: pointer;

      /* カーソルを載せるとほんのり染める */
      &:hover {
        background: var(--botaniro);
        color: var(--kinariiro);
        transition: .7s;
        transform: scale(1);
      }
    }
  }

  /* 色を付ける */
  .today    > a { background: var(--botaniro); color: var(--kinariiro); }
  .sunday   > a { background: var(--tokiiro); }
  .saturday > a { background: var(--sorairo); }
  .holiday  > a { background: var(--hinomaru); color: var(--kinariiro); }

  /* ブログ執筆日 */
  .blogday a {
    outline: 6px double var(--wakakusairo); /* 若草色の輪郭線 */
    &:hover {
      outline-offset: 7px;  /* 少し外側に 若草色の輪郭線 */
      outline: 6px double var(--wakakusairo);
      transition: .7s;
      transform: scale(1);
    }
  }

  /* ブログの見出し */
  .blog.header {
    padding: 0 50px;
    letter-spacing: 4px;
    text-shadow: 3px 3px 3px var(--kurobeni_8), -1px -1px 1px var(--wakakusairo);
  }

  /* ブログの一覧 */
  & nav {
    width: calc(100% - 60px);
    height: 170px;
    overflow-y: scroll;   /* 縦方向にスクロール */
    margin: 0 30px 30px 30px;
    border: 3px double var(--wakakusairo);

    /* flexbox を用いて 最新順に並べる */
    & ul {
      display: flex;
      flex-direction: column-reverse;
      list-style: none;
      padding: 0;
      text-align: right;

      /* ブログタイトルの装飾 */
      & li a {
        text-decoration: none;
        color: var(--kurobeni);

        /* カーソルを載せるとほんのり染める */
        &:hover {
          background: var(--wakakusairo);
          color: var(--kinariiro);
          transition: .7s;
          transform: scale(1);
        }
      }
    }
  }
}
```

少し長くなっていますが、CSSグリッドで配置を整え、色遣いなどの装飾を施している CSS です。

`[data-month= "1"] ` というセレクタの記述について補足します。

```
&[data-month= "1"] { background-image: url("images/snow.webp"); }
&[data-month= "2"] { background-image: url("images/grasslands.webp"); }
&[data-month= "3"] { background-image: url("images/hoursetail.webp"); }
```

イベントリスナの紹介で「データ属性」をJavaScriptから活用する事例を挙げましたが、CSS でもデータ属性を用いることにより、`1`月ならば背景画像を雪に、`2`月ならば草原、`3`月ならば土筆（つくし）の写真にと、変更されるようにしています。


## JavaScript で動的に生成する

![](calendar1.png)

本命となる JavaScript を見て行きましょう。

CSS の適用を解除すると、右のような簡素な形となります。

`<table>` タグを使って表を生成、カレンダーとしています。また今月の投稿欄では、投稿があった日付のブログへのリンクを生成しています。

動的に生成された HTML を取り出すと、以下のようになります。

```
<div id="wallpaper" data-month="5">
  <div id="calendar">
    <div class="photo" data-month="5"></div>
    <div class="panel">
      <a class="prev" title="前月">
        <i class="fa-solid fa-angle-left"></i>
      </a>
      <a class="next" title="翌月">
        <i class="fa-solid fa-angle-right"></i>
      </a>
      <span class="year" data-year="2023">令和 五 年</span>
      <span class="month" data-month="5">皐月</span>
    </div>

    <table>
      <thead>
        <tr>
          <th>日</th>
          <th>月</th>
          <th>火</th>
          <th>水</th>
          <th>木</th>
          <th>金</th>
          <th>土</th>
        </tr>
      </thead>
      <tbody id="tbody">
        <tr>
          <td></td>
          <td class="monday">  <a href="#">1</a> </td>
          <td class="tuesday"> <a href="#">2</a> </td>
          <td class="holiday" title="憲法記念日"> <a href="#">3</a> </td>
          <td class="holiday" title="みどりの日"> <a href="#">4</a> </td>
          <td class="holiday blogday" title="こどもの日 こどもの日のお祝いです">
            <a href="R05-05-05.html">5</a>
          </td>
          <td class="saturday"> <a href="#">6</a> </td>
        </tr>
        <tr>
          <td class="sunday blogday" title="連休も今日で最後です">
            <a href="R05-05-07.html">7</a>
          </td>
          <td class="monday">    <a href="#">8</a> </td>
          <td class="tuesday">   <a href="#">9</a> </td>
          <td class="wednesday"> <a href="#">10</a> </td>
          <td class="thursday">  <a href="#">11</a> </td>
          <td class="today">     <a href="#">12</a> </td>
          <td class="saturday">  <a href="#">13</a> </td>
        </tr>
        <tr>
          <td class="sunday">    <a href="#">14</a> </td>
          <td class="monday">    <a href="#">15</a> </td>
          <td class="tuesday">   <a href="#">16</a> </td>
          <td class="wednesday"> <a href="#">17</a> </td>
          <td class="thursday">  <a href="#">18</a> </td>
          <td class="friday">    <a href="#">19</a> </td>
          <td class="saturday">  <a href="#">20</a> </td>
        </tr>
        <tr>
          <td class="sunday">    <a href="#">21</a> </td>
          <td class="monday">    <a href="#">22</a> </td>
          <td class="tuesday">   <a href="#">23</a> </td>
          <td class="wednesday"> <a href="#">24</a> </td>
          <td class="thursday">  <a href="#">25</a> </td>
          <td class="friday">    <a href="#">26</a> </td>
          <td class="saturday">  <a href="#">27</a> </td>
        </tr>
        <tr>
          <td class="sunday">    <a href="#">28</a> </td>
          <td class="monday">    <a href="#">29</a> </td>
          <td class="tuesday">   <a href="#">30</a> </td>
          <td class="wednesday"> <a href="#">31</a> </td>
        </tr>
      </tbody>
    </table>

    <p class="blog header">今月の投稿</p>
    <nav>
      <ul id="ul">
        <li> <a href="R05-05-05.html">こどもの日のお祝いです</a> </li>
        <li> <a href="R05-05-07.html">連休も今日で最後です</a> </li>
      </ul>
    </nav>
  </div>
</div>
```

`<div class="panel">` として、前月へ、あるいは翌月へと操作出来るようにしています。

暦本体ついては、 `<table>` タグ内に `<td>1</td>` から `<td>31</td>` を生成、表示しています。

`<td class="monday">` とそれぞれの曜日に応じたクラス名を設定されています。

祝日であれば、`<td class="holiday" title="みどりの日"> <a href="#">4</a> </td>` のように、 `"holiday"` クラスと、タイトル属性が設定されています。

ブログの投稿が為されている日であれば、`<td class="sunday blogday" title="連休も今日で最後です">  <a href="R05-05-07.html">7</a></td>` のように、`"blogday"` クラスと、タイトル属性、そしてブログへのリンクが設定されています。


## 七曜表の作成

カレンダーは、七つの曜日が繰り返されるところから、「七曜表」とも呼ばれます。


### 曜日の配列

クラス名などに七つの曜日を設定する為には、次のような配列を準備すると便利です。

```
const NAME_OF_DAY = ["sunday",
                     "monday",
                     "tuesday",
                     "wednesday",
                     "thursday",
                     "friday",
                     "saturday"]
```

すると、`NAME_OF_DAY[0]` で `"sunday"`、`NAME_OF_DAY[6]` で `"saturday"` を得ることが出来ます。同様に「日、月、火、水、木、金、土」の配列も用意しておくと良さそうです。


### 月初の空白

それでは、暦本体の作成ですが、日曜始まりの月であれば、日曜日に `1` を、月曜日に `2` をと順に配置して、土曜日の配置が完了したら、次の行に移るという処理を繰り返せば良いです。


**日曜始まりの月の暦**

| 日 | 月 | 火 | 水 | 木 | 金 | 土 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 2 | 3 | 4 | 5 | 6 | 7 |
| 8 | 9 | 10 | 11 | 12 | 13 | 14 |
| 15 | 16 | 17 | 18 | 19 | 20 | 21 |
| 22 | 23 | 24 | 25 | 26 | 27 | 28 |
| 29 | 30 | 31 |  |  |  |  |
そして、いつも日曜日から月が始まるわけではありません。例えば下は土曜日から始まる月ですが、日曜日から金曜日までの `6` つの空白が必要です。


**土曜始まりの月の暦**

| 日 | 月 | 火 | 水 | 木 | 金 | 土 |
| --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  | 1 |
| 2 | 3 | 4 | 5 | 6 | 7 | 8 |
| 9 | 10 | 11 | 12 | 13 | 14 | 15 |
| 16 | 17 | 18 | 19 | 20 | 21 | 22 |
| 23 | 24 | 25 | 26 | 27 | 28 | 29 |
| 30 | 31 |  |  |  |  |  |
[ツェラーの公式](https://ja.wikipedia.org/wiki/ツェラーの公式) を用いると、ある月の一日が何曜日であるかを知ることができます。土曜始まりの月は `6` つの空白が必要でしたから、曜日と必要な空白との関係を以下の表のようにしておくと、使い勝手が良さそうです。


**曜日と数との対応表**

| 日 | 月 | 火 | 水 | 木 | 金 | 土 |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | 1 | 2 | 3 | 4 | 5 | 6 |
すると、各月の七曜表は、

* その月の `1日` までに必要な空白(=1日の曜日の数)を入れる。
* `0`曜日 から始まり、`6`曜日になったら、次の行(週)に移る。
* `1`日から始め、`末`日になったら、終了する。

という処理で作成できることになります。


### その月の日数を取得する

その月が何日で終わるのかも把握する必要があります。

`28`日で終わる月もあれば、`30`日や`31`日で終わる月もあります。
また、閏年であれば`29`日に終わる月もあります。

次のような対応表（配列）を用意しておくと便利でしょう。

**▼その月の日数を返す配列**

```
  daysInMonth = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
```

すると、`daysInMonth[2]` で、二月の日数 `28` 日を得ることが出来ます。

`[0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][2]` と書くことも出来ます。

二月は平年と閏年とで日数が変わるので、平年用、閏年用と二つの配列を用意することにします。

また、利便性の為に以下のように関数化します。

```
// その月の日数を返す
function daysInMonth(year, month) {
  if (leapYear()) {
    // 閏年
    //          1   2   3   4   5   6   7   8   9  10  11  12月
    return [0, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month]
  } else {
    // 平年
    return [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month]
  }
}
```


### 閏年の判定

閏年は四年に一度あることは良く知られていますが、千年にわたる誤差の蓄積があり、より精密な暦を作成することが求められるようになりました。そこで四年に一度閏年を設けるものの、四百年に三回は閏年を設けず、平年とするよう、合意されました。

グレゴリオ暦で、1700年、1800年、1900年のように、100で割り切れるが400で割り切れない年は平年、2000年のように400で割り切れる年は閏年となります。

以上を踏まえて、閏年を判定する為の関数は以下のようになります。

**▼閏年判定のための関数**

```
function leapYear(year) {
  return (year % 4 === 0) && (year % 100 !== 0) || (year % 400 === 0)
}
```

グレゴリオ暦の年(`year`) を与えると、閏年であれば `true`が、平年であれば `false` が返ります。


### 以前の暦の削除と 当月分の暦の新規作成

「前月」ボタン、「翌月」ボタンを操作した際に、表示されている七曜表を、当月分のものへと更新する必要があります。

日付を書き換えるのも手間です。そこで `<tbody id="tbody">` タグごと削除して、新規作成するようにするようにします。

```
// 以前の七曜表を削除
tbody = document.getElementById("tbody")
if (tbody !== null) {
  tbody.remove()
}
```

ID属性 `tbody` を持つ要素がないか調べます。
`null` は、「存在しない」ことを表す、JavaScript の特別な値です。
以前の暦が存在していれば、 `tbody` は、 `null` ではないはずなので、 `remove()` メソッドで削除します。

これで、`<tbody id="tbody">` タグ は存在しなくなりましたので、
初回読み込み時や「前月」「翌月」操作時に、当月分七曜表を作成する為に、以下のコードで `<tbody id="tbody">` タグ を生成することとします。

```
// 当月の七曜表を新規作成
tbody     = document.createElement("tbody")
tbody.id  = "tbody"
```


### 「前月」「翌月」操作

`<a>` タグを生成、クリックされたときに `previousMonth` 関数が実行されるよう、イベントリスナを設定します。

`previousMonth` 関数 では、 現在の月を表す変数 `currentMonth` を前月に更新します。 `1`月の前月は`12`月ですので、三項演算子を用いて場合分けを行うことにします。当月の七曜表を生成するための関数 `showCalendar` 関数に、年と月を渡します。

以上をまとめると以下のコードになります。

```
// 前月
const prev = document.createElement("a")
prev.addEventListener("click", previousMonth)

// 前月操作時の各種更新
function previousMonth() {
  currentMonth = (currentMonth === 1) ? 12 : currentMonth - 1
  // 当月の七曜表を生成
  showCalendar(currentYear, currentMonth)
}
```


### 七曜表の主要部の完成

以上をまとめると、以下のコードで七曜表の主要部は生成できることが分かります。

**▼calendar_main.js**

```
// 当月の暦生成&表示
function showCalendar(year, month) {
  // 以前の七曜表を削除
  tbody = document.getElementById("tbody")
  if (tbody !== null) { tbody.remove() }

  // 当月の七曜表を新規作成
  tbody     = document.createElement("tbody")
  tbody.id  = "tbody"

  // 月初の空日処理
  let wday = 0
  let tr   = document.createElement("tr")

  // 今月1日は何曜日か (日曜日: 0, 土曜日: 6)
  let firstDay = zeller(year, month, 1)

  // 月が始まるまでの空日処理
  // (今月1日が土曜日なら 6つ空白が必要)
  for (let date = 1 - firstDay; date < 1; date++, wday++) {
    td = document.createElement("td")
    tr.append(td)
  }

  // 一日から末日までの処理
  for (date = 1; date <= daysInMonth(year, month); date++) {
    td = document.createElement("td")
    td.className = NAME_OF_DAY[wday]  // "sunday", "monday" など
    a = document.createElement("a")
    a.setAttribute("href", "#")
    a.append(date)
    td.append(a)
    tr.append(td)

    // 週末(土曜日)まで処理したら 翌週の行を生成
    if (wday === 6) {
      tbody.append(tr)
      tr = document.createElement("tr")
      wday = 0
    } else {
      wday++
    }
  }
  tbody.append(tr)
  table.append(tbody)
}
```

---
== 簡易ブログ機能の実装

簡易ブログ機能へと発展させるには、ブログデータと祝日データが必要です。

ブログの記載日とその表題のデータを以下のような連想配列で持つことにします。

```
// ブログデータを設定
const BLOGS = {
  "R05-04-01": "本日四月一日より令和五年度の始まり、近くの公園の桜も咲いています。",
  "R05-04-03": "仕事始めです",
  (略)
}
```

また `Holidays JP API` より 祝日データを取得することとします。
https://holidays-jp.github.io/api/v1/date.json へアクセスすると、 `JSON` 形式のデータが得られます。

```
const HOLIDAYS = {
  "2022-01-01": "元日",
  "2022-01-10": "成人の日",
  "2022-02-11": "建国記念の日",
  "2022-02-23": "天皇誕生日",
  "2022-03-21": "春分の日",
  "2022-04-29": "昭和の日",
  (略)
  "2024-11-23": "勤労感謝の日"
}
```

また、各月ごとに異なる写真を表示するためには、データ属性を用いて `<div id="wallpaper" data-month="1">` とします。 CSS には `#wallpaper[data-month= "1"] { background-image: url("images/snow.webp"); `} と、雪の写真が表示されるよう設定します。

以上を踏まえると、少し長くなりますが、以下のコードとなって完成です。

**▼calendar.js**

```
/* 暦 & 簡易ブログ のための JavaScript
-------------------------------------------------------------------------*/

// 本日
let today        = new Date()
let currentYear  = today.getFullYear()
let currentMonth = today.getMonth() + 1

// 定数宣言
const thisYear    = currentYear
const thisMonth   = currentMonth
const thisDay     = today.getDate()
const MONTHS      = ["", "睦月", "如月", "彌生", "卯月", "皐月", "水無月", "文月", "葉月", "長月", "神無月", "霜月", "師走"]
const WDAYS       = ["日", "月", "火", "水", "木", "金", "土"]
const NAME_OF_DAY = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

// 暦本体の為の要素定義
const calendar  = document.getElementById("calendar")

// 前月翌月の操作盤の為の要素生成
const panel = document.createElement("div")
panel.className = "panel"
  // 前月
  const a_prev = document.createElement("a")
  a_prev.className = "prev"
  a_prev.setAttribute("title", "前月")
  a_prev.innerHTML = "<"
  a_prev.addEventListener("click", previousMonth)
  // 翌月
  const a_next = document.createElement("a")
  a_next.className = "next"
  a_next.setAttribute("title", "翌月")
  a_next.innerHTML = ">"
  a_next.addEventListener("click", nextMonth)
  // 月表示
  const span_month = document.createElement("span")
  span_month.className = "month"
  span_month.setAttribute("data-month", currentMonth)
  span_month.innerHTML = MONTHS[currentMonth]
panel.append(a_prev)
panel.append(a_next)
panel.append(span_month)
calendar.append(panel)

// 暦本体の為の要素生成
const table = document.createElement("table")
const thead = document.createElement("thead")
let tr = document.createElement("tr")
for (wday in WDAYS) {
  th   = document.createElement("th")
  text = `${WDAYS[wday]}`
  th.append(text)
  tr.append(th)
}
thead.append(tr)
table.append(thead)
calendar.append(table)

// 七曜表を生成
showCalendar(currentYear, currentMonth)

// 前月操作時の各種更新
function previousMonth() {
  currentMonth = (currentMonth === 1) ? 12 : currentMonth - 1
  document.querySelector("#calendar .month").setAttribute("data-month", currentMonth)
  document.querySelector("#calendar .month").innerText = MONTHS[currentMonth]
  // 七曜表生成
  showCalendar(currentYear, currentMonth)
}

// 翌月操作時の各種更新
function nextMonth() {
  currentMonth = (currentMonth === 12) ? 1 : currentMonth + 1
  document.querySelector("#calendar .month").setAttribute("data-month", currentMonth)
  document.querySelector("#calendar .month").innerText = MONTHS[currentMonth]
  // 七曜表生成
  showCalendar(currentYear, currentMonth)
}

// 当月の七曜表を生成
function showCalendar(year, month) {
  // 以前の七曜表を削除
  tbody = document.getElementById("tbody")
  if (tbody !== null) { tbody.remove() }
  // 当月の七曜表を新規作成
  tbody     = document.createElement("tbody")
  tbody.id  = "tbody"

  // 月初の空日処理
  let wday = 0
  let tr   = document.createElement("tr")

  // 今月1日は何曜日か (日曜日: 0, 土曜日: 6)
  let firstDay = zeller(year, month, 1)

  // 月が始まるまでの空日処理
  // (今月1日が土曜日なら 6つ空白が必要)
  for (let date = 1 - firstDay; date < 1; date++, wday++) {
    td = document.createElement("td")
    tr.append(td)
  }

  // 一日から末日までの処理
  for (date = 1; date <= daysInMonth(year, month); date++) {
    td = document.createElement("td")
    td.className = NAME_OF_DAY[wday]  // "sunday", "monday" など
    a = document.createElement("a")
    a.setAttribute("href", "#")
    a.append(date)
    td.append(a)
    tr.append(td)

    // 週末(土曜日)まで処理したら 翌週の行を生成
    if (wday === 6) {
      tbody.append(tr)
      tr = document.createElement("tr")
      wday = 0
    } else {
      wday++
    }
  }
  tbody.append(tr)
  table.append(tbody)
}

// その月の日数を返す
function daysInMonth(year, month) {
  if (leapYear()) {
    // 閏年     1   2   3   4   5   6   7   8   9  10  11  12月
    return [0, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month]
  } else {
    // 平年
    return [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month]
  }
}

// 閏年判定
function leapYear(year) {
  return (year % 4 === 0) && (year % 100 !== 0) || (year % 400 === 0)
}

// ツェラーの公式
// https://ja.wikipedia.org/wiki/ツェラーの公式
function zeller(year, month, day) {
  if (month === 1 || month === 2) {
    month += 12
    year  -=  1
  }

  let d     = day
  let m     = month
  let C     = Math.floor(year/100)
  let Y     = year % 100
  let gamma = -2*C + Math.floor(C/4)

  let h     = (d + Math.floor(26*(m+1)/10) + Y + Math.floor(Y/4) + gamma) % 7
  let wday  = (h + 6) % 7
  // 曜日 日  月  火  水  木  金  土
  // h    1   2   3   4   5   6   0
  // wday 0   1   2   3   4   5   6

  return wday
}
```



若干のCSSの調整を加えて組み込むことで、以下のように簡易ブログサイトが完成します。

![](calendar3a.png)
