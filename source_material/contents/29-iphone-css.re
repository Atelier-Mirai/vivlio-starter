= iPhoneの為のCSS

//abstract{
  ウェブサイトの意匠・装飾を整えるための@<code>{CSS(Cascading Style Sheet)}について、基礎を学びました。

  この章では iPhoneで 綺麗に見えるよう、装飾して行きます。
//}

== CSSを分割して管理する

「さくら」は、さくらを詠んだ俳句を紹介するトップページのみの簡潔なサイトですが、文字の大きさや色、配置など、美しく彩る為に様々な装飾を行っていきます。

=== @<code>{import文} - 分割したCSSを読み込む
CSSがとても長くなりますので、一つのCSSファイルですと、管理がとても大変になります。そこで、部品ごとのCSSファイルに分割し、それらを大本となる一つのCSSファイルに取り込む方針で作成して行きます。

@<file>{stylesheets} というディレクトリ(フォルダ)を作成し、その下に、 @<file>{master.css} というファイルを作成してください。作成できましたら、@<file>{master.css} を次のように書いて行きましょう。

//list[][master.css][1]{
/*=====================================================================
  部品別にスタイルシートを記述しておき、
  個々のスタイルシートを読み込むようにすると、
  管理がしやすくお勧めです。
=====================================================================*/

/* 日本の伝統色 和の色十二食
---------------------------------------------------------------------*/
@import "_colors.css";

/* リセットCSS
---------------------------------------------------------------------*/
@import "_reset.css";

/* 全体の配置
---------------------------------------------------------------------*/
@import "_body.css";

/* ヘッダー
---------------------------------------------------------------------*/
@import "_header.css";

/* ヒーローイメージ
---------------------------------------------------------------------*/
@import "_hero.css";

/* キャッチフレーズ
---------------------------------------------------------------------*/
@import "_catch.css";

/* ソースコードへのリンク
---------------------------------------------------------------------*/
@import "_code.css";

/* ボタンの装飾
---------------------------------------------------------------------*/
@import "_button.css";

/* 俳句の紹介
---------------------------------------------------------------------*/
@import "_haiku.css";

/* 写真の枠
---------------------------------------------------------------------*/
@import "_frame.css";

/* フッター
---------------------------------------------------------------------*/
@import "_footer.css";
//}

全部で49行ととても沢山書かれているように見えますが、そのほとんどは「コメント」です。

@<code>{@import}は、他のスタイルシートに書かれた装飾規則を取り込む(@<ruby>{import,インポート})する時に使います。

@<code>{@import "_colors.css";} と書くことで、他のCSSファイル @<file>{_colors.css} に書かれた内容を、@<file>{master.css} に取り込むことが出来ます。 @<fn>{chuui}

//footnote[chuui][直接 @<file>{master.css} に記述するのと同じ効果が得られます。@<file>{master.css} と @<file>{_color.css} は同じディレクトリ(フォルダ) において下さい。]

部品ごとにそれぞれのCSSファイルを作り、その内容を全て @<file>{master.css} 取り込んでいるのです。

このように、色に関するCSSファイル、ボタンの装飾に関するCSSファイルなど、それぞれのファイルにしておくことで、修正する際には、それぞれのCSSファイルのみを修正すれば良いので、全体の見通しも良くなります。

さらに、他のウェブサイトを作成する際にも、色やボタンに関する装飾など、使い廻わすことができるので、とても便利です。

//note[_ (アンダースコア)について]{
ファイル名の先頭に、@<file>{_colors.css, _reset.css} など、@<file>{_(アンダースコア)} が付けられていることに気づいた方もいるかもしれません。 CSSの文法上は @<file>{_(アンダースコア)} を付ける必要はありませんが、自分なりのルールとして、取り込まれることになる部分ファイルには、@<file>{_(アンダースコア)}を付けることとすると、区別しやすく良いでしょう。
//}

== 日本の伝統色 和の色十二色

先にCSSカスタムプロパティを使って日本の伝統色を使う方法をご紹介いたしました。色数として838色がございますが、その中から12色の色鉛筆にちなんで、選んでみました。

//list[][_colors.css][1]{
/*=====================================================================
  色の指定  CSSカスタムプロパティを定義
  color: var(--kyohiiro); などのように用いることができる
=====================================================================*/

:root {
  --kyohiiro:          #ff251e; /* 京緋色(きょうひいろ) */
  --shinonomeiro:      #f19072; /* 東雲色(しののめいろ) */
  --nanohanairo:       #ffec47; /* 菜の花色(なのはないろ) */
  --sanaeiro:          #67a70c; /* 早苗色(さなえいろ) */
  --amairo:            #2ca9e1; /* 天色(あまいろ) */
  --utsushiiro:        #3d6eda; /* 移色(うつしいろ) */
  --botaniro:          #e7609e; /* 牡丹色(ぼたんいろ) */
  --ayameiro:          #674196; /* 菖蒲色(あやめいろ) */
  --sakurairo:         #fef4f4; /* 桜色(さくらいろ) */
  --momijiiro:         #a61017; /* 紅葉色(もみじいろ) */
  --nibiiro:           #9ea1a3; /* 鈍色(にびいろ) */
  --kurohairo:         #0d0d0d; /* 黒羽色(くろはいろ) */

  --harukazeiro:       transparent; /* 春風色(はるかぜいろ) */
}
//}

== リセットCSS

ブラウザには「ユーザーエージェントスタイルシート」というスタイルシートが標準で適用されています。そのため自分では全くCSSを記述しなくても、見やすいようにブラウザが余白の調整などある程度の飾り付けを行っています(CSSの練習を行った際、見出しの@<code>{<h1>}が大きく表示されていたのも、ユーザーエージェントスタイルシートの働きです)。

せっかく、ブラウザがスタイルシートを適用してくれているのですが、自分でデザインを創り上げる際には少しおせっかいに感じることもあります。不要・不都合なスタイルを上書きし、初期化するためのCSSを「リセットCSS」と言います。

//list[][_reset.css][1]{
/*=====================================================================
  CSSリセット
  ブラウザが標準で準備しているスタイルシートを、
  自分でデザインしやすいよう、リセットする
=====================================================================*/

/* 全ての要素について */
* {
  margin: 0; /* 間隔を0にする */
}

/* 全てのimg要素について */
img {
  width: 100%;            /* 画像の幅を全部表示 */
  height: auto;           /* 画像の高さは横幅に合わせて適宜表示 */
  vertical-align: bottom; /* 画像を文字の下側に揃えて表示 */
}
//}

適用結果は次頁のようになります。各要素間の隙間が消え、見切れていた写真も画面幅一杯に表示されるようになっています@<small>{(紙幅の都合上、さくらを詠んだ俳句については最初の一句のみにしています)}。

//image[reset_umu][リセットCSS 適用前(左) 適用後(右)][width=85%,pos=H]

ここでは、自身で作成いたしましたが、多くの先人たちの手により優れたリセットCSSが作成されておりますので、それを使うのも良いでしょう。 @<fn>{resetcss}

//footnote[resetcss][Web制作に関する最新の情報を紹介している @<href>{https://coliss.com/, coliss} には、有益な記事が豊富にございます。@<href>{https://coliss.com/articles/build-websites/operation/css/css-reset-for-modern-browser.html, 現在の環境に適したリセットCSSのまとめ} では多くのリセットCSSが紹介されています。]


== CSSグリッドレイアウトで 全体の配置を大まかに設定する

それでは、文字や写真など、全体の配置を大まかに整えていきましょう。配置を指定するためには、様々な方法がありますが、ここではCSSグリッドレイアウトを用いた手法をご紹介いたします。CSSグリッドレイアウトとは、行と列それぞれに格子状の線を配置し、その線に沿って文字や写真などの各要素を配置できる手法です。

CSSグリットに関するご紹介を付録にご用意しておりますので、またご覧になってください。

HTML文書では、@<code>{<body>}要素がすべての要素の親ですので、@<code>{<body>}要素に、CSSグリッドレイアウトを適用し、行と列それぞれに格子状の線を設定いたしましょう。

@<file>{stylesheets}ディレクトリ(フォルダ)内に@<file>{_body.css}を新規作成し、次のように書きましょう。

//list[][_body.css][1]{
/*=====================================================================
  body に関する 配置や装飾等の指定
=====================================================================*/

/* body 要素についての指定 */
body {
  /* grid(枠線)を使って配置できるようにします */
  display: grid;

  /* columnは 列の意味で 左右に余白を取り 中央は左と右の二列にします */
  grid-template-columns: 20px 1fr 1fr 20px;

  /* row は 行 の意味で 4行 作成します */
  grid-template-rows:
              /* 各行を指定しやすいよう 行に名前を付けます */
              /* catch code と 同じ行に別名を付けることもできます */
              /* また それぞれの行の高さも指定しています */
              [header]      100px
              [catch code]  547px
              [haiku]       auto
              [footer]      100px;

  /* 各行の間隔を取ります */
  row-gap: 20px;
}

/* body直下にあるそれぞれの部品の配置 */
body > * {
  /* 全ての要素は真ん中の列に配置します */
  /* (左から二本目の線を示しますから、右から二本目の線の間に配置します) */
  grid-column: 2 / -2;
}
//}

開発者ツールを用いて、グリッド線の様子を表示させた結果は、次のようになります。

//sideimage[body_grid][60mm][sep=5mm,side=R]{
列に関しては、 @<code>{grid-template-columns: 20px 1fr 1fr 20px;} と書くことで、左右の余白を @<code>{20px} 取り、中央は右側と左側の二列の構成としています。

//blankline
行に関しては、4行設定し、それぞれの行の高さを 上から順に @<code>{100px, 547px, auto, 100px} としています。
行の高さに @<code>{auto} を設定すると、その行に配置される要素に応じて、自動的に高さた調整されます。

//list[][]{
grid-template-rows:
                100px
                547px
                auto
                100px;
//}


そして、
一番上の線に @<code>{header} と、
二番目の線に @<code>{catch code} と、
三番目の線に @<code>{haiku} と、
四番目の線に @<code>{footer} と、それぞれの行に名前をつけます。

二番目の線は、キャッチフレーズを配置するための線なので @<code>{catch} と名前を付け、またソースコードのダウンロードボタンを配置する線でもあるので、@<code>{code} と同じ線に二つの名前を付けています。

//list[][]{
grid-template-rows:
                [header]     100px
                [catch code] 547px
                [haiku]      auto
                [footer]     100px;
//}

そして、次のコードにより、各行の間隔を @<code>{20px} 開けています。

//list[][]{
row-gap: 20px;
//}

最後に、次のコードで、@<code>{<body>}直下にある全ての要素を
左から二本目の線から、右から二本目の線の間に配置しています。
(つまり左右の余白を除いた中央の二列に配置しています。)
//list[][]{
body > * {
  grid-column: 2 / -2;
}
//}

//}

=== ヒーローイメージの高さを考える

//sideimage[hero_height][60mm][sep=5mm,side=R]{
最も良く売れているiPhoneは、iPhone SE 第三世代です。画面サイズは4.7インチ、画素数は 幅375px、高さ667px です。

//blankline
ヒーローイメージは、今から作るウェブサイトを象徴する大事な写真ですので、サイト名の下は全て「咲き誇る桜の写真」が表示されることとしたい思います。

//blankline
画面全体の高さが667pxなので、サイト名を表示するヘッダーの高さ100pxと、そして行間が20pxあるので、残り547ピクセルをヒーローイメージの高さに設定しました。そして閲覧される方のiPhoneが全てこの大きさだと良いのですが、より大きなiPhoneをお持ちの方には、この桜の写真の下に、「さくらを詠んだ俳句」など、他の文章が表示されることとなります。

//blankline
できれば、閲覧される方のiPhoneのサイズに合わせて、「ヘッダーの高さ100pxと行間20pxを引いた残り全部がヒーローイメージの高さ」になるようにしたいと思います。

先ほど書いた @<file>{_body.css} を次のように更新しましょう。
//}

//list[][_body.css (変更前)]{
grid-template-rows:
                [header]     100px
                [catch code] 547px
                [haiku]      auto
                [footer]     100px;
//}

//list[][_body.css (変更後)]{
grid-template-rows:
                [header]     100px
                [catch code] calc(100vh - 100px - 20px)
                [haiku]      auto
                [footer]     100px;
//}

@<code>{547px} から @<code>{calc(100vh - 100px - 20px)} に更新しました。
@<code>{1vh} は、画面の高さの @<code>{1%} を表す単位ですので、@<code>{100vh} で、画面の高さ全部になります。

@<code>{calc()} は、@<code>{calculate(計算する)} に由来する関数で、単位の異なる数値同士の演算結果を得ることが出来ます。

ですので、@<code>{calc(100vh - 100px - 20px)} と書くことで、「ヘッダーの高さ100pxと行間20pxを引いた残り全部をヒーローイメージの高さ」に設定できます。

== ヘッダーの配置や装飾を行う

それでは、ヘッダーの配置や装飾を行っていきましょう。現在、サイト名は左上に小さく表示されております。せっかくのサイト名ですから、中央に大きく表示することにしましょう。

@<file>{stylesheets}ディレクトリ(フォルダ)内に@<file>{_header.css}を新規作成し、次のようにCSSを書いて行きましょう。

//list[][_header.css]{
/*=====================================================================
  ヘッダー に関する 配置や装飾等の指定
=====================================================================*/

/* header 要素に対する指定を行う */
header  {
  grid-row: header;     /* header 行の下に配置します */
  justify-self: center; /* 水平方向に中央揃えします */
  align-self: center;   /* 垂直方向に中央揃えします */

  background-color: var(--utsushiiro); /* 背景色は移色 */
  color: var(--sakurairo);  /* 文字の色は桜色 */
  font-size: 48px;          /* 文字の大きさの指定 */
  font-weight: bold;        /* 文字の太さを、太字にします */
  letter-spacing: 10px;     /* 少し広めに文字の間隔を空けます */
}
//}

//sideimage[header_simple][60mm][sep=5mm,side=R]{
@<code>{_body.css} で命名した一番上の線 @<code>{header} の下に、 @<code>{<header>} タグを配置することとします。水平方向、垂直方向に中央揃えを行い、背景色や文字の色、文字の大きさや太さ、文字の間隔の設定を行っています。
//}

美しい青空をイメージした背景色に、桜色の文字で「さくら」と書かれた、簡潔なサイト名となっていますが、いかがでしょうか。もしかすると、少し物足りないと感じる方もいらっしゃるかもしれません。そこで、もう一手間加えて、青空に架かる虹をイメージしたサイト名にしてみましょう。

@<href>{https://1-notes.com/css-text-design/,CSSでテキストを彩る装飾サンプル集} というサイトがございます。いろいろな装飾例が掲載されておりますが、その中に虹色に配色する例もございましたので、ご紹介いたします。

//list[][_header.css]{
header {
  /* (略) */

  /* 文字色を透明にします */
  color: transparent;
  /* 反復線形グラデーションによる背景画像を生成します */
  background: repeating-linear-gradient(45deg,
    #e60012 0.1em 0.2em,
    #f39800 0.2em 0.3em,
    #fff100 0.3em 0.4em,
    #009944 0.4em 0.5em,
    #0068B7 0.5em 0.6em,
    #1d2088 0.7em 0.8em,
    #cfa7cd 0.8em 0.9em);
  /* 背景を前景のテキストの中に (切り取って) 表示します */
  -webkit-background-clip: text;
  background-clip: text;
}
//}

//sideimage[header_rainbow][60mm][sep=5mm,side=R]{
作成例は右のようになります。

一旦、文字色を透明にしておきます。次に虹色の背景画像を生成します。最後に生成した背景画像を文字の形に切り取って完成です。
//}

//note[ベンダー接頭辞について]{
ブラウザの提供元(ベンダー)が、試験的、非標準的なCSSプロパティを先行・独自実装している際に付けられることがあります。

先に登場したこの二行は基本的に同じコードですが、上の一行には @<code>{-webkit-} が付いています。これがベンダー接頭辞（プレフィックス）です。

//list[][]{
-webkit-background-clip: text;
background-clip: text;
//}

今日では、ほとんどのブラウザが標準に準拠していますので、ベンダー接頭辞をつける機会も少なくなりましたが、稀に必要となることがあります。
//}


== ヒーローイメージの配置や装飾を行う

続いて、ヒーローイメージの配置や装飾を行っていきます。現在は桜の写真が表示されておりますが、画面の上半分に表示されており、下半分は空白となっております。せっかくのヒーローイメージですから、下半分にも広げてもっと大きく表示するようにしましょう。

@<file>{stylesheets}ディレクトリ(フォルダ)内に@<file>{_hero.css}を新規作成し、次のようにCSSを書いて行きましょう。

//list[][_hero.css][1]{
/*=====================================================================
  ヒーローイメージ に関する 配置や装飾等の指定
=====================================================================*/

/* hero クラスについての指定 */
.hero {
  grid-column: 1 / -1; /* 左右の余白も使って配置します */
  grid-row: catch;     /* catch 行に配置します */
}

/* hero クラス内にあるimg要素についての指定 */
.hero img {
  /* 写真の高さを指定します */
  /* 100vh は 画面の高さの 100% を表します */
  /* calc(100vh - 100px) で 画面高から100pxを引いた値が得られます */
  height: calc(100vh - 100px);
  object-fit: cover;   /* 写真の中央部分を画面幅に応じて表示します */
}
//}

//sideimage[hero][50mm][sep=5mm,side=R]{
適用結果は右のようになります。桜も大きく表示されるようになりました。

//blankline
コードの解説を行っていきます。

まず @<file>{index.html} で 多くの @<code>{<figure>} 要素から、ヒーローイメージを区別する為に、 @<code>{<figure class="hero"} とクラス名を付けて書きました。そこでCSSでもヒーロークラスを選択し各種の配置や装飾を適用する為に、 @<code>{.hero} とセレクタを書いています。

//blankline
そして、せっかくのヒーローイメージですので、左右の余白も使って表示できるよう、列の配置先を @<code>{grid-column: 1 / -1; } と書いています。グリッドの左から数えて一本目の線から、右側から数えて一本目の線までという意味で、つまり横幅全部を使って写真を配置する指定になります。

行の配置先ですが、 @<code>{grid-row: catch;} と記述しています。上から二番目の線の名前を @<code>{catch} と命名しましたので、このように書くことが出来ます。
//}

//blankline


//sideimage[hero_margin][50mm][sep=5mm,side=R]{
次に桜の写真についての指定です。
写真の高さですが、 @<code>{567px;}と指定すると、より画面サイズの大きいiPhoneで見たときに不自然になりますので、@<code>{_body.css} で述べた時と同様、 @<code>{calc}関数を使って高さを指定しています。

写真の高さを指定したのみでは、桜の木が縦に引き延ばされるため、@<code>{object-fit: cover;} により、写真の中央部分を切り取って拡大表示するようにしています。

//blankline
最後に、ヘッダーの下が @<code>{20px} 開いているのが気になります。@<code>{_body.css} で 行間を @<code>{20px} と指定したためですが、これを是正するために、写真全体を上に @<code>{20px} ずらすことにします。そのために @<code>{margin-top: -20px;} を追加します。

//list[][_hero.css]{
.hero {
  grid-column: 1 / -1;
  grid-row: catch;
  margin-top: -20px; /* 上に詰めて配置します */
}
//}

出来上がりは右のようになります。

余分な隙間もなくなり、綺麗になりました。
//}
---
== キャッチフレーズの配置や装飾を行う

//sideimage[catch0][50mm][sep=5mm,side=R]{
美しく桜の写真を表示することができましたので、続いて、キャッチフレーズの配置や装飾を行っていきます。

現在は、俳聖 松尾芭蕉の名句「扇にて酒くむかげやちる櫻」は、右のように、桜の写真下に表示されております。配置を調整して、桜の写真に重ねて表示させていきましょう。

@<file>{stylesheets}ディレクトリ(フォルダ)内に@<file>{_catch.css}を新規作成し、次のようにCSSを書いて行きましょう。

//}


//list[][_catch.css][1]{
/*=====================================================================
  キャッチフレーズ に関する 配置や装飾等の指定
=====================================================================*/

/* catchクラス(キャッチフレーズ)に対する指定 */
.catch {
  grid-row: catch;        /* catch 行の下に配置します */
  grid-column: 3;         /* 左から三本目の線に配置します */
  justify-self: center;   /* 水平方向に中央揃えします */
  align-self: center;     /* 垂直方向に中央揃えします */
}
}
//}

//sideimage[catch1][50mm][sep=5mm,side=R]{
適用結果は、右のようになります@<small>{(グリッドの線を確認しやすいよう、背景の桜の色を薄くしています)}。

//blankline
名句全体を @<code>{catch} 行の下、左から三番目の線の横に配置します。そして、水平方向と垂直方向に中央揃えしています。

//blankline
桜の写真に重ねて名句を配置することができました。
//}
---
//sideimage[catch4][50mm][sep=5mm,side=R]{
続いて、文字の色や大きさを調整して行きましょう。

//list[][_catch.css][12]{
.catch {
  (略)

  /* 文字の色は桜色にします */
  color: var(--sakurairo);
  /* 文字の大きさを指定します */
  font-size: 36px;
  /* 文字の太さは、普通にします */
  font-weight: normal;
  /* 行の高さを文字サイズの1.2倍にします */
  line-height: 1.2;
  /* 文字の右下と左上に影を付けます */
  text-shadow: 2px 2px 5px var(--kurohairo),
              -2px -2px 5px var(--nibiiro);

  /* 俳句なので 縦書きにします */
  writing-mode: vertical-rl;
}
//}

俳句らしく、縦に表示することができました。また文字色を桜色にしましたが、影をつけることに、背景の桜と区別することが出来、はっきりと見えるようになっています。
//}

//vspace[latex][7mm]

文字に影を付ける @<code>{text-shadow} については、MDNの@<href>{https://developer.mozilla.org/ja/docs/Web/CSS/text-shadow,text-shadow}に説明があります。@<br>{}また ウェブサイトを縦書きにする為の記事が、@<href>{https://tategaki.github.io/, 縦書きWeb普及委員会} や、@<href>{https://www.webcreatorbox.com/tech/writing-mode,日本らしさを表現！CSSで文字の縦書きに挑戦！} に詳しい説明がございますので、ぜひご一読ください。

//blankline
続いて、芭蕉翁について知りたい方のためにウィキペディアへのリンクを設定しておりますが、通常の青いリンク色になっています。次のCSSで装飾を施していきましょう。

//list[][_catch.css][24]{
/* catchクラス内の a要素に対する指定 */
.catch a {
  color: inherit;        /* 文字の色は、.catch の色を継承します */
  text-decoration: none; /* 文字の装飾はなし(下線を付けない) */
  font-size: 32px;       /* 文字の大きさを指定します */
  margin-top: 1em;       /* 少し上に間隔を取ります */
}

/* catchクラス内の a要素にマウスを重ねたときの指定 */
.catch a:hover {
  /* 文字の装飾として、下線を付けます */
  -webkit-text-decoration-line: underline;
  text-decoration: underline;
  /* 文字に天色のぼかしをつけます */
  text-shadow: 0 5px 15px var(--amairo);
}
//}

//sideimage[catch5][50mm][sep=5mm,side=R,border=on]{
マウスを重ねていない場合には、名句と同様に桜色となり、
マウスを重ねた際には、傍線とともに文字に@<ruby>{天色,あまいろ}のぼかしがつくようになりました。
//}

== ウェブフォントを活用する

//sideimage[catch6][50mm][sep=5mm,side=R,border=on]{
縦書きに芭蕉翁の名句も載せられるになり、ぐっと雰囲気が出てきました。しかし、ゴシック体で表示されており、少し味気なく感じるのも事実です。

また、今まで開発環境としてFirefoxで見ておりましたが、MacやiPhoneの標準ブラウザである Safari で見てみると右のように、明朝体で表示されます。ゴシック体と明朝体ではだいぶ雰囲気も変わります。サイト全体の印象を整えるためにも同じ書体を使いたいものです。

有志の方々が様々な書体を制作されており、様々な形で配布されております。ここではその中から @<ruby>{Google Fonts,グーグルフォント} を使ってみましょう。 @<fn>{fonts}

//footnote[fonts][@<href>{https://coliss.com/articles/freebies/japanese-free-fonts.html, 日本語のフリーフォント670種類のまとめ} に豊富に紹介されておりますので、ご覧ください。]
//}

=== グーグルフォント を使う
グーグルフォント の URL は、@<href>{https://fonts.google.com/} です。
様々な書体が表示されておりますが、まず中央の Sentence 欄に、芭蕉翁の名句「扇にて酒くむかげやちる櫻」を入力します。次に Language 欄で「日本語」を選択します。

//image[googlefont0][][width=83%]

日本語の様々な書体が表示されます。また右下の「早蕨明朝体」では「櫻」の文字が表示できないことも確認できます。
//image[googlefont1][][width=83%]
---
一番下にある 「Yuji Boku」という書体を使うことにしましょう。 @<fn>{yuji}

//footnote[yuji][書家の片岡佑之の文字を元に制作された書体で、@<href>{https://github.com/Kinutafontfactory/Yuji/blob/master/README-JP.md, 佑字} や @<href>{https://www.moji-sekkei.jp/font/yuji/,砧書体制作所} に詳しく紹介されています。]

左側の書体（赤枠）をクリックします。
//image[googlefont2][][width=83%,border=on]

「扇にて酒くむかげやちる櫻」の右側にある「Select Regular 400」をクリックします。
//image[googlefont3][][width=83%,border=on]

//vspace[latex][7mm]

//sideimage[googlefont5][45mm][sep=5mm,side=R]{
この書体を用いる為に必要なコードが、画面右端より出現します。

//quote{
//noindent
@<code>{Use on the web}@<br>{}
@<code>{To embed a font, copy the code into the <head> of your html} @<br>{}
@<br>{}
@<code>{ウェブでの使用}@<br>{}
@<code>{フォントを埋め込むには、htmlの<head>にコードをコピーします。}
//}

と書かれていますので、@<code>{<link rel="preconnect" ...>} から始まるコードをコピーして、 @<file>{index.html} の @<code>{<head>} に貼り付けます@<small>{(コードの右下の四角のボタンを押すとコピーできます)}。
//}

//list[][index.html][lineno=1-25&129-130]{
#@# //list[][index.html][1]{
<!DOCTYPE html>
<html lang="ja">
  <!-- サイトに関する設定事項を記述します -->
  <head>
    <!-- 文字コードの指定 -->
    <meta charset="utf-8">

    <!-- ページのタイトル -->
    <title>桜吹雪</title>

    <!-- ビューポート(視点)の指定をすると、
    iPhone でも きれいに見せることができる -->
    <meta name="viewport" content="width=device-width">

    <!-- Google Fonts 書家・片岡佑之さんの手書き書体を使う -->
@<b>{    <link rel="preconnect" href="https://fonts.googleapis.com">@<br>{}    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>@<br>{}    <link href="https://fonts.googleapis.com/css2?family=Yuji+Boku&display=swap" rel="stylesheet">}

    <!-- 自分で作ったスタイルシートを読み込む -->
    <link rel="stylesheet" href="stylesheets/master.css">
  </head>

  <!-- 表示したい内容・出し物・コンテンツを記述します -->
  <body>
    (略)
  </body>
</html>
}
//}

HTMLで手書き書体を読み込むように追記しました。

どの要素を手書き書体を使って表示するかは、CSSで指定します。

//quote{
//noindent
@<code>{CSS rules to specify families}@<br>{}
@<code>{ファミリーを指定するためのCSSルール}
//}

と書かれており、次のCSSを記述することで、選択した書体を使えるようになります。

//list[][]{
font-family: 'Yuji Boku', serif;
//}

それでは早速使っていましょう。

芭蕉翁の名句は、

//list[][]{
<h1 class="catch">
  <a href="https://ja.wikipedia.org/wiki/松尾芭蕉">松尾芭蕉</a><br>
  扇にて酒くむかげやちる櫻
</h1>
//}

と HTML でマークアップしていますので、CSSで @<code>{catch} クラス を選択して、書体を指定すれば良いです。

キャッチフレーズに関するCSSは、すべて @<file>{_catch.css} ファイルにありますので、それを開いて、以下を追記しましょう。
//list[][_catch.css]{
.catch {
  font-family: 'Yuji Boku', serif;
}
//}

ブラウザを再読み込みすると、書体が変わっているはずです。

//blankline

また、せっかくなので、全ての文字の書体を変更したいと思うかもしれません。全ての要素の親は @<code>{<body>}ですので、 @<code>{<body>} 要素を対象に、使用する書体を設定すれば良いです。

//list[][_body.css]{
body {
  (略)

  font-family: 'Yuji Boku', serif;
}
//}

サイト名や俳句など、全て「佑字 朴」書体に変更できました。

//image[googlefont6][][width=50%, border=on]







== ソースコードボタンの配置や装飾を行う

//sideimage[code0][50mm][sep=5mm,side=R]{
続いて、ソースコードボタンの配置や装飾を行います。

現在は、右のように、桜の下に「ソースコードはこちら」と表示されておりますが、芭蕉翁の名句「扇にて酒くむかげやちる櫻」の左側を開けてありますので、桜の写真に重ねて表示させましょう。
//}

=== 配置を整える
@<file>{stylesheets}ディレクトリ(フォルダ)内に@<file>{_code.css}を新規作成し、次のようにCSSを書きます。

//list[][_code.css][1]{
/*=====================================================================
  ソースコードへのリンク に関する 配置や装飾等の指定
=====================================================================*/

/* codeクラス(ソースコードへのリンク) についての指定 */
.code {
  grid-row: code;            /* code 行の下に配置します */
  grid-column: 2;            /* 左から二本目の線に配置します */
  text-align: center;        /* 文字揃えは中央にします */
  writing-mode: vertical-rl; /* 縦書きにします */
  justify-self: center;      /* 水平方向に中央揃えします */
  align-self: end;           /* 垂直方向に下揃えします */
  margin-bottom: 50px;       /* 少し下側に間隔を設けます */
}
//}

//sideimage[code1][50mm][sep=5mm,side=R]{
こちらを適用した結果は、右のようになります @<small>{(見やすいように、桜の木の色を薄くしてあります。)}

画面左下に無事に配置できました。このままでは寂しいですので、次はボタンのような形に装飾を行いましょう。

//blankline
少し凝ったボタンを作る為には、お絵かきソフトを使う他ない時代もありましたが、CSSの急速な進化に伴い、素敵なボタンが簡単に作成できるようになりました。

様々なボタンのデザインを解説したサイトとして、
@<href>{https://jajaaan.co.jp/css/button/,CSSボタンデザイン120個以上 詳しく作り方を解説} があります。

こちらを参考に、「簡素なボタン」「虹色のボタン」「金塊のようなボタン」を作って行きましょう。
//}
---
=== ボタンの形に装飾する

まず、ボタンの元となるHTMLコードをもう一度見ておきましょう。
//list[][ボタンの元となるHTMLコード]{
<a href="https://github.com/Atelier-Mirai/sakura_fubuki"
   class="simple button">
   <span>
    ソースコードは<br>こちら
  </span>
</a>
//}

@<code>{<a>(アンカータグ)}に、クラス名を付けています。@<code>{class="simple button"}、@<code>{class="rainbow button"}、@<code>{class="gold button"} のようにクラス名を変更することで、ボタンの装飾が変わるようにします。

また文字の部分を装飾しやすくする為に、@<code>{<span>ソースコードは<br>こちら</span>} と @<code>{<span>}タグで囲んでいます。

//blankline
それでは @<file>{stylesheets}ディレクトリ(フォルダ)内に@<file>{_button.css}を新規作成し、次のようにCSSを書きましょう。 @<fn>{ryuuyou}

//footnote[ryuuyou][こうして別ファイルにしておくことで、他のサイトを作成する際にも、ボタンのデザインを流用しやすくなります。]

//list[][_button.css][1]{
/*=====================================================================
  ボタンの為の装飾の指定
  参考: CSSボタンデザイン120個以上！どこよりも詳しく作り方を解説！
        https://jajaaan.co.jp/css/button/
=====================================================================*/

/* ボタンの基本形
---------------------------------------------------------------------*/
.button {
  /* 横幅と高さを指定して表示できるようにする */
  display: inline-block;

  /* 書体に関する指定 */
  /* 大きさを 16px 〜 24pxまで可変にする */
  font-size: clamp(16px, 4vw, 24px);
  text-decoration: none; /* 下線などの装飾が付かないようにする */

  /* 文字の配置に関する指定 */
  text-align: center;     /* 文字は中央に揃える */
  vertical-align: middle; /* 縦方向も中央に揃える */

  /* ボタンの形に関する指定 */
  border-radius: 0.5rem;  /* 角を少し丸くする */
  padding: 0.8rem 1.2rem; /* 内側に少し詰め物をして間隔を空ける */

  /* アニメーションに関する指定 */
  transition: all 0.3s;   /* 少し時間をあけて変化するようにする */
}
//}

=== 簡素なボタン

以上の基本形を元に「文字色や枠線・背景色を追加指定する」ことで「簡素なボタン」ができ上がります。

//list[][_button.css]{
/* 簡素なボタン
---------------------------------------------------------------------*/
.simple.button {
  color: var(--botaniro);             /* 文字の色は牡丹色 */
  border: double 3px var(--botaniro); /* 二重の牡丹色の枠線 */
  background: var(--sakurairo);       /* 背景色は桜色 */
}

.simple.button:hover {                /* マウスを重ねたときの指定 */
  background: var(--nanohanairo);     /* 背景色は菜の花色 */
}
//}

//sideimage[simple_button][40mm][sep=5mm,side=R]{
CSS での @<code>{.simple.button} と記述されたセレクタは、HTMLの要素 @<code>{<a class="simple button">} を装飾対象にします。時折使う記法ですので、習得しておきましょう。

右のように、簡素な桜色のボタンが出来上がりましたが、いかがでしょうか。
//}

=== 虹色のボタン
続いては、虹色のボタンを作成していきましょう。

//list[][_button.css]{
/* 虹色のボタン
---------------------------------------------------------------------*/
.rainbow.button {
  /* 背景色を桜色のグラデーションにする */
  background-image: linear-gradient(20deg, #e9defa 0%, #f7cbea 100%);

  /* ボタンに枠線をつける */
  border: 4px solid #e60012;
  /* 枠線を虹色にする */
  border-image: linear-gradient(to right,
    #e60012 14%,
    #f39800 28%,
    #fff100 42%,
    #009944 56%,
    #0068B7 70%,
    #1d2088 84%,
    #cfa7cd 100%);
  border-image-slice: 1;
}

/* 文字を虹色にする */
.rainbow.button span {
  background: linear-gradient(
    -225deg,
    #e60012 14%,
    #f39800 28%,
    #fff100 42%,
    #009944 56%,
    #0068B7 70%,
    #1d2088 84%,
    #cfa7cd 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
}

/* マウスを重ねたときの指定 */
.rainbow.button:hover {
  box-shadow: 0 5px 15px #bc33f5; /* ボタンに紫色の影を付ける */
}
//}

//sideimage[rainbow_button][40mm][sep=5mm,side=R]{
背景を桜色にし、枠線や文字を虹色にすることで、右のようなボタンが出来上がります。
//}

=== 金塊のようなボタン
続いては金塊のようなボタンを作っていきましょう。

//list[][_button.css]{
/* 金塊のようなボタン
---------------------------------------------------------------------*/
.gold.button {
  color: #b1921b; /* 文字の色 */
  text-shadow: -1px -1px 1px #ffffd9; /* 文字に影を付ける */

  /* 枠線の太さと色を、上右下左の時計回りの順に指定する */
  border-top:    none;
  border-right:   4px solid #cea82c;
  border-bottom: 10px solid #987c1e;
  border-left:    4px solid #ffed8b;

  border-radius: 0; /* 金塊なので角は丸めない */
  background: linear-gradient(-45deg, /* 金塊のようなグラデーション */
    #ffd75b 0%,
    #fff5a0 30%,
    #fffabe 40%,
    #ffffdb 50%,
    #fff5a0 70%,
    #fdd456 100%);
}

/* マウスを重ねたときの指定 */
.gold.button:hover {
  /* 上に 3px 空白を入れて、下の枠線を 3px 減らすことで、
     押してへこんだように見せる */
  margin-top: 3px;
  border-bottom: 7px solid #987c1e;
}
//}

//sideimage[gold_button][40mm][sep=5mm,side=R]{
金色のグラデーションを作り、枠線の色合いと相まって立体的な金塊のように見せています。またマウスを重ねたときに、CSSアニメーションにより枠線の太さをゆっくり変更することで、ボタンが押され凹んだような効果を得ています。
//}


== 俳句紹介の配置や装飾を行う

//sideimage[haiku0][50mm][sep=5mm,side=R]{
続いて、俳句紹介欄の配置や装飾を行います。

現在は、右のように、桜の下から、「さくらを詠んだ俳句」の見出しの後、一枚ずつ写真と俳句、俳人名が表示されております。

記述したHTMLを確認するとともに、写真を横に二列並べ、より多くの俳句を紹介できるようにします。
//}

=== HTMLの確認

//list[][]{
<!-- 俳句の紹介 -->
<section class="haiku">
  <!-- h2 は 中見出し -->
  <h2>さくらを詠んだ俳句</h2>

  <!-- それぞれの俳句の紹介 -->
  <article>
    <!-- ウィキペディアへのリンク -->
    <a href="https://ja.wikipedia.org/wiki/小林一茶">
      <!-- 桜の写真を載せる -->
      <figure class="rotate-3 frame">
        <img src="images/ipponzakura.webp" alt="">
      </figure>
      <!-- h3 は小見出し -->
      <h3>穀つぶし櫻の下にくらしけり</h3>
      <!-- 詠んだ人の名前 -->
      <p>小林一茶</p>
    </a>
  </article>

  (略)
</section>
//}

@<code>{<section class="haiku">} と、CSSから扱いやすいよう、 @<code>{haiku}クラス名を付与した後、 @<code>{<article>(記事)} タグ内で、俳人へのリンク・写真・俳句・俳人名 を記述しています。

@<code>{<figure>} タグに、 @<code>{class="rotate-3 frame"} などとクラス名を付与しています。 後々、写真へ枠を付けるなどの効果を@<ruby>{齎,もたら}せるよう、準備しています。


=== 配置を整える
それでは、@<file>{stylesheets}ディレクトリ(フォルダ)内に@<file>{_haiku.css}を新規作成し、次のようにCSSを書きます。

//list[][_haiku.css][1]{
/*=====================================================================
  俳句の紹介に関する 配置や装飾等の指定
=====================================================================*/

/* haikuクラスに対する指定 */
.haiku {
  grid-row: haiku;                /* haiku 行の下に配置します */
  display: grid;                  /* 枠線(grid)を使い 配置できるようにします */
  grid-template-columns: 1fr 1fr; /* 二列、創ります */
  row-gap: 20px;                  /* 行間を20px 列間を10px 取ります */
  column-gap: 10px;
}
//}

//sideimage[haiku1][50mm][sep=5mm,side=R]{
適用した結果は右のようになります。写真が二列に並ぶようになりました。

続いて、俳句の色などの装飾を行っていきましょう。
//}

=== 俳句の色などを装飾する

//list[][_haiku.css][14]{
/* haikuクラス内のh3要素(俳句)に対する指定 */
.haiku h3 {
  font-size: 17px;         /* 文字の大きさを指定します */
}

/* haikuクラス内のp要素(俳人名)に対する指定 */
.haiku p {
  text-align: right;       /* 文字を右揃えにします */
}

/* haiku クラス内の a 要素に対する指定 */
.haiku a {
  color: var(--kurohairo); /* 文字の色は黒羽色にします */
  text-decoration: none;   /* 文字の装飾はなし(下線を付けない) */
}

/* haiku クラス内の a要素にマウスを重ねたときの指定 */
.haiku a:hover {
  /* 文字の装飾として、下線を付けます */
  text-decoration: underline;
}
//}

//sideimage[haiku2][50mm][sep=5mm,side=R]{
適用結果は右のようになります。
//}

=== 見出しを整える
続いては、「さくらを詠んだ俳句」の見出しが中央に来るようにしましょう。

//list[][_haiku.css][36]{
/* haiku クラス内の h2要素(見出し)に対する指定 */
.haiku h2 {
  grid-column: 1 / -1;     /* (見出しなので)二列ぶち抜きで配置します */
  font-size: 24px;         /* 文字の大きさを指定します */
  font-weight: normal;     /* 文字の太さは普通にします */
  text-align: center;      /* 文字揃えは中央にします */
  color: var(--kurohairo); /* 文字の色は黒羽色にします */
}
//}

//sideimage[haiku3][50mm][sep=5mm,side=R]{
適用結果は右のようになります。
//}

きれいに整いましたので、これで完成でも良いのですが、もう一手間加えてみましょう。

@<href>{https://jajaaan.co.jp/css/css-headline/,CSS見出しデザイン参考100選}と言うサイトがございます。見出しに関する様々なデザインが掲載されております。その中から
見出しの上下に金色の線を引く」よう装飾を施し、高級感を持たせて見ましょう。

以下のコードを追加します。

//list[][_haiku.css][45]{
/* 見出しの上下に金色の線を引くための装飾いろいろ */
/* 参考: https://jajaaan.co.jp/css/css-headline/ */
.haiku h2 { position: relative; padding: 1.25rem 2rem; margin: 1rem 0 1rem; }
.haiku h2::before, .haiku h2::after {
  position: absolute;  left: 0;  width: 100%;  height: 4px;  content: "";
  background: linear-gradient(
              135deg, #704308 0%, #ffce08 40%, #e1ce08 60%, #704308 100%); }
.haiku h2:before { top: 0; }
.haiku h2:after  { bottom: 0; }
//}

//sideimage[haiku4][60mm][sep=5mm,side=R]{
@<code>{h2::before, h2::after} は、「擬似要素」を生成するための記法です。CSSで擬似的にHTMLの前後に要素を追加することにより、金色の背景色の設定を行っています。
//}

//blankline
擬似要素に関しては、 MDN @<href>{https://developer.mozilla.org/ja/docs/Web/CSS/::before,::before} に、@<code>{position: relative, position: absolute} については、@<href>{https://uxmilk.jp/63409,CSSのposition: absoluteとrelativeとは} に、丁寧な解説や使用例がございますのでご覧ください。


=== 写真に効果を付ける

@<href>{https://taneppa.net/css3_01/,CSS3で写真に色々装飾を加えてみた} と言うサイトがございます。桜の写真そのままだけでも充分美しいのですが、写真の枠をつけたり、モノクロやセピアにしたりなど、簡単に加工することができます。CSSの学習を兼ねて、ご紹介いたします。

@<file>{stylesheets}ディレクトリ(フォルダ)内に@<file>{_frame.css}を新規作成し、次のようにCSSを書きます。

//list[][_frame.css][1]{
/*=====================================================================
  写真の枠や効果に関する指定
  参考: https://taneppa.net/css3_01/
=====================================================================*/

/* frame クラスに対する指定 */
.frame {
  border: solid 8px var(--sakurairo); /* 桜色の枠線を付けます */
  box-shadow: 0 0 0 1px #ccc,         /* 箱に灰色と黒い影を付けます */
              1px 3px 8px 0 #25252555;
  margin-bottom: 0.5em;               /* 下に少し間隔を取ります */
}

/* 写真をセピア色にする */
.sepia.frame img {
  filter: sepia(90%);
}

/* 写真を白黒にする */
.monochrome.frame img {
  filter: grayscale(90%);
}

/* 写真をぼかす */
.blur.frame img {
  filter: blur(3px);
}

/* 写真の色を反転させる */
.invert.frame img {
  filter: invert(75%);
}

/* 写真を少し透明にする */
.opacity.frame img {
  filter: opacity(67%);
}

/* 写真を右下に少し回転する */
.rotate3 {
  transform: rotate(3deg)
}

/* 写真を右上に少し回転する */
.rotate-3 {
  transform: rotate(-3deg)
}
//}

//sideimage[haiku5][60mm][sep=5mm,side=R]{

HTML で、@<code>{<figure class="rotate-3 frame">} とクラス名を付与します。 CSS では、 @<code>{.rotate-3} による回転効果と、 @<code>{.frame} による枠付け装飾が適用され、少し傾いた枠がついた桜の写真となります。

@<code>{<figure class="rotate-3 sepia frame">, <figure class="rotate-3 monochrome frame">} のように、複数の効果を重ね合わせることもできます。

//blankline
ここでの主役は、CSS @<code>{filter} です。画像の色を変化させたり、ぼかしたりなど様々な効果がございます。MDN @<href>{https://developer.mozilla.org/ja/docs/Web/CSS/filter, filter} に詳しい説明と使用例がございますので、ご覧ください。

//blankline
俳句の紹介については以上で完成です。さくらを詠んだ俳句達を綺麗に紹介することができました。

//}











== フッターの配置や装飾を行う

//sideimage[footer0][50mm][sep=5mm,side=R, border=on]{
最後はフッターの配置や装飾を行います。

現在は、右のように左寄せで表示されております。中央に配置するとともに背景色をつけて完成させましょう。
//}

//blankline
@<file>{stylesheets}ディレクトリ(フォルダ)内に@<file>{_footer.css}を新規作成し、次のようにCSSを書きます。

//list[][_footer.css][1]{
/*=====================================================================
  フッターに関する 配置や装飾等の指定
=====================================================================*/

/* footer 要素に対する指定 */
footer {
  grid-row: footer;             /* footer 行の下に配置します */
  grid-column: 1 / -1;          /* 左右の余白も使って配置します */
  background: var(--sakurairo); /* 背景を桜色にします */
  padding: 14px 0;              /* 空白を入れ上下中央揃えにします */
}

/* footer 要素内の p 要素に対する指定 */
footer p {
  text-align: center;           /* 文字を中央揃えにします */
}
//}

以上で iPhone用のCSSは 完成しました。

//image[iphone_css][][width=100%]
