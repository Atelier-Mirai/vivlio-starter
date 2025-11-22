# 練習

:::{.chapter-lead}
先の章で「イベントリスナ」について学びました。この章ではいくつかの簡単な例を紹介、イベントリスナやJavaScriptを使ったサイト作成に関する理解を深めていきます。  
:::



## 和風月名

和風月名とは「睦月、如月、彌生、卯月、皐月、水無月、文月、葉月、長月、神無月、霜月、師走」からなる月の呼び方のことです。

後の章では、暦作成を行って参りますが、その前の練習として、和風月名を表示するプログラムを作成してみましょう。


### HTML

HTMLはとっても簡単です。次のようなものにしましょう。

**▼monthname.html**

```
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>和風月名</title>
    <script src="monthname.js" defer></script>
  </head>

  <body>
    <h1>和風月名</h1>

    <button id="next">翌月</button>
  </body>
</html>
```

見出しと翌月ボタンがあるだけのとてもシンプルな構造です。


### JavaScript

JavaScript は、次のようなものにしましょう。

**▼monthname.js**

```

// 和風月名の配列
const MONTHS = ["", "睦月", "如月", "彌生", "卯月", "皐月", "水無月", "文月", "葉月", "長月", "神無月", "霜月", "師走"]

// id が next の要素(=翌月ボタン)を取得
const next = document.getElementById("next")

// 現在の月を取得
let today        = new Date()
let currentMonth = today.getMonth() + 1

// 次の月を表示する為の関数
const nextMonth = () => {
  // p要素を新規作成
  let p = document.createElement("p")
  // 和風月明の配列を用いて MONTHS[curretnMonth] とすることで
  // 現在の月の名前を取得する
  let name = MONTHS[currentMonth]
  // p要素に取得した月名を追加する
  p.append(name)

  // body要素を取得する。
  let body = document.querySelector("body")
  // 取得したbody要素に先ほど作成したp要素を追加する
  body.append(p)

  // 三項演算子を用いて、次の月へと更新する
  currentMonth = (currentMonth === 12) ? 1 : currentMonth + 1
}

// イベントリスナーの登録
// next が click されると nextMonth が実行される
next.addEventListener("click", nextMonth)
```

コードの解説を行っていきましょう。

まず、2行目では和風月名の配列を用意しています。
JavaScriptの配列は`0`から始まりますが、1月なら睦月、2月なら如月、3月なら彌生と対応付けやすくするために、`["", "睦月", "如月", "彌生", (略)]`と、一番先頭には `""`と空文字を入れています。これにより `MONTHS[2]`で睦月、`MONTHS[2]`で如月、`MONTHS[3]`で彌生と対応が取りやすくなります。

9行目では、`getMonth()`メソッドにより、現在の月`currentMonth`を取得しています。JavaScriptの月は`0`から始まるので、`+1`することで、`1`から始まるようにしています。


:::{.note}
**JavaScriptの月が0から始まる理由**

我が国では、睦月、如月、彌生のように月名を呼ぶこともありますが、一月、二月、三月と数字で表すことが多いです。

一方、JavaScriptを開発した欧米の文化では、数字で月を表すよりは、January, February, March と月の名前で呼ぶことが一般的です。

数字から月の名前に変換できるようにするためには、`const MONTHS = ["January", "February", "March"]` と月名の配列を用意して、`MONTHS[0] -> January, MONTHS[1] -> February, MONTHS[2] -> March` とするのが簡単です（変換表、変換テーブルと呼ばれます）。

JavaScriptの配列は `0`から始まりますし、`getMonth`メソッドは**月を表す「添字」**として使われることを想定しているので、`0`から始まることとなっています。

:::


12行目から始まる `nextMonth`関数は内部にコメントも多数ございますので、読み解けることと思いますが、27行目の「三項演算子（条件演算子）」について、説明します。

```
currentMonth = (currentMonth === 12) ? 1 : currentMonth + 1
```

の一文は、以下の `if`文と同様です。

```
if (currentMonth === 12) {
  currentMonth = 1
} else {
  currentMonth = currentMonth + 1
}
```

つまり、ここでは翌月を求める処理を行っているのですが、

```
もし現在の月が12に等しいなら
  現在の月は1月にする
そうでないなら
  現在の月は、現在の月に1を加えた月にする
```

と、12月の次の月は1月ですのでその為の処理をしています。

```
currentMonth = 条件式 ? 成立している時の値 : 成立していないときの値
```

と、`?` と `:` の二つの記号を使って、
短い条件式を簡潔に書き表すことが出来るので、時々用いられます。

![](monthname.png)

実行結果は、右のようになります。
「翌月」ボタンを押すたびに和風月名が表示されますので、確かめてください。


## ミニカレンダー - データ属性の使用


### HTML

和風月名では、月の名前を出すことが出来るようになりました。
前月と翌月ボタンも用意します。
「データ属性」の使用について、ご紹介いたします。

HTMLは次のようにしましょう。

**▼mini_calendar.html**

```
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Mini Calendar</title>
    <style>
      .panel {
        display: grid;
        grid-template-columns: 1fr 3fr 1fr;
        grid-template-rows: auto;
        width: 100px;
        text-align: center;
      }

      .prev { grid-column: 1; grid-row: 1; }
      .name { grid-column: 2; grid-row: 1; margin: 0; }
      .next { grid-column: 3; grid-row: 1; }
    </style>

    <script src="mini_calendar.js" defer></script>
  </head>

  <body>
    <div class="panel">
      <a class="prev" title="前月"><</a>
      <p class="name" data-month="1">睦月</p>
      <a class="next" title="翌月">></a>
    </div>
  </body>
</html>
```

6行目から `<style>` タグを使って、配置等を指定しています。

20行目では `mini_calendar.js` を読み込むことを指定しています。

25行目と27行目についてです。
`<a class="prev" title="前月"><</a>` とコードが書かれています。
まず、 `<` についてですが、これは「文字参照」と呼ばれる記法です。
前月を表すための「`<`」を表示したいのですが、HTMLでは「`<`」は特別な意味を持つ為、そのまま記述することが出来ません。このような場合に文字参照を用います。

また、 `title="前月"` とタイトル属性が付与されています。画面に表示された「`<`」の上にマウスカーソルを重ね、暫く待つと「前月」と表示されます。「`<`」がどのような機能なのかを表示することが出来、使う人に好まれる親切な設計となります。

26行目の `<p class="name" data-month="1">睦月</p>` についてです。注目して頂きたいのは `data-month="1"` です。 これは「データ属性」と呼ばれるもので、 `data-`に続けて、プログラマが好きな文字列を記述できます。ここでは「睦月」が「1月」であることを、JavaScriptから把握しやすくするために `data-month="1"` とコードを書いています。


### JavaScript

ミニカレンダーのための JavaScript は次のようにしましょう。

**▼mini_calendar.js**

```
// 和風月名の配列
const MONTHS = ["", "睦月", "如月", "彌生", "卯月", "皐月", "水無月", "文月", "葉月", "長月", "神無月", "霜月", "師走"]

// 現在何月を表示中か取得する
let name = document.querySelector(".name")
// datasetプロパティを通して データ属性 data-month="1" の値を取得する
let stringMonth = name.dataset.month
// datasetプロパティを通して取得した値は文字列なので、
// 計算に用いることができるよう、Number関数により数値型に変換する
currentMonth = Number(stringMonth)

// 前月操作時の各種更新
const previousMonth = () => {
  currentMonth = (currentMonth === 1) ? 12 : currentMonth - 1
  // データ属性に更新したcurrentMonthを設定する
  name.dataset.month = currentMonth
  name.innerText = MONTHS[currentMonth]
}

// 前月操作時の各種更新
const nextMonth = () => {
  currentMonth = (currentMonth === 12) ? 1 : currentMonth + 1
  // データ属性に更新したcurrentMonthを設定する
  name.dataset.month = currentMonth
  name.innerText = MONTHS[currentMonth]
}

// イベントリスナの登録
const prev = document.querySelector(".prev")
prev.addEventListener("click", previousMonth)
const next = document.querySelector(".next")
next.addEventListener("click", nextMonth)
```

ポイントとなるのは「データ属性」についてです。

HTML中に `<p class="name" data-month="1">睦月</p>` と、データ属性 data-month="1" を書きましたので、この値 `"1"`を JavaScript から読み書きしたいのです。

その為には、まずこの `<p>` 要素全体を、JavaScriptから操作できるよう、 `let name = document.querySelector(".name")`として、 `name`に取得します。

そして、この取得した `name` から `data-month` の値を読み込む為には、

```
let stringMonth = name.getAttribute("data-month")
```

のように読み込むことができます。

そして、データ属性の読み書きは良く用いるので、より簡便な方法が用意されています。それが8行目に書かれている次のコードです。

**▼データ属性の値を読み込む**

```
let stringMonth = name.dataset.month
```

また、データ属性に値を書き込む際には、17行目に書かれているようにします。

**▼データ属性の値を書き込む**

```
name.dataset.month = currentMonth
```

より、詳しくは MDN [データ属性の使用](https://developer.mozilla.org/ja/docs/Learn/HTML/Howto/Use_data_attributes) に書かれておりますので、ご参照下さい。


## 単位変換


### ウェブサイトで使われる様々な単位

ウェブサイトを作成していく中では沢山の単位に出会います。px（ピクセル）や`em`、新しいところでは `vw`や`vh`などもあります。

ここでは、`1 インチ = 25.4mm = 96px` という関係式を使って、相互に単位を変換できるサイトを作ることにします。


### HTML

単位変換の為のHTMLは次のようにしましょう。

**▼units.html**

```
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>単位</title>
    <!-- sakura CDN -->
    <link rel="stylesheet" href="https://unpkg.com/sakura.css/css/sakura.css">
    <style>
      [type="number"] { width: 7em; margin: 0; text-align: center; }
      fieldset { padding: 1em; text-align: center; }
    </style>
    <script src="units.js" defer></script>
  </head>

  <body>
    <h1>単位</h1>
    <p>単位を変換します。</p>
    <form id="form">
      <fieldset>
        <input  type="number" name="inch" id="inch" value="1">インチ
        <input  type="number" name="mm"   id="mm">ミリメートル
        <input  type="number" name="px"   id="px">ピクセル
        <button type="button"             id="calc">変換する</button>
      </fieldset>
    </form>
  </body>
</html>
```

HTMLは大きく`<head>`と`<body>`に分かれますが、`<head>`タグの中では`CDN`より`sakura.css`を読み込んでいます。それが7行目のコードです。

`CDN` は `Content Delivery Network`の略で、その名の通り、コンテンツが高速に配信できるよう構築されたネットワークで、有志の方々が作成した多くの優れたコンテンツが登録されています。通常、有志の方々が作成したソースコードを用いる際には自分の手元のコンピュータにダウンロードする必要がありますが、CDNを用いると手元にダウンロードすることなく、すぐにウェブサイト制作に取り掛かることができます。

`sakura.css` は、センスのよいウェブサイトを創る為の軽量でシンプルなCSSフレームワークです。通常、フレームワークを利用する為には、そのフレームワークの使い方を学ぶ為に少し学習時間をとる必要がありますが、`sakura.css` は 「HTMLタグに直接スタイルを適用するだけ」のとても簡潔なフレームワークなので、すぐに使い始めることが出来ます。 [^180]

[^180]: [公式サイト](https://github.com/oxalorg/sakura),[デモサイト](https://oxal.org/projects/sakura/demo)です。

8行目〜11行目は、`<style>`タグを用いて、若干のスタイルの補正を行っています。通常、ウェブサイトを作成する際には、別に作成したスタイルシートを読み込みますが、このような短い練習用のサイトの場合には、`<style>`タグの中に、適用したいCSSルールを直接書くこともできます。

9行目の `[type="number"]` は、`type` 属性の値が `number` である要素を選択しているセレクタです。20行目〜22行目にかけて、1インチや10mmなど、変換したい数値を入れる為の入力枠が用意されています。この入力枠の幅を調整しています。

12行目では、入力枠に入れられた数字を読み取り、変換結果を書き込むためのJavaScriptコード `units.js`を読み込んでいます（これからわたくしたちが作成して行くコードです）。

`defer` について説明します。通常ブラウザは、読み込まれた順番に処理を行っていきますので、12行目を読み込むと、直ちにそこに書かれたプログラムコードを実行しようとします。しかしながら、12行目に到達した時点では、18行目から始まる `<form>` の内容は表示されておらず、ブラウザを見ている利用者も入力枠に値も入れていない状態です。当然、入力枠の内容を読み取ったり書き込んだりすることは出来ないので、エラーとなり、プログラムはそこで終了してしまいます。これを防ぐ為に `defer` と記述します。すると12行目のJavaScriptコードの実行は一旦保留されます。そしてHTMLが最終行の27行目まで読み込まれたのちに、保留していた12行目のJavaScriptコードが実行されるようになります。

`<body>`タグで見るべきところは何といっても `<form>` タグです。`<form>` タグは入力した内容をサーバに送信する為に用いられます。ここではインチやミリメートル、ピクセルの値を入力した後に「変換する」ボタンが押されたら、それぞれの枠の入力値値を取得、変換結果を各枠に表示するようにします。

20行目の `<input type="number">`は、枠に半角数字のみが入力できるように制約する為の記法です。そしてこの単位変換サイトでは複数の入力枠があるので、どの入力枠なのかJavaScriptコードから扱いやすくするために `id="inch"` とID属性を付与しています。さらに初期値として `value="1"` と書き、「1インチ」が表示されるようにしています。

23行目の `<button type="button">`は、その名の通り「変換する」ボタンをつくるためのタグです。通常、 `<form>`タグの中では、サーバーに入力内容を送信する為のボタンとして `<button type="submit">` が用いられますが、ここでは「変換する」ボタンにイベントリスナを設定、変換処理を記述したい為、`<button type="button">` としています。

作成例は次のようになります。
CDNより読み込んだCSSフレームワーク`sakura.css`も適用されているので、綺麗な仕上がりとなっています。

![単位変換サイト 作成例](units1.png)


### JavaScript

単位変換のためのJavaScriptコードの例は次のようになります。

**▼units.js**

```
// HTML中の各要素を取得する
const form      = document.getElementById("form")
const inputInch = document.getElementById("inch")
const inputMm   = document.getElementById("mm")
const inputPx   = document.getElementById("px")
const calc      = document.getElementById("calc")

// イベントリスナ
// calcボタンをクリックした際の処理を登録
calc.addEventListener("click", () => {
  // FormDataクラスのインスタンスを生成すると
  // <form>内の各<input>枠に入力された値が取得しやすくなる
  const formData  = new FormData(form)

  // formDateから各枠(inch, mm, px)の入力値を取得する
  let inch = formData.get("inch")
  let mm   = formData.get("mm")
  let px   = formData.get("px")

  // 入力値は「文字列」として取得されるので
  // 計算に使えるよう NUmber関数により 数値に変換する
  inch     = Number(inch)
  mm       = Number(mm)
  px       = Number(px)

  // inch枠になにか数字が入力されていたなら
  if (inch !== 0) {
    // inchをもとにmmやpxを算出する
    mm = inch * 25.4
    px = inch * 96
  } else if (mm !== 0) {
    inch = mm / 25.4
    px   = inch * 96
  } else if (px !== 0) {
    inch = px / 96
    mm   = inch * 25.4
  }

  // 小数点以下三桁に整形する
  // 例: 9.6 -> "9.600"
  inch = pretyFormat(inch)
  mm   = pretyFormat(mm)
  px   = pretyFormat(px)

  // 各入力枠(inch, mm, px)に値を設定する
  inputInch.value = inch
  inputMm.value   = mm
  inputPx.value   = px
})

// 小数点以下三桁に整形するための関数
// 例: 9.6 -> "9.600" を返す
pretyFormat = (n) => {
  n               = n + 2000 * Number.EPSILON
  n               = Math.floor(n * 1000) / 1000
  integerPart     = Math.floor(n)
  decimalFraction = (n % 1) + 2000 * Number.EPSILON
  decimalFraction = Math.round(decimalFraction * 1000)

  if (decimalFraction < 10) {
    decimalFraction = `00${String(decimalFraction)}`
  } else if (decimalFraction < 100) {
    decimalFraction = `0${String(decimalFraction)}`
  }

  return `${integerPart}.${decimalFraction}`
}
```

特筆すべきは`FormData`です。`<form>`要素内に入力された値を取得する際に使うと大変便利です。より詳しくは、MDN https://developer.mozilla.org/ja/docs/Web/API/FormData/FormDataや https://developer.mozilla.org/ja/docs/Web/API/FormData に詳しい説明や用法が紹介されておりますので、ご覧ください。

他は適宜コメントを付与しておりますので、読み取っていけることと思います。

実行例は次のようになります。

![](units2.png)
1インチと入力後「変換する」ボタンを押すと、25.400ミリメートルや96.000ピクセルであると表示されています。


## 誕生日

単位変換に続いては、誕生日について扱っていきましょう。生まれてから七日目の「お七夜」、お百日目の「お食い初め」など、節目節目で様々な記念日がございます。今日は生まれてから何日目なのかを計算して見ましょう。また始めのうちは○日と数えることが出来ますが、数が大きくなるに従って○歳と年数で数えるようになります。指折り数えて一万日目の記念日はいつなのか、日付も求めて見ましょう。

その為のHTMLは例えば次のようになります。


### HTML

**▼birthday.html**

```
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>誕生日</title>
    <!-- sakura CDN -->
    <link rel="stylesheet" href="https://unpkg.com/sakura.css/css/sakura.css">

    <style>
      p { margin-bottom: 0; }
      [type="number"] { width: 5em; margin: 0; text-align: center; }
      #anniversary    { width: 8em; }
      form            { text-align: center; }
      fieldset        { margin: 0; padding: 1em; }
      output          { display: block;
                        border-bottom: 1px solid black;
                        text-align: center;
                        margin-bottom: 2em; }
    </style>
    <script src="birthday.js" defer></script>
  </head>

  <body>
    <h1>日数計算</h1>

    <p>誕生日から今日までの日数を計算します</p>
    <form id="form-birthday">
      <fieldset>
        <select name="gengo" id="gengo">
          <option value="meiji" >明治</option>
          <option value="taisho">大正</option>
          <option value="showa" >昭和</option>
          <option value="heisei">平成</option>
          <option value="reiwa" >令和</option>
        </select>
        <input type="number" name="year"  id="year"  min="1" max="64" value="6">年
        <input type="number" name="month" id="month" min="1" max="12" value="1">月
        <input type="number" name="date"  id="date"  min="1" max="31" value="1">日
        <button type="button" name="submit" id="calc-birthday">計算する</button>
      </fieldset>
    </form>
    <output id="output-birthday">&nbsp;</output>

    <p>(生まれてから10000日目など) 記念日の日付を計算します</p>
    <form id="form-anniversary">
      <fieldset>
        <input type="number" name="anniversary" id="anniversary" min="1" max="50000" placeholder="10000" value="10000">日
        <button type="button" name="submit" id="calc-anniversary">計算する</button>
      </fieldset>
    </form>
    <output id="output-anniversary">&nbsp;</output>
  </body>
</html>
```

大きく二つのフォームが用意されています。
一つは「誕生日から今日までの日数を計算する」為のフォーム、もう一つは「生まれてから10000日目など記念日の日付を計算する」為のフォームです。

フォームの構成についてですが、`<filedset>`タグ は、いくつかのフォーム内の部品をひとまとまりにして扱う為に使われます。「元号」「年」「月」「日」「計算する」ボタンで、ひとまとまりとします。

`<select>`タグ を用いると「元号」を選択することが出来るようになります。

年や月や日を入力する為の `<input>`タグには `min="1" max="64"` と書かれています。昭和は元年から六四年まで続きました。最小値と最大値を指定することで、入力値がその範囲内に納まるようにしています。

`<output>` タグは、その名の通りシステムからの「出力結果」を表示するためのタグです。ここでは誕生日からの日数や記念日の日付を出力する為に準備しています。

中に書かれている `&nbsp;` は実体参照と呼ばれ、「Interpreted as the **n**on **b**reaking **sp**ace.(自動的な改行が禁止された空白文字)」[^181] の意味です。
通常、HTML で空白文字を入力しても存在しないものとして扱われますが、`&nbsp;` により半角空白がある事になります。

[^181]: [実体参照](https://developer.mozilla.org/en-US/docs/Glossary/Entity)


### 元号について

暦を巡る話題は興味深いものがあります。古くから日月の動きを知り天文気象地理から民の為良き政治を行うことは為政者の務めでした。そしてその土地土地に良き名を付け豊作を願うのと同じくして、良き歳月であれとの祈りを込めて元号は付けられました。

明治は、明治天皇の即位なされた明治元年9月8日から崩御された明治45年7月30日までです。
暦を大きく分けると、太陽の運行を元にした太陽暦、月の動きを元にした太陰暦、両者を折衷した太陰太陽暦があり、天保歴（太陰太陽暦）は今日も七夕やお月見など、愛され親しまれています。
明治五年にこれまで使われていた天保歴(太陰太陽暦)から、太陽暦へ改暦する旨、太政官布告が出されました。これにより、明治五年12月2日 の翌日が 明治六年1月1日となりました。

大正は、明治天皇の崩御された明治45年7月30日を即日改元、大正元年7月30日としたのが始まりで、大正15年12月25日まで続きます。同じ一日ですが、明治45年7月30日は大正元年7月30日でもあります。

昭和は、日本で最も長い元号で、大正天皇の崩御された大正15年12月25日を即日改元、昭和元年12月25日としました。同様に一日ですが、大正15年12月25日は昭和元年12月25日でもあります。
そして、昭和天皇が崩御された昭和64年1月7日を以て、長い昭和の御代は幕を閉じます。

平成は、昭和天皇の崩御の翌日、平成元年1月8日に始まり、平成31年4月30日に、今上陛下への上位を以て幕引きとなります。

令和は、令和元年5月1日より現在に至るまで続く元号です。


纏めると次のようになります。
---


:::{.tip}
{.aki}
**明治**<br>
明治元年9月8日(1868年10月23日)〜明治45年7月30日(1912年7月30日)<br>
明治五年12月2日 1872年12月31日 <br>
天保歴(太陰太陽暦)から、太陽暦への改暦 <br>
明治六年1月1日(1873年1月1日)<br>
{.aki}
**大正**<br>
大正元年7月30日(1912年)-大正15年12月25日(1926年) <br>
{.aki}
**昭和**<br>
昭和元年12月25日(1926年)-昭和64年1月7日(1989年)
{.aki}
**平成**<br>
平成元年1月8日(1989年)-平成31年4月30日(2019年)<br>
{.aki}
**令和**<br>
令和元年5月1日(2019年)-
:::

### ユリウス通日と修正ユリウス日

[ウィキペディア](https://ja.wikipedia.org/wiki/ユリウス通日) より抜粋してご紹介いたします。


**ユリウス通日（つうじつ**（Julian Day：JD））は1583年にスカリゲルによって考案された。スカリゲルは1582年のグレゴリオ暦改暦によって年代学における日付けの計算が煩雑かつ混乱してしまうことを予想して、ユリウス暦、グレゴリオ暦双方での日付の換算や日数計算の便のためにこれを考案した。

スカリゲルが基準にした紀元前4713年は、以下の3つの周期の第1年目が重なる年であった。

* 太陽章（英語版）（28年） - 日付と七曜が揃う周期
* 太陰章（メトン周期）（19年） - 月相（月の満ち欠け）と日付が揃う周期
* インディクティオ（15年） - ローマ帝国での徴税額の査定更正周期

その後、天文学者ジョン・ハーシェルが日数や時間の計算にユリウス通日を利用する方法を考案した。これが広まり、世界中の天文学者が日数計算にユリウス通日を用いるようになった。

ユリウス通日は二時点の間の日数や秒数を計算するのに便利で、天文学や年代学などで使われている。小数を付けることにより時・分・秒数を表現することができる。


**修正ユリウス日（Modified Julian Date：MJD）**は、ユリウス通日から2 400 000.5を差し引いたものである。元々は、整数部の桁数を5桁に収めるように、スミソニアン天体物理観測所（SAO）の宇宙科学者が1957年に考案したもので、これはソ連のスプートニクの軌道を追跡するために用いられたIBM 704コンピュータの記憶容量が小さく、桁数を少なくする必要があったためである。

ユリウス通日の値は19世紀後半（1858年11月17日）から22世紀前半（2132年8月31日）までは、2 400 000台の数値であり、現代における利用には整数部が5桁のMJDで十分に実用的と考えられたのである。


### グレゴリオ暦と修正ユリウス日との相互変換

相互変換の為の公式は次の通りです（1月、2月は、前年の13月、14月として計算します）。

**グレゴリオ暦から修正ユリウス日へ**

![](g2m.png)
**修正ユリウス日からグレゴリオ暦へ**

![](m2g.png)


### JavaScript - 修正ユリウス日を用いて

ユリウス通日・修正ユリウス日は、ある日を0日目(元期)として、1日目、2日目と数えていく方法ですので、二時点の間の日数を計算するのに大変便利です。

ですので、入力された日付から直接計算するのではなく、修正ユリウス日を仲立ちにして求めることとしましょう。

暦の変換を行う為に次の関数を用意すれば良さそうです。

* 和暦からグレゴリオ暦へ変換する為の関数
* グレゴリオ暦から和暦へ変換する為の関数
* グレゴリオ暦から修正ユリウス日を返す為の関数
* 修正ユリウス日からグレゴリオ暦を返す為の関数

また、出力結果を綺麗に出す為に、以下の関数も用意しましょう。

* 和暦を綺麗に整形して出力する為の関数
* 0詰めした二桁を返す為の関数

これらの関数の準備が出来たら、

* 誕生日から今日までの日数を返す関数
* 誕生日から10000日経過した記念日など日付を返す関数

を作成しましょう。ここまでで準備は完了です。

あとは、誕生日からの日数計算ボタンが押されたときには、フォームからの日付を読み取り、グレゴリオ暦に変換、後は、誕生日から今日までの日数を返す関数 を呼ぶだけで処理が完了しますし、同様に、記念日の日付を計算するボタンが押されたときには、フォームからの日付を読み取り、グレゴリオ暦に変換、後は、記念日の日付を計算する関数 を呼ぶだけで処理が完了します。

なお、本来であれば、存在しない日付（2月30日など）や明治改暦以前の日付を入力された際に、エラーメッセージを表示するなどの処理も必要ですが、ここでは簡単化の為に「正しい日付が入力されるもの」として、作成しましょう。

作成例は次のようになります。

**▼birthday.js**

```
/*=====================================================================
  日数変換に用いる各種関数の定義
=====================================================================*/

/* 和暦からグレゴリオ暦へ変換する為の関数
-------------------------------------------------------------------------*/
const Wareki2Gregorian = (gengo, year, month, date) => {
       if (gengo === "meiji")  { year += 1867 }
  else if (gengo === "taisho") { year += 1911 }
  else if (gengo === "showa")  { year += 1925 }
  else if (gengo === "heisei") { year += 1988 }
  else if (gengo === "reiwa")  { year += 2018 }

  return [year, month, date]
}

/* グレゴリオ暦から和暦へ変換する為の関数
-------------------------------------------------------------------------*/
const Gregorian2Wareki = (year, month, date) => {
  // 各元号末日の修正ユリウス日
  const MEIJI_ERA  = 19613
  const TAISHO_ERA = 24874
  const SHOWA_ERA  = 47533
  const HEISEI_ERA = 58603
  let gengo = ""

  // 修正ユリウス日を求める
  let mjd = Gregorian2MJD(year, month, date)

  // 元号とグレゴリオ暦年を求める
       if (mjd <= MEIJI_ERA)  { gengo = "meiji";  year -= 1867 }
  else if (mjd <= TAISHO_ERA) { gengo = "taisho"; year -= 1911 }
  else if (mjd <= SHOWA_ERA)  { gengo = "showa";  year -= 1925 }
  else if (mjd <= HEISEI_ERA) { gengo = "heisei"; year -= 1988 }
  else                        { gengo = "reiwa";  year -= 2018 }

  // 算出結果を返す
  return [gengo, year, month, date]
}

/* グレゴリオ暦から修正ユリウス日を返す為の関数
-------------------------------------------------------------------------*/
const Gregorian2MJD = (year, month, date) => {
  // 1月や2月は前年の13月,14月として扱う
  if (month === 1 || month === 2) {
    month += 12
    year  -= 1
  }

  // 公式に従い、修正ユリウス日mjdを求める
  let mjd = Math.floor(365.25 * year)
          + Math.floor(year / 400)
          - Math.floor(year / 100)
          + Math.floor(30.59 * (month - 2))
          + date
          - 678912

  // 算出結果を返す
  return mjd
}

/* 修正ユリウス日からグレゴリオ暦を返す為の関数
-------------------------------------------------------------------------*/
const MJD2Gregorian = (mjd) => {
  // 与えられた修正ユリウス日mjdから、公式に従い、グレゴリオ暦を求める
  n = mjd + 678881
  a = 4*n + 3 + 4*Math.floor((3.0/4.0) * Math.floor(4*(n+1)/146097 + 1))
  b = 5 * Math.floor( (a % 1461) / 4) + 2
  y = Math.floor(a / 1461)
  m = Math.floor(b / 153) + 3
  d = Math.floor((b % 153) / 5) + 1
  if (m === 13 || m === 14) {
    m = m - 12
    y = y +  1
  }

  // 算出結果を返す
  return [y, m, d]
}

/* 和暦を綺麗に整形して出力する為の関数
-------------------------------------------------------------------------*/
const pretyFormat = (gengo, year, month, date) => {
  // 変換表(変換テーブル)
  const table = { "meiji": "明治", "taisho": "大正", "showa": "昭和", "heisei": "平成", "reiwa": "令和" }

  // 令和1年ではなく、令和元年と出力する為に
  year = (year === 1) ? "元" : sprintf("%02d", year)

  // 整形結果を返す
  return `${table[gengo]}${year}年${sprintf("%02d", month)}月${sprintf("%02d", date)}日`
}

/* sprintf: 書式指定子に基づき、引数を整形して返す関数
  "%02d" で 0詰めした二桁を返す
-------------------------------------------------------------------------*/
const sprintf = (format, number) => {
  // 一桁の数なら、0詰めして返す
  if (format === "%02d" && number < 10) {
    return `0${number}`
  } else {
    return number
  }
}

/* 誕生日から今日までの日数を返す為の関数
-------------------------------------------------------------------------*/
const daysAliveFromBirthday = (year, month, date) => {
  // 誕生日の修正ユリウス日を求める
  birthdayMjd = Gregorian2MJD(year, month, date)

  // 今日の日付を取得
  let today = new Date()
  ty = today.getFullYear()
  tm = today.getMonth() + 1
  td = today.getDate()
  if (tm === 1 || tm === 2) {
    tm += 12
    ty -=  1
  }
  // 今日の修正ユリウス日を求める
  todayMjd = Gregorian2MJD(ty, tm, td)

  // 引き算をすることで、何日経過したか、判明する
  return todayMjd - birthdayMjd
}

/* 誕生日から10000日経過した記念日など日付を返す為の関数
-------------------------------------------------------------------------*/
const dateFromBirthdayToAnniversary = (year, month, date, elapsedDays) => {
  // 誕生日の修正ユリウス日を求める
  birthdayMjd = Gregorian2MJD(year, month, date)

  // 経過日数elapsedDaysを誕生日の修正ユリウス日に加えると、
  // 記念日の修正ユリウス日になる
  anniversaryMjd = birthdayMjd + elapsedDays

  // 修正ユリウス日をグレゴリオ暦に変換、日付を返す
  return MJD2Gregorian(anniversaryMjd)
}

/*=====================================================================
  入力フォームの処理
  誕生日から今日までの日数を計算する為に
=====================================================================*/

// 誕生日フォームの為の定数宣言
const formBirthday   = document.getElementById("form-birthday")
const calcBirthday   = document.getElementById("calc-birthday")
const outputBirthday = document.getElementById("output-birthday")

// 誕生日の計算するボタンの為のイベントリスナ
calcBirthday.addEventListener("click", () => {
  // form から入力された値を取得する
  let formDataBirthday = new FormData(formBirthday)
  let gengo = formDataBirthday.get("gengo")
  let year  = formDataBirthday.get("year")
  let month = formDataBirthday.get("month")
  let date  = formDataBirthday.get("date")

  // form から取得した値は文字列型なので、数値型に変換する
  year  = Number(year)
  month = Number(month)
  date  = Number(date)

  // 和暦からグレゴリオ暦に変換
  let y, m, d
  [y, m, d] = Wareki2Gregorian(gengo, year, month, date)

  // 生きてきた日数を求める
  let daysAlive = daysAliveFromBirthday(y, m, d)

  // 出力する
  outputBirthday.textContent = `今日は 生まれてから 「${daysAlive}」日目の記念日です`
})

/*=====================================================================
  入力フォームの処理
  (生まれてから10000日目など) 記念日の日付を計算する為に
=====================================================================*/

// 記念日フォームの為の定数宣言
const formAnniversary   = document.getElementById("form-anniversary")
const calcAnniversary   = document.getElementById("calc-anniversary")
const outputAnniversary = document.getElementById("output-anniversary")

// 記念日の計算するボタンの為のイベントリスナ
calcAnniversary.addEventListener("click", () => {
  // form から入力された値を取得する(誕生日)
  let formDataBirthday = new FormData(formBirthday)
  let gengo = formDataBirthday.get("gengo")
  let year  = formDataBirthday.get("year")
  let month = formDataBirthday.get("month")
  let date  = formDataBirthday.get("date")
  // form から入力された値を取得する(記念日)
  let formDataAnniversary = new FormData(formAnniversary)
  let anniversary = formDataAnniversary.get("anniversary")

  // form から取得した値は文字列型なので、数値型に変換する
  year        = Number(year)
  month       = Number(month)
  date        = Number(date)
  anniversary = Number(anniversary)

  // 和暦からグレゴリオ暦に変換
  let gy, gm, gd
  [gy, gm, gd] = Wareki2Gregorian(gengo, year, month, date)

  // 生まれてからanniversary日目の日付を求める
  let ay, am, ad
  [ay, am, ad] = dateFromBirthdayToAnniversary(gy, gm, gd, anniversary)

  // 和暦に変換する
  let wg, wy, wm, wd
  [wg, wy, wm, wd] = Gregorian2Wareki(ay, am, ad)

  // 見やすいように整形する
  let day = pretyFormat(wg, wy, wm, wd)

  // 出力する
  outputAnniversary.textContent = `生まれてから ${anniversary} 日目の記念日は「${day}」です`
})
```

比較的長いコードとなりましたが、設計方針を立て、必要な部品を組み立てて行くことで作り上げることが出来ます。また、途中正しく計算できているかどうか、要所要所で、確認すると良いでしょう。 `console.log("年月日", year, month, date)` などを挿入すると、ブラウザの開発者ツールのコンソール画面から、各変数 `year, month, date` の値を確認することが出来ます。

実行例は次のようになります。

![](birthday.png)


## 写真を表示する その１

さて、ここまで練習として計算問題を取り上げてきました。コンピューターは計算するために発明された機械だからなのですが、もう少しウェブサイトを創る上で実用的な例が欲しいと感じられたのではないでしょうか。

そこで、「写真をクリックしたら拡大して表示される」機能を作って見ましょう。ウェブサイトでもよく見られる「ライトボックス」と呼ばれるものです。

もともとは、「ライトボックス」とは、写真フィルムなどの確認に用いられるものを指しています。

> **ライトボックス**
> 蛍光灯やLED照明が入った箱で、一つの面が半透明のアクリル板などでできているもの。内部からの透過光により、半透明の面に置いた写真用フィルムやアニメーションのセル画などをチェックすることができる。(デジタル大辞泉)

![](lightbox.jpg)
そこから転じて、ウェブサイトでよく見られる、「写真をクリックしたら拡大して表示される」機能を指すようになりました。

> ライトボックスとは、Webページ上のサムネイル画像を拡大表示できるJavaScriptのライブラリ、および、そのライブラリを使用して実現できる画像表示機能のことである。ボルチモア在住のWebデザイナー、Lokesh Dhakarによって開発された。(IT用語辞典 BINARY)

ここでは maybe(かもしれない) lightbox ということで、mightbox と名付け、作成しましょう。


### HTML

HTMLは次のようにコーディングしましょう。

**▼mightbox.html**

```
<!DOCTYPE html>
<html>
        <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width">
                <title>Mightbox</title>
                <link rel="stylesheet" href="mightbox.css">
                <script src="mightbox.js" defer></script>
        </head>

        <body>
                <h1>Mightbox</h1>

                <!-- サムネイル画像（縮小画像）と原画像 -->
                <a href="sakura.webp" class="mightbox">
                        ![](sakura_thumb.webp)
                </a>
        </body>
</html>
```

サムネイルは「親指の爪」の意味です。親指の爪のように小さな画像、縮小画像を意味しています。ウェブサイトでは画像の概要だけを確認できれば良い場面に使われ、画像が小さく軽いので速く表示することが出来ます。

サムネイル画像 `sakura_thumb.webp` をみて興味を持った利用者が、より詳細を確認したいときに、クリックすることで原画像 `sakura.webp`が表示されるようにします。

その為のコードが15行目から始まる `<a>`タグです。


### CSS

それでは次にCSSです。
ひとまず、次のように書きましょう。

**▼mightbox.css**

```
/* リセットCSS */
*,
*:after,
*:before {
  box-sizing: border-box;
}

/* body 内の各要素を中央揃えにする */
body {
  display: grid;
  justify-items: center;        /* グリッドアイテム(<h1>や<a>)を水平方向で中央揃え */
        align-items: center;            /* グリッドアイテム(<h1>や<a>)を垂直方向で中央揃え */
  min-height: 100vh;
}
```

ここまでの結果は次のようになります。

![](mightbox1.png)
画面の中央に、見出しとサムネイル画像が表示されています。

このサムネイル画像をクリックすると、ブラウザの働きにより別のタブで原画像の表示がされます。

別のタブではなく、「同じタブ内で写真を大きく前面に表示したい」と思います。

どうすれば良いでしょうか。
古くからある方法は、原画像を表示するために以下のような HTML を用意しておき、普段は隠しておき、サムネイル画像がクリックされたときに表示させるというものです。

**▼原画像表示の為のHTML**

```
<div id="modal">
  ![](sakura.webp)
</div>
```

この HTML を前面に全画面で表示させる為のCSSは次のようになります。

**▼全画面表示用の追加CSS**

```
/* 全画面表示用の要素 */
#modal {
        display: grid;                                  /* グリッドレイアウトモードにする */
  place-items: center;    /* justify-items: center; align-items: center; と同じ */

  /* body内の他の要素の上に重ねて表示する */
        position: absolute;
        top: 0;
        left: 0;
        z-index: 10000;

  /* 全画面で表示する */
        width: 100vw;
        height: 100vh;

        background: #feeeed80;  /* 背景色の設定(桜色) */
        cursor: pointer;                                /* マウスカーソルの形状は、ポインタ（指印） */

        /* 原画像を表示するためのimg要素 */
        img {
                width: 100%;                                    /* 幅100% */
                max-width: 100vw;                       /* 最大幅は画面幅 */
                height: auto;                                   /* 高さは画像幅に応じて自動調整 */
        }
}

/* サムネイル画像(縮小画像)にhiddenクラスが付与されたら、非表示にする */
.hidden {
        display: none;
}
```


### JavaScript

それでは、原画像表示の為のHTMLをどのように作れば良いのでしょうか。サムネイル画像を配置する都度、原画像用のHTMLを準備することは考えられますが、手間です。そこで、JavaScriptを用いて、サムネイル画像がクリックされた際に、動的にHTMLを生成することを考えます。そのためのコードは次のようになります。

**▼mightbox.js**

```
// mightboxクラス(複数ある場合は先頭要素のみ)を取得する
let mightbox = document.querySelector(".mightbox")

// イベントリスナを登録、mightboxクリック時の処理を記述する
mightbox.addEventListener("click", (event) => {
  // aタグのリンク先への遷移を停止する
  event.preventDefault()

  // 画像表示用の要素 #modal を作成
  let modal = document.createElement("div")
  modal.id = "modal"

  // img要素を作成
  let img = document.createElement("img")
  // 表示したい原画像のURLを href属性より取得し、設定する
  img.src = mightbox.getAttribute("href")

  // #modal に img 要素を追加する
  modal.append(img)
  // body に #modal要素を追加する（原画像が表示されるようになる）
  document.querySelector("body").append(modal)
  // サムネイル画像（縮小画像）が見えぬよう、hiddenクラスを追加する
  mightbox.classList.add("hidden")

  // イベントリスナを登録、#modalクリック時の処理を記述する
  modal.addEventListener("click", () => {
    // サムネイル画像（縮小画像）が見えるよう、追加したhiddenクラスを削除する
    mightbox.classList.remove("hidden")
    // #modal要素を削除する（元頁が表示されるようになる）
    modal.remove()
  })
})
```

比較的短いコードとなっています。JavaScriptでHTMLを追加、削除したり、あるいはイベントリスナを登録するなど、先に学習した事柄を活かした例となっています。

コメントもつけてございますので、一行、一行、読み解いて行けるかと思います。

サムネイル画像をクリックすると、次のように原画像が前面に表示されます。

![](mightbox2.png)


## 写真を表示する その２

モーダルウィンドウを実現する為には、先の例のようにHTMLを追加し、仮想的に最前面の層（トップレイヤー）として扱っていました。

そして、モーダルウィンドウは良く用いられる機能なので、その為の専用のHTMLタグが用意されました。 それが `<dialog>` タグです。

これを用いると、より簡潔なCSSやJavaScriptで、モーダルウィンドウを実現できます。

[Meet the top layer: a solution to z-index:10000(トップ層の紹介 z-index:10000の解決策)](https://developer.chrome.com/blog/what-is-the-top-layer/) にその使い方が紹介されておりますが、少し簡略化して、写真表示の為のライトボックスにしてみましょう。


### HTML

HTML は次のように書きましょう。

**▼toplayer.html**

```
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Top Layer</title>
    <link rel="stylesheet" href="toplayer.css">
    <script src="toplayer.js" defer></script>
  </head>

  <body>
    <h1>Top Layer</h1>

    <!-- サムネイル画像 -->
    ![](sakura_thumb.webp)

    <!-- 原画像 -->
    <dialog>
      ![](sakura.webp)
    </dialog>
  </body>
</html>
```


### CSS

CSS は次のように書きましょう。

**▼toplayer.css**

```
/* リセットCSS */
*,
*:after,
*:before {
  box-sizing: border-box;
}

/* body 内の各要素を中央揃えにする */
body {
  display: grid;
  place-items: center;
  min-height: 100vh;
}

/* ダイアログボックス */
dialog {
  background: #fef4f4; /* 桜色 */
  border-radius: 30px;
  width: 50vw;
  height: 50vw;

  /* 開いた際、ダイアログボックスの枠線等を消す */
  &[open] {
    border: none;
    outline: none;
  }

  /* 背景色 */
  &::backdrop {
    background: #0d0d0dc0; /* 黒羽色 */
    backdrop-filter: blur(4px);
  }

  /* 原画像 */
  img {
    /* 原画像が大きいときの為に、最大値を設定 */
    max-width: 90%;
    max-height: 90%;

    /* 画像を中央揃え */
    position: absolute;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
  }
}
```

ここまでの実行例は次のようになります。

![](toplayer1.png)


### JavaScript

`<dialog>` タグの中の原画像は、表示されていないことにも注目してください。
`<dialog>` タグを表示させるには、JavaScriptから表示させる為の専用メソッドを呼ぶ必要があります。

その為のコードは次のようになります。

**▼toplayer.js**

```
// HTML中の各要素（サムネイル画像、原画像、ダイアログ要素）を取得
const THUMBNAIL_IMAGE = document.querySelector(".open-dialog")
const ORIGINAL_IMAGE  = document.querySelector(".close-dialog")
const DIALOG          = document.querySelector("dialog")

// ダイアログ(モーダルウィンドウ)を開く為の関数を定義
const OPEN_DIALOG = () => {
  DIALOG.showModal()
}

// ダイアログ(モーダルウィンドウ)を閉じる為の関数を定義
const CLOSE_DIALOG = () => {
  DIALOG.close()
}

// サムネイル画像にイベントリスナを設定、
// クリックされたらOPEN_DIALOG関数が呼ばれ、実行される
THUMBNAIL_IMAGE.addEventListener("click", OPEN_DIALOG)
// 原画像にイベントリスナを設定、
// クリックされたらCLOSE_DIALOG関数が呼ばれ、実行される
ORIGINAL_IMAGE.addEventListener("click", CLOSE_DIALOG)
```

サムネイル画像をクリックすると、次のようになります。

![](toplayer2.png)
CSS の効果により、背景が暗く、ぼかしもかけられています。

とても簡潔なコードで実装できますので、使って見てください。


## GLightbox

さて、写真を美しく見せるライトボックスはウェブサイトでは良く用いられます。
そこで、多くの先人の方々が様々なコードをライブラリとして提供してくださっています。
ライトボックスを実現する為の様々なライブラリがございますが、ここではその中から「GLightbox」をご紹介いたします。

[公式サイト](https://biati-digital.github.io/glightbox/)では次のように紹介されております。

> Glightboxは、コードネームを「Gie」と言い、タッチ操作可能な純粋なJavascriptで書かれたlightboxです。

ライトボックスとして写真を拡大表示できるのはもちろん、説明書きを補足したり、動画や地図などの表示も出来る優れもの、使い方も簡単です。


### 基本的な画像ギャラリー

**▼glightbox.html**

```
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width">
    <title>GLightbox</title>

    <!-- CDNよりGLightbox用CSSとJavaScriptを読み込む -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/glightbox/3.2.0/css/glightbox.css">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/glightbox/3.2.0/js/glightbox.min.js"></script>
    <!-- GLightboxをカスタマイズするの為のJavaScriptを読み込む -->
    <script src="glightbox-custom.js" defer></script>
  </head>

  <body>
    <h1>GLightbox</h1>

    <h3>基本的な画像ギャラリー</h3>
    <a href="images/sakura1.webp" class="glightbox">
      ![](images/sakura1_thumb.webp)
    </a>
    <a href="images/sakura2.webp" class="glightbox">
      ![](images/sakura2_thumb.webp)
    </a>
    <a href="images/sakura3.webp" class="glightbox">
      ![](images/sakura3_thumb.webp)
    </a>
  </body>
</html>
```

`<a>`タグのクラス名を `class="glightbox"` と指定するだけで簡単にライトボックスを実現できます。

実行例は次のようになります。

![サムネイル画像たち](glightbox1.png)
![クリックすると拡大表示される](glightbox2.png)


### 説明付きの画像ギャラリー

スライドに説明を追加することが出来ます。説明文はテキストの他、HTMLコードを表示することも出来ます。説明の位置も、上下左右、配置場所を設定できます。
また説明文の長さも、一行で納まるような短い説明文や、複数行に渡る長い説明文を追加することもできます。


#### JavaScript の準備

説明文付きの画像ギャラリーや、動画ギャラリー、インライン表示ギャラリーの為には、カスタマイズ用のJavaScriptを準備する必要があります。

カスタマイズ用のJavaScriptは、 `glightbox-custom.js` という名前にしましょう。
HTML の `<head>` タグに以下を記述します。

**▼glightbox.html**

```
<!-- GLightboxをカスタマイズするの為のJavaScriptを読み込む -->
<script src="glightbox-custom.js" defer></script>
```

次に、`glightbox-custom.js` は次のように書きましょう。

**▼glightbox-custom.js**

```
GLightbox({
  // selectorプロパティに、
  // 説明書きや動画再生、インライン表示させたいクラス名を指定します
  selector: ".glightbox-with-description, .glightbox-videos-gallery, .glightbox-inline"
})
```

説明書きや動画再生、インライン表示させたいクラス名を指定するだけの簡単設定です。

説明書きの為のクラス名を `.glightbox-with-description` としましたが、クラス名は任意です。自身で分かりやすいクラス名にすることができます。


#### 短い説明文を追加する場合

`テキスト`

基本的な画像ギャラリーの場合には、`<a>`タグのクラス名を `class="glightbox"` と指定しました。
説明文を追加する場合には、`<a>`タグのクラス名を `class="glightbox-with-description"` と指定します。

続けて下の例のように、 データ属性 `data-glightbox` の値として、次のようにタイトルや説明文を書きます。 `""(ダブルクォーテーション)`の中に、 `title` と `description（説明）` が書かれていることに注意してください。

**▼タイトルと説明書き**

```
data-glightbox="title:タイトルです; description: 説明書きです"
```

説明書きの配置は、`descPosition` で指定できます。指定しない場合には下に表示されます。`top, bottom, left, right` により、上下左右、好きな場所に配置できます。

**▼説明書きを「上」に配置する**

```
data-glightbox="descPosition: top; title:タイトルです; description: 説明書きです"
```

また 説明書きにはHTMLタグも書くことが出来ます。画像の出典元へのリンク`<a href=https://www.beiz.jp/素材/海/00141.html>写真: BEIZ images</a>`を表示することにしましょう。 `description: 説明書きです` の後に付け加えると良いです。

**▼説明書きにリンクも追加する**

```
data-glightbox="descPosition: top; title:タイトルです; description: 説明書きです <a href=https://www.beiz.jp/素材/海/00141.html>写真: BEIZ images</a>"
```

出来上がりは以下のようになります。

**▼短い説明文の完成形**

```
<a href="images/sea1.webp"
   class="glightbox-with-description"
   data-glightbox="descPosition: top; title:タイトルです; description: 説明書きです <a href=https://www.beiz.jp/素材/海/00141.html>写真: BEIZ images</a>">
  ![](images/sea1_thumb.webp)
</a>
```

こちらの実行例は次のようになります。

![サムネイル画像たち](glightbox3.png)
![クリックすると拡大表示される](glightbox4.png)


#### 長い説明文を追加する場合

長い説明文を追加する場合には、 短い説明文の場合と異なり `data-glightbox` の中の`description`に全てを記述するのは困難です。

そこで、 `description` には、説明書きが書かれている「クラス名」を記述することにして、実際の説明書きはそちらに書くことにします。

```
<a href="images/sea2.webp"
   class="glightbox-with-description"
   data-glightbox="descPosition: right; title: 説明書きは右に配置します; **description: .custom-description-warehauminoko;**">
```

「クラス名」を `.custom-description-warehauminoko;` として見ました。「われは海の子」の紹介をしたかったので、それに因んだクラス名にしました。自分で分かりやすいクラス名を付けると良いです。

実際の説明書きは、次のように `<div>` を作成して記述します。

```
<div class="glightbox-desc **custom-description-warehauminoko**">
  <!-- 実際の説明書きをいろいろ書く-->
</div>
```

`class="glightbox-desc` に続けて、自分で命名した説明書きのクラス名を続けているのが肝心なところです。

完成形は次のようになります。

**▼長い説明文の完成形**

```
<a href="images/sea2.webp"
   class="glightbox-with-description"
   data-glightbox="descPosition: right; title: 説明書きは右に配置します; description: .custom-description-warehauminoko;">
  ![](images/sea2_thumb.webp)
</a>
<div class="glightbox-desc custom-description-warehauminoko">
  <p>
    幻想的な朝焼けに包まれる海の写真です。
    <a href="https://www.beiz.jp/素材/海/00119.html" target="_blank" style="text-decoration: underline; font-weight: bold">写真: BEIZ images</a>
  </p>
  <figure style="margin: 0;">
    <figcaption>われは海の子</figcaption>
    <ul style="list-style-type: japanese-formal;">
      <li>我は海の子白浪の
          さわぐいそべの松原に
          煙たなびくとまやこそ
          我がなつかしき住家なれ。</li>
      <li>生まれてしほに浴して
          浪を子守の歌と聞き
          千里寄せくる海の氣を
          吸ひてわらべとなりにけり。</li>
      <li>高く鼻つくいその香に
          不斷の花のかをりあり。
          なぎさの松に吹く風を
          いみじき樂と我は聞く。</li>
      <li>丈餘のろかい操りて
          行手定めぬ浪まくら
          百尋千尋海の底
          遊びなれたる庭廣し。</li>
      <li>幾年こゝにきたへたる
          鐵より堅きかひなあり。
          吹く鹽風に黑みたる
          はだは赤銅さながらに。</li>
      <li>浪にたゞよふ氷山も
          來らば來れ恐れんや。
          海まき上ぐるたつまきも
          起らば起れ驚かじ。</li>
      <li>いで大船を乘出して
          我は拾はん海の富。
          いで軍艦に乘組みて
          我は護らん海の國。</li>
    </ul>
  </figure>
</div>
```

![サムネイル画像たち](glightbox3.png)
![クリックすると拡大表示される](glightbox5.png)
七番まである歌詞のうち、五番までが表示されています。残りの歌詞はスクロールすると表示されます。


### 動画ギャラリー

動画サービスとして有名な Vimeo や Youtube、自身のサーバーにある動画についても GLightbox を使うと簡単に再生することができます。動画は100％レスポンシブで、モバイルデバイスでも正しく再生されます。

HTMLは次のように書きましょう。

```
<h3>動画ギャラリー</h3>
<a href="https://vimeo.com/115041822"
   class="glightbox-videos-gallery">
  ![](images/vimeo_logo.webp)
</a>

<a href="https://www.youtube-nocookie.com/embed/Ga6RYejo6Hk"
   class="glightbox-videos-gallery">
  ![](images/youtube_logo.webp)
</a>

<a href="https://biati-digital.github.io/glightbox/demo/pexels-video-1550080.mp4"
   class="glightbox-videos-gallery">
  ![](images/mp4_logo.webp)
</a>
```

(事前にカスタマイズ用のJavaScriptを読み込んでいるので)
`class="glightbox-videos-gallery"` とクラス名を指定するのみで簡単に動画再生できるようになります。

実行例は次のようになります。

![サムネイル画像たち](glightbox6.png)
![クリックすると動画再生される](glightbox7.png)


### `iframe` とインライン要素

`iframe` とは `inline frame(インラインフレーム)` のことで、IT用語辞典では「Webページ内に矩形の領域を設け、別のWebページなどを読み込んで表示するもの」と説明されています。

GLightboxでは、表示させたいサイトの url を入力するだけで iframe を追加することができるので、簡単にウェブページやグーグルマップなどを表示できます。

また、`href`属性に他のサイトの url に代えて、自身のHTML中の `ID属性` を入力することで、ページ内の任意の `<div>` を表示することもできます。

ここでは、「グーグルマップ」と、インライン要素として「ページ内の `<div>` 表示」を行って見ましょう。


#### 地図(Google Map)

グーグルマップを表示させるためには、以下のようにします。

```
<h4>地図(Google Map)</h4>
<a href="https://www.google.com/maps/embed?pb=!1m18!1m12!1m3!1d3274.763025247525!2d134.6931975884683!3d34.837050266980405!2m3!1f0!2f0!3f0!3m2!1i1024!2i768!4f13.1!3m3!1m2!1s0x3554e003a23324b3%3A0x7a4f8c2f6eba81b1!2z5aer6Lev5Z-O!5e0!3m2!1sja!2sjp!4v1692601028619!5m2!1sja!2sjp"
  class="glightbox-inline">
  ![](images/himejijo_thumb.webp)
</a>
```

`<a>`タグ内の`href`属性にグーグルマップへのurlを設定し、 `class="glightbox-inline"` するだけで、完成です。

実行例は次のようになります。

![サムネイル画像（姫路城）](glightbox8.png)
![クリックすると地図が表示される](glightbox9.png)


#### インライン要素

インライン要素として「ページ内の `<div>` 表示」させるには、次のように書きます。

`<a>`タグ内の`href`属性には、`ID属性` を設定している点、また `data-glightbox="width: 75vw; height: auto;"` として、インライン表示される幅(width)を設定している点に注目してください。

ここでは、金子みすゞ さんの「青い空」という詩を表示させたいので、 `ID属性` を `#inline-aoisora` としています。

```
<h4>インライン要素</h4>
<a href="#inline-aoisora"
   class="glightbox-inline"
   data-glightbox="width: 75vw; height: auto;">
  ![](images/sky_thumb.webp)
</a>
<div id="inline-aoisora" style="display: none">
  <div class="inline-inner">
    <h4 class="text-center">インライン・コンテンツの例</h4>
    <div class="text-center">
      <figure>
        <figcaption>青い空</figcaption>
        <p>
          なんにもない空<br>
          青い空、<br>
          波のない日の<br>
          海のよう。<br>
{.aki}
          あのまん中へ<br>
          とび込んで、<br>
          ずんずん泳いで<br>
          ゆきたいな。<br>
{.aki}
          ひとすじ立てる<br>
          白い泡、<br>
          そのまま雲に<br>
          なるだろう。<br>
        </p>
      </figure>

      <small>
        <a href="https://www.beiz.jp/素材/空/00165.html">澄み切った青空に綿雲が浮かぶ(BEIZ images)</a>
      </small>
    </div>
  </div>
</div>
```

実行例は次のようになります。

![サムネイル画像（青い空）](glightbox10.png)
![クリックすると「青い空（詩）」が表示される](glightbox11.png)
