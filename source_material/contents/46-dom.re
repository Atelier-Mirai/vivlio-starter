= @<code>{Document Object Model}

//abstract{
前章までに変数や定数、関数といったプログラミングの基本的な部品について紹介しました。
そしてあと二つ学ぶべき事柄が残っています。一つは「DOM(Document Object Model)」でもう一つは「イベントリスナ」です。この二つを習得することで、JavaScript から HTML を自由自在に操作できるようになります。

本章では、まず「DOM(Document Object Model)」についてご紹介いたします。
//}

== JavaScript から HTMLを操作する為の仕組み

DOMとは何でしょうか。
@<href>{https://e-words.jp/w/DOM.html,IT用語辞典} の説明を見て見ましょう。

//tip{
DOMとは、HTML文書を構成する要素をコンピュータプログラムで参照したり操作したりするための取り決め。

HTMLで記述されたウェブページなどの構成要素（見出し、段落、画像、リンクなど）と、それらの配置や見栄えなどを定めた属性情報などを参照、制御する手法を定めている。ウェブブラウザなどに実装されており、ページ上にJavaScriptなどで記述されたスクリプトからページ内の各要素を読み取ったり、内容や設定の変更、要素の追加や削除などを行う標準的な手段として用いられる。
//}

辞典ですので、きっちりと書かれておりますが、少し難しく感じるかもしれません。

MDN の @<href>{https://developer.mozilla.org/ja/docs/Web/API/Document_Object_Model/Introduction,DOMの紹介} がございますので、その一部を抜粋しましょう。

//tip{
ドキュメントオブジェクトモデル (DOM) はウェブ文書のためのプログラミングインターフェイスです。ページを表現するため、プログラムが文書構造、スタイル、内容を変更することができます。 DOM は プログラミング言語をページに接続することができます。
//}

分かりやすくなったでしょうか。

//tip{
**ドキュメントオブジェクトモデル (DOM)** とは、**HTMLで作られたウェブページと、プログラミング言語であるJavaScriptを繋ぐ為の仕組み** です。DOMを仲立ちにすることで、JavaScript から HTMLを操作することができます。
//}

#@# それでは、練習用の簡単なHTMLを準備して、実験して見ましょう。ファイル名は @<file>{dom.html}としましょう。
#@#
#@# //list[][dom.html][file=source/dom0.html, 1]{
#@# //}
#@#
#@# 作成した @<file>{dom.html} を、ブラウザで開いて見ましょう。小さな「開始」ボタンが表示されているはずです。
#@#
#@# 次に、もう一つファイルを作成し、ファイル名は @<file>{dom.js}とします。
#@# そして、次のようなJavaScriptのプログラムを書きましょう。
#@# //list[][dom.js][file=source/dom.js, 1]{
#@# //}
#@#
#@# この JavaScript を HTML から読み込む為に、最初に書いた @<file>{dom.html} の終わりに @<code>{<script src="dom.js"></script>} の一行を追加します。
#@#
#@# //list[][dom.html][file=source/dom.html, 1]{
#@# //}
#@#
#@# これで準備は完了です。
#@#
#@# もう一度、作成した @<file>{dom.html} を、ブラウザで開いて見ましょう。
#@# 先ほど表示されていた小さな「開始」ボタンに代わり、「もう一度」と表示されているはずです。
#@#
#@# JavaScript から HTMLを操作することが出来ました。
#@#
#@#
#@# 文書構造の為の @<code>{HTML}、装飾・配置の為の @<code>{CSS} と並んで、 @<code>{JavaScript} は、ウェブサイト作成の為に広く用いられます。
#@#
#@# その理由は、**@<code>{JavaScript**から@<code>{HTML}を制御・操作できる} からです。
#@#
#@# //blankline
#@#
#@# @<code>{HTML}文書をブラウザで読み込むと、@<code>{DOM(Document Object Model)} と呼ばれるプログラミング用のデータ表現が生成されます。@<code>{JavaScript} には、この @<code>{DOM(Document Object Model)} を操作できる機能が備わっていますので、ブラウザに読み込まれた @<code>{HTML}文書の内容(コンテンツ)やその構造を、@<code>{JavaScript} によって操作することができます。

#@# @<code>{DOM} では HTMLドキュメントのタグの入れ子関係を木構造で表現するため、@<code>{DOM} が表現するHTMLタグの木構造を @<code>{DOM} ツリー と呼びます。

#@# 例えば、@<code>{DOM} には HTML文書そのものを表現する @<code>{document} グローバルオブジェクトがあります。 @<code>{document} グローバルオブジェクトには、指定した@<code>{HTML} 要素を取得したり、新しく @<code>{HTML} 要素を作成するためのメソッド(方法・方式・手法、関数)が実装されています。 この @<code>{document} グローバルオブジェクトを使うことで、@<code>{HTML}に書かれた各要素を @<code>{JavaScript} から操作できます。
#@# @<fn>{41}
#@# //footnote[41][コードは「JavaScript Primer 迷わないための入門書」より引用・改変]

#@# //list[][HTMLの操作]{
#@# // CSSセレクタを使ってDOMツリー中のh1要素を取得する
#@# const heading = document.querySelector("h1");
#@#
#@# // h1要素に含まれるテキストコンテンツを取得する
#@# const headingText = heading.textContent;
#@#
#@# // 取得したテキストコンテンツを変更する
#@# heading.textContent = "こんにちは"
#@#
#@# // button要素を作成する
#@# const button = document.createElement("button");
#@# button.textContent = "ボタンを押してください";
#@#
#@# // body要素の子要素としてbuttonを挿入する
#@# document.body.appendChild(button);
#@# //}

#@# //blankline
#@# //vspace[latex][2mm]
#@#
#@# //blankline

=== 初めてのDOMツリー

#@# - @<code>{HTML}要素を取得・表示する

それでは、理解の為に例を使って練習しましょう。HTMLファイルとして @<file>{index.html} を JavaScriptファイルとして @<file>{introduction.js} を作成します。

//list[][][1]{
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>JavaScript練習</title>

    <!-- JavaScriptの読み込み -->
    <script src="introduction.js" @<b>{defer}></script>
  </head>

  <body>
    <h1>JavaScript練習</h1>
  </body>
</html>
//}

@<file>{index.html} に関しては、11行目で @<file>{introduction.js} を読み込むようにしています。

着目していただきたいのは、@<code>{@<b>{defer}} と書かれている箇所です。通常、ブラウザは上から順番に一行目、二行目と実行していきますので、11行目でJavaScriptを読み込むと、すぐに読み込んだ JavaScript のプログラムを実行しようとします。

JavaScript を使って、HTML の各要素を操作する場合、例えば @<code>{<h1>}の文字を取得しようとした場合、15行目にある @<code>{<h1>} はまだ読み込まれていないので、実行出来ずにエラーとなります。

@<code>{@<b>{defer}} を付けると、「HTMLの読み込み完了を待ってから、JavaScript が読み込まれ実行される」（「遅延読み込み」と言います）ため、無事に @<code>{<h1>} の文字列を取得することができます。

//blankline
@<file>{introduction.js} は次のように書きましょう。

//list[][introduction.js][1]{
// (1) CSSセレクタを使い、DOMツリーから操作したいh1要素を取得する
const element = document.querySelector("h1")

// (2) 取得したh1要素の内容物（コンテンツ、JavaScript練習）を取得する
const content = h1.textContent

// (3)取得した内容物(コンテンツ)「JavaScript練習」を表示する。
alert(content)
//}

実行した結果は次のようになります。画面に「JavaScript練習」とダイアログを表示させることが出来ました。

//image[dom0][][width=80%]
#@#
#@#  - (1) DOMから操作したいh1要素を取得する
#@#  - (2) 取得したh1から得たいものを取得する
#@#  - (3) 表示する
#@#
#@# の三段階、それぞれの処理を行っています。

== HTML要素を取得・更新する

=== 準備

簡単なHTMLでDOMツリーから要素を取得、表示することを体験しました。これから、DOMツリーを扱う為のメソッドをいくつか紹介いたします。練習しやすいよう、次のように HTML / CSS を用意しましょう。

//list[][index.html][1]{
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>JavaScript練習</title>
    <link rel="stylesheet" href="style.css">
    <script src="practise.js" @<b>{defer}></script>
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
//}

//list[][style.css][1]{
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
//}

HTML では、複数の@<code>{<li>}要素や、@<code>{class}属性、@<code>{id}属性も登場しています。@<code>{<span style="display: none;">} と 表示させないようインラインCSSが記述されていたり、@<code>{JavaScriptは、<br>「相互作用・動き・制御」の為の言語です。} と @<code>{<br>} タグで改行されています。

CSS でも要素セレクタ、クラスセレクタ、IDセレクタと三種類登場しています。

表示結果は次のようになります。
//image[dom1][][width=80%]

#@# 準備が出来ましたので、DOMツリー操作の為のいくつかの基本的なメソッドを学んで行きましょう。

=== (1) DOMから操作したい要素を取得する

DOMから操作したい要素を取得するためには、次の3つのメソッドが用意されています。MDN に詳細が記されていますので、抜粋しつつ、それぞれのメソッドに関して見ていきましょう。

 * @<code>{@<href>{https://developer.mozilla.org/ja/docs/Web/API/Document/getElementById, Document.getElementById()}}
 * @<code>{@<href>{https://developer.mozilla.org/ja/docs/Web/API/Document/querySelector, Document.querySelector()}}
 * @<code>{@<href>{https://developer.mozilla.org/ja/docs/Web/API/Document/querySelectorAll, Document.querySelectorAll()}}


==== Document.getElementById()

//quote{
Document の getElementById() メソッドは、 id プロパティが指定された文字列に一致する要素を表す Element オブジェクトを返します。要素の ID は指定されていれば固有であることが求められているため、特定の要素にすばやくアクセスするには便利な方法です。

ID を持たない要素にアクセスする必要がある場合は、 querySelector() で何らかのセレクタを使用して要素を検索することができます。

//tip{
**構文**@<br>{}
@<code>{element = document.getElementById(id)}@<br>{}

**引数**@<code>{id}@<br>{}
探す要素の ID です。 ID は大文字と小文字の区別がある文字列で、文書内で固有です。指定された ID の要素は一つしかありません。@<br>{}

**返値**@<br>{}
指定された ID に一致する DOM 要素オブジェクトを記述した Element オブジェクト、または文書内に一致する要素がなければ null です。
//}
//}

「**探す要素の ID**」とありますので、DOMツリーから ID が @<code>{"html"} の要素 を選択したい場合には、次のように書けば良いことが分かります。

//list[][][1]{
// ID属性が html の要素を取得する
let html = document.getElementById("html")
//}

コンソール画面で、@<code>{element = document.getElementById("html")} と入力すると、@<code>{<li id="html">} と表示されます。表示された @<code>{<li id="html">} にマウスカーソルを重ねると、どの部分を選択しているのか、確認できます。

//image[dom1a][][width=80%]

==== Document.querySelector()

//quote{
Document の querySelector() メソッドは、指定されたセレクタまたはセレクタ群に一致する、文書内の**最初の Element** を返します。一致するものが見つからない場合は null を返します。

//tip{
**構文**@<br>{}
@<code>{element = document.querySelector(selectors)}@<br>{}

**引数** @<code>{selectors}@<br>{}
DOMString で、照合する 1 つ以上のセレクタを設定します。この文字列は妥当な CSS セレクタでなければなりません。@<br>{}

**返値**@<br>{}
Element オブジェクトで、文書内で指定された CSS セレクタに**最初に一致する要素**を示すオブジェクト、もしくは、一致する要素がない場合は null を返します。

指定されたセレクタに一致するすべての要素のリストが必要な場合は、代わりに querySelectorAll() を使用してください。
//}

//}

「@<code>{selectors} の文字列は妥当な CSS セレクタでなければなりません。」とあります。CSSでは @<code>{<h1>}要素を選択する際に@<code>{h1}と書きますが、同様に、DOMツリーから @<code>{<h1>}要素 を選択する場合には、次のように書けば良いことが分かります。

//list[][][1]{
// (最初の) <h1>要素を取得する
let h1 = document.querySelector("h1")
//}

 : @<code>{document.querySelector("li")}
    単一のセレクタで指定すると、(複数の@<code>{<li>}が該当しますが、最初に見つかった) @<code>{<li class="hardware">コンピュータ <span>(Mac / Linux / Windows など)</span></li>} を取得できます。
 : @<code>{document.querySelector("ol li span")}
    (@<code>{li}のような単一のセレクタではなく) 複数のセレクタを並べると、@<code>{<span>(Mac / Linux / Windows など)</span>} を取得できます。
 : @<code>{document.querySelector(".hardware")}
    クラス名を指定すると、@<code>{<li class="hardware">コンピュータ <span>(Mac / Linux / Windows など)</span></li>} を取得できます。
 : @<code>{document.querySelector("#html")}
    ID属性を指定すると、@<code>{<li id="html">HTMLは、「文書構造」の為の言語です。</li>} を取得できます。@<br>{}
    (@<code>{document.getElementById("html")} でも取得できます。 @<code>{#}の有無にも着目してください。)

コンソール画面で、@<code>{element = document.querySelector("li")} と入力すると、@<code>{<li class="hardware>} と表示されます。表示された @<code>{<li class="hardware">} にマウスカーソルを重ねると、どの部分を選択しているのか、確認できます。

//image[dom2][][width=90%]
---
==== Document.querySelector**All**()

@<code>{querySelector()}メソッドとよく似ていますが、メソッド名の最後に**All** と付いています。

違いもまたその点に有り、「@<code>{querySelector()}メソッドは、指定されたセレクタまたはセレクタ群に一致する、文書内の**最初のElement** を返します。」とあるように、いくつかの要素が該当した場合には、最初の一つが返ってきます。よって、@<code>{document.querySelector("li")} と書くと、六つの @<code>{<li>} 要素の内、最初の一つを得ることが出来ます。

六つの @<code>{<li>} 要素 **全て**を取得する為には、次のように書きます。

//list[][][1]{
// 六つの <li> 要素 全て を取得する
let lists = document.querySelectorAll("li")}
//}


//image[dom3][][width=90%]

コンソール画面で、@<code>{elements = document.querySelectorAll("li")} と入力すると、@<code>{NodeList(6) [ li.hardware, li.software, li.software, li#html, li#css, li#javascript ]} と表示されます。表示された @<code>{li.hardware} や @<code>{li.software} などにマウスカーソルを重ねると、どの部分を選択しているのか、確認できます。

//blankline
@<code>{NodeList(6) [ li.hardware, li.software, li.software, li#html, li#css, li#javascript ]} と表示されているように、通常の配列のように扱えます。

ですので、 @<code>{elements[0]} と書いて @<code>{li.hardware} を、@<code>{elements[1]} と書いて @<small>{(最初の)}@<code>{li.software} を、扱うことができます。

また、配列のように扱えますので、繰り返しの為の構文「@<code>{for...of}」文を用いると、取得した六つの要素を表示できます。

コンソール画面に入力して、確認してみましょう。

//list[][][1]{
// 取得した六つの <li> 要素 全て を表示する
for (const li of lists) {
  console.log(li);
}
//}

//image[dom4][][width=80%]



=== (2) 取得した要素から得たい内容物(コンテンツ)を取得する

取得した要素から得たい内容物(コンテンツ)を取得する為にも、次の3つのメソッドが用意されています。MDN に詳細が記されています。抜粋しつつ、それぞれのメソッドに関して見ていきましょう。

 * @<code>{@<href>{https://developer.mozilla.org/ja/docs/Web/API/Element/innerHTML, Element.innerHTML}}
 * @<code>{@<href>{https://developer.mozilla.org/ja/docs/Web/API/HTMLElement/innerText, HTMLElement.innerText}}
 * @<code>{@<href>{https://developer.mozilla.org/ja/docs/Web/API/Node/textContent, Node.textContent}}


==== Element.innerHTML

//quote{
Element オブジェクトの innerHTML プロパティは、要素内の HTML のマークアップを取得したり設定したりします。

//tip{
**構文**@<br>{}

**要素内の HTML のマークアップを「取得」するとき**@<br>{}
@<code>{content = element.innerHTML}@<br>{}

**要素内の HTML のマークアップを「設定」するとき**@<br>{}
@<code>{element.innerHTML = content}@<br>{}

**値**@<br>{}
要素の子孫を HTML にシリアライズしたものを含んだ DOMString です。 innerHTML に値を設定すると、要素のすべての子孫を削除して、htmlString の文字列で与えられた HTML を解釈して構築されたノードに置き換えます。
//}
//}

それでは、要素内の HTML を取得したり、設定したりしてみましょう。

//list[][マークアップコンテンツを取得する例][1]{
// DOMツリーから要素を取得
let element = document.querySelector("h1")
// マークアップコンテンツを取得する
let content = element.innerHTML
// 取得したマークアップコンテンツを表示する
console.log(content)
//}

コンソール画面で入力すると、「JavaScript練習」と表示されています。

//image[dom5][][width=80%,pos=H]

次に @<code>{<h1>}要素に、マークアップを設定して見ましょう。

//list[][マークアップコンテンツを設定する例][1]{
// DOMツリーから要素を取得
let element = document.querySelector("h1")
// マークアップコンテンツを設定する
let element.innerHTML = "JavaScript<br>練習"
//}


コンソール画面に入力すると、@<code>{JavaScript<br>練習} と @<code>{<br>} を入れたので、改行されて表示されています。

//image[dom7][][width=80%]
---
==== HTMLElement.innerText

//quote{
innerText は HTMLElement のプロパティで、ノードとその子孫の「レンダリングされている」テキスト内容を示します。

ゲッターとしては、カーソルで要素の内容を選択しクリップボードにコピーした際のテキストに近いものを取得することができます。 セッターとしては、この要素の子要素を指定された値で置き換え、すべての改行を @<code>{<br>} 要素に変換します。

//tip{
**構文**@<br>{}

**要素内の テキスト内容を「取得」するとき**@<br>{}
@<code>{content = element.innerText}@<br>{}

**要素内の テキスト内容を「設定」するとき**@<br>{}
@<code>{element.innerText = content}@<br>{}
//}
//}

要素内の テキスト内容 を取得したり、設定したりしてみましょう。

//list[][テキスト内容を取得する例][1]{
// DOMツリーから要素を取得
let element = document.getElementById("javascript")
// テキスト内容を取得する
let content = element.innerText
// 取得したテキスト内容を表示する
let console.log(content)
//}

HTMLでは、@<code>{<li id="javascript">JavaScriptは、<br>「相互作用・動き・制御」の為の言語です。</li>} のように、 @<code>{<br>} タグで改行していました。

ID属性を指定しているので、 @<code>{document.getElementById("javascript")} として、この要素を取得します。

そして、 @<code>{content = element.innerHTML} で、テキスト内容を取得できたので、取得したテキスト内容を表示するために、 @<code>{console.log(content)} と入力します。

コンソール画面で入力すると、@<br>{}
　　　"JavaScriptは、@<br>{}
　　　「相互作用・動き・制御」の為の言語です。"@<br>{}
と @<code>{<br>} タグは、改行に置換されて、表示されています。

//image[dom8][][width=80%,pos=H]

それでは、この @<code>{<li id="javascript">}要素の、テキスト内容を設定して見ましょう。

//list[][テキスト内容を設定する例][1]{
// DOMツリーから要素を取得
let element = document.getElementById("javascript")
// テキスト内容を設定する
let element.innerText = `JavaScriptを利用すると、
HTML要素の取得や更新など、
さまざまなことが行えます。`
//}

改行文字を設定しやすいよう、 @<code>{``(バッククォート)} で「JavaScriptを利用すると〜行えます。」を囲んでいます。

//blankline
コンソール画面で入力すると、@<br>{}
　　　"JavaScriptを利用すると、@<br>{}
　　　HTML要素の取得や更新など、@<br>{}
　　　さまざまなことが行えます。@<br>{}
と 改行文字は @<code>{<br>} に置換されて、表示されています。

//image[dom9][][width=80%]
---
==== Node.textContent

//quote{

textContent は Node のプロパティで、ノードおよびその子孫のテキストの内容を表します。

//tip{
**構文**@<br>{}

**要素内の テキスト内容を「取得」するとき**@<br>{}
@<code>{content = element.textContent}@<br>{}

**要素内の テキスト内容を「設定」するとき**@<br>{}
@<code>{element.textContent = content}@<br>{}
//}
//}

要素内の テキスト内容 を取得したり、設定したりしてみましょう。

//list[][テキスト内容を取得する例][1]{
// DOMツリーから要素を取得
let element = document.querySelector("li:nth-child(2)")
// テキスト内容を取得する
let content = element.textContent
// 取得したテキスト内容を表示する
console.log(content)
//}

ここでは、二番目の @<code>{<li>}要素である @<code>{<li class="software">エディタ <span style="display: none;">(Windsurf / Zed / VS Codeなど)</span></li>} に着目します。 HTML上では @<code>{<span>} タグに Windsurf など具体的なエディタ名が書かれているのですが、@<code>{<span style="disdplay: none;"} と、インラインCSSにより、非表示となっています。

これがどのようにテキスト内容として取得されるのか、が着目点です。

//blankline
コンソール画面で入力すると、@<br>{}
　　　エディタ (Windsurf / Zed / VS Codeなど)@<br>{}
と 非表示となっている @<code>{<span>} タグ内のテキストも取得されています。

//image[dom10][][width=80%,pos=H]

それでは、この @<code>{<li id="javascript">}要素の、テキスト内容を設定して見ましょう。

//list[][テキスト内容を設定する例][1]{
// DOMツリーから要素を取得
let element = document.querySelector("li:nth-child(2)")
// テキスト内容を設定する
element.textContent = "エディタ (Windsurf / Zed / VS Codeなど)"
//}

コンソール画面で入力すると「エディタ (Windsurf / Zed / VS Codeなど)」と全て表示されます。

//image[dom11][][width=80%]

もとの HTML は、@<code>{<li class="software">エディタ <span style="display: none;">(Windsurf / Zed / VS Codeなど)</span></li>} と書かれていましたが、 @<code>{textContent} メソッドにより @<code>{<li class="software">エディタ (Windsurf / Zed / VS Codeなど)</li>} と、元あったの @<code>{<span>} タグも消去され、@<code>{textContent} での設定文字になることにも注目してください。


=== innerHTML, innerText, textContent の違い

MDN @<href>{https://developer.mozilla.org/ja/docs/Web/API/Node/textContent, textContent} に、三つの取得/設定メソッドの違いについて、記載されておりますので、抜粋して掲載いたします。どのメソッドを用いるべきか、使い分けの参考にしてください。

//tip{
 * @<code>{textContent} は、 @<code>{<script>} と @<code>{<style>} 要素を含む、すべての要素の中身を取得します。
 * @<code>{innerText} は「人間が読める」要素のみを示します。

//blankline
 * @<code>{textContent} はノード内のすべての要素を返します。
 * @<code>{innerText} はスタイルを反映し、「非表示」の要素のテキストは返しません。

//blankline
 * @<code>{textContent} は テキストの内容を返します。
 * @<code>{innerHTML} は、その名が示すとおり @<code>{HTML} を返します。
//}


== 属性を操作する



=== ID属性の追加や削除を行う

MDN @<href>{https://developer.mozilla.org/ja/docs/Web/API/Element/id, Element.id} より、ご紹介いたします。

//quote{

id は Element インターフェイスのプロパティで、グローバル属性の id を反映した要素の識別子を表します。

id の値が空文字列でない場合は、文書内で固有でなければなりません。

id はよく getElementById() で特定の要素を受け取るために使用します。他の一般的な用途としては、要素の ID をセレクターとして CSS で文書をスタイル付けするために使用されます。

//tip{
**構文**@<br>{}

**要素のIDを「取得」するとき**@<br>{}
@<code>{idStr = element.id}@<br>{}

**要素のIDを「設定」するとき**@<br>{}
@<code>{element.id = newid}@<br>{}

**要素のIDを「削除」するとき**@<br>{}
@<code>{element.removeAttribute("id")}@<br>{}
//}
//}

要素のIDを取得/設定/削除してみましょう。

//list[][ID操作の例][1]{
// DOMツリーから要素を取得
let element = document.getElementById("css")

// ID文字列を取得する
let idString = element.id

// 取得したID文字列を表示する
console.log(idString)
//}

コンソール画面に入力した結果です。

//image[id0][][width=80%]

続いて、新しいIDを設定して見ましょう。

//list[][][1]{
// 新しいIDを設定する
element.id = "CascadingStyleSheet"
//}

コンソール画面に入力した結果は次の通りです。
//image[id1][][width=80%]

今まで@<code>{cyan} で表示されていたCSSの項目が、新しいIDを設定したことに伴い、 @<code>{blue} で表示されています。

「インスペクタ」画面で確認すると、IDが @<code>{CascadingStyleSheet} に更新されていること、CSS として、@<code>{{ background: blue; color: white; \}} が適用されていることが確認できます。

//image[id2][][width=75%]


//blankline
最後に、IDの削除を行って見ましょう。IDを削除する為の専用のメソッドは備わっていません。汎用的に属性を削除できる @<code>{removeAttribute()} メソッドを使って行います。

//list[][][1]{
// 要素のIDを削除する
element.removeAttribute("id")
//}

//image[id3][][width=75%]

要素からIDを削除しましたので、それに伴い、青色の背景色で表示するCSSも適用されなくなっています。





=== クラス名の追加や削除を行う

MDN @<href>{https://developer.mozilla.org/ja/docs/Web/API/Element/className, Element.className} より、ご紹介いたします。

//quote{
className は Element インターフェイスのプロパティで、この要素の class 属性の値を取得したり設定したりします。

//tip{
**構文**@<br>{}

**要素のクラス名を「取得」するとき**@<br>{}
@<code>{cName = element.className}@<br>{}

**要素のクラス名を「設定」するとき**@<br>{}
@<code>{element.className = cName}@<br>{}

 * @<code>{cName} は文字列変数で、現在の要素のクラスまたは空白区切りのクラス群を表します。
 * このプロパティでは、 @<code>{className} という名前が @<code>{class} の代わりに使用されています。 これは @<code>{DOM} を操作するために使用される多くの言語と @<code>{"class"} キーワードが競合するためです。

**クラス名を「削除」するとき**@<br>{}
@<code>{element.removeAttribute("class")}@<br>{}
//}
//}

要素のクラス名を取得/設定/削除してみましょう。

//list[][クラス名操作の例][1]{
// DOMツリーから要素を取得
let element = document.querySelector("li:first-child")

// クラス名を取得する
let name = element.className

// 取得したクラス名を表示する
console.log(name)
//}

コンソール画面に入力した結果です。

//image[className0][][width=80%]

続いて、新しいクラス名を設定して見ましょう。

//list[][][1]{
// 新しいクラス名を設定する
element.className = "effect"
//}

コンソール画面に入力した結果は次の通りです。
//image[className1][][width=75%]

@<code>{.hardware} クラスには、 @<code>{.hardware { border-bottom: solid 3px lime; }} と指定していましたが、クラス名を @<code>{.effect} に変更したので @<code>{.effect { font-weight: bold; font-style: italic; }} と表示されます。

//image[className2][][width=75%]

「インスペクタ」画面で確認すると、クラス名が @<code>{.effect} に更新されていることや、@<code>{{ font-weight: bold; font-style: italic; \}} が適用されていることが確認できます。

//blankline
もしかすると、クラス名を変更するのではなく、新しいクラス名を追加したかったのかもしれません。新しいクラス名を追加するには次のようにします。

//list[][][1]{
// 新しいクラス名を「追加」設定する
element.className = `${name} effect`
//}

先に取得した @<code>{name} には、元のクラス名 @<code>{hardware} が保存されているので「式展開（テンプレートリテラル・テンプレート文字列）」を使いクラス名を追加します( @<small>{@<code>{``}(バッククォート)で囲みます})。

//image[className3][][width=80%]
---
最後に、クラス名の削除を行って見ましょう。クラス名を削除する為の専用のメソッドは備わっていません。汎用的に属性を削除できる @<code>{removeAttribute()} メソッドを使って行います。

//list[][][1]{
// 要素のクラス名を削除する
element.removeAttribute("class")
//}

//image[className4][][width=80%]

要素からクラス名を削除しましたので、それに伴い、下線や斜体などのCSSも適用されなくなっています。
---
=== 属性の追加や削除を行う

MDN @<href>{https://developer.mozilla.org/ja/docs/Web/API/Element/setAttribute, element.setAttribute} より、ご紹介いたします。

//quote{
指定の要素に新しい属性を追加します。または指定の要素に存在する属性の値を変更します。

//tip{
**構文**@<br>{}
**要素の属性を「取得」するとき**@<br>{}
@<code>{value = element.getAttribute("attrName")}@<br>{}
または@<br>
value = element.attrName

**要素の属性を「設定」するとき**@<br>{}
@<code>{element.setAttribute("attrName", value)}

 * @<code>{attrName} は属性の名前を文字列で表現したものです。
 * @<code>{value} は属性に設定したい値です。

**要素の属性を「削除」するとき**@<br>{}
@<code>{element.removeAttribute("attrName")}@<br>{}
//}
//}

要素の属性を取得/設定/削除してみましょう。様々な属性がありますが、ここではタイトル属性(@<code>{title}) にしましょう。

//list[][クラス名操作の例][1]{
// DOMツリーから要素を取得
let element = document.querySelector("h1")

// タイトル属性を取得する
let value = element.title

// 取得したタイトル属性を表示する
console.log(value)
//}

コンソール画面に入力した結果です。

//image[attr1][][width=80%]

もともと @<code>{<h1>JavaScript練習</h1>} と書いていますので、属性は何も設定されていません。ですので取得した @<code>{value} を表示させる為に @<code>{console.log(value)} としましたが、表示できるものが何もないので、 @<code>{<empty string>} と表示されます。

//blankline
#@# //clearpage
それでは、タイトル属性に新しい値として「千里の道も一歩から」を設定して見ましょう。

//list[][][1]{
// DOMツリーから要素を取得
let element = document.querySelector("h1")

// タイトル属性に新しい値を設定する
element.setAttribute("title", "千里の道も一歩から")

// タイトル属性を取得する
let value = element.title

// 取得したタイトル属性を表示する
console.log(value)
//}

//sideimage[attr2a][70mm][sep=5mm,side=R]{
コンソール画面に入力してみましょう。

//blankline

「インスペクタ」画面で確認すると、@<code>{title}属性が付与され @<code>{<h1 title="千里の道も一歩から">JavaScript練習</h1>} に更新されていること、マウスカーソルを重ねると、「千里の道も一歩から」と、@<code>{title}属性 が表示されます。

//}
#@# //image[attr2][][width=70%]


//image[attr3][][width=70%]

//blankline
最後に、タイトル属性の削除を行って見ましょう。

//list[][][1]{
// タイトル属性を削除する
element.removeAttribute("title")
//}

== 新しい要素を作成・追加・削除する

=== 要素を作成する
MDN @<href>{https://developer.mozilla.org/ja/docs/Web/API/Document/createElement, Document.createElement()} より、ご紹介いたします。

//quote{
HTML 文書において、 @<code>{document.createElement()} メソッドは @<code>{tagName} で指定された HTML 要素を生成します。

//tip{
**構文**@<br>{}
@<code>{element = document.createElement(tagName)}

**引数**@<br>{}
@<code>{tagName}: 生成される要素の型を特定する文字列です。

//}
//}

=== 要素を追加する
MDN @<href>{https://developer.mozilla.org/ja/docs/Web/API/Element/append, Element.append()} より、ご紹介いたします。

//quote{
Element.append() メソッドは、一連の Node または DOMString オブジェクトを Element のの最後の子の後に挿入します。 DOMString オブジェクトは等価な Text ノードとして挿入されます。

//tip{
**構文**@<br>{}
@<code>{append(...nodesOrDOMStrings)}

 * @<code>{...}は、@<ruby>{残余引数,ざんよひきすう}を示す記法です。一つ又は複数の「ノード若しくは文字列」を引数として指定できます。

//}
//}

=== 要素を削除する
MDN @<href>{https://developer.mozilla.org/ja/docs/Web/API/Element/remove, Element.remove()} より、ご紹介いたします。

//quote{
Element.remove() は所属するツリーから要素を削除します。

//tip{
**構文**@<br>{}
@<code>{remove()}
//}
//}

=== 要素を作成、追加、削除する例

新しい @<code>{<p>} 要素を作成して、@<code>{<body>} 要素に追加して見ましょう。

//list[][][1]{
// 新しい p 要素を作成する
let newParagraph = document.createElement("p")

// p 要素に 文字列を追加する
newParagraph.append("DOMの学習は完了です")

// p 要素を body に追加する
let body = document.querySelector("body")
body.append(newParagraph)
//}

コンソール画面で入力した結果は次のようになります。
//image[create1][][width=80%]

「DOMの学習は完了です」と表示されています。

//blankline
インスペクタ画面で確認してみると、新しい @<code>{<p>} 要素が、@<code>{<body>} 要素に追加されていることが分かります。

//image[create2][][width=80%]

それでは要素を削除して見ましょう。

//list[][][1]{
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
//}

コンソール画面で実行すると、次のようになります。
//image[create3][][width=80%]


長い DOM の学習も、これで完了です。これで JavaScript を使って、自由自在にHTMLを操作できるようになりました。ここでは基礎的ないくつかのメソッドを取り上げましたが、もう少し詳しく知りたく思うかもしれません。その時には、MDN には豊富なメソッドがその使用例と併せて紹介されています。ご覧になり、ご自身の能力を高めて行かれてください。
