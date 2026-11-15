# 平らな CSS で層の順が保てない組の扱い（Fable への相談）

> 作成日: 2026-11-15
> ステータス: **相談中**（答えが出たら、決定を `css-layer-restructure-spec.md` と `theme-contract-spec.md` へ移し、この文書は archives へ送る）
> 出自: S3-1（`css-layer-restructure-spec.md` §8）の実装中に見つかった設計の問い

Fable のセッションに、次の「---」より下をそのまま渡す。

---

2.0 の CSS の設計について、一つ判断をお願いします。S3-1（平らな CSS の生成）を実装している途中で見つかった問いです。S3-1 は EPUB と Kindle の見た目を変えない段階で、答えを待たずに完了できます。答えが効くのは、S3-2（出力先の規則を target 層へ移す）・S6（テーマの切り出し）・`vs theme:check` の検査の作り方です。

コードの書き換えはしないでください。読む資料は次の 3 つで足ります。

1. `css-layer-restructure-spec.md` §2.1（層の順序と理由）・§4.3（層を外しても結果が変わらないことの保証）・§10（S2-1〜S2-4 の実装記録）
2. `kindle-css-compatibility-notes.md` §2（KFX の CSS の対応表）
3. `theme-contract-spec.md` §3.5（テーマの CSS の決まり）

## 1. 問い

PDF は層のある CSS を読み、勝ち負けは層の順で決まる。EPUB と Kindle は層を外して層の順に並べた CSS を読む（KFX が `@layer` の中を捨てるため）。平らな CSS では、勝ち負けは詳細度で決まり、詳細度が同じときだけ並びの順で決まる。そのため、**下の層の詳細度の高い規則が、上の層の規則に勝つ**組が出る。

§2.1 の層の順の理由のうち、二つはこの「詳細度に関係なく層で勝つ」ことに頼っている。

- `theme` が `parts` の上にある理由:「層が上なら、詳細度が低い規則でも勝つ。テーマは詳細度を上げたり `!important` を使ったりせずに済む」
- `utilities` が `theme` の上にある理由: 著者が原稿に書いた `{.text-right}` などが、テーマの規則に負けないようにする

EPUB と Kindle では、この二つが成り立たない。§4.3 は、検査（`InversionCheck`）で組を挙げ、テーマを作る人が詳細度をそろえて直す、という扱いにしている。この扱いのままでよいか、それとも平らにするときに層の順を保つ仕組みを入れるか、を決めてほしい。

## 2. S3-1 で分かったこと

### 2.1 検査の判定の広さで、挙がる数が大きく変わる

§4.3 (c) の判定は「最後の複合選択子が同じクラスを含むか、どちらもクラスを持たず同じ要素名」である。同梱の CSS（`stylesheets/`・EPUB と Kindle の束・`book-settings.css` を除く）で数えた。

| 判定 | 静的に挙がる組 |
| :--- | ---: |
| §4.3 (c) のとおり | 8（3 種類） |
| 片方がクラスを持たない組も含める（`p.note` と `p`、`.part-title` と `body` など） | 842 |

(c) で挙がる 8 組は、どれも実際の本では起きないか、1.x の EPUB と同じ結果になるので、理由を書いた許可の表に載せた（`css_layer_test.rb` の `ALLOWED_INVERSIONS`）。広い判定の 842 組のほとんどは、著者の指定（`.aki`・`.aki2`・`.align-*`・`.text-*`。utilities 層）と、詳細度の高い部品の規則（`body.vs-header-simple h2`・`pre[class*="language-"]` など）の組である。

### 2.2 実際の HTML で起きる組は 4 組だけ

広い判定の組を、組み上がった HTML（本書の PDF 用 HTML・EPUB・Kindle 用 EPUB、B4 の EPUB）で絞った。両方の選択子に当たる要素がある組は 4 組で、**utilities 層の組は 0** だった（著者の指定のクラスが、部品の規則が選ぶ要素に付いていない）。4 組とも上の層は settings 層（`book.yml` から生成する `book-settings.css`）である。

| 層ありで勝つ規則（上の層） | 平らにすると勝つ規則（下の層） | 起きる場所 | 今の扱い |
| :--- | :--- | :--- | :--- |
| `body.vs-kindle strong { color: #15803d }`（settings） | `p:has(> strong:only-child):has(+ table) strong { color: var(--color-text) }`（parts） | Kindle の章 | KFX は `:has()` の規則を捨てるので、画面では settings の色になる |
| `body.vs-header-simple h2 { page-break-before: auto }`（settings） | `body.vs-header-simple.vs-kindle h2 { break-before: page }`（parts） | Kindle の付録 | Kindle は S2 の前から平らな CSS を読んでおり、付録の節の前で改ページしている。S3-2 で target 層へ移すと、層でも勝つ |
| `body { page-break-before: always }`（settings） | `.part-title { break-before: recto }`（pages） | 部扉（PDF・EPUB・Kindle） | **(c) では挙がらない**（片方がクラスを持つ）。層ありの PDF では S2-1 から settings が勝っている（1.x は詳細度で recto）。部扉は 1 枚ずつ組んで結合するので、本書の画素は変わっていない |
| `body { page-break-before: always }`（settings） | `body.toc { break-before: recto }`（pages） | 目次（PDF） | 同上 |

下の 2 組は、PDF と EPUB で勝つ側が違い、しかも §4.3 (c) の判定では見つからない。判定を広げても、HTML で絞れば数は手で読める大きさに収まる。

### 2.3 KFX は詳細度を上げた選択子を解しそう（画面では未確認）

平らにするときに上の層の詳細度を上げる案（下の §3 の B）が成り立つかを、`scripts/kfx_probe.rb` の 3 項目で測った（Kindle Previewer 4.0.4）。

| 項目 | CSS | 期待 | 中間生成物 |
| :--- | :--- | :--- | :--- |
| 対照 | `.t-ctl { 緑 } div p.t-ctl { 赤 }` | 赤（詳細度の高い後の規則） | 期待どおり |
| クラスの重ね | `.t-rep.t-rep.t-rep { 緑 } div p.t-rep { 赤 }` | 緑 | 期待どおり |
| 当たらないクラスの `:not()` の重ね | `p.t-not:not(.t-n1):not(.t-n2) { 緑 } div div p.t-not { 赤 }` | 緑 | 期待どおり |

変換の中間生成物は、変換器の前処理（Chromium）が解いた値であり、KFX の描画が捨てる規則を映さないことがある（`kindle-css-compatibility-notes.md` §2.1）。画面での確認は、必要なら Opus が行う。

## 3. 考えられる案

| 案 | 中身 | 得るもの | 失うもの |
| :--- | :--- | :--- | :--- |
| A. 今の仕様のまま | 平らな CSS は詳細度で決まると割り切る。検査で組を挙げ、vs の CSS は直すか許可の表に載せ、テーマを作る人には `vs theme:check` が 🟡 で知らせる | 生成が単純。出力の CSS が読める | テーマを作る人が、部品の詳細度に合わせて選択子を書く必要がある（§2.1 の理由が EPUB と Kindle では成り立たない） |
| B. 平らにするとき、上の層の詳細度を上げる | 各層の規則の選択子に、当たらないクラスの `:not()` を層の位置に応じた数だけ足し、詳細度の順が層の順と同じになるようにする（PostCSS の cascade-layers が `:not(#\#)` で行うことを、KFX が解する形で行う） | PDF と EPUB と Kindle で勝ち負けが同じになる。テーマを作る人は層だけ考えればよい | 選択子が長くなる（下の層の詳細度の最大値 × 層の数）。実測の最大は、parts 層がクラス 7（`[0,7,2]`・コードの行番号の規則）、pages 層が **id を含む** `#toc li.toc-section > .toc-title::after`（`[1,2,2]`）。クラスの `:not()` では id に勝てないので、id の `:not(#…)` を使うか（KFX での扱いは未測定）、`#toc` の規則を書き直す必要がある。`!important` と層の外（`custom.css`）の扱いも決める必要がある。KFX の描画での確認が要る |
| C. B を一部の層だけに | 「詳細度に関係なく勝つ」ことに頼る層（`theme`・`utilities`、必要なら `settings`・`target`）だけを上げる | B より出力が短い | 層ごとに扱いが違い、仕組みの説明が増える |

あわせて、§4.3 (c) の判定の広さも決めてほしい。2.2 のとおり、(c) は実際に起きる組を見落とす。広い判定にして、ビルドでは組み上がった HTML で絞る形にすれば、数は小さい。ただ、テストは HTML なしの静的な検査なので、広い判定では許可の表が 842 組になる。テストの側の扱いも含めて決めてほしい。

## 4. 答えてほしいこと

1. A・B・C のどれにするか（ほかの案でもよい）。B か C なら、`!important`（今は層の中に 0 か所）と層の外の規則をどう扱うか
2. §4.3 (c) の判定の広さと、テスト・ビルド・`vs theme:check` のそれぞれで、何を報告するか
3. 2.2 の部扉と目次の `break-before` を直すか。直すなら、settings 層の側で打ち消す（S2-1 の本扉・権利ページ・奥付と同じ `CHAPTER_PAGEBREAK_EXEMPT_SELECTORS`）か、ほかの方法か
4. 決めたことを入れる段階（S3-2・S3-3・S6 のどこか）
