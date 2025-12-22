# コードのリファクタリング超ダイジェスト

:::{.chapter-lead}
この付録では、「リファクタリング」と呼ばれるコードの整理術について、ほんの触りだけご紹介いたします。

リファクタリングとは、「動くコードのまま、読んだり直したりしやすい形に整え直すこと」です。
新しい機能を足したり、バグを直したりする前に、まずはコードの見通しをよくするためのお掃除、と考えていただくとイメージしやすくなります。
:::

## リファクタリングとは何ですか

ソフトウェア開発の世界では、次のような作業をまとめて「リファクタリング」と呼びます。

- 動いてはいるが読みにくいコードを、意味の分かる変数名・関数名に直す
- 同じような処理が何度も出てくるところを、ひとつの関数にまとめる
- 長くて追いにくい関数を、役割ごとに分割する

ここで大事なのは、**外から見た「振る舞い」は変えない** という約束です。

- ✅ 振る舞いを変えずに、内部の書き方だけを整える → リファクタリング
- ✅ バグを直す前に、原因を探しやすい形にコードを整理する → リファクタリングの一種
- ❌ 新しい機能を追加する → それ自体はリファクタリングではない（機能追加）

リファクタリングは、ある程度コードを書き進めて「ちょっと読みにくくなってきたな」と感じたときに、
こまめに挟んでいくのが理想です。一気に大工事をするというより、「早め早めの掃除」として付き合うと気が楽になります。

## 小さな JavaScript での例

ここでは、JavaScript のごく小さな例を使って、リファクタリングの流れを眺めてみましょう。

### リファクタリング前のコード

次のように、利用者一覧を表示する関数が 2 つあるとします。

```js
function printUserSummary(users) {
  for (const user of users) {
    console.log(user.name + " (" + user.age + "歳)");
  }
}

function sendBirthdayMail(users) {
  for (const user of users) {
    if (!user.hasBirthdayToday) continue;

    const title = "お誕生日おめでとうございます";
    const body =
      user.name + " (" + user.age + "歳) さん、いつもありがとうございます。";

    console.log("送信:", title, body);
  }
}
```

動作としては問題ありませんが、`user.name + " (" + user.age + "歳)"` という書き方が、
2 つの関数で重複しています。表示形式を少し変えたくなったとき、両方を直し忘れるとバグの元になりそうです。

### ステップ 1: 共通処理を関数に切り出す

まずは、「利用者を表示するときのラベル」を作る処理だけを、別の関数に切り出してみます。

```js
function formatUserLabel(user) {
  return user.name + " (" + user.age + "歳)";
}

function printUserSummary(users) {
  for (const user of users) {
    console.log(formatUserLabel(user));
  }
}

function sendBirthdayMail(users) {
  for (const user of users) {
    if (!user.hasBirthdayToday) continue;

    const title = "お誕生日おめでとうございます";
    const body = formatUserLabel(user) + " さん、いつもありがとうございます。";

    console.log("送信:", title, body);
  }
}
```

やっていることはまったく同じですが、

- 「名前と年齢をラベルにする処理」は `formatUserLabel` に 1 箇所だけ
- それを使う側 (`printUserSummary` / `sendBirthdayMail`) は、
  「ラベルをどう使うか」だけに集中できる

という構造になりました。

このように、**意味のあるまとまりごとに名前を付けてあげる** のは、リファクタリングの代表的な一手です。

### ステップ 2: テンプレートリテラルで読みやすくする

さらに、文字列のつなぎ方をテンプレートリテラルに変えると、
文章としての見通しもよくなります。

```js
function formatUserLabel(user) {
  return `${user.name} (${user.age}歳)`;
}

function printUserSummary(users) {
  for (const user of users) {
    console.log(formatUserLabel(user));
  }
}

function sendBirthdayMail(users) {
  for (const user of users) {
    if (!user.hasBirthdayToday) continue;

    const title = "お誕生日おめでとうございます";
    const body = `${formatUserLabel(user)} さん、いつもありがとうございます。`;

    console.log("送信:", title, body);
  }
}
```

動作は最初のコードと変わりませんが、

- 「どの部分が名前で、どの部分が年齢か」がひと目で分かる
- ラベルの形式を変えたいとき、`formatUserLabel` だけを見ればよい

という状態になりました。

これも立派なリファクタリングです。

## リファクタリングをするときの心がけ

少しだけ大きなコードを書くようになってきたら、次のような点を意識すると安全に進めやすくなります。

- **小さなステップで進める**  
  まずは関数 1 つだけ名前を変える、1 箇所だけ共通化する、など、
  「前後のコードを見比べやすい粒度」で手を動かします。

- **動作が変わっていないか、こまめに確認する**  
  ブラウザをリロードしたり、簡単なテストコードを書いたりして、
  リファクタリングの前後で結果が同じかどうかをチェックします。

- **「読み手の自分」にやさしくするつもりで書く**  
  変数名や関数名に迷ったときは、
  「一週間後の自分が読んだらどう感じるか？」を想像してみると、
  自然とよい名前が浮かびやすくなります。

この付録の内容は、最初にすべて覚える必要はありません。
いったん「リファクタリングという考え方がある」と知っておいて、
コードが少し長くなってきたタイミングで、また読み返していただければうれしいです。








---


### 見出しや本文の色・フォントを整える

まずは、ページ全体の文字まわりを整えるところから始めましょう。

たとえば、トップページ全体を囲む `<body class="top">` や、ヒーローイメージ上のタイトル `<h1 class="glow text catch_phrase">`、最新記事カードのタイトル `<h3>` には、実際の `studio-wave` でも次のようなスタイルを（ここでは少し簡略化して）指定しています。

```css
/* サイト全体のベースフォントと背景 */
body.top {
  font-family: "Helvetica Neue",
               Arial,
               "Hiragino Kaku Gotic ProN",
               "Hiragino Sans",
               Meiryo,
               sans-serif;
  background: linear-gradient(to top,
                              #FFFFFF80,
                              #6DD5FA40,
                              #2980B980);
}

/* ヒーローイメージ上の大きな見出し */
.top h1.catch_phrase {
  font-size: 50px;
  line-height: 1.2;
  text-align: center;
  color: var(--sakurairo);
  text-shadow: 0 0 5px var(--nibiiro);
  font-family: "Yuji Boku", serif;
}

/* 最新記事カードのタイトル */
#recent h3 {
  font-size: 14px;
  margin-block-start: 10px;
}
```

実際の `studio-wave` プロジェクトでは、和色のカスタムプロパティや細かな余白の設定など、もう少し多くのプロパティを組み合わせていますが、ここでは「フォント・行間・文字色・背景色」を押さえておけば十分です。


### CSS グリッドで「最新記事」を並べる

次に、`index.html` の中央に並んでいる「最新記事」セクションを見てみましょう。

```html
<!-- 最新記事の一覧 -->
<section id="recent">
  <h2>最新記事</h2>

  <!-- それぞれの記事の紹介 -->
  <article>
    <a href="post01.html">
      <figure>
        <img src="images/note.webp" alt="海辺の風景を描くスケッチノート">
      </figure>
      <h3>海辺のスケッチノート</h3>
    </a>
  </article>

  ...（中略）...

</section>
```

この `#recent` の中に並ぶ複数の `<article>` を、「海辺のライフスタイル誌」の誌面のように、きれいなグリッド状に並べるのに使うのが **CSS グリッドレイアウト** です。

CSS グリッドレイアウトは、ページ上に「行（row）」と「列（column）」からなる二次元の格子（グリッド）を用意し、そのマス目の上に要素を配置していく仕組みです。雑誌の紙面を考えるときに、見出し・本文・写真を「どの段・どの列に置くか」を決めていくのと、とてもよく似ています。

`#recent` に対して、次のような CSS を指定してみましょう。

```css
/* 最新記事セクションをグリッドレイアウトにする */
#recent {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  grid-template-rows: auto;
  gap: 24px;
}

#recent > article {
  background: #fff;
  border-radius: 8px;
  padding: 12px;
}
```

ここで登場する 2 つのプロパティが、この章で特に覚えておきたい **`grid-template-columns`（列の設計図）** と **`grid-template-rows`（行の設計図）** です。

- `display: grid;` で、`#recent` を「グリッドコンテナ」にする
- `grid-template-columns: repeat(3, 1fr);` で、横方向に同じ幅の列を 3 本用意する
- `grid-template-rows: auto;` で、縦方向の行は中身の高さに合わせて伸縮させる
- `gap: 24px;` で、行と列のあいだに 24px の余白をあける

といった形で、誌面の「マス目」を決めていきます。`#recent` の直下にある `<article>` たちは、このグリッドコンテナの「マス目」に自動的に横 3 枚ずつ、縦に折り返しながら配置されます。

グリッドコンテナ（`#recent`）の中に、`grid-template-columns` や `grid-template-rows` で「行・列の設計図」を描き、その上に `<article>` という記事カードをポンポンとのせていくイメージです。


### 行と列を数えて配置してみる

もう少し踏み込んで、グリッドの「行番号・列番号」を意識した配置も体験してみましょう。

グリッドでは、左端の列の線が `1`、次が `2`、… と番号づけされ、同様に一番上の行の線が `1`、その下が `2`、… というふうに数えられます。

たとえば、次のように `grid-template-columns` と `grid-template-rows` を定義したとします。

```css
/* 行・列にマス目を切っておく */
.front-page-grid {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr 1fr;  /* 横 4 列 */
  grid-template-rows:    1fr 1fr 1fr 1fr;  /* 縦 4 行 */
  gap: 20px;
}
```

ここに、`.hero`, `.recent`, `.footer` といったブロックを載せていくとしましょう。

```css
.hero   { grid-column: 1 / 5; grid-row: 1; }
.recent { grid-column: 1 / 5; grid-row: 2 / 4; }
.footer { grid-column: 1 / 5; grid-row: 4; }
```

- `.hero` は「列 1 本目から 5 本目まで」「行 1 行目」に配置
- `.recent` は「列 1 本目から 5 本目まで」「行 2 行目〜4 行目」にわたって配置
- `.footer` は「列 1 本目から 5 本目まで」「行 4 行目」に配置

という具合に、**誌面のどの段・どの行をどのブロックに割り当てるか** を CSS のコードで表現できます。

実際の `studio-wave` では、完全に同じコードではありませんが、考え方としてはこのように「行と列の設計図（`grid-template-rows` / `grid-template-columns`）」と「どのブロックをどのマス目に置くか（`grid-row` / `grid-column`）」を組み合わせて、トップページ全体のレイアウトを組み立てています。

---

## 学習の為の参考サイトや書籍のご紹介


### HTML / CSS を学ぶ為に

様々な書籍や有益なサイトがございますが、始めて学ぶ方向けに、次のMDNのページがお勧めです。MDNは開発者向けの技術情報が集積されている公式サイトで使用例など豊富な情報が掲載されています。

* [ウェブ入門](https://developer.mozilla.org/ja/docs/Learn/Getting_started_with_the_web)
* [HTML の基本](https://developer.mozilla.org/ja/docs/Learn/Getting_started_with_the_web/HTML_basics)
* [CSS の基本](https://developer.mozilla.org/ja/docs/Learn/Getting_started_with_the_web/CSS_basics)

また、どのような仕組みでウェブサイトが閲覧できるのか、少し技術的な背景についても知見があると、（専門家を目指す方はもちろんですが） 知的好奇心を満たす点からも楽しいものです。

* [ウェブのしくみ](https://developer.mozilla.org/ja/docs/Learn/Getting_started_with_the_web/How_the_Web_works)

MDNでの学習を終えた方には、次の三冊がお勧めです。

* CSSグリッドで作る HTML5&CSS3 レッスンブック
* 作って学ぶ　HTML＆CSSモダンコーディング
* 作って学ぶ　HTML＆CSSグリッドレイアウト

一冊目は初心者向けに基礎的なウェブサイトの作成を簡単な技術的な背景も含めて解説されている良書です。二冊目は、前書の学習を終え、基礎的なHTML/CSSが書けるようになった方が、より進んだサイト作成の技術を学ぶために最適な一冊となっています。最後の三冊目はグリッドレイアウトとは何か、最新のCSSを用いて学ぶことができます。


### JavaScript を学ぶ為に

JavaScript の学習に当たっては、以下のＭＤＮサイトが概要を掴むには良いでしょう。

* [JavaScript の基本](https://developer.mozilla.org/ja/docs/Learn/Getting_started_with_the_web/JavaScript_basics)

簡潔に説明されてはいますが、始めてプログラミングに触れる方には少し難しいと感じるかもしれません。そういった方へは、巻末の参考書籍

* スラスラ読める JavaScript ふりがなプログラミング

がお勧めです。一語一語、漢文に倣った読み下し文でコードの意味が書かれており、短いコードの一文一文を確かめながら実行することで、理解を深めていくことができるようになっています。

* 1冊ですべて身につくJavaScript入門講座

前著を読まれた方が次に読む一冊としてお勧めの書籍です。JavaScriptをウェブサイトに組み込み、画像データの表示など、実践的な内容を学習していきます。

* JavaScript Primer 迷わないための入門書

は、JavaScript をより深く知りたい方にお勧めの一冊。難易度高目ではありますが、前半だけでも読み通すと、言語の全容を知ることができ、他のプログラミング言語の理解にも繋がります。