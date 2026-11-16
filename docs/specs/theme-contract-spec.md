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

`tcy` と `sesame` は `vs-` を付けない。公式テーマと、電書協の様式で書かれた既存の CSS が、そのまま当たるようにするためである。

### 2.6 契約 HTML はテーマと出力先に依らない

`v2-architecture-spec.md` §3.1 の決まりである。今この決まりに反している箇所と、直し方を示す。

| 今の挙動 | 直し方 | 見た目への影響 |
| :--- | :--- | :--- |
| h2 を `article.section-topic` で包むのは `theme.style: image` のときだけ | 常に包む。`simple` のときの見た目は CSS で今と同じに保つ | `simple` の本の HTML が変わる。画素の比較で、見た目が変わらないことを確かめる |
| `body` の `vs-header-image`・`vs-header-simple` を `BodyClassInjector` がコードで決める | テーマの `theme.yml` の宣言（§3.3 の `body_class`）から決める。`standard` テーマの宣言で今と同じクラスが付く | なし |
| 扉絵・節絵の画像の用意（`prepare theme images`）と、EPUB の見出しの画像（`inject_heading_images`）が常に走る | テーマが `features:` で使うと宣言したときだけ走る（§3.4）。EPUB の見出しの画像は L4 の変換なので、契約 HTML には影響しない | なし |
| 見出しの印の字（`theme.markers`） | 今も CSS の変数で渡しており、HTML には入らない。変えない | なし |

### 2.7 固定レイアウトの契約 HTML（枠だけ）

`traits.fixed?` の本では、1 ページが 1 枚の HTML になる。

- `body` に `vs-fixed` と、ページの種類のクラスを付ける。
- `head` に、ページの寸法の `viewport` を書く。
- ページの中の要素（全面の画像・重ねる文字の箱・動画）のクラスは、絵本の仕様で決め、契約の表に足す。契約の版は上げない（足すだけなので、既存のテーマは壊れない）。

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
| `number` | 数（`min`・`max` を書ける） | `token:` の変数へ |
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
- `standard` の今の 15 個のキーを「`options:`」「`frontispiece`」「`ornament`」に分けた表は、S6-7 の最初に作ってここに書く。どれにも入らないキー（Ruby が読むが、扉絵にも節絵にも属さないもの。`markers.*` と `lead_size` が候補）が出たら、実装を止めて相談する。3 つ目の機能を足すかは、その表を見て決める。
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
| `stylesheets/tokens.css`（公開する変数の既定値） | 残す。`--book-*` の一覧の正典（§5.2） | `standard` の `tokens:` は空。テーマに依らない中立の既定値と `standard` の値を分けるのは、2 つ目の組版のテーマ（`bunko`・S8）が値を決めるとき |
| `pages/chapter.css` の `@page :nth(1)`（扉絵） | 残す | §3.4 |
| `pages/appendix.css`・`pages/preface.css` の `:root` の付け替え | 残す | 付録の色・前書きの色は公開する変数（`--book-color-accent-appendix`・`-preface`）で、どのテーマでも働く仕組みである |
| `parts/heading.css`・`prose.css`・`box.css`・`preface.css` などの、色・書体・余白・飾りの規則 | 残す | 下の「部品に残す飾り」 |
| `ThemeColor`（12 色の名前と値） | 12 色は `--book-accent-*` として vs の土台が持つ（§5.2） | テーマではなく、どのテーマからも使える色の名前とする |

**部品に残す飾り（`v2-s6-consultation.md` §4.10）。** `css-layer-restructure-spec.md` §3.2 の線引き（消すと働かなくなるものは部品、飾りはテーマ）は決まりとして残すが、S6 で theme 層へ移すのは上の表の見出しの 2 枚だけとする。

- 部品の色と書体は、すでに公開する変数を読んでいる。テーマは変数で変えられる。規則で変えたいテーマは theme 層に書けば、PDF では詳細度に関係なく勝つ。規則を移さなくても、テーマにできることは減らない。
- 規則を parts 層から theme 層へ移すたびに、詳細度が同じ組で勝つ側が入れ替わりうる。組版のテーマが `standard` の 1 つしか無い時点では、どの規則が「どのテーマにも要る骨格」で、どれが「`standard` だけの飾り」かを確かめる相手が無い。「迷う規則は部品の側に置く」（同 §3.2）に合う。
- 残した規則のうち、`bunko`（S8）を書くときに打ち消しが要ったものを、S8 の中で `standard` へ移す（§10 の論点 5）。前書きの見た目（`parts/preface.css`）が、いちばんの候補である。

**`targets/` の規則の線引き（`v2-post-s3-consultation.md` §5.4）。**

- vs の部品（囲み・コード・表・索引・用語集・奥付）の規則は、`stylesheets/targets/` に残す。テーマへ移すのは、上の表の 3 行目の規則（選択子が `vs-header-*` を含むもの）だけである。テーマの出力先の CSS は 11 種類の全部の束に入るが、vs の `targets/epub.css`・`kindle.css` は本文のページの 4 種類にしか入らない。素の `h1`・`h2` を選ぶ規則を移すと目次・索引・用語集の見出しにも当たるので、相手の部品がテーマへ移っていても vs の `targets/` に残す（`v2-s6-consultation.md` §4.2 の決め 11）。
- 移すときは、選択子と宣言を変えない。クラスを足して絞ると詳細度が上がり、平らな CSS では勝ち負けが変わりうる（`v2-flat-cascade-consultation.md` §5.3 の 5）。
- 移すと、vs の `targets/` の規則との前後が変わる（テーマの出力先の CSS は vs の `targets/` の後に読む）。詳細度が同じ組では勝つ側が入れ替わりうるので、移動の前後で EPUB の計算値と Kindle の中間生成物が差 0 であることを確かめる（§9 の S6 の条件 8）。

種類ごとの既定のテーマ:

| 種類 | 既定のテーマ | 中身 |
| :--- | :--- | :--- |
| `techbook` | `standard` | 今の見た目 |
| `novel` | `bunko`（仮の名前） | 縦書き・文庫の体裁。§6.4 |
| `picture_book` | `picture`（仮の名前） | 固定レイアウト。絵本の仕様で決める |

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
- **S6 で名前を変える範囲（`v2-s6-consultation.md` §4.2 の決め 8）。** `--book-*` に変えるのは、§5.2 の公開する変数と、機能の変数（`--book-frontispiece-*`・`--book-ornament-*`）である。`standard` へ移る見出しの 2 枚の中だけの変数は `--standard-*` にする。vs の内部の変数（`base/page.css` の `--page-width`・`--page-height`・`--align-max-width`・`--font-body`、`pages/titlepage.css`・`pages/colophon.css` の `--subtitle-*`、生成する `--talk-c-<key>` など）は、2.0 では名前を変えない（`base/page.css` の残りの 20 個は §5.2 の公開する変数で、S6-2 で `tokens.css` へ移した。§11.4 の「仕様と違えたこと」の 1）。`--_*` に変えて別名を置けば内部の変数でなくなり、置かなければ、その変数に値を入れていた 1.x の `custom.css` が警告なしに効かなくなるためである。`--_*` の決まりは、これから足す内部の変数に当てる。名前を変えた変数は例外なく対応の表（`css-layer-restructure-spec.md` §7.2）に載せる。

### 5.2 公開する変数の一覧（分類）

1 行ずつの一覧は S6 で `stylesheets/tokens.css` に置き、そこを正典とする。分類と、今の名前からの対応を示す。

| 分類 | 新しい名前 | 今の名前 | 値を入れる側 | Kindle |
| :--- | :--- | :--- | :--- | :--- |
| テーマ色の 12 色 | `--book-accent-yellow` … `--book-accent-lime` | `--accent-*` | vs の土台 | 届く |
| 本のテーマ色 | `--book-color-accent`・`--book-color-accent-preface`・`--book-color-accent-appendix` | `--theme-accent`・`--color-preface-accent`・`--appendix-accent-color` | `settings`（テーマのオプション） | 届く |
| 色 | `--book-color-text`・`-link`・`-strong`・`-em-underline`・`-border`・`-border-weak`・`-output-border`・`-column-bg`・`-column-border`・`-figure-border`・`-overlay`・`-danger`・`-mark`・`-heading`・`-section-number` | `--color-*`・`--heading-accent`・`--section-number-color` | テーマ | 届く |
| 書体 | `--book-font-body`・`-heading`・`-column`・`-code`・`-folio`・`-title` | `--font-main-text`・`--font-header`・`--font-column`・`--font-code`・`--font-folio`・`--font-title`（奥付の本文が読む `--font-body` は内部の変数のまま） | `settings`（`typography`） | 総称の名前に置き換わる（`kindle-tokens.css`） |
| 版面 | `--book-page-margin-top`・`-bottom`・`-inner`・`-outer`・`--book-font-size`・`--book-line-height`・`--book-letter-spacing`・`--book-paper-scale` | `--page-margin-*`・`--base-font-size`・`--base-line-height`・`--letter-spacing`・`--paper-scale` | `settings`（判型のプリセット） | `--book-font-size`・`--book-line-height` は端末任せ（`1em`・`normal`）。残り（余白・`--book-letter-spacing`・`--book-paper-scale`）は届かない（Kindle に紙面が無い） |
| 柱とノンブル | `--book-folio-font-size`・`-color`・`--book-folio-left-content`・`-right-content`・`-center-content` | `--folio-*` | `settings` | 届かない（Kindle に紙面が無い） |
| 見出しの印 | `--book-marker-h3`・`--book-marker-h4` | `--h4-marker` ほか | `settings`（テーマのオプション） | 届く |
| 会話 | `--book-talk-accent`・`-bg`・`-icon-size`・`-speaker-size` | `--talk-*` | `settings`・テーマ | 届く |

- 扉絵・節絵の変数（`--frontispiece-*`・`--section-bg-image`・`--section-title-font-size`）は、組み込みの機能（§3.4）が値を入れる変数で、名前は `--book-frontispiece-*`・`--book-ornament-*` とする（`--section-bg-image` は `--book-ornament-image`、`--section-title-font-size` は `--book-ornament-title-font-size`）。
- 使われていない変数（`--color-shadow`）は消す。
- 1 行ずつの一覧（`tokens.css`）に定義を置かないものが 4 種類ある。前書きと付録の色（`pages/preface.css`・`pages/appendix.css` がそのページの `:root` で定義する）、会話の色（`parts/talk.css` が `.talk` で定義する。要素ごとに値が違うので `:root` に上げない）、扉絵と節絵の画像（`book-settings.css` が必ず定義する）、アバターの大きさ（`talk.yml` から生成する）。一覧には注釈で置き場を書く。
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
/* themes/bunko-official/bridge.css（生成物） */
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
- 紙面の寸法と部品の一覧は、小説の仕様に書く。

---

## 7. 置き場・配布・更新

### 7.1 置き場

| 置き場 | 中身 | 誰が管理するか |
| :--- | :--- | :--- |
| 本の `themes/<名前>/` | その本が使えるテーマ。ビルドが読むのはここだけ | 雛形から来たものは `vs upgrade`、それ以外は著者 |
| gem の雛形（`lib/project_scaffold/themes/`） | 同梱のテーマ（`standard`・`bunko`・`picture`）。正典はリポジトリの直下の `themes/` | vs の開発（`ruby scripts/copy_to_scaffold.rb` で同期） |
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

`vs theme:check` は、テーマの CSS の中の外部の URL（`url(http…)`・`@import url(http…)`）も 🟡 で示す。組むたびにネットワークへ取りにいくテーマを、入れた時点で知らせるためである。

### 7.3 `vs upgrade` と著者のファイル

| ファイル | `vs upgrade` の扱い |
| :--- | :--- |
| `stylesheets/custom.css` | 触らない（今と同じ） |
| 雛形から来たテーマ（`config/scaffold.lock` に記録がある `themes/<名前>/`） | 今の雛形の更新と同じ（変更の無いファイルは置き換え、著者が変えたファイルは三方向のマージ。`upgrade-three-way-merge-spec.md`） |
| 著者が入れたテーマ（`scaffold.lock` に記録が無い） | 触らない。契約の版が今の vs に合わないときだけ 🟡 で知らせる |
| `vs theme:add` で入れた同梱のテーマ | `scaffold.lock` に記録し、雛形から来たテーマと同じに扱う |
| `stylesheets/` の土台と部品 | 今と同じ |

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
  2. `BodyClassInjector` と `BookSettingsCss` に、`standard` テーマに固有の名前（`vs-header-image`・`--frontispiece-*` など）を直接書いた箇所が無い（`theme.yml` と機能の宣言から来る）。
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
| S6-10 配色のテーマと `kindle_tokens:` | `kindle_tokens:` の書き出し（target 層の 2 番目）。材料の `standard-mono`。S6 の完了の確かめ | 完了の条件の 4・10。全部の比べ。`rake test:layout`・`rake test:standard`・`rake test:release` |

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

- 入口の実験（実装の前に行う）: 本書の章を 2 つ選び、`role` 属性の付いた契約 HTML に、`theme-bunko` と `theme-base` を §6.2 の形（`theme` 層・`bridge.css`）で当てて、Vivliostyle で PDF と EPUB を組む。確かめる点は次の四つ。(a) 縦書き・右綴じで組める。(b) 見出し・段落・ルビが `theme-bunko` の見た目になる。(c) vs の部品（脚注・囲み・図）が崩れない。(d) 判型が vs の `page.use` の値になる。結果を `v2-feasibility-notes.md` に追記する。
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
| 1 | 小説と絵本の既定のテーマの名前 | S8・S9 の仕様 | `bunko`・`picture` は仮 |
| 2 | 対応表（`bridge.css`）に載せる変数の一覧 | S7 の入口の実験 | 15 種ほどを見込む |
| 3 | テーマを探すための一覧（登録簿）を持つか | 2.0 の後 | 2.0 では作らない |
| 4 | `theme-epub3j` を土台にしたテーマを同梱するか（電書協の様式を求める著者向け） | S8 の仕様 | 2.0 では `theme-bunko` だけを確かめる |
| 5 | 部品に残した飾りの規則（§4 の「部品に残す飾り」）を `standard` へ移す範囲 | S8（`bunko` を書くとき） | S6 では見出しの 2 枚だけを移す。`bunko` で打ち消しが要った規則を移す。いちばんの候補は前書きの見た目（`parts/preface.css`） |

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
