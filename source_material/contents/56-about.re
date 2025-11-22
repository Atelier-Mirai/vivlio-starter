= サイトについてページの機能拡張

//abstract{
  * 表を互い違いに色を塗る
  * 見出しの均等割付
  * 電話番号、メールアドレスにリンクを設定する
  * ルビをふる
  * 地図を載せる
  * 紹介動画を掲載する
といった機能拡張を行っていきます。
//}

== 表を互い違いに色を塗る
表のそれぞれの行が、別々の色になっていると見易いので、 @<code>{nth-child} を使って実現します。

//list[][table.css]{
  /*  奇数行と偶数行とで、それぞれで色を変える */
  tr:nth-child(odd)  th { background: #a1dfbc; color: black; }
  tr:nth-child(even) th { background: #00ba13; color: white; }
  tr:nth-child(odd)  td { background: #bfcdf5; color: black; }
  tr:nth-child(even) td { background: #4470ec; color: white; }
//}

== 見出しの均等割付
  均等割付を行うには、 @<code>{text-align-last: justify;} と宣言します
  (Safari でも、今秋提供される バージョン 16.0 から対応しています)。

//list[][table.css]{
th {
  width: 5em;
  text-align: left;         /* 左揃え */
  text-align-last: justify; /* 均等割付 */
}
//}

== 電話番号、メールアドレスにリンクを設定する
電話番号をクリックすると電話発信を、メールアドレスをクリックするとメールソフトが立ち上がるように、リンクを設定できます。

//list[][about.html]{
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
//}

@<code>{a}タグに着目してください。

 * @<code>{<a href="tel:(略)>}で電話番号へのリンクを設定
 * @<code>{<a href="mailto:(略)>}でメールアドレスへのリンクを設定 します。

以上を行うと、次のようになります。

//image[table][][width=60%]

== ルビを振る

//sideimage[ruby][80mm][sep=5mm,side=R]{
@<code>{<ruby>}タグと@<code>{<rt>}タグを使って、漢字の読みがなを振ることもできます。
//}

//list[][about.html]{
<p>
  綺麗なインテリアや可愛い文房具など、<br>
  日常の中で見つけたお気に入りのものを<br>
  <ruby>纏<rt>まと</rt></ruby>めているサイトです。
</p>
//}
---
== 地図を掲載する

ウェブサイトに案内地図を載せたい場面があります。
Google Map を使い、iPhone では縦長に、iPad では横長に載せることにしましょう。

//image[map_iphone][地図 (iPhone)][width=40%]{
//}

//image[map_ipad][地図 (iPad)][width=80%]{
//}

//list[][about.html]{
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
//}

//list[][map.css]{
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
//}

HTML コード中、@<code>{<iframe src="https://www.google.com/maps/(略)</iframe>}と書かれている部分が、Google Mapを埋め込んでいる部分です。
@<code>{embed?pb=!1m18!1m12!1m3!1d(略)}が、「住所」に相当しています。

CSS コード中、地図の縦横比を決定するために @<code>{aspect-ratio} プロパティを使用します
（従来は @<code>{padding-top} によるハック により実現していました）。
---
=== 地図の埋め込み方法

#@# //sideimage[map1][91mm][sep=5mm,side=R]{
#@# それでは、埋め込み方法を説明致します。

 - 1. @<href>{https://www.google.co.jp/maps, Google Map} を開きます。
#@# //}

//image[map1][][width=90%]

//sideimage[map2][60mm][sep=5mm,side=R]{
 - 2. 左上の検索窓に、場所名や住所を入力します。
//}
//blankline
#@# //image[map2][][pos=H,width=80%]

//sideimage[map3][60mm][sep=5mm,side=R]{
 - 3. 「コメダ珈琲野並店」と入力し、虫眼鏡ボタンを押します。
//}
//blankline

 - 4. コメダ珈琲 野並店が表示されました。埋め込み用のデータを表示させる為に、右下の「共有」ボタンを押します。
//image[map4][][width=60%]

//sideimage[map5][80mm][sep=5mm,side=R]{
 - 5. ここでは自分のWebサイトの中にGoogle Mapを埋め込みたいので、「地図を埋め込む」をクリックします。
//}
#@# //image[map5][][pos=H,width=80%]

 - 6. 「HTMLをコピー」をクリックして、エディタ に貼り付けます。
//image[map6][][width=70%]

 - 7. 不要なコードもあるので、必要な部分だけを残して完成です。

== 紹介動画を掲載する

ウェブサイトに動画を掲載したいことも良くあります。
写真と同様にサーバーにアップロードして配信することもできますが、動画は容量が嵩みますので、動画共用サイト(YouTubeやVimeoなど)にアップロードし、その@<code>{URL}を自分のウェブサイトに埋め込んで使うことがお勧めです。

//image[youtube_iphone][YouTube (iPhone)][width=40%]{
//}

//image[youtube_ipad][YouTube (iPad)][width=80%]{
//}

//list[][about.html]{
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
//}

HTML の構造が、先に掲載した地図と全く同様になっていることにお気付きでしょうか。
iPhone では縦長に、 iPad では横長にと、表示方法も同様ですので、
CSS も同じものを使うことができます。
HTML のクラス名のみが異なりますので、 @<code>{.map-container} を @<code>{.video-container} に、@<code>{.map} を @<code>{.video} に変更したら完了です。

=== YouTube埋め込み方法

 - 1. 埋め込みたい YouTube 動画に移動します。

 - 2. 動画のURLの末尾にある動画IDをメモします。 @<br>{}
   @<code>{https://www.youtube.com/watch?v=OAo1GBrdvzg} であれば 動画IDは @<code>{OAo1GBrdvzg}  です。

 - 3. 以下のHTMLの動画IDの部分を置き換えて完了です。

//list[][html]{
<iframe src="https://www.youtube.com/embed/動画ID"
        frameborder="0"
        allowfullscreen>
</iframe>
//}

 - 4. @<code>{?rel=0&showinfo=0"}と付けるのもお勧めです。
//list[][html]{
<iframe src="https://www.youtube.com/embed/動画ID?rel=0&showinfo=0"
        frameborder="0"
        allowfullscreen>
</iframe>
//}

 * 動画再生した後に関連動画が表示されなくなります。
 * 動画再生中の表題が非表示になり、すっきりします
