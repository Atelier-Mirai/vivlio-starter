# 扉絵と装飾画像

:::{.chapter-lead}
Vivlio Starter では、章の扉ページに表示する背景画像（frontispiece）と、節見出しの装飾画像（ornament）を設定できます。バンドル画像を使用するか、独自の画像を配置することで、書籍に華やかさと個性を加えることができます。
:::

## frontispiece と ornament とは
<!-- ## frontispiece -->

:::{.section-lead}
frontispiece は章の扉ページに表示される縦長の背景画像、ornament は節見出しに表示される横長の装飾画像です。これらを設定することで、書籍全体に統一感のあるビジュアルデザインを実現できます。
:::

### frontispiece（扉絵）

frontispiece は、各章の扉ページ（章タイトルが表示されるページ）の背景に配置される画像です。縦長（portrait）の画像が使用され、章の雰囲気を演出します。

- **推奨アスペクト比**: 4:3 または √2:1（A4縦）
- **推奨サイズ**: 幅 2880px 程度
- **用途**: 章扉ページの背景画像

### ornament（装飾画像）

ornament は、節見出し（`## 見出し`）の背景に配置される装飾画像です。横長（landscape）の画像が使用され、見出しを視覚的に強調します。

- **推奨アスペクト比**: 2.39:1（シネマスコープ）
- **推奨サイズ**: 幅 2880px 程度
- **用途**: 節見出しの背景装飾

## 基本的な設定方法

:::{.section-lead}
`config/book.yml` の `theme` セクションで frontispiece と ornament を設定します。バンドル画像を使用する場合は、画像名を指定するだけで利用できます。
:::

### 最小限の設定

```yaml
theme:
  style: image  # image テーマを使用
  frontispiece:
    image: himawari  # ひまわりの画像を使用
  ornament: himawari  # ひまわりの装飾を使用
```

### 詳細な設定

```yaml
theme:
  style: image
  frontispiece:
    image: sakura  # 桜の画像を使用
    padding: 10mm  # 扉絵の余白
    heading_width: 120mm  # 章タイトルの幅
    lead_width: 100mm  # リード文の幅
  ornament: sakura  # 桜の装飾を使用
```

## バンドル画像の使用

:::{.section-lead}
Vivlio Starter には、すぐに使える花の画像が 36 種類バンドルされています。これらの画像は `stylesheets/images/bundled/` に配置されており、設定ファイルで画像名を指定するだけで使用できます。
:::

### 利用可能なバンドル画像

以下の花の画像が利用可能です。画像名は日本語の花の名前（ローマ字表記）です。

| 画像名 | 花の名前 | 画像名 | 花の名前 |
|:---|:---|:---|:---|
| `ajisai` | 紫陽花 | `ajisai2` | 紫陽花2 |
| `asagao` | 朝顔 | `asagao2` | 朝顔2 |
| `carnation` | カーネーション | `carnation2` | カーネーション2 |
| `carnation3` | カーネーション3 | `cosmos` | コスモス |
| `cosmos2` | コスモス2 | `hasu` | 蓮 |
| `hasu2` | 蓮2 | `himawari` | ひまわり |
| `himawari2` | ひまわり2 | `himawari3` | ひまわり3 |
| `himawari4` | ひまわり4 | `kasumisou` | かすみ草 |
| `kiku` | 菊 | `kiku2` | 菊2 |
| `kiku3` | 菊3 | `kikyo` | 桔梗 |
| `nanohana` | 菜の花 | `nanohana2` | 菜の花2 |
| `rengesou` | レンゲ草 | `sakura` | 桜 |
| `sakura2` | 桜2 | `sakura3` | 桜3 |
| `suisen` | 水仙 | `suisen2` | 水仙2 |
| `suisen3` | 水仙3 | `tanpopo` | たんぽぽ |
| `tsubaki` | 椿 | `tulip` | チューリップ |
| `tulip2` | チューリップ2 | `wakaba` | 若葉 |
| `wakaba2` | 若葉2 | `yuri` | 百合 |

### バンドル画像の指定方法

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

## 独自画像の使用

:::{.section-lead}
バンドル画像ではなく、独自の画像を使用したい場合は、`stylesheets/images/` ディレクトリに画像ファイルを配置します。
:::

### 画像の配置場所

独自の画像は、以下のディレクトリに配置します。

```
stylesheets/
└── images/
    ├── my_image.webp        # 独自画像
    ├── my_image_portrait.webp   # 縦長バリアント（オプション）
    └── my_image_landscape.webp  # 横長バリアント（オプション）
```

### 画像の指定方法

配置した画像を使用する場合は、拡張子を省略して画像名を指定します。

```yaml
theme:
  frontispiece:
    image: my_image  # stylesheets/images/my_image.webp
  ornament: my_image  # stylesheets/images/my_image.webp
```

### 対応している画像形式

以下の画像形式に対応しています。

- WebP（`.webp`）- 推奨
- PNG（`.png`）
- JPEG（`.jpg`, `.jpeg`）

<!-- textlint-disable -->
**推奨**: WebP 形式は、高画質を保ちながらファイルサイズを小さくできるため、推奨されます。
<!-- textlint-enable -->

## 画像の自動生成

:::{.section-lead}
Vivlio Starter は、元画像から frontispiece 用の縦長画像と ornament 用の横長画像を自動生成する機能を備えています。
:::

### 自動生成の仕組み

元画像（例: `himawari.webp`）を指定すると、以下の処理が自動的に行われます。

1. **画像の検索**: `stylesheets/images/` と `stylesheets/images/bundled/` から画像を検索
2. **アスペクト比の確認**: 画像のアスペクト比が適切かチェック
3. **バリアントの生成**: 必要に応じて `_portrait` と `_landscape` バリアントを生成
4. **キャッシュ**: 生成した画像は次回以降再利用される

### バリアント画像の命名規則

自動生成される画像は、以下の命名規則に従います。

- **縦長バリアント**: `画像名_portrait.webp`
- **横長バリアント**: `画像名_landscape.webp`

例えば、`himawari.webp` から以下の画像が生成されます。

- `himawari_portrait.webp` - frontispiece 用
- `himawari_landscape.webp` - ornament 用

### 既存のバリアント画像の優先

`_portrait` や `_landscape` のバリアント画像が既に存在する場合は、自動生成をスキップしてそれらを使用します。

```yaml
theme:
  frontispiece:
    image: himawari  # himawari_portrait.webp が存在すればそれを使用
  ornament: himawari  # himawari_landscape.webp が存在すればそれを使用
```

### 明示的なバリアント指定

バリアント画像を直接指定することもできます。

```yaml
theme:
  frontispiece:
    image: himawari_portrait  # 縦長バリアントを直接指定
  ornament: himawari_landscape  # 横長バリアントを直接指定
```

## 画像の検索順序

:::{.section-lead}
画像は、ユーザー提供画像を優先し、見つからない場合はバンドル画像を検索します。この仕組みにより、バンドル画像を独自画像で上書きすることができます。
:::

### 検索の優先順位

画像の検索は、以下の順序で行われます。

1. **ユーザー提供画像**: `stylesheets/images/` 内を検索
2. **バンドル画像**: `stylesheets/images/bundled/` 内を検索

### 上書きの例

バンドル画像 `himawari` を独自の画像で上書きしたい場合は、`stylesheets/images/himawari.webp` を配置します。

```
stylesheets/
└── images/
    ├── himawari.webp  # この画像が優先される
    └── bundled/
        └── himawari.webp  # バンドル画像（使用されない）
```

この場合、`config/book.yml` で `himawari` を指定すると、ユーザー提供の `himawari.webp` が使用されます。

## frontispiece の詳細設定

:::{.section-lead}
frontispiece には、余白や見出しの幅などの詳細な設定オプションがあります。
:::

### 設定可能な項目

```yaml
theme:
  frontispiece:
    image: sakura  # 画像名
    padding: 10mm  # 扉絵の余白（既定値: 0mm）
    heading_width: 120mm  # 章タイトルの幅（省略可）
    lead_width: 100mm  # リード文の幅（省略可）
```

### padding（余白）

扉絵の周囲に余白を設定します。画像の端が切れないようにしたい場合に使用します。

```yaml
frontispiece:
  image: himawari
  padding: 15mm  # 15mm の余白を追加
```

### heading_width（章タイトルの幅）

章タイトルの最大幅を設定します。長いタイトルを適切に折り返したい場合に使用します。

```yaml
frontispiece:
  image: himawari
  heading_width: 100mm  # タイトルの最大幅を 100mm に制限
```

### lead_width（リード文の幅）

章のリード文（`:::{.chapter-lead}`）の最大幅を設定します。

```yaml
frontispiece:
  image: himawari
  lead_width: 90mm  # リード文の最大幅を 90mm に制限
```

## 画像が見つからない場合

:::{.section-lead}
指定した画像が見つからない場合、プレースホルダー画像が自動的に生成されます。
:::

### プレースホルダーの表示

画像が見つからない場合、以下の情報を含むプレースホルダー画像が表示されます。

- 指定した画像名
- "No Image" のメッセージ

例えば、`himawa` という存在しない画像を指定した場合、以下のように表示されます。

```
┌─────────────────────┐
│   himawa.webp       │
│   No Image          │
└─────────────────────┘
```

### ビルド時の警告

画像が見つからない場合、ビルド時に警告メッセージが表示されます。

```
⚠️ 画像が見つかりません: images/himawa.webp プレースホルダーを使用します
```

この警告を確認したら、画像名のスペルミスや配置場所を確認してください。

## 実践例

:::{.section-lead}
実際の使用例を通して、frontispiece と ornament の設定方法を理解しましょう。
:::

### 例1: バンドル画像を使用する

最もシンプルな設定です。バンドル画像をそのまま使用します。

```yaml
theme:
  style: image
  color: blue
  frontispiece:
    image: sakura
  ornament: sakura
```

### 例2: 独自画像を使用する

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

### 例3: 異なる画像を使用する

frontispiece と ornament で異なる画像を使用します。

```yaml
theme:
  style: image
  color: purple
  frontispiece:
    image: himawari  # ひまわりの扉絵
  ornament: sakura  # 桜の装飾
```

### 例4: バリアントを明示的に指定する

既に生成済みのバリアント画像を直接指定します。

```yaml
theme:
  style: image
  frontispiece:
    image: cosmos_portrait  # 縦長バリアントを直接指定
  ornament: cosmos_landscape  # 横長バリアントを直接指定
```

## トラブルシューティング

:::{.section-lead}
frontispiece と ornament の設定で問題が発生した場合の対処方法を紹介します。
:::

### 画像が表示されない

**症状**: 設定した画像が表示されず、プレースホルダーが表示される

**原因と対処法**:

1. **画像名のスペルミス**: `config/book.yml` の画像名を確認
2. **画像ファイルが存在しない**: `stylesheets/images/` に画像ファイルがあるか確認
3. **拡張子の不一致**: 画像ファイルの拡張子が `.webp`, `.png`, `.jpg`, `.jpeg` のいずれかか確認

### 画像のアスペクト比が合わない

**症状**: 画像が引き伸ばされたり、一部が切れたりする

**対処法**:

- frontispiece: 縦長の画像（4:3 または √2:1）を使用
- ornament: 横長の画像（2.39:1）を使用
- 自動生成機能を利用する（元画像を指定するだけ）

### バンドル画像が使用されない

**症状**: バンドル画像を指定しているのに、独自画像が使用される

**原因**: `stylesheets/images/` に同名の画像ファイルが存在する

**対処法**:

- ユーザー提供画像が優先されるため、意図的な上書きでない場合は削除
- または、異なる画像名を使用

### 画像生成に失敗する

**症状**: バリアント画像の自動生成が失敗する

**原因**: ImageMagick がインストールされていない

**対処法**:

```bash
# macOS の場合
brew install imagemagick

# 確認
magick -version
```

## まとめ

:::{.section-lead}
frontispiece と ornament を活用することで、書籍に視覚的な魅力を加え、読者の興味を引きつけることができます。
:::

Vivlio Starter の frontispiece と ornament 機能により、以下のメリットが得られます。

- **豊富なバンドル画像**: 36 種類の花の画像をすぐに使用可能
- **簡単な設定**: `config/book.yml` で画像名を指定するだけ
- **自動生成**: 元画像から最適なサイズとアスペクト比の画像を自動生成
- **柔軟なカスタマイズ**: 独自画像の使用や詳細な設定が可能

まずはバンドル画像を試してみて、書籍のテーマに合った画像を見つけてください。慣れてきたら、独自の画像を使用してオリジナリティを加えることもできます。
