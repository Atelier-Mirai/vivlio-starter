= 画像の絞り込み

//abstract{
沢山の画像から目的のものを抽出する。そういった機能を備えている JavaScript ライブラリとして「Muuri」があります。ここでは、架空のラーメン店の紹介を例に、使い方のご紹介を致します。
//}

== Muuri

#@# Muuriとはフィンランド語で「壁」の意味を持つ語で、
@<href>{https://muuri.dev/,Muuri}公式サイトによると、次のように紹介されています。
//quote{
  Muuriは、レスポンシブで、ソート可能で、フィルタリング可能で、ドラッグ可能なレイアウトを作成します。

 最近では、JavaScriptを一行も使わずに、かなり素晴らしいレイアウトを構築することができます。しかし、時にはCSSだけでは十分でないことがあります。そこでMuuriの登場です。Muuriの核心は、あなたの想像力によってのみ制限されるレイアウトエンジンです。お望みであれば、ウェブワーカーで非同期に、どんな種類のレイアウトでも構築することができます。

 アニメーションやインタラクティブ機能（フィルタリング、ソート、ドラッグ＆ドロップ）をレイアウトに散りばめる必要があるかもしれません。これらの追加機能のほとんどはMuuriのコアに組み込まれており、追加のライブラリを探したり、何度も車輪を作り直したりする必要はありません。

 Muuriの長期的なゴールは、比類ないパフォーマンスと、複雑さのほとんどを抽象化した、素晴らしいレイアウトを構築するためのシンプルなAPIを提供することです。 (翻訳 DeepL)
//}

Muuriの豊富な機能の中から、絞り込み機能のご紹介を、架空の全国各地の有名ラーメン店の紹介を例に行っていきます。
@<href>{https://wave-improve.netlify.app/ramen/muuri.html,動作例}や@<href>{https://github.com/Atelier-Mirai/wave-improve/tree/master/ramen,ソースコード}もご活用下さい。

//image[ramen][][width=70%]

== HTML

それでは、HTML を書いていきましょう。公式サイトによると以下のように書くと良さそうです。

//list[][index.html]{
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>人気のラーメン店</title>

  <!-- 簡単に見栄えの良いページを作るためのスタイルシート -->
  <link rel="stylesheet" href="https://unpkg.com/sakura.css/css/sakura.css">
  <link rel="stylesheet" href="style.css">
</head>

<body>
  <h1>ラーメン人気店紹介</h1>
  <p>全国各地の美味しいラーメン店を紹介します。</p>
  <hr class="divider">

  <!-- 絞り込み -->
  <section class="grid-wrapper">
    <div class="form-group">
      <input type="text"
             id="search-field"
             class="form-input search-field"
             placeholder="所在地やラーメン店名などを入力">
      <select class="form-select filter-field">
        <option value=""        >全てを表示</option>
        <option value="shoyu"   >醤油ラーメンを表示</option>
        <option value="miso"    >味噌ラーメンを表示</option>
        <option value="shio"    >塩ラーメンを表示</option>
        <option value="tonkotsu">豚骨ラーメンを表示</option>
      </select>
    </div>

    <!-- ラーメン店紹介 -->
    <div class="grid">
      <div class="item">
        <div class="item-content">
          <!-- Safe zone, enter your custom markup
          This can be anything.
          Safe zone ends -->
        </div>
      </div>
    </div>
  </section>

  <!-- Muuri -->
  <script src="https://cdn.jsdelivr.net/npm/muuri@0.9.5/dist/muuri.min.js"></script>
  <script src="muuri_filter.js"></script>
</body>
</html>
//}

絞り込みのための入力欄を用意し、紹介するラーメン店の画像や説明文、最後にMuuriライブラリと絞り込み用のスクリプトを読み込むというシンプルな形です。

//blankline
中核となるラーメン店の紹介ですが、
//list[][]{
<div class="item">
  <div class="item-content">
    <!-- Safe zone, enter your custom markup
    This can be anything.
    Safe zone ends -->
  </div>
</div>
//}
と書かれているように、内部には好きな HTML をマークアップできるようですので、お店の紹介として、次のようなマークアップを行うことにしましょう。

//list[][]{
<div class="item" data-color="shoyu" data-title="櫻幕ラーメンは 京都市東区にある 醤油ラーメンが人気のお店。280円とお財布に優しいお店である。">
  <div class="item-content">
    <div class="card">
      <figure class="card-image">
        <img src="images/ramen01.webp" loading="lazy">
      </figure>
      <h2 class="card-title">
        [京都市] 櫻幕ラーメン
      </h2>
      <p class="card-desc">
        櫻幕ラーメンは 京都市東区にある 醤油ラーメンが人気のお店。280円とお財布に優しいお店である。
      </p>
    </div>
  </div>
</div>
//}

@<code>{data-color="shoyu"} は、醤油、味噌、塩、豚骨とラーメンのスープの色で絞り込みが行えるようにしていきます。
@<code>{data-title="櫻幕ラーメンは 京都市東区にある 醤油ラーメンが人気のお店。280円とお財布に優しいお店である。} は、利用者からの文字入力による絞り込みを行うためのもので、「京都市」や「櫻幕ラーメン」などと入力すると、該当するラーメン店が抽出されます。

これを二十四店舗分作成し、
//list[][]{
<!-- ラーメン店紹介 -->
<div class="grid">
  <div class="item">一軒目のラーメン店</div>
  <div class="item">二軒目のラーメン店</div>
  <div class="item">三軒目のラーメン店</div>
                    　・
                    　・
                    　・
  <div class="item">二十四軒目のラーメン店</div>
</div>
//}

とすれば完成ですが、少し大変です。

そこで次のような、Ruby スクリプトで作り上げることと致しましょう。

//list[][ramen.rb]{
city_list   = %w(札幌市 仙台市 東京都 京都市 大阪市 福岡市)
ward_list   = %w(北区 東区 南区 西区)
shurui_list = %w(豚骨 醤油 味噌 塩)
name_list   = %w(松鶴 梅鶯 櫻幕 藤帰 菖蒲 牡丹 萩猪 芒月 菊盃 紅葉 柳風 鳳凰)
price_list  = %w(280 380 480 580 680 780 880 980)

(1..24).to_a.each.with_index(1) do |_, index|
  city          = city_list.sample
  address       = "#{city}#{ward_list.sample}"
  shurui        = shurui_list.sample
  shurui_romaji = { 豚骨: "tonkotsu",
                    醤油: "shoyu",
                    味噌: "miso",
                    塩: "shio" }[shurui.to_sym]
  name          = name_list.sample
  price         = price_list.sample.to_i
  phrase        = if price < 500
                    "お財布に優しいお店である"
                  elsif price < 800
                    "良心的な価格設定が嬉しい"
                  else
                    "高価だが価値ある逸品"
                  end
  comment = "#{name}ラーメンは #{address}にある #{shurui}ラーメンが人気のお店。#{price}円と#{phrase}。"
  idx = sprintf("%02d", index)

  html = <<~EOS
    <div class="item" data-color="#{shurui_romaji}" data-title="#{comment}">
      <div class="item-content">
        <div class="card">
          <figure class="card-image">
            <img src="images/ramen#{idx}.webp" loading="lazy">
          </figure>
          <h2 class="card-title">
            [#{city}] #{name}ラーメン
          </h2>
          <p class="card-desc">
            #{comment}
          </p>
        </div>
      </div>
    </div>
  EOS

  puts html
end
//}

Ruby は、まつもとひろゆきさんが創られたプログラミング言語で、柔軟性とその優れた書き味からとても人気があります。環境をお持ちでないかたは、 @<href>{https://paiza.io/ja/projects/new,paiza.io}から実行できます。

出力結果を貼り付けたら、HTML の完成です。 @<fn>{tenmei}

//footnote[tenmei][ちなみに店名は花札から取っています。]

== CSS

//list[][style.css]{
/* sakura.css の補正 */
body { max-width: 90%; }

/* 区切り線 ラーメンらしく雷門の模様に */
.divider { background-image: url("images/raimon_ss.webp");
           height: 20px;
           border: none;
           overflow: none; }

/* 24店舗をグリッドで配置する */
.grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: 20px;
}

/* ラーメンの種類に応じて枠線を付ける */
div[data-color="shoyu"]    { border: 5px solid #674196; }
div[data-color="miso"]     { border: 5px solid #f19072; }
div[data-color="shio"]     { border: 5px solid #2ca9e1; }
div[data-color="tonkotsu"] { border: 5px solid #ffec47; }

/* Muuri 補正 */
.item { transform: none !important; }

/* ラーメンカードに適宜余白等設定 */
.card .card-image { margin: 0; }
.card .card-image img { width: 100%; height: auto; }
.card h2,
.card p { padding: 0.5em; }
.card h2 { margin: 0; font-size: 1.5em; }
//}

特段、凝ったことはしていない普通のスタイルシートです。
CSSグリッドレイアウトにより二十四店舗を配置し、ラーメンのスープの色に応じて枠線を付け、種類を分かりやすくしています。 @<fn>{ramengazou}

//footnote[ramengazou][ラーメンの画像は Google 検索により落としてきたものであり、また無作為にデータを作っていることから画像と種類が対応しないものもありますが、それは許容しましょう。]

== JavaScript

公式サイトによると、次のように書くことで、絞り込みが行えるようです。

//list[][muuri_filter.js]{
document.addEventListener('DOMContentLoaded', () => {
  let grid        = null;
  let wrapper     = document.querySelector('.grid-wrapper');
  let searchField = wrapper.querySelector('.search-field');
  let filterField = wrapper.querySelector('.filter-field');
  let gridElem    = wrapper.querySelector('.grid');
  let searchAttr  = 'data-title';
  let filterAttr  = 'data-color';
  let searchFieldValue;
  let filterFieldValue;

  // Init the grid layout
  grid = new Muuri(gridElem, {
    dragEnabled: false
  });

  grid._settings.layout = {
    horizontal:  false,
    alignRight:  false,
    alignBottom: false,
    fillGaps:    false
  };
  grid.layout();

  // Set inital search query, active filter, active sort value and active layout.
  searchFieldValue = searchField.value.toLowerCase();
  filterFieldValue = filterField.value;

  // Search field event binding
  searchField.addEventListener('keyup', () => {
    let newSearch = searchField.value.toLowerCase();
    if (searchFieldValue !== newSearch) {
      searchFieldValue = newSearch;
      filter();
    }
  });

  // Filtering
  const filter = () => {
    filterFieldValue = filterField.value;
    grid.filter( (item) => {
      let element = item.getElement(),
          isSearchMatch = !searchFieldValue ? true : (element.getAttribute(searchAttr) || '').toLowerCase().indexOf(searchFieldValue) > -1,
          isFilterMatch = !filterFieldValue ? true : (element.getAttribute(filterAttr) || '') === filterFieldValue;
      return isSearchMatch && isFilterMatch;
    });
  }

  // Filter field event binding
  filterField.addEventListener('change', filter);
});
//}

簡単ではございましたが、Muuri による絞り込み機能のご紹介でした。
ご活用いただければ幸いです。
