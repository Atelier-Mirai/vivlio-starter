# モーダルウィンドウ

:::{.chapter-lead}
文字や写真、動画の表示に使えるモーダルウィンドウの例をご紹介いたします。  
:::



## モーダルウィンドウ

モーダルウィンドウを実現するためのライブラリは多数ございますが、
その中から、[MODAAL](https://humaan.com/modaal/) をご紹介いたします。

> ModaalはWCAG 2.0 Level AAアクセシブル・モーダルウィンドウ・プラグインです。
>
>
> なぜ他のモーダルプラグインなのか？
>
>
> 品質、柔軟性、アクセシビリティの適切な組み合わせのプラグインを見つけるのは困難です。私たちは、さまざまなプロジェクトで使えるものを開発し、アクセシブルなウェブを目指すことができれば、おもしろいと思いました。

::: {.text-right}
[DeepL](https://www.deepl.com/ja/translator) による翻訳　
:::

`Modaal`の使い方はとても簡単です。

- 1. HTML に (通常時には非表示の)コンテンツを用意する。
- 2. クリックした際の処理を jQuery を書く。

以上でモーダルウィンドウを実現できます。

`Modaal`のデモサイトは英語ですので、以下の機能について翻訳してご紹介いたします。

* インライン（基本）
* フルスクリーン
* 画像(一枚)
* 画像ギャラリー(複数枚)
* 動画(YouTube / Vimeo)
* iframe
* 確認画面


## 基本準備

基本となる以下のHTMLを用意します。

**▼index.html**

```
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Modaal 使用例</title>
    <meta name="viewport" content="width=device-width">

    <!-- 簡単に見栄えの良いページを作るためのスタイルシート -->
    <link rel="stylesheet" href="https://unpkg.com/sakura.css/css/sakura.css">
    <!-- Modaal を CDN から読み込む -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/Modaal/0.4.4/css/modaal.min.css">

    <style>
      /* 通常時にモーダルウィンドウ内のコンテンツを表示させないために */
      .hidden { display: none !important; }
      /* スタイルシート「sakura」が干渉するので上書き */
      img { margin-bottom: 0; }
    </style>
  </head>

  <body>
    <h1>モーダルウィンドウ ライブラリ Modaalの使用例</h1>

    <!-- jQuery を CDN から読み込みます -->
    <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.1/jquery.min.js"></script>
    <!-- Modaal を CDN から読み込みます -->
    <script src="https://cdnjs.cloudflare.com/ajax/libs/Modaal/0.4.4/js/modaal.min.js"></script>
    <!-- Modaal 設定用の JavaScript(jQuery)です -->
    <script src="modaal-custom.js"></script>
  </body>
</html>
```

「簡単に見栄えの良いページを作るためのスタイルシート」として [sakura.css](https://oxal.org/projects/sakura/) を使います。

そして、`Modaal` のためのスタイルシートを CDN から読み込みます。

`<style>`タグ内では、二つのルールを宣言しています。一つは、通常時にモーダルウィンドウ内のコンテンツを表示させないためのもので、もう一つは、スタイルシート「sakura」が干渉するので上書きするためのものです。


`</body>`の直前に、三つの `<script>`タグを書き、必要な JavaScript を読み込みます。
一つ目は `jQuery` です。 `Modaal` は、`jQuery` の利用を前提に書かれていますので、読み込みが必要です。

二つ目は `Modaal` 本体です。CDN から読み込みます。

三つ目は `modaal-custom.js` としていますが、名前は任意です。Modaal 設定用の JavaScript(jQuery)で、特定の要素をクリックした際に、どのようなモーダルウィンドウを実現したいのか、簡単なコードを書くためのファイルです。


## インライン


### 基本的な使い方

それでは、実際に使い始めていきましょう。
以下のコードを追加してください。

```
<h2>インライン（基本）</h2>
<p>
  ページ内の既存の要素（IDを使用）からコンテンツを取得し、
  コンテンツに読み込みます。
</p>
<a href="#inline" class="inline">Inline</a>
<div  id="inline" class="hidden">
  ここに書かれたインラインコンテンツが表示されます
</div>
```

![](inline0.png)

ブラウザで見ると右のようになります。
`class="hidden"` により非表示となっていることが確認できます。

`Inline`をクリックしたときに、コンテンツが表示されるようにするためには、`modaal-custom.js`に次のコードを記述しましょう。

**▼modaal-custom.js**

```
// inline (基本)
$(".inline").modaal();
```

![](inline1.png)

`Inline`をクリックすると右のようになります。

右上の 「ｘ」ボタンをクリックすると、モーダルウィンドウを閉じることができます。


### 複数のモーダルウィンドウを用意したい場合

複数のモーダルウィンドウを用意したい場合には次のコードを書きます。

```
  <a href="#inline1" class="inline">Inline1</a>
  <div  id="inline1" class="hidden">インラインコンテンツ　その１</div>

  <a href="#inline2" class="inline">Inline2</a>
  <div  id="inline2" class="hidden">インラインコンテンツ　その２</div>

  <a href="#inline3" class="inline">Inline3</a>
  <div  id="inline3" class="hidden">インラインコンテンツ　その３</div>
```

`<a href="#inline1">`に対応する `<div  id="inline1">`が開くようになります。


### まとめ

- 1. HTML コードを書く。

```
  <a href="#inline" class="inline">Inline</a>
  <div id="inline" class="hidden">コンテンツ</div>
```

- 2. コンテンツが最初から見えてしまわぬよう、`class="hidden"`として非表示にする。

- 3. `class="inline"`要素をクリックした際に、インライン表示のモーダルウィンドウとなるよう、簡単なコードを書く。

- 4. `<a href="#inline">`に対応する `<div  id="inline1">`が開くようになる。

---
== フルスクリーン
フルスクリーンで開くモーダルウィンドウも作成できます。そのために次のHTMLを用意します。

```
<h2>フルスクリーン</h2>
<a href="#fullscreen" class="fullscreen">Fullscreen</a>
<p>
  フルスクリーンモードでは、
  Modaalウィンドウがビューポート全体に広がるように開きます。
  コンテンツがウィンドウの高さを超える場合は、
  ダイアログが垂直方向にスクロールし、
  すべてのコンテンツにアクセスできるようになります。
</p>
<div id="fullscreen" class="hidden">
  ここに書かれたインラインコンテンツがフルスクリーンで表示されます
</div>
```

![](fullscreen0.png)

ブラウザで見ると右のようになります。

`Fullscreen`をクリックしたときに、コンテンツがフルスクリーン表示されるようにするためには、`modaal-custom.js`に次のコードを記述しましょう。

**▼modaal-custom.js**

```
// フルスクリーン
$(".fullscreen").modaal({
  fullscreen: true
});
```

![](fullscreen1.png)

`Fullscreen`をクリックすると右のようになります。


## 画像

画像が開くモーダルウィンドウも作成できます。そのためには、次のHTMLを用意します。

```
  <h2>画像(一枚)</h2>
  <p>
    一枚の画像を開きます。
    開いた画像の下にラベルを表示したり、
    data-modaal-desc="My Image Description "を使って
    アクセス可能なラベルを表示することもできます。
  </p>
  <a href="images/sea01.webp" class="image" data-modaal-desc="空飛ぶ鷗">
    ![](images/sea01_s.webp)
  </a>
```

`![](images/sea01_s.webp)`と、画像ファイル名を指定しています。「サムネイル」（親指の爪）画像と呼ばれるもので、その名の通り、小さな画像ファイルを作って、最初はそれを表示させています。そして、サムネイル画像がクリックされた際には、`<a href="images/sea01.webp">` で指定した大きな画像を表示させます。

![](gazou0.png)

ブラウザで見ると右のようになります。

「空飛ぶ鷗」の画像をクリックしたときに、「空飛ぶ鷗」の画像が表示されるようにするためには、`modaal-custom.js`に次のコードを記述しましょう。

**▼modaal-custom.js**

```
  // 画像(一枚)
  $('.image').modaal({
    type: 'image'
  });
```

![](gazou1.png)

「空飛ぶ鷗」の画像をクリックすると右のようになります。

`data-modaal-desc="空飛ぶ鷗"` と記述したことで、写真の下に補足説明も掲載されます。


## 画像ギャラリー(複数枚)

関連性のある複数枚の画像を開くためのモーダルウィンドウも作成できます。そのためには、次のHTMLを用意します。

```
<h2>画像ギャラリー(複数枚)</h2>
<p>
  data-group="group-name "属性でリンクされた一連の画像を開きます。
  group-nameは、あなたのギャラリーグループの識別子に置き換えてください。
</p>
<div>
  <a href="images/sea01.webp" class="gallery" data-group="sea"
                                              data-modaal-desc="空飛ぶ鷗">
    ![](images/sea01_s.webp)
  </a>
  <a href="images/sea02.webp" class="gallery" data-group="sea"
                                              data-modaal-desc="打ち寄せる波">
    ![](images/sea02_s.webp)
  </a>
  <a href="images/sea03.webp" class="gallery" data-group="sea"
                                              data-modaal-desc="透明な南の海">
    ![](images/sea03_s.webp)
  </a>
  <a href="images/sea04.webp" class="gallery" data-group="sea"
                                              data-modaal-desc="夜明け前">
    ![](images/sea04_s.webp)
  </a>
  <a href="images/sea05.webp" class="gallery" data-group="sea"
                                              data-modaal-desc="断崖にて">
    ![](images/sea05_s.webp)
  </a>
</div>
```

画像一枚で表示する例とほぼ同じですが、それぞれの画像リンクに共通して `data-group="sea"`と書かれていることに着目してください。グループ名が`sea`で共通しているので、海に関する一塊の写真ギャラリーとして、Modaal は扱うようになります。

![](gallery0.png)

ブラウザで見ると右のようになります。

写真ギャラリーを実現するためには、`modaal-custom.js`に次のコードを記述しましょう。

**▼modaal-custom.js**

```
// 画像ギャラリー(複数枚)
$('.gallery').modaal({
  type: 'image'
});
```

![](gallery1.png)

「空飛ぶ鷗」の画像をクリックするとモーダルウィンドウで写真ギャラリーが表示されます。
写真下の「＞」をクリックすることで次の写真へと移動できます。

真ん中の「透明な南の海」を見ている状態です。


## 動画

YouTube や Vimeo など動画が開くモーダルウィンドウも作成できます。


### YouTube

```
<h3>YouTube</h3>
<p>
  リンクのhref属性で指定された埋め込み動画をiframeに読み込みます。
  現在テストされているフォーマットは、YoutubeとVimeoです。
  その他、iframeでの埋め込みに対応しているものも動作するはずです。
</p>
<p>
  Modaalのビデオタイプは、VimeoとYoutubeの両方で徹底的にテストされています。
  最良の結果を得るためには、URLフォーマットが以下のようになっていることを
  確認してください。私たちはこのURLをiframeに移植し、
  そこから各サービスプロバイダーが必要な再生をすべてコントロールします。
</p>
<p>
  https://www.youtube.com/embed/cBJyo0tgLnw
  最後のIDはあなたのユニークなビデオIDです。
  これは、youtubeの動画で「共有」を選択し、
  「埋め込み」をクリックすると表示されます。
  提示されたコンテンツの中にこのURLがあります。
</p>

<a href="https://www.youtube.com/embed/cBJyo0tgLnw" class="youtube">
  ![](images/youtube.webp)
</a>
```

`<p>`タグ内に説明が書かれていますので、ご自身の動画を埋め込む場合には、適宜、動画IDを変更して実行してください。

![](youtube0.png)

ブラウザで見ると右のようになります。

「YouTube」の画像をクリックしたときに、動画が再生されるようにするためには、`modaal-custom.js`に次のコードを記述しましょう。

**▼modaal-custom.js**

```
  // 動画(YouTube)
  $('.youtube').modaal({
    type: 'video'
  });
```

![](youtube1.png)

「YouTube」の画像をクリックすると右のようになります。

---
=== Vimeo

```
<h3>Vimeo</h3>
<p>
  https://player.vimeo.com/video/109626219
  最後のIDはお客様固有のビデオIDです。
  これは、vimeoの動画で「共有」を選択し（一般的に右側に表示されます）、
  「埋め込み」内のコンテンツを選択することで確認できます。
  埋め込みコードの一番最初にあるsrc=""の中に必要なURLがあります。
</p>
<a href="https://player.vimeo.com/video/109626219" class="vimeo">
  ![](images/vimeo.webp)
</a>
```

![](vimeo0.png)

ブラウザで見ると右のようになります。

「Vimeo」の画像をクリックしたときに、動画が再生されるようにするためには、`modaal-custom.js`に次のコードを記述しましょう。

**▼modaal-custom.js**

```
  // 動画(Vimeo)
  $('.vimeo').modaal({
    type: 'video'
  });
```

![](vimeo1.png)

「Vimeo」の画像をクリックすると右のようになります。

---
== `iframe` で 他のウェブサイトの内容を開く

iframe を使うと、モーダルウィンドウで他のウェブサイトの内容を開くことができます。まずは次のHTMLを用意します。

```
<h2>iframeで 他のウェブサイトの内容を開く</h2>
<p>
  リンクのhref属性で定義されたURLを、iframeに読み込みます。
  このためには、モーダルの幅と高さも設定する必要があります。
</p>
<a href="http://humaan.com" class="iframe">iframe</a>
```

![](iframe0.png)

ブラウザで見ると右のようになります。

`iframe`をクリックしたときに、リンク先のサイト「`http://humaan.com`」をモーダルウィンドウ内で表示されるためには、`modaal-custom.js`に次のコードを記述しましょう。

**▼modaal-custom.js**

```
// iframe
let w = $(window).width();  // 画面幅を取得
let h = $(window).height(); // 画面高を取得
let bc = '';
if (w >= 768) {   // iPad 以上の画面幅の場合
  w = w * 0.8;    // w *= 0.8; と省略して書くことも出来ます
  h = h * 0.8;
  bc = '#ff0000'; // 背景色を赤色にする
} else {          // iPhone で閲覧の場合
  bc = '#0000ff'; // 背景色を青色にする
}

$('.iframe').modaal({
  type: 'iframe',
  width: w,
  height: h,
  background: bc
});
```

今までより少しコードが長くなりました。
`<p>`タグ内の説明として「モーダルの幅と高さも設定する必要があります」と書かれているように、
画面幅を取得し、iPhone か iPad かによって、モーダルウィンドウの大きさと背景色を変更するようにしています。

![](iframe_iphone.png)

`iframe`をクリックした例(iPhone)

![](iframe_ipad.png)

`iframe`をクリックした例(iPad)


## 確認画面

最後の例は、モーダルウィンドウで開く確認画面です。準備として次のHTMLを用意します。

```
<h2>確認画面</h2>
<p>
  ユーザーに特定のアクションの「確認」または「取消」を促すモーダルなウィンドウ。
  必要に応じて、コールバックイベントを含むコンテンツをプッシュすることができます。
  デフォルトでは、一度開くと、
  アクション（確認／取消など）が選択されるまで閉じることができません。
</p>
<a href="#" class="confirm">confirm</a>
```

また、`sakura.css` の干渉補正のために、以下も追加します。

```
<style>
  /* sakura.css の干渉補正 */
  .modaal-confirm-btn.modaal-cancel { color: #555; }
</style>
```

![](confirm0.png)

ブラウザで見ると右のようになります。

`confirm`をクリックしたときに、確認画面がモーダル表示されるようにするためには、`modaal-custom.js`に次のコードを記述しましょう。

**▼modaal-custom.js**

```
// 確認画面
$('.confirm').modaal({
  type: 'confirm',
  confirm_button_text: '確認',
  confirm_cancel_button_text: '取消',
  confirm_title: '確認画面です',
  confirm_content: '<p>登録してもよろしいですか</p>',
  confirm_callback: () => {
    alert('登録しました');
  },
  confirm_cancel_callback: () => {
    alert('取り消しました');
  }
});
```

![](confirm1.png)

`confirm`をクリックすると右のようになります。

「確認」をクリックすると「登録しました」とメッセージが表示され、一見動作しているように思いますが、 `alert('登録しました');` により表示させているのみです。実用に供するには、実際の登録処理をコーディングして下さい。

