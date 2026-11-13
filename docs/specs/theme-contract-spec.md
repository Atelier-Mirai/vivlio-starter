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
| 部扉 | `doc-part` | 部扉の最上位の要素 |
| 奥付 | `doc-colophon` | 奥付の最上位の要素 |
| 索引 | `doc-index` | 索引の最上位の要素 |
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
  theme.css          組版のテーマの入口（配色のテーマには無い）
  *.css              theme.css から @import する部品（分け方は自由）
  kindle.css         任意。Kindle だけに当てる構造の劣化
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

tokens:                      # 公開する変数の値（§5）。--book- を除いた名前で書く
  color-accent: "#15803d"
  color-link: "#000"

options:                     # 著者が book.yml の theme: で変えられる項目（§3.3）
  color:
    type: color
    default: green
    token: color-accent
  style:
    type: enum
    values: [image, simple]
    default: image
    body_class: { image: vs-header-image, simple: vs-header-simple }

styles:                      # 読み込む CSS（順に theme 層へ入る）
  - theme.css
```

`theme.yml` の読み込みと検査は `lib/vivlio_starter/cli/theme/manifest.rb` に置く。知らないキーは 🟡 で知らせて無視する（後の版のテーマを前の版の vs で開いた場合に止めないため）。

### 3.2 二段のテーマ

エディタのカラーテーマのように、値だけを差し替えるテーマを作れるようにする。形式は一つで、何を書くかで段が決まる。

| 段 | 書くもの | 例 | Kindle |
| :--- | :--- | :--- | :--- |
| **配色のテーマ** | `theme.yml` の `extends:` と `tokens:` だけ。CSS を持たない | `standard` を土台に、12 色とは別の配色・書体の組を配る | 値は CSS の生成がリテラルに解くので、必ず通る |
| **組版のテーマ** | `styles:` の CSS・画像・書体 | 章扉の形・見出しの組み方・柱とノンブルの置き方を変える | テーマの CSS が §3.5 の範囲に収まっていれば通る |

- `extends:` は 1 段だけとする（土台のテーマがさらに `extends:` を持つことは認めない）。読み込みの順は、土台の `tokens` → 土台の `styles` → 自分の `tokens` → 自分の `styles`。
- 土台のテーマも本の `themes/` に無ければならない（§7）。`vs theme:add` は、`extends:` の先が無ければ一緒に入れるか、無いと知らせる。
- 配色のテーマは壊れようが無い（組版に触れない）ので、配る側も使う側も負担が小さい。今の「`custom.css` で 12 色を変える」は、配色のテーマを自分の本だけで使っていることに当たる。`custom.css` はそのまま使える（§7.3）。

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
- 値は、ビルドのときに `settings` 層の CSS（今の `book-settings.css`）へ書き出す。どの変数へ渡るかは `token:` が決めるので、vs の側にテーマごとのコードは要らない。
- `standard` テーマの `heading_chars`・`lead_chars`（字数から幅を求める）のように、計算が要るオプションは、`features:` の組み込みの機能の設定として扱う（§3.4）。テーマが自分で計算を持つことはできない（コードを持たないため）。
- 値の検査（型・範囲・`values:`）は `theme.yml` の宣言から行い、外れたら 🟡 で、使える値を示す（`vs build` と `vs preflight` の両方）。

### 3.4 組み込みの機能（`features:`）

見出しに画像を合成する処理のように、CSS だけでは作れず、vs のコード（Ruby）が要るものは、vs の本体に「組み込みの機能」として残す。テーマは、使うものを `features:` に書く。

| 機能 | 中身（今のコード） | オプション（`standard` で今あるキー） |
| :--- | :--- | :--- |
| `frontispiece` | 章扉の扉絵。`prepare theme images`・`HeadingImageComposer`・EPUB と Kindle の見出しの画像・`check chapter leads` | `frontispiece.image`・`edge_inset`・`heading_offset`・`heading_chars`・`lead_chars`・`lead_size` |
| `ornament` | 節見出しの節絵 | `ornament.image`・`heading_chars` |

- 機能を使うテーマは、その機能のオプションを自分の `options:` に並べずに使える（機能の側が宣言を持つ。`lib/vivlio_starter/cli/theme/features/<名前>.rb`）。
- 機能を使わないテーマでは、その機能の段は走らず、オプションは `theme:` 節に書けない（書いてあれば §3.3 の「このテーマには無い設定」の 🟡）。
- 2.0 で用意する機能はこの二つだけとする。小説と絵本のテーマが必要とする処理は、個別の仕様で、機能として足すかを決める。機能を足すのは vs の本体の変更で、テーマの側からは足せない。

### 3.5 Kindle で組むための CSS の範囲

`supports.targets` に `kindle` を含めるテーマの CSS は、次の範囲で書く。範囲の外の書き方は、Kindle 用の CSS の生成が解けず、その宣言か規則を落として 🟡 で知らせる（`css-layer-restructure-spec.md` §4.5）。

| 書き方 | 扱い |
| :--- | :--- |
| 変数の定義 | `:root`・`html`・`body`・`body.<ページの種類>` でだけ行う。それより深い要素で定義し直した変数は、Kindle 用に解けない |
| `var()`・`color-mix()`・単位のそろった `calc()` | 使ってよい（生成がリテラルに解く） |
| `:is()`・`:where()` | 選ぶ対象の並びとして使う場合は、生成が並びに展開する。入れ子の深い使い方は避ける |
| `:has()` | Kindle では解けない。使った規則は Kindle に届かない |
| CSS の入れ子（`&`） | 使わない（2.0 の生成は入れ子を展開しない） |
| 層の中の `!important` | 使わない（`css-layer-restructure-spec.md` §2.4） |
| `display: grid`・`flex`・疑似要素の位置指定 | 使ってよいが、Kindle では `block` になる。崩れる部品は `kindle.css` に代わりの組み方を書く（`kindle-css-compatibility-notes.md` §2） |

`vs theme:check <名前>`（§7.2）が、この範囲を検査して報告する。

---

## 4. 標準のテーマ

今の見た目を `themes/standard/` に切り出す。切り出しの前後で、本書の四つの出力先の出力が変わらないことを完了の条件とする（§9 の S6）。

| 今の置き場 | 行き先 |
| :--- | :--- |
| `stylesheets/theme.css`（色と寸法の変数） | `themes/standard/theme.yml` の `tokens:` と、`themes/standard/theme.css` |
| `simple-header.css`・`image-header.css` | `themes/standard/` |
| 章・前書き・付録の本文の見た目（`chapter-common.css`・`preface.css`・`appendix.css` のうち、色・書体・余白・飾り） | `themes/standard/`。どの規則がテーマでどの規則が部品かの線引きは `css-layer-restructure-spec.md` §3 |
| `stylesheets/images/`（扉絵・節絵の花の画像） | `themes/standard/images/` |
| `book.yml` の `theme:` 節のキー | `themes/standard/theme.yml` の `options:` と、`features:` の機能の宣言 |
| `ThemeColor`（12 色の名前と値） | 12 色は `--book-accent-*` として vs の土台が持つ（§5.2）。テーマではなく、どのテーマからも使える色の名前とする |

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

### 5.2 公開する変数の一覧（分類）

1 行ずつの一覧は S6 で `stylesheets/tokens.css` に置き、そこを正典とする。分類と、今の名前からの対応を示す。

| 分類 | 新しい名前 | 今の名前 | 値を入れる側 |
| :--- | :--- | :--- | :--- |
| テーマ色の 12 色 | `--book-accent-yellow` … `--book-accent-lime` | `--accent-*` | vs の土台 |
| 本のテーマ色 | `--book-color-accent`・`--book-color-accent-preface`・`--book-color-accent-appendix` | `--theme-accent`・`--color-preface-accent`・`--appendix-accent-color` | `settings`（テーマのオプション） |
| 色 | `--book-color-text`・`-link`・`-strong`・`-em-underline`・`-border`・`-border-weak`・`-column-bg`・`-column-border`・`-figure-border`・`-danger`・`-mark`・`-heading`・`-section-number` | `--color-*`・`--heading-accent`・`--section-number-color` | テーマ |
| 書体 | `--book-font-body`・`-heading`・`-column`・`-code`・`-folio`・`-title` | `--font-main-text`・`--font-header`・`--font-column`・`--font-code`・`--font-folio`・`--font-title` | `settings`（`typography`） |
| 版面 | `--book-page-margin-top`・`-bottom`・`-inner`・`-outer`・`--book-font-size`・`--book-line-height`・`--book-letter-spacing`・`--book-paper-scale` | `--page-margin-*`・`--base-font-size`・`--base-line-height`・`--letter-spacing`・`--paper-scale` | `settings`（判型のプリセット） |
| 柱とノンブル | `--book-folio-font-size`・`-color`・`--book-folio-left-content`・`-right-content`・`-center-content` | `--folio-*` | `settings` |
| 見出しの印 | `--book-marker-h3`・`--book-marker-h4` | `--h4-marker` ほか | `settings`（テーマのオプション） |
| 会話 | `--book-talk-accent`・`-bg`・`-icon-size`・`-speaker-size` | `--talk-*` | `settings`・テーマ |

- 扉絵・節絵の変数（`--frontispiece-*`・`--section-bg-image`・`--section-title-font-size`）は、組み込みの機能（§3.4）が値を入れる変数で、名前は `--book-frontispiece-*`・`--book-ornament-*` とする。
- 使われていない変数（`--color-shadow`）は消す。
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

- 配布の形は「テーマのディレクトリ」だけを決め、経路は限定しない。git のリポジトリ・zip・npm のどれで配っても、`vs theme:add` が本の中へ複製する。配る側は、ディレクトリを公開するだけでよい。
- `vs theme:add` が外から取得するのは CSS・画像・書体・YAML だけで、スクリプトは実行しない（npm のパッケージは `npm pack` で取得し、`install` のスクリプトを走らせない）。
- テーマの一覧の場所（探すための登録簿）は 2.0 では作らない。

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

- 作るもの: §3 の `theme.yml` の読み込みと検査、§3.3 のオプションの書き出し、§3.4 の機能の宣言、§4 の切り出し、§5 の変数の名前の変更と別名、§7.2 のコマンド、§7.3 の `vs upgrade` の扱い、§8 の版の検査。
- 完了の条件:
  1. `stylesheets/theme.css`・`simple-header.css`・`image-header.css`・`stylesheets/images/` が無くなり、`themes/standard/` にある。
  2. `BodyClassInjector` と `BookSettingsCss` に、`standard` テーマに固有の名前（`vs-header-image`・`--frontispiece-*` など）を直接書いた箇所が無い（`theme.yml` と機能の宣言から来る）。
  3. 本書の四つの出力先の出力が、S0 の基準と比べて、PDF は全ページの画素が一致、Kindle は Kindle Previewer の画面が見比べて同じ。
  4. 配色のテーマの見本（`themes/standard-mono/`。`extends: standard` と `tokens:` だけ）で本書を組み、色だけが変わる（PDF の文字の位置が `standard` と一致する。`pdftotext -bbox` の座標の比較）。Kindle でも色が変わる。
  5. 1.x の `custom.css`（今の名前の変数を使ったもの）を置いた写しで、色の変更が効く。
  6. `theme.name` に無い名前を書くと 🔴、`contract: 2` のテーマを置くと 🔴、`supports.writing_mode` に無い組方向で 🔴 になり、それぞれ次にすることを示す。
- 確かめ方: 3 は `v2-migration-plan.md` §3。4〜6 はテストと、写しの本での実行。

### S7 公式テーマの取り込み

- 入口の実験（実装の前に行う）: 本書の章を 2 つ選び、`role` 属性の付いた契約 HTML に、`theme-bunko` と `theme-base` を §6.2 の形（`theme` 層・`bridge.css`）で当てて、Vivliostyle で PDF と EPUB を組む。確かめる点は次の四つ。(a) 縦書き・右綴じで組める。(b) 見出し・段落・ルビが `theme-bunko` の見た目になる。(c) vs の部品（脚注・囲み・図）が崩れない。(d) 判型が vs の `page.use` の値になる。結果を `v2-feasibility-notes.md` に追記する。
- 実験で (a)〜(d) のどれかが成り立たない場合: 取り込みを「CSS を写すだけで、結果は保証しない」に下げ、`vs theme:add` の npm の経路は 2.0 に含めない、という判断をユーザーに仰ぐ。小説の既定のテーマは vs が書く（§6.4）ので、2.0 の小説の出力はこの実験の結果に左右されない。
- 作るもの: `vs theme:add` の npm の経路、§6.2 の変換、§6.3 の `bridge.css` の生成。
- 完了の条件: `vs theme:add @vivliostyle/theme-bunko` の後、`theme.name` を替えるだけで、小説の見本の本が `pdf`・`print_pdf`・`epub` で組める。`targets` に `kindle` があると、`v2-architecture-spec.md` §2.5 の検査が 🔴 で止め、対応するテーマを示す。

---

## 10. 論点（未決）

| # | 論点 | 答えが要る時点 | 設計での扱い |
| :--- | :--- | :--- | :--- |
| 1 | 小説と絵本の既定のテーマの名前 | S8・S9 の仕様 | `bunko`・`picture` は仮 |
| 2 | 対応表（`bridge.css`）に載せる変数の一覧 | S7 の入口の実験 | 15 種ほどを見込む |
| 3 | テーマを探すための一覧（登録簿）を持つか | 2.0 の後 | 2.0 では作らない |
| 4 | `theme-epub3j` を土台にしたテーマを同梱するか（電書協の様式を求める著者向け） | S8 の仕様 | 2.0 では `theme-bunko` だけを確かめる |
