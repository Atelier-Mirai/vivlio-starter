# `Document Object Model`

:::{.chapter-lead}
前章までに変数や定数、関数といったプログラミングの基本的な部品について紹介しました。
そしてあと二つ学ぶべき事柄が残っています。一つは「DOM(Document Object Model)」でもう一つは「イベントリスナ」です。この二つを習得することで、JavaScript から HTML を自由自在に操作できるようになります。

本章では、まず「DOM(Document Object Model)」についてご紹介いたします。  
:::



## JavaScript から HTMLを操作する為の仕組み

DOMとは何でしょうか。
[IT用語辞典](https://e-words.jp/w/DOM.html) の説明を見て見ましょう。


:::{.tip}
DOMとは、HTML文書を構成する要素をコンピュータプログラムで参照したり操作したりするための取り決め。

HTMLで記述されたウェブページなどの構成要素（見出し、段落、画像、リンクなど）と、それらの配置や見栄えなどを定めた属性情報などを参照、制御する手法を定めている。ウェブブラウザなどに実装されており、ページ上にJavaScriptなどで記述されたスクリプトからページ内の各要素を読み取ったり、内容や設定の変更、要素の追加や削除などを行う標準的な手段として用いられる。
:::

辞典ですので、きっちりと書かれておりますが、少し難しく感じるかもしれません。

MDN の [DOMの紹介](https://developer.mozilla.org/ja/docs/Web/API/Document_Object_Model/Introduction) がございますので、その一部を抜粋しましょう。


:::{.tip}
ドキュメントオブジェクトモデル (DOM) はウェブ文書のためのプログラミングインターフェイスです。ページを表現するため、プログラムが文書構造、スタイル、内容を変更することができます。 DOM は プログラミング言語をページに接続することができます。
:::

分かりやすくなったでしょうか。


:::{.tip}
**ドキュメントオブジェクトモデル (DOM)** とは、**HTMLで作られたウェブページと、プログラミング言語であるJavaScriptを繋ぐ為の仕組み** です。DOMを仲立ちにすることで、JavaScript から HTMLを操作することができます。
:::

### 初めてのDOMツリー

それでは、理解の為に例を使って練習しましょう。HTMLファイルとして `index.html` を JavaScriptファイルとして `introduction.js` を作成します。

```
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>JavaScript練習</title>

    <!-- JavaScriptの読み込み -->
    <script src="introduction.js" defer></script>
  </head>

  <body>
    <h1>JavaScript練習</h1>
  </body>
</html>
```

`index.html` に関しては、11行目で `introduction.js` を読み込むようにしています。

着目していただきたいのは、`**defer**` と書かれている箇所です。通常、ブラウザは上から順番に一行目、二行目と実行していきますので、11行目でJavaScriptを読み込むと、すぐに読み込んだ JavaScript のプログラムを実行しようとします。

JavaScript を使って、HTML の各要素を操作する場合、例えば `<h1>`の文字を取得しようとした場合、15行目にある `<h1>` はまだ読み込まれていないので、実行出来ずにエラーとなります。

`**defer**` を付けると、「HTMLの読み込み完了を待ってから、JavaScript が読み込まれ実行される」（「遅延読み込み」と言います）ため、無事に `<h1>` の文字列を取得することができます。


`introduction.js` は次のように書きましょう。

**▼introduction.js**

```
// (1) CSSセレクタを使い、DOMツリーから操作したいh1要素を取得する
const element = document.querySelector("h1")

// (2) 取得したh1要素の内容物（コンテンツ、JavaScript練習）を取得する
const content = h1.textContent

// (3)取得した内容物(コンテンツ)「JavaScript練習」を表示する。
alert(content)
```

実行した結果は次のようになります。画面に「JavaScript練習」とダイアログを表示させることが出来ました。

![](dom0.png)


## HTML要素を取得・更新する


### 準備

簡単なHTMLでDOMツリーから要素を取得、表示することを体験しました。これから、DOMツリーを扱う為のメソッドをいくつか紹介いたします。練習しやすいよう、次のように HTML / CSS を用意しましょう。

**▼index.html**

```
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>JavaScript練習</title>
    <link rel="stylesheet" href="style.css">
    <script src="practise.js" defer></script>
  </head>

  <body>
    <h1>JavaScript練習</h1>
    <p>ウェブサイトを作成するためには、次の三つの道具が必要です。</p>
    <ol>
      <li class="hardware">コンピュータ<span>(Mac / Linux / Windows など)</span></li>
      <li class="software">エディタ
                            <span style="display: none;">
                              (Windsurf / Zed / VS Codeなど)
                            </span>
      </li>
      <li class="software">ブラウザ (Firefox, Safariなど)</li>
    </ol>

    <p>ウェブサイトの作成には、次の三つの言語が良く使われます。</p>
    <ul>
      <li id="html">HTMLは、「文書構造」の為の言語です。</li>
      <li id="css">CSSは、「意匠・装飾」の為の言語です。</li>
      <li id="javascript">JavaScriptは、<br>
                         「相互作用・動き・制御」の為の言語です。</li>
    </ul>
  </body>
</html>
```

**▼style.css**

```
body { width: 500px; margin: 0 auto; }
h1 { color: orange; text-align: center; }
p, li { line-height: 2; }

.hardware { border-bottom: solid 3px lime; }
.software { border-bottom: double 3px magenta; }
.effect   { font-weight: bold; font-style: italic; }

#html       { background: orange; }
#css        { background: cyan; }
#CascadingStyleSheet { background: blue; color: white; }
#javascript { background: yellow; }
```

HTML では、複数の`<li>`要素や、`class`属性、`id`属性も登場しています。`<span style="display: none;">` と 表示させないようインラインCSSが記述されていたり、`JavaScriptは、<br>「相互作用・動き・制御」の為の言語です。` と `<br>` タグで改行されています。

CSS でも要素セレクタ、クラスセレクタ、IDセレクタと三種類登場しています。

表示結果は次のようになります。

![](dom1.png)


### (1) DOMから操作したい要素を取得する

DOMから操作したい要素を取得するためには、次の3つのメソッドが用意されています。MDN に詳細が記されていますので、抜粋しつつ、それぞれのメソッドに関して見ていきましょう。

* `[Document.getElementById()](https://developer.mozilla.org/ja/docs/Web/API/Document/getElementById)`
* `[Document.querySelector()](https://developer.mozilla.org/ja/docs/Web/API/Document/querySelector)`
* `[Document.querySelectorAll()](https://developer.mozilla.org/ja/docs/Web/API/Document/querySelectorAll)`


#### Document.getElementById()

> Document の getElementById() メソッドは、 id プロパティが指定された文字列に一致する要素を表す Element オブジェクトを返します。要素の ID は指定されていれば固有であることが求められているため、特定の要素にすばやくアクセスするには便利な方法です。
>
> ID を持たない要素にアクセスする必要がある場合は、 querySelector() で何らかのセレクタを使用して要素を検索することができます。
>
>
> [tip] <b></a>
>
> **構文**<br>
> `element = document.getElementById(id)`<br>
>
> **引数**`id`<br>
> 探す要素の ID です。 ID は大文字と小文字の区別がある文字列で、文書内で固有です。指定された ID の要素は一つしかありません。<br>
>
> **返値**<br>
> 指定された ID に一致する DOM 要素オブジェクトを記述した Element オブジェクト、または文書内に一致する要素がなければ null です。
>
> [/tip]
> 

「**探す要素の ID**」とありますので、DOMツリーから ID が `"html"` の要素 を選択したい場合には、次のように書けば良いことが分かります。

```
// ID属性が html の要素を取得する
let html = document.getElementById("html")
```

コンソール画面で、`element = document.getElementById("html")` と入力すると、`<li id="html">` と表示されます。表示された `<li id="html">` にマウスカーソルを重ねると、どの部分を選択しているのか、確認できます。

![](dom1a.png)


#### Document.querySelector()

> Document の querySelector() メソッドは、指定されたセレクタまたはセレクタ群に一致する、文書内の**最初の Element** を返します。一致するものが見つからない場合は null を返します。
>
>
> [tip] <b></a>
>
> **構文**<br>
> `element = document.querySelector(selectors)`<br>
>
> **引数** `selectors`<br>
> DOMString で、照合する 1 つ以上のセレクタを設定します。この文字列は妥当な CSS セレクタでなければなりません。<br>
>
> **返値**<br>
> Element オブジェクトで、文書内で指定された CSS セレクタに**最初に一致する要素**を示すオブジェクト、もしくは、一致する要素がない場合は null を返します。
>
> 指定されたセレクタに一致するすべての要素のリストが必要な場合は、代わりに querySelectorAll() を使用してください。
>
> [/tip]
> 

「`selectors` の文字列は妥当な CSS セレクタでなければなりません。」とあります。CSSでは `<h1>`要素を選択する際に`h1`と書きますが、同様に、DOMツリーから `<h1>`要素 を選択する場合には、次のように書けば良いことが分かります。

```
// (最初の) <h1>要素を取得する
let h1 = document.querySelector("h1")
```

- `document.querySelector("li")`  
  単一のセレクタで指定すると、(複数の`<li>`が該当しますが、最初に見つかった) `<li class="hardware">コンピュータ <span>(Mac / Linux / Windows など)</span></li>` を取得できます。

- `document.querySelector("ol li span")`  
  (`li`のような単一のセレクタではなく) 複数のセレクタを並べると、`<span>(Mac / Linux / Windows など)</span>` を取得できます。

- `document.querySelector(".hardware")`  
  クラス名を指定すると、`<li class="hardware">コンピュータ <span>(Mac / Linux / Windows など)</span></li>` を取得できます。

- `document.querySelector("#html")`  
  ID属性を指定すると、`<li id="html">HTMLは、「文書構造」の為の言語です。</li>` を取得できます。<br> (`document.getElementById("html")` でも取得できます。 `#`の有無にも着目してください。)

コンソール画面で、`element = document.querySelector("li")` と入力すると、`<li class="hardware>` と表示されます。表示された `<li class="hardware">` にマウスカーソルを重ねると、どの部分を選択しているのか、確認できます。

![](dom2.png)
---
==== Document.querySelector**All**()

`querySelector()`メソッドとよく似ていますが、メソッド名の最後に**All** と付いています。

違いもまたその点に有り、「`querySelector()`メソッドは、指定されたセレクタまたはセレクタ群に一致する、文書内の**最初のElement** を返します。」とあるように、いくつかの要素が該当した場合には、最初の一つが返ってきます。よって、`document.querySelector("li")` と書くと、六つの `<li>` 要素の内、最初の一つを得ることが出来ます。

六つの `<li>` 要素 **全て**を取得する為には、次のように書きます。

```
// 六つの <li> 要素 全て を取得する
let lists = document.querySelectorAll("li")}
```

![](dom3.png)
コンソール画面で、`elements = document.querySelectorAll("li")` と入力すると、`NodeList(6) [ li.hardware, li.software, li.software, li#html, li#css, li#javascript ]` と表示されます。表示された `li.hardware` や `li.software` などにマウスカーソルを重ねると、どの部分を選択しているのか、確認できます。


`NodeList(6) [ li.hardware, li.software, li.software, li#html, li#css, li#javascript ]` と表示されているように、通常の配列のように扱えます。

ですので、 `elements[0]` と書いて `li.hardware` を、`elements[1]` と書いて (最初の)`li.software` を、扱うことができます。

また、配列のように扱えますので、繰り返しの為の構文「`for...of`」文を用いると、取得した六つの要素を表示できます。

コンソール画面に入力して、確認してみましょう。

```
// 取得した六つの <li> 要素 全て を表示する
for (const li of lists) {
  console.log(li);
}
```

![](dom4.png)


### (2) 取得した要素から得たい内容物(コンテンツ)を取得する

取得した要素から得たい内容物(コンテンツ)を取得する為にも、次の3つのメソッドが用意されています。MDN に詳細が記されています。抜粋しつつ、それぞれのメソッドに関して見ていきましょう。

* `[Element.innerHTML](https://developer.mozilla.org/ja/docs/Web/API/Element/innerHTML)`
* `[HTMLElement.innerText](https://developer.mozilla.org/ja/docs/Web/API/HTMLElement/innerText)`
* `[Node.textContent](https://developer.mozilla.org/ja/docs/Web/API/Node/textContent)`


#### Element.innerHTML

> Element オブジェクトの innerHTML プロパティは、要素内の HTML のマークアップを取得したり設定したりします。
>
>
> [tip] <b></a>
>
> **構文**<br>
>
> **要素内の HTML のマークアップを「取得」するとき**<br>
> `content = element.innerHTML`<br>
>
> **要素内の HTML のマークアップを「設定」するとき**<br>
> `element.innerHTML = content`<br>
>
> **値**<br>
> 要素の子孫を HTML にシリアライズしたものを含んだ DOMString です。 innerHTML に値を設定すると、要素のすべての子孫を削除して、htmlString の文字列で与えられた HTML を解釈して構築されたノードに置き換えます。
>
> [/tip]
> 

それでは、要素内の HTML を取得したり、設定したりしてみましょう。

**▼マークアップコンテンツを取得する例**

```
// DOMツリーから要素を取得
let element = document.querySelector("h1")
// マークアップコンテンツを取得する
let content = element.innerHTML
// 取得したマークアップコンテンツを表示する
console.log(content)
```

コンソール画面で入力すると、「JavaScript練習」と表示されています。

![](dom5.png)
次に `<h1>`要素に、マークアップを設定して見ましょう。

**▼マークアップコンテンツを設定する例**

```
// DOMツリーから要素を取得
let element = document.querySelector("h1")
// マークアップコンテンツを設定する
let element.innerHTML = "JavaScript<br>練習"
```

コンソール画面に入力すると、`JavaScript<br>練習` と `<br>` を入れたので、改行されて表示されています。

![](dom7.png)
---
==== HTMLElement.innerText

> innerText は HTMLElement のプロパティで、ノードとその子孫の「レンダリングされている」テキスト内容を示します。
>
> ゲッターとしては、カーソルで要素の内容を選択しクリップボードにコピーした際のテキストに近いものを取得することができます。 セッターとしては、この要素の子要素を指定された値で置き換え、すべての改行を `<br>` 要素に変換します。
>
>
> [tip] <b></a>
>
> **構文**<br>
>
> **要素内の テキスト内容を「取得」するとき**<br>
> `content = element.innerText`<br>
>
> **要素内の テキスト内容を「設定」するとき**<br>
> `element.innerText = content`<br>
>
> [/tip]
> 

要素内の テキスト内容 を取得したり、設定したりしてみましょう。

**▼テキスト内容を取得する例**

```
// DOMツリーから要素を取得
let element = document.getElementById("javascript")
// テキスト内容を取得する
let content = element.innerText
// 取得したテキスト内容を表示する
let console.log(content)
```

HTMLでは、`<li id="javascript">JavaScriptは、<br>「相互作用・動き・制御」の為の言語です。</li>` のように、 `<br>` タグで改行していました。

ID属性を指定しているので、 `document.getElementById("javascript")` として、この要素を取得します。

そして、 `content = element.innerHTML` で、テキスト内容を取得できたので、取得したテキスト内容を表示するために、 `console.log(content)` と入力します。

コンソール画面で入力すると、<br>
　　　"JavaScriptは、<br>
　　　「相互作用・動き・制御」の為の言語です。"<br>
と `<br>` タグは、改行に置換されて、表示されています。

![](dom8.png)
それでは、この `<li id="javascript">`要素の、テキスト内容を設定して見ましょう。

**▼テキスト内容を設定する例**

```
// DOMツリーから要素を取得
let element = document.getElementById("javascript")
// テキスト内容を設定する
let element.innerText = `JavaScriptを利用すると、
HTML要素の取得や更新など、
さまざまなことが行えます。`
```

改行文字を設定しやすいよう、 ```(バッククォート)` で「JavaScriptを利用すると〜行えます。」を囲んでいます。


コンソール画面で入力すると、<br>
　　　"JavaScriptを利用すると、<br>
　　　HTML要素の取得や更新など、<br>
　　　さまざまなことが行えます。<br>
と 改行文字は `<br>` に置換されて、表示されています。

![](dom9.png)
---
==== Node.textContent

> textContent は Node のプロパティで、ノードおよびその子孫のテキストの内容を表します。
>
>
> [tip] <b></a>
>
> **構文**<br>
>
> **要素内の テキスト内容を「取得」するとき**<br>
> `content = element.textContent`<br>
>
> **要素内の テキスト内容を「設定」するとき**<br>
> `element.textContent = content`<br>
>
> [/tip]
> 

要素内の テキスト内容 を取得したり、設定したりしてみましょう。

**▼テキスト内容を取得する例**

```
// DOMツリーから要素を取得
let element = document.querySelector("li:nth-child(2)")
// テキスト内容を取得する
let content = element.textContent
// 取得したテキスト内容を表示する
console.log(content)
```

ここでは、二番目の `<li>`要素である `<li class="software">エディタ <span style="display: none;">(Windsurf / Zed / VS Codeなど)</span></li>` に着目します。 HTML上では `<span>` タグに Windsurf など具体的なエディタ名が書かれているのですが、`<span style="disdplay: none;"` と、インラインCSSにより、非表示となっています。

これがどのようにテキスト内容として取得されるのか、が着目点です。


コンソール画面で入力すると、<br>
　　　エディタ (Windsurf / Zed / VS Codeなど)<br>
と 非表示となっている `<span>` タグ内のテキストも取得されています。

![](dom10.png)
それでは、この `<li id="javascript">`要素の、テキスト内容を設定して見ましょう。

**▼テキスト内容を設定する例**

```
// DOMツリーから要素を取得
let element = document.querySelector("li:nth-child(2)")
// テキスト内容を設定する
element.textContent = "エディタ (Windsurf / Zed / VS Codeなど)"
```

コンソール画面で入力すると「エディタ (Windsurf / Zed / VS Codeなど)」と全て表示されます。

![](dom11.png)
もとの HTML は、`<li class="software">エディタ <span style="display: none;">(Windsurf / Zed / VS Codeなど)</span></li>` と書かれていましたが、 `textContent` メソッドにより `<li class="software">エディタ (Windsurf / Zed / VS Codeなど)</li>` と、元あったの `<span>` タグも消去され、`textContent` での設定文字になることにも注目してください。


### innerHTML, innerText, textContent の違い

MDN [textContent](https://developer.mozilla.org/ja/docs/Web/API/Node/textContent) に、三つの取得/設定メソッドの違いについて、記載されておりますので、抜粋して掲載いたします。どのメソッドを用いるべきか、使い分けの参考にしてください。


:::{.tip}
* `textContent` は、 `<script>` と `<style>` 要素を含む、すべての要素の中身を取得します。
* `innerText` は「人間が読める」要素のみを示します。


* `textContent` はノード内のすべての要素を返します。
* `innerText` はスタイルを反映し、「非表示」の要素のテキストは返しません。


* `textContent` は テキストの内容を返します。
* `innerHTML` は、その名が示すとおり `HTML` を返します。
:::

## 属性を操作する


### ID属性の追加や削除を行う

MDN [Element.id](https://developer.mozilla.org/ja/docs/Web/API/Element/id) より、ご紹介いたします。

> id は Element インターフェイスのプロパティで、グローバル属性の id を反映した要素の識別子を表します。
>
> id の値が空文字列でない場合は、文書内で固有でなければなりません。
>
> id はよく getElementById() で特定の要素を受け取るために使用します。他の一般的な用途としては、要素の ID をセレクターとして CSS で文書をスタイル付けするために使用されます。
>
>
> [tip] <b></a>
>
> **構文**<br>
>
> **要素のIDを「取得」するとき**<br>
> `idStr = element.id`<br>
>
> **要素のIDを「設定」するとき**<br>
> `element.id = newid`<br>
>
> **要素のIDを「削除」するとき**<br>
> `element.removeAttribute("id")`<br>
>
> [/tip]
> 

要素のIDを取得/設定/削除してみましょう。

**▼ID操作の例**

```
// DOMツリーから要素を取得
let element = document.getElementById("css")

// ID文字列を取得する
let idString = element.id

// 取得したID文字列を表示する
console.log(idString)
```

コンソール画面に入力した結果です。

![](id0.png)
続いて、新しいIDを設定して見ましょう。

```
// 新しいIDを設定する
element.id = "CascadingStyleSheet"
```

コンソール画面に入力した結果は次の通りです。

![](id1.png)
今まで`cyan` で表示されていたCSSの項目が、新しいIDを設定したことに伴い、 `blue` で表示されています。

「インスペクタ」画面で確認すると、IDが `CascadingStyleSheet` に更新されていること、CSS として、`{ background: blue; color: white; }` が適用されていることが確認できます。

![](id2.png)

最後に、IDの削除を行って見ましょう。IDを削除する為の専用のメソッドは備わっていません。汎用的に属性を削除できる `removeAttribute()` メソッドを使って行います。

```
// 要素のIDを削除する
element.removeAttribute("id")
```

![](id3.png)
要素からIDを削除しましたので、それに伴い、青色の背景色で表示するCSSも適用されなくなっています。


### クラス名の追加や削除を行う

MDN [Element.className](https://developer.mozilla.org/ja/docs/Web/API/Element/className) より、ご紹介いたします。

> className は Element インターフェイスのプロパティで、この要素の class 属性の値を取得したり設定したりします。
>
>
> [tip] <b></a>
>
> **構文**<br>
>
> **要素のクラス名を「取得」するとき**<br>
> `cName = element.className`<br>
>
> **要素のクラス名を「設定」するとき**<br>
> `element.className = cName`<br>
>
> * `cName` は文字列変数で、現在の要素のクラスまたは空白区切りのクラス群を表します。
> * このプロパティでは、 `className` という名前が `class` の代わりに使用されています。 これは `DOM` を操作するために使用される多くの言語と `"class"` キーワードが競合するためです。
>
> **クラス名を「削除」するとき**<br>
> `element.removeAttribute("class")`<br>
>
> [/tip]
> 

要素のクラス名を取得/設定/削除してみましょう。

**▼クラス名操作の例**

```
// DOMツリーから要素を取得
let element = document.querySelector("li:first-child")

// クラス名を取得する
let name = element.className

// 取得したクラス名を表示する
console.log(name)
```

コンソール画面に入力した結果です。

![](className0.png)
続いて、新しいクラス名を設定して見ましょう。

```
// 新しいクラス名を設定する
element.className = "effect"
```

コンソール画面に入力した結果は次の通りです。

![](className1.png)
`.hardware` クラスには、 `.hardware { border-bottom: solid 3px lime; `} と指定していましたが、クラス名を `.effect` に変更したので `.effect { font-weight: bold; font-style: italic; `} と表示されます。

![](className2.png)
「インスペクタ」画面で確認すると、クラス名が `.effect` に更新されていることや、`{ font-weight: bold; font-style: italic; }` が適用されていることが確認できます。


もしかすると、クラス名を変更するのではなく、新しいクラス名を追加したかったのかもしれません。新しいクラス名を追加するには次のようにします。

```
// 新しいクラス名を「追加」設定する
element.className = `${name} effect`
```

先に取得した `name` には、元のクラス名 `hardware` が保存されているので「式展開（テンプレートリテラル・テンプレート文字列）」を使いクラス名を追加します( ````(バッククォート)で囲みます)。

![](className3.png)
---
最後に、クラス名の削除を行って見ましょう。クラス名を削除する為の専用のメソッドは備わっていません。汎用的に属性を削除できる `removeAttribute()` メソッドを使って行います。

```
// 要素のクラス名を削除する
element.removeAttribute("class")
```

![](className4.png)
要素からクラス名を削除しましたので、それに伴い、下線や斜体などのCSSも適用されなくなっています。
---
=== 属性の追加や削除を行う

MDN [element.setAttribute](https://developer.mozilla.org/ja/docs/Web/API/Element/setAttribute) より、ご紹介いたします。

> 指定の要素に新しい属性を追加します。または指定の要素に存在する属性の値を変更します。
>
>
> [tip] <b></a>
>
> **構文**<br>
> **要素の属性を「取得」するとき**<br>
> `value = element.getAttribute("attrName")`<br>
> または@<br>
> value = element.attrName
>
> **要素の属性を「設定」するとき**<br>
> `element.setAttribute("attrName", value)`
>
> * `attrName` は属性の名前を文字列で表現したものです。
> * `value` は属性に設定したい値です。
>
> **要素の属性を「削除」するとき**<br>
> `element.removeAttribute("attrName")`<br>
>
> [/tip]
> 

要素の属性を取得/設定/削除してみましょう。様々な属性がありますが、ここではタイトル属性(`title`) にしましょう。

**▼クラス名操作の例**

```
// DOMツリーから要素を取得
let element = document.querySelector("h1")

// タイトル属性を取得する
let value = element.title

// 取得したタイトル属性を表示する
console.log(value)
```

コンソール画面に入力した結果です。

![](attr1.png)
もともと `<h1>JavaScript練習</h1>` と書いていますので、属性は何も設定されていません。ですので取得した `value` を表示させる為に `console.log(value)` としましたが、表示できるものが何もないので、 `<empty string>` と表示されます。


それでは、タイトル属性に新しい値として「千里の道も一歩から」を設定して見ましょう。

```
// DOMツリーから要素を取得
let element = document.querySelector("h1")

// タイトル属性に新しい値を設定する
element.setAttribute("title", "千里の道も一歩から")

// タイトル属性を取得する
let value = element.title

// 取得したタイトル属性を表示する
console.log(value)
```

![](attr2a.png)

コンソール画面に入力してみましょう。


「インスペクタ」画面で確認すると、`title`属性が付与され `<h1 title="千里の道も一歩から">JavaScript練習</h1>` に更新されていること、マウスカーソルを重ねると、「千里の道も一歩から」と、`title`属性 が表示されます。

![](attr3.png)

最後に、タイトル属性の削除を行って見ましょう。

```
// タイトル属性を削除する
element.removeAttribute("title")
```


## 新しい要素を作成・追加・削除する


### 要素を作成する

MDN [Document.createElement()](https://developer.mozilla.org/ja/docs/Web/API/Document/createElement) より、ご紹介いたします。

> HTML 文書において、 `document.createElement()` メソッドは `tagName` で指定された HTML 要素を生成します。
>
>
> [tip] <b></a>
>
> **構文**<br>
> `element = document.createElement(tagName)`
>
> **引数**<br>
> `tagName`: 生成される要素の型を特定する文字列です。
>
> [/tip]
> 

### 要素を追加する

MDN [Element.append()](https://developer.mozilla.org/ja/docs/Web/API/Element/append) より、ご紹介いたします。

> Element.append() メソッドは、一連の Node または DOMString オブジェクトを Element のの最後の子の後に挿入します。 DOMString オブジェクトは等価な Text ノードとして挿入されます。
>
>
> [tip] <b></a>
>
> **構文**<br>
> `append(...nodesOrDOMStrings)`
>
> * `...`は、残余引数（ざんよひきすう）を示す記法です。一つ又は複数の「ノード若しくは文字列」を引数として指定できます。
>
> [/tip]
> 

### 要素を削除する

MDN [Element.remove()](https://developer.mozilla.org/ja/docs/Web/API/Element/remove) より、ご紹介いたします。

> Element.remove() は所属するツリーから要素を削除します。
>
>
> [tip] <b></a>
>
> **構文**<br>
> `remove()`
>
> [/tip]
> 

### 要素を作成、追加、削除する例

新しい `<p>` 要素を作成して、`<body>` 要素に追加して見ましょう。

```
// 新しい p 要素を作成する
let newParagraph = document.createElement("p")

// p 要素に 文字列を追加する
newParagraph.append("DOMの学習は完了です")

// p 要素を body に追加する
let body = document.querySelector("body")
body.append(newParagraph)
```

コンソール画面で入力した結果は次のようになります。

![](create1.png)
「DOMの学習は完了です」と表示されています。


インスペクタ画面で確認してみると、新しい `<p>` 要素が、`<body>` 要素に追加されていることが分かります。

![](create2.png)
それでは要素を削除して見ましょう。

```
// p 要素を取得し 削除する
let paragraph = document.querySelector('p')
paragraph.remove()

// 変数に入力することなく 繋げて書くことも出来ます (メソッドチェーン)
// p 要素を取得し 削除する
document.querySelector('p').remove()

// ol 要素を削除する
document.querySelector('ol').remove()

// ul 要素を削除する
document.querySelector('ul').remove()
```

コンソール画面で実行すると、次のようになります。

![](create3.png)
長い DOM の学習も、これで完了です。これで JavaScript を使って、自由自在にHTMLを操作できるようになりました。ここでは基礎的ないくつかのメソッドを取り上げましたが、もう少し詳しく知りたく思うかもしれません。その時には、MDN には豊富なメソッドがその使用例と併せて紹介されています。ご覧になり、ご自身の能力を高めて行かれてください。

