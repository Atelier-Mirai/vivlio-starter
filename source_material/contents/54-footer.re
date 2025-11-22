= 様々なフッターの装飾

//abstract{
この章では、様々なフッターの装飾を行っていきます。

 * 文字のグラデーション
 * 可変の文字サイズ
 * グラデーションで背景画像を彩る
 * 菱形のナビゲーションメニュー
 * スムーズスクロール

//}

この章では、様々なフッターの装飾を行っていきます。
もともとのフッターは次のようでした。

//image[footer_wave][][width=90%,border=on]

立派にフッターの役目は果たしていますが、作成者のただ一行のみで淋しい気がいたします。
ロゴやナビゲーションメニュー、住所や電話番号なども載せ、彩り豊かに機能強化を図りましょう。

//image[footer][][width=90%]

== 文字のグラデーション

//sideimage[nijiiro][60mm][sep=5mm,side=R]{

右のように虹色の文字を作成することもできます。

@<href>{https://1-notes.com/css-text-design/,CSSでテキストを彩る装飾サンプル集} を参考に実装していきましょう。
//}

//list[][index.html]{
<span>WAVE</span>
//}

//list[][index.html]{
<span>WAVE</span>
//}

//list[][logo.css]{
span {
  color: transparent;
  background: repeating-linear-gradient(45deg,
    #e60012 0.1em 0.2em,
    #f39800 0.2em 0.3em,
    #fff100 0.3em 0.4em,
    #009944 0.4em 0.5em,
    #0068B7 0.5em 0.6em,
    #1d2088 0.7em 0.8em,
    #cfa7cd 0.8em 0.9em);
  -webkit-background-clip: text; /* Chrome での表示用 */
  background-clip: text;
  font-weight: bold;
  letter-spacing: 10px;
}
//}

簡単な HTML と CSS で実装できます。他にも様々な装飾例が掲載されていますので、ご参考になれば幸いです。

== 可変の文字サイズ

端末の画面幅によって、文字の大きさを変更したい。そういった場面もあるかと思います。
少し前にはなりますが、「今すぐ使える CSS レシピブック」という書籍には以下のように紹介されております。

=== メディアクエリを使う方法

//list[][css]{
p {
  font-size: 12px;
}

@media (min-width:320px) {
  p {
    font-size: calc((24 - 12) * ((100vw - 320px) / (960 - 320)) + 12px);
  }
}

@media (min-width: 960px) {
  p {
    font-size: 24px;
  }
}
//}

画面幅320pxで最小値が12px、画面幅960pxで最大値24pxを取るのは明確です。
画面幅320px〜960pxで、徐々に拡大する為に @<code>{calc}関数を使い、フォントサイズを計算します。
@<code>{calc}関数の@<ruby>{引数,ひきすう} @<code>{(24 - 12) * ((100vw - 320px) / (960 - 320))} について説明します。

画面幅が 320pxから960pxまで 640px 増えた際に、フォントサイズは 12px から 24px まで 12px 増加します。
つまり、@<br>{}
画面幅が160px増えたならば、フォントサイズ3px増加させ、@<br>{}
画面幅が320px増えたならば、フォントサイズ6px増加させ、@<br>{}
画面幅が480px増えたならば、フォントサイズ9px増加させるように、比例配分すれば良いのです。

@<code>{100vw}で現在の画面幅が取得できますので、@<code>{(100vw - 320px)}で画面幅の増分が得られます。
これを、@<code>{(960 - 320)} で割ることで、画面幅の増分が占める640pxへの割合が得られますので、@<code>{(24 - 12)}に掛けることで、フォントサイズを何ピクセル大きくすればよいかが得られます。
これに最小値の @<code>{12px} を足せば、現在の画面幅 @<code>{100vw} で指定すべきフォントサイズが得られます。

//image[graph1][][width=80%]

=== @<code>{clamp}関数を使う方法

メディアクエリを使ってレスポンシブサイズを実現できましたが、少し面倒でした。
@<href>{https://developer.mozilla.org/ja/docs/Web/CSS/clamp,@<code>{clamp()}}関数を使うと、より簡便に実現できます。

//quote{
//noindent
clamp() は CSS の関数で、値を上限と下限の間に制限します。 clamp() によって、定義された最大値と最小値の間の値を選択することができます。最小値、推奨値、最大値の3つの引数を取ります。
//}

使い方は次のように使います。

//list[][]{
p {
  font-size: clamp(最小値, 推奨値, 最大値);
}
//}

最小値は@<code>{12px}、最大値は@<code>{24px} ですが、推奨値はどのように記述すれば良いでしょうか。

画面幅に応じて変化する単位として @<code>{vw} があります。@<code>{1vw} は画面幅の @<code>{1%}を表します。

ここでは、画面幅 @<code>{640px} の時に フォントサイズ @<code>{18px} になるようにしましょう。
@<code>{18 / 640 = 2.8%} なので 次のCSSで実現できそうです。

//list[][]{
p {
  font-size: clamp(12px, 2.8vw, 24px);
}
//}

コードが書けたので、ブラウザで確認してみます。画面幅に応じて @<code>{<p>} タグのフォントサイズが変化し、美味く実装できているようですが、少し最小値や最大値の点で違いもあることが分かります。

最小値 12px になるときの画面幅を計算すると、 @<code>{12px / 2.8vw * 100 = 428px}となります。

最大値 24px になるときの画面幅を計算すると、 @<code>{24px / 2.8vw * 100 = 857px}となります。

//image[graph2][][width=80%]

メディアクエリ版と完全に等価ではありませんが、簡単に実装できるので使ってみてください。

== グラデーションで背景画像を彩る

@<href>{https://www.webcreatorbox.com/tech/css-gradient,美しいグラデーションをCSSで実装} というサイトがございます。こちらを参考に写真とグラデーションを重ね合わせ、フッターの背景にします。

//image[haikei1][元の背景画像][width=70%]
//image[haikei2][淡いグラデーション][width=70%]
//image[haikei3][重ね合わせた背景][width=70%]

//list[][footer.css]{
footer {
  background: linear-gradient(45deg, #2ca9e128, #ffec4760) fixed,
              url('sea.webp') 75% 75%;
  background-size: cover;
  width: 100vw;
}
//}

簡単に実現できますので、よろしければお使いください。

== 菱形のナビゲーションメニュー

//sideimage[footer_nav][60mm][sep=5mm,side=R]{
それでは、最後に菱形のナビゲーションメニューを創っていきましょう。

まずは、HTML を書いていきます。
//}

//list[][index.html]{
<nav>
  <ul>
    <li><a href="index.html"><i class="fa-solid fa-house-chimney"></i></a></li>
    <li><a href="#kiji">     記事  <br>一覧  </a></li>
    <li><a href="#about">    会社  <br>案内  </a></li>
    <li><a href="#contact">  お問い<br>合わせ</a></li>
  </ul>
</nav>
//}

いたって普通のナビゲーションメニューです。
Font Awesome を使い、@<code>{<i class="fa-solid fa-house-chimney"></i>} で家のアイコンを表示させ、
ページ内リンクとして @<code>{#kiji}、@<code>{#about}、@<code>{#contact} を設定しています。

//list[][footer.css]{
nav ul {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  grid-template-rows: 1fr;
  gap: 25px;

  list-style: none;
  padding: 0;
}
//}
CSS は、まず @<code>{display: grid;}とし、 @<code>{<ul>} をコンテナ（箱）にし、グリッドアイテムである@<code>{<li>} を横に四つ並べます。

//list[][footer.css]{
nav ul li {
  display: grid;
  grid-template-columns: 64px;
  grid-template-rows: 64px;

  background-color: var(--kurohairo);

  transform: rotate(45deg);
}
//}
@<code>{<li>} 要素ですが、内包する @<code>{<a>} 要素の為のコンテナとなることができます。
列、行ともに64px の グリッドを設定します。そして背景色を黒羽色にし、45度回転させます。
一辺64pxの正方形の対角線の長さは約90pxですから、90px × 4 = 360px の幅を持つナビゲーションメニューができます。

//list[][footer.css]{
nav ul li a {
  justify-self: center;
  align-self: center;

  color: var(--sakurairo);
  font-size: 14px;
  text-decoration: none;
  text-align: center;

  transform: rotate(-45deg);
}
//}
次に @<code>{<a>}要素です。グリッドアイテムとなっていますので、<@<code>{justify-self: center; align-self: center;} で、グリッドトラックの中央に配置します。
文字色や文字サイズなどの調整を行います。
そして、このままですと、文字も45度傾いたままですので、 @<code>{transform: rotate(-45deg);} で逆方向に回転させ、文字が水平になるようにします。


//list[][footer.css]{
nav ul li:hover {
  background: var(--botaniro);
}
//}
最後に @<code>{hover}させた際の色を指定して、CSS は完了です。

== スムーズスクロール

@<code>{<a href="#kiji">記事</a>} として、ページ内リンクを設定できます。
クリックすると、 @<code>{<h2 id="kiji">記事</h2>} に跳びます。

このときに「瞬間移動」するのではなく、滑らかにスクロールさせたいものです。
様々な手法がありますが、ここでは簡便な方法として、smooth scroll polyfills を使った方法をご紹介します。

//list[][index.html]{
<html>
  <head>
    <!-- Smooth Scroll -->
    <script src="https://cdn.jsdelivr.net/npm/smooth-scroll@16.1.3/dist/smooth-scroll.polyfills.min.js"></script>
  </head>

  <body>
    <!-- (略) -->

    <!-- Smooth Scroll -->
    <script>
      let scroll = new SmoothScroll('a[href*="#"]', { easing: 'easeInOutQuint' });
    </script>
  </body>
</html>
//}

@<code>{<head>}内に、CDN から スクリプトを取得するよう記述します。
そして、 @<code>{</body>} の直前に、一行コードを記述するのみで完了です。

//blankline
「polyfills」という名称の通り、もともと一部のブラウザでのCSSの挙動を補正するための JavaScript でした。
今春より全てのブラウザでCSSのみでスムーススクロールができるようになっています。
//blankline
@<href>{https://developer.mozilla.org/ja/docs/Web/CSS/scroll-behavior,scroll-behavior} として、MDN に 解説もございますので、よろしければご覧になってください。
