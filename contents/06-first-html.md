# <span id="idx-5376xxg0dgl-53" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>の考え方

:::{.chapter-lead}
ウェブサイト作成の土台となる`<span id="idx-5376xxg0dgl-54" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>`を学びます。この章では、<span id="idx-5376xxg0dgl-55" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>の詳細な文法よりも「なぜ<span id="idx-5376xxg0dgl-56" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>が必要なのか」「どういう考え方で書くのか」という本質に焦点を当てます。

細かな要素やルールは、AIに聞けばいつでも教えてもらえます。ここでは、AIに質問するときの「足場」となる考え方を身につけましょう。
:::



## <span id="idx-5376xxg0dgl-57" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>とは何か

### 文書に「意味」を与える

<span id="idx-5376xxg0dgl-58" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>は「HyperText Markup Language」の略で、日本語にすると「ハイパーテキストに印付けをする言語」という意味です。

人間が見れば「これは見出しだな」「これは本文だな」と分かる文章でも、コンピュータにはそれが分かりません。そこで、

- これは**見出し**です → `<h1>見出し</h1>`
- これは**段落**です → `<p>段落の文章</p>`
- これは**画像**です → `<img src="photo.jpg" alt="写真の説明">`

のように「タグ」で囲むことで、コンピュータにも文書の構造が伝わるようになります。これが<span id="idx-5376xxg0dgl-59" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>の基本的な役割です。

### セマンティック<span id="idx-5376xxg0dgl-60" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>

「セマンティック」とは「意味のある」という意味です。<span id="idx-5376xxg0dgl-61" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>では、見た目ではなく**意味**に基づいてタグを選ぶことが大切です。

例えば、文字を大きく太くしたいとき：

- ❌ 見た目で考える → 「大きくしたいから何かのタグを使おう」
- ✅ 意味で考える → 「これは見出しだから`<h1>`を使おう」

見た目の調整は<span id="idx-3ghtaxxv1hvr-74" class="index-term" data-yomi="しーえすえす">CSS</span>の役割です。<span id="idx-5376xxg0dgl-62" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>では「それが何であるか」を素直に表現することに集中しましょう。この考え方を**セマンティック<span id="idx-5376xxg0dgl-63" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>**と呼びます。

### なぜセマンティック<span id="idx-5376xxg0dgl-64" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>が大切なのか

意味に基づいてタグを選ぶと、次のような恩恵があります：

- **検索エンジン**が内容を正しく理解できる
- **音声読み上げソフト**が適切に読み上げられる
- **<span id="idx-3ghtaxxv1hvr-75" class="index-term" data-yomi="しーえすえす">CSS</span>での装飾**が一貫性を持って行える
- **将来の自分やチームメンバー**がコードを読みやすくなる

## <span id="idx-5376xxg0dgl-65" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>の基本構造

どんなウェブページも、基本的に次のような構造になっています：

```html
<!DOCTYPE html>
<html lang="ja">
  <head>
    <meta charset="utf-8">
    <title>ページのタイトル</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="style.css">
  </head>
  <body>
    <!-- ここに表示したい内容を書く -->
  </body>
</html>
```

- `<head>` … ページの「設定」を書く場所（タイトル、文字コード、<span id="idx-3ghtaxxv1hvr-76" class="index-term" data-yomi="しーえすえす">CSS</span>の読み込みなど）
- `<body>` … ページの「中身」を書く場所（読者の目に見える部分）

この構造は「お作法」として覚えておきましょう。AIに「<span id="idx-5376xxg0dgl-66" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>の雛形を作って」と頼めば、いつでも生成してくれます。

### `<head>` 内の必須設定

`<head>` に書かれている設定を見てみましょう：

```html
<meta charset="utf-8">
```

文字コードの指定です。`utf-8` は世界中の文字を扱える標準的な文字コードで、日本語を含むほとんどのウェブサイトで使われています。

```html
<meta name="viewport" content="width=device-width, initial-scale=1">
```

スマートフォンでの表示を正しく行うための設定です。これがないと、スマートフォンでもPC向けの縮小表示になってしまいます。

```html
<link rel="stylesheet" href="style.css">
```

<span id="idx-3ghtaxxv1hvr-77" class="index-term" data-yomi="しーえすえす">CSS</span>ファイルを読み込むための記述です。`rel="stylesheet"` は「このファイルはスタイルシートです」という意味、`href` で読み込むファイルの場所を指定します。<span id="idx-3ghtaxxv1hvr-78" class="index-term" data-yomi="しーえすえす">CSS</span>ファイルは複数読み込むこともできます。

これらは「おまじない」のようなものですが、意味を知っておくと、問題が起きたときに対処しやすくなります。

## よく使うタグの役割

<span id="idx-5376xxg0dgl-67" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>には100以上のタグがありますが、よく使うものは十数個です。ここでは代表的なものを「役割」で整理します。

### 文書の構造を示すタグ

| タグ | 役割 |
|------|------|
| `<header>` | ページやセクションの「頭」（サイト名、ロゴなど） |
| `<nav>` | ナビゲーションメニュー |
| `<main>` | ページの主要な内容 |
| `<section>` | 意味のあるまとまり（節） |
| `<article>` | 独立した記事やコンテンツ |
| `<footer>` | ページやセクションの「足」（著作権表示など） |

### 見出しと本文

| タグ | 役割 |
|------|------|
| `<h1>`〜`<h6>` | 見出し（h1が最も重要、h6が最も小さい） |
| `<p>` | 段落（paragraph） |

### リンクと画像

| タグ | 役割 |
|------|------|
| `<a href="...">` | リンク（anchor） |
| `<img src="..." alt="...">` | 画像 |
| `<figure>` | 図版（画像やコードなど） |

### 画像ファイルの形式

ウェブで使える画像形式には、いくつかの種類があります：

**主な画像形式**

| 形式 | 特徴 | 適した用途 |
|------|------|-----------|
| **JPEG（.jpg）** | 写真向け。色数が多く、ファイルサイズを小さくできる。透過不可 | 写真、グラデーションのある画像 |
| **PNG（.png）** | 透過に対応。可逆圧縮で画質劣化なし | ロゴ、アイコン、透過が必要な画像 |
| **GIF（.gif）** | 256色まで。アニメーションに対応。透過可能 | 簡単なアニメーション、シンプルな図 |
| **WebP（.webp）** | Google開発の次世代形式。JPEG/PNGより高圧縮で高画質。透過・アニメ対応 | あらゆる用途に推奨 |

**WebP が優れている理由**

WebP は、JPEG と同等の画質を保ちながらファイルサイズを 25〜35% 程度削減できます。PNG の透過機能も備え、GIF のようなアニメーションにも対応しています。


| 形式 | 特徴 | 適した用途 |
|------|------|-----------|
| **SVG（.svg）** | ベクター画像。数式で図形を記録するため拡大しても劣化しない。テキストや<span id="idx-3ghtaxxv1hvr-79" class="index-term" data-yomi="しーえすえす">CSS</span>で編集しやすい | ロゴ、アイコン、シンプルな図形・イラスト |

**ベクター画像** とは、JPEG や PNG のような「ピクセルを並べた写真」ではなく、「点や線・曲線の位置情報」で図形を記録する方式のことです。

```html
<img src="images/photo.webp" alt="海辺の写真">
```

現在、主要なブラウザ（Chrome、Firefox、Safari、Edge）はすべて WebP に対応しており、新規に画像を追加する際は WebP を第一候補にするとよいでしょう。

一方、ロゴやアイコンなど「線で構成された図形」は、ベクター形式の SVG で用意しておくと、どれだけ拡大しても輪郭がなめらかで、美しく表示されます。

### リスト

| タグ | 役割 |
|------|------|
| `<ul>` | 順序なしリスト（箇条書き） |
| `<ol>` | 順序ありリスト（番号付き） |
| `<li>` | リストの項目 |

:::{.note}
**タグの詳細はAIに聞こう**

各タグの細かな使い方や属性については、AIに質問すれば詳しく教えてもらえます。

> 「<span id="idx-5376xxg0dgl-68" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>の`<figure>`タグの使い方を教えて」
> 「`<a>`タグのtarget属性について説明して」

のように聞いてみましょう。
:::

## ブロック要素と<br>インライン要素

<span id="idx-5376xxg0dgl-69" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>の要素は、大きく2種類に分けられます：

| 種類 | 特徴 | 代表的な要素 |
|------|------|-------------|
| **ブロック要素** | 横幅いっぱいに広がり、前後で改行される | `<div>`, `<p>`, `<h1>`, `<section>`, `<header>` |
| **インライン要素** | 内容の幅だけを占め、改行されない | `<span>`, `<a>`, `<strong>`, `<img>` |

```html
<p>これは<a href="#">リンク</a>を含む段落です。</p>
```

この例では、`<p>`（ブロック）の中に`<a>`（インライン）が入っています。インライン要素は文章の流れの中に自然に溶け込みます。

この区別を知っておくと、<span id="idx-3ghtaxxv1hvr-80" class="index-term" data-yomi="しーえすえす">CSS</span>で「なぜ`width`が効かないのか」といった疑問を解決しやすくなります。

## コメントの書き方

<span id="idx-5376xxg0dgl-70" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>では、`<!--` と `-->` で囲んだ部分がコメントになります：

```html
<!-- これはコメントです。ブラウザには表示されません -->
<header>
  <!-- サイト名 -->
  <a href="index.html">WAVE</a>
</header>
```

コメントは「メモ書き」として使えます。AIが生成したコードにもコメントが付いていることが多いので、読み方を知っておくと理解が早まります。

## 属性で情報を追加する

タグには「属性」を付けて、追加の情報を指定できます：

```html
<a href="about.html" class="nav-link">サイトについて</a>
<img src="photo.webp" alt="海辺の写真" width="800">
```

よく使う属性：

- `href` … リンク先のURL
- `src` … 画像やスクリプトの場所
- `alt` … 画像の代替テキスト（必須）
- `class` … <span id="idx-3ghtaxxv1hvr-81" class="index-term" data-yomi="しーえすえす">CSS</span>や<span id="idx-ufy6mn67o2id-41" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span>で使う「グループ名」（複数要素に付けられる）
- `id` … ページ内で一意の「固有名」（1つだけ）

### id と class の違い

`id` と `class` はどちらも要素に名前を付ける属性ですが、使い方が異なります：

| 属性 | 付けられる数 | 用途 |
|------|-------------|------|
| `id` | ページ内に1つだけ | ページ内リンクの目印、<span id="idx-ufy6mn67o2id-42" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span>での特定 |
| `class` | 複数の要素に付けられる | <span id="idx-3ghtaxxv1hvr-82" class="index-term" data-yomi="しーえすえす">CSS</span>でのスタイル指定、グループ化 |

```html
<!-- idは1つの要素にだけ -->
<section id="recent">
  <!-- classは複数の要素に同じ名前を付けられる -->
  <article class="card">記事1</article>
  <article class="card">記事2</article>
  <article class="card">記事3</article>
</section>
```

<span id="idx-3ghtaxxv1hvr-83" class="index-term" data-yomi="しーえすえす">CSS</span>では、`id` は `#recent`、`class` は `.card` のように書き分けます。基本的には `class` を使い、ページ内リンクなど「唯一である必要があるとき」だけ `id` を使うのがおすすめです。

### <span id="idx-5376xxg0dgl-71" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span> / <span id="idx-3ghtaxxv1hvr-84" class="index-term" data-yomi="しーえすえす">CSS</span> / <span id="idx-ufy6mn67o2id-43" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span> の名前の付け方

<span id="idx-5376xxg0dgl-72" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>や<span id="idx-3ghtaxxv1hvr-85" class="index-term" data-yomi="しーえすえす">CSS</span>、<span id="idx-ufy6mn67o2id-44" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span>では、**ファイル名やクラス名の付け方にも一定の慣習**があります。ここでは、この本で使う主なルールだけを簡単にまとめておきます。

| 種類       | ファイル名の例            | 中で使う名前の例                     | よく使われる書き方 |
|------------|---------------------------|--------------------------------------|--------------------|
| <span id="idx-5376xxg0dgl-73" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>       | `about-us.html`          | （タグ名は仕様で決まっている）      | ケバブケース       |
| <span id="idx-3ghtaxxv1hvr-86" class="index-term" data-yomi="しーえすえす">CSS</span>        | `style-guide.css`        | `.primary-button`, `#main-header`   | ケバブケース       |
| <span id="idx-ufy6mn67o2id-45" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span> | `helper-functions.js`    | `initialValue`, `getUserName()`     | キャメルケース     |

- **ケバブケース**: `about-us.html` のように、小文字 + 単語の区切りにハイフン（`-`）を使う書き方です。URL やファイル名、<span id="idx-3ghtaxxv1hvr-87" class="index-term" data-yomi="しーえすえす">CSS</span> のクラス名でよく使われます。
- **キャメルケース**: `initialValue` や `getUserName` のように、2単語目以降の先頭を大文字にする書き方です。<span id="idx-ufy6mn67o2id-46" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span> の変数名や関数名でよく使われます。

<span id="idx-5376xxg0dgl-74" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span> のコードを書くときは、次のように考えるとよいでしょう。

- ファイル名（`index.html`, `style.css`, `script.js` など）は **ケバブケース** で統一する。
- <span id="idx-3ghtaxxv1hvr-88" class="index-term" data-yomi="しーえすえす">CSS</span> のクラス名・ID 名も、`main-header`, `hero-image`, `nav-link` のように **ケバブケース** にそろえる。
- <span id="idx-ufy6mn67o2id-47" class="index-term" data-yomi="じゃばすくりぷと">JavaScript</span> の変数名・関数名は、`userName`, `getPosts()` のように **キャメルケース** を使う。

プロジェクトの中でスタイルをそろえておくと、あとからコードを読んだときに「これは何の名前か」がすぐに分かるようになり、AI に質問するときにも説明しやすくなります。

ちなみに、命名規則の名前そのものも「見た目のイメージ」から来ています：

- **スネークケース（`snake_case`）**: 単語をアンダースコア（`_`）でつないだ形が、横に伸びたヘビ（snake）のように見えることから。
- **ケバブケース（`kebab-case`）**: ハイフン（`-`）で単語が串刺しになっている様子が、ケバブ（串に刺した肉料理）のように見えることから。
- **キャメルケース（`camelCase`）**: 単語の区切りごとに大文字がポコポコと現れる形が、フタコブラクダ（camel）の背中のコブに似ていることから。

由来のイメージを一緒に覚えておくと、どの書き方がどの名前だったかを思い出しやすくなります。

## studio-wave の<br><span id="idx-5376xxg0dgl-75" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>を眺める

本書で作成していく `studio-wave` のトップページは、次のような構造になっています：

```html
<!DOCTYPE html>
<html lang="ja">
  <head>
    <meta charset="utf-8">
    <title>WAVE</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="style.css">
  </head>
  <body>
    <header><a href="index.html">WAVE</a></header>
    <nav><!-- ナビゲーションメニュー --></nav>
    <main>
      <figure class="hero"><!-- ヒーローイメージ --></figure>
      <h1 class="catch_phrase">Best place to visit...</h1>
      <section id="recent"><!-- 最新記事一覧 --></section>
    </main>
    <footer><!-- 連絡先・著作権表示 --></footer>
  </body>
</html>
```

この骨組みを見ると：

- `<header>` にサイト名
- `<nav>` にメニュー
- `<main>` に本編（ヒーロー画像、キャッチコピー、記事一覧）
- `<footer>` に連絡先

という構造が、タグの名前から読み取れます。これがセマンティック<span id="idx-5376xxg0dgl-76" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>の良さです。

完全なソースコードは、次章以降で段階的に組み上げていきます。また、GitHubの [studio-wave リポジトリ](https://github.com/Atelier-Mirai/studio-wave) からいつでもダウンロードできます。

## AIへの質問例

<span id="idx-5376xxg0dgl-77" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>で分からないことがあったら、次のような質問をAIにしてみましょう：

> **基本的な質問**
> - 「<span id="idx-5376xxg0dgl-78" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>で画像を表示するにはどうすればいい？」
> - 「リンクを新しいタブで開くには？」
> - 「箇条書きと番号付きリストの違いは？」

> **セマンティックな質問**
> - 「記事のまとまりを表すのに適したタグは？」
> - 「`<section>`と`<article>`の使い分けは？」
> - 「`<div>`と`<section>`どちらを使うべき？」

> **実践的な質問**
> - 「ナビゲーションメニューの<span id="idx-5376xxg0dgl-79" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>を書いて」
> - 「この<span id="idx-5376xxg0dgl-80" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>にアクセシビリティの観点で問題はある？」
> - 「フォームの送信先を設定するには？」

## この章のまとめ

- <span id="idx-5376xxg0dgl-81" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>は文書に「意味」を与えるための言語
- **見た目ではなく意味**でタグを選ぶ（セマンティック<span id="idx-5376xxg0dgl-82" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>）
- `<head>` は設定、`<body>` は内容
- よく使うタグは十数個。役割で覚えておく
- 細かな文法はAIに聞けばいつでも教えてもらえる

次章では、<span id="idx-5376xxg0dgl-83" class="index-term" data-yomi="えいちてぃーえむえる">HTML</span>で作った骨組みに「見た目」を与える<span id="idx-3ghtaxxv1hvr-89" class="index-term" data-yomi="しーえすえす">CSS</span>を学びます。
