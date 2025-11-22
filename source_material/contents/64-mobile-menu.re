= モバイルメニュー

//abstract{
  iPhone のためのモバイルメニューの実装です。
  CSS と JavaScript を使って実現します。
//}

== HTML
#@# //sideimage[fixed_footer][80mm][sep=5mm,side=R]{
巻末の参考文献「作って学ぶHTML&CSSモダンコーディング」を元に適宜改変しております。下の作成例のように、画面右上にボタンが配置され、これを押すとメニューが開きます。@<href>{https://wave-improve.netlify.app/mobile_menu/index.html,動作例}をごらんになってください。また @<href>{https://github.com/Atelier-Mirai/wave-improve/tree/master/mobile_menu,ソースコード} もございます。

//image[mobile_menu12][][width=60%]

#@# //}

//list[][index.html][1]{
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Mobile Menu</title>
<meta name="viewport" content="width=device-width">

<!-- Font Awesome -->
<link rel="stylesheet"
      href="https://use.fontawesome.com/releases/v6.2.0/css/all.css">
<!-- 簡単に見栄えの良いページを作るためのスタイルシート -->
<link rel="stylesheet" href="https://unpkg.com/sakura.css/css/sakura.css">
<!-- ハンバーガーボタン -->
<link rel="stylesheet" href="hamburgers.css">
<!-- モバイルメニュー用のスタイルシート -->
<link rel="stylesheet" href="mobile_menu.css">
</head>

<body>
<header class="header">
  <h1><a href="index.html">文學堂</a></h1>

  <!-- https://jonsuh.com/hamburgers/ の例 -->
  <button class="navbtn hamburger hamburger--spin">
    <span class="hamburger-box">
      <span class="hamburger-inner"></span>
    </span>
  </button>

  <!-- ナビゲーションメニュー -->
  <nav class="nav">
    <ul>
      <li><a href="#pora-no">
          <i class="fa-solid fa-book fa-lg fa-fw"></i>ポラーノの広場</a></li>
      <li><a href="#botchan">
          <i class="fa-solid fa-calendar-days fa-lg fa-fw"></i>坊ちゃん</a></li>
      <li><a href="#toshishun">
          <i class="fa-solid fa-house-chimney fa-lg fa-fw"></i>杜子春</a></li>
      <li><a href="#takasebune">
          <i class="fa-solid fa-ship fa-lg fa-fw"></i>高瀬舟</a></li>
    </ul>
  </nav>
</header>

<!-- 文學紹介 -->
<section>
  <h2>文學紹介</h2>
  <p class="lead text">文學堂では古今の作家による名作を紹介しています。</p>

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

<!-- ハンバーガーボタンを押されたら、ナビゲーションメニューを開く -->
<script src="mobile_menu.js"></script>
<!-- Smooth Scroll -->
<script src="https://cdn.jsdelivr.net/npm/smooth-scroll@16.1.3/dist/smooth-scroll.polyfills.min.js"></script>
<script>
  let scroll = new SmoothScroll('a[href*="#"]', { easing: 'easeInOutQuint' });
</script>
</body>
</html>
//}

//sideimage[humburgers][80mm][sep=5mm,side=R]{
先ほどとほぼ同じHTMLです。変更点として@<code>{<header>}にハンバーガーメニューのための@<code>{<button>}を追加しています。

ハンバーガーの作成方法はいろいろありますが、ここでは @<href>{https://jonsuh.com/hamburgers/,Tasty CSS-animated hamburgers} というサイトで提供されているものを使うことにします。

ボタン開閉効果として十七種類が用意されています。ハンバーガーが回転しながら×印に変化していく @<code>{spin} を使いたいので @<code>{<button class="hamburger hamburger--spin">} と書いています。

使用法の紹介もなされておりますのでお好みに合わせてご利用下さい。
//}


== CSS

//list[][mobile_menu.css][1]{
/* ヘッダー */
.header {
  display: grid;
  grid-template-columns: 1fr 70px;
  grid-template-rows: 100px;
}

/* ナビゲーションメニュー */
.header .nav {
  position: fixed;
  inset: 0 -100% 0 100%;  /* 画面右外に移動 */
  transition: transform 0.3s;
  background: #0d0d0ddd;  /* 黒羽色 */

  display: grid;
  align-items: center;
}

.header .nav ul {
  list-style: none;
  padding: 0;

  display: grid;
  gap: 40px;
  justify-content: center;
  align-items: center;
  text-align: center;
}

.header .nav ul a {
  font-size: larger;
  color: #ffec47; /* 菜の花色 */
}

/* メニュー開放時 */
.open .navbtn { z-index: 100; }
.open .nav { transform: translate(-100%, 0); }

/* hamburgers.css のハンバーガーボタン色を上書き */
.hamburger-inner,
.hamburger-inner::before,
.hamburger-inner::after {
  background: #a61017; /* 京緋色 */
}

.hamburger.is-active .hamburger-inner,
.hamburger.is-active .hamburger-inner::before,
.hamburger.is-active .hamburger-inner::after {
  background: #2ca9e1; /* 天色 */
}

/* sakura.css の 干渉補正 */
.navbtn,
.navbtn:hover,
.navbtn:focus:enabled {
  background: transparent !important;
}
//}

ヘッダーやナビゲーションメニューを、CSS グリッドレイアウトを使って、配置します。

注目点は、まず 11行目の @<code>{inset: 0 -100% 0 100%;} です。ナビゲーションメニューを画面右外へと追いやることで、見えないようにしています。ハンバーガーボタンが押されると JavaScript により、@<code>{.open} クラスが付与されるので、37行目の @<code>{.open .nav { transform: translate(-100%, 0); \}} により、画面右側からメニューが現れる仕組みです。

ナビゲーションメニューの背景色は黒羽色、リンクの色は菜の花色、ハンバーガーボタンの色は京緋色と天色にしています。お好みで変更なさってください。

== JavaScript

//list[][mobile_menu.js][1]{
// ハンバーガーボタンが押された際に、メニューを表示する
document.querySelector('.navbtn.hamburger').addEventListener('click', () => {
  document.querySelector('html').classList.toggle('open');
  document.querySelector('.navbtn.hamburger').classList.toggle('is-active');
});

// ナビゲーションメニュー内のリンクがクリックされたときに、メニューを閉じる
document.querySelectorAll('nav a').forEach((link) => {
  link.addEventListener('click', () => {
    document.querySelector('html').classList.toggle('open');
    document.querySelector('.navbtn.hamburger').classList.toggle('is-active');
  });
});
//}

ハンバーガーボタンが押された際に、@<code>{open}クラスを付与することにより、メニューを表示します。
@<code>{is-active} クラスを付与することにより、ボタンの形状を、ハンバーガーから×へと変化します。

ナビゲーションメニュー内のそれぞれのリンクがクリックされたときに、メニューを閉じるようにします。
@<code>{open}クラスを取り除き、ボタン形状もハンバーガーへと変化させて、完了です。
