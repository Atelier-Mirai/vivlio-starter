# 扉絵と装飾画像

:::{.chapter-lead}
章の始まりと節見出しは、読者がいま本のどこにいるかを確かめる目印になります。Vivlio Starter では、章扉の背景画像（frontispiece）と節見出しの装飾画像（ornament）を使う `image`、色と文字を中心に組む `simple` の二つのスタイルを選べます。本章では、それぞれの設定と画像の用意のしかたを見ていきます。
:::

## frontispiece と ornament とは

:::{.section-lead}
frontispiece は章扉に置く縦長の画像、ornament は節見出しに添える横長の画像です。同じ絵柄を使っても、別の画像を組み合わせても構いません。章と節の見え方を揃えたいときに設定します。
:::

### frontispiece（扉絵）

frontispiece は、章タイトルが載る扉ページの背景です。縦長（portrait）の画像を使い、読者が新しい章へ入るときの印象を作ります。

- **推奨アスペクト比**: `page.use` の版面設定に応じて動的に決まります（A 判・B 判はいずれも √2:1 ≒ 1.414）。この比率と異なる画像を指定しても、自動生成（後述）でページ比率に合わせてクロップされます。
- **推奨サイズ**: 幅 2880px 程度
- **用途**: 章扉ページの背景画像

### ornament（装飾画像）

ornament は、節見出し（`## 見出し`）の背景に添える横長（landscape）の画像です。章扉の絵柄と揃えると、ページをめくっても同じ本のデザインが続いていると分かります。

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

### 基本的な設定方法

**最小限の設定**

```yaml
theme:
  style: image  # image スタイルを使用
  frontispiece:
    image: sakura  # 桜の画像を使用
  ornament: sakura  # 桜の装飾を使用
```

**詳細な設定**

```yaml
theme:
  style: image
  color: teal  # テーマカラー
  frontispiece:
    image: sakura  # 桜の画像を使用
    edge_inset: 10mm  # 扉絵を紙の端から引っ込める量
    heading_chars: 8  # 章題を 1 行に何文字入れるか
    lead_chars: 20  # リード文を 1 行に何文字入れるか
  ornament:
    image: sakura  # 桜の装飾を使用
    heading_chars: 14  # 節題を 1 行に何文字入れるか
```

### バンドル画像の使用

花を題材にした画像が 12 種類同梱されています。`stylesheets/images/bundled/` にある画像の名前を設定へ書けば、そのまま章扉や節見出しに使えます。画像をまだ用意していない段階でも、紙面の見え方を試せます。

**利用可能なバンドル画像**

選べる画像は次のとおりです。設定には花の名前をローマ字で書きます。

| 画像名 | 画像名 |
|:---:|:---:|
| ![suisen](suisen.webp) | ![ume](ume.webp) |
| 水仙 `suisen` | 梅 `ume` |
| ![nanohana](nanohana.webp) | ![sakura](sakura.webp) |
| 菜の花 `nanohana` | 桜 `sakura` |
| ![suzuran](suzuran.webp) | ![ajisai](ajisai.webp) |
| 鈴蘭 `suzuran` | 紫陽花 `ajisai` |
| ![asagao](asagao.webp) | ![himawari](himawari.webp) |
| 朝顔 `asagao` | 向日葵 `himawari` |
| ![kikyo](kikyo.webp) | ![kosumosu](kosumosu.webp) |
| 桔梗 `kikyo` | 秋桜 `kosumosu` |
| ![kiku](kiku.webp) | ![tsubaki](tsubaki.webp) |
| 菊 `kiku` | 椿 `tsubaki` |

**バンドル画像の指定方法**

同梱画像を使うには、設定に画像名を書きます。frontispiece と ornament に同じ名前を指定すれば、縦長と横長の画像がそれぞれ選ばれます。

```yaml
theme:
  frontispiece:
    image: sakura  # 桜の画像
  ornament: sakura  # 桜の装飾
```

独自画像に`sakura`がある場合に、同梱画像を選びたいときは、`bundled/` を付けて指定することもできます。

```yaml
theme:
  frontispiece:
    image: bundled/sakura
  ornament: bundled/sakura
```

### 独自画像の使用

本の題材に合わせて画像を用意したら、`stylesheets/images/` に置きます。縦長と横長を別々に作ることも、一枚の元画像から生成することもできます。

**画像の配置場所**

元画像は次の場所に置きます。切り抜き方を自分で決めている場合は、縦長・横長の画像も同じ場所に置けます。

:::{.diagram}
```text
stylesheets/
└── images/
    ├── my_image.webp        # 独自画像
    ├── my_image_portrait.webp   # 縦長の派生画像（オプション）
    └── my_image_landscape.webp  # 横長の派生画像（オプション）
```
:::

**画像の指定方法**

設定には拡張子を除いた画像名を書きます。

```yaml
theme:
  frontispiece:
    image: my_image  # stylesheets/images/my_image.webp
  ornament: my_image  # stylesheets/images/my_image.webp
```

**対応している画像形式**

以下の画像形式に対応しています。

- WebP（`.webp`）- 推奨
- PNG（`.png`）
- JPEG（`.jpg`, `.jpeg`）

<!-- no-lint-start -->
WebP は、画質を保ちながらファイルサイズを抑えやすい形式です。新しく画像を用意する場合の第一候補になります。
<!-- no-lint-end -->

### 画像の自動生成

元画像を一枚指定すると、章扉用の縦長画像と節見出し用の横長画像が必要に応じて生成されます。切り抜く位置まで自分で決めたい場合は、縦長・横長の派生画像を先に用意できます。

**自動生成の仕組み**

たとえば `sakura.webp` を指定すると、次の順に画像が準備されます。

1. **画像の検索**: `stylesheets/images/` と `stylesheets/images/bundled/` から画像を検索
2. **アスペクト比の確認**: 画像のアスペクト比が適切かチェック
3. **派生画像の生成**: 必要に応じて `_portrait` と `_landscape` の画像を生成
4. **キャッシュ**: 生成した画像は次回以降再利用される

**派生画像の命名規則**

生成される画像の名前には、用途を示す接尾語が付きます。

- **縦長の派生画像**: `画像名_portrait.webp`
- **横長の派生画像**: `画像名_landscape.webp`

たとえば、`sakura.webp` から以下の画像が生成されます。

- `sakura_portrait.webp` - frontispiece 用
- `sakura_landscape.webp` - ornament 用

**用意した派生画像を優先する**

切り抜き位置を指定したい場合は、`_portrait` や `_landscape` の画像を先に用意してください。用意した派生画像が使われ、元画像からの自動生成は行われません。

```yaml
theme:
  frontispiece:
    image: sakura  # sakura_portrait.webp が存在すればそれを使用
  ornament: sakura  # sakura_landscape.webp が存在すればそれを使用
```

**派生画像を直接指定する**

設定で派生画像の名前を直接指定する方法もあります。

```yaml
theme:
  frontispiece:
    image: sakura_portrait  # 縦長の派生画像を直接指定
  ornament: sakura_landscape  # 横長の派生画像を直接指定
```

### 画像の検索順序

画像は、まず `stylesheets/images/` に置いた独自画像から探し、見つからなければ同梱画像を探します。同じ名前を付けると独自画像が優先されるため、設定名を変えずに絵柄だけを差し替えられます。

**検索の優先順位**

検索順は次のとおりです。

1. **ユーザー提供画像**: `stylesheets/images/` 内を検索
2. **バンドル画像**: `stylesheets/images/bundled/` 内を検索

**上書きの例**

バンドル画像 `sakura` を独自の画像で上書きしたい場合は、`stylesheets/images/sakura.webp` を配置します。

:::{.diagram}
```text
stylesheets/
└── images/
    ├── sakura.webp  # この画像が優先される
    └── bundled/
        └── sakura.webp  # バンドル画像（使用されない）
```
:::

この場合、`config/book.yml` で `sakura` を指定すると、ユーザー提供の `sakura.webp` が使用されます。

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

指定した画像が見つからない場合は警告が出て、既定画像の `sakura` に切り替えてビルドが続きます。紙面が作れた場合も、意図した絵柄になっているかは警告とあわせて確認してください。

**ビルド時の警告**

`vs build` / `vs preflight` は、存在しない画像名を検出すると次のような警告を表示します（ビルドは中断しません）。

:::{.output}
```text
🟡 theme.frontispiece の画像 'fuji' が見つかりません。既定画像（sakura）で代用します。
        stylesheets/images/fuji.webp を配置するか、バンドル画像名（sakura・himawari など）またはスペルを確認してください。
```
:::

警告が出たら、まず画像名の綴りと `stylesheets/images/` / `stylesheets/images/bundled/` への配置を確かめます。組版前に画像の指定をまとめて調べるなら、`vs preflight` を使えます。

**プレースホルダーの表示（最終手段）**

フォールバック先の `sakura` すら見つからない場合（バンドル画像を削除した場合など）は、指定した画像名（拡張子付き）をグレー背景の中央に記した SVG プレースホルダー画像が生成されます。

:::{.diagram}
```text
┌─────────────────────┐
│                     │
│     fuji.webp       │
│                     │
└─────────────────────┘
```
:::

### 実践例

**例1: バンドル画像を使用する**

同梱画像だけで紙面を確かめる例です。まずこの形でビルドすれば、画像を準備する前に配置を見られます。

```yaml
theme:
  style: image
  color: teal
  frontispiece:
    image: sakura
  ornament: sakura
```

**例2: 独自画像を使用する**

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

**例3: 異なる画像を使用する**

章扉と節見出しに別々の絵柄を使うこともできます。組み合わせた結果は紙面で確かめてください。

```yaml
theme:
  style: image
  color: teal
  frontispiece:
    image: sakura  # 桜の扉絵
  ornament: ume  # 梅の装飾
```

**例4: 派生画像を直接指定する**

切り抜き済みの縦長・横長画像を直接選ぶ例です。

```yaml
theme:
  style: image
  frontispiece:
    image: my_awesome_portrait  # 縦長の派生画像を直接指定
  ornament: my_awesome_landscape  # 横長の派生画像を直接指定
```

### image スタイルのトラブルシューティング

ImageMagick などのツールがない・動かないときは、`vs doctor --fix` で導入してください。ここでは、ツールを入れても直らない症状を扱います。

**設定した画像にならず、桜で組まれる**

指定した画像名が見つからないときは、`vs build` と `vs preflight` が 🟡 で知らせ、既定画像の `sakura` で代わりに組みます（前述の「画像が見つからない場合」）。警告に出た画像名の綴りと、`stylesheets/images/` への置き場所を確かめてください。画像名は拡張子なしで書き、`.webp`・`.png`・`.jpg`・`.jpeg` のどれで置いても見つかります。

**画像が引き伸ばされたり、一部が切れたりする**

元画像を 1 枚指定すれば、縦長（扉絵）と横長（節見出し、2.39:1）の画像が版面の比率に合わせて切り出されます。切り抜く位置が意図と違うときは、`_portrait` / `_landscape` の画像を自分で用意してください（前述の「用意した派生画像を優先する」）。

**同梱画像を指定したのに、自分の画像が使われる**

`stylesheets/images/` に同じ名前の画像があると、そちらが優先されます。同梱画像を使いたいときは、`image: bundled/sakura` のように `bundled/` を付けて指定します。

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

### テーマカラーの選択

`simple` では、テーマカラーが章扉と節見出しの印象を大きく左右します。好きな色を選んだら、文字との見分けやすさも PDF で確かめてください。

### 利用可能な色とジャンル例

![yellow](yellow.svg)
![orange](orange.svg)
![red](red.svg)
![magenta](magenta.svg)
![purple](purple.svg)
![indigo](indigo.svg)
![navy](navy.svg)
![blue](blue.svg)
![cyan](cyan.svg)
![teal](teal.svg)
![green](green.svg)
![lime](lime.svg)

**HEX表記**：`color: #ff0000` のように色コードを直接指定することもできます。

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

A: `vs clean --purge --cache` で PDFなどの生成物やキャッシュを削除して、再びビルドしてください。{.aki}

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
