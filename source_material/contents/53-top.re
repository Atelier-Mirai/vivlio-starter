= トップページの機能拡張

//abstract{
  この章では、トップページに関する次のような機能拡張を行っていきます。
//blankline

ファビコン、アップルタッチアイコン / 検索エンジン用の説明文 / リンクの無効化 / 写真のポップアップ / 写真をスライドさせる / 全画面ヒーローイメージ / スクロールを促す為の表示 / スクロールすると出現するメニュー / 光りながら出現する文字 / 見出しの装飾 / 装飾的なボタン / トップに戻るボタン

//blankline
また、@<code>{JavaScript} の使い方についても触れていきます。
//}

== ファビコン と アップルタッチアイコン
//sideimage[favicon][60mm][sep=5mm,side=R]{
ファビコンとは、ブラウザのタブの左側に表示される小さなアイコンのことです。
//}
//vspace[latex][2mm]

//sideimage[appletouchicon][30mm][sep=5mm,side=R]{
アップルタッチアイコンとは、iPhone / iPad でサイト@<br>{}
をホーム画面に登録すると表示されるアイコンです。
//blankline
どちらもサイトを印象づけ、実装も容易ですので、@<br>{}
ご利用下さい。
//}


=== アイコンの作成
ファビコン、アップルタッチアイコンの作成は、 @<href>{https://ao-system.net/favicongenerator/, 様々なファビコンを一括生成。favicon generator} を利用すると簡単に行えます。

 1. ファビコン、アップルタッチアイコンにしたい正方形の画像を作成します。512x512がお薦めサイズとのことですので、このサイズに予めしておきます。
 2. 「画像ファイルを選択」ボタンを押して、作成した画像をサイトにアップします。
 3. 「ファビコン一括生成」ボタンを押します。
 4. さまざまな大きさの画像が作成され表示されるので、画像の下側にある「ファビコンダウンロード」ボタンを押します。
 5. ダウンロードされた画像たちを解凍(展開)します。たくさんの画像がありますが、使うのは二種類、@<file>{favicon.ico}と、@<file>{apple-touch-icon-180x180.png}です。
 6. この二つの画像ファイルを、@<file>{images}ディレクトリに置き、以下のようなコードを@<code>{<head>}内に追加します。するとブラウザのタブの左側にファビコンが、iPhoneの「ホーム画面に追加」した際に、アップルタッチアイコンが表示されるようになります。

//list[][index.html][]{
<head>
  <!-- ファビコン -->
  <link rel="icon"
        href="images/favicon.ico"
        type="image/ico">

  <!-- アップルタッチアイコン -->
  <link rel="apple-touch-icon"
        href="images/apple-touch-icon-180x180.png"
        type="image/png"
        sizes="180x180">
</head>
//}

== 検索エンジン用の説明文

ウェブサイトを検索すると、そのサイトの簡単な説明文が表示されます。特に指定しなくても、Google がそれらしい説明文を提示しますが、自分で書くこともできますので、やってみましょう。

作成は簡単で、@<code>{<head>}内に次のように書くだけです。

//list[][index.html][]{
<head>
  <!-- 検索エンジン用の説明文 -->
  <meta name="description"
        content="概ね80文字前後のサイトの紹介文が検索時に表示されます。">
</head>
//}

== リンクの無効化

リンク先のページが準備されていると良いのですが、次回更新の予告など、何らかの理由でリンクを無効化したい時もあります。

@<code>{style="pointer-events: none;"} と書くことでリンクを無効化できます。

//list[][]{
<a href="post04.html" style="pointer-events: none;">
  次回予告記事 (居心地のいい部屋にあるもの)
</a>
//}

（インラインスタイルを用いるよりは、HTMLでは @<code>{class="disabled"} とクラス名を付与し、CSS で @<code>{a.disabled { pointer-events: none;\} } と書いたほうが良いです。）

#@# == サイト名の左にロゴマークを表示
#@# サイト名の左にはロゴマークがあるのが一般的ですので、表示させてみましょう。
#@# ロゴは@<file>{logo.png}という画像ファイルにして、 @<file>{images} ディレクトリに納めることにします。
#@#
#@# //list[][index.html][1]{
#@#   <header>
#@#     <div class="logo">
#@#       <img src="images/logo.png" alt="ロゴマーク">
#@#       <a href="index.html">WAVE</a>
#@#     </div>
#@#   </header>
#@# //}
#@#
#@# CSSグリッドの技術を使って、@<code>{logo}クラスを横二列、縦一行のグリッドを作成します。
#@# そして、 @<code>{img} と @<code>{a} それぞれの要素を、一番目と二番目の列に配置しています。
#@#
#@# //list[][style.css]{
#@#   .logo {
#@#     /* ロゴと文字を並べる */
#@#     display: grid;
#@#     grid-template-columns: auto auto;
#@#     grid-template-rows: 58px;
#@#   }
#@#
#@#   .logo img {
#@#     grid-column: 1;
#@#     grid-row: 1;
#@#     align-self: end;
#@#     width: 40px;
#@#     height: 40px;
#@#     margin-right: 5px;
#@#   }
#@#
#@#   .logo a {
#@#     grid-column: 2;
#@#     grid-row: 1;
#@#     align-self: start;
#@#     color: inherit;
#@#     text-decoration: none;
#@#   }
#@# //}

== 写真をポップアップウィンドウで表示する

ウェブサイトに写真を掲載することはよくあります。
@<code>{<img>}タグを使うことで、写真を載せることができますが、より効果的に写真を見せることができるよう、先人の方が様々な有益な「ライブラリ」を提供してくださっています。

//note[ライブラリ]{
  ライブラリとは、図書館、図書室、資料室、書庫、書斎、蔵書、文庫、選書、双書などの意味を持つ英単語。ITの分野では、ある特定の機能を持ったコンピュータプログラムを他のプログラムから呼び出して利用できるように部品化し、そのようなプログラム部品を複数集めて一つのファイルに収納したものをライブラリという。 @<fn>{fn-1}
//}
//footnote[fn-1][出典: @<href>{https://e-words.jp, IT用語辞典}]

様々なライブラリがありますが、 ここでは @<code>{Magnific Popup} をご紹介いたします。

「画面上にある小さな写真」をクリックしたときに、「大きく表示させる」ことができます。

//image[popup0][小さな写真][width=90%]

//image[popup1][クリックすると大きく表示される][width=70%]

=== JavaScript の 簡単な紹介

今まで、 @<code>{HTML} と @<code>{CSS} を使って、ウェブサイトを創ってきましたが、動きのあるウェブサイトを創るために、@<code>{JavaScript} を使います。

//note[JavaScriptとは]{
JavaScriptとは、主にWebページに組み込まれたプログラムをWebブラウザ上で実行するために用いられるプログラミング言語。ページ内の要素に動きや効果を加えたり、閲覧者の操作に即座に反応して何らかの処理を行ったりするのに用いられる。 @<fn>{fn-2}
//}

//footnote[fn-2][出典: @<href>{https://e-words.jp, IT用語辞典}]

今回の例ですと、ブラウザで読み込んだ@<code>{HTML}の要素を操作する機能が @<code>{JavaScript}にはありますので、これによってクリックされた写真を大きく表示したりします。

始めて触れる方もいらっしゃるかもしれませんので、簡単に概要をご紹介いたします。 より詳しくは巻末の参考文献等をご覧ください。

//blankline
それでは、練習として @<file>{index.html} と @<file>{aisatsu.js} を次のように書きましょう。

//list[][index.html]{
<html>
  <head>
    <!-- (略) -->
  </head>
  <body>
    <!-- (略) -->

    <!-- aisatsu.js という JavaScript プログラムを、読み込む -->
    <script src="aisatsu.js"></script>
  </body>
</html>
//}

//list[][aisatsu.js]{
//「おはよう」と、アラート(警報) を出すプログラム
alert("おはよう");
//}

//image[ohayou][実行例][width=50%]

#@# 無事に表示されましたでしょうか。

@<code>{<script src="aisatsu.js"></script>}で、@<file>{aisatsu.js} を読み込んでいます。
@<code>{<script>}タグは、いろいろなところに記述できますが、基本的には @<code>{</body>}の直前にするのがお薦めです。

//blankline
また、素の @<code>{JavaScript} @<fn>{vanilla}を より使い易くするライブラリとして、@<code>{jQuery} があります。

//footnote[vanilla][素の @<code>{JavaScript} のことを、 @<code>{Vanilla JS} と呼ぶこともあります]

//note[jQueryとは]{
jQueryとは、Webブラウザ上で動作するJavaScriptライブラリの一つ。簡潔な記述で豊富な機能(Webページの要素に演出効果やアニメーションなどを追加したり、スタイルやイベント起動の設定や変更など)を活用できる。また様々な機能を実現する豊富な対応プラグインが公開されている。
jQueryは独特の記法を使い、複数の処理を容易に組み合わせられるようになっている。機能のほとんどは「$」あるいは「jQuery」という名前のオブジェクトのメソッドとして定義されている。

最初に$関数にCSSセレクタに似た記法で @<code>{$(“h1”)} のようにページ内の操作したいDOM（Document Object Model）要素を指定すると、その要素を内部に持つjQueryオブジェクトが返されるため、これに実行したいメソッドを指定する。例えば、 @<code>{$("#aisatsu").text("こんにちは")} と書くと、#aisatsu 要素の中身を、「こんにちは」に変更できる。
//}

それでは、素の@<code>{JavaScript} と、@<code>{jQuery} の違いを見てみましょう。

//list[][index.html]{
<body>
  <h1 id="aisatsu">おはよう</h1>

  <script src="ohayou_vanilla.js"></script>
</body>
//}

//list[][aisatsu_vanilla.js]{
// 素のJavaScript(Vanilla JS)での例
document.getElementById("#ohayou").innerText = "こんにちは";
//}

//list[][index.html]{
<body>
  <h1 id="aisatsu">おはよう</h1>

  <script src="aisatsu_jquery.js"></script>
</body>
//}

//list[][aisatsu_jquery.js]{
// jQuery の例
$("#aisatsu").text("こんにちは");
//}

どちらも、 @<file>{index.html} 内の @<code>{id="aisatsu"} が付与された要素を「こんにちは」に書き換えます。

//blankline
従来はブラウザ間の挙動の相違が著しく、また @<code>{JavaScript} 自体の機能も整っていなかったため、各ブラウザ間の差違を埋め、簡潔に容易に記述することができる @<code>{jQuery} が盛んに用いられました。
今日では、ブラウザの互換性の向上や、@<code>{JavaScript} の機能向上に伴い、素の @<code>{JavaScript} や 上位互換となる @<code>{TypeScript} を使って書くケースも増えて参りましたが、ここでは @<code>{jQuery} で書かれた多くの優秀なライブラリがありますので、使っていきましょう。

//blankline
ウェブサイトに @<code>{jQuery} を取り込むには、@<code>{CDN} を使うと便利です。

//note[CDNとは]{
CDN 【Content Delivery Network】 コンテンツデリバリネットワーク
ウェブ上で送受信されるコンテンツをインターネット上で効率的に配送するために構築されたネットワーク@<fn>{fn-1}
//}

有名な @<code>{CDN} として、@<href>{https://cdnjs.com/, cdnjs}や、@<href>{https://www.jsdelivr.com/, jsDelivr}があります。 ここでは、 @<code>{cdnjs}を使ってみましょう。

 - 1. @<href>{https://cdnjs.com/, cdnjs}のサイトにアクセスします。

//image[cdnjs][][width=70%]

 - 2. 中央にある検索窓に @<code>{jQuery} と入力、検索します。 @<br>{}
   候補が表示されますので、一番上の @<code>{jquery @ 3.6.1} をクリックします。

//image[jquery1][][width=70%]

 - 3. @<code>{jQuery} のいくつかの種類が表示されますが、ここでは一番上に表示されている @<file>{jquery.min.js}を使うことにしましょう。 @<code>{</>}ボタンをクリックすると、コピーできますので、エディタに貼り付けます。

//image[jquery2][][width=70%]

//list[][index.html]{
<body>
  <!-- (略) -->

  <!-- jQueryをCDNから読み込む -->
  <script
    src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.1/jquery.min.js"
    integrity="sha512-894YE6QWD5I59HgZOGReFYm4dnWc1Qt5NtvYSaNcOP+u1T9qYdvdihz0PPSiiqn/+/3e7Jo4EaG7TubfWGUrMQ=="
    crossorigin="anonymous"
    referrerpolicy="no-referrer">
  </script>
</body>
//}

少し長いですので、以下のように省略して書くこともできます。

//list[][index.html]{
  <!-- jQueryをCDNから読み込む -->
  <script
    src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.1/jquery.min.js">
  </script>
//}

//note[jQueryのファイルの種類について]{
  @<file>{jquery.min.js}, @<file>{jquery.js}, @<file>{jquery.min.map}, @<file>{jquery.slim.js},  @<file>{jquery.slim.min.js}, @<file>{jquery.slim.min.map} と6つのファイルが表示されました。
  拡張子が @<file>{.js}となっているものは、 @<code>{JavaScript}のファイルで、@<code>{.map}となっているものは、「ソースマップ」と呼ばれるファイルです。

  ブラウザが実行する JavaScript ソースは、開発者が作成した元のソースから何らかの方法で変換される場合があります。ソースマップ は変換後のソースと元のソースを関連付けるファイルであり、 @<fn>{source_map}プログラムのデバッグ時に活用されます。

  拡張子が @<code>{.js} となっているものの内、@<file>{jquery.js} と @<file>{jquery.min.js} は同じものです。人に読み易く書かれている @<file>{jquery.js} を、圧縮(ミニファイ)してブラウザで速く読み込めるようにしたものが @<file>{jquery.min.js} です。

  @<file>{jquery.slim.js} と @<file>{jquery.slim.min.js} は、全ての機能を備えた @<file>{jquery.js} から、利用機会の少ないアニメーション機能などを削除したものです。
//}

//footnote[source_map][出典: @<href>{https://developer.mozilla.org/ja/docs/Tools/Debugger/How_to/Use_a_source_map, ソースマップを使用する}]


=== 写真ポップアップ機能を実装する
@<href>{https://dimsemenov.com/plugins/magnific-popup/, 公式サイト} に詳しく紹介されておりますが、簡単に使い方を説明します。

@<code>{Magnific Popup} や @<code>{Slick}、@<code>{Vegas} など、よく使われる有名なライブラリは、@<code>{CDN}に公開されています。簡潔に記述でき、応答速度の改善も図ることができますので、活用していきましょう。

それでは、写真ポップアップのためのライブラリ、 @<code>{Magnific Popup} を使って行きましょう。
@<code>{HTML}の全体は次のようになります。@<code>{CSS}は@<code>{head}タグに、 @<code>{JavaScript}は @<code>{body}タグの一番最後に書きます。

//list[][index.html]{
<head>
  <!-- Magnific Popup -->
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/magnific-popup.js/1.1.0/magnific-popup.css">
  <link rel="stylesheet" href="magnific-popup-custom.css">
</head>

<body>
  <section class="zoo">
    <h2>動物園の思い出</h2>
    <p>動物園に行ってきました。いろいろな動物に会えました。</p>

    <div>
      <a href="images/tora.webp" title="大きな虎です">
        <img src="images/tora.webp">
      </a>
      <a href="images/tsuru.webp" title="鶴です">
        <img src="images/tsuru_s.webp">
      </a>
      <a href="images/zou.webp" title="象さん 象さん お鼻が長いのね">
        <img src="images/zou_s.webp">
      </a>
      <a href="images/saru.webp" title="お猿さんです">
        <img src="images/saru_s.webp">
      </a>
      <a href="images/hakucho.webp" title="白鳥の湖">
        <img src="images/hakucho_s.webp">
      </a>
      <a href="images/araiguma.webp" title="洗熊です">
        <img src="images/araiguma_s.webp">
      </a>
      <a href="images/kuma.webp" title="熊さんです">
        <img src="images/kuma_s.webp">
      </a>
    </div>
  </section>

  <!-- jQuery -->
  <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.1/jquery.min.js"></script>
  <!-- Magnific Popup -->
  <script src="https://cdnjs.cloudflare.com/ajax/libs/magnific-popup.js/1.1.0/jquery.magnific-popup.min.js"></script>
  <script src="magnific-popup-custom.js"></script>
</body>
//}

=== HTML の解説
HTML を次のように書き、写真ギャラリー用の画像を、imageディレクトリに入れておきます。
サムネイル画像(小さな画像)も準備しておきます。

//list[][写真表示用のHTML]{
<div>
  <a href="images/tora.webp" title="大きな虎です">
    <img src="images/tora_s.webp">
  </a>
</div>
//}

@<code>{<img src="images/tora_s.webp">}で使われている@<file>{tora_s.webp}は、元の画像ファイル@<file>{tora.webp}を小さくしたもので、「サムネイル」と呼ばれる画像です。
小さな画像を用意することで、ウェブサイトを見る人が心地よく閲覧できるようになります。

作成者の意図に応じて、写真の大きさや動きをカスタマイズすることができます。
そのために次のコードを書き、@<file>{magnific-popup-custom.css} と @<file>{magnific-popup-custom.js} を読み込んでいます。
//list[][index.html]{
  <link rel="stylesheet" href="magnific-popup-custom.css">
  <script src="magnific-popup-custom.js"></script>
//}

=== カスタマイズ用のCSS
@<code>{Magnific Popup} をカスタマイズする為の @<code>{CSS}は、一例として次のように書きます。

//list[][magnific-popup-custom.css]{
/* 画像の大きさを指定 */
.zoo div {
  /* 横一杯に使う */
  grid-column: 1 / -1;

  /* aタグのためのコンテナ(箱)にする */
  display: grid;
  grid-gap: 10px;

  /* grid-auto-fill */
  grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
}

.zoo div a img {
  vertical-align: bottom;
}

/* 写真をクリックしたときに、ズームアップする為の設定 */
.mfp-with-zoom .mfp-container,
.mfp-with-zoom.mfp-bg {
  opacity: 0;
  backface-visibility: hidden;
  transition: all 0.3s ease-out;
}

.mfp-with-zoom.mfp-ready .mfp-container {
    opacity: 1;
}

.mfp-with-zoom.mfp-ready.mfp-bg {
    opacity: 0.8;
}

.mfp-with-zoom.mfp-removing .mfp-container,
.mfp-with-zoom.mfp-removing.mfp-bg {
  opacity: 0;
}
//}

//note[grid-auto-fill]{
//list[][]{
grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
//}

と書くことで、グリッドの列を生成できます。 @<href>{https://www.webprofessional.jp/difference-between-auto-fill-and-auto-fit/} に分かりやすい説明がございますので、ご覧になってください。
//}

=== カスタマイズ用のJavaScript
@<code>{Magnific Popup} をカスタマイズする為の @<code>{JavaScript}は、次のように書きます。

//list[][magnific-popup-costom.js]{
$(".zoo div").each(function () {
  $(this).magnificPopup({
    // 基本設定いろいろ
    delegate: "a",
    type: "image",
    tLoading: "Loading image# % curr % ...",
    mainClass: "mfp-img-mobile",
    gallery: {
      enabled: true,
      navigateByImgClick: true,
      preload: [0, 1],
      arrowMarkup: `<button title="%title%"
                            type="button"
                            class="mfp-arrow mfp-arrow-%dir%"></button>`,
      tPrev: "Previous(Left arrow key)",
      tNext: "Next(Right arrow key)",
      tCounter: '<span class="mfp-counter"> %curr% of %total% </span>'
    },
    image: {
      tError: '<a href="%url%"> The image# %curr% </a> could not be loaded.',
      titleSrc: function (item) {
        return `${item.el.attr('title')} <small> by Marsel Van Oosten </small>`;
      }
    },

    // クリックしたときにズームアップするための設定
    mainClass: "mfp-with-zoom",
    zoom: {
      enabled: true,
      duration: 300,
      easing: "ease-in-out",
      opener: function (openerElement) {
        return openerElement.is("img") ? openerElement : openerElement.find("img");
      }
    }
  });
});
//}

以上で、 @<code>{Magnific Popup} を使った写真ギャラリーの作成は完了です。
---

コンピュータによる画像表現

==== ラスター形式

//sideimage[nine][25mm][sep=5mm]{
コンピュータで画像を表現するにはどのようにしたら良いのでしょうか。
左は 8 × 8 = 64 個の画素を使って作成した 数字の「９」の画像です。
画素が光っていない黒を0, 光っている白を1とすると、
//quote{
//noindent
00000000
01111110
01111110
00000000
11111110
11111110
11111110
00000000
//}
の64@<ruby>{bit,ビット}(= 8 @<ruby>{Byte,バイト})で表現できます。
//}
//vspace[latex][2mm]

白黒画像でしたらこれで完了ですが、カラー写真では、フルカラー16,777,216色を表現するために、赤256段階(=8@<ruby>{bit,ビット})、緑256段階(=8@<ruby>{bit,ビット})、青256段階(=8@<ruby>{bit,ビット})が必要ですから、8 Byte × 8 × 8 × 8 = 512 @<ruby>{Byte,バイト}となります。

iPhone では、3,024 × 4,032 = 12,192,768 もの画素数で写真を撮ることができ、さらに赤1,024段階(=10ビット)、緑1,024段階(=10ビット)、青1,024段階(=10ビット)の1,073,741,824色が表現できます。なので、写真一枚を保存するために、
3,024 × 4,032 × 10 × 10 × 10 = 12,192,768,000 @<ruby>{bit,ビット} (=1,524,096,000 @<ruby>{Byte,バイト} =  1,488,375 @<ruby>{kB,キロバイト} = 1,453 @<ruby>{MB,メガバイト} = 1.4 @<ruby>{GB,ギガバイト}) もの容量が必要となります。数十枚写真を撮るだけで、容量一杯となってしまいます。
//blankline
そこで、写真の情報量をそのまま保存するのではなく、「**圧縮**」して保存することにしましょう。

先ほどの数字の「９」の例ですと、
//quote{
//noindent
黒黒黒黒黒黒黒黒 黒白白白白白白黒 黒白白白白白白黒 黒黒黒黒黒黒黒黒 白白白白白白白黒 白白白白白白白黒 白白白白白白白黒 黒黒黒黒黒黒黒黒
//}
とそのまま表現する代わりに、同じ色が続いているところは色の数を記すことにすると
//quote{
//noindent
黒９白６黒２白６黒９白７黒１白７黒１白７黒９
//}
と 22 文字で表現できます。さらに黒の次は白なので、省略できそうです。すると、

//quote{
//noindent
９６２６９７１７１７９
//}
と 11 文字で表現できます。

そのまま表現していた際には 64 文字必要でしたが、11 ÷ 64 = 17% と 約 1 / 6 で済みました。これが圧縮の原理です。(ランレングス圧縮と呼ばれ、FAXなどで用いられています。)
//blankline
FAXなどで用いられているランレングス圧縮ですが、繰り返しが少ないと効率が悪化するという弱点を抱えています。そこで、より優れた様々な圧縮アルゴリズムが考案されています。
例えば、iPhone では HEVC(High Efficiency Video Coding) 方式を採用し、一枚の写真を保存するために 必要な 1.4 @<ruby>{GB,ギガバイト} を、数 @<ruby>{MB,メガバイト} と、数百分の一に圧縮しています。

==== 次世代画像形式の@<ruby>{WebP,ウェッピー}

様々な画像形式が考案され、写真用の@<ruby>{JPEG,ジェイペグ}, 図やイラストのための@<ruby>{GIF,ジフ},@<ruby>{PNG,ピング}が主流となりましたが、こうした中登場したのが、次世代画像形式の@<ruby>{WebP,ウェッピー}です。

//quote{
//noindent
　WebPとは、グーグル社が開発・公開している画像ファイル形式の一つ。標準のファイル拡張子は「.webp」。Webページへ埋め込む静止画像に適した画像形式として、既存のJPEGやGIF、PNGの置き換えが可能である。 @<br>{}
　JPEGのような写真に適した高圧縮率の非可逆圧縮と、GIFやPNGのような図表やイラストに適した可逆圧縮の両方に対応する。透過PNGのようなピクセル単位の透過度(アルファチャンネル)が非可逆圧縮でも利用でき、GIFアニメーションのような簡易なアニメーション機能(フルカラー画像や非可逆圧縮も可)にも対応する。【出典: IT用語辞典】
//}

ウェブ制作会社ICSが提供する技術情報メディアがあります。HTML / CSS / JavaScriptを中心とした記事が多数掲載されています。@<ruby>{WebP,ウェッピー}について書かれた記事もございましたので、引用してご紹介いたします。 @<fn>{ics}

==== 次世代画像形式のWebP、そしてAVIFへ

長い間、Webの静止画に関しては「写真のJPEG、ロゴやイラストのGIF、透過画像のPNG」という明確な使い分けが確立されて来ました。WebPはこのすべてを置き換えることができる次世代のフォーマットです。

==== WebPはJPEG/GIF/PNG(APNG)をカバーする魅力的なフォーマット

WebPを使うことで、これまでは用途や画像の特徴ごとに使い分けが必要だったフォーマットの一本化が可能になります。主な特徴を簡単に紹介しましょう。

 * 高い圧縮率：同等画質のJPEGと比較して20-30%のサイズ削減（JPEGの置き換え）
 * 不可逆圧縮と透過アニメーションの併用（透過アニメーションでも画質を犠牲にしてサイズを削減できる）（GIF/PNGの置き換え）
 * 画質劣化のない可逆圧縮もサポート（GIF/PNGの置き換え）

//image[webp][][width=80%]

==== さらに次世代のフォーマット、AVIFも

  * 多様な色空間やサンプリング方式をサポート
  * WebPよりもさらに高画質でコンパクト（同じサイズでも画質が高く、JPEGに特有のブロックノイズも発生しない）
  * Amazon・Netflix・Google・Microsoft・Mozilla等の幅広い企業によるコンソーシアムが共同で開発（FacebookやAppleも後から参画）

//image[avif][][width=80%]

//blankline

@<code>{ImageMagick} @<fn>{imagemagick}等のツールを導入することで、簡単に画像形式を変換することができますし、また、ネット上でオンラインで変換してくれるサイトもございます。

画像の表示も速くなり、利用者に快適に閲覧してもらえますので、使っていきましょう。


//footnote[ics][@<href>{https://ics.media/entry/201001/,次世代画像形式のWebP、そしてAVIFへ}]

//footnote[imagemagick][@<href>{https://imagemagick.biz/,ImageMagickの使いかた 日本語マニュアル}]

== 写真をスライドさせる

@<href>{https://kenwheeler.github.io/slick/, slick} というライブラリを使うと、写真をスライドさせることができます。公式サイトにも詳しく例や説明がありますので、ご覧ください。

//image[uminoomoide][][width=90%]

ここでは、 @<href>{https://codepen.io/jackharner/pen/gyyeEd, Grid Of Sliders}として、Jack Harnerさんが@<code>{Code Pen}に公開している例をもとに実装します。コード中にコメントを入れておりますので、写真などを変更されてご活用下さい。

//list[][index.html]{
<head>
  <!-- slick-carousel -->
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/slick-carousel/1.8.1/slick.min.css">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/slick-carousel/1.8.1/slick-theme.min.css">
  <link rel="stylesheet" href="slick-custom.css">
</head>

<body>
  <section class="sea">
    <div class="slider-wrapper">
      <h2>海の思い出</h2>
      <p>海に行ってきました。波の音はとっても心落ち着きます。</p>

      <div class="slider">
        <div class="card">
          <img src="images/sea01.webp" alt="">
          <h3>空飛ぶ鷗</h3>
        </div>
        <!-- (略) -->
        <div class="card">
          <img src="images/sea07.webp" alt="">
          <h3>幾星霜に耐えた老松</h3>
        </div>
      </div>
    </div>
  </section>

  <!-- jQuery -->
  <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.1/jquery.min.js"></script>
  <!-- Slick -->
  <script src="https://cdnjs.cloudflare.com/ajax/libs/slick-carousel/1.8.1/slick.min.js"></script>
  <script src="slick-custom.js"></script>
</body>
//}

//list[][slick-custom.css]{
.slider-wrapper {
  grid-column: 2;
  max-width: 100%;
  min-width: 0px;
  justify-self: center;
}

.card {
  color: black;
  text-align: center;
  display: inline-flex !important;
  align-items: center;
  justify-content: center;
  flex-direction: column;
  max-width: 100%;
  min-width: 0px;
  margin: 1em; /* 写真に少し間隔を入れる為 */
}

.card img {
  max-width: 100%;
}

.title {
  font-size: 4em;
  text-align: center;
  margin: 0.25em;
}

/* 戻る矢印、次へ矢印 */
.slick-prev,
.slick-next {
  position: absolute;
  top: 42%;
  cursor: pointer;
  border-top:   2px solid #666;
  border-right: 2px solid #666;
  height: 15px;
  width: 15px;
}

.slick-prev {
  left: -1.5%;
  transform: rotate(-135deg);
}

.slick-next {
  right: -1.5%;
  transform: rotate(45deg);
}

.slick-prev::before,
.slick-next::before {
  content: "";
}
//}

//list[][slick-custom.js]{
$(".slider").slick({
  slidesToShow: 3,         // 画面に見せるスライドの枚数
  slidesToScroll: 3,       // 1回のスクロールで移動するスライドの枚数
  dots: true,              // 画面下部に案内用ドット（点）を表示
  arrows: true,            // 左右の矢印表示
  autoplay: true,          // 自動再生
  autoplaySpeed: 2000,     // 自動再生速度(ms)
  rows: 1,                 // スライド表示に用いる行数
  pauseOnHover: true,      // ホバー時に停止するか否か
  responsive: [            // レスポンシブ対応
    {
      breakpoint: 768,     // 端末の横幅が768px以下の見せ方
      settings: {
        slidesToShow: 2,
        slidesToScroll: 2,
      }
    },
    {
      breakpoint: 428,     // 端末の横幅が428px以下の見せ方
      settings: {
        slidesToShow: 1,
        slidesToScroll: 1,
      }
    }
  ]
});
//}

== 全画面のヒーローイメージ

//sideimage[vegas][60mm][sep=5mm,side=R]{
サイトを印象づける「ヒーローイメージ」。これを全画面にしてみましょう。 @<fn>{ugoki_vegas}
//footnote[ugoki][巻末の参考文献 動くWebデザインアイディア帳 のコードを元に改変]

JavaScriptを使って、何枚かの絵が自動で切り替わるようにします。
@<code>{Vegas} という素敵な「ライブラリ」が公開されていますので、それを使うと簡単に実装できます。

いつものように、@<code>{CSS}は@<code>{head}タグに、 @<code>{JavaScript}は @<code>{body}タグの一番最後に書きます。
//}

//footnote[ugoki_vegas][巻末の参考文献「動くWebデザインアイディア帳」より引用、適宜改変しています。]


#@# @<small>{なお、これによりメニューバーの表示がなくなってしまいますが、これは後ほど解決します。}

//list[][index.html]{
<head>
  <!-- Vegas - Fullscreen Backgrounds and Slideshows. -->
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/vegas/2.5.4/vegas.min.css">
  <link rel="stylesheet" href="vegas-custom.css">
</head>

<body>
  <div id="vegas_slider">
    <h1 class="glow text">Best place to visit in the world</h1>
    <a href="https://github.com/Atelier-Mirai/wave-improve" class="btn btn-gradient">
      <span>ソースコードは<br class="mobile only">こちら</span>
    </a>
  </div>

  <!-- jQuery -->
  <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.1/jquery.min.js"></script>
  <!-- Vegas -->
  <script src="https://cdnjs.cloudflare.com/ajax/libs/vegas/2.5.4/vegas.min.js"></script>
  <script src="vegas-custom.js"></script>
</body>
//}

//list[][vegas-custom.css]{
#vegas_slider {
  /* スライダー全体の縦幅を全画面にする */
  width: 100%;
  height: 100vh;
}

#vegas_slider h1 {
  position: absolute;
  z-index: 2;
  top: 40%;
  left: 50%;
  transform: translate(-50%, -50%);
  text-align: center;
  font-size: 6vw; /* 6vw は、幅の 6% という単位指定 */
  letter-spacing: 0.2em;
  text-transform: uppercase; /* (小文字でも)大文字に変換する */
  color: white;
  width: 80%;
}

@media(min-width: 768px) {
  #vegas_slider h1 {
    font-size: 48px; /* 大画面で大きく成りすぎるのを防ぐ */
  }
}

#vegas_slider a {
  grid-column: 2 / 4;
  position: absolute;
  z-index: 2;
  top: 60%;
  left: 50%;
  transform: translate(-50%, -50%);
  text-align: center;
  letter-spacing: 0.1em;
  text-transform: uppercase; /* (小文字でも)大文字に変換する */
  color: white;
}
//}

//list[][vegas-custom.js]{
$('#vegas_slider').vegas({
  overlay: true,
  transition: 'blur',
  transitionDuration: 2000,
  delay: 10000,
  animationDuration: 20000,
  animation: 'kenburns',
  slides: [{ src: './images/room.webp'},
           { src: './images/room02.webp'},
           { src: './images/room03.webp'},
           { src: './images/room04.webp'},
           { src: './images/room05.webp'}]
});
//}

== スクロールを促す為の表示
//sideimage[scroll][30mm][sep=5mm,side=R]{

  ヒーローイメージが全画面になりましたが、このサイトを閲覧した方がどのようにしたら次のページが見られるのか、もしかすると戸惑うかもしれません。UI/UXの観点から、下へのスクロールを促すようにしてみましょう。 @<code>{CSSアニメーション機能}を使って実現します。 @<fn>{scroll_ugoki}

//}


//footnote[scroll_ugoki][巻末の参考文献「動くWebデザインアイディア帳」より引用、適宜改変しています。]


//list[][index.html]{
<head>
  <link rel="stylesheet" href="scroll.css">
</head>

<body>
  <!-- スクロールを促す -->
  <div class="scrolldown">
    <span>Scroll</span>
  </div>
</body>
//}

//list[][scroll.css]{
/* スクロールを促す
-----------------------------------------------------------------------------*/
.scrolldown {
  grid-row: vegas;
  justify-self: center;
  align-self: end;
  padding-bottom: 60px;
}

/* 表示位置 */
.scrolldown {
  position: relative;
}

/* Scrollという文字表示の設定 */
.scrolldown span {
  color: var(--sakurairo);
  font-size: 1rem;
  letter-spacing: 0.05em;
}

/* 線の表示 */
.scrolldown::after {
  content: "";
  position: absolute;
  top: 220px;
  left: 35px;
  width: 2px;
  height: 30px;
  background: var(--sakurairo);
  animation: pathmove 1.4s ease-in-out infinite;
  opacity: 0;
}

/* 高さ・位置・透過度が変化して、線が上から下に動く */
@keyframes pathmove {
  0% {
    height: 0;
    top: 25px;
    opacity: 0;
  }
  30% {
    height: 30px;
    opacity: 1;
  }
  100% {
    height: 0;
    top: 60px;
    opacity: 0;
  }
}
//}
---

@<code>{position: absolute} と @<code>{position: relative} について

#@# === @<code>{position: absolute} と @<code>{position: relative} について
@<code>{position: absolute} と @<code>{position: relative} については、UX MILK さんの記事
@<href>{https://uxmilk.jp/63409} が分かりやすくお勧めです。以下に引用いたします。

//blankline
CSSを記述するときにpositionプロパティを利用して、要素の位置をずらすことがあります。そのときに出てくるのが「@<code>{position: absolute}（絶対位置）」「@<code>{position: relative}（相対位置）」です。
なんとなく使っていたけど、「絶対位置」「相対位置」と言われてもなかなかピンとこない人もいるのではないでしょうか。
今回は実際に配置した例を見て、「absolute」と「relative」について確認していきましょう。

=== @<code>{position} プロパティとは
まずは、「@<code>{position: absolute}」「@<code>{position: relative}」を使ううえで欠かせない @<code>{position}プロパティについて説明します。

@<code>{position}プロパティは、「要素を配置する基準」を指定するためのプロパティです。「@<code>{position: absolute}」と「@<code>{position: relative}」はこの「基準」の場所を区別するためにあるということを理解していると、この先の説明もわかりやすく感じると思います。

=== @<code>{absolute} とは

//sideimage[css-position][40mm][sep=5mm,side=R]{
「@<code>{position: absolute}」は移動するときの基準がウィンドウ、または親要素になります。

つまり複数の要素がある場合でも「@<code>{position: absolute}」で指定すると、他の要素を無視して左上（@<code>{top:0} @<code>{left:0}の位置）から移動するということです。

//blankline
実際に配置した例を見ていきましょう。@<code>{200px × 100px} のboxを３つ並べました。
//}
#@# //image[css-position][][width=33%]

//sideimage[css-position4][60mm][sep=5mm,side=R]{
次に、青色のbox2に @<code>{{ position: absolute; top:150px; left:100px \}} を指定します。

すると、box2はウィンドウの左上を基準（起点）にして、上から @<code>{150px}、左から @<code>{100px} の位置に移動しました。さらに @<code>{position: absolute} を指定した要素は高さがなくなり、浮いたような状態になるため、box3はbox2を無視して位置を詰めています。
//}

#@# //image[css-position4][][width=50%]

=== @<code>{relative} とは

//sideimage[css-position5][60mm][sep=5mm,side=R]{
@<code>{relative} は移動するときの基準が元いた位置になります。つまり @<code>{position} を記述する前に配置されていた場所から移動するということです。

box2に、@<code>{{ position: relative; top:150px; left:100px \}} を指定した例を見ていきましょう。

box2は自分が元々いた位置を基準にして、上から @<code>{150px}、左から @<code>{100px} の位置に移動しています。

また、@<code>{position: absolute} とは違い、移動させた要素の高さが残るため、box3は位置を詰めずそのままの位置に表示されています。
//}

#@# //image[css-position5][][width=50%]


=== @<code>{absolute} と @<code>{relative} の使い方

//sideimage[css-position7][60mm][sep=5mm,side=R]{
実際にウェブサイトを制作すると、親要素を基準にして子要素を移動させたいという場合が多いです。しかし要素に空白を残したくないからと、子要素にだけ「@<code>{position: absolute}」を記述してしまうと、思ったように表示することができません。
たとえば、@<code>{parent}（青いボックス）の子要素である @<code>{child}（緑のボックス）に @<code>{{ position: absolute; top:20px; left:150px \}} を指定すると、右のように表示されます。これは、親要素ではなく画面左上を起点に子要素が移動しているからです。
//}

#@# //image[css-position7][][width=50%]

//vspace[latex][2mm]
//sideimage[css-position8][60mm][sep=5mm,side=R]{
親要素を基準にするためには、親要素に「@<code>{position: relative}」を記述します。こうすることで、子要素が親要素を基準に移動することができます。
//}

#@# //image[css-position8][][width=50%]

=== まとめ
「@<code>{position: absolute}」と「@<code>{position: relative}」は、最初は混乱するかもしれませんが、少しでも理解しておくと、実際に @<code>{position} を使ってレイアウトするときやソースコードを参考にしたときにすんなりと記述しやすくなります。ぜひ覚えておきましょう。


== スクロールすると出現するメニュー

全画面でヒーローイメージが表示されるようになりました。スクロールを促すよう、アニメーションも実装しましたので、今度はスクロールすると出現するメニューを作成していきましょう。

//image[headermenu][][width=90%,border=on]


まず、HTML は次のように書きます。

//list[][index.html]{
<!-- ヘッダー (ロゴとナビゲーションメニュー) -->
<header class="header hidden">
  <!-- ロゴ -->
  <a class="logo" href="index.html">
    <img src="images/logo.webp" alt="ロゴマーク">
    <span>WAVE</span>
  </a>
  <!-- ナビゲーションメニュー -->
  <nav class="menu">
    <ul>
      <li>
        <a href="index.html">
          <i class="fa-solid fa-house fa-lg fa-fw"></i>
          トップ
        </a>
      </li>
      <li>
        <a href="about.html">
          <i class="fa-brands fa-pagelines fa-lg fa-fw"></i>
          サイトについて
        </a>
      </li>
      <li>
        <a href="contact.html">
          <i class="fa-solid fa-envelope fa-lg fa-fw"></i>
          お問い合わせ
        </a>
      </li>
    </ul>
  </nav>
</header>
//}

サイト名の隣には、ロゴマークも表示させるようにしています。

ナビゲーションメニューは、普通に書いています。@<code>{<li>}タグは一行で書くこともできますが、@<href>{https://u670.com/pikamap/htmlseikei.php, HTML整形ツール}を使って、読みやすく整えています。@<fn>{shoseki}
//footnote[shoseki][紙幅に納まるようにもできました。]

それぞれのメニュー項目は、Font Awesome を使って、アイコンも付けています。 Font Awesome では、クラス名を付与することで細かい調整も可能です。@<code>{fa-lg} は @<code>{1.33倍}、@<code>{la-2x} は @<code>{2}倍の大きさ、@<code>{fa-fw} は右に少し間隔が空きます。

より詳しい説明は @<href>{https://coliss.com/articles/build-websites/operation/work/font-awesome-guide-and-useful-tricks.html,Font Awesome アイコンの使い方と便利な機能のまとめ} にございますので、ご覧になってください。

それでは、次に CSS を見ていきましょう。 @<fn>{css_ugoki}
//footnote[css_ugoki][巻末の参考文献「動くWebデザインアイディア帳」より引用、適宜改変しています。]


//list[][header.css]{
/* ふわっと出現させるためのCSS
-----------------------------------------------------------------------------*/
.header.upward {
  position: fixed;
  animation: upwardAnimation 0.5s forwards;
}

/* ヘッダーが画面上部に上がって消えていく動き */
@keyframes upwardAnimation {
  from {
    opacity: 1;    transform: translateY(0);
  }
  to {
    opacity: 0;    transform: translateY(-100px);
  }
}

.header.downward {
  position: fixed;
  animation: downwardAnimation 0.5s forwards;
}

/* ヘッダーが画面上部から下に現れてくる動き */
@keyframes downwardAnimation {
  from {
    opacity: 0;    transform: translateY(-100px);
  }
  to {
    opacity: 1;    transform: translateY(0);
  }
}
//}

このCSSで把握しておきたいのは、「CSS アニメーション」 です。突然メニューが現れ、突然消えるのではなく、余韻を持たせるかのように、ゆっくりと表示され、そして消えていくようにしています。

ヘッダーが現れる動きを見ていきましょう。
@<code>{animation: downwardAnimation 0.5s} と書き、@<code>{0.5秒}かけて @<code>{downwardAnimation} を実行します。

@<code>{downwardAnimation} には、アニメーションの開始時(@<code>{from})には、@<code>{opacity: 0; transform: translateY(-100px);} ですので、透明で上に隠れている状態です。アニメーション終了時(@<code>{to})には、@<code>{opacity: 1; transform: translateY(0);} となり、鮮明に姿を現わします。

@<href>{https://developer.mozilla.org/ja/docs/Web/CSS/CSS_Animations/Using_CSS_animations,CSS アニメーションの使用} や @<href>{https://developer.mozilla.org/ja/docs/Web/CSS/animation,animation} に詳しい説明がございますので、ご覧になって下さい。

それでは、JavaScript を見ていきましょう。

//list[][navigation.js][1]{
const fixedAnimationForHeaderMenu = () => {
  // スクロール量を取得
  let scroll = $(window).scrollTop();

  // 300px以上、スクロールしたら
  if (scroll >= 300) {
    // ヘッダーを表示
    $(".header").removeClass("hidden");
    $(".header").addClass("shown");
    // 上から現れるよう、動きのためのクラス名を付与
    $(".header").removeClass("upward");
    $(".header").addClass("downward");
  }
  // そうでなければ
  else {
    // 画面上部に消えていく動きのためのクラス名を付与
    $(".header").removeClass("downward");
    $(".header").addClass("upward");
  }
}

// スクロールイベント発火で、fixedAnimationForHeaderMenu を呼ぶ。
$(window).scroll(fixedAnimationForHeaderMenu);
//}

最後の23行目で、画面スクロールされた時に 関数 @<code>{fixedAnimationForHeaderMenu} が呼ばれるようにしています。1行目から20行目までは、実際に呼ばれる@<code>{fixedAnimationForHeaderMenu}関数の定義が書かれています。スクロール量を取得、もし300px以上スクロールしていたら、メニュー出現のためのクラス名を付与し、そうでなければ、消失用のクラス名を付与するという、分かりやすいコードです。

//note[補足説明]{
全画面のヒーローイメージ表示との兼ね合いで HTMLで @<code>{<header class="hidden">} と書いています。@<code>{.hidden { display: none; \}} と非表示にしておき、スクロールしたら @<code>{class="hidden"} を取り除き、@<code>{class="shown"} を付与しています。@<code>{.shown { display: grid; \}} ですので、ヘッダーメニューが表示されるようになります。
//}




//note[新しい関数の書き方 アロー関数のご紹介]{
//blankline
**@<ruby>{ECMAScript,エクマ スクリプト**}

JavaScriptは、@<ruby>{Ecma International,エクマ インターナショナル}（旧欧州電子計算機工業会 European Computer Manufacturers Association）によって仕様が定められています。第一版から始まり、第五版の ECMAScript 5th edition(ES5)まで順調に機能向上が図られてきました。そして仕様に大きな変更が加えられ、ECMAScript 2015(ES2015) と呼ばれるようになりました(グレゴリオ暦に因んだ命名で、二千十五版ではありません)。それ以降、毎年行われる様々な仕様の追加が行われ、ES2016,ES2017...、となります。

//blankline
**アロー関数**

ES2015において、新しい関数の書き方「アロー関数」が導入されました。 @<fn>{namae} @<fn>{arrow}
//footnote[namae][@<code>{ => } が、「矢印、アロー」に見えるので。]

//list[][新しく導入されたアロー関数]{
// アロー関数
const add = (a, b) => {
  return a + b;
}
//}

比較のために、従来の関数宣言も掲載します。
//list[][従来の関数宣言]{
// 従来の関数宣言
function add(a, b) {
  return a + b;
}
//}

使い方はどちらも同じで、次のようにして結果を表示できます。

//list[][関数の呼び出し]{
// 関数の呼び出しと結果の表示
const answer = add(9, 23);
alert(answer);
//}

//blankline
**従来の関数と アロー関数への 変形**

JavaScriptの関数は、「第一級オブジェクト」と呼ばれる関数を変数に代入できる性質を持ちます。
ですので、次のように 変数 @<code>{add} に 関数 @<code>{tashizan}を代入して使うことができます。
//list[][]{
// 変数 add に 関数tashizanを代入する
const add = function tashizan(a, b) {
  return a + b;
}

// 関数の呼び出しと結果の表示
const answer = add(9, 23);
alert(answer);
//}

変数 @<code>{add} に代入して呼び出すことができるのであれば、わざわざ 関数に @<code>{tashizan}
と命名する必要も無いので、名前を省けます（「無名関数」と言います）。

//list[][]{
// 変数 add に 無名関数を代入する
const add = function (a, b) {
  return a + b;
}
//}

@<code>{function} と毎回書くのも文字が長いので省略して、代わりに @<code>{ => } を @<code>{ () } の次に書きます。

//list[][アロー関数の完成]{
const add = (a, b) => {
  return a + b;
}
//}

//blankline

始めての方には、@<code>{function} というキーワードの存在が分かりやすいかと思いますが、関数を簡単に定義できるよう「アロー関数」が導入されました。従来の関数とは細かい動作の面で差違がございますが、これからの主流として広く用いられていますので、ぜひ使ってみてください。
//}

//footnote[arrow][@<href>{https://developer.mozilla.org/ja/docs/Web/JavaScript/Reference/Functions/Arrow_functions,アロー関数式}]
---
== 光りながら出現する文字

//sideimage[shine][80mm][sep=5mm,side=R]{
キャッチフレーズを光るように出現させるために @<code>{CSSアニメーション機能} を使います。そして、手書きでコードを記述するのは大変なので、支援するための @<code>{JavaScript}を自分で書いて行きます。 @<fn>{css_ugoki}

コードの解説も行いましたので、参考にしていただければ幸いです。
//}

それでは準備です。HTMLの @<code>{<head>}内に CSS を、@<code>{</body>}の直前に @<code>{<script>} を書き、必要な JavaScript ファイルを読み込みます。

//list[][index.html]{
<head>
  <link rel="stylesheet" href="glow-text.css">
</head>

<body>
  <h1 class="glow text">Best place to visit in the world</h1>

  <!-- jQuery -->
  <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.1/jquery.min.js"></script>
  <!-- glow text-->
  <script src="glow-text.js"></script>
</body>
//}

CSS は次のようになります。@<fn>{css_ugoki}

//footnote[css_ugoki][巻末の参考文献「動くWebデザインアイディア帳」より引用、適宜改変しています。]


//list[][glow-text.css]{
/* 文字を光りながら出現させるためのCSS
-----------------------------------------------------------------------------*/
.glow.text span {
  opacity: 0;
}

/* アニメーションで透過度を0から1に変化させ、text-shadowをつける */
.glow.text.shine span {
  animation: glow_anime_on 1s ease-out forwards;
}

@keyframes glow_anime_on {
    0% { opacity:0; text-shadow: 0 0    0 #fff, 0 0    0 #fff; }
   50% { opacity:1; text-shadow: 0 0 10px #fff, 0 0 15px #fff; }
  100% { opacity:1; text-shadow: 0 0    0 #fff, 0 0    0 #fff; }
}
//}

先に紹介したCSSアニメーションを使い、文字の周りに白い影をつけることで、あたかも光っているように見えるという仕組みです。

さらに順番に光っているように見せたいので、次のように

//list[][]{
<h1 class="glow text shine">
  <span style="animation-delay: 0.0s;">B</span>
  <span style="animation-delay: 0.1s;">e</span>
  <span style="animation-delay: 0.2s;">s</span>
  <span style="animation-delay: 0.3s;">t</span>
</h1>
//}

と一文字ずつ @<code>{animation-delay} を付けると、光りながら文字が出現します。

CSS アニメーションの仕組みが分かったところで、次は JavaScript の出番です。
//list[][]{
<h1 class="glow text">Best place to visit in the world</h1>
//}
と書かれた一文字ずつを取り出して、@<code>{<span style="animation-delay:.0s;">B</span>} のようにしたいのですが、手作業で行うのは大変です。生産性向上のために、次のコードを用意しましょう。

//list[][glow-text.js][1]{
// .glow.text に shineクラス名を付与する関数定義
const addShineClassName = () => {
  let $element = $(".glow.text");
  $element.each(() => {
    let elemPosition = $element.offset().top - 50;
    let scroll       = $(window).scrollTop();
    let windowHeight = $(window).height();

    // .glow.text要素の位置までスクロールされたなら、shineクラスを付与する。
    if (scroll >= elemPosition - windowHeight) {
      $element.addClass("shine");
    } else {
      $element.removeClass("shine");
    }
  });
}

// 画面スクロール時に呼び出す関数を記述する
$(window).scroll(() => {
  addShineClassName();
});

// 画面が読み込まれた際に
// <h1 class="glow text">Best</h1>を
// <h1 class="glow text">
//   <span style="animation-delay:.0s;">B</span>
//   <span style="animation-delay:.1s;">e</span>
//   <span style="animation-delay:.2s;">s</span>
//   <span style="animation-delay:.3s;">t</span>
// </h1>
// にする関数
$(window).on('load', () => {
  //spanタグを追加する
  let $element = $(".glow.text");
  $element.each(() => {
    let text = $element.text();
    let textbox = "";
    text.split('').forEach((t, i) => {
      let delay = i / 10;
      textbox += `<span style="animation-delay:${delay}s;">${t}</span>`;
    });
    $element.html(textbox);
  });

  addShineClassName();
});
//}

前半は先ほどのメニュー表示の処理と良く似ていますので割愛して、32行目から解説していきましょう。

@<code>{$(window).on('load', () => {処理いろいろ\}} は、
「画像や動画など全ての読み込みが完了したら、『処理いろいろ』を実行する書き方です。
@<code>{() => {処理いろいろ\}} は、「無名関数」と呼ばれる関数で、先のアロー関数の紹介もお読みください。

34行目の右辺「@<code>{$(".glow.text")}」は、HTML内に書かれた @<code>{.glow.text"} クラスの要素を取得する jQuery での書きかたです。取得した要素は @<code>{$element} という変数で参照できるようにします。

35行目の @<code>{.each} は、@<code>{.each}メソッド（手続き・処理・手法）と呼ばれ、一つ一つを取り出して、処理を行うメソッドです。@<code>{.glow.text"} クラスを付与された要素が複数あった場合にも、一つ一つの要素ごとに処理を行って行きます。

36行目は、要素の中身（コンテンツ）を取り出して、@<code>{text}という変数に代入しています。
@<code>{$element}が @<code>{<h1>Best</h1>} の場合、@<code>{text} は @<code>{Best} となります。

それでは、この@<code>{Best}から、一文字ずつ取り出して、@<code>{<span style="animation-delay:.0s;">B</span>} のようにする処理を行っていきましょう。

37行目は、処理が終わったものを格納するための変数です。最初は処理が終わったものがないので、空っぽ(@<code>{''})です。

38行目から実際の処理を行います。@<code>{text.split('')}で、@<code>{split}という名前の通り、一文字ずつばらばらにされます。そして @<code>{.forEach((t, i)}へ送られます。@<code>{.forEach((t, i)}メソッドの@<ruby>{引数,ひきすう} @<code>{t}にはばらばらにされた文字一つ一つが渡されています（B, e, s, t と一文字ずつ渡されます）。@<code>{i}には何番目の文字であるかが渡されています（0, 1, 2, 3 と 0から数えます)。

39行目は、@<code>{delay} を算出しています。 @<code>{i / 10}ですので、順番に 0.0, 0.1, 0.2, 0.3 となります。

40行目です。@<code>{+=} は「自己代入演算子」です。一般にプログラミング言語では、@<code>{ age = age + 1} のように、自分自身の値に１を加えたものを、自分自身に代入することがよくあります。例えば、年齢(age)10歳の人は来年には11歳になります。このような処理は良く出てくるので、@<code>{ age = age + 1} を簡潔に書けるよう @<code>{ age += 1} という記法が用意されています。

同じく40行目の右辺を見ていきます。@<br>{}
@<code>{`<span style="animation-delay: ${delay\}s;">${t\}</span>`} は、@<br>{}
@<code>{ <span style="animation-delay:   0.0   s;">  B </span>} ととてもよく似ています。

違いを探すと、@<code>{${delay\}} が、@<code>{0.0} に @<code>{${t\}} が、@<code>{B} に変わっています。
変数 @<code>{delay} は、0.0, 0.1, 0.2, 0.3 と、変数 @<code>{t} は、B, e, s, t と変化します。
JavaScript では、「文字列リテラル」と呼ばれる「変数を文字列の中に埋め込み展開する」記法が用意されています。@<code>{`<span ${delay\} ${t\} </span>`} と、展開したい変数を文字列の中に埋め込むことで、楽に記述できます。
ちなみに 前後を囲んでいる記号 @<code>{`} は、「バッククォート」と呼ばれます。普段よく見かける @<code>{’}(クォーテーション) や @<code>{”}(ダブルクォーテーション)とは逆に、左上から右下に向きが傾いているので、「バッククォート」と呼ばれます。

42行目は、jQuery で、要素を書き換えるメソッドです。
@<code>{$elenet}が、
//list[][]{
<h1 class="glow text">
  Best
</h1>
//}
だったのが、
//list[][]{
<h1 class="glow text">
  <span style="animation-delay:.0s;">B</span>
  <span style="animation-delay:.1s;">e</span>
  <span style="animation-delay:.2s;">s</span>
  <span style="animation-delay:.3s;">t</span>
</h1>
//}
に書き変わります。
最後に45行目で、@<code>{class="glow text"} を @<code>{class="glow text shine"} と、クラス名を付与しています。

短いコードでしたが、いかがでしたでしょうか。
---
== 見出しの装飾

//sideimage[soushokumidashi][60mm][sep=5mm,side=R]{
せっかくですので、綺麗に見出しを装飾してみましょう。
簡単に CSS を書くだけで実現できます。
//}

HTMLはとても簡潔です。
//list[][index.html]{
<h2>最新記事</h2>
//}

CSS は次の通りです。
//list[][text.css]{
h2 {
  position: relative;
  padding: 1rem 1.5rem;
  box-shadow: 0 2px 14px rgba(0, 0, 0, .1);
}

h2:before,
h2:after {
  position: absolute;
  left: 0;
  width: 100%;
  height: 4px;
  content: '';
  background-image: linear-gradient(135deg,
                                    #704308 0%,
                                    #ffce08 40%,
                                    #e1ce08 60%,
                                    #704308 100%);
}

h2:before {
  top: 0;
}

h2:after {
  bottom: 0;
}
//}

こちらのコードは、
@<href>{https://jajaaan.co.jp/css/css-headline/,CSS見出しデザイン参考100選} からの引用です。


また、@<href>{https://saruwakakun.com/html-css/reference/h-design,CSSのコピペだけ！おしゃれな見出しのデザイン例まとめ68選} にも素敵なデザインが紹介されていますので、ご参考になさってください。
---
== 装飾的なボタンを作る
//sideimage[source_code_button][60mm][sep=5mm,side=R]{
従来はお絵描きソフトを使って作成していたボタンも、CSSで作成できるようになりました。
//}

//sideimage[page_top_button][60mm][sep=5mm,side=R]{
@<href>{https://jajaaan.co.jp/css/button/, CSSボタンデザイン120個以上！どこよりも詳しく作り方を解説！} というサイトにて、数多く紹介されておりますが、その中から、
グラデーションを使った綺麗なボタンと、金塊のように輝くボタンをご紹介します。
//}

#@# //image[source_code_button][][width=50%]
#@# //image[page_top_button][][width=33%]

#@# またボタンの文字サイズも画面幅に応じてレスポンシブにしたいものです。
#@# @<href>{https://www.amazon.co.jp/dp/4863542623/, 今すぐ使える CSS レシピブック}に、「レスポンシブな文字サイズ」という記事がございますので、併せてご紹介致します。

//list[][index.html]{
<a href="https://github.com/Atelier-Mirai/wave-improve" class="gradient button">
  <span>ソースコードはこちら</span>
</a>

<a href="#" class="gold button">
  <span><i class="fas fa-angle-double-up fa-lg fa-fw"></i>Page Top</span>
</a>
//}

@<code>{a}タグに、 @<code>{class="gradient button"}、@<code>{class="gold button"}とクラス名を付与して、実際の装飾は @<code>{CSS} でいろいろ行っていきます。

//list[][button.css]{
/*=====================================================================
  ボタンの為の装飾指定

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
  letter-spacing: 0.1em; /* 文字と文字の間を少し空ける */
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

/* グラデーションボタン
---------------------------------------------------------------------*/
.gradient.button {
  /* 背景色を桜色のグラデーションにする */
  background-image: linear-gradient(-20deg, #e9defa 0%, #f7cbea 100%);
}

/* マウスを重ねたときの指定 */
.gradient.button:hover {
  box-shadow: 0 5px 15px #bc33f5; /* ボタンに紫色の影を付ける */
}

/* 文字の色の指定 */
.gradient.button span {
  background: linear-gradient(   /* 虹色にする */
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

/* 金塊のようなボタン
---------------------------------------------------------------------*/
a.gold.button {
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
a.gold.button:hover {
  /* 上に 3px 空白を入れて、下の枠線を 3px 減らすことで、
     押してへこんだように見せる */
  margin-top: 3px;
  border-bottom: 7px solid #987c1e;
}
//}

== トップに戻るボタン

//sideimage[top][60mm][sep=5mm,side=R]{
トップに戻るボタンを実装してみましょう。

ボタンの装飾については先ほど扱いましたので、機能面について触れていきます。
//}


//list[][index.html]{
<head>
  <link rel="stylesheet" href="button.css">
  <link rel="stylesheet" href="page-top.css">
</head>

<body>
  <footer>
    <p id="page-top">
      <a href="#" class="gold button">
        <span><i class="fas fa-angle-double-up fa-lg fa-fw"></i>Page Top</span>
      </a>
    </p>
    &copy; WAVE
  </footer>

  <!-- jQuery -->
  <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.1/jquery.min.js"></script>
  <!-- page top -->
  <script src="page-top.js"></script>
</body>
//}
先に紹介したボタン装飾の為の @<file>{button.css} とトップに戻るボタンの為の @<file>{page-top.css} 、 そして @<file>{page-top.js} を読み込んでいます。 @<fn>{top_ugoki}

//footnote[top_ugoki][巻末の参考文献「動くWebデザインアイディア帳」より引用、適宜改変しています。]


//list[][page-top.css]{
/* 戻るボタンを右下に固定*/
#page-top {
  position: fixed;
  right: 10px;
  bottom:10px;
  z-index: 2000;
  /*はじめは非表示*/
  opacity: 0;
  transform: translateY(100px);
}

/* 上に上がる動き */
#page-top.upward {
  animation: upward-animation 0.5s forwards;
}
@keyframes upward-animation {
  from {
    opacity: 0;
    transform: translateY(100px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

/* 下に下がる動き */
#page-top.downward {
  animation: downward-animation 0.5s forwards;
}
@keyframes downward-animation {
  from {
    opacity: 1;
    transform: translateY(0);
  }
  to {
    opacity: 1;
    transform: translateY(100px);
  }
}
//}

@<code>{position: fixed;}を使って、戻るボタンを右下に固定しています。

「上に上がる動き」「下に下がる動き」は、**CSSアニメーション**機能を使っています。
@<code>{animation: upward-animation 0.5s forwards;} と書き、@<code>{upward-animation}を@<code>{0.5}秒間行っています。@<code>{upward-animation}は、@<code>{@keyframes upward-animation}で定義されたアニメーションです。@<code>{opacity: 0;}(透明)から@<code>{opacity: 1;}(不透明)まで変化します。

CSS アニメーション については、@<href>{https://developer.mozilla.org/ja/docs/Web/CSS/CSS_Animations/Using_CSS_animations,CSS アニメーションの使用} に詳しい説明がございます。ぜひご欄になってください。

//list[][page-top.js]{
// ウィンドウをスクロールした際の処理を、関数定義する。
//-----------------------------------------------------------------------
const pageTopAnimation = () => {
  // scroll という変数に、ウィンドウのスクロール量を取得して、代入する。
  let scroll = $(window).scrollTop();
  // もしスクロール量が200px以上ならば
  if (scroll >= 200){
    // #page-top に付与した downward というクラス名を除く
    $("#page-top").removeClass("downward");
    // #page-top に upward というクラス名を付与する
    $("#page-top").addClass("upward");

  // そうではなくて、もし #page-topに upward というクラス名が付与されていたら
  } else if ($("#page-top").hasClass("upward")){
    // upward というクラス名を除き
    $("#page-top").removeClass("upward");
    // downward というクラス名を#page-topに付与する
    $("#page-top").addClass("downward");
  }
}

// 画面をスクロールをした際にどの関数を呼ぶか記述する
//-------------------------------------------------------------------------
$(window).scroll(() => {
  pageTopAnimation();
});

// ページが読み込まれた際にどの関数を呼ぶか記述する
//-------------------------------------------------------------------------
$(window).on("load", () => {
  pageTopAnimation();
});

// #page-topをクリックした際の設定
//-------------------------------------------------------------------------
$("#page-top a").on("click", () => {
  $("body, html").animate(
    { scrollTop: 0 }, // ページトップまでスクロール
    500               // ページトップまで500msかけてスクロールする。
  );
  return false;       // リンク自体の無効化。
});
//}

#@# コメントを入れてございますので、お読みいただければと思います。

「トップに戻る」動作は、最後の @<code>{$("#page-top a").on("click", () => {...\}} で充分ですが、より魅力的になるよう、@<code>{jQuery}を使い「イベント」と呼ばれる特定の条件下でクラス名を付与するようにしています。そして、特定のクラス名が付与された際の様々な動きは、主に@<code>{CSSアニメーション機能}で行うようになっています。

#@# @<code>{jQuery}では「イベント」と呼ばれる特定の条件下でクラス名を付与するコードが中心となります。そして、特定のクラス名が付与された際の様々な動きは、主に@<code>{CSSアニメーション機能}が担っています。

#@# == ナビゲーションメニュー
#@# @<code>{html}は次のようになります。
#@# デスクトップ用とモバイル用、それぞれのナビゲーションメニューを作成します。 @<fn>{ugoki}
#@# @<small>{(共通のhtmlを使うこともできますが、実装が容易ですので、別々に作成しています。)}
#@#
#@# サイト名の左にロゴマークも付け、フォントアイコン(FontAwesome)を追加して、ナビゲーションメニューを豊かに彩っています。
#@#
#@# FontAwesome では @<code>{fa-lg}を使うと@<code>{1.33倍}に、@<code>{fa-2x}では @<code>{2倍}の大きさになります。@<code>{fa-fw}は 右に少し間隔が空きます。 @<href>{https://coliss.com/articles/build-websites/operation/work/font-awesome-guide-and-useful-tricks.html, 2021年最新版、Font Awesome アイコンの使い方と便利な機能のまとめ} に詳しく紹介されていますので、こちらもご参照下さい。
#@#
#@# //list[][index.html]{
#@# <head>
#@#   <link rel="stylesheet" href="navigation.css">
#@# </head>
#@#
#@# <body>
#@#   <!-- デスクトップ用ナビゲーションメニュー -->
#@#   <header id="desktop-header" class="hidden">
#@#     <div class="logo">
#@#       <img src="images/logo.png" alt="ロゴマーク">
#@#       <a href="index.html">WAVE</a>
#@#     </div>
#@#
#@#     <nav>
#@#       <ul>
#@#         <li>
#@#           <a href="index.html">
#@#             <i class="fas fa-home fa-lg fa-fw"></i>
#@#             トップ
#@#           </a>
#@#         </li>
#@#         <li>
#@#           <a href="about.html">
#@#             <i class="fab fa-pagelines fa-lg fa-fw"></i>
#@#             サイトについて
#@#           </a>
#@#         </li>
#@#         <li>
#@#           <a href="contact.html">
#@#             <i class="far fa-envelope fa-lg fa-fw"></i>
#@#             お問い合わせ
#@#           </a>
#@#         </li>
#@#       </ul>
#@#     </nav>
#@#   </header>
#@#
#@#   <!-- モバイル用ナビゲーションメニュー -->
#@#   <header id="mobile-header" class="hidden">
#@#     <!-- ハンバーガーメニュー -->
#@#     <div class="open-button">
#@#       <!-- CSS で spanタグをハンバーガーの線に変える -->
#@#       <span></span>
#@#       <span></span>
#@#       <span></span>
#@#     </div>
#@#
#@#     <!-- ナビゲーションメニュー -->
#@#     <nav>
#@#       <ul id="mobile-menu">
#@#         <!-- (デスクトップ用と同じ) -->
#@#       </ul>
#@#     </nav>
#@#   </header>
#@#
#@#   <!-- jQuery -->
#@#   <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.1/jquery.min.js"></script>
#@#   <!-- navigation -->
#@#   <script src="navigation.js"></script>
#@# </body>
#@# //}
#@#
#@# @<code>{<header id="desktop-header" class="hidden">} と、書かれています。@<code>{class="hidden"}とありますが、CSS内で最初はナビゲーションメニューを非表示にしています。(Vegasを使って全画面のヒーローイメージを表示させているため)。その後、スクロール操作がされたことを、 @<code>{jQuery}で検知し、ナビゲーションメニューを表示させるようにします。
#@#
#@# モバイルメニューについても同様ですが、@<code>{<span></span><span></span><span></span>}と三つの @<code>{span}を @<code>{CSS}を使って、三本線のハンバーガーボタンにします。そして、ハンバーガーボタンが押されたときに、モバイルメニューを表示させるようにします。
#@#
#@# //list[][navigation.css]{
#@# /*=======================================================================
#@#   デスクトップ用メニューのためのCSS
#@# =======================================================================*/
#@#
#@# /* ヘッダーを上部に固定させるためのCSS
#@# -----------------------------------------------------------------------*/
#@# #desktop-header {
#@#   /* ヘッダー位置を上部に固定するためのCSS */
#@#   position: fixed;
#@#   top: 0;
#@#   left: 0;
#@#   height: 70px;
#@#   z-index: 999;
#@#   width: 100vw;
#@#
#@#   /* ヘッダーレイアウト用CSS */
#@#   background: var(--sakurairo);
#@#   font-size: 40px;
#@#   color: #555d6b;
#@#   text-shadow: 5px 5px 5px gray;
#@#
#@#   /* ロゴと文字を並べる */
#@#   display: grid;
#@#   grid-template-columns: auto 1fr;
#@#   grid-template-rows: 58px;
#@# }
#@#
#@# #desktop-header div.logo {
#@#   grid-column: 1;
#@#   grid-row: 1;
#@#   justify-self: start;
#@#   padding-left: 5vw;
#@#   width: 240px;
#@# }
#@#
#@# #desktop-header div.logo img {
#@#   width: 40px;
#@#   height: 40px;
#@#   margin-right: 5px;
#@#   vertical-align: bottom;
#@# }
#@#
#@# #desktop-header div.logo a {
#@#   color: var(--amairo);
#@#   text-decoration: none;
#@# }
#@#
#@# #desktop-header div.logo a:hover {
#@#   color: var(--utsushiiro);
#@# }
#@#
#@# #desktop-header nav {
#@#   grid-column: 2;
#@#   grid-row: 1;
#@#   padding-right: 5vw;
#@# }
#@#
#@# #desktop-header nav li a {
#@#   text-decoration: none;
#@#   min-width: 64px;
#@# }
#@#
#@# #desktop-header nav li a i {
#@#   margin-right: 3px;
#@# }
#@#
#@#
#@# /* ふわっと出現させるためのCSS
#@# -----------------------------------------------------------------------*/
#@# #desktop-header.upward {
#@#   position: fixed;
#@#   animation: upwardAnimation 0.5s forwards;
#@# }
#@#
#@# /* ヘッダーが画面上部に上がって消えていく動き */
#@# @keyframes upwardAnimation {
#@#   from {
#@#     opacity: 1;
#@#     transform: translateY(0);
#@#   }
#@#   to {
#@#     opacity: 0;
#@#     transform: translateY(-100px);
#@#   }
#@# }
#@#
#@# #desktop-header.downward {
#@#   position: fixed;
#@#   animation: downwardAnimation 0.5s forwards;
#@# }
#@#
#@# /* ヘッダーが画面上部から下に現れてくる動き */
#@# @keyframes downwardAnimation {
#@#   from {
#@#     opacity: 0;
#@#     transform: translateY(-100px);
#@#   }
#@#   to {
#@#     opacity: 1;
#@#     transform: translateY(0);
#@#   }
#@# }
#@#
#@# /* ヘッダーの表示、非表示のためのCSS
#@# -----------------------------------------------------------------------*/
#@# #desktop-header.hidden {
#@#   display: none;
#@# }
#@# #mobile-header.hidden {
#@#   display: none;
#@# }
#@# .shown {
#@#   display: grid;
#@# }
#@#
#@# /*=======================================================================
#@#   モバイル用メニューのためのCSS
#@# =======================================================================*/
#@#
#@# /* ボタン全体の形のためのCSS */
#@# .open-button {
#@#   display: none;
#@#   position: fixed;
#@#   top: 10px;
#@#   right: 10px;
#@#   z-index: 999;
#@#   background: var(--nibiiro);
#@#   cursor: pointer;
#@#   width: 50px;
#@#   height: 50px;
#@#   border-radius: 5px;
#@# }
#@#
#@# /* 個々の線のためのCSS */
#@# .open-button span {
#@#   display: inline-block;
#@#   transition: all .4s;
#@#   position: absolute;
#@#   left: 14px;
#@#   height: 3px;
#@#   border-radius: 2px;
#@#   background: var(--sakurairo);
#@#   width: 45%;
#@# }
#@#
#@# .open-button span:nth-of-type(1) {
#@#   top: 15px;
#@# }
#@# .open-button span:nth-of-type(2) {
#@#   top: 23px;
#@# }
#@# .open-button span:nth-of-type(3) {
#@#   top: 31px;
#@# }
#@#
#@# /* activeクラスを付与した後の設定 */
#@# .open-button.active span:nth-of-type(1) {
#@#   top: 18px;
#@#   left: 18px;
#@#   transform: translateY(6px) rotate(-45deg);
#@#   width: 30%;
#@# }
#@# .open-button.active span:nth-of-type(2) {
#@#   opacity: 0;
#@# }
#@# .open-button.active span:nth-of-type(3) {
#@#   top: 30px;
#@#   left: 18px;
#@#   transform: translateY(-6px) rotate(45deg);
#@#   width: 30%;
#@# }
#@#
#@# /* ボタンの出現アニメーション */
#@# .appearance {
#@#   animation-name: appearance-animation;
#@#   animation-duration: 0.5s;
#@#   animation-fill-mode: forwards;
#@#   opacity: 0;
#@#   display: block;
#@# }
#@#
#@# @keyframes appearance-animation {
#@#   from {
#@#     opacity: 0;
#@#     transform: translateY(-100px);
#@#   }
#@#   to {
#@#     opacity: 1;
#@#     transform: translateY(0);
#@#   }
#@# }
#@#
#@# #mobile-menu.active {
#@#   /* 固定位置にして全画面表示 */
#@#   position: fixed;
#@#   top: 0;
#@#   left: 0;
#@#   width: 100%;
#@#   height: 100%;
#@#   /* Page Top を 2000 にしているのでそれより前面に */
#@#   z-index: 3000;
#@#
#@#   /* 余韻を残して切り替わるように */
#@#   transition: all 0.4s;
#@#
#@#   /* 背景色の設定など */
#@#   background: var(--sakurairo);
#@#   display: grid;
#@#   grid-template-rows: 4rem 4rem 4rem;
#@#   grid-auto-flow: row;
#@#   justify-content: center;
#@# }
#@#
#@# #mobile-menu.active li a:first-child {
#@#   margin-top: 4rem;
#@# }
#@#
#@# #mobile-menu.active li a {
#@#   font-size: 18px;
#@#   letter-spacing: 0.3rem;
#@#   color: var(--shinonomeiro);
#@# }
#@#
#@# #mobile-menu.active li a {
#@#   text-shadow: 2px 2px var(--nanohanairo);
#@# }
#@#
#@# #mobile-menu.active li a i {
#@#   font-size: 20px;
#@#   color: var(--kyohiiro);
#@# }
#@# //}
#@#
#@# //list[][navigation.js]{
#@# // アニメーション関数(デスクトップ用)を定義する
#@# const fixedAnimationForDesktop = () => {
#@#   // スクロール量を取得
#@#   let scroll = $(window).scrollTop();
#@#
#@#   // 300px以上、スクロールしたら
#@#   if (scroll >= 300) {
#@#     // ヘッダーを表示
#@#     $("#desktop-header").removeClass("hidden");
#@#     $("#desktop-header").addClass("shown");
#@#     // 上から現れるよう、動きのためのクラス付与
#@#     $("#desktop-header").removeClass("upward");
#@#     $("#desktop-header").addClass("downward");
#@#   }
#@#   // そうでなければ
#@#   else {
#@#     // 画面上部に消えていく動きのためのクラス付与
#@#     $("#desktop-header").removeClass("downward");
#@#     $("#desktop-header").addClass("upward");
#@#     // ヘッダーを非表示
#@#     $("#desktop-header").removeClass("shown");
#@#     $("#desktop-header").addClass("hidden");
#@#   }
#@# }
#@#
#@# // アニメーション関数（モバイル用）を定義する
#@# const fixedAnimationForMobile = () => {
#@#   // スクロール量を取得
#@#   let scroll = $(window).scrollTop();
#@#
#@#   // 300px以上、スクロールしたら
#@#   if (scroll >= 300) {
#@#     $("#mobile-header").removeClass("hidden");
#@#     $(".open-button").addClass("appearance");
#@#   }
#@#   // そうでなければ
#@#   else {
#@#     $("#mobile-header").addClass("hidden");
#@#     $(".open-button").removeClass("appearance");
#@#   }
#@# }
#@#
#@# // 画面幅を取得
#@# let windowWidth = $(window).width();
#@#
#@# // 画面がスクロールときに、メニュー表示を行う
#@# if (windowWidth <= 768) {
#@#   // モバイル版のメニュー表示
#@#   $(window).scroll(fixedAnimationForMobile);
#@#   // ハンバーガーボタンをクリックした際の処理
#@#   $(".open-button").on("click", () => {
#@#     $(".open-button").toggleClass("active");
#@#     $("#mobile-menu").toggleClass("active");
#@#   });
#@#   // リンクをクリックした際の処理
#@#   $("#mobile-menu li a").on("click", () => {
#@#     $(".open-button").removeClass("active");
#@#     $("#mobile-menu").removeClass("active");
#@#     $(".open-button").removeClass("appearance");
#@#   });
#@# } else {
#@#   // デスクトップ版のメニュー表示
#@#   $(window).scroll(fixedAnimationForDesktop);
#@# }
#@# //}
#@#
#@# //blankline
#@#
#@# //sideimage[menu][100mm][sep=5mm,side=R]{
#@# 完成したメニュー
#@# //}
#@# //blankline
#@# //sideimage[mobile_menu][60mm][sep=5mm,side=R]{
#@# 完成した iPhone用 メニュー
#@# //}
