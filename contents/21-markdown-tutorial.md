# Markdown 執筆チュートリアル

:::{.chapter-lead}
本章では、Vivlio Starter で技術書を執筆するための Markdown 記法を体系的に解説します。標準の Markdown 記法から始まり、Vivliostyle Flavored Markdown（VFM）の拡張機能を紹介しています。次章の Vivlio Starter 独自の便利な拡張記法も併せて習得することで、効率的に美しい技術書を作成できます。
:::

## Markdown とは

### Markdown の概要

Markdown は、ジョン・グルーバー（John Gruber）とアーロン・スワーツ（Aaron Swartz）によって2004年に開発された軽量マークアップ言語です。「書きやすく、読みやすい」ことを目指して設計され、プレーンテキストで構造化された文書を作成できます。

### 開発者と歴史

#### 開発者
- **ジョン・グルーバー**: Daring Fireball の著者、Markdown の考案者
- **アーロン・スワーツ**: プログラマー、情報活動家。14歳で RSS 1.0 の仕様策定に貢献

#### 歴史的背景
- **2004年**: Markdown 最初のバージョン公開
- **2014年**: CommonMark プロジェクト開始（標準化の取り組み）
- **2017年**: GitHub Flavored Markdown（GFM）の仕様公開
- **2024年**: CommonMark 0.31.2 リリース（最新版）

### Markdown の特徴

#### 主な特徴
- **シンプル**: 直感的な記法で学習コストが低い
- **軽量**: 特別なソフトウェア不要で、テキストエディタで編集可能
- **汎用性**: 多くのプラットフォームでサポート
- **変換可能**: HTML、PDF、Word など様々な形式に変換
- **バージョン管理友好**: テキストファイルなので Git で管理しやすい

#### なぜ Markdown が選ばれるのか
- **執筆に集中**: 書式設定から解放され、内容に集中できる
- **移植性**: どの環境でも同じように表示される
- **ウェブ対応**: HTML との親和性が高く、ウェブ公開が容易
- **技術文書向け**: コードブロック、テーブル、リストなど技術文書に必要な要素をサポート

### 主な用途

#### 技術分野
- **ドキュメント**: API ドキュメント、仕様書
- **README**: GitHub や GitLab のプロジェクト説明
- **技術ブログ**: Zenn、Qiita、Note などのプラットフォーム
- **学術論文**: 簡単な学術文書やレポート

#### 出版分野
- **技術書**: プログラミング言語の入門書
- **同人誌**: 技術同人誌や個人出版
- **電子書籍**: EPUB や PDF 形式の電子書籍
- **マニュアル**: 製品マニュアルや取扱説明書

#### その他
- **メモ**: 個人の知識管理
- **スライド**: Markdown からプレゼンテーション作成
- **チャット**: Slack や Discord での整形テキスト

### Markdown のエコシステム

#### 処理系
- **パーサー**: Markdown を解析するライブラリ
- **レンダラー**: 各形式に変換するツール
- **エディタ**: Markdown 専用の編集環境

#### 拡張仕様
- **CommonMark**: 標準仕様
- **GFM**: GitHub の拡張
- **VFM**: Vivliostyle の拡張
- **Pandoc**: 学術文書向けの拡張

### Vivlio Starter と Markdown

Vivlio Starter は Markdown を中核技術として採用し、技術書執筆に最適化された環境を提供します：

- **VFM 対応**: 出版物向けの拡張機能
- **PDF 生成**: CSS 組版による美しい出力
- **相互参照**: 技術書に必須の参照機能
- **自動化**: ビルドプロセスの完全自動化

## 標準 Markdown 記法

標準 Markdown 記法は CommonMark 仕様（バージョン 0.31.2）に基づいています。これは曖昧さを排除し、一貫性を確保するための標準仕様です。

### 見出し

```markdown
# 第1レベル見出し
## 第2レベル見出し
### 第3レベル見出し
#### 第4レベル見出し
##### 第5レベル見出し
###### 第6レベル見出し
```

#### ATX 形式のルール
- `#` の数でレベルを指定（1〜6）
- 行頭に記述し、少なくとも1つのスペースを空ける
- 末尾の `#` はオプション（装飾として）

### テキスト装飾

```markdown
**太字** または __太字__
*斜体* または _斜体_
***太字と斜体***
~~取り消し線~~
```

### リスト

#### 箇条書きリスト
```markdown
- 項目1
- 項目2
  - 子項目1
  - 子項目2
- 項目3
```

#### 番号付きリスト
```markdown
1. 最初の項目
2. 2番目の項目
3. 3番目の項目
   1. 子項目1
   2. 子項目2
```

#### リストのルール
- **箇条書き**: `-`, `*`, `+` のいずれかで開始
- **番号付き**: 数字とドットで開始（実際の数字は無視）
- **インデント**: 親リスト項目のテキスト開始位置に合わせてインデント
- **ネスト**: 番号付きリストの入れ子もサポート（CommonMark 仕様）

### コードブロック

インラインコード: `code`

バッククォート自身を含む場合は、2つのバッククォートで囲みます: `` ` ``

フェンスコードブロック:
```ruby
def hello(name)
  puts "Hello, #{name}!"
end
```

言語指定付きフェンス:
```javascript
function main() {}
```

#### コードブロックの種類
- **インラインコード**: バッククォート1つで囲む。バッククォート自身を表現する場合は `` ` `` のように2つのバッククォートで囲む
- **フェンスコードブロック**: 3つのバッククォート（` ``` `）で囲む（言語指定可能）

#### 入れ子コードブロック

コードブロックの中にコードブロックを記述することもできます。その場合には、`~`（チルダ）を使うか、あるいは外側の`` ` ``（バッククォート）の数を増やすことで記述できます。

チルダを使う場合:

~~~markdown
```ruby
def hello(name)
  puts "Hello, #{name}!"
end
```
~~~

バッククォートを4つに増やす場合:

````markdown
```ruby
def hello(name)
  puts "Hello, #{name}!"
end
```
````

### 水平線

3つ以上のハイフン・アスタリスク・アンダースコアのいずれかで水平線を描けます。

```markdown
---
***
___
```

### エスケープ

`\`（バックスラッシュ）を前置することで、Markdown の記法として解釈される記号をそのまま表示できます。

```markdown
\*アスタリスク\*
\`バッククォート\`
\# ハッシュ
\- ハイフン
```

### 表（テーブル）

表を表示するには次のように記述します。

```markdown
| 言語      | 開発者              | 主な特徴                     |
|-----------|---------------------|------------------------------|
| HTML      | Tim Berners-Lee     | ウェブページの構造を定義       |
| CSS       | Håkon Wium Lie       | スタイルとレイアウトを制御     |
| JavaScript| Brendan Eich        | 動的なウェブ機能を実装         |
| Ruby      | まつもとゆきひろ   | オブジェクト指向スクリプト言語 |
```

#### 配置制御の例

それぞれの枡目（セル）の配置を指定することも可能です。

```markdown
| 左揃え              | 中央揃え | 右揃え |
|:--------------------|:-------:|-------:|
| これは左に配置されます | 中央です   | 右です |
| 長いテキスト        | 短い     | 123    |
```

#### テーブルのルール（GFM拡張）
- パイプ `|` で列を区切る
- ハイフン `-` でヘッダーと本体を区切る
- コロン `:` で配置を制御
  - `:--` 左寄せ（デフォルト）
  - `:-:` 中央揃え
  - `--:` 右寄せ

### リンクと画像

```markdown
[リンクテキスト](https://example.com)
![代替テキスト](画像パス)
[リンクテキスト](https://example.com "タイトル")
![代替テキスト](画像パス "タイトル")
```

#### リンクの形式
- **インラインリンク**: `[text](url)`
- **参照リンク**: `[text][id]` と `[id]: url`
- **自動リンク**: `<https://example.com>`

### 引用ブロック

```markdown
> 通常の引用

> **引用元**: 著者名
> 
> 引用内容を詳細に記述できます。

> 入れ子の引用
>> 2レベル目の引用
```

#### 引用ブロックのルール
- `>` で始まる行が引用
- 連続する `>` で複数段落
- `>>` で入れ子引用

### 生のHTML

```markdown
<div class="custom">
  これはHTML要素です
</div>
```

CommonMark ではHTMLタグをそのまま使用できます。

## VFM（Vivliostyle Flavored Markdown）の記法

VFM は CommonMark と GitHub Flavored Markdown（GFM）をベースに、出版物の執筆に最適化された Markdown 方言です。CSS組版の先駆者として有名なVivliostyleで採用されています。

### コードブロックのキャプション

コードブロックにキャプションを付けることができます。ファイル名はコロン（`:`）またはスペース区切りの `title=` で指定します。

~~~markdown
```javascript:app.js
const main = () => {
  console.log("Hello, World!");
  return 42;
};
```
~~~

`title=` を使った書き方も同等です。

~~~markdown
```javascript title=app.js
const main = () => {
  console.log("Hello, World!");
  return 42;
};
```
~~~

#### HTML 出力
```html
<figure class="language-javascript">
  <figcaption>app.js</figcaption>
  <pre><code class="language-javascript">const main = () => {
  console.log("Hello, World!");
  return 42;
};</code></pre>
</figure>
```

### 脚注

脚注は次のように記述します。参照番号による脚注と、インライン脚注の2種類があります。

#### 参照番号による脚注
`[^css]` のように記述し、文末に `[^css]: 内容` の形で定義します。同じ脚注を本文中で何度も参照でき、詳細な説明や外部リンクに適しています。

#### インライン脚注
`^[簡単な補足]` のように記述し、その場で内容を完結させます。一回限りの短い注釈に便利で、定義を別に書く必要がありません。

```markdown
VivliostyleはCSS組版の先駆者です[^css]。
詳細は公式ドキュメントを参照^[簡単な補足]。

[^css]: [CSS組版の歴史](https://example.com/css-history)
```

#### HTML 出力
```html
<p>
  VivliostyleはCSS組版の先駆者です<sup>1</sup>。
  詳細は公式ドキュメントを参照<sup>2</sup>。
</p>
<section class="footnotes" role="doc-endnotes">
  <hr>
  <ol>
    <li id="fn1"><a href="https://example.com/css-history">CSS組版の歴史</a></li>
    <li id="fn2">簡単な補足</li>
  </ol>
</section>
```

### 画像のキャプションと属性

単独行に記述された画像（alt テキストあり）は自動的に `<figure>` でラップされ、alt テキストがキャプションになります。同一段落内にテキストと混在する画像はキャプションなしのインライン画像として扱われます。

```markdown
![Figure 1](./fig1.png)

![Figure 2](./fig2.png "Figure 2"){id="image" data-sample="sample"}

text ![Figure 3](./fig3.png)
```

#### HTML 出力
```html
<figure>
  <img src="./fig1.png" alt="Figure 1">
  <figcaption aria-hidden="true">Figure 1</figcaption>
</figure>
<figure>
  <img src="./fig2.png" alt="Figure 2" title="Figure 2" id="image" data-sample="sample">
  <figcaption aria-hidden="true">Figure 2</figcaption>
</figure>
<p>text <img src="./fig3.png" alt="Figure 3"></p>
```

### 数式（Math）

MathJax を使った数式表示が利用できます。デフォルトで有効です。

インライン数式は `$...$`、ディスプレイ数式は `$$...$$` で記述します。

```markdown
インライン: $a^2 + b^2 = c^2$

ディスプレイ: $$e^{i\pi} + 1 = 0$$
```

無効にしたい場合は Frontmatter で指定します。

```markdown
---
vfm:
  math: false
---
```

### セクション化（Sectionization）

VFM では見出しを自動的に階層的な `<section>` でラップします。見出しにカスタム ID やクラスを付与することもできます。

```markdown
# Plain

# Introduction {#intro}

# Welcome {.title}

# Level 1

## Level 2

### Level 3
```

#### HTML 出力
```html
<section class="level1">
  <h1 id="plain">Plain</h1>
</section>
<section class="level1">
  <h1 id="intro">Introduction</h1>
</section>
<section class="level1">
  <h1 class="title" id="welcome">Welcome</h1>
</section>
<section class="level1">
  <h1 id="level-1">Level 1</h1>
  <section class="level2">
    <h2 id="level-2">Level 2</h2>
    <section class="level3">
      <h3 id="level-3">Level 3</h3>
    </section>
  </section>
</section>
```

セクションを途中で終了させたい場合は、対応する数の `#` だけの行を使います。

```markdown
# Level 1

## Level 2

##

Level 2 がここで終了します。
```

また、前後を同じ数の `#` で囲むと、セクション化されない単なる見出しになります。

```markdown
## Not Sectionize {.just-a-heading} ##
```

### Frontmatter

ファイルの先頭に YAML を記述することで、ページごとのメタデータを定義できます。

```markdown
---
id: 'my-page'
lang: 'ja'
title: 'タイトル'
author: '著者名'
link:
  - rel: 'stylesheet'
    href: 'custom.css'
vfm:
  math: false
  hardLineBreaks: false
---

本文はここから始まります。
```

#### 主なプロパティ

| プロパティ | 型 | 説明 |
|---|---|---|
| `id` | String | `<html id="...">` |
| `lang` | String | `<html lang="...">` 例: `ja` |
| `dir` | String | 文字方向（`ltr` / `rtl` / `auto`） |
| `class` | String | `<html>` と `<body>` に付与するクラス |
| `title` | String | `<title>...</title>`（省略時は最初の見出しを使用） |
| `author` | String | `<meta name="author">` |
| `link` | Object[] | `<link>` タグの追加（CSS の読み込みなど） |
| `script` | Object[] | `<script>` タグの追加 |
| `meta` | Object[] | `<meta>` タグの追加 |
| `vfm` | Object | VFM の動作設定 |

#### vfm プロパティ

| プロパティ | デフォルト | 説明 |
|---|---|---|
| `math` | `true` | 数式構文の有効/無効 |
| `hardLineBreaks` | `true` | 改行を `<br>` に変換する（デフォルト有効） |
| `partial` | `false` | フラグメント出力（`<html>` タグなし） |
| `disableFormatHtml` | `false` | HTML の自動フォーマットを無効化 |
| `theme` | — | Vivliostyle テーマの CSS ファイル |

### ハード改行（Hard Line Breaks）

Vivlio Starter では、**デフォルトでハード改行が有効**になっています。これにより、日本語の文章でエンターキーを押した改行がそのまま `<br>` タグに変換され、直感的な執筆が可能です。

#### デフォルト動作（hardLineBreaks: true）

```markdown
---
title: "日本語の文章"
---

はじめまして。
Vivliostyle Flavored Markdown の世界へようこそ。
VFM は出版物の執筆に適した Markdown 方言です。
```

#### HTML 出力（デフォルト）
```html
<p>
  はじめまして。<br>
  Vivliostyle Flavored Markdown の世界へようこそ。<br>
  VFM は出版物の執筆に適した Markdown 方言です。
</p>
```

#### 個別無効化（技術的な文章の場合）

技術的な説明文などで改行をスペースとして扱いたい場合は、フロントマターで `hardLineBreaks: false` を指定します。

```markdown
---
vfm:
  hardLineBreaks: false
---

あるいは、`book.yml` で

```yaml
vfm:
  hardLineBreaks: false
```

と設定することもできます。

### 技術的な説明

この関数は引数を受け取り、
処理を実行して、
結果を返します。

複数行にわたる説明ですが、
改行はスペースとして扱われ、
自然な段落として表示されます。
```

#### HTML 出力（hardLineBreaks: false）
```html
<h3>技術的な説明</h3>
<p>この関数は引数を受け取り、 処理を実行して、 結果を返します。 複数行にわたる説明ですが、 改行はスペースとして扱われ、 自然な段落として表示されます。</p>
```

#### 重要な注意点

- **コードブロック**: `hardLineBreaks` 設定の影響を受けません。フェンスコードブロック（```）とインデントコードブロックは常に独立した要素として処理されます。
- **空行**: 空行は段落分けとして扱われ、`hardLineBreaks` 設定に関係なく新しい段落になります。
- **詩や歌詞**: デフォルト有効により、詩的な表現が見たままの形で表示されます。

### 改行

改行するには2つの方法があります：

#### HTMLタグを使用
```markdown
これは1行目です。<br>
これは2行目です。
```

#### 段落分け
```markdown
これは1段落目です。

これは2段落目です。
```

---
