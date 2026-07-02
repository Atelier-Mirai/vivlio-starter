# 扉絵と装飾画像

:::{.chapter-lead}
Vivlio Starter では、章の扉ページに表示する背景画像（frontispiece）と、節見出しの装飾画像（ornament）を設定できます。画像を使った華やかなデザインと、シンプルで洗練されたデザインの2つのスタイルから選択可能です。
:::

## frontispiece と ornament とは

:::{.section-lead}
frontispiece は章の扉ページに表示される縦長の背景画像、ornament は節見出しに表示される横長の装飾画像です。これらを設定することで、書籍全体に統一感のあるビジュアルデザインを実現できます。
:::

### frontispiece（扉絵）

frontispiece は、各章の扉ページ（章タイトルが表示されるページ）の背景に配置される画像です。縦長（portrait）の画像が使用され、章の雰囲気を演出します。

- **推奨アスペクト比**: `page.use` の版面設定に応じて動的に決まります（既定の A4 系ページでは √2:1 ≒ 1.414）。この比率と異なる画像を指定しても、自動生成（後述）でページ比率に合わせてクロップされます。
- **推奨サイズ**: 幅 2880px 程度
- **用途**: 章扉ページの背景画像

### ornament（装飾画像）

ornament は、節見出し（`## 見出し`）の背景に配置される装飾画像です。横長（landscape）の画像が使用され、見出しを視覚的に強調します。

- **推奨アスペクト比**: 2.39:1（シネマスコープ）
- **推奨サイズ**: 幅 2880px 程度
- **用途**: 節見出しの背景装飾

## テーマスタイルの選択

:::{.section-lead}
Vivlio Starter では、`theme.style` の設定により、画像を使った `image` スタイルと、画像を使わない `simple` スタイルの2つのデザインから選択できます。
:::

### image と simple の比較

| 項目 | image スタイル | simple スタイル |
|:---|:---|:---|
| 章扉背景 | frontispiece 画像 | なし（色とグラデーション） |
| 節見出し装飾 | ornament 画像 | なし（色とボーダー） |
| ビルド時間 | やや時間がかかる | 高速 |
| 設定の複雑さ | やや複雑 | シンプル |
| デザインの印象 | 華やか・個性的 | ミニマル・洗練 |
| 推奨用途 | 絵本、写真集、創作物 | 技術書、学術書、ビジネス書 |

### スタイルの選び方

**image スタイルが向いている場合**
- 視覚的なインパクトを重視したい
- 書籍のテーマに合った画像がある
- 華やかで個性的なデザインにしたい

**simple スタイルが向いている場合**
- コンテンツの可読性を最優先したい
- ミニマルで洗練されたデザインにしたい
- ビルド時間を短縮したい

## image スタイルの設定

:::{.section-lead}
`theme.style: image` を指定することで、章扉と節見出しに画像を使用したデザインが適用されます。バンドル画像を使用するか、独自の画像を配置することで、書籍に華やかさを加えることができます。
:::

### 基本的な設定方法

**最小限の設定**

```yaml
theme:
  style: image  # image スタイルを使用
  frontispiece:
    image: himawari  # ひまわりの画像を使用
  ornament: himawari  # ひまわりの装飾を使用
```

**詳細な設定**

```yaml
theme:
  style: image
  color: blue  # テーマカラー
  frontispiece:
    image: sakura  # 桜の画像を使用
    padding: 10mm  # 扉絵の余白
    heading_width: 120mm  # 章タイトルの幅
    lead_width: 100mm  # リード文の幅
  ornament: sakura  # 桜の装飾を使用
```

### バンドル画像の使用

Vivlio Starter には、すぐに使える花の画像が 12 種類バンドルされています。これらの画像は `stylesheets/images/bundled/` に配置されており、設定ファイルで画像名を指定するだけで使用できます。

**利用可能なバンドル画像**

以下の花の画像が利用可能です。画像名は日本語の花の名前（ローマ字表記）です。

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

バンドル画像を使用する場合は、画像名をそのまま指定します。

```yaml
theme:
  frontispiece:
    image: sakura  # 桜の画像
  ornament: sakura  # 桜の装飾
```

または、`bundled/` プレフィックスを付けて明示的に指定することもできます。

```yaml
theme:
  frontispiece:
    image: bundled/sakura
  ornament: bundled/sakura
```

### 独自画像の使用

バンドル画像ではなく、独自の画像を使用したい場合は、`stylesheets/images/` ディレクトリに画像ファイルを配置します。

**画像の配置場所**

独自の画像は、以下のディレクトリに配置します。

```
stylesheets/
└── images/
    ├── my_image.webp        # 独自画像
    ├── my_image_portrait.webp   # 縦長バリアント（オプション）
    └── my_image_landscape.webp  # 横長バリアント（オプション）
```

**画像の指定方法**

配置した画像を使用する場合は、拡張子を省略して画像名を指定します。

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

<!-- vs-lint-disable -->
**推奨**: WebP 形式は、高画質を保ちながらファイルサイズを小さくできるため、推奨されます。
<!-- vs-lint-enable -->

### 画像の自動生成

Vivlio Starter は、元画像から frontispiece 用の縦長画像と ornament 用の横長画像を自動生成する機能を備えています。

**自動生成の仕組み**

元画像（例: `himawari.webp`）を指定すると、以下の処理が自動的に行われます。

1. **画像の検索**: `stylesheets/images/` と `stylesheets/images/bundled/` から画像を検索
2. **アスペクト比の確認**: 画像のアスペクト比が適切かチェック
3. **バリアントの生成**: 必要に応じて `_portrait` と `_landscape` バリアントを生成
4. **キャッシュ**: 生成した画像は次回以降再利用される

**バリアント画像の命名規則**

自動生成される画像は、以下の命名規則に従います。

- **縦長バリアント**: `画像名_portrait.webp`
- **横長バリアント**: `画像名_landscape.webp`

例えば、`himawari.webp` から以下の画像が生成されます。

- `himawari_portrait.webp` - frontispiece 用
- `himawari_landscape.webp` - ornament 用

**既存のバリアント画像の優先**

`_portrait` や `_landscape` のバリアント画像が既に存在する場合は、自動生成をスキップしてそれらを使用します。

```yaml
theme:
  frontispiece:
    image: himawari  # himawari_portrait.webp が存在すればそれを使用
  ornament: himawari  # himawari_landscape.webp が存在すればそれを使用
```

**明示的なバリアント指定**

バリアント画像を直接指定することもできます。

```yaml
theme:
  frontispiece:
    image: himawari_portrait  # 縦長バリアントを直接指定
  ornament: himawari_landscape  # 横長バリアントを直接指定
```

### 画像の検索順序

画像は、ユーザー提供画像を優先し、見つからない場合はバンドル画像を検索します。この仕組みにより、バンドル画像を独自画像で上書きすることができます。

**検索の優先順位**

画像の検索は、以下の順序で行われます。

1. **ユーザー提供画像**: `stylesheets/images/` 内を検索
2. **バンドル画像**: `stylesheets/images/bundled/` 内を検索

**上書きの例**

バンドル画像 `himawari` を独自の画像で上書きしたい場合は、`stylesheets/images/himawari.webp` を配置します。

```
stylesheets/
└── images/
    ├── himawari.webp  # この画像が優先される
    └── bundled/
        └── himawari.webp  # バンドル画像（使用されない）
```

この場合、`config/book.yml` で `himawari` を指定すると、ユーザー提供の `himawari.webp` が使用されます。

### frontispiece の詳細設定

frontispiece には、余白や見出しの幅などの詳細な設定オプションがあります。

**設定可能な項目**

```yaml
theme:
  frontispiece:
    image: sakura  # 画像名
    padding: 10mm  # 扉絵の余白（既定値: 0mm）
    heading_width: 120mm  # 章タイトルの幅（省略可）
    lead_width: 100mm  # リード文の幅（省略可）
```

**padding（余白）**

扉絵の周囲に余白を設定します。画像の端が切れないようにしたい場合に使用します。

```yaml
frontispiece:
  image: himawari
  padding: 15mm  # 15mm の余白を追加
```

**heading_width（章タイトルの幅）**

章タイトルの最大幅を設定します。長いタイトルを適切に折り返したい場合に使用します。

```yaml
frontispiece:
  image: himawari
  heading_width: 100mm  # タイトルの最大幅を 100mm に制限
```

**lead_width（リード文の幅）**

章のリード文（`:::{.chapter-lead}`）の最大幅を設定します。

```yaml
frontispiece:
  image: himawari
  lead_width: 90mm  # リード文の最大幅を 90mm に制限
```

### 画像が見つからない場合

指定した画像が見つからない場合、警告を表示したうえで、既定画像（`sakura`）に自動でフォールバックしてビルドを続行します。無効な色名が既定色（yellow）にフォールバックするのと同じ考え方です。

**ビルド時の警告**

`vs build` / `vs preflight` は、存在しない画像名を検出すると次のような警告を表示します（ビルドは中断しません）。

```
🟡 theme.frontispiece の画像 'fuji' が見つかりません。既定画像（sakura）で代用します。
        stylesheets/images/fuji.webp を配置するか、バンドル画像名（sakura・himawari など）またはスペルを確認してください。
```

この警告を確認したら、画像名のスペルミスや、`stylesheets/images/` / `stylesheets/images/bundled/` への配置場所を確認してください。ビルド前にまとめて確認したい場合は `vs preflight` が手軽です。

**プレースホルダーの表示（最終手段）**

フォールバック先の `sakura` すら見つからない場合（バンドル画像を削除した場合など）は、指定した画像名（拡張子付き）をグレー背景の中央に記した SVG プレースホルダー画像が生成されます。

```
┌─────────────────────┐
│                     │
│     fuji.webp       │
│                     │
└─────────────────────┘
```

### 実践例

**例1: バンドル画像を使用する**

最もシンプルな設定です。バンドル画像をそのまま使用します。

```yaml
theme:
  style: image
  color: blue
  frontispiece:
    image: sakura
  ornament: sakura
```

**例2: 独自画像を使用する**

独自の画像を使用し、余白と幅を調整します。

```yaml
theme:
  style: image
  color: green
  frontispiece:
    image: my_cover  # stylesheets/images/my_cover.webp
    padding: 12mm
    heading_width: 110mm
    lead_width: 95mm
  ornament: my_decoration  # stylesheets/images/my_decoration.webp
```

**例3: 異なる画像を使用する**

frontispiece と ornament で異なる画像を使用します。

```yaml
theme:
  style: image
  color: purple
  frontispiece:
    image: himawari  # ひまわりの扉絵
  ornament: sakura  # 桜の装飾
```

**例4: バリアントを明示的に指定する**

既に生成済みのバリアント画像を直接指定します。

```yaml
theme:
  style: image
  frontispiece:
    image: cosmos_portrait  # 縦長バリアントを直接指定
  ornament: cosmos_landscape  # 横長バリアントを直接指定
```

### image スタイルのトラブルシューティング

**画像が表示されない**

**症状**: 設定した画像が表示されず、プレースホルダーが表示される

**原因と対処法**:

1. **画像名のスペルミス**: `config/book.yml` の画像名を確認
2. **画像ファイルが存在しない**: `stylesheets/images/` に画像ファイルがあるか確認
3. **拡張子の不一致**: 画像ファイルの拡張子が `.webp`, `.png`, `.jpg`, `.jpeg` のいずれかか確認

**画像のアスペクト比が合わない**

**症状**: 画像が引き伸ばされたり、一部が切れたりする

**対処法**:

- frontispiece: 縦長の画像（4:3 または √2:1）を使用
- ornament: 横長の画像（2.39:1）を使用
- 自動生成機能を利用する（元画像を指定するだけ）

**バンドル画像が使用されない**

**症状**: バンドル画像を指定していても、独自画像が使用される

**原因**: `stylesheets/images/` に同名の画像ファイルが存在する

**対処法**:

- ユーザー提供画像が優先されるため、意図的な上書きでない場合は削除
- または、異なる画像名を使用

**画像生成に失敗する**

**症状**: バリアント画像の自動生成が失敗する

**原因**: ImageMagick がインストールされていない

**対処法**:

```bash
# macOS の場合
brew install imagemagick

# 確認
magick -version
```

## simple スタイルの設定

:::{.section-lead}
`theme.style: simple` を設定することで、章扉や節見出しに背景画像を使わず、色とタイポグラフィを中心とした洗練されたデザインを実現できます。読みやすさを重視し、コンテンツに集中できる環境を提供します。
:::

### 基本的な設定方法

**最小限の設定**

```yaml
theme:
  style: simple  # シンプルスタイルを使用
  color: teal    # テーマカラーを指定
```

この設定だけで、以下が自動的に適用されます：

- 章扉の背景画像が無効化（`--frontispiece-image: none`）
- 節見出しの装飾画像が無効化（`--section-bg-image: none`）
- テーマカラーを使った美しいグラデーションとボーダー
- `simple-header.css` の読み込み

この設定だけで、章扉と節見出しがテーマカラーを基調としたシンプルなデザインになります。frontispiece や ornament の設定は無視されます（設定が残っていても問題ありません）。

### テーマカラーの選択

シンプルスタイルでは、テーマカラーが章扉や節見出しの主要な装飾要素となります。書籍のジャンルやご自身の好みに応じて設定してください。

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

一覧にない色名（例: `pink`）を指定した場合は、`vs build` / `vs preflight` が次のように警告し、既定色（yellow）でビルドを続行します。

```
🟡 theme.color 'pink' は無効な色名です。既定色（yellow）でビルドを続行します。
        指定できる色: yellow / orange / red / magenta / purple / indigo / navy / blue / cyan / teal / green / lime、または '#ff0000' のような HEX（#rrggbb / #rrggbbaa）
```
<!-- 
**ビジネス・技術書向け**
- `navy` - 信頼感のある深い紺色
- `indigo` - 知的な印象の藍色
- `teal` - モダンで洗練された青緑色

**学術・教育書向け**
- `purple` - 学術的で上品な紫色
- `blue` - 清潔感のある青色
- `green` - 安心感のある緑色

**創作・エッセイ向け**
- `coral` - 温かみのあるサンゴ色
- `amber` - 親しみやすい琥珀色
- `plum` - 上品で個性的な紫色 -->




### simple スタイルのトラブルシューティング

**Q: 章扉や節見出しが地味すぎる**

A: より鮮やかなテーマカラー（`magenta` など）を試してください。{.aki}

**Q: 以前の画像が表示される**

A: `vs clean --purge --cache` で PDFなどの生成物やキャッシュを削除して、再びビルドしてください。{.aki}

**Q: テーマカラーが反映されない**

A: `book.yml` の `theme.color` 設定を確認し、有効な色名（yellow / orange / red / magenta / purple / indigo / navy / blue / cyan / teal / green / lime）を指定してください。{.aki}

## 見出し記号のカスタマイズ

:::{.section-lead}
Vivlio Starter では、目見出し（h3）と号見出し（h4）の前に表示される記号をカスタマイズできます。`config/book.yml` の `markers` セクションで記号を設定することで、書籍のテーマに合わせた装飾を追加できます。
:::

### 見出し記号の設定

`config/book.yml` の `markers` セクションで、目見出しと号見出しの記号を設定できます。

```yaml
# 目や号の見出し記号
markers: 
  h3: ♣ # 目見出しの記号。h3見出しの前に表示される。一文字推奨。
  h4: ♦ # 号見出しの記号。h4見出しの前に表示される。一文字推奨。
```

### 設定例

**デフォルト設定（トランプ記号）**

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
