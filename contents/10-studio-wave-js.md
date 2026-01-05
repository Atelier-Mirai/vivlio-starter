# Wave Studio Js

:::{.chapter-lead}
この章では、Chapter 7・8 で作ってきた Wave Studio のトップページを題材に、実際のウェブサイトの中で <span id="idx-ufy6mn67o2id-65" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span> がどのように使われているかを見ていきます。

第9章では、変数・条件分岐・繰り返し・関数・DOM・イベントリスナといった文法を一通り学びました。この章では、その知識を使って「キラキラ光るキャッチコピー」と「先頭へ戻るボタン」という 2 つのしかけを読み解きます。

<span id="idx-5376xxg0dgl-107" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>・<span id="idx-3ghtaxxv1hvr-169" class="index-term" data-yomi="しーえすえす">CSS</span>・<span id="idx-ufy6mn67o2id-66" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span> がそれぞれどんな役割を持ち、どのように連携しているのかを、コードを追いながら確認していきましょう。
:::


## Wave Studio の <span id="idx-ufy6mn67o2id-67" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span> 概観

まずは `index.html` にどのように <span id="idx-ufy6mn67o2id-68" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span> が読み込まれているかを確認しましょう。

```html
<!-- 自分で作ったJavaScript -->
<script src="javascripts/glow_text.js" defer></script>
<script src="javascripts/page_top.js" defer></script>
```

- `glow_text.js`  
  ヒーローイメージの下にあるキャッチコピー `Best place to visit in the world` を、
  文字が一文字ずつキラキラと現れるように演出するスクリプトです。

- `page_top.js`  
  画面右下の「Page Top」ボタンを、スクロールに応じて出したり引っ込めたりするためのスクリプトです。

どちらにも `defer` 属性が付いています。`defer` は「<span id="idx-5376xxg0dgl-108" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span> の読み込みが終わってから <span id="idx-ufy6mn67o2id-69" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span> を実行する」という指定でした。これにより、

- まず <span id="idx-5376xxg0dgl-109" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span> と <span id="idx-3ghtaxxv1hvr-170" class="index-term" data-yomi="しーえすえす">CSS</span> でページの見た目を組み立て
- そのあとに <span id="idx-ufy6mn67o2id-70" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span> で「動き」や「インタラクション」を追加する

という流れになります。


## キラキラ光るキャッチコピー

最初に、トップページ中央のキャッチコピーに注目しましょう。

```html
<!-- キャッチフレーズ -->
<h1 class="glow text catch_phrase">
  Best place to visit in the world
</h1>
```

`class="glow text catch_phrase"` とあるように、この見出しには `glow` と `text` という 2 つのクラスが付いています。  
`glow_text.js` と `_text.css` は、この `.glow.text` をターゲットにして「光る文字」アニメーションを実現しています。


### <span id="idx-3ghtaxxv1hvr-171" class="index-term" data-yomi="しーえすえす">CSS</span>：.glow.text と shine クラス

まずは `stylesheets/_text.css` の該当部分です。

```css
/* 文字を光りながら出現させるためのCSS */
.glow.text {
  span {
    /* 初期値は透明 */
    opacity: 0;
  }

  &.shine span {
    /* アニメーションで透過度を0から1に変化させ、text-shadowをつける */
    animation: glow_anime_on 1s ease-out forwards;
  }
}

@keyframes glow_anime_on {
    0% { opacity:0; text-shadow: 0 0    0 #fff, 0 0    0 #fff; }
   50% { opacity:1; text-shadow: 0 0 10px #fff, 0 0 15px #fff; }
  100% { opacity:1; text-shadow: 0 0    0 #fff, 0 0    0 #fff; }
}
```

ポイントは次の 2 つです。

- `.glow.text span { opacity: 0; }`  
  `.glow.text` の中の各文字（後で `span` タグとして分解される）を、最初は見えないように透明にしておきます。

- `.glow.text.shine span { animation: glow_anime_on ... }`  
  `.glow.text` に `shine` クラスが付いたときだけ、アニメーションを適用します。

<span id="idx-3ghtaxxv1hvr-172" class="index-term" data-yomi="しーえすえす">CSS</span> は「shine クラスが付いたら光る」「各文字を個別にアニメーションできるようにしておく」ところまでを担当し、
**いつ shine クラスを付けるか・各文字のタイミングをどうずらすかは <span id="idx-ufy6mn67o2id-71" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span> 側が決めます。**


### <span id="idx-ufy6mn67o2id-72" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span>：テキストを 1 文字ずつ分解する

次に `javascripts/glow_text.js` の冒頭です。

```js
const DELAY_TIME = 0.25 // 一文字ずつの遅延時間

// .glow.text に shineクラス名を付与する関数定義
const addShineClassName = () => {
  let elements = document.querySelectorAll(".glow.text")
  elements.forEach((element, index) => {
    let elemPosition = element.getBoundingClientRect().top - 50
    let scroll       = window.scrollY
    let windowHeight = window.innerHeight

    // .glow.text要素の位置までスクロールされたなら、shineクラスを付与する。
    if (scroll >= elemPosition - windowHeight) {
      element.classList.add("shine")
    } else {
      element.classList.remove("shine")
    }
  })
}
```

`addShineClassName` 関数は、画面のスクロール位置と `.glow.text` の位置を比べて、

- `.glow.text` が画面内に入ってきたら `shine` クラスを付ける
- それ以外のときは `shine` クラスを外す

という仕事をします。

これにより、「見出しが画面内に現れたタイミングで、光るアニメーションを開始する」ことができます。


### <span id="idx-ufy6mn67o2id-73" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span>：load イベントで文字を分解する

続いて、ページ読み込み完了時の処理を見てみましょう。

```js
// ページ読み込み時、addShineClassName関数を実行するよう、イベントリスナを設定
window.addEventListener("load", () => {
  document.querySelectorAll(".glow.text").forEach((element, index) => {
    let text                = element.textContent.trim()
    let delay_initial_value = 0 + (index * text.length * DELAY_TIME)
    let textbox             = ""

    text.split("").forEach((t, i) => {
      let delay = delay_initial_value + i * DELAY_TIME
      textbox  += `<span style="animation-delay:${delay}s">${t}</span>`
    })

    element.innerHTML = textbox
  })

  addShineClassName()
})
```

やっていることを言葉で整理すると、次のようになります。

1. `.glow.text` 要素をすべて取得する。
2. 各要素について：
   - 表示テキスト（`Best place ...`）を `textContent` で取り出す。
   - `split("")` で 1 文字ずつの配列に分解する。
   - 各文字ごとに、`<span style="animation-delay:〇〇s">文字</span>` の <span id="idx-5376xxg0dgl-110" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span> を作る。
     - 文字の順番 `i` に応じて `animation-delay` を少しずつ増やし、
       一文字ずつ時間差で光り始めるようにしている。
   - 最後に `element.inner<span id="idx-5376xxg0dgl-111" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span> = textbox` で、元のテキストを
     「たくさんの `<span>` に分解されたテキスト」に置き換える。
3. 最後に `addShineClassName()` を呼び出し、最初の状態を反映する。

これで、<span id="idx-3ghtaxxv1hvr-173" class="index-term" data-yomi="しーえすえす">CSS</span> 側に用意しておいた `.glow.text.shine span` のアニメーションと組み合わさり、
**キャッチコピーの文字が、一文字ずつ順番にキラキラと現れる**ようになります。


## 先頭へ戻るボタン

次に、画面右下に表示される「Page Top」ボタンを見ていきましょう。

```html
<p id="page_top">
  <!-- 金色のボタン -->
  <a href="#" class="gold button">
    <span>
      <i class="fa-solid fa-angles-up fa-lg fa-fw"></i>
      <span class="desktop-only">Page Top</span>
    </span>
  </a>
</p>
```

`id="page_top"` が、先頭へ戻るボタン全体を囲む要素です。  
<span id="idx-3ghtaxxv1hvr-174" class="index-term" data-yomi="しーえすえす">CSS</span> と <span id="idx-ufy6mn67o2id-74" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span> は、この `#page_top` に対して「表示・非表示」と「アニメーション」を制御します。


### <span id="idx-3ghtaxxv1hvr-175" class="index-term" data-yomi="しーえすえす">CSS</span>：固定位置とアニメーション

まずは `stylesheets/_page_top.css` を見てみましょう。

```css
/* 戻るボタンを右下に固定*/
#page_top {
  position: fixed;
  right:   10px;
  bottom:  10px;
  z-index: 2000;
  opacity: 0; /*はじめは非表示*/
  transform: translateY(100px);

  /* 上に上がる動き */
  &.upward {
    animation: upward-animation 0.5s forwards;
  }

  /* 下に下がる動き */
  &.downward {
    animation: downward-animation 0.5s forwards;
  }
}
```

ここでは、

- `position: fixed; right: 10px; bottom: 10px;` で、ボタンを画面右下に固定
- 最初は `opacity: 0` と `translateY(100px)` で、画面の外（下）の方に隠しておく
- `upward` クラスが付いたときは「上にスッと現れる」アニメーション
- `downward` クラスが付いたときは「下へ引っ込む」アニメーション

という動きを <span id="idx-3ghtaxxv1hvr-176" class="index-term" data-yomi="しーえすえす">CSS</span> 側で用意しています。

さらに、`stylesheets/_smooth_scroll.css` では次の指定を行っています。

```css
/*=====================================================================
  スムーズスクロール
=====================================================================*/
html {
  scroll-behavior: smooth; /* ゆっくり遷移する */
  scroll-padding-top: 0px; /* 上に高さ0px空ける */
}
```

これにより、`<a href="#">` をクリックしてページ先頭に戻るとき、
一瞬でジャンプするのではなく、なめらかにスクロールするようになります。


### <span id="idx-ufy6mn67o2id-75" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span>：スクロール量に応じて出し入れする

最後に `javascripts/page_top.js` を見てみましょう。

```js
/*=====================================================================
 ウィンドウがスクロールした際
 先頭へ戻る要素の表示/非表示を行う
=====================================================================*/
const pageTopAnimation = () => {
  // scroll という変数に、ウィンドウのスクロール量を取得して、代入する。
  let scroll = document.querySelector("html").scrollTop
  // 先頭へ戻る要素を取得
  let page_top = document.querySelector("#page_top")

  // もしスクロール量が200px以上ならば
  if (scroll >= 200){
    // #page_top要素からdownwardクラスを削除する
    page_top.classList.remove("downward")
    // #page_top要素にupwardクラスを追加する
    page_top.classList.add("upward")

  // そうではなくて、もし#page_topに upwardクラスが付与されていたら
  } else if (page_top.classList.contains("upward")) {
    // #page_top要素からupwardクラスを削除する
    page_top.classList.remove("upward")
    // #page_top要素にdownwardクラスを追加する
    page_top.classList.add("downward")
  }
}

// スクロールイベント発火で pageTopAnimation 関数を呼ぶ
document.addEventListener("scroll", (event) => {
  pageTopAnimation()
})
```

ここでも、役割を整理してみましょう。

- `scroll` 変数に、今どれだけスクロールされたか（ピクセル単位）を代入する。
- `page_top` として、`#page_top` 要素を取得する。
- スクロール量が `200px` 以上なら：
  - `downward` クラスを外し、`upward` クラスを付ける。
  - → <span id="idx-3ghtaxxv1hvr-177" class="index-term" data-yomi="しーえすえす">CSS</span> 側の `upward-animation` が効いて、ボタンが下からふわっと現れる。
- 逆に `200px` 未満で、かつ `upward` が付いているとき：
  - `upward` クラスを外し、`downward` クラスを付ける。
  - → `downward-animation` が効いて、ボタンが下に引っ込んでいく。

そして最後の `document.addEventListener("scroll", ...)` で、

- ユーザーがスクロールするたびに `pageTopAnimation()` を呼び出す
- そのときのスクロール量に応じて、クラスを付け替える

という仕組みになっています。

## ヒーローイメージの<br>画像を切り替えてみよう

Wave Studio のトップページに出てくる海のヒーローイメージは 1 枚でもきれいですが、何枚か差し替わると「動画っぽさ」が出て、ぐっと印象が変わります。

ここでは、`work3/` をコピーして `work4/` を作り、`work4/images/sea01.webp`〜`sea07.webp` を使って、

- 画面いっぱいに広がるフェードスライドショー
- ある程度スクロールすると、画面上部に固定されるメニューバー

を実装してみました。

これを最初から自分だけでコーディングしても良いのですが、**AI に「こういう動きを作って」と頼んでしまう**のも 1 つのやり方です。大まかな仕様さえ伝えれば、AI が <span id="idx-ufy6mn67o2id-76" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span> と <span id="idx-3ghtaxxv1hvr-178" class="index-term" data-yomi="しーえすえす">CSS</span> のひな形を用意してくれます。

実際に本書の執筆でも、次のようなプロンプトを何度か投げながら実装を整えていきました。

**プロンプト例（実際に使ったものを整理したもの）**

- **Vegas 風スライドショーを作る**

  > studio-wave プロジェクトの `work3` をコピーして `work4` を作りました。`work4/images` に `sea01.webp`〜`sea07.webp` という縦長の海の写真を置いてあります。これらを使って、トップページの `.hero` 要素に Vegas 風の全画面スライドショーを実装してください。jQuery ではなくバニラ <span id="idx-ufy6mn67o2id-77" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span> で、画像をフェードで切り替えるようにしてほしいです。

- **ヒーロー画像を画面いっぱいに表示する**

  > いま実装したスライドショーの画像は 1920×1440 の縦長画像です。ヘッダー部分を除いた画面全体を覆うように、<span id="idx-3ghtaxxv1hvr-179" class="index-term" data-yomi="しーえすえす">CSS</span> を調整してください。縦横比は保ったまま、上下左右に余白が出ないようにしたいです。

- **スクロール後に固定ヘッダーを表示する**

  > `header` と `nav` をまとめた `.site-header` という要素を作り、最初は非表示にしておきたいです。200px くらいスクロールしたら、画面上部に固定表示されて、フェード＋少し下にスライドして現れるようにしてください。<span id="idx-ufy6mn67o2id-78" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span> からスクロール量を見てクラスを付け替える実装をお願いします。

- **画像のファイルサイズを軽くする**

  > `work4/images/sea01.webp`〜`sea07.webp` のファイルサイズが大きくて読み込みが重いので、ImageMagick の `mogrify` コマンドを使って、横幅 1080px・quality 70% に一括リサイズする方法を教えてください。元ファイルを上書きして構いません。

このように、

- 「どのフォルダに」「どんなファイル名で」「どのように表示したいか」

を文章で伝えるだけで、AI がかなりの部分まで形にしてくれます。あとはブラウザで動きを確認しながら、

- 「もう少しゆっくり切り替えてほしい」
- 「スマホのときだけ文字サイズを小さくしたい」

といった細かい要望を追加で伝えていけば、少しずつ完成度を高めていくことができます。

なお、この章で扱った Studio Wave の <span id="idx-ufy6mn67o2id-79" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span> / <span id="idx-3ghtaxxv1hvr-180" class="index-term" data-yomi="しーえすえす">CSS</span> は、実際のプロジェクトでは次のファイルに分かれています。興味があれば、エディタで開いてコードの全体像を眺めてみてください。

- **<span id="idx-ufy6mn67o2id-80" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span>**
  - `work3/javascripts/glow_text.js`  … 文字を光らせるアニメーション
  - `work3/javascripts/page_top.js`   … 「先頭へ戻る」ボタンの表示/非表示
  - `work4/javascripts/hero_slideshow.js` … ヒーローイメージのフェードスライドショー
  - `work4/javascripts/page_top.js`        … 固定ヘッダー（`.site-header`）と Page Top ボタンの制御

- **<span id="idx-3ghtaxxv1hvr-181" class="index-term" data-yomi="しーえすえす">CSS</span>**
  - `work3/stylesheets/_text.css`        … `.glow.text` のアニメーション用スタイル
  - `work3/stylesheets/_page_top.css`    … Page Top ボタンの位置とアニメーション
  - `work3/stylesheets/_smooth_scroll.css` … スムーズスクロールの指定
  - `work4/stylesheets/_hero.css`        … ヒーローイメージのレイアウトとクロスフェード
  - `work4/stylesheets/_site_header.css` … スクロール後に表示される固定ヘッダーの見た目


## AIに聞いてみよう

Studio Wave の <span id="idx-ufy6mn67o2id-81" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span> で分からないところがあったら、AI にこんなふうに質問してみましょう。

> - 「`querySelector` と `querySelectorAll` の違いを教えて」
> - 「`getBoundingClientRect()` は何を返す関数？」
> - 「`classList.add` / `remove` / `contains` の使い方をまとめて教えて」
> - 「<span id="idx-3ghtaxxv1hvr-182" class="index-term" data-yomi="しーえすえす">CSS</span> の `animation` と `animation-delay` の詳しい書き方は？」

第9章で学んだ文法とこの章の実例を行き来しながら、「実際のサイトではどのように使われているか」を意識して読むと、理解が一気に深まります。


## まとめ

- Wave Studio のトップページでは、**<span id="idx-5376xxg0dgl-112" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>** が土台、**<span id="idx-3ghtaxxv1hvr-183" class="index-term" data-yomi="しーえすえす">CSS</span>** が見た目とアニメーション、**<span id="idx-ufy6mn67o2id-82" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span>** が「いつ・どのように動かすか」の制御を担当しています。
- `glow_text.js` では、キャッチコピーのテキストを 1 文字ずつ `span` に分解し、`animation-delay` を変えながら <span id="idx-3ghtaxxv1hvr-184" class="index-term" data-yomi="しーえすえす">CSS</span> アニメーションを適用することで、文字がキラキラ現れる表現を実現しています。
- `hero_slideshow.js` と `_hero.css` では、複数の海の画像を全画面で切り替えるスライドショーを実装し、画像サイズのリサイズや簡単な遅延読み込みで表示の軽さも両立させています。
- `page_top.js` と `_site_header.css` では、スクロール量に応じてクラスを付け替え、<span id="idx-3ghtaxxv1hvr-185" class="index-term" data-yomi="しーえすえす">CSS</span> のアニメーション（`upward` / `downward`）と `scroll-behavior: smooth` を組み合わせることで、「一定量スクロールしたら出てくる先頭へ戻るボタン」と「スクロール後に現れる固定ヘッダー」を実現しています。

今後、自分で <span id="idx-ufy6mn67o2id-83" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span> を書くときにも、

1. まず <span id="idx-5376xxg0dgl-113" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span> で「フック」となる id / class を決める
2. 次に <span id="idx-3ghtaxxv1hvr-186" class="index-term" data-yomi="しーえすえす">CSS</span> で「どんな見た目・アニメーションになるか」を用意する
3. 最後に <span id="idx-ufy6mn67o2id-84" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span> で「いつ・どの状態でクラスを付け替えるか／中身を書き換えるか」を実装する

という順番を意識すると、実装の見通しが良くなります。

