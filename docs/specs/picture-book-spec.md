# 絵本（固定レイアウトの経路・原稿の形・テーマ `picture-book`・雛形）

> 作成日: 2026-11-17
> ステータス: **仕様済み・着手待ち**（段階 S9。S9-0 は S8 の間に行ってよい）
> 対象: 絵本を固定レイアウトで `pdf`・`print_pdf`・`epub`・`kindle` の四つに組むための、原稿の形・契約 HTML・寸法と見開き・出力先・段の表・既定のテーマ `picture-book`・雛形 `scaffolds/picture_book/`
> 出自: `v2-s9-picture-book-consultation.md` §4（2026-11-17・Fable）。確かめの点（§0 の末尾）は同日にユーザーが「勧めのとおり」と答えた。段階の順と判断の線は `v2-plan-review-consultation.md` §4
> 組になる仕様書: `v2-architecture-spec.md`（§3.5 の固定レイアウトの経路・§4 の出力先）・`theme-contract-spec.md`（§2.7 の固定レイアウトの契約 HTML）・`video-spec.md`（動画。S10）・`v2-migration-plan.md`（段階の順・基準・判断の線）

---

## 0. 決定の一覧

| # | 問い | 決定 | 節 |
| :--- | :--- | :--- | :--- |
| 1 | 小段階 | S9-0（入口の確かめ）と S9-1〜S9-7。本書と小説の出力を組んで比べるのは S9-1 と S9-7 | §9.2 |
| 2 | 入口の確かめ | 手で作る 2 つの EPUB（A: 実体の文字を重ねる・B: ページを画像にする）を、ユーザーが KDP のプレビューで見る。製品のコードは書かない | §9.1 |
| 3 | S8b・S8c との順 | 入れ替えは自由のまま。`vs furigana`（S8c）を S9 の前提にしない。雛形の絵本の振り仮名は手で書く | §1.2 |
| 4 | 原稿の形 | 1 ファイルに複数ページ。ページは `@page`・`@spread` の行で区切る。`catalog.yml` は `CHAPTERS:` だけを使う | §2.1 |
| 5 | ページの記法 | 絵は `@page` の属性、文字は `:::{.text}` の箱。位置は名前（`.top`・`.bottom` など）か、ページに対する割合（`x=`・`y=`・`w=`） | §2.2 |
| 6 | ページで使える記法 | 段落と行内の記法だけ（ルビ・強調・傍点・縦中横・改行）。ほかは 🟡 | §2.3 |
| 7 | 重ねる文字 | PDF とクリーン EPUB は実体の文字。**Kindle は、閲覧用 PDF のページを画像にして並べる** | §2.4 |
| 8 | 寸法 | 判型は `page.use` のまま。`viewport` は判型を 96dpi の px に直した値。絵本の既定は今ある `b5_standard`（縦）。横長と正方形のプリセットを 3 つ足す | §4.1 |
| 9 | 画像の大きさ | クリーン EPUB は今の上限（長辺 2048px・WebP）。Kindle のページの画像は長辺 1920px の JPEG。大きさは出力の一覧に示し、100 MB を超えたクリーン EPUB は 🟡 | §4.2 |
| 10 | 見開き | 1 枚の絵を左右のページが半分ずつ見せる。どの出力先でも同じ作り。縦書きの絵本は S9-6 で扱う | §4.3 |
| 11 | 出力先の宣言 | §5.1 の表。`css_form` に `:none`、`packager` に `:fixed_epub`・`:fixed_epub_images` を足す | §5.1 |
| 12 | 入稿用 PDF | 組み直し。絵は塗り足しまで拡大して流用する（表紙の `cover_bleed: scale` と同じ）。本文の画像の CMYK 化は 2.0 では行わない | §5.3 |
| 13 | 表紙 | 今の `covers/` の仕組みのまま。ページの並びに表紙を入れない | §5.4 |
| 14 | テーマ | 名前は `picture-book`。位置と寸法は vs の CSS、見た目だけをテーマが書く。オプションは最初は置かない | §7 |
| 15 | 確かめ | 機械で見る条件 9 つと、目で見る 8 か所。絵本の基準 P1 を S9 の完了で作る（r5） | §9.3・§9.4 |
| 16 | 動画 | どの種類の本でも使える。仕様は `video-spec.md`（S10） | `video-spec.md` |
| 17 | 読み上げ・音声・色の管理・絵本の分冊 | 2.0 の後へ回す。固定レイアウトの分冊は 🔴 で止める | §1.3 |

**ユーザーの確かめ（2026-11-17・「勧めのとおり」）。** (2) 絵本の既定の判型を B5 の縦にする。(3) Kindle の絵本を「ページの画像」で作り、Kindle では文字の検索と読み上げができない。(4) 雛形の絵を、スクリプトで作る単純な図形の絵にする。(5) 縦書きの絵本は、遅れた場合に 2.0 の後へ回してよい。(1) の S9-0 の KDP のプレビューは、ユーザーが行う（§9.1）。

---

## 1. 範囲と前提

### 1.1 すでに決まっていること（4 本の仕様書から）

- 絵本も動く絵本も `pdf`・`print_pdf`・`epub`・`kindle` の四つで出す（`v2-design-research-brief.md` §5）。動く絵本は種類にしない。`picture_book` に動画の記法を使った本である（`v2-architecture-spec.md` §2.1）。
- 固定レイアウトの経路（`v2-architecture-spec.md` §3.5）: L1 は「ページの並び」を返す。L2・L3 は `build page spreads` の段で、ページごとに寸法の決まった 1 枚の HTML を作る。契約 HTML は、`body` に `vs-fixed` とページの種類のクラス、`head` にページの寸法の `viewport`（`theme-contract-spec.md` §2.7）。L4 は同じ仕組みで、変換の並びが固定レイアウト用。L5 の PDF は Vivliostyle（判型＝ページの寸法）、EPUB は vs が自分で梱包する。章の番号の範囲（`00`・`01–89`・`90–98`・`99`）は固定レイアウトに持ち込まない。
- 固定レイアウトの EPUB は Kindle Previewer で KPF にできない（4 版とも Mobi になる。Enhanced Typesetting はリフロー型だけ）。KDP は固定レイアウトの本を EPUB で受け付ける。`kindle` は KPF にせず EPUB を出す（`<名前>-kindle.epub`。KDP へはこの EPUB を出す）。
- 動画の実験（`v2-feasibility-notes.md` §5）: Kindle Previewer は `<video>` をエラーにする。Apple Books は H.264 と HEVC を再生する。Kobo は iOS と Android のアプリだけ。
- Web 出力（PWA）は 2.0 では作らない（`v2-architecture-spec.md` §4.6）。
- 絵本の既定のテーマは vs が `theme-contract-spec.md` §3.5 の範囲の CSS で書く（同 §6.4）。
- `book.type`・`page.layout` は本全体で一つで、分冊の巻ごとには変えない（`v2-architecture-spec.md` §5.4）。

### 1.2 段階の順

- 着手は S8 の後（`v2-migration-plan.md` §2.1）。S9-0（KDP の確かめ）は製品のコードに触れないので、S8 の間に行ってよい。答えが早いほど、S9-5 の作り方が早く決まる。
- S8b・S8c との入れ替えは自由。`vs furigana`（S8c）を S9 の前提にしない。雛形の絵本の振り仮名は手で書く。

### 1.3 2.0 で扱わないもの

- 読み上げ（EPUB の Media Overlays）・音声・絵の色の管理（CMYK）・塗り足しつきの絵・自動再生・ページごとの字数の表示（`PLANNED.md`）。
- 固定レイアウトの分冊。S9-1 で 🔴 にする（確かめる面を増やさないため）。

---

## 2. 原稿の形

### 2.1 1 ファイルに複数ページ

絵本は 16〜32 ページで、1 ページの文字は数行である。1 ファイル 1 ページにすると、文字を通して読み直すことも、ページを入れ替えることも手間になる。ファイルを分けるのは自由で、`catalog.yml` の `CHAPTERS:` に並べた順につなぐ（場面ごとに分ける使い方）。`PREFACE:` などのほかの区分は固定レイアウトでは使えず、書いてあれば 🔴。ファイル名の番号の範囲（`00`・`90`〜`99`）にも意味を持たせない。

### 2.2 ページの区切りと文字の箱

行頭の `@page` と `@spread` で区切る。今の `@pagebreak` と同じ「行の指示」の形で、ページが原稿の単位であることが一目で分かる。

```markdown
@page image=images/p01.jpg alt="森の入り口に立つ、まるくん"

むかし むかし、{森|もり}の おくに……

@spread image=images/p02-03.jpg alt="夜の森"

:::{.text .left .bottom}
まるくんは あるきました。
:::

:::{.text .right x=55% y=10% w=35%}
「だれか いますか」
:::

@page

えの ない、もじだけの ページです。

@page colophon
```

| 書き方 | 意味 |
| :--- | :--- |
| `@page image=… alt=…` | 1 ページ。絵はページいっぱいに敷く。`fit=contain` で、切らずに収める（既定は、ページを覆うように切る） |
| `@spread image=… alt=…` | 見開きの 2 ページ。1 枚の絵を左右に半分ずつ見せる |
| `@page`（属性なし） | 絵の無い、文字だけのページ |
| `@page colophon` | 奥付。vs が、今の奥付と同じ中身を作る。**置いた場所にだけ作る**（置かなければ奥付は無い） |
| `@page blank` | 白いページ |
| `title="…"` | そのページを、EPUB の目次（`nav`）と PDF のしおりに載せる題。付けたページだけが載る |
| 区切りの後の、箱に入れない段落 | テーマの決めた既定の位置の箱に入る |
| `:::{.text 位置}` … `:::` | 文字の箱。位置は名前（`.top`・`.bottom`・`.center`・`.left`・`.right` と、その組み合わせ）か、`x=`・`y=`・`w=`（箱の左上と幅。ページに対する割合）。見開きでは `.left`・`.right` でページを選び、割合はそのページに対するもの |

- 位置を割合で書くのは、PDF（mm）と EPUB（px）で同じ値が使え、判型を変えても釣り合いが保たれるためである。名前の位置は、割合を考えなくても書けるようにするためのものである。細かい見た目（箱の地の色など）は、箱にクラスを足して `custom.css` で書ける（`:::{.text .bottom .mybox}`）。
- 本扉と権利ページは、vs が作らない。絵本の本扉は絵であり、著者が 1 ページとして書く。奥付だけを vs が作るのは、書誌（`book.yml`）から組める定型の中身だからである。
- 記法の型は、`notation-implementation-guide.md` に「ページの単位（固定レイアウト）」の節を足して載せる。型の記号は、S8 で足す D 型・E 型の次にする。
- **絵に `alt` が無ければ 🟡**（原稿の行を指す）。絵本は絵が中身なので、読み上げと Kindle の画像のページ（§2.4）の代わりの文になる。
- 記法の名前（`@page`・`@spread`・`colophon`・`blank`・`fit=`・`title=`・`.text` と位置のクラス）は著者から見える名前で、S9-2 で確定したら了承待ちの一覧に載せる（`v2-migration-plan.md` §4.1）。

### 2.3 ページで使える記法と、通し方

段落と、行内の記法（ルビ・強調・太字・傍点・縦中横・行内の属性・行末の改行）だけとする。見出し・箇条書き・表・コード・数式・脚注・相互参照・索引の印・囲みは、固定レイアウトの本では 🟡 で「絵本のページでは使えません」と示し、文字として組まない（落とす）。理由は、ページの中の文字は位置の決まった小さな箱で、あふれても次のページへ送れないからである。

- 通し方: ファイルごとに、`@page`・`@spread`・`:::{.text}` を入れ物の HTML に置き換えてから、今の前処理 → VFM → 後処理のうち行内の記法に関わる段だけを通し、最後にページごとの HTML に分ける。**段の選び方（S5-4 の `STEPS` に「固定レイアウトでも走る」の印を足すか、固定レイアウト用の短い並びを別に持つか）は S9-2 で Opus が決める。** 軸は「走る段が 10 以下なら別の並び」。どちらでも、記法の実装を二重に持たない。
- 文字が箱からあふれたかは、PDF を組んだ後で見る（S9-3。箱の高さと、中の文字の最後の行の位置を `pdftotext -bbox` で比べ、あふれたページを 🟡 で示す）。難しければ、あふれの検出は 2.0 の後へ回してよい（Opus が決めて記録する）。

### 2.4 重ねる文字

PDF とクリーン EPUB は実体の文字で組む。検索・読み上げ・文字の選択ができ、`vs furigana` の結果もそのまま使える。**Kindle は、閲覧用 PDF のページを 1 枚ずつ画像にして並べる。** 理由は三つある。

1. Kindle の固定レイアウトで、重ねた文字が PDF と同じ位置・同じ書体で出るかは、端末の種類（電子ペーパー・タブレット・スマートフォン）ごとに確かめる手段が無い。画像なら、紙面が PDF と同じになることが作りで決まる。
2. 道具がすでにある（`vs pdf:pages` の PDF → JPEG）。`kindle-fixed-layout-ideas.md` の実装の素描がそのまま使える。
3. 動画のポスター画像（S10）も、PDF で置き換えた後の紙面がそのまま Kindle に届く。

失うのは、Kindle での文字の検索と読み上げ、文字の拡大（Amazon の指針の `RegionMagnification`）である。絵本の文字は大きく組むものなので、2.0 では受け入れる（2026-11-17 ユーザー了承）。画像の `alt` には、そのページの絵の `alt` と文字をつないだものを入れる。S9-0 で A が通れば、2.0 の後で実体の文字に替える余地が残る。

---

## 3. 契約 HTML（固定レイアウト）

1 ページが 1 枚の HTML。保証する要素とクラスの表は `theme-contract-spec.md` §2.7（契約 HTML の正典）にある。

- 位置を `style` の変数で渡すのは、vs の CSS（`base/fixed.css`）が 1 つの規則で読め、Kindle 用の CSS の制約（`var()` を解く）に触れないためである（Kindle は画像なので CSS を持たない。クリーン EPUB と PDF は `var()` を解する）。
- 足すだけなので、契約の版は上げない（`theme-contract-spec.md` §2.7）。`HtmlContract` に、`theme-contract-spec.md` §2.7 の表のクラスを足す（S9-2）。

---

## 4. 寸法・画像・見開き

### 4.1 判型と `viewport`

- **判型は `page.use` のプリセットで決める（今と同じ）。** 固定レイアウトで読むのは紙の大きさと、基準の字の大きさだけで、余白と行送りは読まない。
- **`viewport` は、判型を 96dpi の px に直した値にする**（B5 は 688 × 971）。CSS の 1mm は 96/25.4 px なので、同じ HTML と CSS が、Vivliostyle の PDF（`@page` の大きさ＝判型）と EPUB（`viewport`）の両方でそのまま同じ釣り合いに組まれる。寸法を二つ持たない。
- **絵本の既定の判型は、今ある `b5_standard`（B5 の縦）にする**（2026-11-17 ユーザー了承）。同人誌の印刷所は A5 と B5 の縦が標準で、横長と正方形は特別な扱いになることが多い。電子では、縦のページを 2 枚並べた見開きが、横向きのタブレットの画面にそのまま合う。
- **足すプリセットは 3 つ**: `b5l_standard`（B5 の横・257 × 182）・`a4l_standard`（A4 の横）・`sq210_standard`（210mm の正方形）。`Common::PAGE_SIZES` と `config/page_presets.yml` に、S8-3 と同じ足し方で入れる（S9-1）。値（基準の字の大きさ）は S9-6 でテーマと一緒に決め、ユーザーが紙面を見て了承する。

### 4.2 画像の大きさ

著者は印刷の解像度の絵を 1 枚だけ用意する。出力先ごとに vs が縮める。

| 出力先 | 絵の大きさ |
| :--- | :--- |
| `pdf` | 今の画像の最適化のまま |
| `print_pdf` | 元の絵のまま（縮めない） |
| `epub` | 今の上限（長辺 2048px）で WebP。見開きの絵は、2 ページぶんなので長辺 4096px まで |
| `kindle` | ページの画像は長辺 1920px の JPEG（品質 85）。定数とする |

- **大きさの知らせ。** 出力の一覧に、EPUB と Kindle 用の EPUB の大きさを示す。クリーン EPUB が 100 MB（Kobo の上限）を超えたら 🟡（`v2-architecture-spec.md` §4.5 の決めを、動画の無い絵本にも当てる）。
- Kindle の 1920px と品質 85 は、雛形の本の大きさを S9-5 で測って、1 ページ 400 KB を大きく超えるようなら下げる（Opus が決めて記録する）。

### 4.3 見開きと綴じの向き

- **見開きは、1 枚の絵を左右のページが半分ずつ見せる。** 2 ページぶんの 1 枚の HTML にはしない。PDF（単ページ）・入稿用 PDF（単ページ）・EPUB（`page-spread-left`・`page-spread-right`）・Kindle の画像のページが、どれも同じ作りになるためである。リーダーによっては左右のページの間に細い線が見えるが、受け入れる。
  - `@spread` が偶数ページ（左綴じなら左のページ）から始まらないときは 🔴 で、「前に 1 ページ足すか、`@page blank` を入れてください」と示す。表紙はページに数えないので、本文の 1 ページ目は奇数ページ（1 枚だけで見える側）である。
  - 文字の箱は、左右どちらかのページに置く。ノドをまたぐ箱は書けない。
- **綴じの向きは `traits.binding` を読む。** 右綴じ（縦書き）では、見開きの絵の右半分を先のページが見せる。
- **閲覧用 PDF** は単ページのまま出し、見開きで開くよう `PageLayout`（左綴じは `TwoPageRight`、右綴じは `Direction` と合わせる）を書く。qpdf で 1 か所書けば済むなら入れ、手間が大きければ入れない（Opus が決めて記録する）。

---

## 5. 出力先

### 5.1 宣言

`OutputTarget.for(id, traits)` が、`traits.fixed?` のときに次を返す。

| 出力先 | `transforms` | `css_form` | `finalizers` | `assets` | `packager` |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `pdf` | なし | `:layered` | なし | 画像はそのまま | `:vivliostyle_pdf` |
| `print_pdf` | なし | `:layered` | なし | 画像はそのまま（縮めない） | `:print_pdf`（組み直しだけ。導出しない） |
| `epub` | 固定レイアウト用（S9 では `MarkBody` に当たる 1 段だけ。動画の段は S10） | `:flat` | `AuthorPriority` → `InversionReport` | WebP・`<video>` | `:fixed_epub` |
| `kindle` | なし（HTML を使わない） | `:none`（新しい値。CSS を持たない） | なし | JPEG | `:fixed_epub_images` |

- `body_classes` は `vs-fixed`（どの出力先でも契約 HTML に付いている）に、`epub` では `vs-epub` を足す。
- クリーン EPUB に平らな CSS を渡すのは、リフローと同じ理由（層を外した CSS はどのリーダーでも同じに読まれる）。`custom.css` を勝たせる段もそのまま使える。
- `kindle` は閲覧用 PDF を材料にするので、`output.targets` に `pdf` が無くても、閲覧用 PDF を組む（`BuildPlan#viewing_pdf?`。入稿用だけを選んだ本が閲覧用を組むのと同じ扱い）。

### 5.2 vs が作る固定レイアウトの EPUB

`build/epub/fixed_package.rb`。`epub` と `kindle` で同じ梱包を使い、ページの中身（XHTML と CSS か、画像 1 枚か）だけが違う。

| 項目 | 中身 |
| :--- | :--- |
| OPF | `rendition:layout` は `pre-paginated`、`rendition:spread` は `landscape`、`rendition:orientation` は `auto`。`spine` の `page-progression-direction`（`traits.binding`）と、各 `itemref` の `page-spread-left`・`page-spread-right`。書誌と識別子は今の EPUB と同じ出どころ（`Epub::Opf` の識別子の安定化を使う） |
| Kindle だけ | Amazon の固定レイアウトの指針のメタデータ（`fixed-layout`・`original-resolution`・`orientation-lock`・`primary-writing-mode`・`book-type`）。**どれを書くかは S9-0 で通った版に合わせる** |
| `nav` | `title=` の付いたページだけを目次に載せる。1 つも無ければ、最初のページだけを載せる（`nav` は必須のため）。`landmarks` に表紙と本文の始まり |
| 表紙 | 今の表紙の画像（`covers/`。`output.epub.embed`・`output.kindle.embed` の決めも今のまま） |
| ページ（`epub`） | 1 ページ 1 枚の XHTML・平らな CSS 1 枚・WebP の絵・書体 |
| ページ（`kindle`） | 1 ページ 1 枚の XHTML で、中は画像 1 枚（と、S10 のリンクの箱） |
| 書体（`epub`） | **文字の箱で使う書体を同梱する。** 固定レイアウトでは、読者の端末の書体で組むと箱から字があふれる。`VariantGlyphFont` と同じ ttfunk の部分集合で、使った字だけにする。部分集合を作れない書体（TTF でないもの）は丸ごと同梱し、大きさを出力の一覧に示す。書体の利用の条件は著者が確かめるもので、マニュアルに書く（`v2-migration-plan.md` §2.4 の 14） |
| 梱包 | `mimetype` を無圧縮で先頭に置く zip。素材は、種類（MIME）つきの一覧で受ける形にしておく（S10 で動画がそのまま入る） |

- 合わせる指針は、クリーン EPUB は EPUB 3 の規格と Apple Books の Asset Guide、Kindle は Amazon の指針とする。Kobo は規格どおりの固定レイアウトを読むので、別の作りを持たない。

### 5.3 入稿用 PDF

固定レイアウトの本は、閲覧用 PDF から導出せず、組み直す（今の `full_bleed` の経路。`output.print_pdf.full_bleed` の値に関わらず）。

- **塗り足しは、vs が絵を塗り足しの端まで拡大して作る。** 表紙の `cover_bleed: scale` と同じ考え方で、著者は判型どおりの絵を用意すれば済む。B5 で 3mm の塗り足しなら、絵は 3% ほど大きく刷られる。文字の箱の位置は変わらない。
- 塗り足しを含めた絵を著者が用意する形（表紙の `_bleed` の画像に当たるもの）は、2.0 では作らない。要望が出たら足す（`PLANNED.md`）。
- 本文の画像の CMYK 化は 2.0 では行わない（今の技術書と同じく RGB のまま）。`PLANNED.md` に「本文の画像の CMYK 化（絵本ではとくに要る）」の項を足した。
- 印刷に出す本でページ数が 4 の倍数でないときは、💡 で知らせる（中綴じでは 4 の倍数が要る。止めはしない）。

### 5.4 表紙

今の `covers/` の仕組みのまま使う。絵本の表紙は絵なので、著者が画像を置く形（`book.cover` に自分の画像の名前）が中心になる。ページの並びの 1 枚目を表紙にする形は取らない。理由は、表紙が本文と別のファイルで入稿される今の流れ・EPUB の表紙の扱い・S8b のくるみ表紙（`cover-spread-spec.md`）が、どれも `covers/` を前提にしているためである。

---

## 6. 段の表と、ほかのコマンド

| 段 | 固定レイアウトの本で |
| :--- | :--- |
| `optimize images`・`book-settings.css` の生成・`prepare cover assets` | 走る |
| **`build page spreads`**（新） | 走る。`preprocess sections`・`convert sections html`・後処理に替わる |
| `techbook post-process` | 走る（ページの HTML に当てる。PDF の書体の対策は種類に依らない） |
| `build overall pdf`・表紙との結合・圧縮・改名 | 走る |
| しおり（`outline`） | `title=` の付いたページがあれば作る |
| `print pdf` | 走る（組み直し） |
| `generate epub` | 走る（中身は固定レイアウトの梱包） |
| `preprocess sections`・`convert sections html`・`index scan and build`・`generate part title pages`・`generate toc html`・前付（本扉・権利ページ）の生成・`backlink dedup`・`check chapter leads`・`prepare theme images`・回転した表の画像 | 載らない |

- `vs build` の単章のビルド（`vs build 21`）は、固定レイアウトでは「そのファイルのページだけを PDF に組む」とする。
- `vs preflight` は、`build page spreads` の検査（§2）を走らせる。
- `vs lint` は、`contents/` のファイルの文字に掛ける。`@page`・`@spread` の行と `:::{.text …}` の行は、校正の対象から外す（`NotationGuard` に足す）。規則の組は種類の既定の `minimal`。
- `vs metrics` は `metrics.use: none` なので、字数と漢字の水準だけを示す。ページごとの字数を示すかは、2.0 の後で考える。
- `vs create`・`vs rename` などの章の番号を扱うコマンドは、固定レイアウトの本でもファイルの単位で働く。番号の範囲の意味（前書き・付録）だけが無い。食い違いが出たら、そのコマンドを固定レイアウトで 🔴 にして 2.0 の後へ回してよい（Opus が決めて記録する）。

---

## 7. テーマ `picture-book`

- **名前は `picture-book`。** `novel` と同じく、本の種類の名前にする（`theme-contract-spec.md` §10 の論点 1）。
- **分担。** 位置と寸法は vs の CSS、見た目はテーマが書く。

  | 置き場 | 書くもの |
  | :--- | :--- |
  | `stylesheets/base/fixed.css`（vs。base 層。固定レイアウトの本の入口にだけ入れる） | `@page` の余白を 0 に・`body.vs-fixed` の大きさ・`vs-page-art` と絵の敷き方（覆う・収める・見開きの半分）・`vs-text` の位置（名前のクラスと `--vs-x` など）・入稿用の塗り足しへの拡大。`vs-text` と `figure.vs-video` に同じ位置の規則を当てる |
  | `themes/picture-book/`（テーマ） | 文字の箱の書体・字の大きさ・行送り・字の色・箱の地（白い板・影・なし）・既定の位置（箱に入れない段落の置き場）・文字だけのページと奥付の組み方 |

- **`theme.yml`**: `supports.layout: [fixed]`・`supports.writing_mode: [horizontal, vertical]`（縦書きを S9-6 で作らなかった場合は `[horizontal]`）・`supports.targets` は四つ・`features:` は空・`options:` は最初は置かない（`novel` と同じく、迷う項目は足さない）。`tokens:` に、文字の箱の値（字の大きさ・色・地の色）を公開する変数として置く。名前は `--book-*` の決まりに従い、S9-6 で決める（了承待ちの一覧に載せる）。
- 字の大きさは、ページの幅に対する割合ではなく pt で書く（判型のプリセットの基準の字の大きさから求める）。`viewport` が判型と同じ釣り合いなので、EPUB でも同じ見た目になる。
- **リフローのテーマ（`standard`・`novel`）を固定レイアウトの本で選ぶと、`supports.layout` の検査が 🔴 で止め、固定レイアウトに対応するテーマの名前を示す**（S6-3 で作った検査が、S9 で 🔴 を外すと働く）。逆に、`picture-book` をリフローの本で選んでも同じ検査で止まる。

---

## 8. 雛形 `scaffolds/picture_book/`

12 ページの短い絵本。

- 絵は、**リポジトリの中のスクリプトで作る、単純な図形の絵**にする（丸・三角・四角の登場人物。2026-11-17 ユーザー了承）。著作権の問題が無く、作り直せて、判型を変えても作り直せる。用意できる絵があれば、S9-7 の前にユーザーが替えてよい（雛形は `vs new` で著者の手元に写る）。スクリプトは `scripts/` に置く。
- 中身: 絵と文字のページ・見開き 2 組・文字だけのページ・ルビ（手で書く）・`title=` の付いたページ 2 つ・`@page colophon`・表紙（`covers/` に絵）。
- `book.yml` は絵本で意味のあるキーだけを載せる。
- `gem build` の大きさを S9-7 で記録する。1.0.1 の 2 倍を超えたら、雛形の絵の画素数を下げる（`v2-migration-plan.md` §2.4 の 11）。

---

## 9. 段階ごとの完了の条件と確かめ方

### 9.1 S9-0 入口の確かめ

KDP が受け付けるかは Kindle の出力だけの危険で、クリーン EPUB の梱包はどちらにしても要る。そこで、確かめのために製品のコードを先に書くことはしない。`v2-feasibility-notes.md` §7 の作り直しの手順で、スクラッチに次の 2 つの EPUB を作る（どちらも 8 ページ・B5 縦・表紙つき・見開き 1 組・EPUBCheck がエラーと警告 0）。

| 版 | 中身 | 見る理由 |
| :--- | :--- | :--- |
| A | 絵の上に実体の文字を `position: absolute` で重ねる。ルビつき。リンクを 1 つ | クリーン EPUB と同じ作りが Kindle で通るか |
| B | ページ全体を 1 枚の画像にする（文字は絵に焼いてある）。画像の上に、透明な `<a>` の箱を 1 つ重ねる | §2.4 の決定（Kindle は画像のページ）が通るか。動画のリンク（S10）が置けるか |

ユーザーが KDP に下書きとして上げ（出版はしない）、プレビューで次を見る。(1) 受け付けられる。(2) ページの順と、見開きの左右。(3) 絵がページいっぱいに出る。(4) A の文字の位置とルビ。(5) B のリンクを押せる。(6) 表紙。結果は `v2-feasibility-notes.md` §4 に追記する。

| 結果 | 手 |
| :--- | :--- |
| B が通る | 計画どおり。Kindle は画像のページで作る。A の結果は記録だけする（2.0 の後で、実体の文字に替えるかを考える材料） |
| B の表示は通るがリンクが効かない | Kindle は画像のページで作る。動画のリンクは、S10 で、ポスターの下に URL を字で焼く形にする |
| A だけが通る | Kindle もクリーン EPUB と同じ梱包にする（S9-5 が小さくなる） |
| どちらも通らない | **ユーザーが選ぶ**: (ア) 絵本の `kindle` を 2.0 の対象から外す（`TraitCombinationCheck` が 🔴 で止め、Kindle Create で作る手順をマニュアルに書く。`v2-migration-plan.md` §4.4 の「い」）。(イ) 原因を調べる期間を置く（Amazon の指針のメタデータを変えた版を 2 回まで）。勧めは (イ) を 1 回行ってから (ア) |

- KDP への登録はリポジトリの外に出る作業なので、ユーザーが行う（`v2-migration-plan.md` §4.1 の「止めて選んでもらう」）。Opus は 2 つの EPUB と見る点の一覧を用意する。

### 9.2 S9 の小段階

| 小段階 | 作るもの | 確かめ |
| :--- | :--- | :--- |
| S9-1 軸を開く | `OutputTarget.for(id, traits)`（固定レイアウトの宣言は中身が空の枠でよい）。段の表の `!traits.fixed?` の条件（`v2-architecture-spec.md` §3.3）。`BuildPlan#derive_print?` に `!traits.fixed?`、`#viewing_pdf?` に「固定レイアウトで `kindle`」を足す。判型のプリセット 3 つ（§4.1）。`BookProfile` の `picture_book` に `theme.name`・`page.use`。固定レイアウトの分冊と、`CHAPTERS:` のほかの区分の 🔴。固定レイアウトを止める 🔴 はまだ外さない | **本書と小説を、その時点の基準と比べる。** `Common::CONFIG` の書き出しと、段の並び（S5-3 と同じ 25 通りに N1 の設定を足す）が前後で同じ。B1 の `pdf`・`epub`・`kindle` を組み、PDF の画素・EPUB・Kindle 用 EPUB が同じ（`EpubFlow` が宣言の引き方を変えるため） |
| S9-2 ページの原稿と契約 HTML | 原稿をページに分ける読み込み（§2）・`build page spreads` の段・`stylesheets/base/fixed.css`（§7）・`HtmlContract` に `theme-contract-spec.md` §2.7 のクラス・原稿の検査（見開きの偶奇・絵の縦横比・`alt`・使えない記法） | 本書に触れない（新しい段は固定レイアウトの本でだけ載る）ことを段の並びで見る。材料のテーマ（`supports.layout: [fixed]`）と 6 ページの材料の本で、ページごとの HTML が出て、`HtmlContract` の検査が通る。検査ごとのテスト |
| S9-3 PDF と入稿用 PDF | ページの HTML から `vivliostyle.config.js` を作る・表紙との結合・入稿用の組み直しと塗り足し（§5.3）・`techbook post-process` をページの HTML に当てる・固定レイアウトを止める 🔴 を `pdf`・`print_pdf` について外す | 材料の本で、`pdfinfo` の寸法とページ数、入稿用の TrimBox・BleedBox、文字の箱の位置（`pdftotext -bbox`）、Type 3 の書体が 0 |
| S9-4 クリーン EPUB | `build/epub/fixed_package.rb`（§5.2）・書体の同梱・`nav`・`epub` について 🔴 を外す | EPUBCheck が致命・エラー・警告とも 0。OPF の `rendition:*`・`page-spread-*`・`viewport`。Apple Books で §9.3 の 8 か所 |
| S9-5 Kindle（画像のページ） | 閲覧用 PDF のページを画像にして梱包する（`:fixed_epub_images`）・`<名前>-kindle.epub`・`kindle` について 🔴 を外す | EPUBCheck。Kindle Previewer で開いて 8 か所（変換の記録は Success・エラー 0。Enhanced Typesetting は Not Supported が正しい） |
| S9-6 テーマ `picture-book` と、縦書きの絵本 | `themes/picture-book/`（§7）・`vs theme:check`。`page.writing_mode: vertical` の固定レイアウト（文字の箱の `writing-mode`・右綴じでの見開きの左右） | `vs theme:check picture-book` が 🟡 0。縦書きの材料の本で、ページが右から左へ進み、見開きの左右が合う。プリセットの値と `picture-book` の紙面を、ユーザーが見て了承する |
| S9-7 雛形と完了の確かめ | `scaffolds/picture_book/`（§8）・`vs new --type picture_book`・`vs lint` と `vs preflight` の扱い（§6）・`book_profile_test.rb` の (2) | §9.3 の機械の条件と目で見る 8 か所。**全部の比べ**（B1〜B5・N1）。`rake test`・`rake test:layout`・`rake test:standard`・`rake test:release`。ユーザーが、雛形の Kindle 用の EPUB を KDP のプレビューで見る。その後、基準を r5 に上げて P1 を足す |

S9 の中の決まり:

1. **固定レイアウトを止める 🔴 は、出力先ごとに外す。** S9-3 で PDF、S9-4 で EPUB、S9-5 で Kindle。途中の版で、作っていない出力先を選んだ本が壊れた出力を出さないためである。
2. **S9-2〜S9-6 は、本書と小説の出力を組み直さない。** 触るのは固定レイアウトの本でだけ走るコードである。段の並びが前後で同じことと `rake test` で足りる。共通の部分（`EpubFlow`・`OutputTarget`・段の表）に手を入れることになったら、その小段階で B1 と N1 を組んで比べる。
3. **縦書きの絵本（S9-6 の後半）は、S9-1〜S9-5 が計画どおりに進んだときに作る。** 遅れていれば、`page.writing_mode: vertical` と `page.layout: fixed` の組み合わせを 🔴 で止めて 2.0 の後へ回す（2026-11-17 ユーザー了承。遅れたと判断した時点で、ユーザーに知らせる）。作りは小さい（文字の箱の組方向と、見開きの左右の入れ替え）ので、勧めは「作る」である。
4. **S10 のために、S9 のうちに作っておくこと**（作り直しを避けるため）。(1) 固定レイアウトの EPUB の梱包は、素材を種類（MIME）つきの一覧で受ける（§5.2）。(2) ページの中の箱の位置の決め方は、文字の箱に限らない書き方にする（§7）。(3) `BuildPlan#derive_print?` は、固定レイアウトでは常に偽にする（S9-1）。(4) Kindle の固定レイアウトを画像のページで作るので、動画の置き換えを Kindle の固定レイアウト用に別に書かなくて済む。

### 9.3 S9 の完了の条件

`scaffolds/picture_book/` の本で見る。

機械で見るもの:

1. 四つの出力先が終了コード 0 で組め、🔴 と 🟡 が 0。
2. PDF の紙の寸法がプリセットの値で、ページ数が原稿のページ数（＋表紙）と合う（`pdfinfo`）。
3. 入稿用 PDF の TrimBox と BleedBox が合い、絵が BleedBox の端まである（ページの端の画素が白でない）。
4. 文字の箱の位置が、原稿の割合と合う（`pdftotext -bbox`。許す差は 1mm）。
5. Type 3 の書体が 0。
6. 契約 HTML に `theme-contract-spec.md` §2.7 のクラスがあり、`HtmlContract` の検査が通る。
7. クリーン EPUB と Kindle 用の EPUB の EPUBCheck が、致命・エラー・警告とも 0。OPF の `rendition:layout`・`page-progression-direction`・`page-spread-*` が合う。
8. Kindle Previewer が Kindle 用の EPUB を開ける（変換の記録が Success・エラー 0）。
9. クリーン EPUB が 100 MB 未満。Kindle 用の EPUB の大きさを記録する。

目で見るもの（PDF・Apple Books・Kindle Previewer のそれぞれで。撮った画面を基準に残す）: 表紙・最初のページ・見開き（左右がつながる）・絵に重ねた文字とルビ・文字だけのページ・`title=` からの目次・奥付・ページをめくる向きの 8 か所。Apple Books では、文字の箱が PDF と同じ位置にあり、書体が同梱したものであることを見る。**KDP のプレビューは、S9-7 でユーザーが雛形の Kindle 用の EPUB を上げて見る**（S9-0 と同じ 6 点）。

### 9.4 絵本の基準

S9-7 の完了のコミットで、基準を r5 に上げ、`P1`（`scaffolds/picture_book/` の本の四つの出力先・画面）を足す。決まり（`v2-migration-plan.md` §3.2）のとおり B1〜B5 と N1 も組み直す。S10 以降は、P1 を PDF の画素と `epub_diff.rb` で守る（Kindle の中間生成物の比べは、固定レイアウトでは使わない。Kindle 用の EPUB を `epub_diff.rb` で比べる）。

---

## 10. 論点（未決）

| # | 点 | 決める時点 | 判断の軸・結果ごとの手（扱いは `v2-migration-plan.md` §4.1） |
| :--- | :--- | :--- | :--- |
| 1 | KDP が受け付けるか | S9-0（ユーザー） | §9.1 の表 |
| 2 | Vivliostyle が、ページごとの HTML（`@page` の余白 0・絵をページいっぱいに・`object-fit`・見開きの半分）を寸法どおりに組めるか | S9-2 の最初（材料の本を 1 回組む） | 見開きの半分が `object-fit` と `object-position` で組めなければ、絵を前もって左右に切った 2 枚にする（`build page spreads` が切る）。位置の変数が効かなければ、`style` に直接 `left`・`top`・`width` を書く。Opus が決めて記録する |
| 3 | Apple Books が、同梱した書体と重ねた文字を PDF と同じ位置に出すか | S9-4 | 位置がずれるなら、原因が書体（同梱が効いていない）か単位かを分ける。直せないときは、クリーン EPUB も画像のページにして `alt` に文字を入れる（実体の文字を失う。ユーザーに見せて了承を得る＝止めて選んでもらう） |
| 4 | Kindle のメタデータの組 | S9-0 で通った版に合わせる | |
| 5 | Kindle のページの画像の大きさ（1920px・品質 85） | S9-5 | 雛形の本で 1 ページ 400 KB を大きく超えたら下げる。Opus が決めて記録する |
| 6 | 固定レイアウトでも走る前処理の段の選び方 | S9-2 | 走る段が 10 以下なら別の並び（§2.3）。Opus が決めて記録する |
| 7 | 縦書きの絵本を 2.0 に含めるか | S9-5 の後 | §9.2 の決まり 3（遅れていれば 2.0 の後へ。ユーザー了承済み） |
| 8 | 文字のあふれの検出 | S9-3 | 難しければ 2.0 の後（Opus が決めて記録する） |
| 9 | 足すプリセットの値・テーマの `tokens:` の名前と値 | S9-6。値はユーザーが紙面を見て了承 | |
| 10 | 雛形の絵の出どころ | S9-7 の前（スクリプトの図形の絵で了承済み。替えるならユーザー） | §8 |
| 11 | 読み上げ（EPUB の Media Overlays）・音声・絵の色の管理（CMYK）・塗り足しつきの絵・自動再生・ページごとの字数の表示 | 2.0 の後 | `PLANNED.md` |
| 12 | 固定レイアウトの分冊 | 2.0 の後 | S9-1 で 🔴 にする |
| 13 | 4 本目の答えの「う」（絵本と動画を 2.1 へ） | §10 の 2・3 などの危険が二つ以上当たったとき | `v2-migration-plan.md` §4.4。ユーザーに示す |
