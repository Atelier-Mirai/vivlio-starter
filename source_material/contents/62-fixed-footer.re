= 固定フッター

//abstract{
  iPhoneアプリでよくあるように画面下にメニューを配置します。
  CSS と JavaScript を使って、実現していきます。
//}

== HTML
#@# //sideimage[fixed_footer][80mm][sep=5mm,side=R]{
@<href>{https://gar-den.jp/, 注文住宅なら京都市で設計施工を行う工務店 garDEN} を元に適宜改変いたしました。 下の作成例のように、画面下にメニューが配置されます。@<href>{https://wave-improve.netlify.app/fixed_footer/index.html,動作例}をごらんになってください。また @<href>{https://github.com/Atelier-Mirai/wave-improve/tree/master/fixed_footer,ソースコード} もございます。

//image[fixed_footer][][width=60%]

モバイル端末に向いたデザインですので、画面幅によって、CSS / JavaScript の適用を制御する必要がありますが、ここでは簡単化のために、割愛してございます。
#@# //}

//list[][index.html][1]{
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Fixed Footer</title>
<!-- Font Awesome -->
<link rel="stylesheet" href="https://use.fontawesome.com/releases/v6.2.0/css/all.css">
<!-- 簡単に見栄えの良いページを作るためのスタイルシート -->
<link rel="stylesheet" href="https://unpkg.com/sakura.css/css/sakura.css">
<!-- Fixed Footer  -->
<link rel="stylesheet" href="fixed_footer.css">
</head>

<body>
<h1><a href="index.html">文學堂</a></h1>

<section>
  <h2><ruby>文學紹介</h2>
  <p class="lead text">文學堂では古今の様々な作家による名作を紹介しています。</p>

  <article id="pora-no">
    <h3>ポラーノの広場 宮沢賢治</h3>
    <p>そのころわたくしは、モリーオ市の博物局に勤めて居りました。</p>
  </article>

  <article id="botchan">
    <h3>坊ちゃん 夏目漱石</h3>
    <p>親譲りの無鉄砲で小供の時から損ばかりしている。</p>
  </article>

  <article id="toshishun">
    <h3>杜子春 芥川龍之介</h3>
    <p>或春の日暮です。</p>
  </article>

  <article id="takasebune">
    <h3>高瀬舟 森鷗外</h3>
    <p>高瀬舟は京都の高瀬川を上下する小舟である。</p>
  </article>
</section>

<footer id="fixed_footer">
  <nav>
    <ul>
      <li><a href="#pora-no">
          <i class="fa-solid fa-book fa-lg"></i><br>
          ポラーノの広場</a></li>
      <li><a href="#botchan">
          <i class="fa-solid fa-calendar-days fa-lg"></i><br>
          坊ちゃん</a></li>
      <li><a href="#toshishun">
          <i class="fa-solid fa-house-chimney fa-lg"></i><br>
          杜子春</a></li>
      <li><a href="#takasebune">
          <i class="fa-solid fa-ship fa-lg"></i><br>
          高瀬舟</a></li>
    </ul>
    <div class="telephone">
      <a href="tel:052-373-4649">
        <i class="fa-solid fa-phone"></i>
        電話をかける<small>9:00～18:00 / 日曜祝日休</small>
        052-373-4649
      </a>
    </div>
  </nav>
</footer>

<!-- jQuery -->
<script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.1/jquery.min.js"></script>
<!-- Fixed Footer -->
<script src="fixed_footer.js"></script>

<!-- Smooth Scroll -->
<script src="https://cdn.jsdelivr.net/npm/smooth-scroll@16.1.3/dist/smooth-scroll.polyfills.min.js"></script>
<script>
let scroll = new SmoothScroll('a[href*="#"]', { easing: 'easeInOutQuint' });
</script>
</body>
</html>
//}

画面下部のボタンをクリックした際に、各文学作品にスクロールするようにします。
文学作品の @<code>{<p>}タグはもう少し必要ですが、紙幅の関係で割愛しています。

作品紹介、メニュー項目を用意し、必要な CSS / JavaScript を読み込むという、分かりやすい HTML と成っています。

== CSS

//list[][fixed_footer.css][1]{
#fixed_footer {
  position: fixed;
  width: 100%;
  z-index: 1000;
  transition-property: all;
  transition-duration: 0.3s;
  transition-timing-function: ease;
  transition-delay: 0.3s;
}

/* 最初は電話をかけるを下に隠しておく */
#fixed_footer { bottom: -95px; }
/* 電話をかけるが上に現れる */
#fixed_footer.active { bottom: 0; }

#fixed_footer.active span {
  display: inline-block;  margin: 6px 0; }

/* CSS Grid で ボタン項目を並べる */
#fixed_footer nav ul {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  grid-auto-flow: column;

  overflow: hidden;
  margin: 0 -1px;
  padding: 0;
  list-style: none;
}

#fixed_footer nav ul li a {
  vertical-align: middle;
  text-align: center;
  text-decoration: none;
  display: block;
  background: #0d0d0d;
  padding-top: 12px;
  color: #fef4f4;
  font-size: 11px;
  height: 60px;
  border-left: 1px solid #fef4f4;
  position: relative;
}

#fixed_footer nav ul li a span {
  display: inline-block;
  margin: 12px 0;
}

#fixed_footer nav ul li a::after {
  content: "";
  display: block;
  border: 15px solid transparent;
  border-left-color: #ffec47;
  border-top-color: #ffec47;
  width: 0;
  height: 0;
  position: absolute;
  left: 0;
  top: 0;
}

#fixed_footer nav .telephone {
  background: #0d0d0d;
  text-align: center;
  border-top: 1px solid #fef4f4;
}

#fixed_footer nav .telephone a {
  color: #fef4f4;
  text-decoration: none;
  width: 100%;
  display: inline-block;
  padding: 10px;
}

#fixed_footer nav .telephone a small {
  display: block;
  font-size: 9px;
}

/* sakura.css による干渉を補正 */
#fixed_footer { width: 100%; left: 0; }
li {  margin-bottom: 0; }
a:hover { border: none; }
//}

少し長いCSSで恐縮ですが、大半は形を整えるためのものです。

//blankline
機能面でのポイントとしては、まず、先頭に書かれた @<code>{#fixed_footer { position: fixed; \}} が挙げられます。これによりスクロールに関わらず画面下部に固定して表示されます。

また、作成例では隠れていますが、ある程度スクロールすると、「電話をかける」ためのリンクも出現します。それを実現しているのが、11-14行目です。 @<code>{active}クラスの有無で位置を調整するようにしています。

19行目からは、CSS Grid Layout を使って、ボタン項目を並べています。

53-55行目では、ボタン項目の装飾として黄色の三角形を作成しています。

== JavaScript

//list[][fixed_footer.js][1]{
/* 150px以上のスクロールで activeクラスを付与 電話をかける を表示させる
---------------------------------------------------------------------*/
let fixed_footer = () => {
  const $fixed_footer = $('#fixed_footer');
  const trigger_position = 150;
  let   current_position = $(this).scrollTop();

  if (current_position > trigger_position) {
    $fixed_footer.addClass('active');
  } else {
    $fixed_footer.removeClass('active');
  }
}

/* 画面スクロールやページ読み込みの際に fixed_footer 関数を呼ぶ
---------------------------------------------------------------------*/
$(window).scroll(() => { fixed_footer(); });
$(window).on("load", () => { fixed_footer(); });
//}

スクロール量を取得し、 @<code>{active} クラスを付与するという、簡潔なスクリプトです。
