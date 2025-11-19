# サイトについてページの機能拡張

:::{.chapter-lead}
* 表を互い違いに色を塗る
* 見出しの均等割付
* 電話番号、メールアドレスにリンクを設定する
* ルビをふる
* 地図を載せる
* 紹介動画を掲載する

といった機能拡張を行っていきます。  
:::



## 表を互い違いに色を塗る

表のそれぞれの行が、別々の色になっていると見易いので、 `nth-child` を使って実現します。

**▼table.css**

```
  /*  奇数行と偶数行とで、それぞれで色を変える */
  tr:nth-child(odd)  th { background: #a1dfbc; color: black; }
  tr:nth-child(even) th { background: #00ba13; color: white; }
  tr:nth-child(odd)  td { background: #bfcdf5; color: black; }
  tr:nth-child(even) td { background: #4470ec; color: white; }
```


## 見出しの均等割付

均等割付を行うには、 `text-align-last: justify;` と宣言します
(Safari でも、今秋提供される バージョン 16.0 から対応しています)。

**▼table.css**

```
th {
  width: 5em;
  text-align: left;         /* 左揃え */
  text-align-last: justify; /* 均等割付 */
}
```


## 電話番号、メールアドレスにリンクを設定する

電話番号をクリックすると電話発信を、メールアドレスをクリックするとメールソフトが立ち上がるように、リンクを設定できます。

**▼about.html**

```
<table>
  <tr>
    <th>サイト名</th>
    <td>WAVE</td>
  </tr>
  <tr>
    <th>開設日</th>
    <td>四月一日</td>
  </tr>
  <tr>
    <th>住所</th>
    <td>名古屋市桜区桜町1丁目1番地<br>桜ビル1階</td>
  </tr>
  <tr>
    <th>電話番号</th>
    <td><a href="tel:052-373-4649">052-373-4649</a></td>
  </tr>
  <tr>
    <th>メール<br>アドレス</th>
    <td><a href="mailto:contact@example.com">contact@example.com</a></td>
  </tr>
  <tr>
    <th>運営方針</th>
    <td>ときどきまったり更新中。最新記事の一覧はトップページに掲載しています。</td>
  </tr>
</table>
```

`a`タグに着目してください。

* `<a href="tel:(略)>`で電話番号へのリンクを設定
* `<a href="mailto:(略)>`でメールアドレスへのリンクを設定 します。

以上を行うと、次のようになります。

![](table.png)


## ルビを振る

![](ruby.png)

`<ruby>`タグと`<rt>`タグを使って、漢字の読みがなを振ることもできます。

**▼about.html**

```
<p>
  綺麗なインテリアや可愛い文房具など、<br>
  日常の中で見つけたお気に入りのものを<br>
  <ruby>纏<rt>まと</rt></ruby>めているサイトです。
</p>
```

---
== 地図を掲載する

ウェブサイトに案内地図を載せたい場面があります。
Google Map を使い、iPhone では縦長に、iPad では横長に載せることにしましょう。

![地図 (iPhone)](map_iphone.png)
![地図 (iPad)](map_ipad.png)

**▼about.html**

```
<!-- 地図の取り扱いがしやすいよう コンテナで包みます。 -->
<div class="map-container">
  <div class="note">
    <h2>会社案内</h2>
    <p>地下鉄桜線 桜駅1番出口より徒歩三分、交通至便の地にあります。</p>
  </div>

  <div class="map">
    <iframe
      src="https://www.google.com/maps/embed?pb=!1m18!1m12!1m3!1d3264.098229592375!2d136.94909095223227!3d35.10425798023631!2m3!1f0!2f0!3f0!3m2!1i1024!2i768!4f13.1!3m3!1m2!1s0x60037b0d5843e2af%3A0x282e3c573e3f00d8!2z44Kz44Oh44OA54-I55CyIOmHjuS4puW6lw!5e0!3m2!1sja!2sjp!4v1592795030975!5m2!1sja!2sjp"
      style="border:0;"
      loading="lazy">
    </iframe>
  </div>
</div>
```

**▼map.css**

```
/* モバイル
---------------------------------------------------------------------*/
/* iPhone では、一列 x 二行 で配置します */
.map-container {
  display: grid;
  grid-template-columns: 1fr;
  grid-template-rows: auto auto;
  gap: 10px;
}

/* 紹介文章を一行目に表示します */
.map-container .note {
  grid-column: 1;
  grid-row: 1;
}

/* 地図をニ行目に表示します */
.map-container .map {
  grid-column: 1;
  grid-row: 2;
}

/* 地図の縦横比の指定 */
.map-container .map {
  /* iPhone では、縦長(横2に対して縦3の比率)で表示します */
  aspect-ratio: 2 / 3;
}

/* 地図をグリッド内で最大表示します */
.map-container .map iframe {
  width: 100%;
  height: 100%;
}

/* デスクトップ
---------------------------------------------------------------------*/
@media (min-width: 768px) {
  /* iPad や Mac では、二列 x 一行 で配置します */
  .map-container {
    display: grid;
    grid-template-columns: 2fr 1fr;
    grid-template-rows: auto;
  }

  /* 紹介文章を二列目に表示します */
  .map-container .note {
    grid-column: 2;
    grid-row: 1;
  }

  /* 地図を一列目に表示します */
  .map-container .map {
    grid-column: 1;
    grid-row: 1;
  }

  /* 地図の縦横比の指定 */
    .map-container .map {
    /* iPad や Mac では、横長(横16に対して縦9の比率)で表示します */
    aspect-ratio: 16 / 9;
  }
}
```

HTML コード中、`<iframe src="https://www.google.com/maps/(略)</iframe>`と書かれている部分が、Google Mapを埋め込んでいる部分です。
`embed?pb=!1m18!1m12!1m3!1d(略)`が、「住所」に相当しています。

CSS コード中、地図の縦横比を決定するために `aspect-ratio` プロパティを使用します
（従来は `padding-top` によるハック により実現していました）。
---
=== 地図の埋め込み方法

- 1. [Google Map](https://www.google.co.jp/maps) を開きます。

![](map1.png)

![](map2.png)

- 2. 左上の検索窓に、場所名や住所を入力します。


![](map3.png)

- 3. 「コメダ珈琲野並店」と入力し、虫眼鏡ボタンを押します。


- 4. コメダ珈琲 野並店が表示されました。埋め込み用のデータを表示させる為に、右下の「共有」ボタンを押します。

![](map4.png)

![](map5.png)

- 5. ここでは自分のWebサイトの中にGoogle Mapを埋め込みたいので、「地図を埋め込む」をクリックします。

- 6. 「HTMLをコピー」をクリックして、エディタ に貼り付けます。

![](map6.png)

- 7. 不要なコードもあるので、必要な部分だけを残して完成です。


## 紹介動画を掲載する

ウェブサイトに動画を掲載したいことも良くあります。
写真と同様にサーバーにアップロードして配信することもできますが、動画は容量が嵩みますので、動画共用サイト(YouTubeやVimeoなど)にアップロードし、その`URL`を自分のウェブサイトに埋め込んで使うことがお勧めです。

![YouTube (iPhone)](youtube_iphone.png)
![YouTube (iPad)](youtube_ipad.png)

**▼about.html**

```
<!-- YouTubeの取り扱いがしやすいよう コンテナで包みます。 -->
<div class="video-container">
  <div class="note">
    <h2>一日社長 ノンちゃん</h2>
    <p>「一日社長 ノンちゃん」です。のんびり<ruby>寛<rt>くつ</rt></ruby>いでいます。</p>
  </div>

  <div class="video">
    <iframe
      src="https://www.youtube.com/embed/OAo1GBrdvzg?rel=0&showinfo=0"
      frameborder="0"
      allowfullscreen>
    </iframe>
  </div>
</div>
```

HTML の構造が、先に掲載した地図と全く同様になっていることにお気付きでしょうか。
iPhone では縦長に、 iPad では横長にと、表示方法も同様ですので、
CSS も同じものを使うことができます。
HTML のクラス名のみが異なりますので、 `.map-container` を `.video-container` に、`.map` を `.video` に変更したら完了です。


### YouTube埋め込み方法

- 1. 埋め込みたい YouTube 動画に移動します。

- 2. 動画のURLの末尾にある動画IDをメモします。 <br>
    `https://www.youtube.com/watch?v=OAo1GBrdvzg` であれば 動画IDは `OAo1GBrdvzg`  です。

- 3. 以下のHTMLの動画IDの部分を置き換えて完了です。

**▼html**

```
<iframe src="https://www.youtube.com/embed/動画ID"
        frameborder="0"
        allowfullscreen>
</iframe>
```

- 4. `?rel=0&showinfo=0"`と付けるのもお勧めです。

**▼html**

```
<iframe src="https://www.youtube.com/embed/動画ID?rel=0&showinfo=0"
        frameborder="0"
        allowfullscreen>
</iframe>
```

* 動画再生した後に関連動画が表示されなくなります。
* 動画再生中の表題が非表示になり、すっきりします

