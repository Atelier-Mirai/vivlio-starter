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

閲覧用 PDF では、表表紙と裏表紙を本文と結合するかどうかを設定できます。

```yaml
output:
  pdf:
    combined: true                    # true で結合、false で除外
```

表紙の PDF がまだ存在しない場合、ビルド時に `covers/frontcover_master.png` から自動生成されます。

### PDF 圧縮

ファイルサイズを抑えたい場合は、PDF 圧縮を有効にできます。

```yaml
output:
  pdf:
    compress: false                   # 自動圧縮の有効/無効
```

コマンドラインから一時的に圧縮を切り替えることもできます。

```bash
vs build --compress      # 圧縮を有効にしてビルド
vs build --no-compress   # 圧縮を無効にしてビルド
```

### 技術書典向け（Techbook）モード

技術書典などの入稿システムでエラーになりやすい絵文字（Type 3フォントエラー）を回避するための専用モードです。

```yaml
output:
  pdf:
    techbook: true                    # true で自動的に絵文字を画像に置き換える
```

これを `true` に設定しておくと、原稿に書かれたカラー絵文字が自動的にきれいな画像（TwemojiのSVG画像）へと置き換えられ、入稿に最適な高品質のPDFが書き出されます。

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
    embed: true                # 表紙画像を EPUB に埋め込む
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

### ファイルサイズの自動最適化

EPUB は、各電子書籍ストアの配信基準に収まるよう、ビルド時に自動で軽量化されます。著者が設定する項目はありません。

- **フォントを埋め込みません**: 本文（明朝体）・見出し（ゴシック体）・コード（等幅）は、リーダー側の標準フォントで表示されます。`font-family` には `serif` / `sans-serif` / `monospace` の総称ファミリが指定されるため、書体の系統（明朝／ゴシック／等幅）はどの端末でも保たれます。これにより、数十 MB に及ぶフォント実体を同梱せずに済みます。
- **絵文字はそのまま表示されます**: PDF とは異なり、EPUB ではリーダー側のカラー絵文字フォントで表示されるため、画像化（Twemoji 化）は行いません。原稿に書いた絵文字がそのまま使われます。
- **epubcheck 準拠**: 生成された EPUB は、構造検証ツール epubcheck でエラーが出ないよう自動調整されます。楽天 Kobo や Apple Books などストアの審査を通過しやすくなります。

:::{.note}
**フォント埋め込みについて**

現在のバージョンでは、ファイルサイズを優先してフォントを埋め込まない設定が既定です。小説など特定の書体を厳密に保ちたい用途に向けたフォント埋め込みオプションは、将来のバージョンで `config/book.yml` に追加される予定です。
:::

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
| `--[no]-verify` | リンク・画像の基本検証を有効/無効にする（既定: 有効） |
| `--verify-links` | 外部 URL の HTTP 到達性チェックを有効にする |
| `--log <level>` | ログレベルを指定（error / warn / info / debug） |

### 使用例

```bash
# 画像最適化を省略して高速ビルド
vs build --no-resize

# デバッグ用に中間ファイルを残す
vs build --no-clean

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
| Step 5 | Markdown → HTML 変換 |
| Step 5b | 中扉（パートタイトル）ページの生成 |
| Step 5c | Techbook モードの後処理（絵文字の画像化。`techbook: true` 時のみ） |
| Step 6 | 目次 HTML と PDF の生成 |
| Step 7 | 本文 PDF の生成（Vivliostyle による組版） |
| Step 8 | 用語集バックリンクの重複排除 |
| Step 9 | 表紙・奥付 PDF の生成 |
| Step 10 | 全 PDF の結合 |
| Step 11 | PDF アウトライン（しおり）の付与 |
| Step 12 | 圧縮・リネーム |
| Step 13 | 印刷入稿用 PDF の生成（`print_pdf` 時のみ） |
| Step E | EPUB の生成（`epub` 時のみ） |
| Step 14 | 最終クリーンアップ |

### タイミング表示

`--log=debug`オプションを付けた場合には、ビルド完了時に各ステップの所要時間が表示されます。

```
== Build Step Timings ==
  - Step  0 (clean)                               0.00s
  - Step  1 (optimize images)                     0.02s
  - Step  2 (prepare theme images)                0.00s
  - Step  3 (preprocess sections)                 0.24s
  - Step  4 (index scan and build)                0.09s
  - Step  5 (generate sections / part pages)      1.26s
  - Step  6 (generate toc and pdf)                3.40s
    (vivliostyle build)                          (3.08s)
  - Step  7 (build overall pdf)                  10.00s
    (vivliostyle build)                          (9.93s)
  - Step  8 (backlink dedup)                     17.33s
    (vivliostyle build)                          (9.82s)
  - Step  9 (build front pages and tail)          7.05s
    (vivliostyle build)                          (3.01s)
    (vivliostyle build)                          (2.91s)
  - Step 10 (merge all pdfs)                      2.91s
  - Step 11 (apply outline to output pdf)         4.49s
  - Step 12 (compress, rename and final clean)    0.11s
  = TOTAL                                        46.89s
==========================
```

一般的に、フルビルドはとても時間がかかります。`vs preflight`コマンドでのエラー確認や、`vs build 00` のように個別の章を一つ一つビルドして誤りがないか確認しながら執筆し、最後の仕上げとしてフルビルドするのがお勧めです。

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
    combined: true                     # 表表紙・裏表紙を結合するか
    compress: false                    # 自動圧縮を有効にするか
    techbook: true                     # 技術書典向け Techbook モード（既定: false）

  # 印刷入稿用 PDF
  print_pdf:
    bleed: 3mm
    crop_marks: true
    cover:
      front: frontcover_cmyk.pdf
      back: backcover_cmyk.pdf

  # EPUB
  epub:
    embed: true                        # 表紙画像を EPUB に埋め込むか
    layout: reflowable                 # reflowable（リフロー型）/ fixed（固定レイアウト型）
```

:::{.column}
**ヒント**: 執筆中は `targets: pdf` で内容を確認し、入稿前に `targets: pdf, print_pdf` に切り替えて入稿用 PDF を生成する、という使い分けがおすすめです。EPUB も同時に生成したい場合は `targets: pdf, epub` としてください。
:::


## リンク・画像の自動検証

:::{.section-lead}
`vs build` は、ビルド中に原稿内のリンクと画像パスを自動的に検証します。PDF 出力後に壊れたリンクや欠落した画像に気づく手戻りを防ぐための機能です。
:::

検証はビルドを止めません。問題が見つかった場合は警告として報告され、ビルド自体は続行します。

### 検証される内容

**画像パスの存在チェック**

原稿内の画像記法 `![代替テキスト](foo.png)` を検証します。参照先のファイルが存在しない場合、ビルド後に警告が表示されます。

```
⚠️  01-quickstart.md:15 - 画像 'foo.png' が見つかりません
                          画像の場所: images/01-quickstart/foo.webp
```

**裸 URL の検出**

Markdown リンク記法を使わずに本文中に直接書かれた URL（裸 URL）を検出します。

```markdown
<!-- 裸 URL（警告対象） -->
詳しくは https://example.com/page を参照してください。

<!-- リンク記法（問題なし） -->
詳しくは [こちら](https://example.com/page) を参照してください。
```

裸 URL が検出された場合、`[テキスト](URL)` 記法の使用を推奨する警告が表示されます。

### 検証サマリー

全ファイルの処理が完了すると、検証結果のサマリーが表示されます。

問題がない場合:

```
✅ リンク・画像の検証が完了しました（問題なし）
```

問題がある場合:

```
🔍 リンク・画像検証の結果:
        画像: 2 件の課題（存在しない画像: 2）
        リンク: 1 件の問題（裸 URL: 1）
        外部URL到達性チェック: スキップ（--verify-links で有効化）
```

### 外部 URL の到達性チェック

`--verify-links` オプションを付けると、外部 URL に実際に HTTP リクエストを送信して到達性を確認します。ネットワーク依存のため、デフォルトでは無効です。

```bash
vs build --verify-links
```

到達できない URL が見つかった場合、サマリーに詳細が表示されます。

```
🔍 リンク・画像検証の結果:
   リンク: 1 件の問題（リンク切れ: 1）
   外部URL: 15 件チェック → 14 OK, 1 NG
     ❌ https://example.com/deleted-page → 404 Not Found
        参照元: 12-markdown-tutorial.md:88
```

| ステータス | 判定 |
|:---|:---|
| 2xx | OK |
| 3xx | OK（リダイレクト先は追跡しない） |
| 4xx | 警告（リンク切れの可能性） |
| 5xx | 警告（サーバーエラー） |
| タイムアウト | 警告（到達不能） |

### 検証を無効にする

検証を完全にスキップしてビルドを高速化したい場合は `--no-verify` を使います。

```bash
vs build --no-verify
```

### book.yml での設定

プロジェクト固有の設定は `config/book.yml` で細かく制御できます。

```yaml
build:
  verify:
    images: true          # 画像パスの存在チェック（既定: true）
    bare_urls: true       # 裸 URL の検出と警告（既定: true）
    external_links: false  # 外部 URL の HTTP 到達性チェック（既定: false）
    timeout: 10           # HTTP チェックのタイムアウト秒数
    max_concurrency: 5    # HTTP チェックの最大同時接続数
```

CLI オプションは `book.yml` の設定より優先されます。たとえば `book.yml` で `external_links: true` にしていても、`--no-verify` を付ければ全チェックがスキップされます。

| 状況 | 結果 |
|:---|:---|
| `book.yml: external_links: true` + CLI オプションなし | HTTP チェック実行 |
| `book.yml: external_links: true` + `--no-verify` | 全チェックスキップ |
| `book.yml: external_links: false` + `--verify-links` | HTTP チェック実行 |
| `book.yml: images: false` + CLI オプションなし | 画像チェックのみスキップ |

:::{.note}
**コードブロック内は検証対象外**

コードブロック（`` ``` `` 〜 `` ``` ``）やインラインコード（`` ` `` 〜 `` ` ``）内の画像記法・URL は検証されません。サンプルコードとして URL を掲載している場合でも、誤検知の心配はありません。
:::


## 特殊記号や絵文字の自動処理とフォントエラー対策

:::{.section-lead}
Vivlio Starterでは、入力された原稿内の特殊な記号や絵文字、波ダッシュなどを自動的にお手入れします。これにより、印刷所でのフォントエラーを防ぎ、美しい誌面を保証します。
:::

### フォントエラー（Type 3フォント）の自動対策
商業印刷所や同人誌印刷所の入稿チェックにおいて、「**Type 3フォント**が含まれているため入稿できません」と警告・返却されてしまうトラブルがよくあります。これは、お使いの絵文字や特殊な記号が、印刷に適さない形式の簡易的なフォント（Type 3）としてPDFに埋め込まれてしまうことが原因です。

Vivlio Starterでは、著者が意識することなくこの問題を回避できるよう、以下の対策を自動で行っています。

- **特殊なリスト記号の画像化**:
  章の中で箇条書きのマークとして使われるクローバー（`♣`）やダイヤ（`♦`）などの特殊記号は、PDFを書き出す際に自動的に画像へと差し替えられます。
- **インライン絵文字の画像化（Techbookモード）**:
  `config/book.yml` の設定で `techbook: true`（技術書典向けモード）を有効にしておくことで、文章中に書かれた一般的な絵文字を、印刷に適した高品質な画像（TwemojiのSVG画像）へと自動で変換します。画像化されることで、文字化けや表示崩れの心配もなく、すっきりと綺麗に表示されます。
  ※絵文字の画像素材に関するクレジット表記は、奥付に自動的に挿入されます。

著者が特別な設定や画像の準備を行う必要はありません。いつも通りテキストを入力するだけで、自動的に印刷に適した安全なPDFが生成されます。

### 波ダッシュ（〜）の表記統一
パソコンの環境（MacやWindowsなど）や入力方法の違いによって、波ダッシュ（`〜`）は内部的に異なる文字コードで保存されてしまうことがあります。これが原因で、特定の環境で文字化けしたり、一部の文字だけデザインが変わって見えたりすることがあります。

Vivlio Starterでは、表紙や本文、奥付にいたるまで、すべてのページの波ダッシュを自動的に「`〜`」の標準的な文字コードへと統一します。これにより、どの環境で開いても文字化けのない美しい表示が保証されます。


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
- 中間生成物が古い場合があるため `vs clean` を実行してからビルドし直す（タイトルページ・奥付・目次が再生成されます）
- それでも直らない場合は `vs clean --all` でキャッシュも含めて削除してからビルドする

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


## ビルド前の高速チェック（vs preflight）

:::{.section-lead}
`vs build` の前に原稿のエラーだけを素早く確認したい場合は、`vs preflight` コマンドが便利です。PDF を生成せず、数秒でチェックを完了します。
:::

「preflight（プリフライト）」とは飛行前点検のことです。パイロットが離陸前に機体を点検するように、ビルド前に原稿を点検するコマンドです。

### vs build との比較

| | `vs preflight` | `vs build` |
|:---|:---|:---|
| 実行時間 | 約6秒 | 約600秒 |
| PDF 生成 | しない | する |
| エラー検出 | ⚠️ ❌ 即時報告 | ビルド後に判明 |
| 用途 | 執筆中の頻繁なチェック | 入稿・配布前の最終ビルド |

`vs build` でも同じ検証は行われますが、エラーに気づくのがビルド完了後になります。`vs preflight` を先に実行しておくことで、ビルド前に問題を修正できるので、効率的に執筆することが出来ます。

### 基本的な使い方

```bash
vs preflight         # 全章をチェック
vs preflight 11      # 11章だけチェック
vs preflight 21-24   # 21〜24章をチェック
vs preflight install # スラッグ "install" を含む章をチェック
```

章の指定方法は `vs build` と同じです。

### 実行結果の見方

`🔴` は品質エラー（著者の意図が成果物に反映されない）、`🟡` は警告（確認を促したい）を表します。検出できる問題の種別は以下の通りです。

| 種別 | 記号 |
|:---|:---:|
| 画像ファイル不在 | 🔴 |
| コードインクルードファイル不在 | 🔴 |
| QueryStream 雛形ファイル不在 | 🔴 |
| ラベルID重複 | 🔴 |
| 裸URL | 🟡 |
| 孤立ラベル | 🟡 |

具体的には、次のように出力されます。

````
vs preflight
🔴 13-new.md:157 - ソースコード 'sample.rb' が見つかりません
        コードの場所: codes/sample.rb
🔴 11-workflow.md:20 - 画像 'workflow.svg' が見つかりません（代替画像を使用します）
        画像の場所: images/11-workflow/workflow.svg
🔴 22-extentions.md:427 - 雛形ファイル '_book.full.md' が見つかりません（記法: = books | :full）
        雛形の場所: templates/_book.full.md
        ヒント: templates/_book.md は存在します。スタイル名を確認してください。
🔴 25-cross-reference.md:361 - ラベルID '画像(左寄せ) @img-left' は重複しています
        重複箇所: 25-cross-reference.md: 361, 381
                  26-querystream.md: 25, 30
🟡 94-sample.md:461 - 裸 URL を検出しました
        URL: https://onlinelibrary.wiley.com/journal/15213889
🟡 25-cross-reference.md:329 - 孤立ラベル 'Prime2 @prime2' は未参照です
🔍 リンク・画像検証の結果:
        画像: 15 件の課題（存在しない画像: 15）
        ソースコード: 6 件の課題（存在しないファイル: 6）
        リンク: 3 件の問題（裸 URL: 3）
        外部URL到達性チェック: スキップ（--verify-links で有効化）
❌ Preflight 完了: 課題あり — 詳細は上記を確認してください
````

課題がない場合には、次のように出力されます。

````
vs preflight
✅ Preflight 完了: 良好な状態です
````

### オプション

| オプション | 説明 |
|:---|:---|
| `--no-resize` | 画像最適化をスキップ（さらに高速化） |
| `--log <level>` | ログレベルを指定（error / warn / info / debug） |
| `-h` / `--help` | ヘルプを表示 |

### 終了コード

`vs preflight` はシェルスクリプトや Makefile からの呼び出しを考慮して、終了コードを返します。

| 終了コード | 意味 |
|:---|:---|
| `0` | 問題なし（警告のみの場合も含む） |
| `1` | ❌ エラーが1件以上検出された |

:::{.tip}
**執筆中の活用例**

章を書き終えるたびに `vs preflight <章番号>` を実行する習慣をつけると、画像の置き忘れやコードファイルのパスミスにすぐ気づけます。`vs build` によるビルド完了を待たずに済むので、執筆のリズムが保ちやすくなります。
:::


## PDFの便利な操作（画像切り出し・印刷トラブル対策）

:::{.section-lead}
本が完成したあと、SNSなどで見本ページを公開したいときや、どうしても印刷所のシステムでフォントエラーが出てしまうときの対策として、PDFを操作する便利な追加コマンドが用意されています。
:::

### 本のページを画像として保存する（vs pdf:pages）
「本の表紙や、一部のページを画像（JPEG形式）にしてSNS（X/Twitterなど）で公開したい」「イベント用の見本ページを作りたい」というときに便利なコマンドです。

```bash
vs pdf:pages
```

引数を付けずに実行すると、すでに作成されているPDFからすべてのページを画像として切り出し、新しく作成されたフォルダ（例: `janken_images/`）の中に保存します。

#### 特定のページだけを画像にする
「表紙と、3ページ目、そして5〜8ページ目だけを画像にしたい」という場合は、`--pages` オプションを使ってページを指定します。

```bash
# 1ページ、3ページ、5〜8ページのみを画像にする
vs pdf:pages --pages="1,3,5-8"
```

#### 画像の画質や保存先を調整する
画像の解像度（きれいさ）や保存フォルダを自由に変更することもできます。

| オプション | 既定値 | 説明 | 使用例 |
|:---|:---:|:---|:---|
| `--dpi` | `350` | 画像の解像度を指定します。数値を大きくするとより鮮明になります。 | `--dpi=600` |
| `--quality` | `95` | 画像の保存品質（1〜100）を指定します。 | `--quality=90` |
| `--output` | `(自動)` | 画像を保存するフォルダの名前を指定します。 | `--output=./samples` |

```bash
# 解像度を600dpiにして、./samples フォルダに保存する
vs pdf:pages --dpi=600 --output=./samples
```

---

### 印刷エラーを確実に回避する「ラスタライズ」（vs pdf:rasterize）
一部の印刷所では、PDF内のフォントの処理方法が原因で、システムエラーとしてデータの受け付けを拒否されてしまうことがあります。
そのような場合の「最終手段」として、**PDFのすべてのページを画像化（ラスタライズ）して結合し直したPDF**を作成するコマンドが用意されています。

```bash
vs pdf:rasterize
```

このコマンドを実行すると、元のPDFの各ページを極めて高画質な絵として処理し、それらを束ね直した `<元のファイル名>_rasterized.pdf` を作成します。

#### ラスタライズPDFの特徴
- **フォントエラーが100%発生しなくなります**: すべてのテキストが画像化されているため、印刷機や印刷所のシステムが文字を読み込む必要がなくなり、フォントに起因する入稿エラーを確実に回避できます。
- **見た目が完全に固定されます**: 文字のズレや記号の化けなどが物理的に発生しなくなります。

:::{.note}
**ラスタライズ時の注意点**
- **ファイルサイズが大きくなります**: ページを画像にするため、完成するPDFのファイルサイズは通常のものより数十倍大きくなることがあります。
- **テキストの選択や検索ができなくなります**: 文字情報が画像になっているため、PDFリーダーで文字をコピーしたり検索したりすることはできなくなります（印刷の仕上がりには影響ありません）。
:::

#### 主なオプション
- `--clean`
  ラスタライズを行う際、一時的に各ページをJPEG画像として書き出します。この一時ファイルを処理完了後に自動で消去したい場合は、`--clean` を付けて実行します。

```bash
# 途中で作成された一時的な画像ファイルを自動で削除する
vs pdf:rasterize --clean
```

---

### 必要な事前準備
これらの画像切り出し・ラスタライズコマンドを使用するには、お使いのパソコンに `pdftoppm` というツールがインストールされている必要があります。

もしコマンド実行時にエラーが表示された場合は、ターミナルで `vs doctor` を実行してみてください。必要なツールが正しく準備されているかを自動で診断してくれます。


## まとめ

:::{.section-lead}
`vs build` は、原稿から書籍を仕上げるための統合ビルドコマンドです。
:::

本章で紹介した内容を振り返ります。

- **閲覧用 PDF**（`targets: pdf`）— 内容確認と配布に
- **印刷入稿用 PDF**（`targets: print_pdf`）— 同人印刷所への入稿に
- **EPUB**（`targets: epub`）— 電子書籍ストアへの配信に
- **単章ビルド**（`vs build 1`）— 執筆中のすばやい確認に
- **リンク・画像検証**（`--verify-links` / `--no-verify`）— リンク切れ・欠落画像の早期発見に
- **ビルド前チェック**（`vs preflight`）— 約6秒で原稿エラーを早期発見に
- **特殊記号・絵文字の対策** — Type 3フォントエラーや波ダッシュの化けを自動で防止
- **ページの画像化**（`vs pdf:pages`）— SNSでの見本公開用などに特定のページを画像として書き出し
- **PDFのラスタライズ**（`vs pdf:rasterize`）— フォントエラーで入稿できないときの最終手段として画像PDFを生成

原稿の執筆に集中し、組版や出力ファイルの最適化はビルドコマンドにお任せください。

:::{.column}
**次のステップ**

ビルドした PDF の品質をさらに高めるには、`vs metrics` コマンドで文章の品質指標を確認できます。また、`vs lint` コマンドで表記ゆれや文法の問題を検出できます。
:::
