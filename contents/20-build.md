# ビルド（vs build）

:::{.chapter-lead}
原稿の執筆が一段落したら、`vs build` コマンドで書籍を組版しましょう。閲覧用 PDF、印刷入稿用 PDF、電子書籍（EPUB）の三つの形式を、ひとつのコマンドで生成できます。
:::

`vs build` は Vivlio Starter の中核となるコマンドです。原稿の前処理から画像最適化、Markdown→HTML 変換、Vivliostyle による組版、PDF 結合、アウトライン付与まで、書籍制作に必要な一連の工程を自動的に実行します。

## はじめてのビルド

:::{.section-lead}
まずは最も基本的な使い方から見ていきましょう。
:::

```bash
vs build
```

引数なしで実行すると、`config/catalog.yml` に定義された全章を対象に**フルビルド**を行います。出力される形式は `config/book.yml` の `output.targets` で決まります。

### 出力形式の選択

`config/book.yml` の `output.targets` を編集して、出力したい形式を指定します。

```yaml
output:
  targets: pdf              # 閲覧用 PDF のみ（既定）
  # targets: pdf, epub      # 閲覧用 PDF と EPUB の両方
  # targets: epub            # EPUB のみ
  # targets: print_pdf       # 印刷入稿用 PDF のみ
  # targets: pdf, print_pdf  # 閲覧用 PDF と印刷入稿用 PDF
```

文字列、カンマ区切り、配列のいずれでも指定できます。

```yaml
targets: pdf                 # 文字列
targets: pdf, print_pdf      # カンマ区切り
targets: [pdf, epub]         # 配列形式
```

| 形式 | 説明 | 用途 |
|:---|:---|:---|
| `pdf` | 閲覧用 PDF | 画面での確認、配布 |
| `print_pdf` | 印刷入稿用 PDF | 同人印刷所への入稿（トンボ・塗り足し付き） |
| `epub` | EPUB（電子書籍） | 楽天 Kobo、Apple Books、Kindle への配信 |


## 閲覧用 PDF のビルド

:::{.section-lead}
`targets: pdf` は、著者が内容を確認したり、読者に配布するための PDF を生成します。
:::

```yaml
output:
  targets: pdf
```

```bash
vs build
```

ビルドが完了すると、プロジェクトルートに `janken_v0.1.0.pdf` のようなファイルが生成されます。ファイル名は `project.name` と `project.version` から自動的に決定されます。

### ファイル名の規則

```yaml
project:
  name: "janken"
  version: "0.1.0"

output:
  filename:
    include_version: true   # true:  janken_v0.1.0.pdf
                             # false: janken.pdf
```

### 表紙の結合

閲覧用 PDF では、表表紙と裏表紙を本文と結合できます。

```yaml
output:
  pdf:
    cover:
      enabled: true                    # true で結合、false で除外
      front: "frontcover_rgb.pdf"      # 表表紙（RGB）
      back: "backcover_rgb.pdf"        # 裏表紙（RGB）
```

表紙の PDF がまだ存在しない場合、ビルド時に `covers/frontcover_master.png` から自動生成されます。

### PDF 圧縮

ファイルサイズを抑えたい場合は、PDF 圧縮を有効にできます。

```yaml
output:
  pdf:
    compress:
      enabled: false           # 自動圧縮の有効/無効
      suffix: '_compressed'    # 圧縮版のサフィックス
```

コマンドラインから一時的に圧縮を切り替えることもできます。

```bash
vs build --compress      # 圧縮を有効にしてビルド
vs build --no-compress   # 圧縮を無効にしてビルド
```

### PDF プレビュー

macOS では、ビルド完了後に自動的にプレビューアプリで PDF を開きます。

```yaml
output:
  pdf_preview:
    close_existing_windows: true               # 既存ウィンドウを閉じてから開く
    window_bounds: "{4096, 0, 5120, 2160}"    # 表示位置とサイズ
```


## 印刷入稿用 PDF のビルド

:::{.section-lead}
`targets: print_pdf` は、同人印刷所に入稿するための PDF を生成します。トンボ（トリムマーク）と塗り足し（ブリード）が自動的に付与されます。
:::

```yaml
output:
  targets: print_pdf
  print_pdf:
    bleed: 3mm           # 塗り足し幅
    crop_marks: true      # トンボを付ける
```

出力は PDF/X-4 準拠で、主要な同人印刷所（ねこのしっぽ、日光企画など）に対応しています。隠しノンブルも自動的に書き込まれます。

### 入稿用の表紙

印刷入稿用の表紙は本文とは別ファイルとして出力されます（CMYK カラープロファイル対応）。

```yaml
output:
  print_pdf:
    cover:
      front: frontcover_cmyk.pdf    # 表表紙（CMYK）
      back: backcover_cmyk.pdf      # 裏表紙（CMYK）
```

:::{.note}
**閲覧用と入稿用の同時ビルド**

`targets: pdf, print_pdf` と指定すると、両方を一度にビルドできます。閲覧用 PDF で内容を確認しながら、入稿用 PDF も同時に準備できるので便利です。
:::


## EPUB のビルド

:::{.section-lead}
`targets: epub` は、楽天 Kobo や Apple Books、Amazon Kindle などの電子書籍ストアに配信するための EPUB ファイルを生成します。
:::

```yaml
output:
  targets: epub
  epub:
    cover:
      embed: true              # 表紙画像を EPUB に埋め込む
      image: cover.jpg         # カバー画像（covers/ ディレクトリ配下）
    layout: reflowable         # reflowable（リフロー型）/ fixed（固定レイアウト型）
```

```bash
vs build
```

### カバー画像

EPUB のカバー画像は `covers/cover.jpg` を使用します。ファイルが存在しない場合は `covers/frontcover_master.png` から自動生成されます。推奨サイズは 1600×2560px です。

| 設定 | 説明 |
|:---|:---|
| `embed: true` | 表紙画像を EPUB に埋め込む（楽天 Kobo / Apple Books 向け） |
| `embed: false` | 表紙画像を埋め込まない（Kindle 向け。KDP で別途アップロード） |

### レイアウト方式

| 方式 | 説明 |
|:---|:---|
| `reflowable` | リフロー型。端末の画面サイズに応じてテキストが自動的に折り返される。一般的な技術書向け |
| `fixed` | 固定レイアウト型。PDF と同じ見た目を維持する。図版が多い書籍向け |

### メタデータ

EPUB のメタデータ（タイトル、著者名、言語、ISBN など）は `book` セクションから自動的に取得されます。別途設定する必要はありません。

```yaml
book:
  main_title: "初めてのウェブアプリ開発"
  subtitle: "じゃんけんゲームを創ろう"
  author: "アトリヱ未來"
  language: "ja"
  isbn: ''
```

### EPUB の確認

生成された EPUB ファイルは、お好みの EPUB リーダーで確認できます。macOS の「ブック」アプリ、Calibre、Kindle Previewer などが利用できます。


## 単章ビルド

:::{.section-lead}
特定の章だけを素早くビルドしたい場合は、章番号やファイル名を引数に指定します。執筆中の確認に便利です。
:::

```bash
vs build 1            # 01 章をビルド
vs build 8            # 08 章をビルド
vs build 1 8          # 01 章と 08 章をビルド
vs build 1-8          # 01 章から 08 章までをビルド
vs build 01-life      # ファイル名で指定
```

章番号は自動的にゼロ埋めされるので、`1` と入力しても `01` として解釈されます。

単章ビルドでは PDF のみが生成され、目次や索引などの全体構成ページは生成されません。原稿の体裁をすばやく確認したいときに活用してください。


## コマンドラインオプション

:::{.section-lead}
`vs build` には、ビルドの挙動を細かく制御するためのオプションが用意されています。
:::

```bash
vs build --help     # ヘルプを表示
```

### 主要オプション一覧

| オプション | 説明 |
|:---|:---|
| `--no-resize` | 画像最適化を無効にする（ビルド高速化） |
| `--high` / `--medium` / `--low` | 画像品質プリセットを指定 |
| `--compress` / `--no-compress` | PDF 圧縮の有効/無効 |
| `--no-clean` | 中間生成物を残す（デバッグ用） |
| `--dry-run` | 実行せずにビルド予定のみを表示 |
| `--force` | タイトルページ・奥付を強制再生成 |
| `--no-cache` | キャッシュを無効化（`--force` と同義） |
| `--log <level>` | ログレベルを指定（error / warn / info / debug） |

### 使用例

```bash
# 画像最適化を省略して高速ビルド
vs build --no-resize

# デバッグ用に中間ファイルを残す
vs build --no-clean

# ビルド予定だけ確認する
vs build --dry-run

# タイトルページと奥付を強制再生成
vs build --force

# 詳細なログを表示
vs build --log debug
```


## ビルドパイプライン

:::{.section-lead}
`vs build` の内部では、複数のステップが順番に実行されます。各ステップの所要時間はビルド完了時に表示されます。
:::

### フルビルドのステップ

| Step | 処理内容 |
|:---|:---|
| Step 0 | 中間生成物のクリーンアップ |
| Step 1 | 画像の最適化（リサイズ・圧縮） |
| Step 2 | テーマ画像の準備 |
| Step 3 | Markdown の前処理（frontmatter 付加、画像パス修正） |
| Step 4 | 索引語のスキャンと索引ページ生成 |
| Step 5 | Markdown → HTML 変換、中扉ページ生成 |
| Step 6 | 目次 HTML と PDF の生成 |
| Step 7 | 本文 PDF の生成（Vivliostyle による組版） |
| Step 8 | 用語集バックリンクの重複排除 |
| Step 9 | 表紙・奥付 PDF の生成 |
| Step 10 | 全 PDF の結合 |
| Step 11 | PDF アウトライン（しおり）の付与 |
| Step 12 | リネーム・クリーンアップ |
| Step 13 | 印刷入稿用 PDF の生成（`print_pdf` 時のみ） |
| Step E | EPUB の生成（`epub` 時のみ） |

### タイミング表示

ビルド完了時に各ステップの所要時間が表示されます。

```
== Build Step Timings ==
  - Step  0 (clean)                             0.00s
  - Step  1 (optimize images)                   0.03s
  - Step  3 (preprocess sections)               0.31s
  - Step  5 (generate sections / part pages)    1.52s
  - Step  7 (build overall pdf)                 8.20s
    (vivliostyle build)                        (8.13s)
  = TOTAL                                      11.56s
==========================
```

この表示を参考に、ボトルネックとなっているステップを確認できます。たとえば、画像の最適化に時間がかかっている場合は `--no-resize` で省略し、内容の確認に集中することもできるでしょう。


## book.yml の出力関連設定

:::{.section-lead}
`config/book.yml` の `output` セクションで、出力に関する各種設定を行います。ここでは、設定項目の全体像をまとめます。
:::

```yaml
output:
  # 出力形式（pdf / print_pdf / epub）
  targets: pdf

  # ファイル名にバージョンを含めるか
  filename:
    include_version: true

  # PDF プレビュー設定（macOS のみ）
  pdf_preview:
    close_existing_windows: true
    window_bounds: "{0, 0, 1024, 768}"

  # 閲覧用 PDF
  pdf:
    cover:
      enabled: true
      front: "frontcover_rgb.pdf"
      back: "backcover_rgb.pdf"
    compress:
      enabled: false
      suffix: '_compressed'

  # 印刷入稿用 PDF
  print_pdf:
    bleed: 3mm
    crop_marks: true
    cover:
      front: frontcover_cmyk.pdf
      back: backcover_cmyk.pdf

  # EPUB
  epub:
    cover:
      embed: true
      image: cover.jpg
    layout: reflowable
```

:::{.column}
**ヒント**: 執筆中は `targets: pdf` で内容を確認し、入稿前に `targets: pdf, print_pdf` に切り替えて入稿用 PDF を生成する、という使い分けがおすすめです。EPUB も同時に生成したい場合は `targets: pdf, epub` としてください。
:::


## トラブルシューティング

:::{.section-lead}
ビルド時によくある問題とその解決方法をまとめます。
:::

### ビルドが途中で止まる

**症状**: 特定のステップで長時間止まる

**解決方法**:
- `--log info` を付けて実行し、どの処理で止まっているか確認する
- 画像が大量にある場合は `--no-resize` で画像最適化をスキップする
- `vs doctor --fix` で依存ツール（Vivliostyle、Playwright など）の状態を確認する

### PDF のページ番号がずれる

**症状**: 目次のページ番号と実際のページが一致しない

**解決方法**:
- `vs build --force` でタイトルページ・奥付を再生成する
- キャッシュが古い場合があるため `vs clean` を実行してからビルドし直す

### EPUB で索引リンクが機能しない

**症状**: EPUB の索引ページからリンクが飛ばない

**解決方法**:
- `index_glossary.enabled: true` が設定されていることを確認する
- `vs build` を再実行する（索引リンクはビルド時に自動生成される）

### 「PDFファイルが見つかりません」と表示される

**症状**: EPUB のみビルドしているのに PDF のエラーが出る

**解決方法**:
- `output.targets` が正しく `epub` のみになっていることを確認する
- `targets: epub` と指定していれば、PDF 関連の処理は自動的にスキップされる


## まとめ

:::{.section-lead}
`vs build` は、原稿から書籍を仕上げるための統合ビルドコマンドです。
:::

本章で紹介した内容を振り返ります。

- **閲覧用 PDF**（`targets: pdf`）— 内容確認と配布に
- **印刷入稿用 PDF**（`targets: print_pdf`）— 同人印刷所への入稿に
- **EPUB**（`targets: epub`）— 電子書籍ストアへの配信に
- **単章ビルド**（`vs build 1`）— 執筆中のすばやい確認に
- **dry-run**（`vs build --dry-run`）— ビルド予定の事前確認に

原稿の執筆に集中し、組版はビルドコマンドにお任せください。

:::{.column}
**次のステップ**

ビルドした PDF の品質をさらに高めるには、`vs metrics` コマンドで文章の品質指標を確認できます。また、`vs lint` コマンドで表記ゆれや文法の問題を検出できます。
:::
