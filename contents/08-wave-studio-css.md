# wave-studio を作ろう

:::{.chapter-lead}
前章までで、HTMLとCSSの考え方を学びました。この章では、実際に手を動かしながら `wave-studio` のトップページを段階的に作り上げていきます。

3つのステップを経て、シンプルな骨組みから、色と余白を整え、最終的にはコンポーネントに分割された本格的なサイトへと育てていきましょう。
:::



## 3つのステップで学ぶ

`wave-studio` プロジェクトには、学習用に3つの段階が用意されています：

| ステップ | フォルダ | 学べること |
|---------|---------|-----------|
| Step 1 | `work/` | HTML構造 + CSS Gridの基本 |
| Step 2 | `work2/` | 色・フォント・エフェクトの追加 |
| Step 3 | `work3/` | CSSのコンポーネント分割 |

各ステップで完成形のコードが用意されていますので、手元で動かしながら学べます。分からないところはAIに質問しながら進めましょう。

### 各ステップの完成イメージ

3つのステップを経て、サイトがどのように変化していくかを見てみましょう。

**Step 1（work/）: 骨組み**

:::{.flex-container}
![iPhone表示](work_iphone.webp){width=35%}
![iPad表示](work_ipad.webp){width=55%}
:::

CSS Grid で基本的なレイアウトを作成。装飾は最小限ですが、構造は整っています。

**Step 2（work2/）: 見た目の強化**

:::{.flex-container}
![iPhone表示](work2_iphone.webp){width=35%}
![iPad表示](work2_ipad.webp){width=55%}
:::

色・フォント・グラデーション・ホバーエフェクトが加わり、洗練された印象に。

**Step 3（work3/）: コンポーネント分割**

:::{.flex-container}
![iPhone表示](work3_iphone.webp){width=35%}
![iPad表示](work3_ipad.webp){width=55%}
:::

外部リソース（Font Awesome、Google Fonts）も活用した完成形。CSSはファイル分割され保守しやすい構成に。



## Step 1: 骨組みを作る

### 目標

まずは `work/` フォルダで、HTML と最小限の CSS を使って基本的なレイアウトを作ります。

:::{.sideimage-right}
![](work_iphone.webp){width=30%}

Step 1 の完成形（iPhone表示）です。装飾は最小限ですが、CSS Grid によってヘッダー・メイン・フッターが整然と配置されています。
:::

### HTMLの構造

`work/index.html` の骨組みは次のようになっています：

```html
<body>
  <header><a href="index.html">WAVE</a></header>
  <nav><!-- メニュー --></nav>
  <main>
    <figure class="hero"><!-- ヒーロー画像 --></figure>
    <h1 class="catch_phrase">...</h1>
    <p class="sub_title">...</p>
    <section id="recent"><!-- 記事一覧 --></section>
  </main>
  <footer><!-- 連絡先 --></footer>
</body>
```

前章で学んだセマンティックHTMLの考え方で、各部分に適切なタグを使っています。

### CSS Gridでレイアウト

`work/style.css` では、`<body>` にCSS Gridを適用して全体のレイアウトを定義しています：

```css
body {
  display: grid;
  grid-template:
    ".    head .   " 100px
    "main main main" auto
    "foot foot foot" 140px /
    20px  1fr  20px;
  row-gap: 20px;
}
```

この指定は：
- **3行**: ヘッダー(100px)、メイン(自動)、フッター(140px)
- **3列**: 左余白(20px)、中央(残り全部)、右余白(20px)

というグリッドを作っています。`.`は「空のマス目」を表します。

### 子要素の配置

各要素を `grid-area` でマス目に配置します：

```css
header { grid-area: head; }
footer { grid-area: foot; }

body main {
  grid-area: main;
  display: grid;  /* mainの中にもグリッドを作る */
  /* ... */
}
```

グリッドは入れ子（ネスト）にできるので、`<main>` の中にさらにグリッドを作って、ヒーロー画像や記事一覧を配置しています。

### リセットCSSの基本

ブラウザの標準スタイルをリセットして、自分のデザインを適用しやすくしています：

```css
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

img {
  width: 100%;
  height: auto;
}
```

### AIに聞いてみよう

Step 1 で分からないことがあったら：

> - 「CSS Gridの`grid-template`の書き方を詳しく教えて」
> - 「`grid-area`と`grid-column`の違いは？」
> - 「`1fr`という単位は何？」



## Step 2: 見た目を整える

### 目標

`work2/` フォルダでは、Step 1 の骨組みに色・フォント・エフェクトを追加して、見た目を整えます。

:::{.sideimage-right}
![](work2_iphone.webp){width=30%}

Step 2 の完成形（iPhone表示）です。日本の伝統色、Webフォント、ホバーエフェクトなどが加わり、洗練された印象になっています。
:::

### CSSカスタムプロパティで色を定義

色を変数として定義しておくと、サイト全体で統一感を保ちやすくなります：

```css
:root {
  --kyohiiro:     #ff251e;  /* 京緋色 */
  --amairo:       #2ca9e1;  /* 天色 */
  --sakurairo:    #fef4f4;  /* 桜色 */
  --kurohairo:    #0d0d0d;  /* 黒羽色 */
  /* ... */
}
```

使うときは `color: var(--amairo);` のように書きます。

### Webフォントの読み込み

Google Fonts から美しい日本語フォントを読み込みます：

```html
<link rel="stylesheet"
      href="https://fonts.googleapis.com/css2?family=Yuji+Boku&display=swap">
```

```css
h1 {
  font-family: "Yuji Boku", serif;
}
```

### グラデーション背景

青空と海をイメージしたグラデーション：

```css
body {
  background: linear-gradient(to top,
    #FFFFFF80,
    #6DD5FA40,
    #2980B980);
}
```

### 虹色ヘッダー

サイト名「WAVE」を虹色のグラデーションで彩ります。ポイントは `background-clip: text` です：

```css
header {
  color: transparent;  /* 文字自体は透明に */
  background: repeating-linear-gradient(45deg,
    #e60012 0.1em 0.2em,  /* 赤 */
    #f39800 0.2em 0.3em,  /* 橙 */
    #fff100 0.3em 0.4em,  /* 黄 */
    #009944 0.4em 0.5em,  /* 緑 */
    #0068B7 0.5em 0.6em,  /* 青 */
    #1d2088 0.7em 0.8em,  /* 藍 */
    #cfa7cd 0.8em 0.9em); /* 紫 */
  background-clip: text;  /* 背景を文字の形で切り抜く */
}
```

`background-clip: text` を使うと、グラデーション背景が文字の形に切り抜かれ、虹色の文字が実現できます。

### ボタンのスタイリング

`.sub_title` 内のリンクをボタン風に装飾します：

```css
.sub_title a {
  display: inline-block;
  color: var(--sakurairo);
  border: solid 1px var(--sakurairo);
  padding-block: var(--space-m);
  padding-inline: 40px;
  border-radius: 10px;
  background: linear-gradient(45deg, var(--amairo), var(--utsushiiro));
  transition: all 0.5s ease-in-out;
}

.sub_title a:hover {
  background: var(--shinonomeiro);
  transform: scale(1.1) rotate(-3deg);  /* 拡大＋回転 */
}
```

`transition` を指定しておくことで、ホバー時の変化が滑らかになります。

### 疑似要素で見出しを装飾

記事タイトルの `<h3>` を `::before` と `::after` 疑似要素で装飾します：

```css
section#recent h3::before {
  content: "▼";
  color: var(--nanohanairo);  /* 菜の花色 */
}

section#recent h3::after {
  content: "▲";
  color: var(--utsushiiro);   /* 移色 */
}
```

疑似要素は HTML を変えずにCSSだけで装飾を追加できる便利な機能です。`content` プロパティで表示する内容を指定します。

### レスポンシブ対応

画面幅に応じてレイアウトを変えるメディアクエリ：

```css
@media (width >= 768px) {
  section#recent {
    grid-template-columns: repeat(3, 1fr);  /* 3列に */
  }
}
```

### AIに聞いてみよう

Step 2 で分からないことがあったら：

> - 「CSSのtransitionの使い方を教えて」
> - 「グラデーションで透明度を指定するには？」
> - 「メディアクエリの書き方を詳しく」



## Step 3: コンポーネントに分割する

### 目標

`work3/` フォルダでは、CSSを役割ごとのファイルに分割し、保守しやすい構成にします。

:::{.sideimage-right}
![](work3_iphone.webp){width=30%}

Step 3 の完成形（iPhone表示）です。見た目はStep 2とほぼ同じですが、CSSがコンポーネント単位で整理され、アイコンフォントも加わっています。
:::

### ファイル構成

```
work3/
├── index.html
├── stylesheets/
│   ├── master.css      ← 読み込みの起点
│   ├── _colors.css     ← 色の定義
│   ├── _reset.css      ← リセットCSS
│   ├── _layout.css     ← 全体レイアウト
│   ├── _header.css     ← ヘッダー
│   ├── _hero.css       ← ヒーロー画像
│   ├── _navigation.css ← ナビゲーション
│   ├── _recent.css     ← 記事一覧
│   ├── _footer.css     ← フッター
│   └── ...
└── javascripts/
    └── ...
```

### master.css で束ねる

`master.css` は各ファイルを `@import` で読み込むだけのファイルです：

```css
@import "_colors.css";
@import "_reset.css";
@import "_layout.css";
@import "_header.css";
@import "_hero.css";
/* ... */
```

こうしておくと：
- **どこに何があるか**が一目で分かる
- **部品単位で編集**できる
- **他のプロジェクトで再利用**しやすい

### 外部リセットCSSの活用

Step 3 では、自作のリセットCSSの代わりに、CDN（コンテンツ配信ネットワーク）から公開されているリセットCSSを読み込んでいます：

```html
<link rel="stylesheet"
      href="https://cdn.jsdelivr.net/npm/@acab/reset.css@0.11.0/index.min.css">
```

外部のリセットCSSを使うと、より包括的なリセットが適用され、自分で書くコード量を減らせます。

### Nested CSS（入れ子CSS）

Step 3 のCSSでは、**Nested CSS** 記法を使っています。セレクタを入れ子にして書けるので、構造が分かりやすくなります：

```css
section {
  grid-area: recent;

  /* 入れ子でメディアクエリを書ける */
  @media (width >= 768px) {
    grid-template-columns: repeat(4, 1fr);
  }

  /* 入れ子で子孫セレクタを書ける */
  a {
    color: var(--kurohairo);

    &:hover {  /* &は親セレクタを参照 */
      text-decoration: underline;
    }
  }

  h3 {
    &::before { content: "▼"; color: var(--nanohanairo); }
    &::after  { content: "▲"; color: var(--utsushiiro); }
  }
}
```

`&` は親セレクタを参照する記号です。従来は `section a:hover { ... }` と書いていたものが、入れ子の中で `&:hover` と書けるようになりました。

### Font Awesome でアイコン表示

ナビゲーションメニューにアイコンを追加しています：

```html
<link rel="stylesheet"
      href="https://use.fontawesome.com/releases/v7.1.0/css/all.css">
```

```html
<nav aria-label="主なメニュー">
  <a href="#recent">
    <i class="fa-regular fa-newspaper" aria-hidden="true"></i>
    最新記事
  </a>
</nav>
```

- `fa-regular fa-newspaper` … 新聞アイコン
- `aria-hidden="true"` … 装飾用アイコンを読み上げ対象外に

### JavaScriptで動きを追加

詳しくは次章のお楽しみですが、Step 3 では JavaScript による動的な機能も追加されています：

```html
<script src="javascripts/glow_text.js" defer></script>
<script src="javascripts/page_top.js" defer></script>
```

- **キラキラ光るキャッチコピー**: キャッチフレーズの文字が輝くアニメーション
- **先頭へ戻るボタン**: クリックでページ先頭にスムーズスクロール

CSS だけでは実現できないインタラクティブな機能は、JavaScript の出番です。

### AIに聞いてみよう

Step 3 で分からないことがあったら：

> - 「Nested CSSの書き方を詳しく教えて」
> - 「CSSの@importとlinkの違いは？」
> - 「Font Awesomeのアイコンを使う方法は？」
> - 「JavaScriptのdeferとは何？」



## 実践のコツ

### 1. 小さく始めて、少しずつ足す

最初から完璧を目指さず、まずは動くものを作り、少しずつ改善していきましょう。Step 1 → 2 → 3 の流れがまさにこの考え方です。

### 2. 開発者ツールを活用する

ブラウザの開発者ツール（右クリック → 「調査」または `F12`）を使うと：
- 要素に適用されているCSSを確認できる
- その場でCSSを変えて試せる
- レスポンシブデザインのプレビューができる

### 3. 分からないことはAIに聞く

「このCSSが効かない理由は？」「もっと良い書き方はある？」など、具体的なコードを見せながらAIに質問すると、的確なアドバイスが得られます。

### 4. 完成形のコードを参考にする

`wave-studio` のコード全体は [GitHub](https://github.com/Atelier-Mirai/wave-studio) で公開しています。困ったときは完成形を見て、自分のコードと比較してみましょう。



## この章のまとめ

- **Step 1**: HTML + CSS Gridで骨組みを作る
- **Step 2**: 色・フォント・エフェクトで見た目を整える
- **Step 3**: CSSをコンポーネントに分割して保守性を高める

3つのステップを通じて、シンプルなページが本格的なサイトへと育っていく過程を体験しました。

この流れは、どんなウェブサイトを作るときにも応用できます：

1. まず構造を作る（HTML）
2. 基本レイアウトを整える（CSS Grid）
3. 見た目を磨く（色・フォント・エフェクト）
4. コードを整理する（ファイル分割）

分からないことはAIに聞きながら、自分だけのウェブサイトを作っていきましょう。
