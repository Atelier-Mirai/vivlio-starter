# カバー画像の生成

:::{.chapter-lead}
一冊の本でも、画面で見る PDF、印刷所へ渡す PDF、電子書籍では、表紙に必要な画像形式が異なります。`vs cover` は、一つのデザインから用途に合った表紙画像（カバー）を生成するコマンドです。同梱の `light` / `dark` テーマを使う場合も、独自の画像や SVG を用意する場合も、準備から生成・確認までの流れは共通です。
:::

表紙の元になる画像は `covers/` に置きます。表紙は `vs build` がビルドのたびに作り直して本に組み込むので、`vs cover` を先に実行する必要はありません。`vs cover` は、デザインを直したときや、入稿用・電子書籍用の表紙だけを渡し直すときに、本文を組まずに表紙だけを作るために使います。

## 表紙のデザインを選ぶ

:::{.section-lead}
`book.yml` の `book.cover` に、使うデザインの名前（テーマ名）を書きます。同梱の `light`・`dark` を使うか、自分で用意した画像（PNG・JPEG・WebP）または SVG を使うかを選べます。
:::

```yaml
book:
  cover: light     # 同梱の明るいテーマ（既定）
  # cover: dark    # 同梱の暗いテーマ
  # cover: floral  # 著者が用意した covers/frontcover_floral.png など
```

`cover: <テーマ名>` を指定すると、表紙と裏表紙のそれぞれについて、次の順に元の画像を探します。

**元の画像を探す順序**

| 優先順位 | 探索先 | 説明 |
|:---:|:---|:---|
| 1 | `covers/frontcover_<テーマ名>.png` | 著者が用意した画像 |
| 2 | `covers/frontcover_<テーマ名>.svg` | 著者が用意した SVG |
| 3 | `covers/bundled/frontcover.svg` | 同梱のテンプレート（`light`・`dark` のみ） |

1 の画像は、PNG のほかに JPEG（`.jpg`・`.jpeg`）と WebP（`.webp`）も使えます。裏表紙は `backcover_<テーマ名>` の名前で、同じ順に探します。

テーマ名には、`floral`・`master`・`my-floral` のように好きな名前を付けられます。使える文字は、半角の英小文字・数字・`_`（アンダースコア）・`-`（ハイフン）です。

独自のテーマ名で画像も SVG も見つからないときは、🔴 で報告して表紙を作りません。テーマ名やファイル名の書き誤りは、表紙を作る時点で分かります。

### light / dark テーマ

`light` または `dark` を選ぶと、同梱のテンプレート（`covers/bundled/` の SVG）に、それぞれのテーマの色を当てて表紙を作ります。表紙には `book.yml` の書名（`main_title`）・副題（`subtitle`）・著者名（`author`）・連載名（`series`）・発行日（`release`）が入ります。本の情報を設定すれば、画像を用意しなくても表紙ができます。

### 独自の SVG を使う

表紙を `frontcover_<テーマ名>.svg`、裏表紙を `backcover_<テーマ名>.svg` の名前で `covers/` に置き、`book.yml` にテーマ名を書きます。デザインごとに名前を変えて置いておけば、`cover:` を書き換えるだけで別の案に切り替えられます。

:::{.diagram}
```text
covers/
├── frontcover_floral.svg    # 著者が用意した花柄デザイン
└── backcover_floral.svg
```
:::

SVG の中に `{{title}}`・`{{subtitle}}`・`{{author}}`・`{{series}}`・`{{release}}` と書いた箇所には、ビルドのときに `book.yml` の値が入ります。書名や著者名を変えても、SVG を編集し直す必要はありません。

SVG は、判型と同じ縦横比の `viewBox` で描きます（A4 なら `viewBox="0 0 595 842"`）。入稿用の表紙の塗り足し（@pageref:print-cover）には、`viewBox` の外側に描いた部分が使われます。背景のように紙の端まで届けたい要素は、四辺とも `viewBox` の外へ 3 mm 以上（A4 の `viewBox` なら 9 以上）広げて描いてください。`viewBox` の中だけに描くと、塗り足しは白になります。同梱の `covers/bundled/frontcover.svg` は背景と上下の帯を外側まで描いてあり、描き方の見本になります。

### 独自の画像を使う

表紙を `frontcover_<テーマ名>.png`、裏表紙を `backcover_<テーマ名>.png` の名前で `covers/` に置きます。JPEG なら拡張子は `.jpg`、WebP なら `.webp` です。次は、テーマ名を `master` にした例です。

:::{.diagram}
```text
covers/
├── frontcover_master.png
└── backcover_master.png
```
:::

画像は、仕上がりの判型を 350 dpi で表す大きさで用意します。入稿用の表紙を作るとき、300 dpi に満たない画像には 🟡 で警告します。

**判型ごとの画像の大きさ（塗り足し 3 mm のとき）**

| 判型 | 画像の大きさ | 塗り足し込み（`_bleed`） |
| :--- | :--- | :--- |
| A4（210 × 297 mm） | 2,894 × 4,093 px | 2,976 × 4,175 px |
| B5（182 × 257 mm） | 2,508 × 3,541 px | 2,590 × 3,623 px |
| A5（148 × 210 mm） | 2,039 × 2,894 px | 2,121 × 2,976 px |

作図のソフトで下敷きにできるよう、判型ごとの雛形を `covers/templates/` に用意しています（`frontcover_a4.png`・`backcover_a4.png` など）。雛形には、画像の大きさ、裁ち落とされる範囲、電子書籍で切れる範囲、文字を置ける範囲を書き込んであります。雛形の文字と線は使い方を示すためのものなので、削除してから、`covers/frontcover_<テーマ名>.png` などの名前で保存します。

入稿用の表紙の塗り足しは、次のいずれかの方法で埋めます。

- 塗り足しまで描いた画像を、名前に `_bleed` を付けて置く（`covers/frontcover_master_bleed.png` など）。大きさは上の表の右の列のとおりで、この画像をそのまま使う
- 何も置かなければ、仕上がりの大きさの画像を塗り足しまで拡大して使う（`output.print_pdf.cover_bleed: scale`、既定）。画像の四辺は裁ち落とされる
- `cover_bleed: keep` にすると拡大せず、塗り足しは白になる。紙の端まで色の付いていないデザインに使う

## 表紙を生成する

:::{.section-lead}
デザインを選んだら、`vs cover` で表紙を生成します。作る形式は `output.targets` で、大きさは判型で決まります。
:::

```bash
vs cover
```

:::{.text-table}
`vs cover` は `book.yml` の `book.cover`・`page.use`・`output.targets` を読み、必要な表紙を作ります。判型は `page.use` に選んだプリセットの判型（`a4_custom` なら A4）で、表紙が対応する判型は A4・B5・A5 です。

**`output.targets` と作る表紙**

| `output.targets` | 作る表紙 |
|:---|:---|
| `pdf` | 閲覧用 PDF（RGB） |
| `print_pdf` | 入稿用 PDF（CMYK） |
| `epub`・`kindle` | 電子書籍用 JPEG |
:::

入稿用と電子書籍用の表紙はプロジェクト直下に置かれるので、開いて確かめてください。閲覧用は、`vs build` で本に組み込んだ姿で確かめます。

### 分冊の本の表紙

分冊の本では、巻の `id`（`catalog.yml` で巻に付けた名前）を添えると、その巻の表紙を作ります。たとえば下巻に `id: lower` と付けたなら `vs cover lower` です。`vs cover all` なら全巻の表紙を作ります。巻の `cover` に書いたテーマを使い、`light`・`dark` には巻の書名が入ります（@pageref:volume-book-values）。プロジェクト直下の表紙の名前には、`mybook_lower_frontcover_v0.1.0.pdf` のように巻の `id` が付きます。

## 生成される表紙

:::{.section-lead}
閲覧・入稿・電子書籍では、表紙に求められる大きさと色が異なります。
:::

### 閲覧用 PDF

仕上がりの判型の大きさで、色は RGB です。画像は 350 dpi の画像として、SVG は図形のまま PDF にします。この表紙は、`vs build` が本文の前後に結合します。結合しないときは、`output.pdf.combined` を `false` にします（@chapref:ch-build）。

### 入稿用 PDF @print-cover

仕上がりの判型に塗り足し（`output.print_pdf.bleed`、既定 3 mm）を加え、トンボを付けた PDF です。色は Japan Color 2001 Coated の ICC プロファイルで CMYK に変換し、PDF/X-1a:2001 として書き出します。表紙と裏表紙は別のファイルで、プロジェクト直下に置かれます（`mybook_frontcover_v0.1.0.pdf`・`mybook_backcover_v0.1.0.pdf`）。

塗り足しは、裁断で切り落とされる部分です。書名や著者名などは、仕上がりの端から十分に離して置いてください。

CMYK で表せる色の範囲は RGB より狭いので、鮮やかな青や緑は近い色に置き換わり、閲覧用の表紙よりくすんで見えます。入稿の前に入稿用の表紙 PDF を開いて色を確かめ、変わりすぎた色はデザインの側で選び直してください。

:::{.note}
**PDF/X-1a とは**

PDF/X-1a は、商業印刷向けの PDF の規格です。色を CMYK に限ることや、フォントを埋め込むことなどが定められています。準拠しているかは、Adobe Acrobat Pro のプリフライトで確かめられます。入稿先に固有の指定があるときは、その条件も確かめてください。
:::

### 電子書籍用 JPEG

EPUB と Kindle は同じ 1 枚の JPEG を使います。大きさは KDP の推奨の 1,600 × 2,560 px、色は sRGB、JPEG の品質は 95 です。Display P3 などで描いた画像も、sRGB に変換して書き出します。プロジェクト直下には `mybook_frontcover_v0.1.0.jpg` の名前で置かれます。

EPUB には、この表紙が埋め込まれます。Kindle 用の `.kpf` には表紙を含めません。KDP では、本と表紙を別々にアップロードする決まりだからです。KDP の登録画面で、プロジェクト直下の JPEG を表紙としてアップロードしてください（@chapref:ch-build）。

:::{.note}
**電子書籍用の表紙は左右が切り落とされます**

元の画像を高さ 2,560 px に縮めてから、中央の幅 1,600 px を切り出します。A4 判の画像（2,894 × 4,093 px）なら、縮めた横幅は約 1,810 px なので、左右を約 105 px ずつ切り落とします。同梱の `light`・`dark` の表紙では、左右の細い金の縦線がこの切り落としにかかり、上下の金の帯だけが残ります。

タイトルや著者名が左右の切り落としにかからないよう、中央寄りへ配置してください。
:::

