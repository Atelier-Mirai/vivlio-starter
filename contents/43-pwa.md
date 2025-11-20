# ウェブアプリ化する

:::{.chapter-lead}
これまでiPhoneアプリを作るためには、専用の言語や環境での開発が一般的でしたが、技術の進歩に伴い、ウェブサイトをそのままアプリ化できるようになりました。これを `PWA(Progressive Web App)` と言います。じゃんけんゲームを、ウェブアプリ化してiPhoneへインストールしましょう。  
:::



## PWAとは

PWAとは、「Progressive Web App」の略称で、新しいウェブアプリケーションの形態です。PWAには次のような特徴があります。

* モバイルデバイスに最適化されたウェブアプリケーション
* キャッシュ機能を持つので、オフラインでも一部機能を利用できる。
* ユーザーの許可を得てプッシュ通知を受け取ることができる。
* ブラウザからアプリのようにホーム画面に追加できる。
* スムーズなスクロールや高速な立ち上がりなど、ネイティブアプリに近い体験が得られる

つまり、`PWA`はウェブサイトの機能とネイティブアプリの特徴を組み合わせたものです。利用者にはインストールが簡単で軽量なアプリのような使い勝手を提供しつつ、開発者には慣れ親しんだウェブ技術を活かせるというメリットがあります。


## PWA化する


### HTML

すでにHTMLは次のように記述されているはずです。

**▼index.html**

```
<!-- PWA (Progressive Web Apps) にするための設定 -->
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="#fef4f4">
<meta name="theme-color" content="#fef4f4">
<meta name="apple-mobile-web-app-title" content="じゃんけん">
<link rel="manifest" href="/manifest.json">
<script src="/app.js" defer></script>
```

26行目は、じゃんけんゲームを開いたときに全画面表示にするための設定です。
27行目ではステータスバーの色を、28行目ではテーマ色を桜色に設定しています。
28行目はアプリのタイトルを「じゃんけんゲーム」と設定しています。
29行目は「マニフェストファイル」と呼ばれる`PWA`の為の設定ファイルが `manifest.json`であることを記しています。

`manifest.json` は次の通りです。

**▼manifest.json**

```
{
  "name": "じゃんけんゲーム",
  "short_name": "じゃんけん",
  "start_url": "/",
  "background_color": "#fef4f4",
  "theme_color": "#fef4f4",
  "display": "standalone",
  "icons": [
    {
      "src": "/images/icon-512x512.png",
      "sizes": "512x512",
      "type": "image/png"
    }
  ]
}
```

マニフェストファイルには、アプリ名が「じゃんけんゲーム」、略称が「じゃんけん」であること、開始URLが「`/`」であること、背景色とテーマ色が桜色（`#fef4f4`）、表示モードが `standalone（iPhoneアプリのように見せる）`こと、アイコンファイル名や画像の大きさや種類が記します。

30行目は「サービスワーカー」と呼ばれる `PWA`の中枢機能を登録する為のコードです。

`app.js` [^103] は次のように書かれています。

**▼app.js**

```
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("sw.js")
    .then((registration) => {
      // 登録成功
      console.log(`Service Worker の登録に成功しました。スコープ: ${registration.scope}`)
    }).catch((error) => {
      // 登録失敗
      console.log(`Service Worker の登録に失敗しました。${error}`)
    })
}
```

2行目で 「サービスワーカー」 `sw.js` の登録を行い、登録成功時、失敗時、それぞれのメッセージを表示する内容となっています。

`sw.js` [^104]は次のように書かれています。

**▼sw.js**

```
const CACHE_NAME = "janken-v1"
self.addEventListener("fetch", (event) => {
  console.log("[Service Worker] Fetching something ...")
  event.respondWith(
    // キャッシュの存在チェック
    caches.match(event.request).then((response) => {
      // キャッシュ内に該当レスポンスがあれば、それを返す
      if (response) {
        return response
      } else {
        // キャッシュがなければリクエストを投げて、
        // レスポンスをキャッシュに入れる
        return fetch(event.request).then((res) => {
          return caches.open(CACHE_NAME).then((cache) => {
            // 最後に res を返せるように、ここでは clone() する必要がある
            cache.put(event.request.url, res.clone())
            return res
          })
        }).catch(() => {
          // エラーが発生しても何もしない
        })
      }
    })
  )
})
```

[^104]: 出典: https://jam25.jp/javascript/about-pwa/, https://laboradian.com/create-offline-site-using-sw/

通常のウェブサイトでは、ネットワーク接続がない状態では閲覧することができませんが、キャッシュを取得することにより、オフライン（ネットワーク接続がない状態）でもじゃんけんゲームが動作するようになっています。

もし皆さんが別のウェブアプリを作成されたい際には、 `index.html` や `manifest.json` の内容を適宜更新なさってください。 `app.js` や `sw.js` は、このまま使うと良いでしょう。学習を続け、より深い `JavaScript` の知識を身に付けた暁には必要に応じて改修なさってください。


## ホーム画面に追加する

`PWA`ができましたので、再度`Netlify`に公開（デプロイ）しましょう。

続いて、iPhone のホーム画面にじゃんけんゲームを表示させましょう。

![](janken01.jpg)

- 1. ブラウザで `joyful-janken.netlify.app` にアクセスします。中央の共有ボタンを押します。

![](janken02.jpg)

- 2. メニューが表示されますが、続きを表示させる為に、少し上へ引っ張ります。

![](janken03.jpg)

- 3. 「ホーム画面に追加」メニューを押します。

![](janken04.jpg)

- 4. 右上の「追加」を押します。

![](janken05.jpg)

- 5. ホーム画面に「じゃんけん」が追加されています。

![](janken06.jpg)

- 6. 「じゃんけん」を押すと、「じゃんけんゲーム」が始まります。

本書では、算盤からiPhoneに至るまでの計算機の歴史やその動作原理を学んだ後、HTML, CSS, JavaScript といったウェブ技術を用いてウェブアプリを作成、サーバーに公開、iPhone にインストールすることまで行いました。

初めてのウェブアプリ作成はいかがでしたでしょうか。長い旅でしたが沢山のものを得られたことと思います。皆さんにはこの先広大な世界が待っています。どうぞその身に付けた翼で輝かしい未來へと羽ばたいていってください。

前途に幸多からんことを祈って、筆を置きます。

