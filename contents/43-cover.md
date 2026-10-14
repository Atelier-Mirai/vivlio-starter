# カバー画像の生成

:::{.chapter-lead}
一冊の本でも、画面で見る PDF、印刷所へ渡す PDF、電子書籍では、表紙に必要な画像形式が異なります。`vs cover` は、一つのデザインから用途に合った表紙画像（カバー）を生成するコマンドです。同梱の `light` / `dark` テーマを使う場合も、独自の SVG や PNG を用意する場合も、準備から生成・確認までの流れは共通です。
:::

表紙の元になる画像は `covers/` に置きます。生成した表紙はビルドのときに本へ組み込まれるので、著者が生成物を探して扱う必要はありません。印刷所へ渡す入稿用の表紙だけは、プロジェクト直下に `vivlio_starter_frontcover_v1.0.0.pdf` のような名前で置かれます（`project.name` と `project.version` から付く名前です）。

## カバーテーマの選択

:::{.section-lead}
最初に `book.yml` の `output.cover` で使うデザインを選びます。同梱テンプレートを使うか、名前を付けた独自の SVG または PNG を使うかで指定します。
:::

```yaml
output:
  # 同梱のデザインを使う場合
  cover: light   # 明るいテーマ
  # cover: dark  # 暗いテーマ

  # 著者が用意した独自デザインを使う場合
  # cover: floral    # covers/frontcover_floral.png または frontcover_floral.svg を使用
  # cover: mandala   # covers/frontcover_mandala.png または frontcover_mandala.svg を使用
  # cover: master    # covers/frontcover_master.png を使用（既定）
```

### テーマ別のソースファイル探索順

`cover: <テーマ名>` を指定すると、以下の順でソースファイルを探索します。

| 優先順位 | 探索先 | 説明 |
|:---:|:---|:---|
| 1 | `covers/frontcover_<テーマ名>.png` | 著者が用意した PNG |
| 2 | `covers/frontcover_<テーマ名>.svg` | 著者が用意した SVG |
| 3 | `covers/bundled/frontcover.svg` | 同梱のテンプレート SVG（`light` / `dark` のみ） |

たとえば `cover: dark` なら、次の順に探します。
1. `covers/frontcover_dark.png` があればそれを使用
2. なければ `covers/frontcover_dark.svg` を使用
3. どちらもなければ `covers/bundled/frontcover.svg` に dark パレットを適用して使用

`floral` のような独自のテーマ名で PNG も SVG も見つからないときは、同梱のテンプレートには切り替えず、ビルドが 🔴 で知らせます。テーマ名やファイル名の書き誤りに気づけるようにするためです。

PNG と SVG では、印刷所へ渡す入稿用の表紙の作り方が異なります。PNG は、塗り足しまで描いた `_bleed` 付きの画像や `cover_bleed` の設定（後述）が使えます。SVG は、仕上がりの大きさで描いた絵に、トンボを付けて書き出します。

### light / dark テーマ

`light` または `dark` を選ぶと、同梱の `covers/bundled/frontcover.svg` に対応する色が使われます。タイトルや著者名も `book.yml` から入るため、まず本の情報を設定して試し刷りできます。

```yaml
output:
  cover: dark  # 暗いテーマのデザインを使用
```

### 著者独自デザインの svg 画像を用いる

独自の SVG を使う場合は、`covers/` に `frontcover_<テーマ名>.svg` を置き、`book.yml` にテーマ名を書きます。別案を試すときも、ファイルを残したまま設定を切り替えられます。

:::{.diagram}
```text
covers/
├── frontcover_floral.svg    # 著者が用意した花柄デザイン
└── backcover_floral.svg
```
:::

```yaml
output:
  cover: floral  # frontcover_floral.svg を使用
```

SVG に `{{title}}` や `{{author}}` などを書いておけば、ビルド時に `book.yml` の値が入りますので、書籍名や著者名を変えてもデザインファイルを編集し直さずに済みます。

:::{.note}
**複数デザインの管理**

`floral`、`mandala` など複数のデザインを `covers/` に用意しておき、`book.yml` の `cover:` を切り替えるだけで異なるデザインを試せます。
:::

### 著者独自デザインの png 画像を用いる

デザインツールから PNG を書き出して使う場合は、`covers/frontcover_<テーマ名>.png` に置きます。

:::{.diagram}
```text
covers/
├── frontcover_master.png
└── backcover_master.png
```
:::

```yaml
output:
  cover: master  # covers/frontcover_master.png, covers/backcover_master.png を使用
```

画像は、仕上がりの判型に合わせた大きさ（350 dpi）で用意します。

| 判型 | 画像の大きさ |
| :--- | :--- |
| A4（210 × 297 mm） | 2,894 × 4,093 px |
| B5（182 × 257 mm） | 2,508 × 3,541 px |
| A5（148 × 210 mm） | 2,039 × 2,894 px |

## カバー画像の生成

:::{.section-lead}
デザインを選んだら、`vs cover` で各用途のカバーを生成します。生成後は、閲覧用と印刷用で色や端の見え方が違わないか、実際のファイルを開いて確認します。
:::

### 基本的な使い方

設定したテーマのカバーは、次のコマンドでまとめて作ります。

```bash
vs cover
```

`vs cover` は `book.yml` のテーマ・判型・`output.targets` を読み、必要な表紙を作ります。`pdf` があれば閲覧用（RGB）、`print_pdf` があれば入稿用（CMYK）、`epub` か `kindle` があれば電子書籍用（JPEG）です。入稿用と電子書籍用の表紙はプロジェクト直下に置かれるので、それを開いて確かめてください。閲覧用は、`vs build` で本に組み込んだ姿で確かめます。

### 表紙だけを作り直す

表紙の判型は `page.use`、作る形式は `output.targets` で決まります。`vs cover` に引数はありません。別の判型や形式で作りたいときは、`book.yml` を書き換えてから実行します。

表紙のデザインを直したときや、入稿用・電子書籍用の表紙だけを渡し直すときは、本文を組み直さずに `vs cover` だけを実行すれば足ります。`vs build` も表紙を作り直すので、本を組むときに `vs cover` を先に実行しておく必要はありません。

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

### PDF 用（RGB 版）

**用途**: PDF閲覧、電子配布

- **サイズ**: `page.use` の判型に合わせる（B5 なら 182 × 257 mm）
- **解像度**: 350 dpi
- **カラーモード**: RGB
- **ファイル形式**: PDF（通常）
- **特徴**: ファイルサイズは大きめだが、画面での閲覧に向く

### 印刷用 PDF（CMYK 版、PDF/X-1a）

**用途**: 商業印刷、印刷所入稿

- **サイズ**: B5 または A5（`page.use` に応じて自動選択）
- **塗り足し**: 3 mm（商業印刷標準）
- **解像度**: 350 dpi
- **カラーモード**: CMYK（Japan Color 2001 Coated による ICC ベース変換を自動適用）
- **ファイル形式**: PDF/X-1a:2001準拠（出力インテント埋め込み）
- **特徴**: 印刷所への入稿を想定した仕様

印刷用 PDF では、表紙画像が塗り足し領域まで拡大されます。裁断で周辺が落ちることを見込み、タイトルや著者名などは端から十分に離して配置してください。

塗り足しまで描いた表紙を用意したときは、`covers/frontcover_master_bleed.png` のように、表紙の画像の名前に `_bleed` を付けて置きます。こちらを拡大せずにそのまま使います。拡大したくないが、塗り足し用の画像もないときは、`config/book.yml` の `output.print_pdf.cover_bleed` を `keep` にします。この場合、塗り足しの帯は白のまま残ります。

:::{.note}
**PDF/X-1a とは**

PDF/X-1a は、商業印刷向けの PDF 規格です。色空間やフォントなどに条件が定められており、印刷工程での扱いを揃える助けになります。入稿先に固有の指定がある場合は、その条件も確認してください。
:::

### 電子書籍用（JPEG）

**用途**: 電子書籍（EPUB・Kindle）

- **サイズ**: 1,600 × 2,560 px（KDP の推奨の寸法）
- **縦横比**: 1:1.6
- **色**: sRGB
- **品質**: JPEG 95%
- **置き場所**: プロジェクト直下（例: `janken_frontcover_v0.1.0.jpg`）

EPUB と Kindle は同じ 1 枚を使います。EPUB には、この表紙が埋め込まれます。Kindle 用の `.kpf` には表紙を入れません。KDP では、本と表紙を別々に上げる決まりだからです。KDP の登録画面で、プロジェクト直下の JPEG を表紙として上げてください（@chapref:ch-build）。

元の画像に Display P3 などの色の情報が付いていても、sRGB に直して書き出します。sRGB の色の情報は OS にあるものを使います。見つからない環境では、元の色の情報のまま書き出します。KDP の指定（RGB）は、そのままでも満たしています。

:::{.note}
**電子書籍用の表紙は左右が切り落とされます**

元の画像を高さ 2,560 px に縮めてから、中央の幅 1,600 px を切り出します。A4 判のマスター画像（2,894 × 4,093 px）なら、縮めた横幅は約 1,810 px なので、左右を約 105 px ずつ切り落とします。同梱の `light`・`dark` の表紙では、左右の細い金の縦線がこの切り落としにかかり、上下の金の帯だけが残ります。

電子書籍用にはマスター画像の中央部分が残ります。タイトルや著者名が左右の切り落としにかからないよう、中央寄りへ配置してください。
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
ImageMagick や Ghostscript などのツールがない・動かないときは、`vs doctor --fix` で導入してください。ここでは、ツールを入れても直らない症状を扱います。
:::

### マスターファイルが見つからない

**症状**: コマンド実行時に警告が表示される。

:::{.output}
```text
🟡 表紙マスターが見つかりません: covers/frontcover_master.png
```
:::

独自のテーマ名で PNG も SVG も見つからないときは、次のように表示されます。

:::{.output}
```text
🔴 カスタム画像 'floral' のPNGファイルもSVGファイルも見つかりません
        covers/frontcover_floral.png または .svg
        covers/backcover_floral.png または .svg
```
:::

**原因**: 表紙の画像が指定された場所に存在しない。

**解決方法**:
1. `covers/` ディレクトリが存在するか確認
2. ファイル名が `frontcover_<テーマ名>` と `backcover_<テーマ名>` に拡張子（`.png` か `.svg`）を付けた名前になっているか確認（`master` なら `frontcover_master.png` と `backcover_master.png`）
3. `book.yml` の `output.cover` に書いたテーマ名と、置いた画像の名前が合っているか確認

### CMYK 変換で色が変わる

**症状**: 印刷用 PDF（CMYK 版）の色が RGB 版と異なる。

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

# 3. 本文と結合してビルドし、表紙を確かめる
vs build
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
# 1. 入稿用の表紙を作り直す（output.targets に print_pdf を入れておく）
vs cover

# 2. プロジェクト直下の入稿用表紙を開いて確かめる
open vivlio_starter_frontcover_v1.0.0.pdf
open vivlio_starter_backcover_v1.0.0.pdf

# 3. PDF/X-1a準拠であることを確認（Adobe Acrobat推奨）

# 4. 問題なければ印刷所に入稿
```
