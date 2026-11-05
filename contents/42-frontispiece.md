# 扉絵と装飾画像

:::{.chapter-lead}
章の始まりと節見出しは、読者がいま本のどこにいるかを確かめる目印になります。Vivlio Starter では、章扉の背景画像（frontispiece）と節見出しの装飾画像（ornament）を使う `image`、色と文字を中心に組む `simple` の二つのスタイルを選べます。本章では、それぞれの設定と画像の用意のしかた、テーマカラーと見出し記号の選び方を見ていきます。
:::

## 扉絵と装飾画像とは

:::{.section-lead}
扉絵（frontispiece）は章扉の背景に置く縦長の画像、装飾画像（ornament）は節見出しの背景に置く横長の画像です。同じ絵柄を使っても、別の画像を組み合わせても構いません。
:::

扉絵の上には、章番号・章題・リード文（`:::{.chapter-lead}`）が載ります。装飾画像は節見出し（`## 見出し`）の左上と右下に飾りを添え、その間に節番号と節題が載ります。章扉と節見出しの絵柄をそろえると、ページをめくっても同じ本のデザインが続いていると分かります。

EPUB・Kindle では、扉絵から作った横長の画像に章番号と章題を入れて、章の先頭に置きます。リード文は画像に入れず、そのすぐ下に文字として続きます。読者が選んだ文字の大きさで読めるようにするためです。

## テーマスタイルの選択

:::{.section-lead}
最初に `theme.style` を選びます。画像を章扉と節見出しへ使うなら `image`、画像を使わず色と文字で組むなら `simple` です。どちらも同じ原稿で切り替えられるので、仕上がりを見ながら選べます。
:::

| 項目 | image スタイル | simple スタイル |
|:---|:---|:---|
| 章扉 | 扉絵（frontispiece）の上に章題を組む | テーマカラーと書体で組む |
| 節見出し | 装飾画像（ornament）を添える | テーマカラーの線で飾る |
| 用意するもの | 画像（同梱の 12 種類から選べる） | なし |
| 紙面の印象 | 華やか・個性的 | 簡素・端正 |

章ごとの雰囲気を絵で伝えたい本や、読者の目を楽しませたい入門書には `image` が、画像を用意する手間をかけずに本文の見え方を先に固めたい本には `simple` が向いています。設定を一行変えるだけで切り替えられるので、両方で組んで見比べてから決めても構いません。

スタイルで組み方が変わるのは本文の章です。付録は、`image` の本でも `simple` で組みます。前書き・後書きは、どちらのスタイルでも専用のデザインで組みます。

## image スタイルの設定

:::{.section-lead}
`theme.style: image` にすると、章扉には扉絵、節見出しには装飾画像が使われます。まずは同梱画像で仕上がりを確かめ、必要なら本の内容に合った独自画像へ差し替えます。
:::

### 設定方法

扉絵と装飾画像に使う画像の名前を、`frontispiece` と `ornament` の `image` に書きます。

```yaml
theme:
  style: image
  frontispiece:
    image: sakura  # 章扉の画像
  ornament:
    image: sakura  # 節見出しの画像
```

画像の名前のほかに書く項目がなければ、名前だけを書く形も使えます。次の例は、章扉に桜、節見出しに梅を使います。

```yaml
theme:
  style: image
  frontispiece: sakura
  ornament: ume
```

### 同梱画像を使う

花を題材にした画像が 12 種類同梱されています。設定には、花の名前をローマ字で書きます。画像をまだ用意していない段階でも、紙面の見え方を試せます。

| | | |
|:---:|:---:|:---:|
| ![suisen](suisen.webp)<br>水仙 `suisen` | ![ume](ume.webp)<br>梅 `ume` | ![nanohana](nanohana.webp)<br>菜の花 `nanohana` |
| ![sakura](sakura.webp)<br>桜 `sakura` | ![suzuran](suzuran.webp)<br>鈴蘭 `suzuran` | ![ajisai](ajisai.webp)<br>紫陽花 `ajisai` |
| ![asagao](asagao.webp)<br>朝顔 `asagao` | ![himawari](himawari.webp)<br>向日葵 `himawari` | ![kikyo](kikyo.webp)<br>桔梗 `kikyo` |
| ![kosumosu](kosumosu.webp)<br>秋桜 `kosumosu` | ![kiku](kiku.webp)<br>菊 `kiku` | ![tsubaki](tsubaki.webp)<br>椿 `tsubaki` |

### 独自画像を使う

本の題材に合わせた画像を使うときは、`stylesheets/images/` に置き、設定には拡張子を除いた名前を書きます。画像は WebP（推奨）・PNG・JPEG を使えます。

```yaml
theme:
  frontispiece: my_image  # stylesheets/images/my_image.webp
  ornament: my_image
```

用意する画像は、同梱画像と同じく、左上と右下の隅に飾りを置き、ほかを透明にした 1 枚です（同梱画像は 2048×2048 ピクセルの正方形）。`vs build` はこの画像を対角線で二つに分け、二つの飾りの間を広げて、扉絵用の縦長の画像と、節見出し用の横長（横:縦 = 2.39:1）の画像を作ります。

** 元の画像（左）から作られる扉絵用（中）と節見出し用（右）の画像 **
![桜の画像から作られる縦長と横長の画像](sakura-variants.webp){width=100% border=off}

:::{.text2-img}
扉絵には、ページ全体に描いた一枚の絵も使えます。縦横比が用紙に近い画像（A 判・B 判なら縦:横 ≒ 1.41:1）は、分けずにそのまま扉絵に使われます。一枚の絵の例として、`vs new` で作った本には額縁の形の `floral.webp` が `stylesheets/images/` に入っています。次のように書くと、章扉は右の図のようになります。

```yaml
theme:
  frontispiece: floral
```

** 一枚の絵を扉絵にした章扉 **
![額縁の形の一枚の絵を扉絵にした章扉](floral-chapter.webp)
:::

節見出しは左右の端の飾りだけが見えるように組まれるので、装飾画像には隅に飾りを置いた画像を使います。一枚の絵を扉絵にするときも、`ornament` には同梱画像などを指定します。

作られる画像の飾りの位置を自分で決めたいときは、扉絵用の `画像名_portrait.webp`（用紙と同じ縦横比）と、節見出し用の `画像名_landscape.webp`（2.39:1）を `stylesheets/images/` に置きます。幅は 2880 ピクセル程度が目安です。置いた画像がそのまま使われ、`vs build` は画像を作りません。

### 画像を探す順序

画像は、まず `stylesheets/images/` に置いた独自画像から探し、見つからなければ同梱画像（`stylesheets/images/bundled/`）から探します。同じ名前の独自画像（`stylesheets/images/sakura.webp` など）を置けば、設定を変えずに絵柄だけを差し替えられます。その名前のまま同梱画像を使うときは、`image: bundled/sakura` と書きます。

### 扉絵の文字と余白を整える

扉絵と文字の重なり具合は、画像の構図によって変わります。余白や文字の幅が合わないときは、`frontispiece` の次の項目で調整します。例の値は既定値です。

```yaml
theme:
  frontispiece:
    image: sakura
    edge_inset: 5mm  # 扉絵の上下と紙の端の間の余白
    heading_offset: 15mm  # 章番号・章題・リード文のまとまりを下げる量
    heading_chars: 10  # 章題を 1 行に何文字入れるか
    lead_chars: 24  # リード文を 1 行に何文字入れるか
    lead_size:  # リード文の大きさ（空欄なら theme.lead_size に従う）
```

**edge_inset（扉絵の上下と紙の端の間の余白）**

扉絵の高さは、紙の高さからこの余白を上下に除いた長さになり、幅は画像の縦横比で決まります。余白を広げると画像は小さくなり、扉が落ち着いた印象になります。章題との釣り合いを PDF で見ながら調整してください。

**heading_offset（見出しのまとまりを下げる量）**

章番号・章題・リード文のまとまりを、まとめて下へずらします。飾りの位置は絵柄ごとに違うので、文字が飾りに重なるときにこの値で調整します。

**heading_chars（章題の字数）**

章題を 1 行に何文字入れるかを指定します。「原稿の分量と難度の計測」のように 11 文字ある章題を 1 行に収めたいときは、`11` 以上を指定します。字数で指定するので、判型を変えても 1 行の字数は変わりません。文字の大きさは判型に合わせて変わります。

指定した字数が版面に収まらないときは、上限を添えた警告が出ます。

:::{.output}
```text
🟡 theme.frontispiece.heading_chars: 16 は版面幅 162mm に収まりません（最大 12 文字）
        heading_chars: 12 をお試しください
```
:::

**lead_chars（リード文の字数）**

章のリード文（`:::{.chapter-lead}`）に、1 行あたり何文字ぶんの幅を与えるかを指定します。

**lead_size（章扉のリード文の大きさ）**

章扉のリード文を、本文の何倍の大きさで組むかを 1.0〜2.0 で指定します。`1.05` のような細かい値も書け、`1.1em` と書いても同じ意味です。空欄なら `theme.lead_size`（既定 1.2）に従います。EPUB・Kindle でも、扉絵の下に続くリード文はこの大きさで組まれます。

`lead_chars` は 1 行の字数なので、文字を小さくすると 1 行の幅も狭くなります。幅を保ったまま文字を小さくするときは、次の例のように `lead_chars` も増やします。

```yaml
theme:
  frontispiece:
    lead_size: 1.1  # 章扉のリード文を本文の 1.1 倍で組む
    lead_chars: 26  # 1 行の字数を増やして、幅を保つ
```

1.2 倍・24 字を 1.1 倍・26 字にすると、幅はほぼ同じまま、行数が 1 割近く減ります。行の高さも小さくなるので、リード文全体の高さは 15% ほど低くなります。

### リード文が章扉に収まらないとき

リード文が章扉に収まらず、次のページへ送られたときは、`vs build` と `vs preflight` が 🟡 で警告します。章ごとに縮める字数と、すべての章扉に収まる `lead_size` と `lead_chars` の組み合わせが示されます。組み合わせは、文字の大きさごとに 1 行ずつ並びます。どれか 1 行を選んで、その二つの値を書きます。

:::{.output}
```text
🟡 リードが章扉に収まらず、次のページへ送られている章があります（1 章）
        contents/42-frontispiece.md（扉絵と装飾画像）: 2 行が次のページへ。リードを 50 字ほど縮める
        book.yml の theme.frontispiece を次の組み合わせのどれかにすると、すべての章が章扉に収まります:
          lead_size: （空欄） のまま・lead_chars: 24 → 25
          lead_size: （空欄） → 1.15・lead_chars: 24 のまま
```
:::

組み合わせは行数からの見積もりなので、組み直すと 1 行ずれることがあります。まだ収まらなければ、組み直したときに再度警告します。

リード文が扉絵の飾りに重なっていないかは、組んだ PDF の章扉で確かめてください。重なるときは、`lead_size` を下げるか、`heading_offset` を小さくして見出しのまとまりを上へ寄せます。

### 節題の字数を変える

節見出しの装飾画像は版面の幅いっぱいに置かれるので、`ornament` の `heading_chars` は、その幅に何文字並べるかを指定します。章題とは違い、字数を少なくすると節題は大きく、多くすると小さく組まれます。

```yaml
theme:
  ornament:
    image: sakura
    heading_chars: 14  # 節題を 1 行 14 文字で組む（既定値）
```

### 画像が見つからないとき

指定した画像が見つからないときは、`vs build` と `vs preflight` が次のように警告し、既定画像の `sakura` で代わりに組みます。

:::{.output}
```text
🟡 theme.frontispiece の画像 'fuji' が見つかりません。既定画像（sakura）で代用します。
        stylesheets/images/fuji.webp を配置するか、バンドル画像名（sakura・himawari など）またはスペルを確認してください。
```
:::

警告が出たら、画像名の綴りと、`stylesheets/images/` に置いた画像のファイル名を確かめてください。

## simple スタイルの設定

:::{.section-lead}
`theme.style: simple` は、背景画像を使わず、テーマカラーと書体で章扉や節見出しを組むスタイルです。画像の用意に時間をかけず、本文の見え方から先に確かめたいときにも向いています。
:::

```yaml
theme:
  style: simple
  color: teal  # テーマカラー
```

この設定で、章扉と節見出しはテーマカラーのグラデーションと枠線で飾られます。frontispiece や ornament の設定は使われないため、あとで `image` に戻すときのために残しておいて構いません。

リード文の大きさは、`simple` でも `theme.lead_size` で変えられます（本文に対する倍率・既定 1.2）。`simple` のリード文は版面の幅いっぱいに組まれるので、文字を小さくすると 1 行に入る字数が増えます。

## テーマカラーの選択

:::{.section-lead}
テーマカラー（`theme.color`）は、節番号・見出しの記号・太字・コラムの枠など、本全体の差し色になります。`simple` では、章扉と節見出しの印象もこの色で決まります。
:::

### 選べる色

12 色から選べます。次の見本は、それぞれの色で組んだ `simple` の節見出しです。

:::{.text-left}
![yellow](yellow.svg){width=49%} ![orange](orange.svg){width=49%}
![red](red.svg){width=49%} ![magenta](magenta.svg){width=49%}
![purple](purple.svg){width=49%} ![indigo](indigo.svg){width=49%}
![navy](navy.svg){width=49%} ![blue](blue.svg){width=49%}
![cyan](cyan.svg){width=49%} ![teal](teal.svg){width=49%}
![green](green.svg){width=49%} ![lime](lime.svg){width=49%}
:::

一覧にない色は、`color: '#ff0000'` のように HEX 記法で書けます。YAML では `#` から行末までがコメントになるので、HEX は引用符で囲みます。引用符で囲まないと色を書かなかったことになり、既定の green で組まれます。

`yellow` や `cyan` のような明るい色は、太字の文字色としては淡めになります。モノクロで印刷する本では、`navy`・`indigo`・`green` のような濃い色のほうが強調が紙面に残ります。

一覧にない色名（例: `pink`）を指定した場合は、`vs build` と `vs preflight` が次のように警告し、既定色（green）でビルドを続行します。

:::{.output}
```text
🟡 theme.color 'pink' は無効な色名です。既定色（green）でビルドを続行します。
        指定できる色: yellow / orange / red / magenta / purple / indigo / navy / blue / cyan / teal / green / lime、または '#ff0000' のような HEX（#rrggbb / #rrggbbaa）
```
:::

### 色を組み合わせる

テーマカラーのほかに、前書き・後書きの色（`preface_color`）と付録の色（`appendix_color`）も選べます。3 色を同じ系統からとると、本全体の印象がそろいます。

| 印象 | `color` | `preface_color` | `appendix_color` |
| --- | --- | --- | --- |
| 落ち着いた自然な色（本書の設定） | `green` | `teal` | `cyan` |
| 技術書らしい青 | `blue` | `navy` | `cyan` |
| 柔らかく明るい | `yellow` | `orange` | `lime` |

`preface_color` と `appendix_color` は省略でき、省略すると `color` と同じ色になります。`vs new` で作った本は、`color: green` だけを書き、二つを省略した状態から始まります。green は既定の扉絵 `sakura` に合わせた色です。扉絵を替えたときは、絵の色に合わせてテーマカラーも選び直すとよいでしょう。

## 見出し記号のカスタマイズ

:::{.section-lead}
目見出し（h3）と号見出し（h4）の前には、それぞれ記号を置けます。記号は `theme.markers` で選び、色はテーマカラーになります。
:::

```yaml
theme:
  markers:
    h3: ♣  # 目見出し（h3）の前に置く記号
    h4: ♦  # 号見出し（h4）の前に置く記号
```

二つの階層を見分けられる組み合わせを選んでください。次のような組み合わせがあります。

| 組み合わせ | `h3` | `h4` |
| :--- | :---: | :---: |
| トランプ記号（既定） | `♣` | `♦` |
| 花の記号 | `❀` | `✿` |
| 星の記号 | `★` | `☆` |
| 幾何学記号 | `◆` | `◇` |
| 矢印記号 | `▶` | `▷` |

選んだ記号の見え方は、組んだ PDF で確かめてください。
