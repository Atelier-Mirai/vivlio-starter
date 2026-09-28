# カバー画像の生成

:::{.chapter-lead}
一冊の本でも、画面で見る PDF、印刷所へ渡す PDF、電子書籍では、表紙に必要な画像形式が異なります。`vs cover` は、一つのデザインから用途に合った表紙画像（カバー）を生成するコマンドです。同梱の `light` / `dark` テーマを使う場合も、独自の SVG や PNG を用意する場合も、準備から生成・確認までの流れは共通です。
:::

ソース画像は `covers/` に置き、生成された PDF や JPEG は `.cache/vs/covers/` に保存されます。どれが元のデザインで、どれが配布用の生成物かを分けて扱えます。

## カバーテーマの選択

:::{.section-lead}
最初に `book.yml` の `output.cover` で使うデザインを選びます。同梱テンプレートを使うか、名前を付けた独自の SVG または PNG を使うかで指定します。
:::

```yaml
output:
  # 開発者提供のデザインを使う場合
  cover: light   # 明るいテーマ
  # cover: dark  # 暗いテーマ

  # 著者が用意した独自デザインを使う場合
  # cover: floral    # covers/frontcover_floral.png または frontcover_floral.svg を使用
  # cover: mandala   # covers/frontcover_mandala.png または frontcover_mandala.svg を使用
  # cover: master    # covers/frontcover_master.png を使用（従来の方法）
```

### テーマ別のソースファイル探索順

`cover: <テーマ名>` を指定すると、以下の順でソースファイルを探索します。

| 優先順位 | 探索先 | 説明 |
|:---:|:---|:---|
| 1 | `covers/frontcover_<テーマ名>.png` | 著者が用意した PNG |
| 2 | `covers/frontcover_<テーマ名>.svg` | 著者が用意した SVG |
| 3 | `covers/bundled/frontcover.svg` | 開発者提供のテンプレート SVG |

たとえば `cover: dark` なら、次の順に探します。
1. `covers/frontcover_dark.png` があればそれを使用
2. なければ `covers/frontcover_dark.svg` を使用
3. どちらもなければ `covers/bundled/frontcover.svg` に dark パレットを適用して使用

### light / dark テーマ

`light` または `dark` を選ぶと、同梱の `covers/bundled/frontcover.svg` に対応する色が使われます。タイトルや著者名も `book.yml` から入るため、まず本の情報を設定して試し刷りできます。

```yaml
output:
  cover: dark  # 暗いテーマのデザインを使用
```

### 著者独自デザインのsvg画像を用いる

独自の SVG を使う場合は、`covers/` に `frontcover_<テーマ名>.svg` を置き、`book.yml` にテーマ名を書きます。別案を試すときも、ファイルを残したまま設定を切り替えられます。

```bash
covers/
├── frontcover_floral.svg    # 著者が用意した花柄デザイン
└── backcover_floral.svg
```

```yaml
output:
  cover: floral  # frontcover_floral.svg を使用
```

SVG に `{{title}}` や `{{author}}` などを書いておけば、ビルド時に `book.yml` の値が入りますので、書籍名や著者名を変えてもデザインファイルを編集し直さずに済みます。

:::{.note}
**複数デザインの管理**

`floral`、`mandala` など複数のデザインを `covers/` に用意しておき、`book.yml` の `cover:` を切り替えるだけで異なるデザインを試せます。
:::

### 著者独自デザインのpng画像を用いる

デザインツールから PNG を書き出して使う場合は、`covers/frontcover_<テーマ名>.png` に置きます。

```bash
covers/
├── frontcover_master.png
└── backcover_master.png
```

```yaml
output:
  cover: master  # covers/frontcover_master.png, covers/backcover_master.png を使用
```

## カバー画像の生成

:::{.section-lead}
デザインを選んだら、`vs cover` で各用途のカバーを生成します。生成後は、閲覧用と印刷用で色や端の見え方が違わないか、実際のファイルを開いて確認します。
:::

### 基本的な使い方

設定したテーマのカバーをまとめて作るには、引数を付けずに実行します。

```bash
vs cover
```

`vs cover` は `book.yml` のテーマと判型を読み、必要な形式を生成します。終わったら `.cache/vs/covers/` のファイルを開いて確認してください。

### フォーマット別の生成

一つの形式だけを作り直す場合は、引数で対象を指定します。

```bash
# A4サイズのRGB版PDFのみ生成
vs cover a4

# B5サイズのCMYK版PDF/X-1aのみ生成
vs cover b5

# A5サイズのCMYK版PDF/X-1aのみ生成
vs cover a5

# EPUB用JPEGのみ生成
vs cover epub
```

## 設定のカスタマイズ

:::{.section-lead}
判型は `book.yml` のページ設定から読み取られます。まずは書籍の判型と、生成されるカバーのサイズが合っているかを確認してください。
:::

### ページサイズの自動判定

印刷用 PDF の判型は、`book.yml` の `page.use` から決まります。本文の判型を変えたら、カバーも再生成してサイズを確かめてください。

```yaml
page:
  use: b5_standard  # B5サイズとして処理
  # use: a5_standard  # A5サイズとして処理
  # use: a4_standard  # A4サイズとして処理
```

## 出力フォーマットの詳細

:::{.section-lead}
閲覧・印刷・電子書籍では、色空間や画像の大きさが変わります。ここでは生成物ごとの違いと、デザインを確かめるときの注意点をまとめます。
:::

### PDF用（RGB版）

**用途**: PDF閲覧、電子配布

- **サイズ**: `page.use` の判型に合わせる（B5 なら 182 × 257 mm）
- **解像度**: 350 dpi
- **カラーモード**: RGB
- **ファイル形式**: PDF（通常）
- **特徴**: ファイルサイズは大きめだが、画面での閲覧に向く

### 印刷用PDF（CMYK版、PDF/X-1a）

**用途**: 商業印刷、印刷所入稿

- **サイズ**: B5またはA5（`page.use` に応じて自動選択）
- **塗り足し**: 3 mm（商業印刷標準）
- **解像度**: 350 dpi
- **カラーモード**: CMYK（Japan Color 2001 Coated による ICC ベース変換を自動適用）
- **ファイル形式**: PDF/X-1a:2001準拠（出力インテント埋め込み）
- **特徴**: 印刷所への入稿を想定した仕様

印刷用 PDF では、表紙画像が塗り足し領域まで拡大されます。裁断で周辺が落ちることを見込み、タイトルや著者名などは端から十分に離して配置してください。

:::{.note}
**PDF/X-1aとは**

PDF/X-1a は、商業印刷向けの PDF 規格です。色空間やフォントなどに条件が定められており、印刷工程での扱いを揃える助けになります。入稿先に固有の指定がある場合は、その条件も確認してください。
:::

### EPUB用（JPEG）

**用途**: 電子書籍（EPUB）

- **サイズ**: 1,600 × 2,560 px
- **縦横比**: 1:1.6（電子書籍の標準比率）
- **品質**: JPEG 90%
- **ファイル形式**: JPEG
- **特徴**: ファイルサイズを抑え、電子書籍リーダーで表示しやすい

:::{.column}
**EPUBカバーのトリミング処理**

マスター画像は 2,894 × 4,092 px です。高さ2,560 pxに縮小すると、横幅は約1,812 pxになります。これを1,600 px幅にするため、左右それぞれ106 pxずつトリミングします。

EPUB 用にはマスター画像の中央部分が残ります。タイトルや著者名が左右の切り落としにかからないよう、中央寄りへ配置してください。
:::

## カバー画像の削除

:::{.section-lead}
デザインを差し替えて作り直すときは、`vs clean --cover` で生成済みのカバーを削除できます。`covers/` に置いたソース画像は残るので、同じデザインから再生成できます。
:::

```bash
vs clean --cover
```

### 複数のオプションとの組み合わせ

カバー以外のキャッシュや生成物も片付けるときは、オプションを組み合わせます。削除範囲を確認してから実行してください。

```bash
# カバー画像とキャッシュを削除
vs clean --cover --cache

# カバー画像とキャッシュと生成物をすべて削除
vs clean --cover --cache --purge
```

## トラブルシューティング

:::{.section-lead}
生成できないときや、印刷用の色が画面と違って見えるときは、次の項目から原因を確認してください。
:::

### マスターファイルが見つからない

**症状**: コマンド実行時に警告が表示される。

```
🟡 表紙マスターが見つかりません: covers/frontcover_master.png
```

**原因**: マスター画像が指定された場所に存在しない。

**解決方法**:
1. `covers/` ディレクトリが存在するか確認
2. ファイル名が `frontcover_master.png` および `backcover_master.png` になっているか確認
3. `book.yml` の `output.cover` に書いたテーマ名と、置いた画像の名前が合っているか確認

### 必要なツールがインストールされていない

**症状**: カバー画像が生成されない。

**原因**: ImageMagick または Ghostscript がインストールされていない。

**解決方法**:

```bash
# 自動インストール（推奨）
vs doctor --fix

# 手動インストール（macOSの場合）
brew install imagemagick ghostscript

# 確認
magick -version
gs --version
```

:::{.note}
**ツールの診断**

`vs doctor` コマンドで、必要なツールがインストールされているか確認できます。

```bash
vs doctor
```
:::

### CMYK変換で色が変わる

**症状**: 印刷用PDF（CMYK版）の色がRGB版と異なる。

**原因**: RGB と CMYK では表現できる色域（ガマット）が異なり、RGB でしか出せない鮮やかな色（とくに青や緑）は、くすんだ近い色に置き換わる。

**解決方法**:
- 印刷に使う色は、CMYK へ変換した結果を見ながら選ぶ
- Photoshop などで CMYK プレビューを確認し、必要なら色を調整する

## 実用的なワークフロー

:::{.section-lead}
ここまでの設定を、初回の生成、デザインの修正、入稿前の確認という三つの場面に沿って並べます。どの場面でも、生成したファイルを開いて仕上がりを確かめます。
:::

### 初回生成

```bash
# 1. マスター画像を配置
# covers/frontcover_master.png
# covers/backcover_master.png を配置

# 2. カバー画像を生成
vs cover

# 3. 生成されたファイルを確認
ls -lh .cache/vs/covers/
```

### デザインの修正と再生成

```bash
# 1. マスター画像を修正（デザインツールで編集）

# 2. 古いカバー画像を削除
vs clean --cover

# 3. 新しいカバー画像を生成
vs cover

# 4. PDFに統合してビルド
vs build
```

### 印刷所入稿前の最終確認

```bash
# 1. 印刷用PDFのみを再生成
vs cover b5  # または vs cover a5

# 2. 生成されたCMYK版PDFを確認（テーマが master・判型が B5 の場合）
open .cache/vs/covers/frontcover_master_b5_cmyk.pdf
open .cache/vs/covers/backcover_master_b5_cmyk.pdf

# 3. PDF/X-1a準拠であることを確認（Adobe Acrobat推奨）

# 4. 問題なければ印刷所に入稿
```

## まとめ

:::{.section-lead}
カバーの元画像を一つ決めておくと、配布先ごとに必要な形式を作り直せます。最後は形式の名前だけで判断せず、実際のカバーを開いて文字・色・裁断位置を確かめてください。
:::

本章で扱った手順は次のとおりです。

- ソース画像の準備（判型に合わせたサイズ・350 dpi・PNG または SVG）
- `book.yml` の `output.cover` によるテーマの選択
- `vs cover` による一括生成と形式別の生成（RGB 版・CMYK 版・EPUB 用）
- `vs clean --cover` による生成物の削除
- 生成できないときや色が変わるときの確認

一つのソースから作っていても、RGB 版と CMYK 版では色が変わり、EPUB 用では左右が切り取られます。用途ごとに仕上がりを確かめることで、同じデザインを安心して使い分けられます。

:::{.column}
**次のステップ**

カバーができたら、次章の `vs build` で本文 PDF と結合できます。本文と並べたときの印象も、そこで確かめてください。
:::
