# 縦書きの小説（縦書きの経路・テーマ `novel`・判型・記法・lint・雛形）

> 作成日: 2026-11-17
> ステータス: **実装中**（段階 S8。S8-1・S8-2 は 2026-11-19、S8-3 は 2026-11-20、S8-4 は 2026-11-21 に完了。実装記録は §10）
> 対象: 縦書きの小説を `pdf`・`print_pdf`・`epub`・`kindle` の四つで組むための、縦書きの経路・既定のテーマ `novel`・判型のプリセット・記法・小説の lint・雛形 `scaffolds/novel/`
> 出自: `v2-s8-novel-consultation.md` §4（2026-11-17・Fable）。段階の順と判断の線は `v2-plan-review-consultation.md` §4 で調整した（§2.5 の Kindle の論理方向）
> 組になる仕様書: `v2-architecture-spec.md`（種類と軸・`BookProfile`・記法の型）・`theme-contract-spec.md`（テーマの形・契約 HTML）・`css-layer-restructure-spec.md`（§6 の物理方向）・`v2-migration-plan.md`（段階の順・基準・判断の線）。S8 から分けた背表紙・くるみ表紙は `cover-spread-spec.md`（S8b）、`vs furigana` は `furigana-spec.md`（S8c）

---

## 0. 決定の一覧

| # | 問い | 決定 | 節 |
| :--- | :--- | :--- | :--- |
| 1 | 小段階 | S8-1〜S8-7 の 7 つ。S8-1・S8-2・S8-4・S8-5 は本書の出力を r3 と比べる | §8.1 |
| 2 | S8 から分けるもの | 背表紙・くるみ表紙（S8b）と `vs furigana`（S8c）は、S8 の後の独立した段階にする。互いに順不同。S11b の前に終える | §1.2 |
| 3 | S7 との順 | S7a（入口の実験）→ S8 → S7b（git と npm の経路・`bridge.css`） | §1.2 |
| 4 | テーマの名前 | `novel`。公式テーマを取り込んだものは `vivliostyle-<名前>`（`vivliostyle-bunko`） | §3.1 |
| 5 | テーマの中身 | `supports.writing_mode: [vertical]`。`features:` は空。オプションは最初は置かない | §3.2 |
| 6 | 部品 | 3 段に分ける。縦で保証する部品・横組みの箱として置く部品・縦書きでは使えない部品（🟡）。前書きの飾りは `standard` へ移す | §3.4 |
| 7 | ページの種類 | 奥付と権利ページは横組み、ほかは縦組み。縦書きでは索引と用語集を作らない（🟡） | §2.2 |
| 8 | 節の改ページ | `BookProfile` の `novel` に `page.section_pagebreak: false`・`page.chapter_pagebreak: any`。テーマの `tokens:` には書かない | §4.3 |
| 9 | `theme-epub3j` | 同梱しない | §3.5 |
| 10 | 判型 | 文庫（A6）・B6・新書・四六の 4 つを足す。既定は `bunko_standard`。版面の決め方は今の形のまま。行数と字数のキーは足さない | §4 |
| 11 | 縦中横の自動 | 半角の数字 1〜2 桁と、半角の `!?`・`?!`・`!!`・`??`。3 桁以上は包まず、lint が知らせる | §5.3 |
| 12 | 投稿サイトの記法 | 縦棒あり（半角・全角）・縦棒なし（読みが仮名だけのとき）・`《《…》》`・`|《` の打ち消しを受ける。括弧のルビは受けない | §5.4 |
| 13 | 字下げ | CSS が字下げする。投稿サイトの記法を読む前処理が、段落の頭の全角空白 1 つを落とす。括弧で始まる段落には vs が印を付け、テーマが字下げを 0 にする | §6.1 |
| 14 | 確かめ | 機械で見る条件 8 つと、目で見る 12 か所。小説の基準 N1 を S8 の完了で作る（r4） | §8.2・§8.3 |
| 15 | 書体の埋め込み | 2.0 の後へ回す | §9 |
| 16 | Kindle の論理方向 | 手で書き直す箇所が 20 以下なら `targets/kindle.css` に物理方向で書き、20 を超えたら `LiteralResolver` で書き直す（相談しない） | §2.5 |

---

## 1. 範囲と前提

### 1.1 すでに決まっていること（4 本の仕様書から）

- 小説も `pdf`・`print_pdf`・`epub`・`kindle` の四つで出す。目指す紙面は Vivliostyle の公式の縦書きの作例（「銀河鉄道の夜」）に、ときどき挿絵を入れた形（`v2-design-research-brief.md` §5）。
- 小説の既定のテーマは vs が `theme-contract-spec.md` §3.5 の範囲の CSS で書く。手本は `theme-bunko` と `theme-epub3j`（どちらも CC0-1.0）。挿絵の `figure` と余白の箱は `writing-mode: horizontal-tb`（`theme-contract-spec.md` §6.4）。
- `BookProfile` の `novel` の既定値は、`writing_mode: vertical`・`heading_numbering: none`・`index_glossary.enabled: false`・`lint.ruleset: novel`・`metrics.use: none`・`notation.web_novel: true`（`v2-architecture-spec.md` §2.2）。この仕様書で `theme.name`・`page.use`・改ページの 2 つを足す（§4.3）。
- コードは `book.type` を読まない。分岐は軸か機能のキーで書く（`v2-architecture-spec.md` §2.3）。縦中横の自動は「組方向が縦なら」で入れる。
- 2.0 に含める 5 件の型と入れる場所は `v2-architecture-spec.md` §7.1 の表のとおり。傍点 `[文字]{.sesame}`・縦中横 `[12]{.tcy}`（D 型の行内の属性）、縦中横の自動（L3 の後処理・`traits.vertical?`）、投稿サイトの記法（前処理 `transform_web_novel_marks!`。`vs import` にしない）、小説の lint（`lint.ruleset: novel`）、`vs furigana`、背表紙とくるみ表紙。
- クラス名 `tcy`・`sesame` は `vs-` を付けない（`theme-contract-spec.md` §2.5）。
- 物理方向の 72 か所は、縦書きの本が読む部品について論理方向へ直す。横書きでは結果が同じなので、本書の画素が変わらないことを確かめにする（`css-layer-restructure-spec.md` §6）。
- 雛形は `scaffolds/novel/`（それ自体が組める本）。`vs new mybook --type novel`（`v2-architecture-spec.md` §2.6）。
- 行内の属性の記法（D 型）は、S8-2 で `v2` に作る。1.1.0 は出さず、master には作らない（`v2-migration-plan.md` §6.3）。

### 1.2 S8 の範囲と、分けたもの

- S8 は、縦組みの本文（経路・テーマ・部品）と、5 件のうち 3 件（傍点と縦中横・投稿サイトの記法・小説の lint）を作る。
- **背表紙・くるみ表紙（S8b）と `vs furigana`（S8c）は分ける。** どちらも縦書きの経路にもテーマにも触れない。S8 の完了の条件（小説が四つの出力先で組める）に入れると、小説の基準を作る時期が遅れる。2.0 に含めることは変えない。S8 の完了の後から S11b の前までの間なら、どこに置いてもよい（`v2-migration-plan.md` §2.2）。
- **S7 との順。** S7a（`theme-bunko` を vs の契約 HTML に当てて縦に組む入口の実験）は S8 の前に行う。vs の部品が縦書きでどう崩れるかを最初に見せるので、§3.4 の「部品の 3 段」の表を確かめる材料になる。S7b（git と npm の経路・`bridge.css` の生成）は小説の出力に要らないので、S8 の後に回す。

---

## 2. 縦書きの経路

### 2.1 組方向を書く場所

- **組方向を書くのは vs で、テーマではない。** テーマは `supports:` で対応する組方向を宣言するだけにする。組方向は軸（`page.writing_mode`）で、テーマを替えても変わらない値だからである。
- **書く場所は `stylesheets/base/vertical.css`（base 層）で、`EntryWriter` が、`traits.vertical?` の本の「縦に組むページの種類」（§2.2）の入口にだけ入れる。** 中身は `:root { writing-mode: vertical-rl; }` と、EPUB 向けの接頭辞つきの同じ宣言（`-webkit-writing-mode`・`-epub-writing-mode`）である。
- 横組みの箱（§3.4）の規則は `stylesheets/parts/vertical.css` に置き、本文の部品を読む種類の入口の parts 層の最後で読む（S8-4 で決めた。§10.4 の「仕様に無かったので決めたこと」の 1）。
- `book-settings.css` に書かないのは、全部の種類が同じ 1 枚を読み、settings 層がページの CSS（pages 層）に勝つので、横に組むページで打ち消せないためである。入口は種類ごとに作っているので、入れる・入れないで分けるのがいちばん単純で、詳細度の取り合いが起きない。

### 2.2 ページの種類ごとの組方向

| ページの種類 | 縦書きの本での組方向 | 理由 |
| :--- | :--- | :--- |
| 章・付録・前書き・後書き・本扉・部扉・目次・全巻目次 | 縦 | |
| 奥付・権利ページ | 横 | URL・英数字・版の表記が中心で、縦書きの本でも横に組むのが普通である。今の CSS がそのまま使える |
| 索引・用語集 | 作らない | 縦書きの本の索引は、横組みにして巻末から逆向きに綴じる形が要り、2.0 では扱わない。`page.writing_mode: vertical` と `index_glossary.enabled: true` の組み合わせは、`TraitCombinationCheck` が 🟡 で「縦書きでは索引と用語集のページを作りません」と示し、段を止める（固定レイアウトの行と同じ形） |

- **確かめた（S8-4）。** 1 冊の中に縦の文書と横の文書（奥付・権利ページ）が混ざる形は、そのまま組める。材料の本で、権利ページが横に組まれ、ページは右から左へ進み（PDF の `Direction` は `R2L`）、奇数ページのノンブルが左に来た（§10.4）。

### 2.3 余白の箱

- `base/page.css` の余白の箱（柱とノンブル）の規則に `writing-mode: horizontal-tb` を足す。横書きでは何も変わらないので、条件を付けずに書く。
- ノンブルは算用数字のまま横に組む。漢数字にはしない。

### 2.4 EPUB と Kindle

- **OPF** は `v2-architecture-spec.md` §2.4 の表のとおり（`spine` の `page-progression-direction="rtl"`、Kindle は `primary-writing-mode` の `meta`）。
- **EPUB と Kindle 向けの接頭辞つきの書き方**（`-webkit-text-combine`・`-webkit-text-emphasis` など）は、`parts/inline.css` に、標準の書き方の前の行として手で書く。生成で足す仕組みは作らない（対象が 3 つのプロパティだけのため）。

### 2.5 Kindle の論理方向

Kindle が論理方向のプロパティを正しく解するかは、S8-1 と S8-4 の材料の本を KPF にして、中間生成物で見る（`css-layer-restructure-spec.md` §9 の論点 2）。

- 崩れた箇所を手で書き直す数が 20 以下なら、`novel` と `targets/kindle.css` に物理方向で書く。
- **20 を超えたら、`LiteralResolver` で論理方向を物理方向に書き直す（相談しない）。** 縦書きの本では、組方向から物理方向を決める表を `LiteralResolver` に持たせる。
- どちらを選んだかと数を、実装記録に書く。
- 出どころ: `v2-plan-review-consultation.md` §4.4 の 3。小説の答え（`v2-s8-novel-consultation.md` §4.4）は「20 を超えたら相談する」としていたが、後の答えが名指しで置き換えた（`v2-migration-plan.md` §4.1 の「答えの食い違い」の 1）。

---

## 3. 小説のテーマ `novel`

### 3.1 名前

`novel` にする。`bunko` は文庫という判型の名前で、このテーマは新書や四六判でも使う。公式テーマを取り込んだものとも区別がつく。公式テーマの側は、パッケージの名前 `@vivliostyle/theme-<x>` から `vivliostyle-<x>` を作る（`theme-contract-spec.md` §6.2）。

### 3.2 形

```yaml
# themes/novel/theme.yml
name: novel
title: 小説（縦書き）
version: 2.0.0
contract: 1
supports:
  writing_mode: [vertical]
  layout: [reflowable]
features: []
tokens:            # standard と違う値だけ（§3.3）
styles:
  - prose.css      # 段落・会話文・引用・区切り・挿絵
  - headings.css   # 章題・節題・本扉・目次の見た目
  - page.css       # 柱とノンブルの見た目
```

- **`supports.writing_mode` は `[vertical]` だけ。** CSS は論理方向で書くので横書きにも開けるが、2.0 では確かめる面を増やさない。横書きの小説は、`book.type: novel`・`page.writing_mode: horizontal`・`theme.name: standard`・`theme.style: simple` で組める（`v2-architecture-spec.md` §2.3 の「種類の既定値から軸を一つ変えた本」）。
- **`features:` は空。** 挿絵は CSS だけで組めるので、機能にしない。
- **`options:` は最初は置かない。** S8-5 で紙面を見て、著者が変えたくなる項目が出たら足す。候補は柱の中身（章題・書名・無し）だけである。色は `custom.css` と配色のテーマで変えられる。迷う項目は足さない（足すのは後からできるが、消すのは契約の変更になる）。足したら著者から見える名前なので、了承待ちの一覧に載せる（`v2-migration-plan.md` §4.1）。
- **出力先の CSS**（`epub.css`・`kindle.css`）は、要る規則が出たときに置く。
- **会話文の字下げ。** 手本の `theme-bunko` は `hanging-punctuation: first allow-end` で行っている。この書き方は EPUB と Kindle に届かないので、`novel` は使わず、括弧の段落の印（`p.vs-open-bracket`。§6.1）に `text-indent: 0` を当てる。開き括弧の字は左半分（縦では上半分）が空いているので、見た目は二分下げになり、三つの出力先で同じになる。行末の句読点のぶら下げ（`allow-end`）は PDF だけに `prose.css` で書いてよい（届かない出力先では、ぶら下がらないだけで崩れない）。

### 3.3 `tokens:`

`stylesheets/tokens.css` の中立の既定値は動かさない。`novel` は違う値だけを書く。値は S8-5 で紙面を見て決める（了承を後で得る）が、向きは次のとおりとする。

| 変数 | `novel` の向き |
| :--- | :--- |
| 見出しの書体 | 本文と同じ明朝（太さで区別する） |
| テーマ色と見出しの色 | 黒に近い色（飾りの色を使わない） |
| 行送り | 判型のプリセットの値をそのまま使う（テーマでは書かない） |
| 章リードの倍率・見出しの印 | 使わない（印は空の文字列） |

### 3.4 部品の 3 段

小説の本文の入口は、技術書と同じ部品の束を読む（読む部品を種類で減らさない。小説にコードを載せる著者を妨げない）。そのうえで、縦書きで何を保証するかを 3 段に分ける。

| 段 | 部品 | 扱い |
| :--- | :--- | :--- |
| 縦で保証する | 段落・見出し・ルビ・傍点・縦中横・強調・リンク・引用・区切り線・箇条書き・脚注・`@pagebreak`・相互参照の印・章リード・節リード | S8-1 で論理方向へ直し、S8-5 で `novel` の見た目を決める。§8.2 の目で見る箇所に入れる |
| 横組みの箱として置く | 図と挿絵・表・コード・数式（ブロック）・Mermaid の図・囲み（`.note` など）・出力例 | 箱に `writing-mode: horizontal-tb` を指定する（`stylesheets/parts/vertical.css` にまとめて書く）。保証は「箱の中が横組みで崩れずに読める」まで。箱の幅は版面の幅から前後の空きを引いた値に定める（幅を中身に合わせると、Vivliostyle が次のページへ送らない。§10.4）。著者が挿絵に幅を書けば、その幅になる。版面の高さを超える箱は下が切れる。行内のコードと行内の数式は、横倒しのまま（欧文と同じ扱い） |
| 縦書きでは使えない | 左右に並べる記法（side-by-side）・book-card・表の回転 | 原稿に書いてあれば 🟡 で場所を示す（`Guards::VerticalPartsCheck`。原稿の場所を指す指摘）。組み上がりは保証しない。一覧は S8-4 の材料の本で確かめて確定した（判断の軸: 「崩れずに読める」か。会話のアバター・行番号つきのコードの折り返しの印・サイドイメージ・画像と字を並べる記法は崩れずに読めたので、🟡 にしない。§10.4） |

- **脚注**は、Vivliostyle の `float: footnote` のまま使う。縦書きではページの左端（行の進む先の端）に組まれる。合印と注番号は縦中横にする（`theme-bunko` と同じ）。EPUB と Kindle は今の脚注の変換のまま。S8-4 の材料の本で、3 つの出力先の脚注を見る。
- **前書きの飾り（`parts/preface.css`）は `standard` へ移す**（S8-5。`theme-contract-spec.md` §10 の論点 5）。小説の前書きと後書きは本文と同じ見た目で組むので、部品に残すと `novel` が全部を打ち消すことになる。移すのは飾りの規則だけで、構造の規則（S2-4 でそろえた部分）は部品に残す。ほかの部品の飾りは、`novel` を書いて打ち消しが要ったものだけを移す。移した規則は、この節に表で記録する。移すたびに本書を基準と比べる。
- **目次**は縦に組み、ページ番号は算用数字を縦中横にする（3 桁まで 1 字分に収める。`text-combine-upright: all`）。相互参照が作る番号（「第 3 章」など）も同じにする。

### 3.5 `theme-epub3j` は同梱しない

電書協の様式は EPUB の作り全体（ファイルの分け方・OPF・クラスの体系）の決まりで、CSS を土台にしても「電書協の様式の EPUB」にはならない。vs が合わせるのはクラス名（`tcy`・`sesame`）までとする。要望が出たら、S7b の経路で `vs theme:add @vivliostyle/theme-epub3j` として取り込める。

---

## 4. 判型のプリセットと `BookProfile`

### 4.1 足す判型

`Common::PAGE_SIZES` に 4 つ足し、`config/page_presets.yml` に次のプリセットを足す。

| プリセット | 判型 | 寸法 | 目安（字数 × 行数。縦書き） |
| :--- | :--- | :--- | :--- |
| `bunko_standard`・`bunko_custom` | 文庫（A6 と同じ寸法） | 105 × 148 mm | 9pt・38 字 × 15〜16 行 |
| `b6_standard`・`b6_custom` | B6 | 128 × 182 mm | 9.5pt・42 字 × 17 行前後 |
| `shinsho_standard` | 新書 | 103 × 182 mm | 9pt・2 段にしない。44 字 × 15 行前後 |
| `shiroku_standard` | 四六 | 127 × 188 mm | 9.5pt・43 字 × 17 行前後 |

- `novel` の既定は `bunko_standard`。同人誌の小説でいちばん多い判型で、`v2-architecture-spec.md` §2.2 の仮の値のままである。
- 値（字の大きさ・行送り・四つの余白）は、S8-3 で Opus が上の目安から求め、S8-5 で `novel` を当てた紙面をユーザーが見て確定する。
  - 求め方は「天と地の余白の和 ＝ 紙の高さ − 字の大きさ × 字数」「ノドと小口の和 ＝ 紙の幅 −（行送り ×（行数 − 1）＋ 字の大きさ）」で、版面が字の大きさの整数倍になるように余白を決める。
  - ノドは 13mm 以上にする（無線綴じで読める幅）。
- `airy`・`compact` は小説には置かない（行数を変えたい著者は `*_custom` を使う）。

### 4.2 版面の決め方は今の形のまま

行数と字数のキーは足さない。

- 紙の寸法が決まっていれば、「字数と行数」と「余白」は同じ値の二つの言い方である。両方をキーにすると、どちらが勝つかの決まりが要り、著者が片方だけを直して食い違う。
- 印刷所が確かめるのは余白（とくにノド）なので、正典は余白の側に置く。
- `theme-bunko` が行数と字数から求めるのは紙の寸法のほう（紙が版面にぴったりの大きさになる）で、vs の「紙の寸法は判型で決まる」とは向きが逆である。
- 代わりに、縦書きの本では、`vs build --log` と `vs preflight` が版面の字数と行数を 1 行で示す（💡「版面: 38 字 × 16 行」）。`*_custom` で余白を変えた著者が、結果を数で確かめられる。字数が整数にならないとき（端数が 0.2 字以上）は、同じ行で天地の余白の直し方を示す。
- 行数と字数で指定するキーは、要望が出たら足す（`PLANNED.md`）。

**余白の名前は変えない。** `margin_top`・`margin_bottom`・`margin_inner`・`margin_outer`（天・地・ノド・小口）は紙の上の位置の名前で、組方向に依らない（`css-layer-restructure-spec.md` §6 の表の 1 行目と同じ理由）。

### 4.3 `BookProfile` の `novel` に足す行

```ruby
%i[page use]                => 'bunko_standard',
%i[page section_pagebreak]  => false,
%i[page chapter_pagebreak]  => 'any',
%i[theme name]              => 'novel',
```

- 節の改ページは、テーマの `tokens:` ではなく種類の既定値で決める。`v2-s6-10-consultation.md` §4.3 の食い違い（著者が `true` と書いてもテーマの値が通る）が起きず、「書かない条件では宣言しない」の決まりも変えずに済む。`novel` の雛形の `book.yml` には `section_pagebreak: false` を書く（「載せると決めたキーは全部書く」）。
- `chapter_pagebreak: any` は、小説の章が改ページ（面を問わない）で始まるのが普通なためである。改丁にしたい著者は `recto` と書く。
- `page.use` と `theme.name` は S8-3・S8-5 で足す（その値の判型とテーマを同梱する小段階。`v2-architecture-spec.md` §2.2 の「そのテーマを同梱する段階で足す」）。

---

## 5. 記法

### 5.1 行内の属性・傍点・縦中横（手で指定）

D 型の前処理 `transform_inline_spans!`（`v2-architecture-spec.md` §7.1）。`[文字]{.class}` を `span` にする。傍点は `[文字]{.sesame}`、縦中横は `[12]{.tcy}`。CSS は `stylesheets/parts/inline.css`。CSS に無いクラスは 🟡。文字の色を変えるインライン記法も、この仕組みで受ける（`v2-migration-plan.md` §6.3）。

### 5.2 挿絵

新しい記法は 1 つだけ足す。

| 書き方 | 契約 HTML | 組み方 |
| :--- | :--- | :--- |
| `![題](images/x.png)`（今と同じ） | 今の `figure` | 横組みの箱として行の間に置く。幅の指定（`width=50%`）は箱の中の横幅として働く |
| `![題](images/x.png){.full-page}` | `figure.vs-full-page` | 1 ページを使う。前後で改ページし、版面の中央に、縦横比を保って収める（`object-fit: contain`）。キャプションは出さず、代替テキストにする |

- `figure.vs-full-page` は vs の部品（`parts/figure.css`）に置き、どのテーマでも働く。横書きの本でも使える。クラス名は S8-2 で確かめ、`full-page`・`vs-full-page` とも CSS・コード・原稿に使われていなかったので、この名前にした（了承待ちの一覧に載せた）。
- **組み方（S8-2 で決めた）。** VFM は `{.full-page}` を img の class にし、説明文があれば figure と figcaption で包み、無ければ段落に置く。後処理 `mark_full_page_figures!` が、どちらも `figure.vs-full-page > img` だけの形にする（figcaption を外し、著者の書いた幅を使わない）。字と並んだ行の中の画像は 1 ページを使えないので、そのままにする。CSS は寸法を物理方向の `100vw`・`100vh` で書き、`display: flex` で中央に置く（論理方向で書くと、縦書きで横長の画像の縦横比が崩れる）。版面より小さい画像は引き伸ばさない（`object-fit: contain` で拡大すると、解像度の足りない画像がぼやけるため。縮めるのは `max-width`・`max-height` で行う）。横書き・縦書きの見本の文書で、前後の改ページ・中央への配置・縦横比を確かめた。
- 塗り足しまで使う全面の挿絵（裁ち落とし）は 2.0 では作らない。絵本の固定レイアウト（S9）の領分である。

### 5.3 縦中横の自動

L3 の後処理の一段。条件は `traits.vertical?`。

| 対象 | 扱い |
| :--- | :--- |
| 半角の数字 1〜2 桁（前後が半角の英数字・小数点・桁区切りでない） | `span.tcy` で包む |
| 半角の `!?`・`?!`・`!!`・`??`（ちょうど 2 字） | `span.tcy` で包む |
| 半角の数字 3 桁以上 | 包まない（横倒しのまま組まれる）。lint が全角か漢数字への書き換えを勧める（§6.2 の規則 5） |
| 全角の数字・全角の「！」「？」 | 触らない（もともと 1 字ずつ立つ） |
| 半角の英字 | 触らない（欧文として横倒しに組む。1〜2 字の略語を立てたいときは、手で `[AI]{.tcy}` と書く） |

- 対象にしない場所: コード・数式・ルビの読み（`rt`）・`span.tcy` の中・`a` の中の URL の文字・横組みの箱として置く部品（§3.4）の中・奥付と権利ページ。
- 見出しと目次の中も対象にする。
- 入り切りのキーは置かない。包みたくない箇所は全角で書けば済む。

### 5.4 投稿サイトの記法

前処理 `transform_web_novel_marks!`。条件は `features.web_novel`（`notation.web_novel`）。

| 書き方 | 置き換え先 | 条件 |
| :--- | :--- | :--- |
| `|漢字《かんじ》`・`｜漢字《かんじ》` | `{漢字|かんじ}` | 縦棒から `《` までが親文字。親文字と読みの字の種類は問わない |
| `漢字《かんじ》`（縦棒なし） | `{漢字|かんじ}` | 親文字は `《` の直前の漢字の並び（`々`・`〆`・`ヶ` を含む）。**読みが平仮名・片仮名・長音だけのとき**に限る（小説家になろうの自動のルビと同じ条件） |
| `《《文字》》` | `[文字]{.sesame}` | カクヨムの傍点 |
| `|《` ・`｜《` | `《`（ルビにしない） | 投稿サイトの打ち消しの書き方 |
| 段落の頭の全角空白 1 つ | 落とす | 字下げは CSS が行う（§6.1） |

- 受けないもの: 括弧のルビ（`漢字(かんじ)`・`漢字（かんじ）`）。地の文の括弧と区別できず、誤って変わる箇所が多い。なろうの「ルビに `・` を並べる傍点」は、特別に扱わない（ルビとして組まれ、見た目は傍点に近い）。
- コードの中は置き換えない（`Masking`）。vs のルビ `{漢字|かんじ}` と索引の `[用語]` には触れない（縦棒の形は、`{` の中にある縦棒を親文字の始まりと読まない）。
- 地の文に `《` を書いて、前が漢字で中が仮名だけのときは、ルビになる。投稿サイトでも同じに読まれるので、「投稿サイトと同じに読む」を決まりにし、避けるには `|《` と書く、と文書に書く。
- 置き換えは原稿を書き換えない（ビルドの中だけ）。`vs lint` も、置き換えた後の文で見る。

---

## 6. 小説の lint と字下げ

### 6.1 字下げ

字下げは CSS が行う。原稿の書き方は 2 通りを認め、どちらも同じ組み上がりにする。

| 原稿 | 扱い |
| :--- | :--- |
| 段落の頭に全角空白を書かない（Markdown の書き方） | そのまま。CSS が 1 字下げる |
| 段落の頭に全角空白を書く（投稿サイトの書き方） | `notation.web_novel` が有効なら、前処理が 1 つ落とす。無効なら 2 字下がるので、規則 4 が知らせる |
| 開き括弧（`「`・`『`・`（`・`〈`・`《`・`【`・`〔`）で始まる段落 | L3 の後処理が `p` に `vs-open-bracket` を付け（条件は `traits.vertical?`。縦中横の自動と同じ段）、`novel` が `text-indent: 0` にする |

- 括弧の段落の印を縦書きの本に限るのは、本書の契約 HTML を変えないためである。横書きの本にも要ると分かったら、条件を外して契約の表を直す（足すだけの変更）。`theme-contract-spec.md` §2.5 の表に `p.vs-open-bracket`（付く条件: 縦書き）がある。

### 6.2 規則の組 `novel`

`minimal` の規則に、次の 6 つを足す。どれも原稿の場所を指すので 🟡。id は案で、S8-6 で確定する（著者が `lint.disabled_rules` に書く名前なので、了承待ちの一覧に載せる）。

| # | id（案） | 知らせるもの | 知らせないもの |
| :--- | :--- | :--- | :--- |
| 1 | `novel-ellipsis-pair` | 「…」の並びが奇数個。「・・・」「。。。」（三点リーダーの代わり） | 偶数個の並び |
| 2 | `novel-dash-pair` | 「―」「—」が 1 つだけ | 2 つ以上の並び。数字や英字にはさまれたもの（範囲の表記） |
| 3 | `novel-space-after-mark` | 全角の「！」「？」「⁉」「‼」の直後に全角空白が無い | 直後が閉じ括弧（`」`・`』`・`）` など）・別の「！」「？」・「…」「―」・行末のとき |
| 3b | `novel-period-before-bracket` | 閉じ括弧の前の句点（「。」」「。』」） | 丸括弧の前の句点（「。）」。地の文の補足では普通に使う） |
| 4 | `novel-paragraph-indent` | `notation.web_novel` が無効: 段落の頭の全角空白（2 字下がる）。有効: 1 つの章の中で、頭に全角空白のある段落と無い段落（括弧で始まる段落を除く）が混ざっているとき、少ない側 | 括弧で始まる段落。全部がそろっている章 |
| 5 | `novel-halfwidth-digits` | 縦書きの本で、半角の数字が 3 桁以上並ぶ（横倒しに組まれる） | コード・数式・URL・横組みの箱の中。横書きの本 |

- 規則 4 の「有効のとき」は、投稿サイトへ出す原稿の字下げの書き忘れを見つけるためのものである。本の組み上がりは変わらないので、要らない著者は `lint.disabled_rules` で外せる。
- 規則 5 は組方向を読む（`Common.traits.vertical?`）。`book.type` は読まない。
- 誤検出の確かめは §8.1 の S8-6 のとおり。指摘の数が多すぎる規則（1 作品で 50 件を超える）は、条件を見直してから入れる（「見逃すより検出」だが、常に出る指摘は読まれなくなる）。

---

## 7. 雛形 `scaffolds/novel/`

- **原稿。** 青空文庫の著作権の切れた短い作品を 1 つと、記法の見本の章を 1 つ置く。
  - 作品は宮沢賢治「注文の多い料理店」を候補にする。短く（約 6 千字）、会話文・地の文・ルビの要る字がそろい、挿絵を入れる場面を選びやすい。目指す紙面の作例（「銀河鉄道の夜」）と同じ作者で、見比べやすい。底本と入力者の表記を権利ページに載せる（青空文庫の取り扱いの決まり）。
  - **作品の選び方は、S8-7 の前にユーザーが確かめる**（雛形は `vs new` で著者の手元に写るので、別の作品や架空の原稿がよければ替える）。
- 記法の見本の章には、ルビ・傍点・縦中横（手と自動）・投稿サイトの記法・行の間の挿絵・全面の挿絵・脚注・`@pagebreak` を載せる。前書きと後書きも置く。
- 挿絵は、vs で作った簡単な図（著作権の問題が無いもの）を 2 枚置く。
- `book.yml` は小説で意味のあるキーだけを載せる（`v2-architecture-spec.md` §2.6）。

---

## 8. 段階ごとの完了の条件と確かめ方

### 8.1 S8 の小段階

着手は S7a の後（`v2-migration-plan.md` §2.1）。太字の確かめは、本書の出力を r3 と比べる小段階である。

| 小段階 | 作るもの | 確かめ |
| :--- | :--- | :--- |
| S8-1 物理方向を論理方向へ | `css-layer-restructure-spec.md` §6 の表のとおり、§3.4 の「縦で保証する部品」「横組みの箱として置く部品」が読む CSS の物理方向を論理方向へ直す。`:nth()` で奇数・偶数を書いた規則があれば `:recto`・`:verso` へ。使えない部品の CSS は直さない | **本書を r3 と比べる（全部の比べ）。** PDF は全ページの画素が一致。EPUB は計算値が差 0（Chromium は論理方向を物理方向の計算値に直すので、比べられる）。Kindle は中間生成物が差 0。差が出た宣言は §2.5 のとおり扱う。直した数と、Kindle で書き直した数を記録する |
| S8-2 行内の属性・傍点・縦中横（手で指定）・括弧の段落の印 | D 型の前処理 `transform_inline_spans!`。`stylesheets/parts/inline.css`（`.tcy`・`.sesame`）。`HtmlContract` に `tcy`・`sesame`。`notation-implementation-guide.md` に D 型と E 型の節。`figure.vs-full-page`（§5.2）。`vs upgrade` の原稿の走査の 🟡 の文面（`v2-migration-plan.md` §5.2） | **本書を r3 と比べる。** 本書の原稿に `]{.` の並びが無いことを先に確かめる。本書の契約 HTML が前後でバイト単位で同じ。見本の原稿（横書き）で `span.sesame`・`span.tcy` が出る。CSS に無いクラスで 🟡 |
| S8-3 判型のプリセットと `BookProfile` | **先に `cover-size-independence-spec.md` §6 の 1・2**（表紙の寸法の窓口。今の表紙のコードは A4・B5・A5 のほかを黙って B5 として組む）。`Common::PAGE_SIZES` と `config/page_presets.yml` に §4.1 の判型。表紙のひな形と下敷き（同 §6 の 3〜5）。`BookProfile` の `novel` に `page.use`・`section_pagebreak`・`chapter_pagebreak`。`ConfigKeys` の `page.use` の値の一覧 | 本書の `Common::CONFIG` と `book-settings.css` が前後で同じ（本書の出力は組み直さない）。`book_profile_test.rb` の (1)。各プリセットで 1 章だけの本を組み、`pdfinfo` の寸法が合う |
| S8-4 縦書きの経路 | §2 の全部。`stylesheets/base/vertical.css`・`EntryWriter` がページの種類で入れる・余白の箱の `writing-mode`・OPF の `page-progression-direction` と `primary-writing-mode`・EPUB 向けの接頭辞つきの書き方・縦中横の自動と括弧の段落の印（L3 の後処理の一段）・縦書きで使えない部品と索引の 🟡（`TraitCombinationCheck` と原稿の検査）・版面の字数と行数の 💡（§4.2） | **本書を r3 と比べる。** 余白の箱の `writing-mode: horizontal-tb` は横書きでは変わらないはずなので、B1 の `pdf` の画素と、入口の CSS の差（1 行）を見る。縦書きは、S5 のテストの材料のテーマ（`supports.writing_mode: [horizontal, vertical]`）で 3 章の本を組み、§8.2 の機械の条件の 1〜5 を見る |
| S8-5 テーマ `novel` | `themes/novel/`（§3）。`BookProfile` の `novel` に `theme.name: novel`。`parts/preface.css` の飾りを `themes/standard/` へ移す。`vs theme:check novel` | **本書を r3 と比べる。** 前書きの飾りを移すので、B1 の `pdf`・`epub`・`kindle` と B4 の `pdf`（前書きに囲みがある）を組み、PDF の画素・EPUB の計算値・Kindle の中間生成物・`InversionCheck` の要素ごとの判定を見る（S6-4 と同じ比べ）。`novel` は `vs theme:check` で 🟡 0。プリセットの値と `novel` の紙面を、ユーザーが見て確定する |
| S8-6 投稿サイトの記法と小説の lint | `transform_web_novel_marks!`（§5.4）。`Lint::RULESETS` の `novel` に §6.2 の規則 | 本書に触れない（`features.web_novel` が無効・`lint.ruleset` が `technical`）ことを、段の一覧と `vs lint` の全指摘の前後の突き合わせで確かめる。記法と規則ごとのテスト。誤検出の確かめは、青空文庫の作品 3 つと、投稿サイトの書き方の見本の原稿に `vs lint` を掛け、指摘を全部読む |
| S8-7 雛形と完了の確かめ | `scaffolds/novel/`（§7）・`copy_to_scaffold.rb` の種類ごとの複製・`vs new --type novel`・`book_profile_test.rb` の (2) | §8.2 の機械の条件と、目で見る 12 か所。`rake test`・`rake test:layout`・`rake test:standard`・`rake test:release`。`gem build` の大きさを記録する（`v2-migration-plan.md` §2.4 の 11）。その後、基準を r4 に上げ、N1 を足す（§8.3） |

S8 の中の決まり:

1. **どの小段階も、完了のコミットは「本書の出力が r3 と同じ」ものだけにする。** S8-3・S8-6 は出力を組み直さず、設定と段の一覧で確かめる。S8-7 の最後に、全部の比べを 1 回行う。
2. **S8-1 は、S8 の中でいちばん本書に触れる小段階である。** 直す箇所を部品のファイルごとにコミットを分けてよい（差が出たときに原因のファイルが分かる）。比べは最後のコミットで 1 回でよいが、差が出たらファイルごとに戻して探す。
3. **`vs-vertical` の付いた本の確かめに、S8-4 では `novel` を使わない。** 経路の不具合とテーマの不具合を分けるためである。
4. ビルドなしで HTML を比べる道具（S8 の前に `scripts/` へ移す。`v2-migration-plan.md` §3.6）を、S8-4 の縦中横の自動と括弧の段落の印の確かめに使う。

### 8.2 S8 の完了の条件（紙面の条件）

`scaffolds/novel/` の本で見る。

機械で見るもの:

1. 四つの出力先が終了コード 0 で組め、🔴 と 🟡 が 0。
2. PDF の紙の寸法がプリセットの値（`pdfinfo`）。
3. ページが右から左へ進む（PDF の `ViewerPreferences` の `Direction`・OPF の `page-progression-direction`）。奇数ページのノンブルが左の小口の側にある（`pdftotext -bbox`）。隠しノンブルがノドにある。
4. 本文が縦に組まれている（`pdftotext -bbox` で、1 段落の字の x が同じで y が増える）。
5. 本文だけのページの字数と行数が、プリセットの目安と合う（§4.2 の 💡 と同じ計算）。
6. 契約 HTML に `span.tcy`・`span.sesame`・`ruby`・`p.vs-open-bracket`・`figure.vs-full-page` があり、`HtmlContract` の検査が通る。
7. EPUBCheck が致命・エラー・警告とも 0。
8. KPF ができ、Enhanced Typesetting が Supported・エラー 0。

目で見るもの（PDF・Apple Books・Kindle Previewer のそれぞれで。撮った画面を基準に残す）: 本扉・目次・章の始まり・地の文と会話文の続く段落・ルビ・傍点・縦中横・行の間の挿絵・全面の挿絵・脚注・後書き・奥付の 12 か所。PDF では、目指す紙面の作例と並べて、字の大きさ・行送り・余白の釣り合いをユーザーが見て了承する（プリセットの値の確定を兼ねる）。

### 8.3 小説の基準と、本書を守る確かめ

- **小説の基準。** S8-7 の完了のコミットで、基準を r4 に上げ、`N1`（`scaffolds/novel/` の本の四つの出力先・Kindle の記録・画面）を足す。決まり（`v2-migration-plan.md` §3.2）のとおり B1〜B5 も組み直す。S9 以降は、N1 も B1 と同じ道具（PDF の画素・`epub_diff.rb`・`kindle_record_diff.rb`）で守る。
- **本書を守る確かめ。** §8.1 の表の太字のとおり、S8-1・S8-2・S8-4・S8-5 で r3 と比べ、S8-7 で全部の比べを行う。

---

## 9. 論点（未決）

| # | 点 | 決める時点 | 判断の軸と扱い（`v2-migration-plan.md` §4.1） |
| :--- | :--- | :--- | :--- |
| 1 | 縦の文書と横の文書（奥付）が 1 冊に混ざって組めるか | S8-4（済み） | 混ざってもそのまま組めた（§2.2・§10.4） |
| 2 | Kindle の論理方向 | S8-1・S8-4（済み） | Kindle は論理方向を縦書きの向きで正しく解く。手で書き直したのは 1 規則（`targets/kindle.css`。§10.4 の決めたことの 8） |
| 3 | 縦書きで使えない部品の一覧 | S7a と S8-4（済み） | side-by-side・book-card・表の回転の 3 つ（§3.4・§10.4 の決めたことの 4） |
| 4 | プリセットの値 | S8-3 で求め、S8-5 でユーザーが確定 | §4.1 の目安とノド 13mm |
| 5 | `novel` のオプション | S8-5 | 迷う項目は足さない（§3.2）。足したら了承待ちの一覧へ |
| 6 | `figure.vs-full-page` のクラス名 | S8-2（済み） | 衝突しないことを確かめて `vs-full-page` にした（§5.2）。了承待ちの一覧へ載せた |
| 7 | 雛形の作品 | S8-7 の前にユーザーが確かめる | §7 |
| 8 | 書体の埋め込みのオプション | 2.0 の後（`PLANNED.md`） | PDF は今も書体を埋め込む。EPUB と Kindle は読者が書体を選ぶので、`novel` は総称の明朝で組む。EPUB に書体を埋め込む要望が出たら、書体のライセンスの扱いと一緒に決める |
| 9 | 行数と字数で版面を指定するキー | 要望が出たら（`PLANNED.md`） | §4.2 |
| 10 | 横書きに対応した `novel` | 2.0 の後（`PLANNED.md`） | `supports.writing_mode` に足すだけで済むよう、CSS を論理方向で書いておく |

---

## 10. 実装記録

### 10.1 S8-1 物理方向を論理方向へ（2026-11-19）

記録は `css-layer-restructure-spec.md` §10.12。

### 10.2 S8-2 行内の属性・傍点・縦中横・全面の挿絵（2026-11-19）

#### 作ったもの

- `pre_process/inline_span_transformer.rb`（`InlineSpanTransformer`）と前処理の段 `transform_inline_spans!`。`[文字]{.class}` を `<span class="class">文字</span>` にする（§5.1）。受ける形と段の位置の理由は `notation-implementation-guide.md` §10。
- `IndexMarkup::INLINE_ATTRIBUTE_AHEAD`: 索引の 3 つのパターンが、`]` の直後の `{.` を索引の印から外す。
- `ContainerClassCheck`: 行内の属性のクラスも、`:::{.class}` と同じ許可リストで照合して 🟡（場所・候補・`custom.css` への導線）。
- `stylesheets/parts/inline.css`（`.tcy`・`.sesame`。EPUB 向けの接頭辞つきの書き方を前の行に）。本文のページと目次の入口が読む（`EntryWriter`）。
- 全面の挿絵: 後処理 `mark_full_page_figures!` と `parts/figure.css` の `figure.vs-full-page`（§5.2 の「組み方」）。`HtmlContract` に `vs-full-page`（`tcy`・`sesame` は S6 で表にあった）。
- `vs upgrade` の原稿の走査（`V1Migration.inline_attribute_hits`）を `InlineSpanTransformer.each_span` に替え、🟡 の文面を確定した（`v2-migration-plan.md` §5.2）。
- `notation-implementation-guide.md` §10（D 型）・§11（E 型）。
- テスト 12 件（`inline_span_transformer_test.rb` 6・`full_page_figure_test.rb` 4・`index_markup_test.rb` 1・`container_class_check_test.rb` 1）と、`upgrade_commands_test.rb` の文面の期待値。

#### 仕様に無かったので決めたこと

1. **行末の、段落に付けるクラスは行内の属性として読まない。** 1.x は段落の末尾の `{.text-right}` などの寄せ（`transform_text_right_inlines!`）と、`{.aki}`・`{.aki2}`・`{.small}`・`{.references}`（後処理の `ReplacementRules`）を段落のクラスとして読み、`…[用語]{.aki}` の `[用語]` は索引語のまま残る。行の途中の `[語]{.aki}` だけを span にする。1.x の原稿の組まれ方を変えないためである（`vs upgrade` の走査も数えない）。最初は寄せの 4 つだけを除いていて、ユーザーの質問（1.x で `[用語]{.x}` を紹介しているか）を受けて 1.x の記法を洗い直し、残りの 4 つを足した。
2. **`{…}` の中はクラスだけを受ける。** `#id`・`key=value` は読まない（広げるのは後からできる）。
3. **段の位置は会話（`transform_talk!`）の前。** 中を Kramdown で HTML にする段より前でないと、会話・寄せ・fancy list の中で `{.class}` が字のまま出る。
4. **`vs upgrade` の 🟡 は場所だけを示し、直し方は添えない（ユーザーの判断・11/19）。** 1.x は `[用語]{.x}` の書き方を紹介していない（master の原稿を探して 0 件。`]{` は 14 章の Re:VIEW の表と 31 章の正規表現だけ）。1.x の原稿でこの形になるのは段落の末尾に付けるクラスで、それは 1.x と同じに組む（上の 1）。残るのは Pandoc に慣れた著者が行内の属性のつもりで書いた箇所なので、1.x の組み方へ戻す案内（最初は「`{` の前に `\` を書く」を添えていた）は要らない。1.x では `[文字]` が索引の印になり（索引の無い本では角かっこを外し）、`{.class}` は字のまま紙面に出ていた（VFM で確かめた）。§5.2 の案（`]` と `{` の間に空白を入れる）も採らない。
5. **全面の挿絵は、版面より小さい画像を引き伸ばさない**（§5.2 の「組み方」）。`object-fit: contain` で拡大すると、解像度の足りない画像がぼやける。
6. **全面の挿絵には既定の枠を付けない。** `border=on` を書けば付く。

#### 確かめた結果

比べる相手は S8-1 と同じく、直す前のコミット（`993c007c`）で組んだ B1。

- 本書の原稿に `[文字]{.class}` の形は 0 か所（`InlineSpanTransformer.each_span` で数えた。`]{.` の並びも 0）。
- 契約 HTML（`.cache/vs/build/html`）: HTML はバイト単位で同じ。違ったのは showcase の SVG 2 枚だけで、埋め込んだ書体の部分が組むたびに変わるもの（S8-1 の前後の 4 回の組でも 4 通りだった）。
- PDF: 閲覧用（283 ページ）・印刷用（281 ページ）とも、違うページ 0。
- EPUB・Kindle 用 EPUB: 違いは平らな CSS の 4 ファイル（`inline.css` と全面の挿絵の規則が増えた）だけ。計算値（117 文書・312 組）は差 0。EPUBCheck は 0。Kindle の中間生成物は要素 26,409 で差 0。変換は Supported・Success。
- 見本の本（横書き・1 章）: `span.sesame`・`span.tcy`・`figure.vs-full-page` が契約 HTML と EPUB に出た。未知のクラス `.sesami` で 🟡（候補 `.sesame`）。行末の `[用語]{.text-right}` は段落の寄せと索引語のまま（`{.aki}`・`{.small}` などはテストで確かめた）。PDF で傍点が字の上に付き、全面の挿絵は前後で改ページして版面の中央に縦横比を保って収まった。EPUBCheck は 0。
- `rake test` 4,537 件が通った。

#### S8-4 へ渡すこと

- 全面の挿絵の Kindle の見え方（`100vh`・`flex` を解さないときの寄り）は、S8-4 の縦書きの材料の本で Kindle の記録を取って見る。
- 縦中横・傍点の Kindle の解し方（接頭辞つきの書き方）も同じ。

### 10.3 S8-3 判型のプリセットと `BookProfile`（2026-11-20）

表紙の寸法の窓口と比の扱い（`cover-size-independence-spec.md` §6 の 1・2）を先に済ませた。記録は同 §8。

#### 作ったもの

- `Common::PAGE_SIZES` に `BUNKO`（105×148。A6 と同じ寸法）・`B6`（128×182。B5 と同じく JIS）・`SHINSHO`（103×182）・`SHIROKU`（127×188）。各行に文面の名前（`label:`。`文庫`・`B6`・`新書`・`四六`）。生成物のファイル名の判型の部分は `bunko`・`b6`・`shinsho`・`shiroku`。
- `config/page_presets.yml` に `bunko_standard`・`bunko_custom`・`b6_standard`・`b6_custom`・`shinsho_standard`・`shiroku_standard`（§4.1）。
- `Epub::Config.resolve_page_size`: 足した 4 判型は寸法で Vivliostyle へ渡す（`VIVLIOSTYLE_SIZE_NAMES` は今の 4 つだけ）。
- `BookProfile` の `novel` に `page.use: bunko_standard`・`section_pagebreak: false`・`chapter_pagebreak: any`（§4.3）。
- テスト: `cover_size_test.rb`（判型のプリセットを全部回す。窓口が寸法を返す・名前の字・本文と表紙が同じ寸法・小説の 4 判型の寸法と名前・字数と行数とノド 13mm）・`book_profile_test.rb` 1・`page_layout_test.rb` 1。

#### プリセットの値（S8-5 でユーザーが紙面を見て確定する）

§4.1 の求め方で、天地の余白を版面の高さが字の大きさのちょうど整数倍になるように決め、行数はノドと小口の間に余り 0.5mm 以下で収まるようにした。

| プリセット | 字・行送り | 天・地 | ノド・小口 | 字数 × 行数 |
| :--- | :--- | :--- | :--- | :--- |
| `bunko_standard` | 9pt・1.65（14.85pt） | 15・12.35mm | 13・10mm | 38 × 16 |
| `b6_standard` | 9.5pt・1.7（16.15pt） | 22・19.24mm | 17・16mm | 42 × 17 |
| `shinsho_standard` | 9pt・1.7（15.3pt） | 23・19.3mm | 14・10mm | 44 × 15 |
| `shiroku_standard` | 9.5pt・1.7（16.15pt） | 23・20.89mm | 17・15mm | 43 × 17 |

#### 仕様に無かったので決めたこと

1. **「`ConfigKeys` の `page.use` の値の一覧」は作らない。** `ConfigKeys` はキーごとの既定値・著者が埋めるキー・廃止キーだけを持ち、値の一覧を持つ仕組みが無い。種類ごとに選べるプリセットは、その種類の雛形の `book.yml` が `# use:` の行で並べる（技術書は今の並び。小説は S8-7 の `scaffolds/novel/config/book.yml`）。
2. **Vivliostyle へ名前で渡す判型は今の 4 つ（`A4`・`A5`・`B5`・`JIS-B5`）だけ。** 新書・四六は Vivliostyle が知らず、Vivliostyle の `B6` は ISO の 125×176mm で vs の B6 と違う。`A6` は ISO と同じ寸法だが、足した判型は一律に寸法で渡す。vs の表に無い名前（`Letter` など）は今までどおりそのまま渡す。
3. **`*_custom` は、今の `a5_custom` などと同じく全部の行を書き出す**（YAML の `<<:` で写さない）。著者がそこを直して使うため。

#### 確かめた結果

- 本書の `Common::CONFIG`（4,852 バイト）と `BookSettingsCss.render` の出力（4,861 バイト）が、直す前（`c0fd6419`）のコードと同じ。
- 6 つのプリセットで 1 章だけの本（`vs new` の雛形から、技術書のまま `page.use` だけを替えた）を組み、`pdfinfo` の紙の寸法が 105×148・128×182・103×182・127×188 mm。🟡 は扉絵の字数（`theme.frontispiece.heading_chars`・`lead_chars` が小さい版面に収まらない）で、技術書の既定のテーマを小さい判型に当てたため。S8-5 の `novel` で扱う。
- `rake test` は手順 5 の後でまとめて走らせる。

#### 気づいたこと（11/21 に直した）

- **知らない `page.use` を書くと、本文は黙って B5 で組まれる。** `apply_page_preset` はプリセットが無ければ何もせず、`Common.resolve_page_size` は表に無い `size:` を B5 として読む。確かめの最初の 1 回で、雛形の `page_presets.yml`（まだ同期していない）に無い `a6_standard`（今の `bunko_standard`）を選んだ本が、🔴 を表紙の 1 つだけ出して、本文を B5 で組んだ。`cover-size-independence-spec.md` §2.3 は「本文のビルドでも設定の検査が先に止めるはず」としていたが、その検査は無い。1.x の本を 2.0 の `vs` で組み、`book.yml` に小説の判型を書いて `page_presets.yml` を更新していない著者が踏む。
  - 直し（11/21・ユーザーの判断「組めない旨を示して止める」）: `RootCommand#stop_unknown_page_preset!` が、本を読むコマンドを 🔴 で止める（`stop_unmigrated_book!` の次）。判定は `Common.find_unknown_page_preset`（`book.yml` をその場で読み直し、`page.use` か本の種類の既定のプリセットが `page_presets.yml` に無いか）。gem の雛形にある名前なら「`vs upgrade` で `config/page_presets.yml` を新しくすると、この判型で組めます」、無い名前なら選べる名前を並べる。`vs upgrade` と `vs doctor` は止めない（doctor は同じ文面を 🟡）。
  - 11/21: 文庫判のプリセットを `a6_*` から `bunko_standard`・`bunko_custom` へ、判型の表の名前を `A6` から `BUNKO`（文面は「文庫」・生成物と下敷きは `bunko`）へ改めた（ユーザーの判断。小説を書く人は「A6」でなく「文庫」と呼ぶ。`shinsho`・`shiroku` と同じく日本語の呼び方の名前にそろえる）。`A6` の名前は残さない（1.x に無く、まだ公開していない）。
  - 1.x の `vs` は A4・B5・A5 だけに対応のまま（ユーザーの判断）。小説の判型を 1.x へ戻して入れない。
  - 11/21（ユーザーの判断「途中で止まるより、最初の vs preflight・build で止める」）: プリセットを当てた後の `size:` が判型の表に無く、`page.width`・`page.height` も無い本も、同じ入口で 🔴 で止める（`Common.find_unknown_page_size`・`page_size_notice`。入口は `RootCommand#stop_unknown_page_size!`）。`size:` が `book.yml` か、どのプリセットから来たかを示す。
  - 同じ日に、S8-3 で入れた違いを直した: `page:` を書いていない本（`size:` が無い）は、本文が B5 で組まれるのに、表紙の寸法の窓口が nil を返して表紙だけ 🔴 で止まっていた。窓口も本文の `resolve_page_size` と同じく B5 にした（S8-3 の前の表紙も B5）。

### 10.4 S8-4 縦書きの経路（2026-11-21）

#### 作ったもの

- `stylesheets/base/vertical.css`（`:root` の `writing-mode: vertical-rl` と接頭辞つきの書き方）。`EntryWriter` が、縦書きの本の章・付録・前書き・後書き・目次・本扉・部扉の入口の base 層の最後に足す（`VERTICAL_KINDS`）。奥付・権利ページ・索引・用語集は足さない。
- `stylesheets/parts/vertical.css`（横組みの箱。§3.4 の 2 段目）。本文の部品を読む種類（章・付録・前書き・後書き）の入口の parts 層の最後に足す。
- 余白の箱: `base/page.css` の、中身のある 6 つの箱（ノンブルと柱）に `writing-mode: horizontal-tb`。
- body のクラス `vs-vertical`（`BodyClassInjector.trait_classes`。目次の生成も読む）。奥付と権利ページにも付ける（本の軸なので）。
- OPF: EPUB の設定の `readingProgression` を `traits.binding` から書く（Vivliostyle が `spine` の `page-progression-direction` に書く。今までは `ltr` の決め打ち）。Kindle 用の EPUB にだけ `<meta name="primary-writing-mode" content="vertical-rl"/>` を足す（`Epub::Opf.mark_primary_writing_mode!`）。
- 後処理の段 `mark_vertical_text`（`PostProcessCommands::VerticalText`。条件は `traits.vertical?`）: 縦中横の自動（§5.3）と括弧の段落の印 `p.vs-open-bracket`（§6.1）。目次の生成（`TocCommands`）も縦中横の自動をかける。`HtmlContract` に `vs-open-bracket`。
- 索引: `Common.index_enabled?` が縦書きの本では偽を返す（索引の段・ページ・dedup が止まる）。`TraitCombinationCheck` が 🟡「縦書きの本では、索引と用語集のページを作りません」。
- `Guards::VerticalPartsCheck`（原稿の検査。build と preflight）: 縦書きの本の原稿の `:::{.side-by-side}`・`:::{.book-card}`・`:::{.rotate-table}` を 🟡 で場所とともに示す。
- `Build::TextGridNotice`: 縦書きの本で、`vs build --log` と `vs preflight` の終わりに 💡「版面: 42 字 × 17 行」。字数の端数が 0.2 字以上なら、天地の余白の直し方を同じ行に添える（§4.2）。
- 落とし穴の記録: `vivliostyle-css-pitfalls-notes.md` §2.25。
- テスト 11 件（`entry_writer_test.rb` 1・`epub_builder_sanitize_test.rb` 1・`vertical_text_test.rb` 4・`vertical_parts_check_test.rb` 3・`body_class_injector_test.rb` 1・`trait_combination_check_test.rb` 1）と、既存の 4 件の期待値（縦書きの本の索引の 🟡・原稿の検査の並び）。

#### 仕様に無かったので決めたこと

1. **横組みの箱の規則は `parts/vertical.css` に置く**（§2.1 は `base/vertical.css` にまとめるとしていた）。箱の幅と前後の空きは、部品（parts 層）の `inline-size: 100%`・`margin-inline: auto` などに勝つ必要があり、base 層では負ける。`!important` は著者の `custom.css` にも勝ってしまうので使わない。`base/vertical.css` には本の組方向だけを残した。
2. **横組みの箱の幅は `calc(100% - 2em)` に定める。** 幅を中身に合わせる（`fit-content`）と、Vivliostyle 11.3 は、ページの残りに入らない箱を次のページへ送らず、紙の外へはみ出させた（材料の本で、段落と数式の図が紙の外へ出て消えた。最小の文書で再現し、`display` を変えても直らず、幅を定めると直った。`vivliostyle-css-pitfalls-notes.md` §2.25）。小さな表や短いコードも版面の幅を 1 つ使うので、ページは増える。著者が挿絵に `{width=50%}` と書けばその幅になり、正しく送られる。前後の行との空きは 1em。
3. **番号つきのキャプションごと包む箱は、`div:has(> :is(.table-caption, .code-caption))` で選ぶ。** 包む `div` のクラス（`.cross-ref-table`・`.cross-ref-list`）は契約 HTML の内部のクラスで、vs の CSS も選ばない決まり（`html_contract_test.rb`）。
4. **縦書きでは使えない部品は、side-by-side・book-card・表の回転の 3 つ**（§3.4 の表を直した）。材料の本で、side-by-side は箱が紙の外へはみ出した。book-card は画像と字が縦の流れに並び、カードの形にならなかった。表の回転は、横書きの版面のために表を回す記法で、縦書きでは向きが合わない。会話のアバター（吹き出しが縦に組まれ、アバターが下に付く）・行番号つきのコードの折り返しの印（横組みの箱の中で横書きと同じに出る）・サイドイメージ・画像と字を並べる記法・表と本文を並べる記法は、崩れずに読めたので 🟡 にしない。
5. **縦中横の自動の対象外**には、仕様の表に加えて `kbd`・`samp`・`svg`・`math` と、横組みの箱（`parts/vertical.css` と同じ並び）を入れた。URL を字にしたリンクは、リンクの字が `http://`・`https://`・`www.` で始まるものとした。段落の頭の全角空白の後の開き括弧には、括弧の段落の印を付けない（投稿サイトの記法を読む前処理が空白を落とすのは S8-6）。
6. **`vs build` の 💡 は `--log` のときだけ**（§4.2 のとおり）。`vs preflight` は常に出す。横書きの本には出さない。
7. **縦書きの本で索引を止める場所は `Common.index_enabled?`** にした。前処理・索引の段・ページの並び・dedup が同じ述語を読むので、1 か所で全部が止まる。`vs index:*` も、縦書きの本では索引が無効の扱いになる。
8. **Kindle の横組みの箱の前後の空きは、`targets/kindle.css` に物理方向で書いた**（§2.5 の数え方で、手で書き直した箇所は 1 規則・宣言 2 つ）。Kindle は論理方向のプロパティを縦書きの向きで正しく解いた（箇条書きの `padding-inline-start` が `padding-top`、引用の `border-inline-start` が `border-top` に）。崩れたのは、`targets/kindle.css` が横書きを前提に物理方向で書いた囲みの `margin-top`・`margin-bottom` で、縦の流れの前後（左右）の空きが 0 になっていた。`body.vs-kindle.vs-vertical section > :is(pre, table, …)` に `margin-left`・`margin-right` を足した。`figure` は、写真を並べる記法の `figure` の規則と、平らな CSS で勝ち負けが入れ替わる（`css_layer_test.rb`）ので外した。
9. **`Css::Cascade` の論理方向と物理方向の組（横書きの前提）は、S8-4 では変えない。** 使うのはテーマの検査（`InversionCheck`）と著者の CSS の優先の処理で、縦書きの本の判定が要るのは、縦書きのテーマを検査する S8-5（`vs theme:check novel`）である。そこで組方向で表を切り替えるかを決める。

#### 確かめた結果

本書を守る確かめは、直す前のコミット（`e22f1321`）と作業ツリーで、同じ素材から B1 を組んで比べた（`scripts/build_copy.rb`・4 つの出力先・`--no-clean`）。

- PDF: 閲覧用（283 ページ）・印刷用（281 ページ）とも、違うページ 0。
- 入口の CSS（`.cache/vs/entry-*.css`）: 差 0（横書きの本は `vertical.css` を読まない）。
- 契約 HTML: 違ったのは showcase の SVG だけ（組むたびに変わる。§10.2 と同じ）。
- EPUB・Kindle 用 EPUB: 違いは画像の名前（showcase の SVG と、写真を並べる記法で合成した画像。合成した画像はバイト単位で同じ）と更新日時だけ。CSS は同じ。`spine` は `ltr` のまま。Kindle の記録は、EPUB の中身が同じなので取らなかった。
- `targets/kindle.css` の規則は、Kindle の確かめの後に足した。縦書きの本の `body` にしか当たらない（`vs-vertical`）。

縦書きは、S5 の材料のテーマ（`standard` を継いで `supports.writing_mode: [horizontal, vertical]` を足した `vtest`・`theme.style: simple`・`b6_standard`）で、前書き・4 章・付録（雛形の見本の章）・後書きの本を組んだ（§8.1 の決まり 3 のとおり `novel` は使わない）。§8.2 の機械の条件の 1〜5:

1. 4 つの出力先とも終了コード 0、🔴 は 0。🟡 は、縦書きで使えない部品の 3 件（狙いどおり）・材料の原稿の参照の誤り 3 件・扉絵の字数 1 件（S8-3 で見た、小さい判型と技術書のテーマの組み合わせ。`style: simple` で扉絵を使わない本でも出る。S8-5 で扱う）。EPUBCheck は EPUB・Kindle 用 EPUB とも 0。Kindle の変換は Supported・Success・エラー 0（注意は `box-shadow` と表紙の W14016 だけ）。
2. 紙の寸法は 128 × 182mm（`pdfinfo` で 362.8 × 515.9pt）。
3. PDF の `ViewerPreferences` の `Direction` は `R2L`。OPF の `spine` は EPUB・Kindle 用 EPUB とも `rtl`。Kindle 用 EPUB には `primary-writing-mode` の meta がある。奇数ページのノンブルが左（`pdftotext -bbox`）。印刷用 PDF の隠しノンブルは、奇数ページ（左）で右端、偶数ページ（右）で左端＝ノド。
4. 本文・前書き・後書き・目次・本扉・部扉が縦に組まれ、権利ページは横に組まれた（§2.2 の論点 1。混ざっても、ページの進む向きと奇数ページの側は前後の文書と同じ）。柱とノンブルは横に組まれた。
5. 1 行の字数は 42 字（💡「版面: 42 字 × 17 行」と同じ）。行の間隔は 16pt で、行送り 16.15pt と合う。材料の本は段落の間に空きがあり、17 行がそろったページは無かった（小説のテーマでは段落の間の空きを 0 にする。S8-5）。

ほかに見たもの:

- 縦中横の自動は、契約 HTML で数字 1〜2 桁と `!?` を包んだ（`3.5`・`2026`・`100`・コードの中は包まない）。目次の生成も同じ。括弧で始まる段落に `vs-open-bracket` が付いた。Kindle は縦中横（`text-combine-upright: all`）と傍点（`-webkit-text-emphasis-style`）を読んだ。PDF で、ルビ・傍点・縦中横・脚注（版面の左端）が正しく組まれた。
- 縦書きで使えない部品の見極め（決めたことの 4）と、横組みの箱が紙の外へはみ出す件（決めたことの 2）は、材料の本の全ページを画像にして見た。直した後、紙の端に掛かる字は、使えない部品の side-by-side の 1 か所と付録の 1 か所だけになった。
- `rake test` 4,565 件が通った。

#### S8-5 へ渡すこと

- 括弧の段落の字下げ 0（`p.vs-open-bracket`）・段落の間の空き 0・見出しの形は `novel` で決める（材料の本では `standard` の見た目のまま）。
- 節見出しの番号（`1-1`）は、数字ごとに縦中横になる。小説の既定は `heading_numbering: none` なので、番号のある縦書きの本で要るかは後で見る。
- `vs theme:check novel` で、`Css::Cascade` の組を組方向で切り替えるか（決めたことの 9）。
- Kindle Previewer の画面で、全面の挿絵（中間生成物の `figure.vs-full-page` に前後の改ページが無い）と、横組みの箱の幅（Kindle は `calc(100% - 2em)` を落とす）を見る。S8-7 の目で見る 12 か所に入る。
- `style: simple`（扉絵を使わない）の本で、扉絵の字数の 🟡 が出る。
