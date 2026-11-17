# テーマの契約（vs が保証する HTML・テーマの形・公式テーマとの接続・置き場と配布）

> 作成日: 2026-11-14
> ステータス: **設計済み・実装待ち**
> 対象: 2.0.0 で、本の見た目を「テーマ」として切り出し、他の人へ配れるようにするための契約。vs が保証する側（HTML の構造・公開する変数）と、テーマが提供する側（`theme.yml`・CSS・画像・書体）の両方を決める
> 出自: `v2-design-research-brief.md` §3 の B-1〜B-3 と、§5 の「Fable に検討してほしい点」（テーマを二段に分けるか・変数名の接頭辞）。事実は `v2-inventory-report.md` §2・§7
> 組になる仕様書: `v2-architecture-spec.md`（契約 HTML の位置づけ・設定）・`css-layer-restructure-spec.md`（層の順序・Kindle 用の CSS）・`v2-migration-plan.md`（段階 S1・S6・S7）

---

## 0. 決定の一覧

| 問い | 決定 | 節 |
| :--- | :--- | :--- |
| 契約の範囲 | 契約は三つ: 契約 HTML（§2）・公開する変数（§5）・`theme.yml`（§3）。これ以外をテーマは前提にしない | §1 |
| テーマを二段に分けるか | 分ける。ただし形式は一つ。値だけを書いた `theme.yml`（配色のテーマ）と、CSS と画像を持つテーマ（組版のテーマ）は同じ置き場・同じ読み込みで、配色のテーマは組版のテーマを `extends:` で指す | §3.2 |
| 変数名の接頭辞 | vs が公開する変数は `--book-*` とする。`--vs-*` は Vivliostyle の公式テーマの名前空間なので使わない。クラスの `vs-*` は今のまま使う | §5 |
| 公式テーマの変数の体系に合わせるか | 合わせない。取り込むだけにし、vs の公開する変数から公式テーマの変数へ値を渡す対応表を取り込みのときに作る | §6.3 |
| 公式テーマとの接続（B-2 の三案） | 公式テーマは `theme` 層に入れ、vs の部品はその下の層に置く（案 2 に近い）。取り込みはビルドのときではなく、`vs theme:add` で本の中へ複製するときに行う（案 3 の「取り込むときに変換する」）。`kindle` は保証しない | §6 |
| 標準のテーマ | 今の見た目を `standard` テーマとして切り出す。小説と絵本の既定のテーマは、Kindle で組める範囲の CSS で vs が書く（公式の `theme-bunko` を手本にする） | §4・§6.4 |
| Kindle に届くテーマの値 | 本文の字の大きさ・行送り・書体は、Kindle では読者と端末が決める。テーマが渡せるのは、明朝・ゴシック・等幅の区別（総称の名前）と色。配色のテーマは `theme.yml` の `kindle_tokens:` で Kindle の値を変える（`v2-post-s3-consultation.md` §5.2） | §3.1・§3.5・§5.2 |
| テーマの寸法と Kindle | 紙の寸法（`clamp()`・`min()`・`max()` を使う宣言）は Kindle に届かない。Kindle の寸法は、出力先の CSS に em で書く（同 §5.3） | §3.5 |
| テーマの出力先の CSS | vs の `targets/` と同じ名前の決まり（`epub.css`・`epub-<種類>.css`・`kindle.css`・`kindle-<種類>.css`）を、テーマにも認める（同 §5.4） | §3.1 |
| 置き場 | 本の `themes/<名前>/`。ビルドは gem や npm の中のテーマを直接は読まない | §7 |
| 版の互換 | `theme.yml` の `contract:`（契約の版・整数）で示す。2.0 の契約は `1` | §3.1・§8 |
| `vs upgrade` | 雛形から来たテーマだけを更新する。著者が入れたテーマと `custom.css` は触らない | §7.3 |

---

## 1. 契約の範囲

テーマと vs の間の約束は、次の三つである。

1. **契約 HTML**（§2）— vs が生成する HTML の構造。テーマの CSS が選んでよい要素・クラス・属性の一覧。
2. **公開する変数**（§5）— vs が値を入れる CSS の変数（判型・余白・書体・著者の設定）と、テーマが値を入れて vs の部品に読ませる変数。
3. **`theme.yml`**（§3）— テーマが自分について宣言する内容（名前・契約の版・対応する組方向とレイアウト・オプション・使う組み込みの機能）。

テーマはこの三つだけを前提にする。vs の内部（`lib/` のコード・`.cache/vs/` の配置・`stylesheets/` の中のファイル名・内部用の変数）は契約に含めず、2.x の間に変わりうる。

テーマは CSS・画像・書体・YAML だけで作り、コードを持たない（`v2-architecture-spec.md` §7.2）。

---

## 2. 契約 HTML

`.cache/vs/build/html/` に置かれる HTML（`v2-architecture-spec.md` §3.1 の L3 の出力）の構造を、ここに書く範囲で保証する。数は `v2-inventory-report.md` §2 の実測（本書・2026-11-13）による。

### 2.1 保証の水準

| 水準 | 意味 | 対象 |
| :--- | :--- | :--- |
| **保証** | 契約の版が同じ間は変えない。変えるときは契約の版を上げる | §2.2〜§2.5 と §2.7 に書いたもの |
| **内部** | テーマは選ばない。予告なく変わる | §2.2〜§2.5 に無いクラスと属性。後段の処理の目印（`level1`〜`level4` を除く VFM 以外の目印・`index-term`・`talk-c-*` など、CSS が参照していない 23 種）と `data-vs-*` |

S1 で、保証するクラスの全数の表を `lib/vivlio_starter/cli/html_contract.rb` に置く（§9）。本書の §2.2〜§2.5 は表の分類と決まりを定め、1 行ずつの一覧はコードの表を正典とする。表から文書用の一覧を書き出す `ruby scripts/html_contract_doc.rb` を用意し、テーマを作る人向けの文書（マニュアルの章）はその出力から作る。

### 2.2 `html` と `body`

```html
<html lang="ja">
<body class="chapter chapter-first vs-header-image">
```

| 種別 | クラス | 付く条件 | 水準 |
| :--- | :--- | :--- | :--- |
| ページの種類（必ず一つ） | `chapter`・`appendix`・`preface`・`postface`・`part-title`・`toc`・`titlepage`・`legalpage`・`colophon`・`index-page`・`glossary-page` | ページの種類 | 保証 |
| 位置 | `chapter-first` | 最初の章 | 保証 |
| 組方向（2.0 で足す） | `vs-vertical` | `traits.vertical?` | 保証 |
| レイアウト（2.0 で足す） | `vs-fixed` | `traits.fixed?` | 保証 |
| テーマのオプション | テーマが `theme.yml` で宣言したクラス（§3.3）。`standard` テーマでは `vs-header-image`・`vs-header-simple` | オプションの値 | そのテーマの中でだけ意味を持つ |
| 出力先 | `vs-epub`（EPUB の枝）・`vs-kindle`（Kindle） | 出力先の変換（L4）が足す。契約 HTML には無い | 保証 |

- `lang` は `Common.book_language` の値。
- ページの種類のクラスは、本書の生成物で確かめた 11 種（`v2-inventory-report.md` §2.1）である。全巻目次のページ（本書には無い）の `body` のクラスは、S1 で実物から確かめて表に入れる。
- 出力先のクラスは契約 HTML には付かず、L4 で付く。テーマの CSS は `body.vs-epub`・`body.vs-kindle` を選んでよい。PDF には出力先のクラスを付けない（今と同じ）。

### 2.3 章の骨格

```html
<body class="chapter">
  <section class="level1" role="doc-chapter" aria-labelledby="…">
    <h1 id="…">…</h1>
    <section class="level2">
      <article class="section-topic">
        <h2 id="…">…</h2>
      </article>
      <section class="level3"><h3>…</h3> … </section>
    </section>
  </section>
</body>
```

| 項目 | 決まり | 水準 |
| :--- | :--- | :--- |
| `section.level1`〜`level4` | VFM の出力のまま。見出しの深さに対応する。h2 を飛ばした章では `level1 > level3` になる | 保証 |
| `role` 属性（2.0 で足す） | ページの最上位の `section.level1` に、ページの種類に応じた値を付ける（下の表） | 保証 |
| `article.section-topic` | h2 を包む。**テーマとオプションに依らず常に付ける**（今は `theme.style: image` のときだけ。§2.6） | 保証 |
| 見出しの印 | `h1`〜`h3.vs-h-marker`・`span.subsection-marker`・`span.subsection-title` | 保証 |
| 見出しの `id` | 今の規則のまま | 保証（値の形は内部） |

ページの種類と `role` の値:

| ページの種類 | `role` | 付ける要素 |
| :--- | :--- | :--- |
| 章 | `doc-chapter` | `section.level1` |
| 前書き | `doc-preface` | `section.level1` |
| 後書き | `doc-afterword` | `section.level1` |
| 付録 | `doc-appendix` | `section.level1` |
| 部扉 | `doc-part` | `section.level1` |
| 奥付 | `doc-colophon` | 奥付の中身を包む `section`（S1 で足した。§11.1） |
| 索引 | `doc-index` | `section.index` |
| 目次 | `doc-toc`（今もある） | `nav` |
| 用語集 | `doc-glossary`（今もある） | `section` |
| 扉・権利ページ | 付けない | |

- 値は Digital Publishing WAI-ARIA の語彙から選ぶ。公式テーマは `:is(html, body):has([role='doc-…'])` と `section[role='doc-appendix'] > h1` の形で選ぶ（`@vivliostyle/theme-base` 3.0.1 の CSS で確認・2026-11-14）ので、`section.level1` に付ければ両方の形に当たる。
- `role` を足しても、今の CSS は `role` を選んでいないので見た目は変わらない。EPUB では `epub:type` を足さない（Vivliostyle の EPUB 出力に任せる）。

### 2.4 本文の部品

保証するクラスを、付ける処理ごとに分類する。1 行ずつの一覧は `html_contract.rb` の表による。

| 分類 | 例 | 付ける処理 |
| :--- | :--- | :--- |
| 囲み | `div.memo`・`div.tip`・`div.note`・`div.column`・`div.output` など、`:::{.class}` で著者が書くクラス | 前処理のコンテナ変換 |
| 並べ方 | `div.side-by-side`・`div.img-text`・`div.text-table`・`div.pictures`・`sideimage-left`・`rotate-table` | 前処理と後処理 |
| 位置と余白 | `align-*`・`text-*`・`aki` など | 前処理 |
| 図と表 | `figure`・`figcaption`・`p.table-caption`・`.code-caption`・`figure.vs-foo`（生成資産の型）・`img.vs-emoji` | 後処理 |
| コード | `pre.line-numbers`・`code.language-*`・Prism のトークン（`span.token.*`） | VFM と後処理 |
| 脚注 | `a[role=doc-noteref]`・`aside[role=doc-footnote]` と、後処理が付ける脚注のクラス | VFM と後処理 |
| 参照 | `a.cross-ref-link`・`a.pageref`・`a.glossary-link`・`a.glossary-backlink`・`a.main-ref` | 相互参照・索引 |
| 行内 | `span.vs-nobr`・キーの組み合わせ・リストの型（`vs-list-*`） | 後処理 |
| 会話 | `talk` の部品（`talk-c-*` を除く） | 前処理 |
| 目次・索引・用語集・奥付・扉・権利ページ・部扉・全巻目次の中の部品 | 各ページの生成が付けるクラス | 各生成器 |

決まり:

- 著者が `:::{.class}` で書いたクラスは、そのまま `div` のクラスになる。テーマは、自分の囲みのクラスを足してよい（CSS にクラスを書けば `ContainerClassCheck` が通す。今と同じ）。
- vs が後から足すクラスは `vs-` で始める（今ある `vs-` の付かないクラスは変えない）。テーマが自分で足すクラスは `vs-` で始めない。これで、後の版で vs が足すクラスとテーマのクラスがぶつからない。

### 2.5 2.0 で足す部品

| 部品 | HTML | 備考 |
| :--- | :--- | :--- |
| 縦中横 | `<span class="tcy">12</span>` | クラス名は公式テーマと電書協の EPUB 3 制作ガイドに合わせる |
| 傍点 | `<span class="sesame">…</span>` | 同上 |
| ルビ | `<ruby>漢字<rt>かんじ</rt></ruby>`（今と同じ・VFM の出力） | |
| 動画 | `<figure class="vs-video"><video …></video><figcaption>…</figcaption></figure>` | `v2-architecture-spec.md` §4.5 |
| 行内の属性 | `<span class="…">…</span>`（`[文字]{.class}`） | `v2-architecture-spec.md` §7.1 の D 型 |
| 括弧で始まる段落の印 | `<p class="vs-open-bracket">「…</p>` | 付く条件: 縦書き（`traits.vertical?`）。テーマが字下げを 0 にする（`novel-vertical-spec.md` §6.1）。横書きの本にも要ると分かったら、条件を外す（足すだけの変更） |
| 全面の挿絵 | `<figure class="vs-full-page">…</figure>`（`![題](x.png){.full-page}`） | どのテーマ・どの組方向でも働く vs の部品（`parts/figure.css`）。クラス名は S8-2 で確定する（`novel-vertical-spec.md` §5.2） |

`tcy` と `sesame` は `vs-` を付けない。公式テーマと、電書協の様式で書かれた既存の CSS が、そのまま当たるようにするためである。

### 2.6 契約 HTML はテーマと出力先に依らない

`v2-architecture-spec.md` §3.1 の決まりである。今この決まりに反している箇所と、直し方を示す。

| 今の挙動 | 直し方 | 見た目への影響 |
| :--- | :--- | :--- |
| h2 を `article.section-topic` で包むのは `theme.style: image` のときだけ | 常に包む。`simple` のときの見た目は CSS で今と同じに保つ | `simple` の本の HTML が変わる。画素の比較で、見た目が変わらないことを確かめる |
| `body` の `vs-header-image`・`vs-header-simple` を `BodyClassInjector` がコードで決める | テーマの `theme.yml` の宣言（§3.3 の `body_class`）から決める。`standard` テーマの宣言で今と同じクラスが付く | なし |
| 扉絵・節絵の画像の用意（`prepare theme images`）と、EPUB の見出しの画像（`inject_heading_images`）が常に走る | テーマが `features:` で使うと宣言したときだけ走る（§3.4）。EPUB の見出しの画像は L4 の変換なので、契約 HTML には影響しない | なし |
| 見出しの印の字（`theme.markers`） | 今も CSS の変数で渡しており、HTML には入らない。変えない | なし |

### 2.7 固定レイアウトの契約 HTML

`traits.fixed?` の本では、1 ページが 1 枚の HTML になる（2026-11-17・`picture-book-spec.md` §3）。

```html
<body class="vs-fixed vs-page-picture" data-vs-page="3">
  <div class="vs-page-art"><img class="vs-page-image" src="images/p01.jpg" alt="…"></div>
  <div class="vs-text bottom" style="--vs-x: 10%; --vs-y: 70%; --vs-w: 80%"><p>…</p></div>
</body>
```

| 要素・クラス | 保証 |
| :--- | :--- |
| `body.vs-fixed` と、ページの種類のクラス | `vs-page-picture`（絵のあるページ）・`vs-page-text`（文字だけ）・`vs-page-spread-left`・`vs-page-spread-right`・`vs-page-colophon`・`vs-page-blank` |
| `div.vs-page-art > img.vs-page-image` | ページいっぱいの絵。見開きでは、同じ画像を左右のページが半分ずつ見せる（`vs-page-art` が幅 200% の絵を切る） |
| `div.vs-text` | 文字の箱。名前の位置はクラス（`top`・`bottom`・`center`・`left`・`right`）、割合は `style` の `--vs-x`・`--vs-y`・`--vs-w` |
| `head` の `viewport` | `width=<px>, height=<px>`（判型を 96dpi の px に直した値。`picture-book-spec.md` §4.1） |
| `figure.vs-video` | 動画（S10。`video-spec.md`）。位置の決め方は文字の箱と同じ |

- 位置を `style` の変数で渡す理由は `picture-book-spec.md` §3。
- 契約の版は上げない（足すだけなので、既存のテーマは壊れない）。`HtmlContract` に、この表のクラスを足す（S9-2）。

### 2.8 契約を変えるとき

| 変更 | 契約の版 |
| :--- | :--- |
| クラス・属性・部品を足す | 上げない |
| 保証したクラスの名前を変える・消す、要素の入れ子を変える | 上げる（メジャーな版でだけ行う） |
| 内部のクラスを変える | 関係しない |

---

## 3. テーマの形

### 3.1 ディレクトリと `theme.yml`

```
themes/<名前>/
  theme.yml          必須。テーマの宣言
  *.css              組版のテーマの CSS。styles: に並べた順に theme 層へ入る（配色のテーマには無い。分け方は自由）
  epub.css           任意。EPUB の枝（クリーン EPUB と Kindle）の、全部の種類に当てる規則
  epub-<種類>.css    任意。同、その種類だけ
  kindle.css         任意。Kindle の、全部の種類に当てる規則（構造の劣化・em で書いた寸法）
  kindle-<種類>.css  任意。Kindle の、その種類だけ
  images/            任意。扉絵・節絵・飾りの画像
  fonts/             任意。同梱する書体
  README.md          任意。見本の画像・使い方
  LICENSE            配るなら必須
```

```yaml
# themes/standard/theme.yml
name: standard               # ディレクトリの名前と同じ。半角の英小文字・数字・ハイフン
title: 標準（技術書）         # 著者に見せる名前
version: 2.0.0               # テーマ自身の版
contract: 1                  # 契約の版（§8）
license: MIT
extends:                     # 土台にするテーマの名前（無ければ空）

supports:
  writing_mode: [horizontal]
  layout: [reflowable]
  targets: [pdf, print_pdf, epub, kindle]   # 省略すると四つ全部

features:                    # 使う組み込みの機能（§3.4）
  - frontispiece
  - ornament

tokens: {}                   # 公開する変数の値（§5）。--book- を除いた名前で書く（例 color-accent: "#555"）。
                             # standard は空。既定値は vs の stylesheets/tokens.css が持つ（§4）

# kindle_tokens:             # 任意。Kindle だけで変える値。書き方は tokens: と同じ（下の「kindle_tokens:」）
#   font-heading: serif      # 書体は総称の名前（serif・sans-serif・monospace）だけ
#   color-link: "#222"

options:                     # 著者が book.yml の theme: で変えられる項目（§3.3）
  color:
    type: color
    default: green
    token: color-accent
  appendix_color:
    type: color
    default_from: color      # 書かなければ color に従う（§3.3）
    token: color-accent-appendix
  style:
    type: enum
    values: [image, simple]
    default: image
    body_class:              # ページの種類ごとに書ける（§3.3）
      chapter:  { image: vs-header-image, simple: vs-header-simple }
      appendix: vs-header-simple

styles:                      # 読み込む CSS（順に theme 層へ入る）
  - simple-header.css
  - image-header.css
```

`theme.yml` の読み込みと検査は `lib/vivlio_starter/cli/theme/manifest.rb` に置く。知らないキーは 🟡 で知らせて無視する（後の版のテーマを前の版の vs で開いた場合に止めないため）。

**`tokens:` と `styles:` の入る層（`v2-s6-consultation.md` §4.2 の決め 2・12）。**

- `tokens:` は tokens 層に入る。vs が `.cache/vs/theme-tokens.css` に `:root { … }` として書き出し、vs の `stylesheets/tokens.css` の後に読む。`extends:` があれば、土台の `tokens:` → 自分の `tokens:` の順に並べる。
- theme 層に入れないのは、pages 層が `:root` で付録の色（`pages/appendix.css`）と前書きの色（`pages/preface.css`）を付け替えているためである。テーマの値が theme 層にあるとこの付け替えに勝ち、付録と前書きが本文の色になる。
- theme 層に入るのは `styles:` の CSS だけである。`styles:` には CSS を直接並べる。入口の 1 枚から `@import` で読む形は取らない（層を付けた `@import` の中の `@import` を、平らな CSS の生成が解く必要が出て、確かめる対象が増える）。

**出力先の CSS（`epub.css`・`kindle.css`）。** vs の `stylesheets/targets/` と同じ名前の決まりを、テーマにも認める（`v2-post-s3-consultation.md` §5.4）。テーマのディレクトリの直下に置き、どれも任意である。`theme.yml` には書かない（`styles:` は theme 層に入る CSS だけを並べる）。

| ファイル | 読む束 |
| :--- | :--- |
| `epub.css` | クリーン EPUB と Kindle の、全部の種類 |
| `epub-<種類>.css` | 同、その種類だけ |
| `kindle.css` | Kindle の、全部の種類 |
| `kindle-<種類>.css` | Kindle の、その種類だけ |

- `<種類>` は入口の 11 種類の名前（`css-layer-restructure-spec.md` §2.3）。
- `epub.css` が Kindle にも入るのは、vs の `targets/epub.css` と同じである（Kindle の `body` にも `vs-epub` が付く）。「EPUB の枝」は、クリーン EPUB と Kindle の両方を指す。
- 種類をファイルで分けるのは、選択子にクラスを足して絞ると詳細度が上がり、平らな CSS では勝ち負けが変わりうるためである。奥付の `body.vs-kindle { … }` のように `body` そのものを選ぶ規則は、ファイルで分ける以外に絞りようが無い。
- 入る層は target 層で、vs の `targets/` の後に読む。順は `css-layer-restructure-spec.md` §5 に書く。

**`kindle_tokens:`。** CSS を持たない配色のテーマが、Kindle だけで値を変えるためのキーである（`v2-post-s3-consultation.md` §5.2）。

- 書き方は `tokens:` と同じ（`--book-` を除いた名前）。vs が、target 層の `kindle-tokens.css` の直後に `body.vs-kindle { … }` として書き出す。
- 使い道は、見出しを明朝にする（`font-heading: serif`）、リンクの色を Kindle で指定どおりに描かれる `#222` 以上にする（§5.2）、など。
- 書ける値の範囲は §3.5 の「`body.vs-kindle` の変数の定義」による（書体は総称の名前だけ・本文の字の大きさと行送りは書かない）。
- 組版のテーマは、`kindle_tokens:` の代わりに、`kindle.css` に `body.vs-kindle { … }` で書いてもよい。

### 3.2 二段のテーマ

エディタのカラーテーマのように、値だけを差し替えるテーマを作れるようにする。形式は一つで、何を書くかで段が決まる。

| 段 | 書くもの | 例 | Kindle |
| :--- | :--- | :--- | :--- |
| **配色のテーマ** | `theme.yml` の `extends:` と `tokens:` だけ。CSS を持たない | `standard` を土台に、12 色とは別の配色・書体の組を配る | 色は必ず通る（CSS の生成がリテラルに解く）。書体は明朝・ゴシック・等幅の区別だけが届く。本文の字の大きさと行送りは届かない（§5.2 の Kindle の列） |
| **組版のテーマ** | `styles:` の CSS・画像・書体 | 章扉の形・見出しの組み方・柱とノンブルの置き方を変える | テーマの CSS が §3.5 の範囲に収まっていれば通る |

- `extends:` は 1 段だけとする（土台のテーマがさらに `extends:` を持つことは認めない）。読み込みの順は、tokens 層で土台の `tokens:` → 自分の `tokens:`、theme 層で土台の `styles:` → 自分の `styles:` である（§3.1）。
- 土台のテーマも本の `themes/` に無ければならない（§7）。`vs theme:add` は、`extends:` の先が無ければ一緒に入れるか、無いと知らせる。
- 配色のテーマは壊れようが無い（組版に触れない）ので、配る側も使う側も負担が小さい。今の「`custom.css` で 12 色を変える」は、配色のテーマを自分の本だけで使っていることに当たる。`custom.css` はそのまま使える（§7.3）。
- **配色のテーマの `tokens:` と、土台のオプション（`v2-s6-consultation.md` §4.2 の決め 4）。** 土台のオプション（`standard` の `color` など）の値は settings 層に書き出され、settings 層は tokens 層より上にある。`tokens:` に同じ変数を書くだけでは負けるので、選ばれたテーマの `tokens:` に、土台のオプションの `token:` と同じ名前があれば、その値をオプションの既定値として扱う（`v2-architecture-spec.md` §5.3 の 3）。settings 層には、解決した後の値を今と同じく必ず書く。
  - `book.yml` に著者が書いた値は、テーマの値に勝つ（`css-layer-restructure-spec.md` §2.1）。雛形の `book.yml` は `color: green` を書いているので、配色のテーマの色で組むには、その行を空欄にする。
  - `vs theme:add` は、`book.yml` に書く行を示すときに、テーマの値を覆っている `theme:` 節の行と、空欄にする書き方を一緒に示す（§7.2）。`vs build` は知らせない（著者が意図して書いた値と区別できないため）。

### 3.3 オプション

テーマは、著者が `book.yml` の `theme:` 節で変えられる項目を `options:` に宣言する。

| `type` | 値 | 渡し方 |
| :--- | :--- | :--- |
| `color` | 色の名前（`--book-accent-*` の 12 色）か HEX | `token:` に書いた変数へ |
| `length` | 単位付きの長さ | `token:` の変数へ |
| `number` | 数（`min`・`max`・`unit` を書ける） | `token:` の変数へ（`unit:` があれば単位を付けて） |
| `ratio` | 倍率（`1.2`。`1.2em` と書いてもよい。`min`・`max` を書ける） | `token:` の変数へ百分率で（`120%`。字の大きさの倍率を `em` で書くと Vivliostyle の丸めで字の位置がずれる） |
| `string` | 文字列（見出しの印など） | `token:` の変数へ（CSS の文字列として） |
| `enum` | `values:` のどれか | `body_class:` に書いたクラスを `body` に付ける。`token:` も書ける |
| `image` | テーマの `images/` の中の名前か、本の画像のパス | `token:` の変数へ（`url()` として） |

- 入れ子のオプション（`frontispiece.image` のように）は、`options:` の中を入れ子にして書く。
- **`body_class:` は、ページの種類ごとに書ける（`v2-s6-consultation.md` §4.2 の決め 5）。** 値 → クラスの表（`{ image: vs-header-image, simple: vs-header-simple }`）は、全部の種類の `body` に付ける。入口の種類の名前（`css-layer-restructure-spec.md` §2.3）をキーにすると、その種類だけに付ける。種類の値に文字列を書くと、オプションの値に依らず付けるクラスになる（`standard` の付録は、値に依らず `vs-header-simple`。§3.1 の例）。
- **`default_from:`（同 決め 6）。** 書かなければ別のオプションの値に従うオプションは、`default:` の代わりに `default_from: <オプションの名前>` を書く（`standard` の `preface_color`・`appendix_color` は `color` に、`frontispiece.lead_size` は `lead_size` に従う）。
- **`options:` に置けるもの（同 決め 7）。** `token:` と `body_class:` だけで渡せるものに限る。vs のコード（Ruby）が値を読むものは、機能の宣言に置く（§3.4）。
- 値は、ビルドのときに `settings` 層の CSS（今の `book-settings.css`）へ書き出す。どの変数へ渡るかは `token:` が決めるので、vs の側にテーマごとのコードは要らない。
- `standard` テーマの `heading_chars`・`lead_chars`（字数から幅を求める）のように、計算が要るオプションは、`features:` の組み込みの機能の設定として扱う（§3.4）。テーマが自分で計算を持つことはできない（コードを持たないため）。
- 値の検査（型・範囲・`values:`）は `theme.yml` の宣言から行い、外れたら 🟡 で、使える値を示す（`vs build` と `vs preflight` の両方）。
- **宣言に無いキー（`v2-s6-consultation.md` §4.5 の 2）。** `book.yml` の `theme:` 節に、選ばれたテーマの `options:` にも、そのテーマが使う機能の宣言にも無いキーがあれば、🟡「このテーマには無い設定です」で知らせる（`vs build` と `vs preflight` で同じものを出す）。キーの名前・選ばれたテーマの名前・そのテーマで書けるキーの一覧を示し、綴りの近いキーがあれば直し方（「`colour` → `color`」）を添える。値は読まない。
  - `ConfigKeys::RETIRED` にあるキーは、今の廃止の案内だけを出す（二重に知らせない）。
  - 「前のテーマのオプションが残った」と「打ち間違い」は区別できないので、文面は一つにする。
  - ほかの節の知らないキーの扱い（知らせずに読み飛ばす）は変えない。テーマを替えると、同じ `book.yml` のまま有効なキーの組が変わるのは `theme:` 節だけだからである。

### 3.4 組み込みの機能（`features:`）

見出しに画像を合成する処理のように、CSS だけでは作れず、vs のコード（Ruby）が要るものは、vs の本体に「組み込みの機能」として残す。テーマは、使うものを `features:` に書く。

| 機能 | 中身（今のコード） | オプション（`standard` で今あるキー） |
| :--- | :--- | :--- |
| `frontispiece` | 章扉の扉絵。`prepare theme images`・`HeadingImageComposer`・EPUB と Kindle の見出しの画像・`check chapter leads` | `frontispiece.image`・`edge_inset`・`heading_offset`・`heading_chars`・`lead_chars`・`lead_size` |
| `ornament` | 節見出しの節絵 | `ornament.image`・`heading_chars` |

- 機能を使うテーマは、その機能のオプションを自分の `options:` に並べずに使える（機能の側が宣言を持つ。`lib/vivlio_starter/cli/theme/features/<名前>.rb`）。
- 機能を使わないテーマでは、その機能の段は走らず、オプションは `theme:` 節に書けない（書いてあれば §3.3 の「このテーマには無い設定」の 🟡）。
- **扉絵の `@page :nth(1)` の規則は、vs の `stylesheets/pages/chapter.css` に置く（機能 `frontispiece` の骨格。`v2-s6-consultation.md` §4.2 の決め 3）。** テーマの `styles:` は全部の種類の入口に入り、`@page` は `body` のクラスで絞れない。テーマに置くと、付録・前書き・目次の最初のページにも扉絵が出る。テーマは変数（`--book-frontispiece-*`）で値を入れる。機能を使わないテーマのために、`stylesheets/tokens.css` に `--book-frontispiece-image: none;` の既定値を置く。
- **扉絵の効くページの種類は `chapter` だけで、機能の側に定数で持つ（`v2-s6-10-consultation.md` §4.4）。** `Theme::Features::Frontispiece::PAGE_KINDS = %i[chapter]`。「このページは扉絵の章扉か」は、機能が有効（`BuildPlan.features.frontispiece`）かつ `body` のクラスに `chapter` がある、で判定する。窓口は機能の側に 1 つ（`Theme::Features::Frontispiece.page?(body_classes)`）。テーマのクラス（`vs-header-image`）は読まない。`PageBreakNormalizer#breaking_h2_scope` と `ChapterLeadCheck#collect_leads` はこの窓口を使う。
- **章扉の保護（`section_pagebreak: false` のとき、全面の扉絵のページに本文を流し込まない規則）は、機能 `frontispiece` が settings 層に書く。** 選択子は `body.chapter`。出す条件は `section_pagebreak: false` かつ機能が有効。テーマの CSS に置かないのは、扉絵を使うテーマの全部に要る骨格だからである。settings 層に置くのは、theme 層の `var()`（値は `auto`）に PDF で勝つためで、`:not(.vs-epub)`・`:not(.vs-break-merged)` は今のまま付ける。
- 機能が効くページの種類を `theme.yml` で宣言する形は作らない。効く場所は vs の CSS の置き場で決まっていて、テーマが変えられないため。`ornament` には判定を読むコードが無いので、定数を置かない。
- `standard` の今の 15 個のキーを「`options:`」「`frontispiece`」「`ornament`」に分けた表は、S6-7 の最初に作ってここに書く。どれにも入らないキー（Ruby が読むが、扉絵にも節絵にも属さないもの。`markers.*` と `lead_size` が候補）が出たら、実装を止めて相談する。3 つ目の機能を足すかは、その表を見て決める。

**`standard` の 15 個のキーの振り分け（2026-11-17・S6-7 の最初。46186ddd のコードで数えた）。**

| キー | 値を読む箇所（`BookSettingsCss` の外も含む） | 振り分け |
| :--- | :--- | :--- |
| `preface_color`・`appendix_color` | `BookSettingsCss`（`--book-color-accent-preface`・`-appendix`）だけ | `options:`（`default_from: color`） |
| `frontispiece.image`・`edge_inset`・`heading_offset`・`heading_chars`・`lead_chars`・`lead_size` | `BookSettingsCss`・`FrontmatterGenerator`・`ThemeImageResolver`・`ImageOptimizer`・`InjectHeadingImages`・`ChapterLeadCheck`・`FrontispieceEstimate` | `frontispiece` |
| `ornament.image`・`heading_chars` | `BookSettingsCss`・`FrontmatterGenerator`・`ThemeImageResolver`・`ImageOptimizer`・`InjectHeadingImages` | `ornament` |
| `color` ⚠ | `BookSettingsCss`（`--book-color-accent`）のほか、`Techbook::Processor`（h3・h4・前書きの印の画像の色）・`TalkAvatarGenerator`（アバターの地色）・`InjectHeadingImages`（合成した見出しの画像の番号の色）・`DirectBuild`（`--theme`） | `token:` で渡せるが、扉絵・節絵の外の Ruby も読む |
| `style` ⚠ | `BodyClassInjector`（`vs-header-*`）のほか、`BookSettingsCss`（`simple` で画像の変数を `none`・扉絵の位置の規則を出さない）・`ImageOptimizer`（画像の準備を飛ばす）・`InjectHeadingImages`・`ChapterLeadCheck`・`PageBreakNormalizer`（body のクラスで判定） | `body_class:` で渡せるが、扉絵・節絵の機能の入り切りを兼ねる |
| `lead_size` ⚠ | `BookSettingsCss`（`.chapter-lead` の `font-size` をリテラルの規則で書く・扉絵のリードの幅の既定）・`ChapterLeadCheck`（`frontispiece.lead_size` の既定として） | `token:` が無い（公開する変数に無い）。`simple` の章・付録にも効くので扉絵に属さない |
| `markers.h3`・`markers.h4` ⚠ | `BookSettingsCss`（`--book-marker-h3`・`-h4`）のほか、`HeadingProcessor`（h3 の印の字を HTML に入れる）・`Kindle::RestoreH3Markers`・`Techbook::Processor`（印の画像） | `token:` で渡せるが、扉絵・節絵の外の Ruby も読む |

⚠ の 5 キーが「どれにも入らないキー」に当たる。2026-11-17 にユーザーが次のように決めた。3 つ目の機能は足さない。

1. **`color`・`markers.h3`・`markers.h4` は `options:` に `token:` で置き、vs のコードは公開する変数の名前で値を引く。** 公開する変数は契約の一部（§1）なので、vs の部品の Ruby（技術書の印の画像・会話のアバターの地色・h3 の印の字・Kindle の印の復元・合成した見出しの番号の色）がその値を読むのは契約の内側である。読むのはオプションの名前（`theme.color`）ではなく変数の名前（`color-accent`・`marker-h3`・`marker-h4`）で、窓口は `Theme.token_value` の 1 つにする。引く順は、選ばれたテーマのオプションのうち `token:` がその名前のもの（解決した後の値）→ テーマの `tokens:` → vs の既定（`stylesheets/tokens.css`）。
2. **`style` は `body_class:` で渡し、扉絵・節絵の入り切りは、enum のオプションの値ごとに `features:` で宣言する。** `features: { image: [frontispiece, ornament], simple: [] }` と書くと、`simple` のとき 2 つの機能は使わない。機能が有効なのは、テーマの `features:` にあり、かつ `features:` を持つ enum のオプションの今の値の並びにあるときである。vs のコードは `style` の名前も値も読まず、機能が有効かだけを読む（`BuildPlan.features.frontispiece`・`Theme::Features.active?`）。
3. **`lead_size` は公開する変数 `--book-chapter-lead-size` を足し、`options:` に `type: ratio`・`min: 1.0`・`max: 2.0`・`token: chapter-lead-size` で置く。** `parts/heading.css` の `.chapter-lead` がこの変数を読む。扉絵の章の倍率（`frontispiece.lead_size`）は、機能 `frontispiece` が `--book-frontispiece-lead-size` で渡す。今の書き出し（`.chapter-lead` の `font-size` をリテラルの規則で書く）は、Kindle が `var()` を捨てるためだったが、S3-3a から Kindle 用の CSS の生成が `var()` を解く。`book-settings.css` の字面が変わるので、S6-7 の前段の小段階として先に入れ、PDF の画素・EPUB の計算値・Kindle の中間生成物で前後を比べる（§11）。
   - 倍率の型 `ratio` を §3.3 の表に足す（2026-11-17・前段の確かめで決めた）。値は `1.2`（`1.2em` と書いてもよい）で、CSS には百分率（`120%`）で書き出す。最初は `type: number`・`unit: em` で `1.2em` と書き出したが、前の `font-size: larger` と比べて、章扉と付録の扉の章リードの 1 行で字の位置がわずかにずれた（B1 で 9 ページ）。`em` の長さは Vivliostyle が px に直すときに丸め、`larger` と `120%` は丸めない（1 章だけのビルドで `larger`・`var()` の中の `larger`・`120%`・`1.2em` を比べ、`1.2em` だけが違った）。`calc(var(…) * 1em)` も同じ理由で使わない（`vivliostyle-css-pitfalls-notes.md` §2.18）。
- 2.0 で用意する機能はこの二つだけとする。小説と絵本のテーマが必要とする処理は、個別の仕様で、機能として足すかを決める。機能を足すのは vs の本体の変更で、テーマの側からは足せない。

### 3.5 Kindle で組むための CSS の範囲

`supports.targets` に `kindle` を含めるテーマの CSS は、次の範囲で書く。範囲の外の書き方は、Kindle 用の CSS の生成が解けず、その宣言か規則を落とす。知らせるのは `vs theme:check` で、`vs build` はテーマの CSS で落ちた宣言を知らせない（著者には直せないため。`css-layer-restructure-spec.md` §4.5）。

| 書き方 | 扱い |
| :--- | :--- |
| 変数の定義 | `:root`・`html`・`body`・`body.<ページの種類>` でだけ行う。それより深い要素で定義し直した変数は、Kindle 用に解けない |
| `var()`・`color-mix()`・単位のそろった `calc()` | 使ってよい（生成がリテラルに解く） |
| `:is()`・`:where()` | 選ぶ対象の並びとして使う場合は、生成が並びに展開する。入れ子の深い使い方は避ける |
| `:has()` | Kindle では解けない。使った規則は Kindle に届かない |
| CSS の入れ子（`&`） | 使わない（2.0 の生成は入れ子を展開しない） |
| 層の中の `!important` | 使わない（`css-layer-restructure-spec.md` §2.4） |
| 部品の見た目を変える規則 | 変数で変える。規則で変えるときは、部品の規則と同じ選択子で書く（EPUB と Kindle は層を外した平らな CSS を読み、詳細度で勝ち負けが決まるため。`css-layer-restructure-spec.md` §2.1・§4.3） |
| `display: grid`・`flex`・疑似要素の位置指定 | 使ってよいが、Kindle では `block` になる。崩れる部品は `kindle.css` に代わりの組み方を書く（`kindle-css-compatibility-notes.md` §2） |
| 紙の寸法（`clamp()`・`min()`・`max()` を使う宣言） | Kindle には届かない（生成が、紙の寸法という理由を付けて落とす）。Kindle での大きさと余白は、`kindle.css` に em で書く |

- **紙の寸法が届かない理由。** 紙の寸法（mm と `--book-paper-scale`）は判型に対する比で決めた値で、判型の無い端末では基準が無い（`v2-post-s3-consultation.md` §5.3）。これは意図した書き方で、直す対象ではない。
- mm や pt をそのまま書いた宣言（図の枠 0.5mm・引用の線 2mm など）は Kindle に届き、崩れていない。単位では検査しない。

**`body.vs-kindle` の変数の定義。** Kindle の本文の字の大きさ・行送り・書体は、読者が端末で選ぶ値である。テーマは Kindle の本文の組み方を決めない（`v2-post-s3-consultation.md` §5.2）。テーマが PDF 用の字の大きさを Kindle に届けると、読者の設定と掛け合わさって意図しない大きさになる。この決まりにより、テーマを作る人は端末ごとの確かめを負わずに済む。

- vs の `targets/kindle-tokens.css` が、`body.vs-kindle` で `--book-font-size` を `1em`、`--book-line-height` を `normal`、書体の変数を総称の名前に置き換える（§5.2 の Kindle の列）。
- テーマが Kindle の値を変える道は、`theme.yml` の `kindle_tokens:`（§3.1）と、`kindle.css` の `body.vs-kindle { … }` の二つである。
- どちらでも、書体の値は総称の名前（`serif`・`sans-serif`・`monospace`）だけとし、`--book-font-size`・`--book-line-height` は書かない。
- `vs theme:check` が、それ以外の値を 🟡 で示す（「Kindle では読者が選ぶ値です」と示し、消すことを案内する）。ビルドは止めない。
- 著者の `custom.css` の `body.vs-kindle { … }` は、何でも書ける。著者は自分の本と自分の端末で確かめられるので、知らせない。

- **章と節の改ページは、公開する変数で書く（`v2-s6-10-consultation.md` §4.3）。** テーマの CSS は `break-before: var(--book-chapter-break-before)`・`var(--book-section-break-before)`（Kindle 向けの古い書き方は `page-break-before: var(--book-section-page-break-before)`）と書き、値を直接書かない。`page.section_pagebreak`・`page.chapter_pagebreak` の設定は、settings 層がこの変数の値を書くことで効く。値を直接書いた規則は、§7.2 の検査が 🟡 で示す。

`vs theme:check <名前>`（§7.2）が、この範囲を検査して報告する。

---

## 4. 標準のテーマ

今の見た目を `themes/standard/` に切り出す。切り出しの前後で、本書の四つの出力先の出力が変わらないことを完了の条件とする（§9 の S6）。

| 今の置き場 | S6 の後 | 理由 |
| :--- | :--- | :--- |
| `stylesheets/parts/simple-header.css`・`parts/image-header.css` | `themes/standard/`（theme 層。`styles:` に今の順で並べる） | 見出しの組み方。選択子は `:root` の 1 規則を除いて全部 `vs-header-*` で絞ってあり、ほかの種類のページに当たらない |
| `stylesheets/images/bundled/`（扉絵・節絵の 12 枚） | `themes/standard/images/` | |
| `stylesheets/targets/epub.css`・`kindle.css` の、選択子が `vs-header-*` を含む規則 | `themes/standard/epub.css`・`kindle.css`（§3.1） | 劣化させる相手の部品がテーマへ移る（下の「`targets/` の規則の線引き」） |
| `book.yml` の `theme:` 節のキー | `themes/standard/theme.yml` の `options:` と、`features:` の機能の宣言 | §3.3・§3.4 |
| `stylesheets/tokens.css`（公開する変数の既定値） | 残す。`--book-*` の一覧の正典（§5.2） | `standard` の `tokens:` は空。テーマに依らない中立の既定値と `standard` の値を分けるのは、2 つ目の組版のテーマ（`novel`・S8）が値を決めるとき。`novel` は中立の既定値を動かさず、違う値だけを `tokens:` に書く（`novel-vertical-spec.md` §3.3） |
| `pages/chapter.css` の `@page :nth(1)`（扉絵） | 残す | §3.4 |
| `pages/appendix.css`・`pages/preface.css` の `:root` の付け替え | 残す | 付録の色・前書きの色は公開する変数（`--book-color-accent-appendix`・`-preface`）で、どのテーマでも働く仕組みである |
| `parts/heading.css`・`prose.css`・`box.css`・`preface.css` などの、色・書体・余白・飾りの規則 | 残す | 下の「部品に残す飾り」 |
| `ThemeColor`（12 色の名前と値） | 12 色は `--book-accent-*` として vs の土台が持つ（§5.2） | テーマではなく、どのテーマからも使える色の名前とする |

**部品に残す飾り（`v2-s6-consultation.md` §4.10）。** `css-layer-restructure-spec.md` §3.2 の線引き（消すと働かなくなるものは部品、飾りはテーマ）は決まりとして残すが、S6 で theme 層へ移すのは上の表の見出しの 2 枚だけとする。

- 部品の色と書体は、すでに公開する変数を読んでいる。テーマは変数で変えられる。規則で変えたいテーマは theme 層に書けば、PDF では詳細度に関係なく勝つ。規則を移さなくても、テーマにできることは減らない。
- 規則を parts 層から theme 層へ移すたびに、詳細度が同じ組で勝つ側が入れ替わりうる。組版のテーマが `standard` の 1 つしか無い時点では、どの規則が「どのテーマにも要る骨格」で、どれが「`standard` だけの飾り」かを確かめる相手が無い。「迷う規則は部品の側に置く」（同 §3.2）に合う。
- 残した規則のうち、`novel`（S8）を書くときに打ち消しが要ったものを、S8 の中で `standard` へ移す（§10 の論点 5）。前書きの飾り（`parts/preface.css`）は S8-5 で移すと決めた（`novel-vertical-spec.md` §3.4）。

**`targets/` の規則の線引き（`v2-post-s3-consultation.md` §5.4）。**

- vs の部品（囲み・コード・表・索引・用語集・奥付）の規則は、`stylesheets/targets/` に残す。テーマへ移すのは、上の表の 3 行目の規則（選択子が `vs-header-*` を含むもの）だけである。テーマの出力先の CSS は 11 種類の全部の束に入るが、vs の `targets/epub.css`・`kindle.css` は本文のページの 4 種類にしか入らない。素の `h1`・`h2` を選ぶ規則を移すと目次・索引・用語集の見出しにも当たるので、相手の部品がテーマへ移っていても vs の `targets/` に残す（`v2-s6-consultation.md` §4.2 の決め 11）。
- 移すときは、選択子と宣言を変えない。クラスを足して絞ると詳細度が上がり、平らな CSS では勝ち負けが変わりうる（`v2-flat-cascade-consultation.md` §5.3 の 5）。
- 移すと、vs の `targets/` の規則との前後が変わる（テーマの出力先の CSS は vs の `targets/` の後に読む）。詳細度が同じ組では勝つ側が入れ替わりうるので、移動の前後で EPUB の計算値と Kindle の中間生成物が差 0 であることを確かめる（§9 の S6 の条件 8）。

種類ごとの既定のテーマ:

| 種類 | 既定のテーマ | 中身 |
| :--- | :--- | :--- |
| `techbook` | `standard` | 今の見た目 |
| `novel` | `novel` | 縦書き。文庫・B6・新書・四六の判型で使う。`novel-vertical-spec.md` §3 |
| `picture_book` | `picture-book` | 固定レイアウト。位置と寸法は vs の `base/fixed.css`、見た目だけをテーマが書く。`picture-book-spec.md` §7 |

---

## 5. 公開する変数

### 5.1 名前の決まり

| 種別 | 名前 | 誰が定義するか | 誰が読むか |
| :--- | :--- | :--- | :--- |
| 公開する変数 | `--book-*` | vs の土台（既定値）・`settings`（著者の設定）・テーマの `tokens:`・`custom.css` | vs の部品・テーマの CSS |
| テーマの中だけの変数 | `--<テーマ名>-*`（例 `--standard-frontispiece-width`） | そのテーマ | そのテーマ |
| vs の内部の変数 | `--_*`（下線で始める） | vs | vs。テーマと `custom.css` は読まない・定義しない |
| Vivliostyle の公式テーマの変数 | `--vs-*`・`--vs--*`・`--vs-page--*`・`--vs-theme-*` | 公式テーマ | 公式テーマ。vs はこの名前を定義しない（§6.3 の対応表を除く） |

- vs の今の変数（99 種・接頭辞は `--color`・`--accent`・`--font`・`--frontispiece`・`--page`・`--folio`・`--talk` など）に `--vs-` で始まるものは無く、公式テーマとの衝突は今は無い（`v2-inventory-report.md` §7.3）。衝突が起きるのは、公開する変数に `--vs-` を付けた場合だけなので、付けない。
- クラスの `vs-*`（`vs-epub`・`vs-h-marker` など）は今のまま使う。公式テーマに `.vs-*` のクラスは無い。
- **S6 で名前を変える範囲（`v2-s6-consultation.md` §4.2 の決め 8）。** `--book-*` に変えるのは、§5.2 の公開する変数と、機能の変数（`--book-frontispiece-*`・`--book-ornament-*`）である。`standard` へ移る見出しの 2 枚の中だけの変数は `--standard-*` にする。vs の内部の変数（`base/page.css` の `--page-width`・`--page-height`・`--align-max-width`、`pages/titlepage.css`・`pages/colophon.css` の `--subtitle-*`、生成する `--talk-c-<key>` など）は、2.0 では名前を変えない（`base/page.css` の残りの 20 個は §5.2 の公開する変数で、S6-2 で `tokens.css` へ移した。§11.4 の「仕様と違えたこと」の 1）。`--_*` に変えて別名を置けば内部の変数でなくなり、置かなければ、その変数に値を入れていた 1.x の `custom.css` が警告なしに効かなくなるためである。`--_*` の決まりは、これから足す内部の変数に当てる。名前を変えた変数は例外なく対応の表（`css-layer-restructure-spec.md` §7.2）に載せる。

### 5.2 公開する変数の一覧（分類）

1 行ずつの一覧は S6 で `stylesheets/tokens.css` に置き、そこを正典とする。分類と、今の名前からの対応を示す。

| 分類 | 新しい名前 | 今の名前 | 値を入れる側 | Kindle |
| :--- | :--- | :--- | :--- | :--- |
| テーマ色の 12 色 | `--book-accent-yellow` … `--book-accent-lime` | `--accent-*` | vs の土台 | 届く |
| 本のテーマ色 | `--book-color-accent`・`--book-color-accent-preface`・`--book-color-accent-appendix` | `--theme-accent`・`--color-preface-accent`・`--appendix-accent-color` | `settings`（テーマのオプション） | 届く |
| 色 | `--book-color-text`・`-link`・`-strong`・`-em-underline`・`-border`・`-border-weak`・`-output-border`・`-column-bg`・`-column-border`・`-figure-border`・`-overlay`・`-danger`・`-mark`・`-heading`・`-section-number` | `--color-*`・`--heading-accent`・`--section-number-color` | テーマ | 届く |
| 書体 | `--book-font-body`・`-heading`・`-column`・`-code`・`-folio`・`-title` | `--font-main-text`・`--font-header`・`--font-column`・`--font-code`・`--font-folio`・`--font-title`（奥付のクレジットの 1 行だけが読んでいた `--font-body` は消した。§11.5） | `settings`（`typography`） | 総称の名前に置き換わる（`kindle-tokens.css`） |
| 版面 | `--book-page-margin-top`・`-bottom`・`-inner`・`-outer`・`--book-font-size`・`--book-line-height`・`--book-letter-spacing`・`--book-paper-scale` | `--page-margin-*`・`--base-font-size`・`--base-line-height`・`--letter-spacing`・`--paper-scale` | `settings`（判型のプリセット） | `--book-font-size`・`--book-line-height` は端末任せ（`1em`・`normal`）。残り（余白・`--book-letter-spacing`・`--book-paper-scale`）は届かない（Kindle に紙面が無い） |
| 柱とノンブル | `--book-folio-font-size`・`-color`・`--book-folio-left-content`・`-right-content`・`-center-content` | `--folio-*` | `settings` | 届かない（Kindle に紙面が無い） |
| 見出しの印 | `--book-marker-h3`・`--book-marker-h4` | `--h4-marker` ほか | `settings`（テーマのオプション） | 届く |
| 章リード | `--book-chapter-lead-size`（S6-7 の前段で新設。§3.4 の決め 3） | （無し。`book-settings.css` がリテラルの規則を書いていた） | `settings`（テーマのオプション） | 届く |
| 章と節の改ページ | `--book-section-break-before`（既定 `page`）・`--book-section-page-break-before`（既定 `always`。Kindle 向けの古い書き方の値）・`--book-chapter-break-before`（既定 `recto`）。既定値は `stylesheets/tokens.css`（`v2-s6-10-consultation.md` §4.3。S6-9b で新設） | （無し。v2 の途中の `--section-break-before` は 1.x に無いので別名を置かない） | `settings`（`page.section_pagebreak: false` で `auto`、`page.chapter_pagebreak` が `any` で `page`・`verso` で `verso`。書かない条件では宣言しない） | 届く |
| 会話 | `--book-talk-accent`・`-bg`・`-icon-size`・`-speaker-size` | `--talk-*` | `settings`・テーマ | 届く |

- 扉絵・節絵の変数（`--frontispiece-*`・`--section-bg-image`・`--section-title-font-size`）は、組み込みの機能（§3.4）が値を入れる変数で、名前は `--book-frontispiece-*`・`--book-ornament-*` とする（`--section-bg-image` は `--book-ornament-image`、`--section-title-font-size` は `--book-ornament-title-font-size`）。
- 使われていない変数（`--color-shadow`）は消す。
- 1 行ずつの一覧（`tokens.css`）に定義を置かないものが 3 種類ある。前書きと付録の色（`pages/preface.css`・`pages/appendix.css` がそのページの `:root` で定義する）、会話の色（`parts/talk.css` が `.talk` で定義する。要素ごとに値が違うので `:root` に上げない）、アバターの大きさ（`talk.yml` から生成する）。一覧には注釈で置き場を書く。扉絵と節絵の画像は、S6-7 の前段から `tokens.css` に既定の `none` を置く（機能を使わないテーマのため。§3.4）。
- 「Kindle」の列は、テーマと `settings` が入れた値が Kindle に届くかを示す（`v2-post-s3-consultation.md` §5.2）。「届く」は、CSS の生成が値をリテラルに解いて Kindle 用の CSS に書くことを指す。書体と、版面の字の大きさ・行送りは、`targets/kindle-tokens.css` が `body.vs-kindle` で置き換える。Kindle だけで値を変える道は §3.5 に書く。
- S6 で、`kindle-tokens.css` は `--book-*` の名前で書く。部品が読む名前が `--book-*` になるので、同じ名前で置き換えるのが変数の表の解き方（`body` に近い定義が勝つ）に合う。`vs upgrade` の名前の置き換え（`css-layer-restructure-spec.md` §7.2）は、選択子を問わず `custom.css` の全部の定義に当てる（`body.vs-kindle` の中の定義を含む）。
- Kindle では、`--book-color-link` が `#111` 以下の黒に近い色だと、リンクは Kindle の青で描かれる（`#222` から指定どおり）。テーマの既定を決めるときの前提にする（`kindle-css-compatibility-notes.md` §2 の表）。
- 今の名前は、2.0 の間は別名として読める（`css-layer-restructure-spec.md` §7.2）。1.x の `custom.css` に書いた `--color-link: #1a73e8;` は、書き換えなくても効く。

### 5.3 変数の決まり

- 公開する変数の定義は `:root` で行う。ページの種類で値を変える場合は `body.<ページの種類>` で行う（§3.5 の Kindle の範囲と同じ）。
- 判型（`@page { size }`）と、`calc()` の中で変数が使えない箇所（`vivliostyle-css-pitfalls-notes.md` §2.1・§2.18）は、今と同じく `settings` 層にリテラルで書き出す。テーマは `@page` の `size` を書かない（判型は著者の `page.use` が決める）。

---

## 6. 公式テーマとの接続

### 6.1 公式テーマについて分かっていること

`@vivliostyle/theme-base` 3.0.1 と `@vivliostyle/theme-bunko` 3.1.0 の実物（2026-11-13・14 に `npm pack` で取得）から:

- 要素を主に `role` 属性で選ぶ。形は `:is(html, body):has([role='doc-toc'])` のように `:is()` と `:has()` を組み合わせたものが多い。
- 設定はすべて CSS の変数で、`theme-base` の `css/basic.css` だけで `var()` が 893 か所ある。変数は `:root` と `:root:lang(ja)` で定義される。
- `theme-bunko` は `@import '@vivliostyle/theme-base';` のように、npm のパッケージ名で読み込む。この形は Vivliostyle CLI のテーマの解決を通さないと読めない。
- `@layer` は使っていない。
- 判型は、行数と字数から `calc()` で求める（`theme-bunko`）。

### 6.2 接続の形

| 項目 | 決定 | 理由 |
| :--- | :--- | :--- |
| 層の位置 | 公式テーマの CSS は、ほかのテーマと同じく `theme` 層に入れる。vs の部品（`parts` 層）はその下にある | 本文・見出し・表など共通の要素の見た目はテーマが決め、vs に固有の部品（索引・用語集・囲み・行番号・相互参照など。公式テーマは触れない）は vs の部品の規則が効く |
| 名前 | パッケージの名前 `@vivliostyle/theme-<x>` から `vivliostyle-<x>` を作る（`theme-bunko` は `vivliostyle-bunko`）。`theme.yml` の `name:` もこの名前にする | 同梱の `novel` と、本の `themes/` の中で名前がぶつからない（`novel-vertical-spec.md` §3.1） |
| 取り込みの時点 | `vs theme:add @vivliostyle/theme-bunko` で、本の `themes/` へ複製するときに変換する。ビルドのたびに npm から解決しない | `v2-architecture-spec.md` §7.2 の「本の中に実体を置く」。ビルドがそのマシンの `node_modules` の中身に左右されない |
| 取り込みのときの変換 | (1) `@import '@vivliostyle/theme-base…'` を、複製した先の相対パスに書き換える。(2) `theme.yml` を生成する（`contract: 1`・`supports:` は下の表・`license:` は `package.json` から）。(3) 変数の対応表（§6.3）を `bridge.css` として生成する | |
| 対応する出力先 | `supports.targets: [pdf, print_pdf, epub]`。**`kindle` は含めない** | `:is()` と `:has()` を使った規則は KFX が捨てる（`kindle-css-compatibility-notes.md` §2）。`:has()` は生成でも展開できない |
| 判型 | vs の `page.use`（判型のプリセット）が決める。公式テーマの判型の計算（`--vs-page--width` など）は、対応表で vs の値を渡して上書きする | 判型は著者の設定で、入稿の寸法に関わる |
| 対応を確かめるテーマ | 2.0 では `theme-bunko` だけを確かめる。ほかの公式テーマは、取り込めるが結果は保証しない、と文書に書く | 確かめる面を増やさない |

`supports:` の生成:

| `package.json` の `vivliostyle.theme.category` | `writing_mode` | 備考 |
| :--- | :--- | :--- |
| `novel` で、CSS に `vertical-rl` がある | `[vertical]` | `theme-bunko`・`theme-epub3j` |
| それ以外 | `[horizontal]` | |

`layout` は常に `[reflowable]` とする。

### 6.3 変数の対応表（`bridge.css`）

公式テーマの変数の体系（`--vs-*`・325 種）には合わせない。

- 理由 1: 体系は Vivliostyle の側の版で変わる（3.x は 2026-10-28 の公開）。vs の公開する変数を合わせると、向こうの変更が vs の契約の変更になる。
- 理由 2: vs の変数は「著者が `book.yml` で決めた値を渡す」ためのもので、数は 50 ほどで足りる。325 種を公開の契約にする必要が無い。

代わりに、取り込みのときに、vs の値を公式テーマの変数へ渡す対応表を生成する。

```css
/* themes/vivliostyle-bunko/bridge.css（生成物） */
:root {
  --vs-font-family: var(--book-font-body);
  --vs-font-size: var(--book-font-size);
  --vs-line-height: var(--book-line-height);
  --vs-color-foreground: var(--book-color-text);
  --vs-page--margin-top: var(--book-page-margin-top);
  /* … */
}
```

- `bridge.css` は公式テーマの CSS の後に読み、同じ `theme` 層に入れる。
- 対応させる変数は、書体・文字の大きさ・行送り・文字の色・余白・組方向の 15 種ほどに限る。一覧は S7 の実験（§9）で確定する。
- 対応表は生成物だが、取り込んだ後は本の中のファイルなので、著者が手で直せる。

### 6.4 小説の既定のテーマは vs が書く

小説は `kindle` でも出す（ユーザーの方針）。公式の `theme-bunko` は §6.2 のとおり Kindle を保証できないので、小説の既定のテーマは、§3.5 の範囲の CSS で vs が書く。

- 手本は `theme-bunko`（文庫の体裁・行数と字数からの版面）と `theme-epub3j`（電書協の EPUB 3 制作ガイドの CSS）とする。どちらも CC0-1.0 で、規則を写してよい。
- 目指す紙面は、Vivliostyle の公式の縦書きの作例に、ときどき挿絵を入れた形（`v2-design-research-brief.md` §5）。
- 挿絵は `writing-mode: horizontal-tb` の `figure` に入れる（`v2-feasibility-notes.md` §3.1。縦書きの中で寸法の指定が入れ替わるのを避ける）。
- 余白の箱（柱とノンブル）には `writing-mode: horizontal-tb` を指定する（同上）。
- 紙面の寸法と部品の一覧は、小説の仕様に書く（`novel-vertical-spec.md` §3・§4）。テーマの名前は `novel`。

---

## 7. 置き場・配布・更新

### 7.1 置き場

| 置き場 | 中身 | 誰が管理するか |
| :--- | :--- | :--- |
| 本の `themes/<名前>/` | その本が使えるテーマ。ビルドが読むのはここだけ | 雛形から来たものは `vs upgrade`、それ以外は著者 |
| gem の雛形（`lib/project_scaffold/themes/`） | 同梱のテーマ（`standard`・`novel`・`picture-book`）。正典はリポジトリの直下の `themes/` | vs の開発（`ruby scripts/copy_to_scaffold.rb` で同期） |
| 本の `stylesheets/` | vs の土台と部品（`css-layer-restructure-spec.md` §3）と `custom.css` | 雛形・`custom.css` だけ著者 |

- `vs new` は、選んだ種類の既定のテーマだけを `themes/` に置く。ほかの同梱のテーマは `vs theme:add <名前>` で足す。
- テーマの解決は「`book.yml` の `theme.name` → `themes/<名前>/theme.yml`」の一通りだけとする。無ければ 🔴 で止め、`vs theme:add` の書き方を示す。gem や npm の中を探しにいかない（`v2-architecture-spec.md` §7.2）。

### 7.2 コマンド

| コマンド | 働き |
| :--- | :--- |
| `vs theme` | 本の `themes/` にあるテーマと、今選ばれているテーマ、同梱のテーマの一覧を示す |
| `vs theme:add <名前\|パス\|git の URL\|npm のパッケージ名>` | テーマを本の `themes/` へ複製する。同梱のテーマは名前、手元のディレクトリや zip はパス、配られたテーマは git の URL、公式テーマは npm のパッケージ名で指定する。複製の後に `vs theme:check` を走らせ、`book.yml` に書く行を示す（`book.yml` は書き換えない） |
| `vs theme:check [名前]` | `theme.yml` の検査・契約の版・§3.5 の範囲・契約 HTML に無いクラスを選んでいる規則の報告（`ContainerClassCheck` の逆向き）・層を外したときに結果が変わる規則の報告（`css-layer-restructure-spec.md` §4.3） |
| `vs theme:new <名前> [--extends standard]` | 配色のテーマか組版のテーマの雛形を `themes/` に作る |

`vs theme:check` の、Kindle に届かない宣言の報告（`v2-post-s3-consultation.md` §5.3 の 4）:

| 宣言 | 報告 |
| :--- | :--- |
| 紙の寸法（`clamp()`・`min()`・`max()`）で落ちた宣言 | 場所を挙げずに、件数を 1 行で示す（💡）。意図した書き方で、直す対象ではない |
| それ以外で落ちた宣言（深い要素の変数・`:has()`・単位の混ざる `calc()`・srgb 以外の混色） | ファイル名と行番号つきの 🟡 |
| `kindle_tokens:` と `kindle.css` の `body.vs-kindle` に書いた、総称の名前でない書体・`--book-font-size`・`--book-line-height` | 🟡（§3.5） |

- 見るのは、検査するテーマ自身のファイルの宣言だけである。`extends:` の先のテーマと vs の部品は含めない。
- `vs build` は、テーマの CSS で落ちた宣言を知らせない（`--log=debug` だけ）。`custom.css` と章の CSS は、今のまま 🟡 で知らせる。
- 同梱のテーマは `rake test` で確かめる。紙の寸法のほかに落ちる宣言を、理由つきの許可の表で持ち（今は会話の `--talk-accent` など 3 種類）、表に無い宣言が落ちたら失敗とする。

- 配布の形は「テーマのディレクトリ」だけを決め、経路は限定しない。git のリポジトリ・zip・npm のどれで配っても、`vs theme:add` が本の中へ複製する。配る側は、ディレクトリを公開するだけでよい。
- `vs theme:add` が外から取得するのは CSS・画像・書体・YAML だけで、スクリプトは実行しない（npm のパッケージは `npm pack` で取得し、`install` のスクリプトを走らせない）。
- テーマの一覧の場所（探すための登録簿）は 2.0 では作らない。
- **経路と段階（`v2-s6-consultation.md` §4.8）。** 同梱のテーマの名前・手元のディレクトリ・手元の zip は S6、git の URL と npm のパッケージ名は S7 で作る（git は S7 の入口の実験の結果に依らず作る）。ネットワークから取得する経路は、git と npm で同じ土台（一時ディレクトリへ取得する・取得したものを信用しない）を使う。
- `book.yml` に書く行を示すときは、テーマの値を覆っている `theme:` 節の行と、空欄にする書き方も一緒に示す（§3.2）。

**複製の決まり。** どの経路も、取得した後は同じ決まりを通る。

1. テーマのディレクトリは、`theme.yml` のあるディレクトリとする（指定した場所の直下か、その下の 1 階層）。見つからなければ 🔴。
2. 複製するのは、拡張子の許可の表にあるファイルだけとする（`.yml`・`.css`・画像の `.webp`・`.png`・`.jpg`・`.jpeg`・`.svg`・`.avif`・書体の `.ttf`・`.otf`・`.woff`・`.woff2`・`README.md`・`LICENSE*`）。それ以外は複製せず、複製しなかったファイルの一覧を示す。本の中に実行できるファイルが入らないので、「スクリプトを実行しない」が決まりではなく作りで成り立つ。
3. シンボリックリンクは複製しない。zip は、中のパスが絶対パスか `..` を含む項目・シンボリックリンクの項目があれば、展開せずに 🔴 で止める。展開は一時ディレクトリで行う。
4. 本の `themes/<名前>/` が既にあれば、置き換わるファイルの一覧を見せて確認を取る。「いいえ」なら何も変えない。
5. `extends:` の先が本の `themes/` に無ければ、同梱のテーマなら一緒に入れ、そうでなければ無いと知らせる（§3.2）。

`vs theme:check` は、改ページを値で書いた規則も 🟡 で示す（`v2-s6-10-consultation.md` §4.3）。テーマの `styles:` の CSS で、最後の複合選択子が `h1` か `h2` の規則に `var()` を使わない `break-before`（`avoid`・`auto` を除く）があるもの。出力先の CSS（`epub*.css`・`kindle*.css`）では `h2` だけを見る（章の改丁は PDF だけの設定）。文面は「`page.section_pagebreak`（または `chapter_pagebreak`）の設定が、このテーマでは効きません」と、書き直した 1 行を示す。`vs theme:new` の組版のテーマの雛形の注釈にも、変数で書く例を入れる。

`vs theme:check` は、テーマの CSS の中の外部の URL（`url(http…)`・`@import url(http…)`）も 🟡 で示す。組むたびにネットワークへ取りにいくテーマを、入れた時点で知らせるためである。

### 7.3 `vs upgrade` と著者のファイル

| ファイル | `vs upgrade` の扱い |
| :--- | :--- |
| `stylesheets/custom.css` | 触らない（今と同じ） |
| 雛形から来たテーマ（`config/scaffold.lock` に記録がある `themes/<名前>/`） | 今の雛形の更新と同じ（変更の無いファイルは置き換え、著者が変えたファイルは三方向のマージ。`upgrade-three-way-merge-spec.md`） |
| 著者が入れたテーマ（`scaffold.lock` に記録が無い） | 触らない。契約の版が今の vs に合わないときだけ 🟡 で知らせる |
| `vs theme:add` で入れた同梱のテーマ | `scaffold.lock` に記録し、雛形から来たテーマと同じに扱う |
| `stylesheets/` の土台と部品 | 今と同じ |

**雛形から消えたテーマのファイル（`v2-s6-10-consultation.md` §4.7。S6-10 で作った。§11.15）。** テーマのディレクトリは置いたファイルが読まれる（出力先の CSS）ので、`vs upgrade` が消す。範囲は `themes/` の下だけ。

| 本の側のファイル | 扱い |
| :--- | :--- |
| lock に記録のあるテーマの、lock に記録のあるファイルで、今の雛形に無く、本の中身が lock の記録と同じ | 計画に「削除」として出し、全体の確認が「はい」なら `.vs-backup/upgrade/` へ退避してから消す。lock の記録も消す |
| 同、本の中身が lock の記録と違う（著者が変えた） | 消さない。lock の記録は消す。最後に 🟡「雛形から無くなったファイルですが、変更があるので残しました」とパスを示す。出力先の CSS なら「置いてあるかぎり読まれます。要らなければ削除してください」、それ以外は「読まれません」を添える |
| lock に記録の無いファイル（著者が足したもの） | 触らない。知らせない |
| lock に記録の無いテーマ | 触らない |

`--dry-run` は「削除」の行を見せるだけ。`--yes` は確認なしで消す（退避があるため）。

著者が同梱のテーマを直して使いたい場合は、`vs theme:new mytheme --extends standard` で自分のテーマを作り、そちらに書くよう案内する。同梱のテーマを直接直すと、`vs upgrade` のたびにマージが起きる。

---

## 8. 契約の版

- 契約の版は整数で、2.0 は `1` とする。`lib/vivlio_starter/cli/theme/contract.rb` に `CURRENT = 1` と `SUPPORTED = [1]` を置く。
- テーマの `contract:` が `SUPPORTED` に無ければ、🔴 で止める。知らせる内容は、テーマの契約の版・この vs が対応する版・どちらを更新すればよいか。
- 版を上げるのは §2.8 の「保証したものを変える・消す」ときと、公開する変数の名前を変える・消すときだけとする。足すだけの変更では上げない。
- 版を上げた後の vs は、一つ前の版のテーマも読めるようにする（`SUPPORTED = [1, 2]`）。前の版を外すのは次のメジャーな版とする。
- テーマが新しい部品（足されたクラス）を前提にする場合は、`theme.yml` に `requires_vs: ">= 2.1"` を書ける。満たさなければ 🔴 で、vs の更新を促す。

---

## 9. 段階ごとの完了の条件と確かめ方

段階の番号と順序は `v2-migration-plan.md` §2 による。どの段階も `rake test` と `bundle exec rubocop` が通ることを含む。

### S1 契約 HTML を書き出す

- 作るもの:
  1. `lib/vivlio_starter/cli/html_contract.rb` — 保証するクラス・属性・`role` の表（§2.2〜§2.5 の分類つき）。
  2. `test/vivlio_starter/html_contract_test.rb` — (a) `stylesheets/` と同梱のテーマの CSS が選ぶクラスが、表の「保証」か、出力先のクラスにある。(b) 見本の原稿（記法の見本帳の章）を HTML にし、出てきたクラスが表の「保証」か「内部」のどちらかにある（表に無いクラスが出たら落ちる）。
  3. `scripts/html_contract_doc.rb` — 表から文書用の一覧を書き出す。
  4. `role` 属性（§2.3）・`article.section-topic` を常に付ける（§2.6）・`vs-vertical` と `vs-fixed`（§2.2。`BookTraits` が無い間は付かないだけでよい）。
- 完了の条件:
  1. 本書の生成物に出るクラス（Prism を除いて 146 種）と、CSS が参照するクラス（238 種）が、すべて表で分類されている。
  2. 本書の四つの出力先の出力が、S0 の基準と比べて、PDF は全ページの画素が一致、EPUB と Kindle は `role` 属性の追加だけが差になる。
  3. `theme.style: simple` にした本書の写しでも、PDF の全ページの画素が、変更の前の `simple` の出力と一致する。
- 確かめ方: `v2-migration-plan.md` §3 の比較。表の作り方は `v2-inventory-report.md` §8 の数え方と同じ（生成物を Nokogiri の HTML5 で読む。CSS はコメント・`url()`・文字列を除き、宣言の中身を消してからクラスを拾う）。

### S6 テーマの仕組みと `standard` の切り出し

- 作るもの: §3 の `theme.yml` の読み込みと検査（`kindle_tokens:` の書き出しを含む）、§3.1 のテーマの出力先の CSS の読み込み、§3.3 のオプションの書き出し、§3.4 の機能の宣言、§4 の切り出し、§5 の変数の名前の変更と別名、§7.2 のコマンド、§7.3 の `vs upgrade` の扱い、§8 の版の検査。
- 最初に入れるもの（寸法をテーマへ移す前）: `LiteralResolver` が `clamp()`・`min()`・`max()` を含む宣言を、理由（`:paper_dimension`）を付けて落とす（`css-layer-restructure-spec.md` §4.4）。
- 完了の条件:
  1. `stylesheets/parts/simple-header.css`・`parts/image-header.css`・`stylesheets/images/bundled/` が無くなり、`themes/standard/` にある（§4 の表）。
  2. `lib/vivlio_starter` の Ruby に（注釈と、テストの材料を除く）、`standard` テーマに固有の名前（`vs-header-image`・`--frontispiece-*` など）を直接書いた箇所が無い（`theme.yml` と機能の宣言から来る）。
  3. 本書の四つの出力先の出力が、その時点の基準（r2。`v2-migration-plan.md` §3.2）と比べて、PDF は全ページの画素が一致、EPUB は下の「EPUB の比べ」の表のとおり、Kindle は中間生成物が差 0 で Kindle Previewer の画面が見比べて同じ。
  4. 配色のテーマの見本（`standard-mono`。`extends: standard` と `tokens:`・`kindle_tokens:` だけ。材料は `test/vivlio_starter/fixtures/themes/standard-mono/` に置き、写しの本の `themes/` へ複製して使う。同梱しない）で、`book.yml` の `theme.color`・`preface_color`・`appendix_color` を空欄にした本書を組み（§3.2）、色だけが変わる（PDF の文字の位置が `standard` と一致する。`pdftotext -bbox` の座標の比較）。Kindle でも色が変わる。
  5. 1.x の `custom.css`（今の名前の変数を使ったもの）を置いた写しで、色の変更が効く。
  6. `theme.name` に無い名前を書くと 🔴、`contract: 2` のテーマを置くと 🔴、`supports.writing_mode` に無い組方向で 🔴 になり、それぞれ次にすることを示す。
  7. `clamp()`・`min()`・`max()` の宣言を落とす変更の前後で、Kindle の中間生成物が差 0（今も Kindle に届いていないので、変わらないはずである）。Kindle 用の CSS に `clamp(`・`min(`・`max(` が残らない。
  8. `targets/` の規則を `themes/standard/` へ移す前後で、EPUB の計算値（`css_computed_diff.rb`）と Kindle の中間生成物（`kindle_record_diff.rb`）が差 0。
  9. 変数の名前を `--book-*` に変える前後で、Kindle の中間生成物が差 0（`kindle-tokens.css` を `--book-*` で書き直した後も、本文の字の大きさ・行送り・書体が端末任せのままである）。
  10. 配色のテーマの見本に `kindle_tokens:`（見出しの書体を `serif` に）を書くと、Kindle の見出しだけが明朝になり、PDF と EPUB は変わらない。`kindle_tokens:` に `font-size` か、総称の名前でない書体を書いたテーマで、`vs theme:check` が 🟡 を出す。
- 確かめ方: 3 は `v2-migration-plan.md` §3。4〜6・10 はテストと、写しの本での実行。7〜9 は、変更ごとに前後を組んで比べる。

#### S6 の小段階と、段階の中で決めること（2026-11-16）

決定の経緯は `v2-s6-consultation.md` §4。S6 は十の小段階に分ける。どの小段階も、完了のコミットは「本書の出力が、その時点の基準（r2）と同じ」ものだけにする。EPUB と Kindle 用の CSS の字面は S6-2・S6-4・S6-6 で変わるので、「同じ」の中身は下の「EPUB の比べ」による。前後の比べの相手は、前の小段階の確かめの出力（基準のディレクトリの `r2/check/s6-<番号>/`）を使う。四つの出力先と B2〜B4 を組む全部の比べの時点は `v2-migration-plan.md` §3.6 に書く。

| 小段階 | 作るもの | 確かめ |
| :--- | :--- | :--- |
| S6-1 紙の寸法の宣言を落とす | `LiteralResolver` が `clamp()`・`min()`・`max()` を含む宣言を、理由 `:paper_dimension` を付けて落とす。`css_layer_test.rb` の許可の表から紙の寸法を分ける | 完了の条件の 7（B1 の Kindle の中間生成物が差 0・Kindle 用の CSS に `clamp(`・`min(`・`max(` が無い）。クリーン EPUB の CSS は前後でバイト単位で同じ（リテラル化を通らないため） |
| S6-2 変数の名前を `--book-*` へ | `stylesheets/tokens.css` を `--book-*` の 1 行ずつの一覧にする。`stylesheets/`・`templates/`・`lib/`（`BookSettingsCss`・`CssUpdater`・`techbook/processor.rb`・`inject_heading_images.rb` など）の名前の置き換え。`targets/kindle-tokens.css` を `--book-*` で書く。`Css::LegacyTokens`（対応の表）・`tokens-legacy.css`（読む向き）・settings 層の書き出し（値を入れる向き）・今の名前を使う `custom.css` への 💡。`--color-shadow` を消す | 完了の条件の 9。前の平らな CSS に対応の表の置き換えを当てたものが、後の平らな CSS と一致する（`tokens-legacy.css` の分と `--color-shadow` を除く）。EPUB の計算値が差 0。完了の条件の 5（今の名前を使った `custom.css` の写し）。その後、全部の比べ |
| S6-3 テーマを読む仕組み | `theme.name`（`ConfigKeys`・雛形の `book.yml`）。`Theme::Manifest`（読み込み・検査・`extends:` の 1 段）・`Theme::Contract`（`contract:`・`requires_vs:`）。`EntryWriter` が `styles:` を theme 層に、`tokens:` を tokens 層に、テーマの出力先の CSS を target 層に入れる（順は `css-layer-restructure-spec.md` §5 の 1〜5）。`TraitCombinationCheck` の `supports:` の行。中身の無い `themes/standard/theme.yml`（`name`・`title`・`version`・`contract`・`supports` だけ）。`build_copy.rb`・`copy_to_scaffold.rb`・`scaffold.lock` に `themes/` を足す | 本書の入口の CSS（`.cache/vs/entry-*.css`）と契約 HTML が、前後でバイト単位で同じ。完了の条件の 6（材料のテーマで 🔴 の 3 通り）。`extends:` の読む順のテスト。単章のビルドと `vs preflight` |
| S6-4 見出しの 2 枚を theme 層へ | `parts/simple-header.css`・`parts/image-header.css` を、置き場を変えずに parts 層から theme 層へ移す（`EntryWriter` の表だけを変える）。本文以外の種類（目次・索引など）の入口にも入る | B1 の `pdf`・`epub`・`kindle` と B2 の `pdf` を組む。PDF は全ページの画素が一致。EPUB の計算値と Kindle の中間生成物が差 0。`InversionCheck` の要素ごとの判定が B1・B4 の EPUB と Kindle 用 EPUB で 0 組 |
| S6-5 `standard` へファイルと画像を移す | 2 枚を `themes/standard/` へ移し、`theme.yml` の `styles:` に今の順（`simple-header.css` → `image-header.css`）で並べる。`stylesheets/images/bundled/` を `themes/standard/images/` へ移す。画像の指定を探す順（`v2-migration-plan.md` §5.3 の 4）。`images/bundled` を書いた `lib/` の 10 ファイル | 入口の CSS の差が、2 枚の `@import` の行のパスだけ。B1 の EPUB と Kindle 用 EPUB が `epub_diff.rb` で違い 0 件（Kindle 用 EPUB が同じなので、変換はしない）。B1・B2 の PDF は全ページの画素が一致。`rake test:layout` |
| S6-6 出力先の規則を `standard` へ | `targets/epub.css`・`targets/kindle.css` の規則のうち、選択子が `vs-header-image`・`vs-header-simple` を含むもの（今は 3 か所と 8 か所）を、選択子と宣言を変えずに `themes/standard/epub.css`・`kindle.css` へ移す | 完了の条件の 8（B1 の EPUB の計算値と Kindle の中間生成物が差 0）。EPUB の HTML はバイト単位で同じ。PDF は、入口の CSS が前後でバイト単位で同じであることだけを見る（target 層を読まないため） |
| S6-7 オプションと機能の宣言 | `theme.yml` の `options:`、`Theme::Features::Frontispiece`・`Ornament` の宣言、`ConfigKeys::KEYS` から `theme.*`（`name` を除く）を外す、`Common.load_config` の 3（`v2-architecture-spec.md` §5.3）、`BookSettingsCss` が `token:` から書き出す、`BodyClassInjector` が `body_class:` から付ける、値の検査を宣言から行う（`ThemeValidator` の置き換え）、`HtmlContract` の `theme_option` を宣言から引く、`BuildPlan.features` に `frontispiece`・`ornament`、`theme:` 節の宣言に無いキーの 🟡（§3.3） | 完了の条件の 2。B1・B2・B3 の設定で、`Common::CONFIG` の書き出しと `.cache/vs/book-settings.css` が前後でバイト単位で同じ。契約 HTML がバイト単位で同じ。段の一覧が同じ。`theme.color` などに読めない値を書いた材料で、🟡 の文面が前後で同じ。その後、全部の比べと画面。`rake test:standard` |
| S6-8 コマンド | `vs theme`・`vs theme:add`（§7.2 の S6 の経路）・`vs theme:check`・`vs theme:new` | `themes/standard/` に `vs theme:check` を掛けて 🟡 が 0 件。`vs theme:new x --extends standard` の出力が `vs theme:check` を通る。zip の検査（§7.2 の複製の決まりの 3）のテスト |
| S6-9 `vs upgrade` | §7.3 の表（`scaffold.lock` に記録のあるテーマの更新・`vs theme:add` で入れた同梱のテーマの記録・著者のテーマの契約の版の 🟡）と、`custom.css` の今の名前の置き換え（`css-layer-restructure-spec.md` §7.2） | 写しの本での実行。`ToolUpgrader.run!` を差し替えて走らせる（道具の更新がマシンに効かないようにする）。置き換える行を全部見せ、「いいえ」で何も変わらないこと |
| S6-9b 改ページを変数で読む（`v2-s6-10-consultation.md` §4.5） | `tokens.css` に 3 つの変数（§5.2）。`themes/standard/` の 4 か所（`simple-header.css` の h1・h2、`image-header.css` の `.section-topic h2`、`kindle.css` の `body.vs-header-simple.vs-kindle h2` の変数の名前。`kindle.css` の `var()` の予備の値は外す）。`BookSettingsCss` の定数からテーマの選択子を消し、変数を書く（vs 自身の選択子の打ち消しは残す）。章扉の保護を `Theme::Features::Frontispiece` へ（§3.4）。`PAGE_KINDS` と判定の窓口、`PageBreakNormalizer`・`ChapterLeadCheck` の置き換え。`vs theme:check` の検査と `vs theme:new` の注釈（§7.2） | `lib/vivlio_starter` に `vs-header-` を書いた行（注釈を除く）が 0。B1 の四つの出力先、B2 と B3 の `pdf` を組む。PDF は r2 と全ページの画素が一致。契約 HTML は前後でバイト単位で同じ。`book-settings.css` の差が改ページの節だけ。EPUB の計算値と Kindle の中間生成物が差 0。`InversionCheck` が 0 組。`themes/standard/` に `vs theme:check` で 🟡 0。B2 の設定のクリーン EPUB を前後で組み、計算値が差 0。後の側を Apple Books で開き、`false` と `true` の写しで節の改ページを 2〜3 か所見る（働かなければ、`simple-header.css` の h2 に予備の `break-before: page;` を前の行に足す形を試し、結果をユーザーに示す）。`break-before` の計算値に差が出たら、直さずに記録してユーザーに示す。`any` で消える `page-break-before: always` の分で Kindle の中間生成物に差が出たら、中身を記録してユーザーに示す。`rake test`・`rake test:layout` |
| S6-10 配色のテーマと `kindle_tokens:` | `kindle_tokens:` の書き出し（target 層の 2 番目）。材料の `standard-mono`。S6 の完了の確かめ | 完了の条件の 4・10。全部の比べ。`rake test:layout`・`rake test:standard`・`rake test:release` | §7.3 の「雛形から消えたテーマのファイル」（`upgrade_commands_test.rb` に 3 件。写しの本で、1 ファイルを抜いた材料の雛形に `--dry-run` と本番を走らせ、退避と lock を見る） |

S6 の範囲に入れないもの: `vs theme:add` の git と npm の経路（S7）、`BookProfile` の `theme.name`（S8。`v2-architecture-spec.md` §2.2）、1.x の本の `stylesheets/` を 2.0 の配置へ移す手順（`v2-migration-plan.md` §5.3 の 2〜4・6・7。S11）、原稿の中の変数の名前（S11）、vs の内部の変数の改名（§5.1）、見出しの 2 枚のほかの規則を theme 層へ移すこと（§4）。

仕様に書かれていなかったので、S6 では次のように決める（2〜5・8・11 は該当の節へ書いた）。

1. **`standard` の切り出しは、層を移す小段階（S6-4）と、置き場を移す小段階（S6-5）に分ける。** 見出しの 2 枚は今 parts 層の最初に読まれている。theme 層へ移すと、PDF では parts・pages のどの規則にも詳細度に関係なく勝ち、平らな CSS では並びが pages の後になる。`parts/heading.css` は今 2 枚より後に読まれるので、詳細度が同じ組では今 `heading.css` が勝っている。この入れ替わりが S6 でいちばん差の出やすい箇所で、置き場の移動と同じコミットにすると、差の原因が層かパスかを分けられない。差が出たら、S3-2 と同じく選択子の形をそろえて直す。
2. `tokens:` の書き出し先は tokens 層（§3.1）。
3. 扉絵の `@page :nth(1)` は vs に残す（§3.4）。
4. 配色のテーマの `tokens:` を、土台のオプションの既定値として重ねる（§3.2）。
5. `body_class:` の種類ごとの形と `default_from:`（§3.3）。
6. `options:` に置けるのは `token:` と `body_class:` で渡せるものだけ（§3.3・§3.4）。
7. 名前を変える範囲（§5.1）。
8. **原稿の中の変数の名前は、S6 では書き換えない。** `contents/46-utility.md`（`custom.css` の書き方の表）と `contents/23-figures.md` は今の名前を載せている。書き換えると本書の PDF が変わる。今の名前は別名で効くので、説明は誤りにならない。マニュアルの書き直しは S11 で行う（`v2-migration-plan.md` §4.3）。
9. **`theme.name` は、雛形の `book.yml` に `name: standard` として書く。** 「載せると決めたキーは全部書く」（`config-key-criteria-guidelines.md` §1）による。本書の `book.yml` に 1 行増えるが、出力は変わらない。
10. テーマの出力先の CSS へ移すのは、選択子が `vs-header-*` を含む規則だけ（§4）。
11. **S5 の完了の条件の 4（`page.writing_mode: vertical` の最小の本）のテストは、`supports.writing_mode: [horizontal, vertical]` を書いた材料のテーマで組む。** `standard` は横書きだけなので、S6-3 から 🔴 で止まる（`v2-architecture-spec.md` §8 の S5 の決め 3）。
12. **`themes/standard/theme.yml` の `tokens:` は、S6 の完了の時点で空でよい。** 公開する変数の既定値は `stylesheets/tokens.css` が正典である（§4・§5.2）。

**EPUB の比べ（完了の条件の 3。`v2-s6-consultation.md` §4.4）。** 変更の種類ごとに、いちばん強い比べを当てる。

| 比べるもの | 基準 |
| :--- | :--- |
| HTML（契約 HTML と EPUB の中の XHTML）・OPF | どの小段階でも、r2 とバイト単位で同じ（S4 で記録した属性の順の 2 件と、画像の名前を除く） |
| CSS — 字面を変えない小段階（S6-1 のクリーン EPUB・S6-3・S6-5・S6-7） | 前の小段階とバイト単位で同じ（S6-5 は `url()` の中の画像の名前を除く） |
| CSS — 名前を変える小段階（S6-2） | 前の CSS に対応の表の置き換えを当てたものと一致する。あわせて計算値（`css_computed_diff.rb`）が差 0 |
| CSS — 読む順を変える小段階（S6-4・S6-6） | 計算値が差 0。`InversionCheck` の要素ごとの判定が 0 組 |
| EPUBCheck | 毎回、致命・エラー・警告とも 0 |
| Apple Books の画面 | S6-7 の後に 1 回、r2 の 10 か所と見比べる |

- 計算値の比べでは、変数そのもの（`--` で始まるプロパティ）の行を除く。S6-2 で名前が変わるためである。変数の値が正しく届いているかは、変数を読む側のプロパティ（`color`・`font-family` など）の計算値で分かる。
- Apple Books の画面を小段階ごとに見ないのは、計算値が差 0 で HTML がバイト単位で同じなら、表示が変わる経路は「同じ計算値を Apple Books が別に描く」だけで、S6 の変更はその経路に触れないためである。S6-7 の後の 1 回は、道具（`css_computed_diff.rb` は Chromium で計算する）が見ていない差が無いことの確かめである。

### S7 公式テーマの取り込み

- **S7a と S7b に分ける**（2026-11-17・`v2-migration-plan.md` §2.1・§2.2）。S7a は下の入口の実験だけで、製品のコードを足さず、S8 の前に行う（vs の部品が縦書きでどう崩れるかを最初に見せる）。S7b は「作るもの」の全部（git と npm の経路・§6.2 の変換・`bridge.css`）で、S8 の後に行う。実験が通らない場合の手は `v2-migration-plan.md` §2.4 の 1。
- 入口の実験（S7a。実装の前に行う）: 本書の章を 2 つ選び、`role` 属性の付いた契約 HTML に、`theme-bunko` と `theme-base` を §6.2 の形（`theme` 層・`bridge.css`）で当てて、Vivliostyle で PDF と EPUB を組む。確かめる点は次の四つ。(a) 縦書き・右綴じで組める。(b) 見出し・段落・ルビが `theme-bunko` の見た目になる。(c) vs の部品（脚注・囲み・図）が崩れない。(d) 判型が vs の `page.use` の値になる。あわせて、実験の本の EPUB で、層を外すと勝ち負けが変わる組（要素ごとの判定）の数と中身を記録する（`v2-s6-10-consultation.md` §4.6）。結果を `v2-feasibility-notes.md` に追記する。
- 実験で (a)〜(d) のどれかが成り立たない場合: 取り込みを「CSS を写すだけで、結果は保証しない」に下げ、`vs theme:add` の npm の経路は 2.0 に含めない、という判断をユーザーに仰ぐ。小説の既定のテーマは vs が書く（§6.4）ので、2.0 の小説の出力はこの実験の結果に左右されない。
- 作るもの: `vs theme:add` の git の URL の経路（入口の実験の結果に依らず作る）と npm の経路、§6.2 の変換、§6.3 の `bridge.css` の生成。どちらの経路も、取得した後は §7.2 の複製の決まりを通る。
- git の経路の確かめ方（`v2-s6-consultation.md` §4.8）:
  - 取得は、一時ディレクトリへ `git -c core.hooksPath=/dev/null clone --depth 1 --no-recurse-submodules <URL>` で行う。その後は複製の決まりだけを通し、取得したディレクトリの中でコマンドを走らせない（`bundle`・`npm`・`rake`・`make` を呼ばない）。
  - テストは、手元に作った材料のリポジトリ（`file://` の URL）で行う。材料には、`package.json`（`scripts.postinstall` が、決めた場所に印のファイルを作る）・`Rakefile`・`Makefile`・実行できる `.sh`・`.git/hooks/post-checkout` を入れる。`vs theme:add` の後で、(a) 本の `themes/<名前>/` に許可の表の拡張子のファイルしか無い、(b) 印のファイルができていない、(c) 一時ディレクトリが消えている、の三つを検査する。ネットワークは使わない。
- 完了の条件: `vs theme:add @vivliostyle/theme-bunko` の後、`theme.name` を替えるだけで、小説の見本の本が `pdf`・`print_pdf`・`epub` で組める。`targets` に `kindle` があると、`v2-architecture-spec.md` §2.5 の検査が 🔴 で止め、対応するテーマを示す。

---

## 10. 論点（未決）

| # | 論点 | 答えが要る時点 | 設計での扱い |
| :--- | :--- | :--- | :--- |
| 1 | 小説と絵本の既定のテーマの名前 | 決定済み（2026-11-17） | `novel`・`picture-book`。公式テーマを取り込んだものは `vivliostyle-<名前>`（`v2-s8-novel-consultation.md` §4.5・`v2-s9-picture-book-consultation.md` §4.9・`v2-plan-review-consultation.md` §4.6 の 5）。この仕様書の中の `bunko`・`picture` は `novel`・`picture-book` へ直した（2026-11-17。実装記録の中は当時の名前のまま） |
| 2 | 対応表（`bridge.css`）に載せる変数の一覧 | S7b | S7a の結果を見て、S7b で Opus が決める。軸: 公式テーマと vs の両方が定義し、判型・余白・書体・本文の字の大きさと行送りに効くものだけ。色と飾りは載せない。20 を超えるなら、載せすぎを疑う（`v2-plan-review-consultation.md` §4.6 の 6） |
| 3 | テーマを探すための一覧（登録簿）を持つか | 2.0 の後 | 2.0 では作らない |
| 4 | `theme-epub3j` を土台にしたテーマを同梱するか（電書協の様式を求める著者向け） | 決定済み（2026-11-17） | 同梱しない（`v2-plan-review-consultation.md` §4.6 の 5） |
| 5 | 部品に残した飾りの規則（§4 の「部品に残す飾り」）を `standard` へ移す範囲 | S8-5（`novel` を書くとき） | S6 では見出しの 2 枚だけを移す。S8-5 で Opus が決める。軸: `novel` で打ち消しが要った規則だけを移す。いちばんの候補は前書きの見た目（`parts/preface.css`）。移すたびに本書を基準と比べる（`v2-s8-novel-consultation.md` §4.3） |
| 6 | 改ページの打ち消しが写すテーマの選択子 | 決定済み（2026-11-17） | 公開する変数で読む（§3.5・§5.2。`v2-s6-10-consultation.md` §4.3） |
| 7 | 著者が入れたテーマの層の勝ち負けの組を知らせる形 | S7a | `vs build` では 🟡 にしない（`--log=debug` のときだけ）。S7 の入口の実験で公式テーマの組の数を記録し、多くて取り込みの変換で直せないと分かったときに限り、「`vs theme:add` が入れた時点で 1 回知らせる」形を S7 の仕様で決める（`v2-s6-10-consultation.md` §4.6） |
| 8 | 雛形から消えたテーマのファイル | 決定済み（2026-11-17） | `vs upgrade` が消す（§7.3。S6-10。`v2-s6-10-consultation.md` §4.7） |

---

## 11. 実装記録

### 11.1 S1 契約 HTML を書き出す（2026-11-14）

#### 作ったもの

- `lib/vivlio_starter/cli/html_contract.rb`: 契約 HTML の表。クラス 241 種（保証 223・テーマ 2・内部 16）を §2.2〜§2.5 の分類（`CATEGORIES`）に分け、名前の形で決まる 2 種（`language-*` は保証・`talk-c-*` は内部）・Prism のトークン・ページの種類の `role`（`PAGE_ROLES`）・保証する属性を置いた。CSS と HTML からクラスを拾う手続き（`css_classes`・`unclassified_classes`）も同じファイルにあり、テストと確かめの両方がこれを使う。
- `lib/vivlio_starter/cli/post_process/role_injector.rb`: 章・前書き・後書き・付録・部扉の `body > section.level1` に `role` を付ける。値は `PAGE_ROLES` から読む。索引（`section.index`）は `index/unified_page_builder.rb` が、奥付は `create.rb` が自分で付ける。
- `SectionWrapper` は `theme.style` を読まなくなり、h2 を常に `article.section-topic` で包む。
- `scripts/html_contract_doc.rb`: 表から一覧を Markdown で書き出す（`--out FILE`）。
- テスト: `test/vivlio_starter/html_contract_test.rb`（(a)・`role`・包み）と、`notation_coverage_test.rb` の `test_built_pages_use_only_classes_in_the_html_contract`（(b)）。

#### 仕様と違えたこと（2026-11-14 ユーザー確認）

1. **奥付の `role`。** 奥付は `body` の直下に h1・p・dl が並ぶだけで、§2.3 の「奥付の最上位の要素」が無かった。`create.rb` の雛形の中身を `<section role="doc-colophon">` で包んだ。EPUB の差は `role` の追加だけでなく、要素 1 つの追加になる。Kindle はこの section を `div`（余白 0）に変える。
2. **`simple` の本の EPUB。** h2 を常に包むと、components.css の `body.vs-epub .section-topic`（上下の余白 1.8em・0.6em）が、`simple` の本の章にも当たる。`image` の本の付録は以前からこの規則で組まれているので、そろうものとして受け入れた。§9 の完了の条件 3 は `simple` の PDF だけを見る。実測では、Kindle の計算済みの値は前後で変わらなかった（`article` の余白は 0 のまま、h2 の上下の余白も同じ）。Apple Books の画面も、前後で 10 か所とも画素まで一致した（節見出しの空きは変わらない）。
3. **(b) の置き場。** 見本帳を組むと 80 秒ほどかかるので、`html_contract_test.rb`（`rake test`）ではなく、記法網羅のテスト（`test:notation`・`test:release`）に足した。見本帳は `test/vivlio_starter/fixtures/notation/` で、そのテストが 1 度だけ組んだ HTML を共用する。
4. **表の作り。** 水準に「保証」「内部」のほかに「テーマ」（`vs-header-image`・`vs-header-simple`。§2.2 の「そのテーマの中でだけ意味を持つ」）を置き、付く段（`:contract`・`:target`）を足した。`:target` は、契約 HTML には無く、出力先の変換（PDF・EPUB・Kindle の写し）が付けるクラス（`vs-code-line`・`vs-adm-label`・`vs-image-heading-epub` など）である。CSS が選んでいるものは保証、選んでいない目印は内部とした。
5. **保証と内部の線引き。** §2.1 は「CSS が参照していない 23 種」を内部の例に挙げるが、そのうち `level1`〜`level4`・`vs-h-marker`・`subsection-title`・`vs-emoji` は §2.3・§2.4 が保証として名前を挙げているので、保証にした。残る 16 種（`index-term`・`talk-c-*`・`footnote-ref`・`cross-ref-list`・`toc-label` など）を内部とした。
6. **全巻目次。** `body` のクラスは `whole_toc`（`TokenResolver` の `kind` をそのまま付ける。下線を含む）で、toc.css も `body.whole_toc` を選んでいる。分冊の本の上巻に `whole_toc: true` を書いた写しで組んで確かめた。§2.3 の表に全巻目次の `role` が無いので、付けていない。同じ写しで、本書に出ない 5 種（`whole-toc`・`whole-toc-preface`・`whole-toc-postface`・`cross-ref-other-volume`・`index-other-volume`）を見つけて保証に足した。
7. **`aria-labelledby`。** §2.3 の例の HTML にあるが、表に無く、VFM も出力しないので付けていない。
8. **§2.5 の部品**（`tcy`・`sesame`・`vs-video`）は、まだ生成されないが、表に「2.0 で足す部品」として置いた。`vs-vertical`・`vs-fixed` も同じく表にだけある（`BookTraits` が無いので付かない）。

#### 確かめた結果

| 条件 | 結果 |
| :--- | :--- |
| 1. クラスがすべて表で分類されている | 本書の生成物のクラス 147 種（Prism を除く。`v2-inventory-report.md` §2.2 の 146 種との差 1 は数え方による）と、CSS が選ぶクラス 238 種が、すべて表にある。記法網羅の見本帳・分冊の本（全巻目次つき）・本書の PDF と EPUB の写しでも、表に無いクラスは 0 |
| 2. 本書の四つの出力先 | 閲覧用 PDF 283 ページ・印刷用 PDF 281 ページとも、違うページ 0。EPUB・Kindle 用 EPUB とも、テキストの差 35 件はすべて `role` の追加（章 20・付録 6・部扉 5・前書き・後書き・索引・奥付 各 1）と奥付の section だけ（S1 の変更をほどいて XHTML を比べると差 0）。EPUBCheck は両方ともエラー・警告 0。Kindle は変換の記録が基準と同じ（Supported・Success・エラー 0・注意は W14016 の 1 件）、中間生成物 36 件の計算済みの値は、奥付に足した div を除いて一致。Kindle Previewer の画面は 10 か所とも基準と画素まで一致（差 0 画素）。ただし奥付の Location が 10480 から 10484 へずれた（それより前の 9 か所は同じ Location）。Apple Books の画面も 10 か所とも基準と画素まで一致 |
| 3. `simple` の PDF | 279 ページとも、違うページ 0 |

### 11.2 S6-1 紙の寸法の宣言を落とす（2026-11-16）

#### 作ったもの

- `Css::LiteralResolver.literal_value` が、値に `clamp()`・`min()`・`max()` を含む宣言を、理由 `:paper_dimension` を付けて落とす。変数を解く前の値と、解いた後の値の両方を見る（変数の値から入ってきた紙の寸法も落とす）。判定は `call_start`（引用符の外・名前の頭だけ）を使うので、`minmax()` の `max(` や `min-width` には当たらない。変数の定義に紙の寸法があれば、ほかの解けない定義と同じく知らせずに落とす。
- `calc()` の中の `clamp()`・`min()`・`max()` を計算する道（`calc_compare` と `CALC_TOKEN` の該当の字句）を消した。含む宣言を先に落とすので、通らなくなったためである。
- `Css::Bundle.literalize` は、`:paper_dimension` で落とした宣言を、著者の CSS（`custom.css`・章が足した CSS）のものでも 🟡 で知らせない（`--log=debug` の一覧には出る）。
- テスト（`literal_resolver_test.rb`）: 紙の寸法の決まり（`calc()` の中・外・変数から・`minmax()`・`min-width`・引用符の中）を確かめるテストを足した。同梱の CSS で組む Kindle の束に `clamp(`・`min(`・`max(` が残らないことを、`test_should_leave_no_function_that_kfx_drops` に足した。`custom.css` の紙の寸法を知らせないことを、警告のテストに足した。`calc()` の中の `clamp()` を計算する、今までのテストの 2 行は、新しいテストへ移した（期待値は「落とす」に変わる）。

#### 仕様と違えたこと

1. **検査の置き場。** 小段階の表は「`css_layer_test.rb` の許可の表から紙の寸法を分ける」としていたが、その許可の表（`css-layer-restructure-spec.md` §4.5 の「Kindle 用に落ちる宣言は、紙の寸法のほかを、理由つきの許可の表で持つ」）は、まだ作られていなかった。紙の寸法の検査は、実物の `book-settings.css` で Kindle の束を組む `literal_resolver_test.rb` に入れた。`css_layer_test.rb` は `book-settings.css` を外して束を組むので、本書のビルドでは定義される変数（扉絵の画像など）も「解けない」に数えられる。許可の表をそこで作ると、実際のビルドには無い落ち方が表に載る。§4.5 の許可の表は、S6-2 の最初に、`book-settings.css` を入れた束で作る（S6-2 は名前の変更で、宣言が解けずに落ちても組むのは止まらないので、その検出に要る）。
2. **著者の `custom.css` の紙の寸法。** §4.5 の表は、著者の `custom.css` の「Kindle に届かない宣言」を 🟡 で示すとしている。紙の寸法は意図した書き方（§3.5・`css-layer-restructure-spec.md` §4.4 の「ほかの理由と分けて扱う」）で、`custom.css` に PDF の紙面のために書いた `clamp()` を毎回知らせると、直す必要の無い警告が続く。S6-1 の前も、知らせずに Kindle へ届いていなかった。知らせないことにした。

#### 確かめた結果

| 確かめ | 結果 |
| :--- | :--- |
| 完了の条件の 7（Kindle の中間生成物） | B1 の四つの出力先を組み（`r2/check/s6-1/`）、r2 と比べた。中間生成物 36 件・26,405 要素で `computedstyle`・`style` とも差 0。疑似要素の値（`data-before`・`data-after`）も差 0。変換は Enhanced Typesetting の KPF・成功 |
| Kindle 用の CSS | `clamp(`・`min(`・`max(` が 0 か所（r2 では 5 ファイル・243 か所）。r2 との差は、紙の寸法の宣言の行 233 行と、宣言が紙の寸法だけだった規則が空になって消えた選択子と閉じ括弧の行 42 行だけで、増えた行は 0。HTML の差は S4 で記録した属性の順の 2 件だけ |
| クリーン EPUB | r2 との差は S4 で記録した属性の順の 2 件だけ（CSS はバイト単位で同じ）。EPUBCheck は致命・エラー・警告とも 0（Kindle 用 EPUB も 0） |
| テスト | `rake test` 4,418 件が通った（スキップ 1 は前からのもの）。`bundle exec rubocop` は違反 0 |

- PDF は比べていない。S6-1 は Kindle 用の CSS の生成だけを変え、PDF が読む入口の CSS に触れないためである（S6 の小段階の表の確かめにも無い）。
- 下調べで、vs の CSS がどこにも定義の無い変数を読んでいる箇所を 5 つ見つけた（`--color-header`・`--color-surface`・`--header-font`・`--page-block-margin-start`・`--color-gray`）。S6-1 の前からのもので、直していない。S6-2 で変数の名前を一覧にするときに扱う。

### 11.3 S6-2 の前段: 許可の表と、定義の無い変数（2026-11-16）

S6-2 の名前の変更に入る前に、宣言が解けずに落ちたことを見つける検査と、どこにも定義の無い変数を読む宣言の直しを、別のコミットにした。名前の変更の差と混ざらないようにするためである。

#### 作ったもの

- **Kindle で落ちる宣言の許可の表**（`css-layer-restructure-spec.md` §4.5。`css_layer_test.rb` の `ALLOWED_KINDLE_DROPS`）。本書の `book.yml` から作った `book-settings.css` を入れた束で、ページの種類ごとに Kindle の束を解く。紙の寸法のほかに表に無い宣言が落ちたら失敗し、表の行がどの宣言にも当たらなくなっても失敗する。body のクラスは本書の Kindle 用 EPUB と同じにした（章は `vs-header-image`、付録は `vs-header-simple`）。紙の寸法を除いて 45 件が落ち、表は 13 行になった（会話・副題の飾り・WebP の扉絵と節絵・単位の混ざる `calc()`・oklab の混色・`:has()`）。どの行も、KFX が解さない書き方なので、リテラル化を入れる前から Kindle には届いていない。
- **定義の無い変数を読む宣言を直した。** §11.2 で挙げた 5 つに、目次のページ番号の `--folio-font` を足して 6 つあった。値が無効な宣言は、色や書体のように受け継ぐプロパティでは親の値に、ほかでは初期値になる。同じ要素に当たるほかの規則を調べ、今と同じ値になる書き方にした。

| 箇所 | 直し方 | 今と同じになる理由 |
| :--- | :--- | :--- |
| `parts/preface.css` の h1〜h3 の `color: var(--color-header)` | 消す | ほかに色を決める規則が無く、親の色を受け継ぐ |
| `parts/preface.css` の `strong, b` の `color: var(--color-header)` | `color: inherit` | 消すと `parts/prose.css` の `strong { color: var(--color-strong) }` が勝つ |
| `parts/preface.css` の blockquote の `background: var(--color-surface)` | 消す | 地の色を決める規則がほかに無い（初期値の透明） |
| `pages/toc.css` の h2 の `font-family: var(--header-font)`・ページ番号の `font-family: var(--folio-font)` | 消す | 目次の束で書体を決める規則がほかに無く、親の書体を受け継ぐ |
| `parts/simple-header.css` の h1・h2 の `background-color`（`--heading-gray`・`--section-gray` ← `--color-gray`）と、二つの変数の定義 | 消す | 同じ規則の `background` の一括指定が地の色を初期値（透明）にしている |
| `parts/simple-header.css` の h1 の `margin-block-start`（`--page-block-margin-start` を引く） | 消す | reset の `* { margin: 0 }` と同じ 0 |

- Kindle 用の CSS では、`strong, b { color: inherit; }` の 1 行が前書き・後書きに増える。強調は `targets/kindle.css` の `body.vs-kindle strong` が勝ち、`b` は初期値のまま受け継ぐので、表示は変わらない（下の中間生成物の差 0）。

#### 確かめた結果

B1（四つの出力先・Kindle の記録つき）・B2・B4 を組み（`r2/check/s6-2a/`）、r2 と比べた。

| 確かめ | 結果 |
| :--- | :--- |
| PDF の画素 | B1 の `pdf` 284 ページ・`print_pdf` 282 ページ、B2 279 ページ、B4 317 ページとも違い 0 |
| 計算値（`css_computed_diff.rb`。前は 8624010e） | B1 の 78 文書・234 組、B4 の 56 文書・168 組（EPUB と PDF・画面と印刷・層ありと平ら）とも違い 0。前書きの強調（本書の前書きに 15 か所）を含む |
| EPUB | B1 のクリーン EPUB は、S4 で記録した属性の順の 2 件と、CSS 4 枚の上の宣言の削除だけ。B4 は CSS 3 枚だけ。EPUBCheck は B1 の 2 本・B4 とも致命・エラー・警告 0 |
| Kindle | 中間生成物 36 件・26,405 要素で `computedstyle`・`style` とも差 0。Kindle 用 EPUB の S6-1 との差は、`preface.css`・`postface.css` の `color: inherit` の 1 行ずつだけ |
| テスト | `rake test` 4,419 件が通った（スキップ 1 は前からのもの）。`bundle exec rubocop` は違反 0 |

- B4 の素材（`r2/src/ai_web_starter/`）は r2 の時点の `stylesheets/` を持っている。そのまま組むと CSS の変更が入らず、差 0 になってしまう。`v2-migration-plan.md` §3.2 の決まりどおり、`stylesheets/` を作業ツリーのものに差し替えた写し（`custom.css` は本のものを残す）で組んだ。

### 11.4 S6-2 変数の名前を `--book-*` へ（2026-11-16）

#### 作ったもの

- **対応の表** `Css::LegacyTokens`（`lib/vivlio_starter/cli/css/legacy_tokens.rb`）。今の名前 → 新しい名前の 69 行（§5.2 の公開する変数・扉絵と節絵の変数・`--heading-text` → `--standard-heading-text`）と、消した変数の表（`--color-shadow`・`--heading-gray`・`--section-gray`。後の 2 つは §11.3 で消したもの）。置き換え（`rename`）・`custom.css` が使う今の名前（`legacy_names_in`）・settings 層の書き出し（`settings_declarations`）・別名の CSS（`alias_css`）が、この表を読む。
- **名前の置き換え。** `stylesheets/` の 32 ファイルと、`lib/` の書き出し（`BookSettingsCss`・`CssUpdater`・`FrontmatterGenerator`・`ThemeColor`・`techbook/processor.rb` が HTML に入れる `<style>`）を表で置き換えた。名前を組み立てる箇所（`var(--accent-#{…})`）と `ThemeColor::ACCENT_DECLARATION` は手で直した。
- **`tokens.css` を公開する変数の 1 行ずつの一覧にした。** `base/page.css` の公開する変数（版面・書体・柱とノンブルの 20 個）、`parts/simple-header.css` の `--book-color-heading`、`parts/heading.css` の見出しの印の既定値を移した。一覧に定義を置かない 4 種類（前書きと付録の色・会話の色・扉絵と節絵の画像・アバターの大きさ）は注釈で置き場を示した（§5.2）。`--color-shadow` を消した。
- **`targets/kindle-tokens.css`** を `--book-*` で書いた。
- **読む向きの別名** `stylesheets/tokens-legacy.css`（tokens 層で `tokens.css` の後に読む。`EntryWriter::FOUNDATION`）。`:root` に 69 個、会話の 2 つは `.talk, .talk-item` にも置く（`css-layer-restructure-spec.md` §7.2）。
- **値を入れる向き。** `BookSettingsCss.render` が `custom.css` の `:root`・`html` の定義を読み、今の名前に値が入っていれば `--book-x: var(--old);` を `:root` の最後に書く。値が新しい名前を読んでいる定義は、循環するので書かない。
- **💡** `custom.css` が今の名前を使っていれば（注釈の中は数えない）、`vs build` と `vs preflight` が「vs upgrade で新しい名前に置き換えられます（--theme-accent → --book-color-accent、… ほか N 個）」と出す。置き換えそのものは S6-9 で作る。
- **テスト** `legacy_tokens_test.rb`（10 件）。r1 の雛形の CSS が定義した 72 個の名前（`test/vivlio_starter/fixtures/css/r1_variables.txt`）が、どれも (a) 今も定義されている、(b) 対応の表にある、(c) 消した変数の表にある、のどれかであること。同梱の CSS が今の名前を使わないこと。`tokens-legacy.css` が `alias_css` と同じ中身であること。名前の全体だけを置き換えること。settings 層の書き出しと 💡。既存のテストの期待値は、表の置き換えを当てて新しい名前にした（原稿の文やコマンドの名前など、変数と関係のない文字列に当たった 2 本は戻した）。

#### 仕様と違えたこと

1. **`base/page.css` の変数。** §5.1 の決め 8 は「`base/page.css` の 24 個は内部の変数なので名前を変えない」としていたが、24 個のうち 20 個は §5.2 が新しい名前を示す公開する変数で、完了の条件の 9 も `kindle-tokens.css` をこの名前で書くことを前提にしている。§5.2 に従って名前を変え、§5.1 を直した（2026-11-16 ユーザー確認）。内部の変数として残したのは `--page-width`・`--page-height`・`--align-max-width`・`--font-body` の 4 つ。
2. **`--font-body`。** §5.2 の対応に無く、奥付の「(Powered by Vivlio Starter)」の 1 行だけが読む、値の固定された変数だった（1.x の注釈は「`--font-main-text` の別名」だが、値は結び付いていなかった）。`--book-font-body` へまとめると、本文の書体を変えた本でその 1 行の書体が変わるので、S6-2 では内部の変数のまま残した。その 1 行を本文の書体で組み、`--font-body` を消すことは、S6-2 の完了の後に別のコミットで入れる（2026-11-16 ユーザー決定）。
3. **`--color-overlay`。** §5.2 の色の行に無かったが、`tokens.css` の色なので `--book-color-overlay` にし、§5.2 に足した。
4. **`tokens-legacy.css` を書き出しのファイルにしたこと。** §7.2 は「同じ表を読む」としているが、CSS は表を読めない。表から書き出したファイルを `stylesheets/` に置き、テストで表と突き合わせる形にした（`css-layer-restructure-spec.md` §7.2 に書いた）。

#### 確かめた結果

全部の比べ（`v2-migration-plan.md` §3.6）。B1（四つの出力先・Kindle の記録つき）・B2・B3・B4・単章（`bin/vs build 21`）・preflight を組んだ（`r2/check/s6-2/`）。

| 確かめ | 結果 |
| :--- | :--- |
| PDF の画素（r2 と） | B1 の `pdf` 284 ページ・`print_pdf` 282 ページ、B2 279 ページ、B3 450 ページ、B4 317 ページとも違い 0 |
| 完了の条件の 9（Kindle の中間生成物） | 36 件・26,405 要素で `computedstyle`・`style` とも差 0（r2 とも、§11.3 の確かめとも） |
| 平らな CSS（ビルドなしで、前の束に表の置き換えを当てて後の束と比べた） | 普通のプロパティの並びと、選択子ごとの変数の値が、22 枚（11 種類 × EPUB・Kindle）で一致。違いは、`--book-color-heading` が `tokens.css` へ移って本文以外の 7 種類のページでも定義されるようになった 14 件だけ（そのページに読む規則は無い）。`book-settings.css` は置き換えを当てると同じ |
| 計算値（`css_computed_diff.rb`。前は 5da780e3） | B1 の 78 文書・234 組、B4 の 56 文書・168 組とも違い 0 |
| EPUB の HTML | 前の小段階と比べ、XHTML の差は Techbook が `<head>` に入れる `<style>` の変数の名前だけ（前の側の `<style>` の中に置き換えを当てると、画像の名前を除いて一致）。画像の中身は同じ。EPUBCheck は B1 の 2 本・B4 とも致命・エラー・警告 0 |
| 完了の条件の 5 | B4 の写しで、1.x の名前の `custom.css`（`--theme-accent`・`--color-link`・`--color-column-bg` に値を入れ、`var(--color-mark)` を読む規則を 1 つ）と、新しい名前で同じことを書いた `custom.css` を組み、317 ページとも画素が一致した。素の B4 とは 284 ページで違う（変更が効いている）。1.x の名前の写しでだけ 💡 が 1 回出た |
| 単章・preflight | どちらも終了コード 0。🟡・🔴 は 0。B4 の 🟡 7 件は §11.3 の確かめと同じ（雛形の差の 💡 の件数だけ違う。`lib/project_scaffold/` を同期していないため） |
| テスト | `rake test` 4,429 件が通った（スキップ 1 は前からのもの）。`bundle exec rubocop` は違反 0 |

- 計算値の比べには、§11.3 の確かめの写しの HTML を使った。今回の B1 の写しで preflight を走らせたので、写しの `.cache/vs/build/` の HTML が消えたためである（preflight は別の写しで走らせるべきだった）。二つの HTML の違いは Techbook の `<style>` の中の名前だけで、上の EPUB の比べで確かめた。前の側の `book-settings.css` は §11.3 の写しのもの（前のコードで生成）、後の側は今回の写しのものを `--after-settings` で渡した。
- 雛形の同期（`ruby scripts/copy_to_scaffold.rb`）はしていない。

### 11.5 奥付のクレジットの行を本文の書体で組む（2026-11-16・S6-2 の後）

S6-2 の完了のコミット（8afd8000）の後に入れた、見た目を変える変更（`v2-migration-plan.md` §4.1 の手順）。

- 奥付の「(Powered by Vivlio Starter)」の行（`pages/colophon.css` の `.powered-by`）は、値の固定された内部の変数 `--font-body`（Noto Serif JP）を読んでいた。奥付のほかの行は本文の書体（`--book-font-body`）なので、本文の書体を変えた本では、この 1 行だけが別の書体だった。`--book-font-body` を読むようにし、`--font-body` を `base/page.css` と `targets/kindle-tokens.css` から消した（2026-11-16 ユーザー決定。この 1 行だけのための変数は置かない）。
- `--font-body` は `LegacyTokens::REMOVED` に入れ、別名を置かない。別名（`--book-font-body`）にすると、1.x で `--font-body` に値を入れていた `custom.css` が、クレジットの 1 行でなく本文全体の書体を変えてしまうためである。

| 確かめ | 結果 |
| :--- | :--- |
| B4（本文が Shippori Mincho B1） | PDF は S6-2 の確かめ（`r2/check/s6-2/`）と比べ、違うのは奥付の p316 の 181 画素だけ。クレジットの行が、上の著作権の行と同じ書体になった（`r2/check/s6-2-font-body/colophon-credit-before-after.png`）。EPUB は CSS 7 枚の `--font-body` の定義の行と、`colophon.css` の `.powered-by` の 1 行だけ。EPUBCheck は 0 件 |
| B1（本文が Noto Serif JP） | PDF は r2 と 284 ページとも一致（書体の並びが前と同じ）。EPUB は CSS 8 枚の同じ行だけ。EPUBCheck は 0 件 |
| Kindle | 組んでいない。前は `kindle-tokens.css` の `--font-body: serif`、後は同じファイルの `--book-font-body: serif` を読むので、値は同じ `serif` になる |
| テスト | `rake test` 4,429 件が通った |

### 11.6 S6-3 テーマを読む仕組み（2026-11-16）

#### 作ったもの

- **`theme.name`**（`ConfigKeys::KEYS`。既定 `standard`）。雛形と本書の `book.yml` の `theme:` 節の先頭に `name: standard` を書いた（§9 の S6 の決め 9）。`BookProfile::PROFILES` には足していない（`v2-architecture-spec.md` §2.2。`book_profile_test.rb` に「`PROFILES` の `theme.name` は同梱のテーマにある」を足した）。
- **`Theme::Manifest`**（`lib/vivlio_starter/cli/theme/manifest.rb`）: `theme.yml` を読んだ結果の `Data` と、読み込みと検査の `Manifest.load`。`name:` がディレクトリの名前と同じこと・`contract:` が整数であること・`styles:` がテーマの中にある CSS であること・`tokens:` が `--book-` を除いた名前で、`:root { … }` に書き出せる値であること・`supports:` の軸と値を検査し、外れたら `Theme::Error`（🔴）。知らないキーは読み飛ばして 🟡 にする。`features:`・`options:`・`kindle_tokens:` は形（並び・表）だけを見て持つ（中身は S6-7・S6-10）。
- **`Theme::Contract`**（`theme/contract.rb`）: `CURRENT = 1`・`SUPPORTED = [1]`。`contract:` が `SUPPORTED` に無ければ、新しい版なら「`vs upgrade` で vs を新しく」、古い版なら「契約の版 1 に対応した版のテーマに入れ替え」を示す。`requires_vs:` は `Gem::Requirement` で突き合わせる。
- **`Theme`**（`lib/vivlio_starter/cli/theme.rb`）: `Theme.resolve(name, root:)` が本の `themes/<名前>/` を読み、`extends:` を 1 段だけ読む（土台がさらに `extends:` を持てば 🔴）。結果の `Theme::Resolved` が、土台 → 自分の順の `styles`・`target_files(kind, target)`、自分の値が勝つ `tokens`、`supports` を返す。`Theme.selected` は設定で選ばれたテーマで、読めなければ nil（入口の CSS はテーマ無しで書く。誤りは入口の検査が示す）。設定と作業ディレクトリが同じ間は読み直さない。`Theme.available` は、本の `themes/` と同梱のテーマ（`lib/project_scaffold/themes/`）から読めるものを集める（対応するテーマの名前を示すため）。
- **`EntryWriter`**: `tokens:` を `.cache/vs/theme-tokens.css` に `:root { --book-…: …; }` として書き出し、tokens 層の最後（`tokens-legacy.css` の後）で読む。`styles:` を theme 層に、テーマの出力先の CSS を target 層の vs の `targets/` の後に入れる（`css-layer-restructure-spec.md` §5 の 1・3・4・5。2 の `kindle_tokens:` は S6-10）。`render` は `theme:` を受け取れる（既定は `Theme.selected`）。
- **`Guards::TraitCombinationCheck`**: テーマの行を足した。テーマが本に無い・`theme.yml` の誤り・契約の版と `requires_vs:` が合わない → 🔴。読めたら、知らないキーの 🟡 と、`supports:` に無い組方向・レイアウト・出力先の 🔴。対応するテーマは本の `themes/` と同梱のテーマから探し、無ければ「縦書きに対応するテーマは、まだ同梱されていません」と示す（`v2-architecture-spec.md` §2.5）。
- **`themes/standard/theme.yml`**（`name`・`title`・`version`・`contract`・`supports` だけ）。
- **複製の対象**: `copy_to_scaffold.rb` の `DIRS` に `themes` を足した。`build_copy.rb` は S0 から `themes` を写している。直接ビルド（`vs build x.md`）は、作業場所に `themes/` の参照を張る（プロジェクトの中ならプロジェクトの、外なら同梱のもの。`stylesheets/` と同じ決まり）。
- **テスト**: `theme_test.rb`（8 件。`extends:` の読む順・`supports:` の補い・1 段だけ・`theme.yml` の誤り・契約の版と `requires_vs:`・`Theme.selected`）、`trait_combination_check_test.rb`（テーマの 🔴 の 3 通りと、出力先・知らないキー・対応するテーマの名前・縦書きに対応する材料のテーマ）、`entry_writer_test.rb`（3 件。層ごとの読む順・`theme-tokens.css`・中身の無いテーマはテーマ無しの入口と同じ字面・平らにした CSS の中の位置）、`book_profile_test.rb`（1 件）。

#### 仕様と違えたこと・仕様に無かったので決めたこと

1. **テーマが無い・契約の版が合わない 🔴 も `TraitCombinationCheck` に置いた。** 小段階の表は `supports:` の行だけを挙げているが、`supports:` を見るにはテーマを読む必要があり、読めなかった理由を同じ検査で示すのが自然である（`vs build` と `vs preflight` で同じものが出る）。
2. **`supports:` の書いていない軸。** §3.1 は `targets` の省略（四つ全部）だけを決めている。書いていない軸は `extends:` の先から補い、土台も書いていなければ、組方向は `horizontal`、レイアウトは `reflowable`、出力先は四つ全部とした。配色のテーマが土台の対応をそのまま引き継げるようにするためである。
3. **出力先も `supports:` で検査する。** `v2-architecture-spec.md` §2.5 の表は組方向とレイアウトだけを挙げているが、§3.1 の `supports.targets` と S7 の完了の条件（`targets` に `kindle` があると §2.5 の検査が 🔴）に合わせた。🔴 には「`output.targets` から kindle を外すと組めます」を添える。
4. **固定レイアウトの本では、レイアウトの `supports:` を見ない。** 固定レイアウトは S9 まで別の 🔴 で止めており、二重に止めない（索引の 🟡 を重ねないのと同じ）。S9 で固定レイアウトの 🔴 を外すと、`supports.layout` の検査が働く。
5. **テーマが見つからないときの案内。** §7.1 は `vs theme:add` の書き方を示すとしているが、`vs theme:add` は S6-8 で作る。S6-3 では「本にあるテーマ: standard（config/book.yml の theme.name に書きます）」を示す。S6-8 で、同梱のテーマにある名前なら `vs theme:add <名前>` を示す形に直す。
6. **`theme-tokens.css` は、`tokens:` が空なら書かず、入口でも読まない。** 中身の無いテーマの入口を、テーマの無い入口と同じ字面にするためである（完了の条件「入口の CSS がバイト単位で同じ」）。
7. **雛形に `themes/` だけを写した。** `vs new` で作った本は、`themes/standard/` が無いと入口の検査で止まる（記法網羅のテスト `test:notation` が `vs new` の本を組むので落ちた）。雛形の全体の同期（`copy_to_scaffold.rb`）は S6 の間はしていないので、`themes/` のディレクトリだけを写した。`book.yml` の `name: standard` の 1 行も、S5-1 と同じく雛形の `book.yml` に直接書いた（`config_keys_test.rb` が雛形の `book.yml` を読むため）。
8. **`scaffold.lock` のコードは変えていない。** 雛形にあるファイルはどれも lock に載るので、同梱のテーマは何もしなくても lock に載る。著者が置いたテーマは雛形に無いので lock に載らず、`vs upgrade` の対象にならない（§7.3）。`scaffold_lock.rb` の説明にこのことを書いた。`vs upgrade` の扱いそのものは S6-9 で作る。
9. **`build_command_test.rb` の最小の本に `themes/standard/` を置いた。** 入口の検査を通るための最小の本の構成に、テーマが加わったためである。
10. **テーマの CSS の中の `url()`。** EPUB のパッケージに写るのは `stylesheets/` だけで、テーマの `images/` はまだ写らない。`standard` に CSS が入るのは S6-4・S6-5 で、画像の置き場を移すのは S6-5 なので、そこで扱う。

#### 確かめた結果

B1（`pdf`・`epub`・`kindle`、`--no-clean`）を、前の版（eafb7856 の worktree の `bin/vs`）と後の版で、同じ素材から組んで比べた（`r2/check/s6-3/`。写しは `r2/runs/s6-3-before-b1/`・`s6-3-b1/`）。

| 確かめ | 結果 |
| :--- | :--- |
| 入口の CSS（`.cache/vs/entry-*.css`） | 11 枚ともバイト単位で同じ。`theme-tokens.css` は前後とも無い。ビルドを通さず、11 種類 × PDF・EPUB・Kindle の `EntryWriter.render` を前後で書き出しても同じ |
| 契約 HTML（`.cache/vs/build/html/`） | 39 件ともバイト単位で同じ |
| クリーン EPUB | CSS 8 枚はバイト単位で同じ。XHTML の差は画像の名前だけ（画像 25 件の中身は同じで、名前を中身のハッシュにそろえると XHTML 38 件が一致）。OPF の差は、画像の名前と並びと `dcterms:modified` だけ |
| Kindle 用 EPUB | 画像 64 件の中身は同じで、名前をそろえると XHTML と CSS が一致。OPF はクリーン EPUB と同じ種類の差だけ |
| EPUBCheck | クリーン EPUB・Kindle 用 EPUB とも致命・エラー・警告 0 |
| 完了の条件の 6 | 写しの本で `bin/vs build` と `bin/vs preflight` を走らせ、3 通りとも 🔴 で止まった（終了コード 1）。`theme.name: standart` →「config/book.yml の theme.name のテーマ standart が、本の themes/ にありません」「本にあるテーマ: standard（config/book.yml の theme.name に書きます）」。`contract: 2` のテーマ →「テーマ future の契約の版（contract: 2）に、この vs は対応していません」「この vs が読める契約の版: 1」「vs upgrade で vs を新しくしてください」。`page.writing_mode: vertical` →「テーマ standard は縦書き（page.writing_mode: vertical）に対応していません」「縦書きに対応するテーマは、まだ同梱されていません」。build と preflight で同じ文面 |
| 単章・preflight | `bin/vs build 21` と `bin/vs preflight`（別の写し）とも終了コード 0。🔴・🟡 は 0 |
| テスト | `rake test` 4,447 件が通った（S6-2 の後の 4,429 件に、足した 18 件。スキップ 1 は前からのもの）。`bundle exec rubocop` は違反 0 |

- PDF は組んだが、画素では比べていない。PDF が読むのは入口の CSS と契約 HTML だけで、どちらもバイト単位で同じだからである（小段階の表の確かめにも無い）。
- Kindle の中間生成物も比べていない。Kindle 用 EPUB の中身が、画像の名前を除いて同じだからである。
- 雛形の同期（`ruby scripts/copy_to_scaffold.rb`）はしていない（上の 7 の `themes/` と `book.yml` の 1 行だけ）。

### 11.7 S6-4 見出しの 2 枚を theme 層へ（2026-11-16）

#### 作ったもの

- `EntryWriter::STANDARD_HEADERS`: `parts/simple-header.css`・`parts/image-header.css` を `BODY_PARTS` から外し、11 種類すべての入口の theme 層で読む（置き場は変えない）。theme 層の中では、vs の 2 枚の後にテーマの `styles:` が続く。
- テスト: `entry_writer_test.rb` に「2 枚はどの種類でも theme 層にだけ入る」を足した。`css_layer_test.rb` の `ALLOWED_INVERSIONS` に 4 行を足した（見出しと、囲みや並べ方の最初・最後の子／コードの図の中の要素／節見出しの子と、コードの図・表の題の段落／目次のページの規則）。どの組も同じ要素には当たらない。

#### 仕様に無かったので決めたこと

1. **静的な判定で挙がった 25 組は、選択子を直さずに許可の表へ入れた。** 決め 1 は「差が出たら選択子の形をそろえて直す」としているが、出たのは静的な判定の組だけで、要素ごとの判定・計算値・画素の差は 0 だった。前は部品・ページの規則が勝っていて、今は見出しが勝つ組も洗い出した（同じクラスを含むか、どちらもクラスを持たない組 32 組）。中身は許可の表の 4 種類と同じで、心配していた `parts/heading.css` との入れ替わりは 0 組だった。
2. **本文以外の種類の EPUB の CSS が大きくなる。** 奥付・用語集・索引・部扉の CSS に 2 枚の規則が入る（クリーン EPUB で 1 枚あたり 309 行、Kindle 用で 219 行）。その body には vs-header-* が付かないので、計算値は変わらない。

#### 確かめた結果

B1（`pdf`・`epub`・`kindle`、Kindle の記録つき、`--log=debug`）・B2・B4（`epub`・`kindle`、`--log=debug`）を組んだ（`r2/check/s6-4/`）。

| 確かめ | 結果 |
| :--- | :--- |
| PDF の画素（r2 と） | B1 284 ページ・B2 279 ページとも違い 0 |
| 計算値（`css_computed_diff.rb`。前は 6e5a65bb） | B1 の 117 文書・312 組、B4 の 56 文書・112 組とも違い 0 |
| `InversionCheck` の要素ごとの判定 | B1 の EPUB・Kindle 用 EPUB は 8 種類、B4 は 7 種類とも 0 組 |
| Kindle | 中間生成物 36 件・26,405 要素で `computedstyle`・`style` とも差 0。Enhanced Typesetting: Supported・Success・エラー 0・品質の問題 0 |
| EPUB | 画像の名前を中身のハッシュにそろえると、XHTML はすべて一致（S6-3 の B1 と）。違いは CSS 8 枚だけ。本文のページの 4 枚は、層の名前の注釈 2 行のほかは並びだけの違い。EPUBCheck は B1 の 2 本・B4 の 2 本とも致命・エラー・警告 0 |
| テスト | `rake test` 4,448 件が通った（スキップ 1 は前からのもの）。変えたファイルに `rubocop` を掛け、違反 0 |

- B4 の PDF・単章のビルド・preflight は、小段階の表の確かめに無いので組んでいない。雛形の同期もしていない。

### 11.8 S6-5 `standard` へファイルと画像を移す（2026-11-17）

#### 作ったもの

- `themes/standard/`: `simple-header.css`・`image-header.css`（`stylesheets/parts/` から）と `images/` の 12 枚（`stylesheets/images/bundled/` から）。`theme.yml` の `styles:` に今の順で 2 枚を並べた。`EntryWriter::STANDARD_HEADERS` は消し、2 枚はテーマの `styles:` として theme 層に入る（入口の行は S6-4 と同じ位置）。
- `ThemeImageResolver`: 画像の指定を、(1) 本の直下からのパス、(2) `stylesheets/images/` の中の名前、(3) 選ばれたテーマの `images/` の中の名前（テーマ → 土台の順）の順に探す（`v2-migration-plan.md` §5.3 の 4）。
- 生成したバリアントの置き場（`cache_stem`）: `stylesheets/images/` の画像は今と同じくキャッシュの直下、ほかは本のルートからのパスのまま（`.cache/vs/theme-images/themes/standard/images/sakura_portrait.webp`）。`ImageGenerator` は見つけた元画像のパスをそのまま受ける（`resolve_image_reference` を消した）。
- CSS へ書く形: テーマの画像と本の直下の画像は `../<本のルートからのパス>`（`stylesheets/` 基準）で返し、`BookSettingsCss.rebase_relative` が `../../themes/…` に畳む。
- EPUB: 選ばれたテーマの `images/` を、本のルートと同じ階層でパッケージへ運ぶ（`Epub::Workspace.localize_theme_images!`。Kindle は WebP を除く）。参照されない画像は、今の `stylesheets/` の画像と同じく回収で外れる。
- `Guards::ImageFilenameCheck` が `themes/` の画像の名前も見る（`stylesheets/images/bundled/` を見ていた分）。
- テスト: 置き場の順・`bundled/` の読み方・`cache_stem`・テーマ → 土台の順・EPUB への同梱・`themes/` の画像の名前の検査を足した。2 枚と画像の置き場を読むテスト（`entry_writer_test.rb`・`css_layer_test.rb`・`book_settings_css_test.rb`・`theme_test.rb` など）を新しい置き場に合わせた。

#### 仕様に無かったので決めたこと

1. **生成したバリアントの置き場は、テーマごとに分ける。** `theme-images/bundled/` のままにすると、テーマを替えたときに、前のテーマの同じ名前の画像から作ったバリアントを使う（新しいテーマの元画像のほうが古ければ、作り直さない）。分けた結果、EPUB の中の `theme-images/` のパスと、合成した見出しの画像の名前（鍵に元画像のパスが入る）が変わる。仕様の「`epub_diff.rb` で違い 0 件」は、この名前を中身のハッシュにそろえて確かめた（下の表）。
2. **1.x の `bundled/<名前>` は、テーマの画像の名前として読む。** 42 章が「その名前のまま同梱画像を使うときは `image: bundled/sakura` と書く」と説明している書き方で、置き場が無くなっても同じ画像を指す。
3. **置き場の 1（本の直下からのパス）は、「/」を含み、本の中にその画像があるときだけ使う。** 名前だけの指定（`sakura`）は 2・3 で探す。`..` を含むパスと絶対パスは使わない（パッケージの外を指すため）。
4. **著者への文面と原稿は変えない。** `ThemeValidator` の「バンドル画像名（sakura・himawari など）」の文面は 42 章が出力例として載せており、42 章・51 章は `stylesheets/images/bundled/` を置き場として説明している。変えると本書の PDF が変わるので、§9 の S6 の決め 8 と同じく S11 で書き直す。今の文面は誤りにはならない（名前は同じ画像を指す）。
5. **雛形は `themes/` だけを写した**（S6-3 と同じ。`vs new` の本に見出しと扉絵が無くなるため）。雛形の `stylesheets/` には前の 2 枚と `images/bundled/` が残るが、入口は読まず、名前で探す置き場にも入らない。雛形の同期（`ruby scripts/copy_to_scaffold.rb`）で消える。
6. **EPUB 枝の Vivliostyle の作業ディレクトリを、出力先ごとに組む前に空にする（`EpubFlow#build_target`）。** 最初の確かめで、Kindle 用 EPUB にテーマの WebP 12 枚が入った。Vivliostyle は組むたびに作業ディレクトリを消すが、`<workspaceDir>/themes` だけは自分のテーマの置き場（`themesDir`）として残す。パッケージに運ぶ `themes/standard/images/` がそこに重なり、先に組んだクリーン EPUB の分が Kindle 用 EPUB に入った（`build-pipeline-pitfalls-notes.md` §6）。前は同じ画像が `stylesheets/` の下にあり、毎回消えていた。

#### 確かめた結果

B1（`pdf`・`epub`・`kindle`、`--no-clean`・`--log=debug`）と B2（`pdf`・`theme.style: simple`）を組んだ（`r2/check/s6-5/`・台本 `r2/runs/s6-5.sh`。B1 は 6 の修正の後に組み直した）。ビルドの 🔴・🟡 は 0。日付が変わってから組んだので、原稿の `@today`（「2026 年 11 月 16 日 更新」→「17 日」）の差が出る。

| 確かめ | 結果 |
| :--- | :--- |
| 入口の CSS（S6-4 の B1 と） | 11 枚とも、違いは 2 枚の `@import` の 2 行のパスだけ（`../../stylesheets/parts/` → `../../themes/standard/`） |
| PDF の画素（r2 と） | B1 284 ページは p83、B2 279 ページは p80 の 1 ページだけが違う。どちらも `@today` の日付の行（B1 は `pdftotext` で日付の 1 行だけが違うことを確かめた） |
| EPUB（S6-4 の B1 と） | 画像はすべて中身のハッシュで一致（クリーン 292 件・Kindle 用 217 件）。テキストは、画像の名前を中身のハッシュに、置き場の名前（`theme-images/themes/standard/images/`・`themes/standard/images/`・平らな CSS の出どころの注釈 2 行）を前の名前に、日付を前の日にそろえると、XHTML・CSS はすべて一致。OPF の違いは、パスから作られる項目の id だけ（クリーンは移した 14 枚、Kindle 用は前から写しごとに変わる `_epub_assets/` の名前の分） |
| Kindle 用 EPUB の WebP | 0 枚（6 の修正の前は 12 枚）。KPF ができた |
| EPUBCheck | クリーン・Kindle 用とも致命・エラー・警告 0 |
| テスト | `rake test` 4,454 件が通った（スキップ 1 は前からのもの）。`rake test:layout` 7 件が通った。変えたファイルに `rubocop` を掛け、違反 0 |

- クリーン EPUB には、前と同じくテーマの 12 枚（花）が入る。42 章が本文に `images/42-frontispiece/ajisai.webp` などを載せており、参照の切れた画像の回収はファイルの名前で見るので、同じ名前のテーマの画像も残る（前は `stylesheets/images/bundled/` に入っていた）。
- Kindle の中間生成物（`kindle_record_diff.rb`）は比べていない。Kindle 用 EPUB の中身が、名前を除いて同じだからである（小段階の表のとおり）。

### 11.9 S6-6 出力先の規則を `standard` へ（2026-11-17）

#### 作ったもの

- `themes/standard/epub.css`: `stylesheets/targets/epub.css` の `body.vs-epub:not(.vs-header-image) .section-lead`（1 規則）。
- `themes/standard/kindle.css`: `stylesheets/targets/kindle.css` の `body.vs-header-simple.vs-kindle` の 5 規則（`h1::before`・`h1::after`・`h1`・`h1 .chapter-number`・`h2`・`h2 .section-number`）。
- どちらも選択子と宣言を変えずに移した。読み込みは S6-3 の仕組み（`Theme::Manifest#target_files`）のままで、`theme.yml` は変えていない。`targets/epub.css`・`kindle.css` の冒頭に、`vs-header-*` の規則の置き場を書いた。
- テスト: `entry_writer_test.rb` に「standard の 2 枚は、どの種類でも target 層の vs の `targets/` の後に入る」を足した。vs の `targets/` の読む順を見るテストはテーマ無しで書く形にした。`css_layer_test.rb` の「出力先の規則は `targets/` に置く」に、テーマの出力先の CSS（`themes/<名前>/epub.css`・`kindle-<種類>.css` など）を足した。`theme_test.rb` の standard の出力先の CSS の期待を改めた。`literal_resolver_test.rb` の仮の本に `themes/` を置いた（置かないと、移した Kindle の見出しの規則が束に入らない）。
- `scripts/css_computed_diff.rb`: 前の版の取り出しに `themes/` を足し（その版にあるときだけ）、作業場所に `themes/` の参照を張る。S6-5 までは、テーマの CSS が前後とも比べに入っていなかった（S6-4 の比べは、2 枚がまだ `stylesheets/` にあったので影響しない）。

#### 仕様に無かったので決めたこと

1. **小段階の表の「3 か所と 8 か所」は、`grep` で数えた行の数（注釈の行を含む）で、規則は 1 つと 5 つだった。** 移した規則は上のとおりで、選択子が `vs-header-*` を含む規則はほかに無い。
2. **移した規則と、詳細度が同じ規則との前後。** テーマの出力先の CSS は `targets/kindle-preface.css` の後に読まれ、`body.preface.vs-kindle h2` と `body.vs-header-simple.vs-kindle h2` は詳細度が同じ (0,2,2) である。前書き・後書きの body には `vs-header-*` が付かない（`BodyClassInjector` は章と付録にだけ付ける）ので、同じ要素で取り合わない。静的な判定（`css_layer_test.rb`）でも新しい組は挙がらず、許可の表は変えていない。
3. **雛形は `themes/` だけを写した**（S6-3・S6-5 と同じ）。雛形の `stylesheets/targets/` には移す前の規則が残り、`vs new` の本では同じ規則が 2 回入る（並びと詳細度が同じなので、結果は変わらない）。雛形の同期（`ruby scripts/copy_to_scaffold.rb`）で消える。

#### 確かめた結果

B1（`pdf`・`epub`・`kindle`、`--no-clean`・Kindle の記録つき・`--log=debug`）を組んだ（`r2/check/s6-6/`・台本 `r2/runs/s6-6.sh`）。ビルドの 🔴・🟡 は 0。S6-5 と同じ日に組んだので、`@today` の差は無い。

| 確かめ | 結果 |
| :--- | :--- |
| 入口の CSS（S6-5 の B1 と） | 11 枚ともバイト単位で同じ（PDF は target 層を読まないので、PDF の画素は比べていない） |
| 計算値（`css_computed_diff.rb`。前は 0a869716。HTML は S6-5 の B1 の写しのもの） | EPUB・Kindle の 78 文書・156 組で違い 0。`themes/standard/kindle.css` を消した写しを後の側に渡すと、付録の見出しに違いが出ることも確かめた（道具がテーマの CSS を読んでいることの確かめ） |
| Kindle の中間生成物（`kindle_record_diff.rb`。S6-4 の記録と） | 36 件・26,405 要素で `computedstyle`・`style` とも差 0。Enhanced Typesetting: Supported・Success・エラー 0・品質の問題 0 |
| `InversionCheck` の要素ごとの判定 | 8 種類 × EPUB・Kindle 用 EPUB とも 0 組 |
| EPUB（S6-5 の B1 と） | 画像の名前を中身のハッシュにそろえると（PNG に埋め込まれた生成日時を除く）、画像はすべて一致し、XHTML もすべて一致。OPF の違いは、写しごとに変わる `_epub_assets/` の名前と `dcterms:modified` だけ。CSS の違いは 8 枚: クリーン EPUB の本文のページは出どころの注釈 1 行だけ（移した規則は `targets/epub.css` の最後にあったので、位置が変わらない）、本文以外の種類には移した規則が入る（その body には `vs-header-*` が付かない）、Kindle 用は移した規則が `targets/` の後ろへ移る |
| EPUBCheck | クリーン・Kindle 用とも致命・エラー・警告 0 |
| テスト | `rake test` 4,455 件が通った（スキップ 1 は前からのもの）。変えたファイルに `rubocop` を掛け、違反 0 |

- 契約 HTML の showcase の SVG 2 枚が S6-5 の写しとバイト単位で違うが、埋め込んだ PNG の生成日時（`date:create`）だけで、大きさは同じ。
- 1 回目の `rake test` で `epub_kindle_layout_test.rb` の「targets/ の Kindle の規則が全部解ける」が落ちた。作業ツリーの `.cache/vs/book-settings.css` が 1.x の `vs` の書いたもの（`--appendix-accent-color`・`!important` つきの Kindle の規則）になっていたためで、0a869716 でも同じく落ちる。v2 のコードで書き直すと通る。このテストは作業ツリーの `.cache/vs/book-settings.css` を読むので、1.x の `vs` を作業ツリーで走らせた後は落ちる。

### 11.10 S6-7 の前段: 章リードの大きさを公開する変数へ（2026-11-17）

§3.4 の決め 3（`lead_size` は公開する変数 `--book-chapter-lead-size` で渡す）は `book-settings.css` の字面を変えるので、S6-7 の本体（`book-settings.css` がバイト単位で同じ）の前に、この小段階として入れた。

#### 作ったもの

- `stylesheets/tokens.css`: `--book-chapter-lead-size: 120%`・`--book-frontispiece-lead-size: var(--book-chapter-lead-size)`・`--book-frontispiece-image: none`・`--book-ornament-image: none`（扉絵と節絵の画像の既定。§3.4 の「機能を使わないテーマのために」）。
- `parts/heading.css` の `.chapter-lead` の `font-size: larger` を `var(--book-chapter-lead-size)` に、`themes/standard/image-header.css` の `body.vs-header-image .chapter-lead` に `font-size: var(--book-frontispiece-lead-size)` を足した。
- `BookSettingsCss`: 二つの変数を百分率で書き出す（`format_percent`）。章リードの大きさのリテラルの規則（`chapter_lead_size_rules`）を消した。`:root` の宣言を、S6-7 の本体の書き出しと同じ順（`options:` の `token:` のあるもの → 扉絵 → 節絵）に並べ替えた。前書きの色を付録の色の前にした。
- テスト: `book_settings_css_test.rb` を変数で渡す形に、`css_layer_test.rb` の Kindle の許可の表から扉絵と節絵の画像の 2 行を消した（`tokens.css` の既定 `none` で解けるようになった）。

#### 仕様と違えたこと

1. **倍率は `em` でなく百分率で書き出す（§3.4 の決め 3 を直した）。** 最初は `1.2em` と書き出し、B1 で章扉と付録の扉の 9 ページ（p22・p101 など。日付の p83 を除く）、B2 で 21 ページの章リードの 1 行で、字の位置がわずかにずれた（1 ページに 9〜2,230 画素）。1 章だけのビルド（24 章と 93 章）で `.chapter-lead` の `font-size` を 4 通りに書いて比べると、`larger`・`var()` の中の `larger`・`120%` は画素が同じで、`1.2em` だけが違った。`em` の長さは Vivliostyle が px に直すときに丸める（`vivliostyle-css-pitfalls-notes.md` §2.18 と同じ根）。倍率の型 `ratio` を §3.3 に足し、CSS には百分率で書く。最初の確かめの出力は `r2/check/s6-7a-em/` に残した。
2. **前書きの章リードの大きさ。** 前は `theme.lead_size` を 1.2 以外にすると、`body .chapter-lead`（詳細度 0,1,1）が `parts/preface.css` の `.chapter-lead { font-size: inherit }` に勝ち、前書きの章リードも大きくなっていた。今は変数を読む `parts/heading.css` の規則と `parts/preface.css` の規則が同じ詳細度で、後に読む前書きの規則が勝つので、前書きの章リードは本文と同じ字のままになる（`parts/preface.css` の注釈どおり）。本書と B4 は `lead_size: 1.2` なので、出力は変わらない。

#### 確かめた結果

B1（`pdf`・`epub`・`kindle`、Kindle の記録つき・`--log=debug`）・B2（`pdf`・`theme.style: simple`）・B4（`pdf`・`epub`）を組んだ（`r2/check/s6-7a/`・台本 `r2/runs/s6-7a.sh`。前段のコミットを置いた別の worktree から組んだ）。ビルドの 🔴 は 0、🟡 は B4 の 7 件だけ（廃止キー 3 行・画像の余白 3 件・索引候補の抽出。§11.4 と同じ）。

| 確かめ | 結果 |
| :--- | :--- |
| PDF の画素（r2 と） | B1 284 ページは p83、B2 279 ページは p80 の 1 ページだけが違う（日付の行。`pdftotext` で「16 日」→「17 日」だけ）。B4 317 ページは p316（§11.5 の既知の差）だけ |
| 計算値（`css_computed_diff.rb`。前は 46186ddd と S6-6 の B1 の写しの HTML・`book-settings.css`、後は前段の B1 の `book-settings.css` を `--after-settings` で） | EPUB・Kindle の 78 文書・156 組で違い 0 |
| Kindle の中間生成物（`kindle_record_diff.rb`。S6-6 の記録と） | 36 件・26,405 要素で `computedstyle`・`style` とも差 0。Enhanced Typesetting: Supported・Success・エラー 0・品質の問題 0 |
| `InversionCheck` の要素ごとの判定 | 8 種類 × EPUB・Kindle 用 EPUB とも 0 組 |
| EPUBCheck | B1 のクリーン・Kindle 用、B4 とも致命・エラー・警告 0 |
| テスト | `rake test` 4,455 件が通った（スキップ 1 は前からのもの）。変えたファイルに `rubocop` を掛け、違反 0 |

### 11.11 S6-7 オプションと機能の宣言（2026-11-17）

#### 作ったもの

- **`themes/standard/theme.yml`**: `features: [frontispiece, ornament]` と `options:`（`color`・`preface_color`・`appendix_color`・`style`・`lead_size`・`markers.h3`・`markers.h4`）。`style` は `body_class:`（章は値で `vs-header-image`・`vs-header-simple`、付録は値に依らず `vs-header-simple`）と `features:`（`simple` は扉絵・節絵を使わない）を持つ。
- **`Theme::Option`・`Theme::OptionParser`**（`theme/option.rb`）: `options:` の 1 件の宣言（`type:`・`default:`・`default_from:`・`token:`・`body_class:`・`values:`・`min:`・`max:`・`unit:`・`features:`）。`type:` を持たない表は入れ子の節。誤りは 🔴（`Theme::Error`）。
- **`Theme::Features`**（`theme/features.rb`・`features/frontispiece.rb`・`ornament.rb`）: 機能の一覧と、機能ごとのオプションの宣言（`OPTIONS`）・`book-settings.css` に書く変数（`declarations`）・`@page` の規則（`page_rule`。扉絵の位置）。`Features.active?` は、テーマの `features:` と、`features:` を持つ enum のオプションの今の値から決める。
- **`Theme::Values`**（`theme/values.rb`）: 値の決まり方（書いた値 → `default_from:` の先 → `default:`）と、型ごとの読み方・CSS への書き方（色は 12 色の `var()` か小文字の HEX、倍率は百分率、文字列は引用符つき）。
- **`Theme::Resolved`**: `options`（土台 → 自分）・`features`・`feature_options`・`all_options`・`config_specs`（`ConfigKeys::Spec` の形。テーマの `tokens:` に `token:` と同じ名前があればそれを既定値に。§3.2 の決め 4）・`active_features`・`body_classes`・`token_value`。
- **`Theme.for_settings`・`Theme.declared`・`Theme.token_value`**: 設定の既定値と宣言を読むときのテーマ。本の `themes/` に読めるものが無ければ同梱のテーマの宣言を読む（設定の読み込みを止めない。誤りは入口の検査が 🔴 で示す）。`token_value` は公開する変数の名前で値を引く窓口（§3.4 の決め 1）。
- **`ConfigKeys`**: `theme.*`（`name` を除く 15 個）を `KEYS` から外した。`keys_with(theme_specs)`（`KEYS` に宣言を重ねる入口）と `default_schema(theme_specs)`。
- **`Common.load_config`**: 生の YAML から `theme.name` を先に取り出し、テーマの宣言を既定値に重ねる（`v2-architecture-spec.md` §5.3 の 3）。`Common.theme_specs` が今の宣言を持ち、`default_config_schema`・`config_guide.rb`（`vs config`）・直接ビルドがこれを読む。
- **`BookSettingsCss`**: `options:` の `token:` から変数を書き、機能の変数と `@page` の規則は機能のモジュールに書かせる。オプションの名前（`theme.color` など）と `--book-frontispiece-*`・`--book-ornament-*` の名前は、このファイルから無くなった。
- **`BodyClassInjector`**: `body_class:` の宣言から付ける。**`HtmlContract`**: `theme_option` の分類を `GROUPS` から外し、選ばれたテーマの `body_class:` から引く（`lookup`・`theme_option_classes`。`LiteralResolver` のページの種類のクラスと `scripts/html_contract_doc.rb` も同じ）。
- **`ThemeValidator`**: 宣言の `type:` から検査する（色・数・倍率・enum）。画像の有無は、機能が有効なときに見る（§3.4）。
- **`BuildPlan.features`** に `frontispiece`・`ornament`。`ImageOptimizer`・`InjectHeadingImages`・`ChapterLeadCheck` は `style` を読まず、これを読む。
- **公開する変数の窓口へ移した箇所**: `HeadingProcessor`・`Kindle::RestoreH3Markers`（`marker-h3`）、`Techbook::Processor`（`marker-h3`・`marker-h4`・`color-accent`）、`TalkAvatarGenerator`（`color-accent`）、`FrontmatterGenerator.parse_theme_settings`（`color-accent`・`chapter-lead-size`）。`ThemeColor.resolve` は `var(--book-accent-<名前>)` も読む。`ThemeColor::DEFAULT_NAME` と `BookSettingsCss::DEFAULT_LEAD_SIZE` は定数にした（テストが `theme.yml` と `tokens.css` と突き合わせる）。
- **`Guards::TraitCombinationCheck`**: `theme:` の、選ばれたテーマにも機能にも無いキーの 🟡（§3.3）。綴りの近いキーを `DidYouMean` で示し、同じ段に書けるキーを並べる。廃止キーは出さない。
- **テスト**: `theme_options_test.rb`（9 件）・`trait_combination_check_test.rb`（2 件）を足した。`config_keys_test.rb` は雛形の `standard` の宣言を重ねた表と、`book_yml_consumption_test.rb` は `theme:` の下を宣言（`token:`・`body_class:`・`features:`・機能の宣言・入れ子の節）で照合する。`book_settings_css_test.rb` などを新しい形に合わせた。
- 雛形は `themes/` だけを写した（S6-3 からと同じ）。

#### 仕様と違えたこと・仕様に無かったので決めたこと

1. **倍率の型 `ratio`**（§11.10 の 1）。
2. **機能の数のうち、検査するのは範囲を宣言したもの（`frontispiece.lead_size`）だけ。** 字数（`heading_chars` など）と長さ（`edge_inset` など）は、値を読む `FrontmatterGenerator` が今までどおり 🟡 を出す。両方で見ると同じ誤りに 🟡 が 2 つ出る。
3. **🟡 の文面の違い（色と画像は前後で同じ）。** (a) 読めない `theme.style`（`fancy` など）に「theme.style 'fancy' は選べない値です。image で組みます」が出るようになった（前は黙って `image` で組んでいた）。(b) 倍率が範囲の上を超えたときの括弧の中が「章題と張り合う大きさです」から「2.0 より大きい値です」に、下を割ったときの 2 行目「リードが章扉に収まらないときは、リードを縮めてください」が無くなった。どちらも章リードに固有の言い回しで、宣言から作る文面に持てないためである。下を割ったときの「本文より小さくなります」は、倍率の型なら一般に正しいので残した。
4. **`Common::CONFIG` のキーの並び。** `theme:` の下は、`options:` の順の後に機能のオプションが並ぶ（前は `markers` が最後）。値は同じで、引き方（`CONFIG.theme.markers.h3`）も変わらない。
5. **設定の読み込みで、本のテーマが読めないときは同梱のテーマの宣言を読む。** `ConfigKeys` から `theme.*` を外したので、テーマの宣言が無いと `CONFIG.theme.color` などのキーが無くなり、`vs doctor`・`vs upgrade`・直接ビルドが起動できなくなる。組むときの CSS は今までどおり本の `themes/` だけを読み（`Theme.selected`）、誤りは入口の検査が 🔴 で示す。
6. **完了の条件 2 のうち、改ページの打ち消しの選択子が `BookSettingsCss` に残る。** `page.section_pagebreak: false`・`page.chapter_pagebreak` の規則は、テーマの CSS の改ページの規則と同じ選択子を写して打ち消す（`SECTION_PAGEBREAK_SELECTORS` の `body.vs-header-image .section-topic h2`・`body.vs-header-simple h2`、`CHAPTER_PAGEBREAK_SELECTORS` の `body.vs-header-simple h1`、章扉の保護の `body.vs-header-image:not(.vs-epub) …`）。テーマが変われば選択子も変わるので、テーマの側から宣言させる形（`theme.yml` に打ち消す選択子を書く・テーマの CSS が変数で改ページを読む など）を決める必要がある。S6-7 では決めずに残した（§10 の論点 6）。

#### 確かめた結果

全部の比べ（`v2-migration-plan.md` §3.6）。B1（四つの出力先・Kindle の記録つき・`--log=debug`）・B2・B3・B4（`pdf`・`epub`・`kindle`）・単章（`bin/vs build 21`）・preflight（別の写し）を組んだ（`r2/check/s6-7/`・台本 `r2/runs/s6-7.sh`。S6-7 のコミットを置いた別の worktree から組んだ）。どれも終了コード 0。🔴 は 0、🟡 は B4 の 7 件だけ（§11.10 と同じ）。

| 確かめ | 結果 |
| :--- | :--- |
| `Common::CONFIG`（前段のコードと。B1〜B4 の設定・葉ごと・キーの順を除く） | 4 つとも同じ（152・152・152・158 葉） |
| `book-settings.css` と ThemeValidator の 🟡（前段のコードと。B1〜B4 の設定と、読めない値を並べた材料） | 5 つとも同じ。材料は `theme.color: pinky`・`preface_color: zzz`・`lead_size: 12pt`・`frontispiece.image: fuji`・`frontispiece.lead_size: large`・`ornament.image: kaede`。文面の違いは上の 3 だけ |
| 入口の CSS 11 枚・`book-settings.css`・`book-fonts.css`（B1 の写しの前段と） | バイト単位で同じ |
| 契約 HTML（B1 の写しの前段と） | 同じ。違いは showcase の SVG 2 枚の、埋め込んだ PNG の生成日時（`date:create`）だけ（§11.9 と同じ） |
| 段の一覧（前段のコードと。B1〜B4 の設定・全章と単章） | 同じ |
| PDF の画素（r2 と） | B1 の閲覧用 p83・印刷用 p82、B2 p80、B3 p125 の日付の行だけ（`pdftotext` で「16 日」→「17 日」）。B4 は p316（§11.5 の既知の差）だけ |
| EPUB（`epub_diff.rb`。前段と） | B1 のクリーン 339 ファイル・Kindle 用 261 ファイル、B4 242 ファイルとも違い 0 件 |
| Kindle の中間生成物（`kindle_record_diff.rb`。前段の記録と） | 36 件・26,405 要素で `computedstyle`・`style` とも差 0。Enhanced Typesetting: Supported・Success・エラー 0・品質の問題 0 |
| `InversionCheck` の要素ごとの判定 | B1 の 8 種類 × 2、B4 の 7 種類 × 2 とも 0 組 |
| EPUBCheck | B1 のクリーン・Kindle 用、B4 とも致命・エラー・警告 0 |
| 宣言に無いキー | 写しの `book.yml` に `theme.colour: red` を書いて `bin/vs preflight` を走らせ、「config/book.yml の theme.colour は、テーマ standard には無い設定です」「直すなら: colour → color」が出た（終了コード 0） |
| テスト | `rake test`・`rake test:standard` とも 4,466 件が通った（スキップ 1 は前からのもの）。変えたファイルに `rubocop` を掛け、違反 0 |

- **画面（`v2-migration-plan.md` §3.6 の S6-7 の後の 1 回・2026-11-17）。** B1 の KPF とクリーン EPUB を、r2 の 10 か所（基準の `VERSIONS.md` の表）と見比べた。撮った画面は `r2/check/s6-7/screens/`。
  - Kindle Previewer（Tablet・縦・Mincho・Size 4）は、10 か所とも r2 と画素まで一致する頁があった（`magick compare -metric AE` で 0）。ただし後ろの 4 か所は Location がずれ、コード 1421 → 1428、付録 8400 → 8436、用語集 9990 → 10024、索引 10290 → 10326 で一致した（前の 6 か所は同じ Location）。全体は 10,360 Locations。ずれの元は、Kindle 用 EPUB の XHTML が各 20 バイト長くなったこと（Techbook が `<head>` に入れる `<style>` の中の変数の名前が S6-2 で `--book-*` に変わった）と、S6-4〜S6-6 で `styles/*.css` の中身が変わったことで、表示は変わらない。r3 で場所の表を作り直す。
  - Apple Books（書名を `vs-test s6-7 ` で始めた写し・1024×768 の見開き）は、r2 と同じ着き方（「次の章」1・4・28・33・35・36 回、第 2 章の扉から → 1〜4 回）で、10 か所とも同じ頁（同じページ番号）に着いた。違う画素は、窓の題（書名）と窓の角のほか、下のページ番号の数字の横の位置（数字は同じ）と、付録のコードの字の縁の 4 画素だけで、紙面は同じ。写しは撮った後にライブラリから削除した（「名称変更…」で書名を確かめてから）。

### 11.12 S6-8 コマンド（2026-11-17）

#### 作ったもの

- **`vs theme`**（`ThemeCommands.list`）: 本の `themes/` のテーマを、題・版・土台つきで並べ、`book.yml` の `theme.name` のものに印を付ける。`theme.name` のテーマが本に無ければ 🟡（同梱のテーマなら `vs theme:add <名前>` を示す）。本に無い同梱のテーマがあれば、別の見出しで並べる（無ければ見出しごと出さない）。
- **`vs theme:check [名前]`**（`Theme::Check`・`lib/vivlio_starter/cli/theme/check.rb`。名前を省くと `theme.name`）: 指摘を 🔴・🟡・💡 で返し、🔴 があれば終了コード 1。
  - 🔴: `theme.yml` の誤り・契約の版・`requires_vs:`・`extends:` の先が本に無い（`Theme.resolve` の誤り）。
  - 🟡: `theme.yml` の知らないキー。テーマのファイルが選ぶクラスのうち、契約 HTML に無いもの・`:internal` のもの（`HtmlContract.lookup`。テーマ自身と土台の `body_class:` のクラスは許す）。層の中の `!important`。外部の URL（`url(http…)`・`url(//…)`・`@import "http…"`）。入れ子の規則。
  - Kindle に対応するテーマ（`supports.targets` に `kindle`）だけ: Kindle に届かない宣言（`LiteralResolver` が落としたもの。紙の寸法は 💡 で数だけ、ほかは場所と `Bundle::UNRESOLVED_ADVICE` の直し方つきの 🟡）。`kindle_tokens:` と、テーマの `kindle*.css` の `body.vs-kindle`（body のほかのクラスとの組を含む）で定義した `--book-font-size`・`--book-line-height`・総称の名前でない書体の変数（🟡）。
  - 💡: 層を外すと勝ち負けが変わりうる組（`InversionCheck.pairs` の静的な判定。EPUB・Kindle に対応するテーマだけ）。テーマの規則ごとに、取り合うプロパティと相手の選択子を 1 行にまとめる。
  - 見るのはテーマ自身のファイル（`themes/<名前>/` の下の全部の CSS と `theme.yml`）だけ。Kindle に届くかと層の勝ち負けは、一時ディレクトリに本の写し（`stylesheets/` と `themes/` への参照・空の `custom.css`・本の今の設定から作った `book-settings.css`・テーマの `tokens:`）を作り、ページの種類ごとに EPUB と Kindle の入口を組んで判定する。Kindle の変数の表の範囲は、ページの種類の body のクラスと、テーマのオプションが付けるクラス（`Resolved#body_classes`）。
  - 場所（`ファイル:行`）は、注釈を外した字面で選択子・宣言を探した最初の行。
- **`vs theme:add <名前|パス>`**（`ThemeCommands.add`・`Theme::Install`・`lib/vivlio_starter/cli/theme/install.rb`）: §7.2 の S6 の経路（同梱のテーマの名前・手元のディレクトリ・手元の zip）と複製の決まりの 1〜5。
  - 写す先の名前は、`theme.yml` の `name:`（ダウンロードしたディレクトリの名前は `mono-main` のようになるため）。一時ディレクトリへ許可の表のファイルだけを写してから `Manifest.load` と契約の版を検査し、通ったものだけを本へ写す。
  - 写さなかったもの（許可の表に無い拡張子・シンボリックリンク・`.` で始まるディレクトリは 1 行）を 💡 で並べる。
  - 本に同じ名前のテーマがあれば、ファイルごとの「置き換え・追加・削除」を全部見せてから確認する（中身が同じファイルは出さない）。「いいえ」なら何も変えない。置き換えはディレクトリごと（本の側にだけあるファイルは削除）。全部が同じなら「変えるものはありません」と示し、何もしない。
  - `extends:` の先が本に無ければ、同梱のテーマなら一緒に写す（確認も一緒）。同梱に無ければ 🟡 で知らせ、検査と `book.yml` の案内は省く（テーマを読めないため）。
  - 写した後に `vs theme:check` を走らせ、`book.yml` に書く行（`theme:` と `name:`）を示す。テーマの `tokens:` を `book.yml` に書いた `theme:` の値が覆っていれば、その行と、空欄にする書き方を 💡 で示す（§3.2）。`book.yml` は書き換えない。
  - git の URL・npm のパッケージ名の形（`://`・`git@`・`.git`・`@`）は「この版ではまだできません」と 🔴（S7）。見つからない名前は、同梱のテーマの名前を示す。
- **zip の検査**（`Theme::ZipInspector`）: 展開の前に、中央ディレクトリを Ruby で読み、絶対パス（`/`・`\`・ドライブ名）・`..` を含むパス・シンボリックリンク（Unix で作った項目の外部属性が `S_IFLNK`）の項目を挙げる。1 つでもあれば展開せずに 🔴。ZIP64 は読まずに 🔴（展開したディレクトリの指定を案内する）。展開は一時ディレクトリで `unzip` が行う。
- **`vs theme:new <名前> [--extends 土台]`**（`ThemeCommands.new_theme`・`Theme::Template`）: `--extends` があれば配色のテーマ（`extends:` と、例を注釈にした `tokens:`）、無ければ組版のテーマ（`supports:` と `styles: [theme.css]`、注釈だけの `theme.css`）を作る。名前の形・既にあるディレクトリ・本に無い土台は 🔴。作った後に `vs theme:check` を走らせ、`book.yml` に書く行を示す。
- **テーマが見つからないときの案内**（§11.6 の 5）: `Theme.load_named` が、同梱のテーマにある名前なら「同梱のテーマなので、vs theme:add <名前> で本に入れられます」を先に示す（`theme.name`・`extends:` の両方）。`TraitCombinationCheck` の対応するテーマの案内も、本に無い同梱のテーマには「（vs theme:add <名前> で入れます）」を添える。
- **ヘルプ**: 4 つを `RootCommand.public_commands` と `vs --help` の「テーマ」の分類に足した。原稿（マニュアル）には S11 で書くので、`docs_allowlist.yml` の `undocumented_commands` に理由つきで入れた（原稿に書いたら外す）。
- **テスト**: `theme_commands_test.rb`（8 件。同梱の `standard` で 🟡 0・`theme:new` の 2 種類が `theme:check` を通る・範囲の外の書き方の 🟡・許可の表と土台の同梱・置き換えの確認・zip の検査と展開・まだ受けない経路・一覧）。`theme_test.rb` の土台の無いテーマの案内に、同梱の名前と同梱に無い名前の 2 通りを足した。

#### 仕様と違えたこと・仕様に無かったので決めたこと

1. **層の勝ち負けの組は 💡 で示す。** §4.3（`css-layer-restructure-spec.md`）は「`vs theme:check` は静的な判定で起きうる組を示す」としている。静的な判定は、取り合わない要素どうし（見出しとコードの中の要素、章の body と目次のページ）も挙げる。`standard` では 39 組で、どれも `css_layer_test.rb` の許可の表の理由（同じ要素にならない）に当たる。🟡 にすると、完了の条件（`standard` で 🟡 0）と合わず、直すものでもないので、💡 で「起きうる組」とし、確定は `vs build --log=debug` の要素ごとの判定が行うと書いた。
2. **`vs build` が、著者が入れたテーマの組を要素ごとの判定で 🟡 にする扱い（§4.3 の「扱い（S6 以降）」）は、S6-8 では作っていない。** 小段階の表の S6-8 の行に無い。今の `vs build` は、テーマに依らず `--log=debug` のときだけ組を出す。どの小段階で入れるかは §10 の論点 7 とした。
3. **`book-settings.css` は本の今の設定から作る。** 検査するテーマが選ばれているテーマと違っても、設定の書き出しは今のテーマの宣言による。設定が定義する変数は名前が同じ（公開する変数）なので、Kindle の変数の表への影響は無いと見た。
4. **`scaffold.lock` への記録（§7.3 の「`vs theme:add` で入れた同梱のテーマ」）は S6-9 で行う。** 小段階の表で S6-9 の行にある。
5. **置き換えはディレクトリごと。** §7.2 の 4 は「置き換わるファイルの一覧を見せて確認」とだけ書いている。テーマの版を上げたときにファイルが減ることがあり、古いファイルが残ると `styles:` に無い CSS が残るだけでなく、出力先の CSS（`epub.css` など。置けば読まれる）が残って効いてしまうので、本の側にだけあるファイルは削除し、確認の一覧に「削除」として出す。

#### 確かめた結果

| 確かめ | 結果 |
| :--- | :--- |
| 完了の条件: `themes/standard/` に `vs theme:check` | 🔴・🟡 とも 0。💡 は紙の寸法の 39 個と、層の勝ち負けの 39 組（テーマの規則 10 個） |
| 完了の条件: `vs theme:new x --extends standard` | 出力が `vs theme:check` を通る（指摘 0）。組版のテーマの雛形も同じ |
| 完了の条件: zip の検査のテスト | `../evil.css`・`/etc/evil.css`・`theme/../../evil.css`・`C:/evil.css`・シンボリックリンクの項目で展開せずに 🔴、安全な zip は 1 階層下の `theme.yml` を見つけて入る（`theme_commands_test.rb`） |
| 写しの本で `bin/vs` | `vs theme`・`vs theme:check`・`vs theme:new mono --extends standard`・`vs theme:new plain`・`vs theme:add standard`（同じなので何もしない）・`vs theme:add ../dl/blue-theme`（`install.sh` を写さず、`theme.color: green` が覆っていることを示す）・`vs --help` の分類 |
| テスト | `rake test` 4,474 件が通った（S6-7 の後の 4,466 件に、足した 8 件。スキップ 1 は前からのもの）。変えたファイルに `rubocop` を掛け、違反 0 |

### 11.13 S6-9 `vs upgrade`（2026-11-17）

#### 作ったもの

- **雛形のテーマの振り分け**（`UpgradeCommands#managed_theme_digests`）: 雛形の `themes/<名前>/` のファイルを、三者比較の前に次のとおり振り分ける。残さなかったファイルは計画に載らず、lock からも記録が消える。
  - 本にあり、lock に記録があるテーマ: 雛形から来たテーマとして、ほかの雛形のファイルと同じに更新する（追加・更新・合流・競合）。
  - 本にあり、lock に記録が無いテーマ: 著者が入れたテーマとして触らない（同梱と同じ名前でも）。
  - 本に無いテーマ: 本が使うテーマ（`book.yml` の `theme.name`、無ければ `standard`。とその `extends:` の 1 段）だけを足す。1.x の本は `themes/` を持たないので、ここで `standard` が入る。ほかの同梱のテーマは足さない（§7.1。`vs theme:add` で入れる）。
- **著者のテーマの契約の版**（`contract_mismatches`）: lock に記録の無いテーマのうち、`Theme::Contract.check!`（契約の版・`requires_vs:`）に通らないものを、`vs upgrade` の最後（外部ツールの出力の後）に 🟡 で示す。`theme.yml` の書き方の誤りは `vs theme:check` と `vs build` が示すので挙げない。
- **`vs theme:add` の記録**（`ScaffoldLock.record_theme!`・`ThemeCommands#record_in_lock`）: 同梱のテーマを入れたら、入れたファイルのハッシュを lock に記録し、三方向のマージの祖先（`.cache/vs/scaffold-base/`）も進める。同梱でないテーマを入れたら、同じ名前の記録を消す。本と同じで何も写さなかったときも記録する。lock の無い本では何もしない。
- **`custom.css` の 1.x の変数の名前**（`rename_legacy_tokens!`・`Css::LegacyTokens.rename_lines`・`renamed_css`）: 雛形追従の後（全体の確認で「いいえ」なら行わない）、置き換える行を行番号と前後の形で全部見せてから尋ねる。「はい」なら `.vs-backup/upgrade/` へ退避してから書き換える。「いいえ」なら何も変えない。`--dry-run` は行を見せるだけで尋ねない。

#### 仕様に無かったので決めたこと

1. **`custom.css` の置き換えは `--yes` でも尋ねる。** `--yes` は「競合以外を確認なしで適用する」オプションで、`custom.css` は §7.3 で「触らない」としている著者のファイルである。競合と同じく、必ず尋ねる。断っても、今の名前は別名で効くので組み上がりは変わらない。
2. **自分自身を読む定義になる行は置き換えない。** `--theme-accent: var(--book-color-accent);` は置き換えると `--book-color-accent: var(--book-color-accent);`（循環）になる。行を残し、💡 で「要らなければ削除してください」と示す（`css-layer-restructure-spec.md` §7.2 の、settings 層へ渡さない定義と同じもの）。
3. **注釈の中の名前も置き換える。** `LegacyTokens.rename`（S6-2）の決まりのまま。置き換える行は全部見せるので、注釈の行も確認の前に分かる。雛形の `custom.css` の「使い方の例」も新しい名前で書いてある。
4. **本が使うテーマは `Common::CONFIG` でなく `book.yml` を直接読む。** `vs upgrade` は廃止キーの残った `book.yml` でも動き、設定を読み込んだ時点と作業ディレクトリが合うとも限らないため。
5. **著者のテーマの 🟡 の案内は `vs upgrade` 用に書き換える。** `Contract` の案内（「vs upgrade で vs を新しくしてください」）は、`vs upgrade` の最後では次の手にならない。版の事実（読める契約の版）だけを残し、「著者が入れたテーマなので更新していない」「この vs に合う版のテーマを `vs theme:add` で入れ直す」を示す。
6. **雛形から消えたテーマのファイルは、本から消さない。** 今の雛形の更新と同じ（lock から記録が消えるだけ）。テーマの出力先の CSS（`epub.css` など）は置けば読まれるので、雛形がそれを消したときは本に残って効く。同梱のテーマからファイルを消す変更をするときに、消す扱いを足す（S8 で `bunko` を書くときに見直す）。→ S6-10 で、消す扱いを足した（§7.3・§11.15）。

#### 確かめた結果

| 確かめ | 結果 |
| :--- | :--- |
| 写しの本（B4 の素材 `r2/src/ai_web_starter/`・lock は 1.0.0）で `vs upgrade`。`ToolUpgrader.run!` と `run_gem_command`（`bundle update`）を差し替え、`--skip-self-update` | `--dry-run`: `themes/standard/` の 17 個が「追加」、置き換える `custom.css` の 4 行と残す 1 行、`themes/future/`（`contract: 2`）の 🟡 が最後に出て、何も変えない。1 回目（全体の確認は「はい」・`custom.css` は「いいえ」）: `themes/standard/` が入り lock に 17 個の記録、`themes/future/` は記録されない、`custom.css` は前とバイト単位で同じ。2 回目（「はい」）: 4 行だけが変わり、元が退避された |
| テスト | `upgrade_commands_test.rb` に 7 件（テーマの振り分け 3・契約の版 1・`custom.css` 3）、`theme_commands_test.rb` に 1 件（lock の記録）、`legacy_tokens_test.rb` に 1 件（行の計画）。`rake test` 4,483 件が通った（S6-8 の後の 4,474 件に、足した 9 件。スキップ 1 は前からのもの）。変えたファイルに `rubocop` を掛け、違反 0 |

### 11.14 S6-9b 改ページを公開する変数で読む（2026-11-17）

決定の経緯は `v2-s6-10-consultation.md` §4.3〜§4.5。

#### 作ったもの

- **`stylesheets/tokens.css`**: `--book-section-break-before: page`・`--book-section-page-break-before: always`・`--book-chapter-break-before: recto`（§5.2）。
- **`themes/standard/` の 4 か所**: `simple-header.css` の `body.vs-header-simple h1`（`var(--book-chapter-break-before)`）と `h2`、`image-header.css` の `body.vs-header-image .section-topic h2`（`var(--book-section-break-before)`）、`kindle.css` の `body.vs-header-simple.vs-kindle h2`（変数の名前を `--book-*` にし、`var()` の予備の値を外した）。選択子は変えていない。
- **`BookSettingsCss`**: `page.section_pagebreak: false` で `:root` に `--book-section-break-before: auto`・`--book-section-page-break-before: auto` を、`page.chapter_pagebreak` が `any`・`verso` で `--book-chapter-break-before: page`・`verso` を書く。`SECTION_PAGEBREAK_SELECTORS`（`article.vs-section-topic-epub` だけ）と `CHAPTER_PAGEBREAK_SELECTORS`（`body`・`body.toc`・`body.whole_toc`・`.part-title`）には vs 自身の選択子だけを残した。
- **`Theme::Features::Frontispiece`**: `PAGE_KINDS = %i[chapter]`・`page?(body_classes, active:)`（扉絵の章扉か）・`guard_rule(active:)`（章扉の保護。選択子は `body.chapter:not(.vs-epub) section.level2:first-of-type > .section-topic h2:not(.vs-break-merged)`）。`BookSettingsCss` は、扉絵の機能が有効なときだけ保護を書く。
- **`PageBreakNormalizer#breaking_h2_scope`・`ChapterLeadCheck#collect_leads`** は `Frontispiece.page?` で判定する。`lib/vivlio_starter` の Ruby に `vs-header-` を書いた行は、注釈を除いて 0 になった（完了の条件 2）。
- **`vs theme:check`**: 最後の複合選択子が `h1`・`h2` の規則に、`var()` を使わない `break-before`（`auto`・`avoid` で始まる値を除く）があれば 🟡「`<ファイル>:<行>` の break-before: page では、config/book.yml の page.section_pagebreak が効きません」と、書き直す 1 行（`→ break-before: var(--book-section-break-before); と書いてください`）。出力先の CSS（`epub*.css`・`kindle*.css`）は `h2` だけを見る。**`vs theme:new`** の組版のテーマの `theme.css` の注釈に、変数で書く例を足した。
- **テスト**: `theme_commands_test.rb` に 1 件（値で書いた改ページの 🟡・出力先の CSS の h1 は出さない）、`page_break_normalizer_test.rb` に 1 件（扉絵の機能が有効でも付録は章扉にならない）、`book_settings_css_test.rb` に 1 件（機能が無効なら章扉の保護を書かない）。既存のテストは、変数の名前・`body.chapter` の選択子・機能の有効の与え方（`frontispiece:` を明示する）に合わせた。`chapter_lead_check_test.rb` の付録の材料は、`body` を `chapter vs-header-simple` から実物と同じ `appendix vs-header-simple` に直した。

#### 仕様に無かったので決めたこと

1. **`ChapterLeadCheck#collect_leads` は、ページの種類だけを見る（`page?(…, active: true)`）。** 機能が有効かは、呼び出し元（`image_style?`）が先に確かめている。テストが `collect_leads` を直接呼ぶときに、`BuildPlan.current`（本の設定）を読ませないためでもある。
2. **`PageBreakNormalizer` は、機能の有効を `BuildPlan.current.features.frontispiece` から読む（`frontispiece_active?`）。** テストは `section_pagebreak_enabled?` と同じく差し替えて与える。
3. **`vs theme:check` の検査は、最上位の規則だけを見る（`@media` の中は見ない）。** 見出しの改ページを媒体で分けて書く理由が無いためである。行番号は、選択子の行から下で最初に `break-before` を含む行とした。
4. **`book-settings.css` の中で、変数の `:root` を vs 自身の選択子の打ち消しより前に書く。** 設定の働きの中心が変数になったためで、規則の勝ち負けには関わらない（別の規則で、取り合うプロパティが無い）。
5. **`book_settings_css_test.rb` の「右ページ始まりの規則を全部打ち消す」検査は、変数の定義を数えない。** `tokens.css` の `--book-chapter-break-before: recto` が、`break-before: recto` の字面に当たるためである（正規表現の前に `-` と英数字が無いことを条件にした）。
6. **`stylesheets/utilities/pagebreak.css` の注釈の中のメソッドの名前を、`Theme::Features::Frontispiece.guard_rule` に直した。** EPUB の CSS の字面は変わるが、S6-9b は CSS の字面を変える小段階なので、比べは計算値で行う。
7. **`style: simple` の本（B2）では、`book-settings.css` から章扉の保護が無くなる。** 前は、どの要素にも当たらない規則として出ていた（`body.vs-header-image` の付く頁が無い）。

#### 確かめた結果

前（`368ccc31`。S6-9 の後で、ビルドの経路は S6-7 から同じ）と後（`d373e871`）を、それぞれコミットを置いた別の worktree から組んだ（台本は基準の `r2/check/s6-9b/build_before.sh`・`build_after.sh`、出力は同じディレクトリ）。どの組み上がりも終了コード 0、🔴 と 🟡 は 0。

| 確かめ | 結果 |
| :--- | :--- |
| 完了の条件 2 | `lib/vivlio_starter` の Ruby で、注釈を除いて `vs-header-` を書いた行は 0 |
| PDF の画素（r2 と） | B1 の閲覧用 p83・印刷用 p82、B2 p80、B3 p125 の日付の行だけ（`pdftotext` で「16 日」→「17 日」）。ほかの全ページは一致 |
| 契約 HTML（B1 の前後） | 同じ。違いは showcase の SVG 2 枚の、埋め込んだ PNG の生成日時だけ（§11.9 と同じ） |
| `book-settings.css`（B1 の前後） | 違いは改ページの節だけ（変数の `:root` 2 つ・テーマの選択子 3 つが消えた・章扉の保護の選択子が `body.chapter`） |
| EPUB の計算値（`css_computed_diff.rb`。前の HTML に、前の版と後の版の CSS を当て、後の側には後の `book-settings.css` を渡した） | B1 の 117 文書・312 組（PDF・クリーン EPUB・Kindle、画面と印刷、層ありと平ら）、B2（`simple`・`false`）と B2 の `true` の写しのクリーン EPUB が各 39 文書・78 組とも違い 0。`break-before` の計算値の差も無い |
| EPUB の HTML（前後） | 違いは EPUB の中の画像の名前だけ（写しごとに変わる名前） |
| Kindle の中間生成物（`kindle_record_diff.rb`。B1 の前後） | 36 件・26,405 要素で `computedstyle`・`style` とも差 0。B1（`any`）の付録の章見出し（`body.vs-header-simple h1`）は、前は settings 層の規則から `page-break-before: always` を受けていたが、`themes/standard/kindle.css` の `body.vs-header-simple.vs-kindle h1` も同じ値を書いているので、差は出なかった |
| `InversionCheck` の要素ごとの判定（`--log=debug`） | B1 の EPUB と Kindle の 16 種類、B2 の EPUB の 8 種類とも 0 組 |
| EPUBCheck | B1 のクリーン・Kindle 用、B2 の `false`・`true` とも致命・エラー・警告 0 |
| `vs theme:check standard` | 🔴・🟡 とも 0 |
| テスト | `rake test` 4,486 件が通った（S6-9 の後の 4,483 件に、足した 3 件。スキップ 1 は前からのもの）。`rake test:layout` 7 件が通った。変えたファイルに `rubocop` を掛け、違反 0 |
| Apple Books（B2 の `false`・`true` の写し。書名を `vs-test s6-9b` で始めた写し・1024×768 の見開き） | 第 2 章（表紙から「次の章」4 回）から → で 3 回送って見た。`false` は、節見出し「2-2」が囲みのすぐ後に（p30）、「2-3」が段落のすぐ後に（p32）同じページで続く。`true` は、「2-2」（p33）・「2-3」（p35）とも新しいページの頭から始まる。Apple Books も `break-before` の `var()` を解く（`v2-migration-plan.md` §2.4 の危険の 5 は起きなかった）。予備の `break-before: page;` は足していない。撮った画面は `r2/check/s6-9b/screens-books/`。写しは撮った後に、「名称変更…」で書名を確かめてからライブラリから削除した |

### 11.15 S6-10 配色のテーマと `kindle_tokens:`・S6 の完了（2026-11-17）

決定の経緯は `v2-s6-10-consultation.md` §4.7（雛形から消えたテーマのファイル）。

#### 作ったもの

- **`kindle_tokens:` の書き出し**（`Css::EntryWriter`）: 選ばれたテーマの `kindle_tokens:`（土台 → 自分の順に重ねる。`Theme::Resolved#kindle_tokens`）を、`.cache/vs/theme-kindle-tokens.css` に `body.vs-kindle { --book-…: …; }` として書き出す。Kindle の束の target 層の 2 番目（`targets/kindle-tokens.css` の後・vs の `targets/` の前。`css-layer-restructure-spec.md` §5）で読む。クリーン EPUB と PDF は読まない。`kindle_tokens:` が空なら書かず（前のビルドの残りは消す）、入口にも入れない。`standard` は `kindle_tokens:` を持たないので、本書の出力は変わらない。
- **`Theme::Manifest`**: `kindle_tokens:` を `tokens:` と同じ決まり（`--book-` を除いた名前・`;` `{` `}` を含まない 1 つの値）で検査する。外れたら 🔴（`Theme::Error`）。Kindle で書ける値の範囲（§3.5）は、今までどおり `vs theme:check` が 🟡 で示す。
- **配色のテーマの見本** `test/vivlio_starter/fixtures/themes/standard-mono/theme.yml`: `extends: standard` と `tokens:`（`color-accent: "#555"`・`color-link: "#333"`）と `kindle_tokens:`（`font-heading: serif`・`color-link: "#222"`）だけ。同梱しない。
- **`vs upgrade` が、雛形から消えたテーマのファイルを消す**（§7.3。`UpgradeCommands#plan_theme_removals`・`report_kept_theme_files`）: lock に記録のある `themes/` の下のファイルで、今の雛形に無いものを探す。本の中身が lock の記録と同じなら、計画に「削除（雛形から無くなったファイル）」の行を出し、全体の確認（`--yes` なら確認なし）の後、`.vs-backup/upgrade/` へ退避してから消す。著者が変えていれば残し、`vs upgrade` の最後（外部ツールの出力の後）に 🟡 でパスを示す（出力先の CSS なら「置いてあるかぎり読まれます。要らなければ削除してください」、それ以外は「読まれません」）。どちらも lock の記録は消える（`record_lock!` が雛形に無いファイルとして落とす）ので、次の `vs upgrade` では知らせない。`--dry-run` は「削除」の行と件数を見せるだけ。§11.13 の決め 6 は、これで覆った。
- **雛形の同期**（`0aa202cd`）: S6-2 の後、雛形の `stylesheets/` は旧い変数の名前のまま、`themes/standard/` だけが新しい名前で写されていた（`vs new` の本は、テーマの変数が解けない組み合わせになっていた）。`ruby scripts/copy_to_scaffold.rb` で直下の正典を写した（`stylesheets/images/bundled/`・`parts/simple-header.css`・`parts/image-header.css` が消え、`tokens-legacy.css` が入る）。
- **テスト**: `entry_writer_test.rb` に 2 件（書き出しと target 層の順・書き出せない名前の 🔴）、`theme_commands_test.rb` に 1 件（`standard-mono` が `vs theme:check` を通り、`tokens:` の色が `theme.color` の既定値になる）、`upgrade_commands_test.rb` に 3 件（変えていないファイルの削除と退避・変えたファイルを残す 🟡・`--dry-run`）。

#### 仕様に無かったので決めたこと

1. **`kindle_tokens:` の書き出しは、`tokens:` と同じ `write_theme_tokens!` が行う。** `vs theme:check` の Kindle の束の組み立て（`Theme::Check#prepare_workspace`）も同じ口を通るので、検査する束にも `kindle_tokens:` が入る（検査の対象はテーマ自身のファイルだけで、書き出したファイルは見ない）。
2. **見本の `kindle_tokens:` には、見出しの書体のほかにリンクの色も書いた。** §3.1 の使い道の 2 つ（見出しを明朝に・リンクを `#222` に）を両方通すためである。完了の条件 10 の「Kindle の見出しだけが明朝」は、書体の変わる要素が見出しだけであることとして確かめた。
3. **残したファイルの 🟡 で「出力先の CSS」と見なすのは、テーマのディレクトリの直下の `epub*.css`・`kindle*.css`。** 読まれるかどうかが置き場で決まるのはこれだけである（`styles:` の CSS は `theme.yml` が並べたものだけが読まれ、`theme.yml` も雛形から更新される）。
4. **雛形の同期は S6 の完了に含め、別のコミットにした。** `v2-migration-plan.md` §4.1 の「`stylesheets/`・`themes/` を変えたら同期する」を S6-2 から行っていなかったため。ビルドの経路は変えない（本書は直下の `stylesheets/` を読む）。

#### 確かめた結果

全部の比べ（`v2-migration-plan.md` §3.6 の S6 の最後）と、配色のテーマの見本の 2 通り（`kindle_tokens:` あり・なし）を、S6-10 のコミット（`86f070a2`）を置いた別の worktree から組んだ（台本は基準の `r2/runs/s6-10.sh`、出力は `r2/check/s6-10/`）。どの組み上がりも終了コード 0、🔴 は 0、🟡 は B4 の 7 件だけ（§11.10 と同じ）。

| 確かめ | 結果 |
| :--- | :--- |
| PDF の画素（r2 と） | B1 の閲覧用 p83・印刷用 p82、B2 p80、B3 p125 の日付の行だけ（`pdftotext` で「16 日」→「17 日」）。B4 は p316（§11.5 の既知の差）だけ。ほかの全ページは一致 |
| EPUB（`epub_diff.rb`。B1 は S6-9b の後の出力と） | B1 のクリーン 339 ファイル・Kindle 用 261 ファイルとも違い 0 件 |
| EPUB（B4。S6-7 の後の出力と。S6-9b では B4 を組んでいない） | 7 件。どれも `styles/*.css` で、変わった行は S6-9b の改ページの変数（`tokens.css` の 3 つ・テーマの 4 か所の `var()`・`book-settings.css` の改ページの節）だけ。B4 の改ページの設定（`section_pagebreak: false`・`chapter_pagebreak: any`・`style: image`）は、S6-9b で計算値の差 0 を確かめた B1 と同じ |
| 入口の CSS 11 枚・`book-settings.css`・`book-fonts.css`（B1 の写しの、S6-9b の後と） | バイト単位で同じ。`theme-tokens.css`・`theme-kindle-tokens.css` は書かれない |
| 契約 HTML・EPUB と Kindle の枝の HTML（B1 の写しの、S6-9b の後と。156 文書） | 写しごとに変わる画像の名前（`_epub_assets/` の下・`pictures-` の付くものを含む）と、showcase の SVG の生成日時を除いて同じ |
| Kindle の中間生成物（`kindle_record_diff.rb`。B1 の S6-9b の後と） | 36 件・26,405 要素で `computedstyle`・`style` とも差 0。Enhanced Typesetting: Supported・Success・エラー 0・品質の問題 0 |
| `InversionCheck` の要素ごとの判定（`--log=debug`） | B1 の EPUB と Kindle の 16 種類、B4 の 14 種類、`standard-mono` の 2 通りの各 16 種類とも 0 組 |
| EPUBCheck | B1 のクリーン・Kindle 用、B4、`standard-mono` のクリーン・Kindle 用とも致命・エラー・警告 0 |
| 単章（`bin/vs build 21`）・`vs preflight`（別の写し） | 終了コード 0・🟡 0。preflight は「良好な状態です」 |
| 完了の条件 4（`standard-mono`。`theme.name: standard-mono`、`theme.color`・`preface_color`・`appendix_color` を空欄） | `book-settings.css` に `--book-color-accent`・`-preface`・`-appendix` とも `#555`（`tokens:` の値がオプションの既定値になる）。PDF は B1 と比べて 257 ページで画素が違い、`pdftotext -bbox` の語と頁の 26,346 行は全部同じ位置。並べて見た 3 ページ（前書き p4・本文 p25・付録 p227）で、前書きの節見出しの帯・本文の見出しの印・用語集の印など、テーマ色で塗ったところが灰色になっていた。Kindle の中間生成物は、`style` の差が色だけ（緑・青緑・水色 → `#555`、リンク `#000` → `#333`、コラムの地の混色）で、`computedstyle` の差 0。クリーン EPUB の差は、CSS の色の値・テーマ色で塗った節見出しの合成画像（108 枚。名前が中身のハッシュで変わる）・見出しの印の画像 2 枚と、それを指す XHTML と OPF の行だけ |
| 完了の条件 10（`kindle_tokens:` あり・なしの `standard-mono`） | PDF は 284 ページとも画素が一致（文字の位置も同じ）。クリーン EPUB は違い 0 件。Kindle 用 EPUB は、`styles/*.css` 8 枚に書き出した `body.vs-kindle { … }` と、そのリテラル化の分だけ。Kindle の中間生成物の `style` の差は、見出し（h1〜h4）と図のキャプション（どちらも `--book-font-heading` を読む）の `font-family: sans-serif → serif` の 610 件と、リンクの `color: #333 → #222` の 445 件だけ。`computedstyle` の差は、見出しの字形が変わって後ろの要素が 1px ずつ下がった位置（`contentTop`・`contentBottom` など）だけで、本文の書体は変わらない。`kindle_tokens:` の `font-size` と総称の名前でない書体の 🟡 は、`theme_commands_test.rb`（S6-8）で確かめている |
| 雛形から消えたテーマのファイル（写しの本。B4 の素材 `r2/src/ai_web_starter/`・lock は 1.0.0） | 先に今の雛形で `vs upgrade --yes`（競合は「いいえ」）を掛け、`themes/standard/` を入れた（lock に 17 個の記録）。次に、`themes/standard/kindle.css` と `epub.css` を抜いた材料の雛形を作り、本の `epub.css` に 1 行足して走らせた。`--dry-run`: 「削除 themes/standard/kindle.css（雛形から無くなったファイル）」と「削除 1 件」が出て、ファイル・lock・退避とも変わらない。本番（`--yes`）: `kindle.css` が消え、`.vs-backup/upgrade/<日時>/themes/standard/kindle.css` に元と同じ中身で退避され、lock から `kindle.css`・`epub.css` の記録が消えた。`epub.css` は残り、最後に 🟡「themes/standard/epub.css は雛形から無くなったファイルですが、変更があるので残しました」「置いてあるかぎり読まれます。要らなければ削除してください」。もう一度走らせると、「削除」も 🟡 も出ない。`ToolUpgrader.run!` と `run_gem_command` は差し替えて走らせた |
| テスト | `rake test` 4,492 件が通った（S6-9b の後の 4,486 件に、足した 6 件。スキップ 1 は前からのもの）。変えたファイルに `rubocop` を掛け、違反 0 |
| `rake test:release`（1 段ずつ。記録は `r2/check/s6-10/release/`） | 全段が通った（19:58〜20:57）。`test` と `test:standard` 4,492 件（スキップ 1）・`test:layout` 7 件・`test:targets` 19 件・`test:notation` 7 件・`test:manual` 14 件・`test:package` 4 件 |
