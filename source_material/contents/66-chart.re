= グラフを描画する

//abstract{
様々なグラフを描画したい場面もあるかと思います。定番の JavaScript ライブラリとして「chart.js」があります。ここでは、架空のラーメン店の紹介を例に、使い方のご紹介を致します。
//}

== Chart.js

#@# Muuriとはフィンランド語で「壁」の意味を持つ語で、
@<href>{https://www.chartjs.org,Chart.js}公式サイトによると、次のように紹介されています。
//quote{
シンプル、クリーン、魅力的なHTML5ベースのJavaScriptチャート。Chart.jsは、アニメーションやインタラクティブなグラフをあなたのWebサイトに無料で簡単に取り入れることができます。(翻訳 DeepL)
//}


Chart.js は、棒グラフ各種、線グラフ各種、バブル図や円グラフなど、多様なグラフを描画することができます。公式サイトにはサンプルや使い方に関する説明も充実しています。
//image[chart2][][width=60%]

ここでは、架空の全国各地の有名ラーメン店の紹介としてレーダーチャートの例を紹介します。
@<href>{https://wave-improve.netlify.app/ramen/chart.html,動作例}や@<href>{https://github.com/Atelier-Mirai/wave-improve/tree/master/ramen,ソースコード}もご活用下さい。

//image[chart][][width=100%]



== HTML

それでは、HTML を書いていきましょう。

//list[][index.html]{
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>人気のラーメン店</title>

  <!-- Font Awesome -->
  <link href="https://use.fontawesome.com/releases/v6.2.0/css/all.css"
        rel="stylesheet">

  <!-- 簡単に見栄えの良いページを作るためのスタイルシート -->
  <link rel="stylesheet" href="https://unpkg.com/sakura.css/css/sakura.css">
  <link rel="stylesheet" href="style.css">
</head>

<body>
  <h1>ラーメン人気店紹介</h1>
  <p>全国各地の美味しいラーメン店を紹介します。</p>

  <hr class="divider">

  <section>
    <!-- 店舗紹介 -->
    <div class="grid">
      <div class="item" data-color="shoyu" data-title="櫻幕ラーメンは 京都市東区にある 醤油ラーメンが人気のお店。280円とお財布に優しいお店である。">
        <!-- (略) -->
      </div>

      <table>
        <!-- (略) -->
      </table>

      <div class="map">
        <!-- (略) -->
      </div>
    </div>
  </section>

  <hr class="divider">

  <section class="report">
    <h2>総合評価
      <!-- 今すぐ使えるCSSレシピブックより ★を付ける -->
      <div class="rating" data-rate="3.5">
        <span class="star"></span>
        <span class="star"></span>
        <span class="star"></span>
        <span class="star"></span>
        <span class="star"></span>
      </div>
    </h2>

    <!-- グラフ描画領域 -->
    <div class="chart-container">
      <canvas id="myChart"></canvas>
    </div>

    <!-- 評価記事 -->
    <article class="note">
      <!-- (略) -->
    </article>
  </section>

  <hr class="divider" style="margin-top: 150px;">

  <footer>
    <p class="copyright">
      Copyright © 美味しいラーメン調査委員会 All rights reserved.
    </p>
  </footer>

  <!-- jQuery -->
  <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.1/jquery.min.js"></script>
  <!-- Chart.js -->
  <script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/3.9.1/chart.min.js"></script>
  <script src="chart.js"></script>
</body>

//}

ここでのポイントは、グラフ描画のために書かれた次のコードです。

//list[][]{
<!-- グラフ描画領域 -->
<div class="chart-container">
  <canvas id="myChart"></canvas>
</div>

<!-- jQuery -->
<script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.1/jquery.min.js"></script>
<!-- Chart.js -->
<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/3.9.1/chart.min.js"></script>
<script src="chart.js"></script>
//}

描画のための @<code>{<canvas>}要素を用意し、画面幅に応じてレスポンシブにグラフの大きさを変更できるよう、 親要素として @<code>{<div class="chart-container">} を書いています。

Chart.jsはjQueryを利用しているので、jQueryとChart.jsをCDNから読み込みます。
最後の @<file>{chart.js} は、グラフデータや表示設定等が書かれたスクリプトファイルです。

== JavaScript

//list[][chart.js]{
// レーダーチャートの説明 （Charts.js 公式）
// https://www.chartjs.org/docs/latest/charts/radar.html

// 色の設定
const colorSet = {
  // 線の色に用いる
  red   : '#ff251e',
  orange: '#f19072',
  yellow: '#ffec47',
  green : '#67a70c',
  blue  : '#2ca9e1',
  purple: '#674196',
  grey  : '#9ea1a3',

  // 背景色に用いる
  red_a   : '#ff251e80',
  orange_a: '#f1907280',
  yellow_a: '#ffec4780',
  green_a : '#67a70c80',
  blue_a  : '#2ca9e180',
  purple_a: '#67419680',
  grey_a  : '#9ea1a380',
}

// Setup
const data = {
  labels: ['麺の味', '汁の味', '具の味', 'ラーメンの量', '価格', '雰囲気', '立地'],
  datasets: [
    {
      label: '櫻幕ラーメン',
      data: [75, 79, 90, 70, 100, 55, 40],
      backgroundColor: colorSet.orange_a, // 背景色
      borderColor: colorSet.orange,       // 線の色
      fill: true,                         // 塗りつぶす
    },
    {
      label: '平均',
      data: [58, 48, 40, 65, 56, 47, 50],
      backgroundColor: colorSet.blue_a,
      borderColor: colorSet.blue,
      fill: false,
    }
  ]
};

// Config
const config = {
  type: 'radar',  // グラフの種類 レーダーチャート
  data: data,     // 上で定義した data オブジェクト読み込み 描画する
  options: {
    plugins: {
      legend: {
        position: 'bottom',     // 凡例は図の下に表示
      }
    },
    maintainAspectRatio: false, // 親要素の大きさに合わせ、図を描画する
    elements: {
      line: {
        borderWidth: 3          // 線の太さは 3px
      }
    },
    scales: {
      r: {
           suggestedMin: 0,     // 最小値 0
           suggestedMax: 100    // 最大値 100 の図を描画する
         }
      }
    },
};

// Canvas要素を取得
const ctx     = document.getElementById('myChart');
// 取得したCanvas要素に、config に基づき、図を描画する
const myChart = new Chart(ctx, config);
//}

レーダーチャートの描画方法について @<href>{ https://www.chartjs.org/docs/latest/charts/radar.html,公式サイト} に詳しい説明がございますので、それを参考にしつつ、作成いたしました。

線の色や背景色を定義し、ラーメンに関する各データ系列を準備、グラフの種類等細かい調整を行って描画するコードとなっています。

== ★による評価

//sideimage[star][60mm][sep=5mm,side=R]{
ラーメンの味などをレーダーチャートを使って分かりやすく表示することができました。
総合評価として、★を使って評価したいと思います。

少し前の書籍ではございますが、「今すぐ使えるCSSレシピブック」に掲載されておりますので、ご紹介いたします。
//}

//list[][]{
<div class="rating" data-rate="3.5">
  <span class="star"></span>
  <span class="star"></span>
  <span class="star"></span>
  <span class="star"></span>
  <span class="star"></span>
</div>
//}

//list[][]{
.rating { display: inline; }
.star { font-size: 3rem; margin: 0 .05em; }

.star::before {
  content: '\f005';
  color: #ffec47;
  font-weight: 900;
  font-family: 'Font Awesome 6 Free';
}

.rating[data-rate="0"]   .star:nth-child(n+1)::before,
.rating[data-rate="0.5"] .star:nth-child(n+1)::before,
.rating[data-rate="1"]   .star:nth-child(n+2)::before,
.rating[data-rate="1.5"] .star:nth-child(n+2)::before,
.rating[data-rate="2"]   .star:nth-child(n+3)::before,
.rating[data-rate="2.5"] .star:nth-child(n+3)::before,
.rating[data-rate="3"]   .star:nth-child(n+4)::before,
.rating[data-rate="3.5"] .star:nth-child(n+4)::before,
.rating[data-rate="4"]   .star:nth-child(n+5)::before,
.rating[data-rate="4.5"] .star:nth-child(n+5)::before {
  color: #9ea1a3;
  font-weight: 400;
}

.rating[data-rate="0.5"] .star:nth-child(1)::before,
.rating[data-rate="1.5"] .star:nth-child(2)::before,
.rating[data-rate="2.5"] .star:nth-child(3)::before,
.rating[data-rate="3.5"] .star:nth-child(4)::before,
.rating[data-rate="4.5"] .star:nth-child(5)::before {
  content: '\f5c0';
  color: #ffec47;
  font-weight: 900;
  font-family: 'Font Awesome 6 Free';
}
//}

以上、簡単ではございましたが、Chart.js によるグラフ描画のご紹介でした。
ご活用いただければ幸いです。
