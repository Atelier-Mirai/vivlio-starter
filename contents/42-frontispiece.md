# 扉絵と装飾画像

:::{.chapter-lead}
章の始まりと節見出しは、読者がいま本のどこにいるかを確かめる目印になります。Vivlio Starter では、章扉の背景画像（frontispiece）と節見出しの装飾画像（ornament）を使う `image`、色と文字を中心に組む `simple` の二つのスタイルを選べます。本章では、それぞれの設定と画像の用意のしかたを見ていきます。
:::

## 扉絵と装飾画像とは

:::{.section-lead}
扉絵（frontispiece）は章扉に置く縦長の画像、装飾画像（ornament）は節見出しに添える横長の画像です。同じ絵柄を使っても、別の画像を組み合わせても構いません。章と節に彩りを添えたいときに設定します。
:::

### 扉絵（frontispiece）

扉絵（frontispiece）は、章タイトルが載る扉ページの背景です。縦長（portrait）の画像を使い、読者が新しい章へ入るときの印象を作ります。

- **推奨アスペクト比**: `page.use` の版面設定に応じて動的に決まります（A 判・B 判はいずれも √2:1 ≒ 1.414）。この比率と異なる画像を指定しても、自動生成（後述）でページ比率に合わせてクロップされます。
- **推奨サイズ**: 幅 2880px 程度
- **用途**: 章扉ページの背景画像

EPUB・Kindle では、同じ扉絵の横長版（自動で作ります）に章番号と章題を入れて、章の先頭に置きます。リード文は画像に入れず、そのすぐ下に文字として続きます。読者が選んだ文字の大きさで読めるようにするためです。

### 装飾画像（ornament）

装飾画像（ornament）は、節見出し（`## 見出し`）の背景に添える横長（landscape）の画像です。章扉の絵柄と揃えると、ページをめくっても同じ本のデザインが続いていると分かります。

- **推奨アスペクト比**: 2.39:1（シネマスコープ）
- **推奨サイズ**: 幅 2880px 程度
- **用途**: 節見出しの背景装飾

## テーマスタイルの選択

:::{.section-lead}
最初に `theme.style` を選びます。画像を章扉と節見出しへ使うなら `image`、画像を使わず色と文字で組むなら `simple` です。どちらも同じ原稿で切り替えられるので、仕上がりを見ながら選べます。
:::

### image と simple の比較

| 項目 | image スタイル | simple スタイル |
|:---|:---|:---|
| 章扉 | 扉絵（frontispiece）の上に章題を組む | テーマカラーと書体で組む |
| 節見出し | 装飾画像（ornament）を添える | テーマカラーの線で飾る |
| 用意するもの | 画像（同梱の 12 種類から選べる） | なし |
| 紙面の印象 | 華やか・個性的 | 簡素・端正 |

章ごとの雰囲気を絵で伝えたい本や、読者の目を楽しませたい入門書には `image` が、画像を用意する手間をかけずに本文の見え方を先に固めたい本には `simple` が向いています。設定を一行変えるだけで切り替えられるので、両方で組んで見比べてから決めても構いません。

## image スタイルの設定

:::{.section-lead}
`theme.style: image` にすると、章扉には frontispiece、節見出しには ornament が使われます。まずは同梱画像で仕上がりを確かめ、必要なら本の内容に合った独自画像へ差し替えられます。
:::

### 設定方法

テーマカラーと、扉絵・装飾画像として使いたい画像名を指定してください。必要に応じて文字数などの調整も行なえます。

```yaml
theme:
  style: image
  color: teal  # テーマカラー
  frontispiece:
    image: sakura  # 桜の画像を使用
    edge_inset: 10mm  # （任意）扉絵を紙の端から引っ込める量
    heading_chars: 8  # （任意）章題を 1 行に何文字入れるか
    lead_chars: 20  # （任意）リード文を 1 行に何文字入れるか
  ornament:
    image: sakura  # 桜の装飾を使用
    heading_chars: 14  # （任意）節題を 1 行に何文字入れるか
```

### バンドル画像の使用

花を題材にした画像が 12 種類同梱されています。`stylesheets/images/bundled/` にある画像の名前を設定へ書けば、そのまま章扉や節見出しに使えます。画像をまだ用意していない段階でも、紙面の見え方を試せます。設定には花の名前をローマ字で書きます。

| | | |
|:---:|:---:|:---:|
| ![suisen](suisen.webp)<br>水仙 `suisen` | ![ume](ume.webp)<br>梅 `ume` | ![nanohana](nanohana.webp)<br>菜の花 `nanohana` |
| ![sakura](sakura.webp)<br>桜 `sakura` | ![suzuran](suzuran.webp)<br>鈴蘭 `suzuran` | ![ajisai](ajisai.webp)<br>紫陽花 `ajisai` |
| ![asagao](asagao.webp)<br>朝顔 `asagao` | ![himawari](himawari.webp)<br>向日葵 `himawari` | ![kikyo](kikyo.webp)<br>桔梗 `kikyo` |
| ![kosumosu](kosumosu.webp)<br>秋桜 `kosumosu` | ![kiku](kiku.webp)<br>菊 `kiku` | ![tsubaki](tsubaki.webp)<br>椿 `tsubaki` |

frontispiece と ornament に同じ名前を指定すれば、縦長と横長の画像がそれぞれ選ばれます。

### 独自画像の使用

本の題材に合わせて画像を用意したら、`stylesheets/images/` に置き、設定には拡張子を除いた画像名を書きます。画像は WebP（推奨）・PNG・JPEG を使えます。

```yaml
theme:
  frontispiece:
    image: my_image  # stylesheets/images/my_image.webp
  ornament: my_image  # stylesheets/images/my_image.webp
```

### 画像の自動生成

元画像を一枚指定すると、章扉用の縦長画像（`画像名_portrait.webp`）と節見出し用の横長画像（`画像名_landscape.webp`）が自動で作られます。切り抜く位置を自分で決めたいときは、この名前の画像を `stylesheets/images/` に先に置いてください。置いた画像が使われ、自動生成は行われません。設定に `image: sakura_portrait` のように派生画像の名前を直接書くこともできます。

### 画像の検索順序

画像は、まず `stylesheets/images/` に置いた独自画像から探し、見つからなければ同梱画像を探します。同じ名前の独自画像（`stylesheets/images/sakura.webp` など）を置けば、設定名を変えずに絵柄だけを差し替えられます。同じ名前の独自画像があるときに同梱画像を選ぶには、`image: bundled/sakura` と書きます。

### frontispiece の詳細設定

扉絵と文字の重なり具合は、画像の構図によって変わります。余白や見出し幅が合わないときは、次の項目で少しずつ調整できます。

**設定可能な項目**

```yaml
theme:
  frontispiece:
    image: sakura  # 画像名
    edge_inset: 10mm  # 扉絵を紙の端から引っ込める量（既定値: 5mm）
    heading_offset: 15mm  # 見出しブロックを下げる量（省略可）
    heading_chars: 8  # 章題を 1 行に何文字入れるか（省略可）
    lead_chars: 20  # リード文を 1 行に何文字入れるか（省略可）
    lead_size: 1.1  # リード文の文字の大きさ（省略時は theme.lead_size）
```

**edge_inset（扉絵を紙の端から引っ込める量）**

扉絵をページの端からどれだけ内側へ置くかを指定します。余白を広げると画像は小さくなり、扉が少し落ち着いた印象になります。章題との釣り合いを PDF で見ながら調整してください。

```yaml
frontispiece:
  image: sakura
  edge_inset: 15mm  # 紙の端から 15mm 内側に扉絵を配置
```

基準になるのは上下の端です。左右にできる余白は画像の縦横比に応じて自動で決まるため、上下より広くなることがあります。

**heading_offset（見出しブロックを下げる量）**

章扉に載る「章番号・章題・リード文」のまとまりを、まとめて下へずらします。扉絵の絵柄は画像ごとに構図が違うため、絵の余白と文字の位置が噛み合わないことがあります。そのときにこの値で追い込みます。

```yaml
frontispiece:
  image: sakura
  heading_offset: 20mm  # 見出しのまとまりを 20mm 下げる
```

章番号と章題は同じ見出しの一部なので近く、章題とリード文の間は広く取られています。三つが等間隔に並ばないのは、まとまりが読み取れるようにするためです。

**heading_chars（章題の字数）**

章題を 1 行に何文字入れるかを指定します。「クロスリファレンス」のように 9 文字ある章題を 1 行に収めたいときは `9` 以上を指定します。

```yaml
frontispiece:
  image: sakura
  heading_chars: 10  # 章題を 1 行 10 文字ぶんの幅で組む
```

mm ではなく**文字数**で指定するのは、判型を変えても指定の意味が変わらないようにするためです。文字の大きさは判型に合わせて自動で調整されるので、「10 文字」は A4 でも A5 でも 10 文字になります。

指定した字数が版面に収まらないときは、ビルド時に上限を添えた警告が出ます。

:::{.output}
```text
🟡 theme.frontispiece.heading_chars: 16 は版面幅 108mm に収まりません（最大 11 文字）
        heading_chars: 11 をお試しください
```
:::

**lead_chars（リード文の字数）**

章のリード文（`:::{.chapter-lead}`）に、1 行あたり何文字ぶんの幅を与えるかを指定します。章題だけでなくリード文の折り返しも、扉の印象に関わります。

```yaml
frontispiece:
  image: sakura
  lead_chars: 24  # リード文を 1 行 24 文字ぶんの幅で組む
```

**lead_size（章扉のリード文の大きさ）**

章扉のリード文を、本文の何倍の大きさで組むかを指定します。書かなければ `theme.lead_size`（既定 1.2）に従います。リード文が長くて章扉に収まりにくいときに下げます。

```yaml
frontispiece:
  image: sakura
  lead_chars: 30  # 1 行の字数を増やして、幅を保つ
  lead_size: 1.1  # 章扉のリード文を本文の 1.1 倍で組む
```

`lead_chars` は 1 行の字数なので、文字を小さくすると幅も狭くなり、1 行の字数は変わりません。行の間が詰まるぶん、リード文は低く収まります。幅を保ちたいときは、この例のように `lead_chars` も増やします。1.2 倍・28 字を 1.1 倍・30 字にすると、幅はほぼ同じで、行数は 1 割あまり減ります。

指定できるのは 1.0〜2.0 で、`1.05` のような細かい値も書けます。`1.1em` と書いても同じ意味です。EPUB・Kindle でも、扉絵の下に続くリード文はこの大きさで組まれます。

リード文が章扉に収まらず、次のページへ送られたときは、`vs build` が 🟡 で知らせます。章ごとに縮める字数と、すべての章扉に収まる `lead_size`・`lead_chars` の目安が示されます。

:::{.output}
```text
🟡 リードが章扉に収まらず、次のページへ送られている章があります（1 章）
   contents/33-networks-and-systems.md（第7部　通信・システム編）: 3 行が次のページへ。リードを 80 字ほど縮める
   book.yml で直すなら、次のどれか 1 つ:
     theme.frontispiece.lead_size: （空欄） → 1.05
     theme.frontispiece.lead_chars: 24 → 26
     theme.frontispiece.lead_size: （空欄） → 1.15 と lead_chars: 24 → 26（リードの幅はそのまま）
```
:::

目安は行数からの見積もりなので、組み直すと 1 行ずれることがあります。まだ収まらなければ、組み直したときにまた知らせます。

扉絵の飾りの位置は、絵柄ごとに違います。リード文が飾りに重なっていないかは、組んだ PDF の章扉で確かめてください。重なるときは、`lead_size` を下げるか、`heading_offset` を小さくして見出しのまとまりを上へ寄せます。

**ornament の heading_chars（節題の字数）**

節見出し（`##`）にも字数を指定できます。画像名だけで十分な場合は短縮形を使い、見出しの幅を整えたいときは次の形にします。

```yaml
theme:
  ornament:
    image: sakura
    heading_chars: 14  # 節題を 1 行 14 文字で組む
```

節絵の帯は版面の幅いっぱいで固定されているため、章題とは違って**字の大きさ**が変わります。字数を少なくすると節題は大きく、多くすると小さく組まれます。

### 画像が見つからない場合

指定した画像が見つからないときは、`vs build` と `vs preflight` が次のように知らせ、既定画像の `sakura` で代わりに組みます。

:::{.output}
```text
🟡 theme.frontispiece の画像 'fuji' が見つかりません。既定画像（sakura）で代用します。
        stylesheets/images/fuji.webp を配置するか、バンドル画像名（sakura・himawari など）またはスペルを確認してください。
```
:::

警告が出たら、画像名の綴りと `stylesheets/images/` への置き場所を確かめてください。画像名は拡張子なしで書き、`.webp`・`.png`・`.jpg`・`.jpeg` のどれで置いても見つかります。

### 実践例

**独自画像を使い、余白と字数も整える**

独自画像に替え、扉絵の余白と文字の幅も調整する例です。

```yaml
theme:
  style: image
  color: teal
  frontispiece:
    image: my_cover  # stylesheets/images/my_cover.webp
    edge_inset: 12mm
    heading_chars: 9
    lead_chars: 22
  ornament: my_decoration  # stylesheets/images/my_decoration.webp
```

**章扉と節見出しで別の画像を使う**

章扉と節見出しに別々の絵柄を使うこともできます。組み合わせた結果は紙面で確かめてください。

```yaml
theme:
  style: image
  color: teal
  frontispiece:
    image: sakura  # 桜の扉絵
  ornament: ume  # 梅の装飾
```

### image スタイルのトラブルシューティング

ImageMagick などのツールがない・動かないときは、`vs doctor --fix` で導入してください。ここでは、ツールを入れても直らない症状を扱います。

**画像が引き伸ばされたり、一部が切れたりする**

元画像を 1 枚指定すれば、縦長（扉絵）と横長（節見出し、2.39:1）の画像が版面の比率に合わせて切り出されます。切り抜く位置が意図と違うときは、`_portrait` / `_landscape` の画像を自分で用意してください（前述の「画像の自動生成」）。

## simple スタイルの設定

:::{.section-lead}
`theme.style: simple` は、背景画像を使わず、テーマカラーと書体で章扉や節見出しを組むスタイルです。画像の用意に時間をかけず、本文の見え方から先に確かめたいときにも向いています。
:::

### 基本的な設定方法

**最小限の設定**

```yaml
theme:
  style: simple  # シンプルスタイルを使用
  color: teal    # テーマカラーを指定
```

この設定で、章扉と節見出しはテーマカラーを基調としたグラデーションとボーダーのデザインに変わります。frontispiece や ornament の設定は使われないため、あとで `image` に戻すつもりなら残しておいても構いません。

リード文の大きさは、`simple` でも `theme.lead_size` で変えられます（本文に対する倍率・既定 1.2）。`simple` のリード文は版面の幅いっぱいに組まれるので、文字を小さくすると 1 行に入る字数が増えます。

### テーマカラーの選択

`simple` では、テーマカラーが章扉と節見出しの印象を大きく左右します。好きな色を選んだら、文字との見分けやすさも PDF で確かめてください。

### 利用可能な色とジャンル例

:::{.text-left}
![yellow](yellow.svg){width=49%} ![orange](orange.svg){width=49%}
![red](red.svg){width=49%} ![magenta](magenta.svg){width=49%}
![purple](purple.svg){width=49%} ![indigo](indigo.svg){width=49%}
![navy](navy.svg){width=49%} ![blue](blue.svg){width=49%}
![cyan](cyan.svg){width=49%} ![teal](teal.svg){width=49%}
![green](green.svg){width=49%} ![lime](lime.svg){width=49%}
:::

**HEX 表記**：`color: #ff0000` のように色コードを直接指定することもできます。

### 色を組み合わせる

テーマカラーのほかに、前書き・後書きの色（`preface_color`）と付録の色（`appendix_color`）も選べます（@ch-book-yml の章）。3 色を同じ系統からとると、本全体の印象がそろいます。

| 印象 | `color` | `preface_color` | `appendix_color` |
| --- | --- | --- | --- |
| 落ち着いた自然な色（本書の設定） | `green` | `teal` | `cyan` |
| 技術書らしい青 | `blue` | `navy` | `cyan` |
| 柔らかく明るい | `yellow` | `orange` | `lime` |

`preface_color` と `appendix_color` は省略でき、省略すると `color` と同じ色になります。`vs new` で作った本は、`color: green` だけを書き、二つを省略した状態から始まります。green は既定の扉絵 `sakura` に合わせた色です。扉絵を替えたときは、絵の色に合わせてテーマカラーも選び直すとよいでしょう。

`yellow` や `cyan` のような明るい色は、太字の文字色としては淡めになります。モノクロで印刷する本では、`navy`・`indigo`・`green` のような濃い色のほうが強調が紙面に残ります。

一覧にない色名（例: `pink`）を指定した場合は、`vs build` / `vs preflight` が次のように警告し、既定色（green）でビルドを続行します。

:::{.output}
```text
🟡 theme.color 'pink' は無効な色名です。既定色（green）でビルドを続行します。
        指定できる色: yellow / orange / red / magenta / purple / indigo / navy / blue / cyan / teal / green / lime、または '#ff0000' のような HEX（#rrggbb / #rrggbbaa）
```
:::

### simple スタイルのトラブルシューティング

**Q: 章扉や節見出しが地味すぎる**

A: より鮮やかなテーマカラー（`magenta` など）を試してください。{.aki}

**Q: 以前の画像が表示される**

A: `vs clean --purge --cache` で PDF などの生成物やキャッシュを削除して、再びビルドしてください。{.aki}

**Q: テーマカラーが反映されない**

A: `book.yml` の `theme.color` 設定を確認し、有効な色名（yellow / orange / red / magenta / purple / indigo / navy / blue / cyan / teal / green / lime）を指定してください。{.aki}

## 見出し記号のカスタマイズ

:::{.section-lead}
目見出し（h3）と号見出し（h4）の前には、それぞれ記号を置けます。章扉や節見出しと見た目を揃えたいときは、`config/book.yml` の `theme.markers` で選んでください。
:::

### 見出し記号の設定

目見出しと号見出しの記号は、`config/book.yml` の `theme.markers` に書きます。二つの階層を見分けられる組み合わせを選んでください。

```yaml
theme:
  markers:
    h3: ♣  # 目見出し（h3）の前に置く記号
    h4: ♦  # 号見出し（h4）の前に置く記号
```

以下の設定例では `theme:` の行を省き、`markers:` から先だけを示します。

### 設定例

**既定の設定（トランプ記号）**

```yaml
markers:
  h3: ♣  # クラブ
  h4: ♦  # ダイヤ
```

**花の記号**

```yaml
markers:
  h3: ❀  # 花
  h4: ✿  # 花
```

**星の記号**

```yaml
markers:
  h3: ★  # 黒星
  h4: ☆  # 白星
```

**幾何学記号**

```yaml
markers:
  h3: ◆  # 黒ダイヤ
  h4: ◇  # 白ダイヤ
```

**矢印記号**

```yaml
markers:
  h3: ▶  # 右三角
  h4: ▷  # 右三角（白）
```

### 使用上の注意

- **一文字推奨**: 記号は一文字の使用を推奨します。複数文字を設定すると、レイアウトが崩れる可能性があります。
- **フォント対応**: 使用する記号がフォントに含まれているか確認してください。一部の記号は環境によって表示されない場合があります。
- **視認性**: 本文と区別しやすい記号を選択してください。
