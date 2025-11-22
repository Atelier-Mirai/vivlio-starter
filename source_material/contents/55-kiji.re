= 記事ページの機能拡張

//abstract{

この章では、写真をセピア調にする / 枠を付ける / タブ機能 / 続きを読むボタン について、実装していきます。
//}

== 写真をセピア調にする / 枠を付ける

//sideimage[kiji_shashin_sepia][90mm][sep=5mm,side=R]{

「思い出」の写真のように、セピア調にして枠を付けてみましょう。

簡単な HTML と CSS だけで実現できます。

少し前の記事ですが、@<href>{https://taneppa.net/css3_01/,CSS3】で写真に色々装飾を加えてみた} が参考になります。
//}

//list[][post01.html]{
<figure class="sepia rotate-3 frame">
  <img src="images/note.webp" alt="いろいろなスケッチを書き込んだノート">
</figure>
//}

//list[][frame.css]{
/* 写真をセピア調にする */
.sepia.frame img {
  filter: sepia(90%);
}

/* 枠を付ける */
.frame {
  border: solid 8px var(--sakurairo); /* 桜色の枠線を付けます */
  box-shadow: 0 0 0 1px #ccc,         /* 箱に灰色と黒い影を付けます */
              1px 3px 8px 0 #25252555;
  margin-bottom: 0.5em;               /* 下に少し間隔を取ります */
}

/* 写真を右上に少し回転する */
.rotate-3 {
  transform: rotate(-3deg)
}
//}

@<code>{<figure>}は、写真の他、プログラムコードや詩など、独立した図版を示すタグです。 @<code>{class="sepia rotate-3 frame"} とクラス名を付与し、CSS で装飾を行っていきます。

//blankline

色の変更は、@<code>{filter}プロパティで行えます。
//quote{
//noindent
filter は CSS のプロパティで、ぼかしや色変化などのグラフィック効果を要素に適用します。フィルターは画像、背景、境界の描画を調整するためによく使われます。CSS 標準に含まれているものは、定義済みの効果を実現するためのいくつかの関数です。
//}
ぼかしや輝度、コントラストなどさまざまな調整を行うことができます。
@<href>{https://developer.mozilla.org/ja/docs/Web/CSS/filter,filter} に丁寧な説明や実例がございますので、ご覧ください。

//blankline
写真の枠は、@<code>{border}プロパティで行っています。 @<code>{box-shadow}プロパティで影もつけて、雰囲気を出しています。

//blankline
写真を少し傾けることは、@<code>{transform}プロパティで行っています。
//quote{
//noindent
transform は CSS のプロパティで、与えられた要素を回転、拡大縮小、傾斜、移動することできます。これは、 CSS の視覚整形モデルの座標空間を変更します。
//}
@<href>{https://developer.mozilla.org/ja/docs/Web/CSS/transform,transform} に丁寧な説明や実例がございますので、ご覧ください。

== タブ機能

//sideimage[kiji][90mm][sep=5mm,side=R]{
  タブ機能を使うと、コンパクトに画面内に納めることが出来ます。

  タブ機能は、一つは「見出し」部分、もう一つはその「内容」部分と二つの部品から構成されます。

  見出しが選択されると、それに対応する内容の部分を表示し、それ以外の内容の部分を非表示にするのが基本的な仕組みです。
//}

タブ機能のための HTML は次のようになります。

//list[][]{
<!-- タブの見出し部分 -->
<ul class="tab menu">
  <li><a href="#midori" class="active">緑のアクセント</a></li>
  <li><a href="#komono">小物と飾り棚</a></li>
</ul>

<!-- タブの内容部分 -->
<article id="midori" class="tab segument active">
  <h1>緑のアクセントならこれ</h1>
  <!-- (略) -->
</article>

<article id="komono" class="tab segument">
  <h1>小物と飾り棚の組み合わせ</h1>
  <!-- (略) -->
</article>
//}

CSS は 次のようになります。
見出し部分 は @<code>{active} クラスの有無で色を変えるように、
内容部分 は @<code>{active} クラスの有無で表示・非表示を変えるようにします。

//list[][]{
/* 見出し部分 */
.tab.menu li a {
  display: block;
  background: var(--natsukazeiro);
}

.tab.menu li.active a {
  background: var(--sakurairo);
}

/* 内容部分 */
.tab.segument {
  display: none;
}

.tab.segument.active {
  display: block;
}
//}

そして、 @<code>{<a href="#midori">}と、 見出しがクリックされた際に、このアンカータグから、 @<code>{#midori} を取得し、 @<code>{<article id="komono">} に @<code>{active} クラスを付与することで、内容部分を表示させる役割を担っているのが、次の JavaScript です。

//list[][]{
// 任意のタブにURLからリンクするための関数
const showSegumentByHashLink = (locationHashLink) => {
  if (!locationHashLink) { return false; } // 引数が与えられないときは戻る。

  // タブ設定
  $('.tab.menu li').find('a').each(function() { // タブ内のaタグ全てを取得
    let id = $(this).attr('href');              // aタグのhref属性値を取得
                                                // (=表示させたいタブセグメントのID)

    // もしaタグのhref属性が、リンク元の指定されたURLのハッシュリンクと等しければ、
    if(id === locationHashLink){
      let containingElement = $(this).parent(); // タブ内のaタグの親要素liを取得
      $('.tab.menu li').removeClass("active");  // タブ内のliに付与された
                                                // activeクラスを取り除く
      $(containingElement).addClass("active");  // liにactiveクラスを付与
      $(".tab.segument").removeClass("active"); // タブセグメントのactiveクラスを取り除く
      $(locationHashLink).addClass("active");   // activeクラスを付与
    }
  });
}

// タブをクリックした際に、以下が実行される。
$('.tab.menu a').on('click', function() {
  let id  = $(this).attr('href'); // リンクのhref属性を取得
                                  // (=表示させたいタブセグメントのID)
  showSegumentByHashLink(id);     // タブセグメントを表示する
  return false;                   // aタグをクリックした際の通常動作
                                  // (リンク先へのジャンプ)を無効にする。
});

// ページ読み込み完了時に、以下が実行される。
$(window).on('load', () => {
  let locationHashLink = location.hash;     // URLのフラグメント識別子(ハッシュリンク)を取得
  showSegumentByHashLink(locationHashLink); // 設定したタブセグメントの読み込み
});
//}

== 続きを読む機能

@<href>{https://copypet.jp/502/,コピペでできる！CSSとhtmlのみで作る「続きを読む」の開閉ボタン} を元に実装します。


//list[][]{
<figure class="readmore-box">
  <input type="checkbox" id="readmore-01">
  <label for="readmore-01"></label>
  <div class="readmore-container">
    <p>
      サボテン（仙人掌、覇王樹）は、サボテン科に属する植物の総称である。
    </p>
    <!-- (略) -->
  </div>
</article>
//}

チェックボックスと、ラベルの関係に着目してください。

何も CSS が適用されていないときには、@<code>{<input type="checkbox" id="readmore-01">}, @<code>{<label for="readmore-01"></label>} とあるように、チェックボックスが表示されているだけです。（ラベル部分の文字をクリックすることでも、チェックボックスのオンオフを切り替えることが出来ますが、ラベルの文字が空なので押せなくなっています。）

//list[][]{
.readmore-box {
  position: relative;
}

.readmore-box label {
  position: absolute;
  z-index: 1;
  bottom: 0;
  width: 100%;
  height: 140px; /* グラデーションの高さ */
  cursor: pointer;
  text-align: center;
  /* 以下グラデーションは背景を自身のサイトに合わせて設定してください */
  background: linear-gradient(to bottom, rgba(254, 244, 244, 0) 0%, rgba(254, 244, 244, 0.95) 100%);
}

.readmore-box input:checked + label {
  background: inherit; /* 開いた時にグラデーションを消す */
}

.readmore-box label::after {
  line-height: 2.5rem;
  position: absolute;
  z-index: 2;
  bottom: 20px;
  left: 50%;
  width: 16rem;
  font-family: "Font Awesome 5 Free";
  content: "\f13a  続きを読む";
  font-weight: bold;
  transform: translate(-50%, 0);
  letter-spacing: 0.05em;
  border-radius: 20px;

  /* https://coco-factory.jp/ugokuweb/wp-content/themes/ugokuweb/data/1-6/1-6.html#Flower より グラデーション ボタン */
  border-color: transparent;
  color: var(--sakurairo);
  background: linear-gradient(270deg,#3bade3 0%, #9844b7 50%, #44ea76 100%);
  background-size: 200% auto;
  background-position: right center;
  box-shadow: 0 5px 10px rgba(250, 108, 159, 0.4);
}

.readmore-box input {
  display: none;
}

.readmore-box .readmore-container {
  overflow: hidden;
  height: 250px; /* 開く前に見えている部分の高さ */
  transition: all 0.5s;
}

.readmore-box input:checked + label {
  /* display: none ; 閉じるボタンを消す場合解放 */
}

.readmore-box input:checked + label:after {
  font-family: "Font Awesome 5 Free";
  content: "\f139  閉じる";
  font-weight: bold;
}

.readmore-box input:checked ~ .readmore-container {
  height: auto;
  padding-bottom: 80px; /* 閉じるボタンのbottomからの位置 */
  transition: all 0.5s;
}
//}

装飾も入っていますので、長いCSSと成っています。

 * @<code>{.readmore-box label {\}} で、ラベルの高さ（=グラデーションの高さ）を設定する。
 * @<code>{.readmore-box input:checked + label {\} } で、チェックされたときにグラデーションを消す。
 * @<code>{.readmore-box label::after {\}} で、疑似要素を使って何もなかったラベルをボタンの形に整形する。

と、少しずつ追って行くと良いです。装飾に関する部分を割愛すると理解しやすいでしょう。

ポイントとなるのは、@<code>{input:checked + label} と、隣接セレクタを使ったCSSの部分で、これにより JavaScript を用いることなく HTML / CSS のみで 続きを読む機能を実現しています。
