= スクロールしたら要素を表示させる

//abstract{
  スクロールに伴い、見出しや画像などがされると、動きがある印象深いサイトになります。
  CSS と JavaScript を使って、実現していきます。
//}

== HTML
//sideimage[scroll_animation][80mm][sep=5mm,side=R]{
@<href>{http://noze.space/archives/415, スクロールしたらフワッと要素を表示させるスクリプトの使い勝手を良くしてみる} を元に適宜改変いたしました。作例例は右のようになります。緑色の箱が並んでいるだけでございますので、@<href>{https://wave-improve.netlify.app/scroll_animation/index.html,動作例}をごらんになってください。また @<href>{https://github.com/Atelier-Mirai/wave-improve/tree/master/scroll_animation,ソースコード} もございます。

詳しい解説が元のサイトにございますので、ここでは、HTML / CSS / JavaScript それぞれのソースコードを掲載するのみで、説明は割愛いたします。

簡単に実装できますので、是非、お使いになってみてください。
//}

//list[][index.html]{
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>スクロールでフワッと要素表示</title>

    <!-- 簡単に見栄えの良いページを作るためのスタイルシート -->
    <link rel="stylesheet" href="https://unpkg.com/sakura.css/css/sakura.css">
    <!-- スクロールアニメーション用のスタイルシートなど -->
    <link rel="stylesheet" href="scroll_animation.css">
  </head>

  <body>
    <section>
      <h1>スクロールしたらフワッと要素を表示させる</h1>
      <p><a href="http://noze.space/archives/415">
          http://noze.space/archives/415 より引用改変</a></p>

      <div class="sa up">要素1<br>up</div>
      <div class="sa down">要素2<br>down</div>
      <div class="sa up"   data-sa_delay="400">要素3<br>up<br>400</div>
      <div class="sa down" data-sa_delay="400">要素4<br>down<br>400</div>
      <div class="sa up"   data-sa_delay="600">要素5<br>up<br>600</div>
      <div class="sa down" data-sa_delay="600">要素6<br>down<br>600</div>
      <div class="sa up"   data-sa_delay="800">要素7<br>up<br>800</div>
      <div class="sa down" data-sa_delay="800">要素8<br>down<br>800</div>
      <div class="sa ltr">要素9<br>ltr</div>
      <div class="sa rtl">要素10<br>rtl</div>
      <div class="sa ltr" data-sa_delay="800">要素11<br>ltr<br>800</div>
      <div class="sa rtl" data-sa_delay="800">要素12<br>rtl<br>800</div>
      <div class="sa up" id="elem13">要素13<br>up<br>#elem13</div>
      <div class="sa up" data-sa_trigger="#elem13">
        要素14<br>up<br>trigger13
      </div>
      <div class="sa up" data-sa_trigger="#elem13" data-sa_delay="800">
        要素15<br>up<br>trigger13<br>800
      </div>
      <div class="sa scale_up">要素16<br>scale_up</div>
      <div class="sa scale_down">要素17<br>scale_down</div>
      <div class="sa rotate_l" id="elem18">要素18<br>ratate_l</div>
      <div class="sa rotate_r">要素19<br>ratate_r<br>trigger18</div>
      <div class="sa rotate_r" data-sa_delay="800">
        要素20<br>ratate_r<br>trigger18<br>800
      </div>
    </section>

    <!-- スクロールアニメーション用のスクリプトを読み込む -->
    <script src="scroll_animation.js"></script>
  </body>
</html>
//}

== CSS

//list[][]{
/* sakura.css 補正 */
body { max-width: 90vw; }

/* グリッドレイアウトで、div要素を配置する */
section {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
  gap: 20px;
  margin-bottom: 200px;
}
h1, p { grid-column: 1 / -1; }

div { background: #c0f4c7; height: 200px;
      font-size: 24px; text-align: center; }

/* sa(スクロールアニメーション)用のクラス指定 */
.sa         { opacity: 0; transition: all .5s ease; }
.sa.show    { opacity: 1; transform: none; }
.ltr        { transform: translate(-100px, 0); }
.rtl        { transform: translate(100px, 0); }
.up         { transform: translate(0, 100px); }
.down       { transform: translate(0, -100px); }
.scale_up   { transform: scale(.5); }
.scale_down { transform: scale(1.5); }
.rotate_l   { transform: rotate(180deg); }
.rotate_r   { transform: rotate(-180deg); }
//}

== JavaScript
//list[][]{
const scroll_animation_class      = 'sa';
const scroll_animation_show_class = 'show';
const trigger_margin_dafault      = 300;

let scroll_animation_elements
  = document.querySelectorAll(`.${scroll_animation_class}`);

let scroll_animation_function = function () {
  // 表示タイミング位置を指定
  // 例) data-sa_margin="200"
  // その要素が画面の下から200px上に上がって来たら表示する
  let data_margin  = `${scroll_animation_class}_margin`;
  // 表示タイミングの基準の要素を指定
  // 例) data-sa_trigger="#elem1"
  // #elem1の出現と同時に、その要素も表示させる
  let data_trigger = `${scroll_animation_class}_trigger`;
  // 表示タイミング時間を指定
  // 例) data-sa_delay="500"
  // 500ms 後にその要素を表示する
  let data_delay   = `${scroll_animation_class}_delay`;

  // saクラスの要素を対象に処理を行う
  for(let i = 0; i < scroll_animation_elements.length; i++){
    let elm = scroll_animation_elements[i];

    // もしdata-sa_marginに値があれば、その数値に置き換える
    let trigger_margin = trigger_margin_dafault;
    if (elm.dataset[data_margin] != null) {
      trigger_margin = parseInt(elm.dataset[data_margin]);
    }

    // data-sa_trigger属性に値があれば指定の要素、
    // 無ければその要素自身の位置を判定基準にする
    let show_position = 0;
    if (elm.dataset[data_trigger]) {
      show_position
        = document
            .querySelector(elm.dataset[data_trigger])
            .getBoundingClientRect()
            .top + trigger_margin;
    } else {
      show_position = elm.getBoundingClientRect().top + trigger_margin;
    }

    // data-sa_delay があれば、その時間だけずらして表示する。
    if (window.innerHeight > show_position) {
      let delay = (elm.dataset[data_delay]) ? elm.dataset[data_delay] : 0;
      setTimeout(function(index) {
        scroll_animation_elements[index].classList
                                    .add(scroll_animation_show_class);
      }.bind(null, i), delay);
    }
  }
}

// イベントリスナ
window.addEventListener('load',   scroll_animation_function);
window.addEventListener('scroll', scroll_animation_function);
//}
