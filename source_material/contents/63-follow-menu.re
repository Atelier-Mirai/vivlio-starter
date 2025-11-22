= 追随メニュー

//abstract{
  画面右にあってスクロールに関わらず、ずっと存在しているメニューです。
  CSS のみで実現します。
//}

== HTML
#@# //sideimage[fixed_footer][80mm][sep=5mm,side=R]{
@<href>{https://gar-den.jp/, 注文住宅なら京都市で設計施工を行う工務店 garDEN} を元に適宜改変いたしました。 下の作成例のように、画面下にメニューが配置されます。@<href>{https://wave-improve.netlify.app/follow_menu/index.html,動作例}をごらんになってください。また @<href>{https://github.com/Atelier-Mirai/wave-improve/tree/master/follow_menu,ソースコード} もございます。

//image[follow_menu][][width=60%]

iPad や Mac など比較的大きな画面を持つ端末向けのデザインですので、画面幅によって、CSS の適用を制御する必要がありますが、ここでは簡単化のために、割愛してございます。
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
<!-- Follow Menu  -->
<link rel="stylesheet" href="follow_menu.css">
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

<nav class="follow_menu">
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

<!-- jQuery -->
<script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.1/jquery.min.js"></script>
<!-- Smooth Scroll -->
<script src="https://cdn.jsdelivr.net/npm/smooth-scroll@16.1.3/dist/smooth-scroll.polyfills.min.js"></script>
<script>
let scroll = new SmoothScroll('a[href*="#"]', { easing: 'easeInOutQuint' });
</script>
</body>
</html>

//}

先ほどの「固定フッター」とほぼ同じHTMLです。
追随メニューは、フッターではないので@<code>{<footer id="fixed_footer">}が無くなりました。そして CSS から扱いやすいよう、 @<code>{<nav class="follow_menu">} とクラス名を付与しています。

== CSS

//list[][fixed_footer.css][1]{
.follow_menu {
  position: fixed;
  right: 40px;
  bottom: 40px;
  z-index: 10000;
}

.follow_menu ul {
  list-style: none;
}

.follow_menu ul li {
  display: block;
  box-sizing: border-box;
  width: 100px;
  height: 100px;
  border-radius: 50%;
  position: relative;
}

.follow_menu ul li:nth-child(1) {
  background: #e7609e; border: 1px solid #e7609e; } /* 牡丹色 */
.follow_menu ul li:nth-child(2) {
  background: #67a70c; border: 1px solid #67a70c; }  /* 早苗色 */
.follow_menu ul li:nth-child(3) {
  background: #3d6eda; border: 1px solid #3d6eda;  } /* 移色 */
.follow_menu ul li:nth-child(4) {
  background: #a61017; border: 1px solid #a61017;  } /* 紅葉色 */

.follow_menu ul li a {
  font-size: 1.5rem;
  text-align: center;
  text-decoration: none;
  color: #fef4f4; /* 桜色 */
  display: block;
  box-sizing: border-box;
  padding: 20px 10px;
  line-height: 20px;
  position: relative;

  /* sakura.css の干渉補正 */
  border-bottom: none;
}

.follow_menu ul li a:hover::after {
  opacity: 1;
  border-width: 7px;
}

.follow_menu ul li a::after {
  content: "";
  display: block;
  width: 98px;
  height: 98px;
  border: 0 solid #fef4f4; /* 桜色 */
  border-radius: 50%;
  position: absolute;
  left: 0;
  top: 0;
  box-sizing: border-box;
  opacity: 0;
  transition-property: all;
  transition-duration: 0.3s;
  transition-timing-function: ease;
}

//}

機能面でのポイントとしては、まず、先頭に書かれた @<code>{.follow_menu { position: fixed; \}} が挙げられます。これによりスクロールに関わらず位置を固定して表示されます。

21行目の@<code>{.follow_menu ul li:nth-child(1)} 以下で、それぞれのボタンに対し、色を設定しています。

15-17行目で、 @<code>{100px} の円のボタンにしていますが、45-56行目で @<code>{98px}と少し小さめの円を用意することで、 @<code>{:hover}の際に 桜色の枠線が現れるようにしています。

== 縦書きにする

せっかくの文学作品ですので、縦書きにしたいと思われる方もいらっしゃると思います。

//list[][]{
p {
  writing-mode: vertical-rl;
}
//}

で、簡単に縦書きにすることができます。

少し前の記事とはなりますが、@<href>{https://www.webcreatorbox.com/tech/writing-mode,日本らしさを表現 CSSで文字の縦書きに挑戦} により詳しい解説がございますので、ご参考にしていただければと思います。
