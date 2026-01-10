# HTML / CSS / JavaScript 簡易まとめ

:::{.chapter-lead}
HTML / CSS / JavaScript に関する簡易なまとめです。タグを使用して作成されるHTML要素を一覧表示しています。見つけやすいように、機能別にグループ化しています。


[HTML 要素リファレンス](https://developer.mozilla.org/ja/docs/Web/HTML/Element)より、抄訳しております。引用元にはより詳細な解説や使用例等が掲載されておりますので、是非ご活用下さい。
:::



## HTML 簡易まとめ

HTML は Hyper Text Markup Language 超文書印付け言語 の意味で、ウェブサイトにおける文書構造の記述に用います。


### コメント

プログラミング言語では、ソースコード中に記述されるがコードとしては解釈されない、人に向けた文字列をコメントといいます。主にコードの記述者が別の開発者などにコードの意味や動作、使い方、注意点等について注釈や説明を加える為に使われます。 [^105]

[^105]: 出典：IT用語辞典

HTMLでは、コメントは以下のように記述します。

<div class="table table-nohline">
<table>
<tr class="hline"><th>記述例</th><th> 説明</th></tr>
<tr class="hline"><td>`<!-- コメント --> `</td><td> コメント</td></tr>
</table>
</div>


### メインルート

<div class="table table-nohline">
<table>
<tr class="hline"><th>要素</th><th> 説明</th></tr>
<tr class="hline"><td>`<html>`</td><td> HTML 文書においてルート (基点) となる要素 (トップレベル要素) であり、ルート要素とも呼ばれます。他の全ての要素は、この要素の子孫として配置します。</td></tr>
</table>
</div>


### 文書メタデータ

メタデータは、ページに関する情報のことです。これは検索エンジンやブラウザなどが利用する、およびページの描画を支援するスタイル、スクリプト、データといった情報を含みます。スタイルやスクリプトのメタデータはページ内で定義するか、それらの情報を持つ別のファイルへのリンクとして定義します。

<div class="table table-nohline">
<table>
<tr class="hline"><th>要素</th><th> 説明</th></tr>
<tr class="hline"><td>`<head>`</td><td> 文書に関する機械可読な情報 (metadata)、たとえば題名、スクリプト、スタイルシートなどを含みます。</td></tr>
<tr class="hline"><td>`<link>`</td><td> 外部リソースへのリンク要素です。現在の文書と外部のリソースとの関係を指定します。この要素はCSSへのリンクに最もよく使用されますが、サイトのアイコン (favicon スタイルのアイコンと、モバイル端末のホーム画面やアプリのアイコンの両方) の確立や、その他のことにも使用されます。</td></tr>
<tr class="hline"><td>`<meta>`</td><td> 他のメタ関連要素 (base / link / script / style / title) で表すことができない任意のmetadataを提示します。</td></tr>
<tr class="hline"><td>`<style>`</td><td> 文書あるいは文書の一部分のスタイル情報を含みます。</td></tr>
<tr class="hline"><td>`<title>`</td><td> 題名要素です。ブラウザのタイトルバーやページのタブに表示される文書の題名を定義します。</td></tr>
</table>
</div>


### 区分化ルート

<div class="table table-nohline">
<table>
<tr class="hline"><th>要素</th><th> 説明</th></tr>
<tr class="hline"><td>`<body>`</td><td> HTML文書のコンテンツを示す要素で、`<body>`要素は一つだけ配置できます。</td></tr>
</table>
</div>


### コンテンツ区分

コンテンツ区分要素は、文書のコンテンツを論理的な断片に体系づけます。ページのコンテンツでヘッダーやフッターのナビゲーション、あるいはコンテンツのセクションを識別する見出しなどの、大まかなアウトラインを作成するために区分要素を使用します。

<div class="table table-nohline">
<table>
<tr class="hline"><th>要素</th><th> 説明</th></tr>
<tr class="hline"><td>`<address>`</td><td> これを含んでいる HTML が個人、団体、組織の連絡先を提供していることを示します。</td></tr>
<tr class="hline"><td>`<article>`</td><td> 文書、ページ、アプリケーション、サイトなどの中で自己完結しており、 (集合したものの中で) 個別に配信や再利用を行うことを意図した構成物を表します。</td></tr>
<tr class="hline"><td>`<aside>`</td><td> 文書のメインコンテンツと間接的な関係しか持っていない文書の部分を表現します。</td></tr>
<tr class="hline"><td>`<footer>`</td><td> 直近の区分コンテンツまたは `<body>` 要素のフッターを表します。フッターには通常、そのセクションの著作者に関する情報、関連文書へのリンク、著作権情報等を含めます。</td></tr>
<tr class="hline"><td>`<header>`</td><td> 導入部やナビゲーション等のグループを表すコンテンツです。見出し要素だけでなく、ロゴ、検索フォーム、作者名、その他の要素を含むこともできます。</td></tr>
</table>
</div>
<div class="table table-nohline">
<table>
<tr class="hline"><th>要素</th><th> 説明</th></tr>
<tr class="hline"><td>`<h1>` `<h2>` `<h3>` <br>`<h4>` `<h5>` `<h6>`</td><td> セクションの見出しを6段階で表します。 <br>`<h1>`が最上位で、`<h6>`が最下位です。</td></tr>
<tr class="hline"><td>`<main>`</td><td> 文書の `<body>` の主要な内容を表します。主要な内容とは、文書の中心的な主題、またはアプリケーションの中心的な機能に直接関連または拡張した内容の範囲のことです。</td></tr>
<tr class="hline"><td>`<nav>`</td><td> 現在の文書内の他の部分や他の文書へのナビゲーションリンクを提供するためのセクションを表します。ナビゲーションセクションの一般的な例としてメニュー、目次、索引などがあります。</td></tr>
<tr class="hline"><td>`<section>`</td><td> 文書の自立した一般的なセクション (区間) を表します。そのセクションを表現するより意味的に具体的な要素がない場合に使用します。</td></tr>
</table>
</div>


### テキストコンテンツ

テキストコンテンツ要素は、開始タグ `<body>` と終了タグ `</body>` の間にあるコンテンツでブロックやセクションを編成します。これらの要素はコンテンツの用途や構造を識別するものであり、アクセシビリティ や SEO のために重要です。

<div class="table table-nohline">
<table>
<tr class="hline"><th>要素</th><th> 説明</th></tr>
<tr class="hline"><td>`<div>`</td><td> フローコンテンツの汎用コンテナです。CSS を用いて何らかのスタイル付けがされる (例えば、スタイルが直接適用されたり、親要素にグリッドなど何らかのレイアウトモデルが適用されるなど) までは、コンテンツやレイアウトには影響を与えません。</td></tr>
<tr class="hline"><td>`<figure>`</td><td> 図表などの自己完結型のコンテンツを表します。任意で figcaption 要素を使用してキャプション(見出し)を付けることができます。</td></tr>
<tr class="hline"><td>`<figcaption>`</td><td> 親の figure 要素内にあるその他のコンテンツを説明するキャプション(見出し)や凡例を表します。</td></tr>
<tr class="hline"><td>`<ol>`</td><td> 項目の順序付きリストを表します。ふつうは番号付きのリストとして表示されます。</td></tr>
<tr class="hline"><td>`<ul>`</td><td> 項目の順序なしリストを表します。一般的に、行頭記号を伴うリストとして描画されます。</td></tr>
<tr class="hline"><td>`<li>`</td><td> リストの項目を表すために用いられます。</td></tr>
<tr class="hline"><td>`<p>`</td><td> テキストの段落を表します。</td></tr>
<tr class="hline"><td>`<hr>`</td><td> 段落レベルの要素間において、テーマの意味的な区切りを表します。例えば、話の場面の切り替えや、節内での話題の転換などです。</td></tr>
</table>
</div>


### インライン文字列意味付け

インラインテキストセマンティクス要素は、単語、行、あるいは任意のテキスト範囲の意味、構造、スタイルを定義します。

<div class="table table-nohline">
<table>
<tr class="hline"><th>要素</th><th> 説明</th></tr>
<tr class="hline"><td>`<a>`</td><td> アンカー要素は、`href`属性を用いて、別のウェブページ、ファイル、メールアドレス、同一ページ内の場所、または他の URL へのハイパーリンクを作成します。</td></tr>
<tr class="hline"><td>`<br>`</td><td> 文中に改行（キャリッジリターン）を生成します。詩や住所など、行の分割が重要な場合に有用です。</td></tr>
<tr class="hline"><td>`<b>`</td><td> 注目付け要素です。要素の内容に読み手の注意を惹きたい場合で、他の特別な重要性が与えられないものに使用します。</td></tr>
<tr class="hline"><td>`<em>`</td><td> 強調されたテキストを示します。入れ子にすることができ、入れ子の段階に応じてより強い程度の強調を表すことができます。</td></tr>
<tr class="hline"><td>`<i>`</td><td> 興味深いテキスト要素です。何らかの理由で他のテキストと区別されるテキストの範囲を表します。</td></tr>
<tr class="hline"><td>`<strong>`</td><td> 強い重要性要素です。内容の重要性、重大性、または緊急性が高いテキストを表します。ブラウザは一般的に太字で描画します。</td></tr>
<tr class="hline"><td>`<small>`</td><td> 著作権表示や法的表記のような、注釈や小さく表示される文を表します。既定では、`small` から `x-small` のように、一段階小さいフォントでテキストが表示されます。</td></tr>
<tr class="hline"><td>`<span>`</td><td> 記述コンテンツの汎用的な行内コンテナであり、何かを表すものではありません。`class` または `id` 属性を使用して、スタイル付けのために使用することができます。</td></tr>
</table>
</div>


### 画像とマルチメディア

HTML は 画像、音声、映像といった、さまざまなマルチメディアリソースをサポートします。

<div class="table table-nohline">
<table>
<tr class="hline"><th>要素</th><th> 説明</th></tr>
<tr class="hline"><td>`<img>`</td><td> 文書に画像を埋め込みます。</td></tr>
<tr class="hline"><td>`<audio>`</td><td> 文書内に音声コンテンツを埋め込むために使用します。</td></tr>
<tr class="hline"><td>`<video>`</td><td> 映像要素です。文書中に映像再生に対応するメディアプレイヤを埋め込みます。</td></tr>
</table>
</div>


### SVG と MathML

SVG と MathML のコンテンツを、 <svg> および <math> 要素を使用して直接 HTML 文書に埋め込むことができます。

<div class="table table-nohline">
<table>
<tr class="hline"><th>要素</th><th> 説明</th></tr>
<tr class="hline"><td>`<svg>`</td><td> SVG(Scalable Vector Graphics)形式の図形描画のための要素です。直線、矩形、円、楕円、多角形、折れ線やベジェ曲線の描画が可能です。</td></tr>
<tr class="hline"><td>`<math>`</td><td> 数式を記述する際に用います。</td></tr>
</table>
</div>


### スクリプティング

動的なコンテンツやウェブアプリケーションを作成するために、HTML ではスクリプト言語を使用できます。もっとも有名な言語は、JavaScript です。

<div class="table table-nohline">
<table>
<tr class="hline"><th>要素</th><th> 説明</th></tr>
<tr class="hline"><td>`<canvas>`</td><td> `<canvas>`要素 と `Canvas スクリプティング API` や `WebGL API` を使用して、グラフィックやアニメーションを描画することができます。</td></tr>
<tr class="hline"><td>`<script>`</td><td> 実行できるコードやデータを埋め込むために使用します。ふつうは JavaScript のコードの埋め込みや参照に使用されます。</td></tr>
<tr class="hline"><td>`<noscript>`</td><td> このページ上のスクリプトの種類に対応していない場合や、スクリプトの実行がブラウザーで無効にされている場合に表示する HTML の部分を定義します。</td></tr>
</table>
</div>


### 表(テーブル)

以下の要素は、表形式のデータを作成および制御するために使用します。

<div class="table table-nohline">
<table>
<tr class="hline"><th>要素</th><th> 説明</th></tr>
<tr class="hline"><td>`<table>`</td><td> 表形式のデータ、つまり、行と列の組み合わせによるセルに含まれたデータによる二次元の表で表現される情報です。</td></tr>
<tr class="hline"><td>`<caption>`</td><td> 表のキャプション (またはタイトル) を指定します。</td></tr>
<tr class="hline"><td>`<colgroup>`</td><td> 表内の列のグループを定義します。</td></tr>
<tr class="hline"><td>`<col>`</td><td> 表内の列を定義して、全ての一般セルに共通の意味を定義するために使用します。この要素は通常、colgroup 要素内にみられます。</td></tr>
<tr class="hline"><td>`<thead>`</td><td> 表の列の見出しを定義する行のセットを定義します。</td></tr>
<tr class="hline"><td>`<tbody>`</td><td> 表本体要素 (tbody) は、表の一連の行 (tr 要素) を内包し、その部分が表 (table) の本体部分を構成することを表します。</td></tr>
<tr class="hline"><td>`<tr>`</td><td> 表内でセルの行を定義します。行のセルは td (データセル) および th (見出しセル) 要素を混在させることができます。</td></tr>
<tr class="hline"><td>`<th>`</td><td> 表のセルのグループ用のヘッダーであるセルを定義します。</td></tr>
<tr class="hline"><td>`<td>`</td><td> 表でデータを包含するセルを定義します。これは表モデルに関与します。</td></tr>
<tr class="hline"><td>`<tfoot>`</td><td> 表の一連の列を総括する行のセットを定義します。</td></tr>
</table>
</div>


### フォーム

利用者がデータを記入してウェブサイトやアプリケーションに送信することを可能にするフォームを作成するために組み合わせて用いる要素です。[^106]

[^106]: フォームに関する多くの情報が、 [HTMLフォームガイド](https://developer.mozilla.org/ja/docs/Learn/Forms)に掲載されています。

<div class="table table-nohline">
<table>
<tr class="hline"><th>要素</th><th> 説明</th></tr>
<tr class="hline"><td>`<fieldset>`</td><td> フォーム内のラベル (label) などのようにいくつかのコントロールをグループ化するために使用します。</td></tr>
<tr class="hline"><td>`<legend>`</td><td> fieldset の内容のキャプション(見出し)を表すために用います。</td></tr>
<tr class="hline"><td>`<form>`</td><td> サーバに情報を送信するための対話型コントロールを含む文書の区間を表します。</td></tr>
<tr class="hline"><td>`<button>`</td><td> クリックできるボタンを表し、フォームや、文書で単純なボタン機能が必要なあらゆる場所で使用することができます。</td></tr>
<tr class="hline"><td>`<input>`</td><td> 利用者からデータを受け取るための、フォーム用の対話的なコントロールを作成するために使用します。</td></tr>
<tr class="hline"><td>`<textarea>`</td><td> 複数行のプレーンテキスト編集コントロールを表し、問い合わせフォーム等、利用者が大量の自由記述テキストを入力できるようにするときに便利です。</td></tr>
<tr class="hline"><td>`<label>`</td><td> ユーザーインターフェイスの項目のキャプション(見出し)を表します。</td></tr>
<tr class="hline"><td>`<datalist>`</td><td> 他のコントロールで利用可能な値を表現する一連の option 要素を含みます。</td></tr>
<tr class="hline"><td>`<select>`</td><td> 選択式のメニューを提供するコントロールを表します。</td></tr>
<tr class="hline"><td>`<optgroup>`</td><td> select 要素内の、選択肢 (option) のグループを作成します。</td></tr>
<tr class="hline"><td>`<option>`</td><td> select 要素、optgroup 要素、datalist 要素内で項目を定義するために使われます。</td></tr>
<tr class="hline"><td>`<output>`</td><td> 出力要素(output)です。サイトやアプリが計算結果やユーザー操作の結果を挿入することができるコンテナ要素です。</td></tr>
<tr class="hline"><td>`<meter>`</td><td> 既知の範囲内のスカラ値、または小数値を表します。</td></tr>
<tr class="hline"><td>`<progress>`</td><td> タスクの進捗状況を表示します。プログレスバーとしてよく表示されます。</td></tr>
</table>
</div>


## CSS 簡易まとめ

CSSは、Cascading Style Sheets の略で、ウェブサイトにおける装飾などの為に用います。
[CSS: カスケーディングスタイルシート](https://developer.mozilla.org/ja/docs/Web/CSS)より、抄訳しています。引用元には詳細な解説や使用例等が掲載されています。是非ご活用下さい。


### 構文

カスケーディングスタイルシート(CSS)言語の基本的な狙いは、ブラウザがページの要素を、色、位置、装飾などの特定の特性をもって描けるようにすることです。
その為に、**プロパティ**(人がどのような特性か考えることのできる名前)と、
その特性をどのようにブラウザが操作しなければならないか表す**値**の組で表現します。これを**宣言**と呼びます。ページの要素を選択する条件である**セレクタ**により、それぞれの宣言を文書のそれぞれの部品に適用できるようにします。

<span class="caption">▼CSS構文</span>

```
  セレクタ {
    プロパティ1: 値;
    プロパティ2: 値;
    プロパティ3: 値;
  }
```

<span class="caption">▼CSSの例</span>

```
  header, p.intro {
    background-color: red;
    border-radius: 3px;
  }
```


### セレクタ


#### 基本セレクタ

<dl>
<dt>全称セレクタ</dt>
<dd>
  全ての要素を選択します。任意で、特定の名前空間に限定したり、全ての名前空間を対象にしたりすることができます。 <br>
  例: `*` は文書の全ての要素を選択します。
</dd>
<dt>要素型セレクタ</dt>
<dd>
  指定されたノード名を持つ全ての要素を選択します。 <br>
  例: `input` はあらゆる `<input>` 要素を選択します。
</dd>
<dt>クラスセレクタ</dt>
<dd>
  指定された `class` 属性を持つ全ての要素を選択します。 <br>
  例: `.index` は `"index"` クラスを持つあらゆる要素を選択します。
</dd>
<dt>ID セレクタ</dt>
<dd>
  `ID` 属性の値に基づいて要素を選択します。文書中に指定された `ID` を持つ要素は1つしかないはずです。 <br>
  例: `#toc` は `"toc"` という `ID` を持つ要素を選択します。
</dd>
<dt>属性セレクタ</dt>
<dd>
  指定された属性を持つ要素を全て選択します。 <br>
  構文: `[attr] [attr=value] [attr~=value] [attr|=value] [attr^=value] [attr$=value] [attr*=value]` <br>
  例: `[autoplay]` は `autoplay` 属性が（どんな値でも）設定されている全ての要素を選択します。
</dd>
</dl>


#### グループ化セレクタ

<dl>
<dt>セレクターリスト</dt>
<dd>
  `,(カンマ)` はグループ化の手段であり、一致する全てのノードを選択します。 <br>
  例: `div, span` は `<span>` と `<div>` の両要素に一致します。
</dd>
<dt>子孫結合子</dt>
<dd>
  `半角空白` 結合子は、第1の要素の子孫にあたるノードを選択します。 <br>
  例: `div span`は `<div>`要素内の`<span>`要素を全て選択します。
</dd>
<dt>子結合子</dt>
<dd>
  `>` 結合子は、第1の要素の直接の子に当たるノードを選択します。 <br>
  例: `ul > li` は `<ul>` 要素の内側に直接ネストされた `<li>` 要素を全て選択します。
</dd>
<dt>一般兄弟結合子</dt>
<dd>
  `~` 結合子は兄弟を選択します。つまり、第2の要素が第1の要素の後にあり(直後でなくても構わない)、両者が同じ親を持つ場合です。 <br>
  例: `p ~ span` は `<p>` 要素の後にある `<span>` 要素を全て選択します。
</dd>
<dt>隣接兄弟結合子</dt>
<dd>
</dd>
</dl>

`+` 結合子は隣接する兄弟を選択します。つまり、第2の要素が第1の要素の直後にあり、両者が同じ親を持つ場合です。 <br>
例: `h2 + p` は `<h2>` 要素の後にすぐに続く `<p>` 要素を全て選択します。


#### 擬似表記

<dl>
<dt>擬似クラス</dt>
<dd>
   `:` 表記により、文書ツリーに含まれない状態情報によって要素を選択できます。 <br>
   例: `a:visited` は利用者が訪問済みの `<a>` 要素を全て選択します。
</dd>
<dt>疑似要素</dt>
<dd>
  `::` 表記は、 HTML に含まれていない存在(エンティティ)を表現します。 <br>
  例: `p::first-line` は全ての `<p>` 要素の先頭行を選択します。
</dd>
</dl>


#### コメント

CSSでは、コメントは以下のように記述します。

<div class="table table-nohline">
<table>
<tr class="hline"><th>記述例</th><th> 説明</th></tr>
<tr class="hline"><td>`/* コメント */`</td><td> コメント</td></tr>
</table>
</div>


### 良く使うCSSプロパティのご案内

CSSには、100以上ものプロパティがあり、そしてそれぞれのプロパティが取り得る値も個々に決められています。[CSS リファレンス](https://developer.mozilla.org/ja/docs/Web/CSS/Reference)に全てが紹介されていますので、詳しくはそちらをご覧ください。ここでは、主なもののみを簡単にご紹介します。

<div class="table table-nohline">
<table>
<tr class="hline"><th>要素</th><th> 説明</th></tr>
<tr class="hline"><td>`background`</td><td> 色、画像、原点と寸法、反復方法など、背景に関する全てのスタイルプロパティを一括で設定します。</td></tr>
<tr class="hline"><td>`border`</td><td> 要素の境界(枠線)を設定します。これは border-width / border-style / border-color の値を設定します。</td></tr>
<tr class="hline"><td>`border-radius`</td><td> 要素の境界(枠線)の外側の角を丸めます。1つの半径を設定すると円の角になり、2つの半径を設定すると楕円の角になります。</td></tr>
<tr class="hline"><td>`box-shadow`</td><td> 要素のフレームの周囲にシャドウ(影)効果を追加します。</td></tr>
<tr class="hline"><td>`color`</td><td> 要素のテキストやテキスト装飾における前景色の色の値を設定します。</td></tr>
<tr class="hline"><td>`display`</td><td> 要素をブロック要素とインライン要素のどちらとして扱うかを設定します。およびその子要素のために使用されるレイアウト、例えば フローレイアウト、グリッド、フレックスなどを設定します。</td></tr>
<tr class="hline"><td>`filter`</td><td> ぼかしや色変化などのグラフィック効果を要素に適用します。フィルターは画像、背景、境界の描画を調整するためによく使われます。</td></tr>
<tr class="hline"><td>`font-family`</td><td> 選択した要素に対して、フォントファミリ名や総称ファミリ名の優先順位リストを指定します。明朝体、ゴシック体など、書体名を設定します。</td></tr>
<tr class="hline"><td>`font-size`</td><td> フォントの大きさを定義します。</td></tr>
<tr class="hline"><td>`font-style`</td><td> 通常体 (normal)、筆記体 (italic)、斜体 (oblique) のどれでスタイル付けするかを設定します。</td></tr>
<tr class="hline"><td>`font-weight`</td><td> フォントの太さ (あるいは重み) を指定します。</td></tr>
<tr class="hline"><td>`height`</td><td> 要素の高さを指定します。</td></tr>
<tr class="hline"><td>`line-height`</td><td> 行ボックスの高さを設定します。これは主にテキストの行間を設定するために使用します。</td></tr>
</table>
</div>
<div class="table table-nohline">
<table>
<tr class="hline"><th>要素</th><th> 説明</th></tr>
<tr class="hline"><td>`list-style-type`</td><td> リスト項目要素のマーカーを設定します (円、文字、独自のカウンタースタイルなど)。</td></tr>
<tr class="hline"><td>`margin`</td><td> 要素の全四辺のマージン領域を設定します。</td></tr>
<tr class="hline"><td>`max-height`</td><td> 要素の最大高を設定します。</td></tr>
<tr class="hline"><td>`max-width`</td><td> 要素の最大幅を設定します。</td></tr>
<tr class="hline"><td>`object-fit`</td><td> `<img>` や `<video>` などの中身を、コンテナにどのようにはめ込むかを設定します。</td></tr>
<tr class="hline"><td>`object-position`</td><td> `object-fit` プロパティと併用し、ボックス内における置換要素の配置を指定することが可能です。</td></tr>
<tr class="hline"><td>`padding`</td><td> 要素の全四辺のパディング領域を一度に設定します。</td></tr>
<tr class="hline"><td>`position`</td><td> 文書内で要素がどのように配置されるかを設定します。</td></tr>
<tr class="hline"><td>`text-align`</td><td> ブロック要素または表セルボックスの水平方向の配置を設定します。</td></tr>
<tr class="hline"><td>`text-decoration`</td><td> テキストの装飾的な線の表示を設定します。</td></tr>
<tr class="hline"><td>`text-shadow`</td><td> テキストに影を追加します。文字列及びその装飾に適用される影のカンマで区切られたリストを受け付けます。</td></tr>
<tr class="hline"><td>`vertical-align`</td><td> インラインボックス、インラインブロック、表セルボックスの垂直方向の配置を設定します。</td></tr>
<tr class="hline"><td>`width`</td><td> 要素の幅を設定します。</td></tr>
<tr class="hline"><td>`z-index`</td><td> 位置指定要素とその子孫要素、またはフレックスアイテムの z 順を定義します。より大きな z-index を持つ要素はより小さな要素の上に重なります。</td></tr>
</table>
</div>


#### グリッドレイアウト関係のプロパティ

<div class="table table-nohline">
<table>
<tr class="hline"><th>要素</th><th> 説明</th></tr>
<tr class="hline"><td>`grid-template`</td><td> 一括指定プロパティとして グリッド列、グリッド行、グリッド領域 を定義します。</td></tr>
<tr class="hline"><td>`grid-area`</td><td> 領域の名称を指定して、アイテムを配置します。</td></tr>
<tr class="hline"><td>`grid-template-columns`</td><td> 列の線名と列幅のサイズ変更機能を定義します。</td></tr>
<tr class="hline"><td>`grid-template-rows`</td><td> 行の線名と行高のサイズ変更機能を定義します。</td></tr>
<tr class="hline"><td>`grid-auto-flow`</td><td> 自動配置されたアイテムがどのようにグリッドに流れていくかを指定します。</td></tr>
<tr class="hline"><td>`grid-column`</td><td> グリッド列の中におけるグリッドアイテムの寸法と位置を指定し、線、区間、なし (自動) をグリッド配置に適用されることで、グリッド領域の列の開始と終了の端を指定します。</td></tr>
<tr class="hline"><td>`grid-row`</td><td> グリッド行の中におけるグリッドアイテムの寸法と位置を指定し、線、区間、なし (自動) をグリッド配置に適用されることで、グリッド領域の行の開始と終了の端を指定します。</td></tr>
<tr class="hline"><td>`gap`</td><td> 行や列の間のすき間 (溝) を定義します。これは `row-gap` および `column-gap` の一括指定です。</td></tr>
<tr class="hline"><td>`align-self`</td><td> グリッド領域内のアイテムの垂直方向の配置を指定します。</td></tr>
<tr class="hline"><td>`justify-self`</td><td> グリッド領域内のアイテムの水平方向の配置を指定します。</td></tr>
<tr class="hline"><td>`place-self`</td><td> グリッド領域内のアイテムの垂直方向、水平方向の配置を一括指定します。</td></tr>
</table>
</div>


## JavaScript 簡易まとめ

JavaScriptは、主にブラウザ上で動くプログラミング言語で、動的サイトの作成に用います。[^107]

[^107]: 出典：[JavaScript Primer 迷わないための入門書](https://jsprimer.net)など


### コメント

JavaScriptは、一行コメントと複数行コメントが用意されています。

<div class="table">
<table>
<tr class="hline"><th>コード例</th><th>説明</th></tr>
<tr class="hline"><td>`// xxx`</td><td>一行コメント</td></tr>
<tr class="hline"><td>`/* xxx */`</td><td>複数行コメント</td></tr>
</table>
</div>


### データ構造

> 変数とは、コンピュータプログラムのソースコードなどで、データを一時的に記憶しておくための領域に固有の名前を付けたもの。 [^108]


[^108]: 出典：IT用語辞典

JavaScriptでは、定数宣言用の「`const`」と、変数宣言用の「`let`」が用意されています。

<div class="table">
<table>
<tr class="hline"><th>コード例</th><th>説明</th></tr>
<tr class="hline"><td>`const x`</td><td>**変数宣言**。`x`に値の再代入はできない</td></tr>
<tr class="hline"><td>`let x`</td><td>**変数宣言**。`const`と似ているが、`x`に値を再代入できる</td></tr>
<tr class="hline"><td>`var x`</td><td>**変数宣言**。古い変数宣言方法(今は使わない)</td></tr>
</table>
</div>


### リテラル

> リテラル(literal)とは、直値、直定数とも呼ばれ、コンピュータプログラムのソースコードなどの中に、特定のデータ型の値を直に記載したものである。また、そのように値をコードに書き入れるために定められている書式のことをいう。 [^109]


[^109]: 出典: IT用語辞典

<div class="table">
<table>
<tr class="hline"><th>コード例</th><th>説明</th></tr>
<tr class="hline"><td>`true` または `false`</td><td>**真偽値**</td></tr>
<tr class="hline"><td>`123`</td><td>**10進数**の整数リテラル</td></tr>
<tr class="hline"><td>`123n`</td><td>巨大な整数を表すBigIntリテラル</td></tr>
<tr class="hline"><td>`1_2541_0000`</td><td>日本の人口など、大きな数は `_` で区切ると読みやすくなる</td></tr>
<tr class="hline"><td>`0b10`</td><td>**2進数**の整数リテラル</td></tr>
<tr class="hline"><td>`0x30A2`</td><td>**16進数**の整数リテラル</td></tr>
<tr class="hline"><td>`[x, y]`</td><td>`x`と`y`を初期値にもつ**配列オブジェクト**を作成</td></tr>
<tr class="hline"><td>`{ k: v }`</td><td>プロパティ名が`k`、 <br>プロパティの値が`v`の**オブジェクト(≒連想配列)**を作成</td></tr>
</table>
</div>


### 文字列

> 文字列とは、文字を並べたもの。コンピュータ上では、数値など他の形式のデータと区別して、文字の並びを表すデータを文字列という。 [^110]


[^110]: 出典：IT用語辞典

<div class="table">
<table>
<tr class="hline"><th>コード例</th><th>説明</th></tr>
<tr class="hline"><td>`"xxx"`</td><td>ダブルクォートの**文字列リテラル**。</td></tr>
<tr class="hline"><td>`'xxx'`</td><td>シングルクォートの**文字列リテラル**。</td></tr>
<tr class="hline"><td>``xxx``</td><td>テンプレート文字列リテラル。改行を含んだ入力が可能</td></tr>
<tr class="hline"><td>``${x}``</td><td>テンプレート文字列リテラル中の変数`x`の値を展開する</td></tr>
</table>
</div>


### 制御構造

プログラムの流れを制御するための構文です。
繰り返しのための「 `for文` 」、条件分岐のための「 `if文` 」などが用意されています。

<div class="table">
<table>
<tr class="hline"><th>例</th><th>説明</th></tr>
<tr class="hline"><td>`while(x){}`</td><td>**whileループ**。 <br>`x`が`true`なら反復処理を行う。 <br>繰返回数が不明な際に用いると効果的</td></tr>
<tr class="hline"><td>`for(let x=0;x < y ;x++){}`</td><td>**forループ**。 <br>`x < y`が`true`なら反復処理を行う。 <br>繰返回数が分かる時に使うと効果的</td></tr>
<tr class="hline"><td>`for(const p in o){}`</td><td>**for...inループ**。 <br>オブジェクト（`o`）のプロパティ(`p`) <br>に対して反復処理を行う</td></tr>
<tr class="hline"><td>`for(const x of iter){}`</td><td>**for...ofループ**。 <br>イテレータ(`iter`)の反復処理を行う</td></tr>
<tr class="hline"><td>`if(x){/*A*/}else{/*B*/}`</td><td>**条件式**。 <br>`x`が`true`ならAの処理を、 <br>それ以外ならBの処理を行う</td></tr>
<tr class="hline"><td>`switch(x){case "A":{/*A*/} "B":{/*B*/}}`</td><td>**switch文**。 <br>`x`が`"A"`ならAの処理を、 <br>"B"ならBの処理を行う</td></tr>
<tr class="hline"><td>`x ? A: B`</td><td>**条件 （三項） 演算子**。 <br>`x`が`true`なら`A`の処理を、 <br>それ以外なら`B`の処理を行う</td></tr>
<tr class="hline"><td>`break`</td><td>**break文**。 <br>現在の反復処理を終了しループから抜け出す。</td></tr>
<tr class="hline"><td>`continue`</td><td>**continue文**。 <br>現在の反復処理を終了し次のループに行く。</td></tr>
<tr class="hline"><td>`try{}catch(e){}finally{}`</td><td>`try...catch`構文</td></tr>
<tr class="hline"><td>`throw new Error("xxx")`</td><td>`throw`文</td></tr>
</table>
</div>


### 演算子

> 演算子とは、数学やプログラミングなどで式を記述する際に用いる、演算内容を表す記号などのこと。様々な演算子が定義されており、これを組み合わせて式や命令文を構成する。 [^111]


[^111]: 出典：IT用語辞典

以下の表は優先順位の最も高いもの (21) から最も低いもの (1) の順に並べられている。[^112]

[^112]: 出典: [演算子の優先順位](https://developer.mozilla.org/ja/docs/Web/JavaScript/Reference/Operators/Operator_Precedence)

![](./images/93-cheats/js_operator.png)


### データアクセス

プログラミング言語 Pascal の開発者 ニクラウス・ヴィルト氏による、
「プログラミング」＝「データ構造」＋「アルゴリズム」 は、広く知られています。

配列とオブジェクト(≒連想配列)という主要なデータ構造にアクセスするために、次の構文が用意されています。

<div class="table">
<table>
<tr class="hline"><th>コード例</th><th>説明</th></tr>
<tr class="hline"><td>`array[0]`</td><td>配列への**インデックスアクセス**</td></tr>
<tr class="hline"><td>`obj["x"]`</td><td>オブジェクトへの**プロパティアクセス**（ブラケット記法）</td></tr>
<tr class="hline"><td>`obj.x`</td><td>オブジェクトへの**プロパティアクセス**（ドット記法）</td></tr>
</table>
</div>


### 関数宣言

> 関数とは、コンピュータプログラム上で定義されるサブルーチンの一種で、数学の関数のように与えられた値（引数）を元に何らかの計算や処理を行い、結果を呼び出し元に返すもののこと。 [^113]


[^113]: 出典：IT用語辞典

<div class="table">
<table>
<tr class="hline"><th>サンプル</th><th>説明</th></tr>
<tr class="hline"><td>`function f(){}`</td><td>**関数**宣言</td></tr>
<tr class="hline"><td>`const f = function(){};`</td><td>**関数**式</td></tr>
<tr class="hline"><td>`const f = () => {};`</td><td>**Arrow Function**の宣言</td></tr>
<tr class="hline"><td>`function f(x, y){}`</td><td>関数における仮引数の宣言</td></tr>
<tr class="hline"><td>`function f(x = 1, y = 2){}`</td><td>**デフォルト引数**、 <br>引数が渡されていない場合の初期値を指定する。</td></tr>
<tr class="hline"><td>`clasX{}`</td><td>**クラス**宣言</td></tr>
<tr class="hline"><td>`const X = clasX{};`</td><td>**クラス**式</td></tr>
</table>
</div>


### モジュール

大きなプログラムを作る際、小さな部品（モジュール）を組み合わせて作ると、管理しやすく、部品の再利用もできるので便利です。
JavaScriptにも、特定のファイルで定義した関数を、他のファイルでも使えるようにする仕組みが用意されています。

<div class="table">
<table>
<tr class="hline"><th>コード</th><th>説明</th></tr>
<tr class="hline"><td>`import x from "./x.js"`</td><td>**デフォルトインポート**</td></tr>
<tr class="hline"><td>`import { x } from "./x.js"`</td><td>**名前付きインポート**</td></tr>
<tr class="hline"><td>`export default x`</td><td>**デフォルトエクスポート**</td></tr>
<tr class="hline"><td>`export { x }`</td><td>**名前付きエクスポート**</td></tr>
</table>
</div>


### その他

<div class="table">
<table>
<tr class="hline"><th>コード</th><th>説明</th></tr>
<tr class="hline"><td>`x;`</td><td>文</td></tr>
<tr class="hline"><td>`{ }`</td><td>ブロック文</td></tr>
</table>
</div>


::: {.column}
金の延棒クイズ 【解答】
最後までお読みくださり、ありがとうございます。金の延棒クイズの解答です。


![](gold_table2.webp)

２回鋏を入れて、金の延棒を１と２と４の大きさに分割します。

一日目のお支払いには、１の延棒を渡します。

二日目のお支払いには、２の延棒を渡して、先に渡した１の延棒は返してもらいます。

三日目のお支払いには、１の延棒も渡します。

四日目のお支払いには、大きな４の延棒を渡し、２と１の延棒は返してもらいます。

五日目のお支払いには、１の延棒も渡します。

六日目のお支払いには、２の延棒を渡して、先に渡した１の延棒は返してもらいます。

七日目のお支払いには、全ての延棒を渡します。


延棒の有無を `0` と `1` で表すと二進数と対応しています。

意外なところに潜む二進数。探してみてくださいね。
:::



