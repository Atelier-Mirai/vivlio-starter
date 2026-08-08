# ビルド（vs build）

:::{.chapter-lead}
原稿の執筆が一段落したら、`vs build` コマンドで書籍を組版しましょう。閲覧用 PDF、印刷入稿用 PDF、電子書籍（EPUB）、Amazon Kindle 用ファイル（KPF）の四つの形式を、ひとつのコマンドで生成できます。

`vs build` は Vivlio Starter の中核となるコマンドです。原稿の前処理から画像最適化、Markdown→HTML 変換、Vivliostyle による組版、PDF 結合、アウトライン付与まで、書籍制作に必要な一連の工程を自動的に実行します。
:::

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
  targets: pdf                   # 閲覧用 PDF のみ（既定）
  # targets: pdf, epub           # 閲覧用 PDF と EPUB の両方
  # targets: epub                # クリーン EPUB のみ
  # targets: kindle              # Kindle 用 KPF のみ
  # targets: epub, kindle        # クリーン EPUB と Kindle 用 KPF
  # targets: print_pdf           # 印刷入稿用 PDF のみ
  # targets: pdf, print_pdf      # 閲覧用 PDF と印刷入稿用 PDF
```

文字列、カンマ区切り、配列のいずれでも指定できます。

```yaml
targets: pdf                      # 文字列
targets: pdf, print_pdf           # カンマ区切り
targets: [pdf, epub, kindle]      # 配列形式
```

| 形式 | 説明 | 用途 |
|:---|:---|:---|
| `pdf` | 閲覧用 PDF | 画面での確認、配布 |
| `print_pdf` | 印刷入稿用 PDF | 同人印刷所への入稿（トンボ・塗り足し付き） |
| `epub` | クリーン EPUB（電子書籍） | 楽天 Kobo、Apple Books への配信 |
| `kindle` | Kindle 用 KPF | Amazon Kindle（KDP）への配信 |


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

`true` にしておくと、原稿に書かれたカラー絵文字が自動的にきれいな画像（Twemoji の SVG 画像）へ置き換えられ、入稿に適した PDF が書き出されます。**既定で有効**なので、ふだんは意識する必要はありません。

### PDF プレビュー

macOS では、ビルド完了後に自動的にプレビューアプリで PDF を開きます。

```yaml
output:
  pdf_preview:
    close_existing_windows: true            # 既存ウィンドウを閉じる
    window_bounds: "{0, 0, 1280, 960}"      # 表示位置とサイズ
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
    full_bleed: false     # 本文にフチなし要素があるか
```

本文の入稿用 PDF はトンボ・塗り足し付きで、主要な同人印刷所（ねこのしっぽ、日光企画など）に対応しています。隠しノンブルも自動的に書き込まれます。

入稿用 PDF は、既定では閲覧用 PDF と同じレンダリング結果から導出されます。本文が完全に同一のため、閲覧用でチェックした内容がそのまま入稿物になり、ビルド時間も短縮されます。本文に紙端まで届く画像や背景（フチなし要素）がある場合のみ `full_bleed: true` を指定してください。塗り足し込みで個別にレンダリングされます（詳細は「config/book.yml リファレンス」の章を参照）。

### 入稿用の表紙

印刷入稿用の表紙は本文とは別ファイルとして出力されます。Japan Color 2001 Coated による ICC ベースの CMYK 変換を行い、出力インテントを埋め込んだ PDF/X-1a:2001 として書き出します（`@vivliostyle/cli` 同梱の ICC を自動利用）。別のプロファイルを使いたいときだけ、パスを指定してください。

```yaml
output:
  print_pdf:
    icc_profile: /path/to/JapanColor2001Coated.icc
```

出力先とファイル名は `.cache/vs/covers/frontcover_<テーマ名>_<判型>_cmyk.pdf` のように自動で決まります（「カバー画像の生成」の章を参照）。

:::{.note}
**閲覧用と入稿用の同時ビルド**

`targets: pdf, print_pdf` と指定すると、両方を一度にビルドできます。閲覧用 PDF で内容を確認しながら、入稿用 PDF も同時に準備できるので便利です。
:::


## EPUB のビルド（クリーン EPUB）

:::{.section-lead}
`targets: epub` は、楽天 Kobo や Apple Books などの電子書籍ストアに配信するための、高品質な「クリーン EPUB」を生成します。Amazon Kindle 向けには、後述の `targets: kindle` を使います。
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
| `embed: false` | 表紙画像を埋め込まない |

クリーン EPUB（`targets: epub`）では既定で `embed: true` です。Kindle 向けの表紙の扱いは後述の「Kindle のビルド」を参照してください。

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


## Kindle のビルド

:::{.section-lead}
`targets: kindle` は、Amazon Kindle（KDP）に配信するための KPF ファイルを生成します。Kindle の表示エンジンに合わせて調整した中間 EPUB を作り、`kindlepreviewer` で `.kpf` へ自動変換します。
:::

```yaml
output:
  targets: kindle
  kindle:
    embed: false               # 表紙画像を埋め込まない（KDP で別途アップロード）
    layout: reflowable         # reflowable（リフロー型）/ fixed（固定レイアウト型）
```

```bash
vs build
```

ビルドが完了すると、プロジェクトルートに `janken_v0.1.0.kpf` のようなファイルが生成されます。KDP の管理画面では、この `.kpf` をアップロードしてください。

### クリーン EPUB との違い

`epub` と `kindle` は、同じ電子書籍でも生成物が異なります。Kindle の表示エンジン（KFX / Enhanced Typesetting）は EPUB の一部の CSS・画像形式に対応していないため、`kindle` ターゲットでは Kindle 向けの調整を加えた専用の中間 EPUB を経由します。

| 項目 | `epub`（クリーン EPUB） | `kindle`（KPF） |
|:---|:---|:---|
| 配信先 | 楽天 Kobo / Apple Books | Amazon Kindle（KDP） |
| 最終成果物 | `.epub` | `.kpf` |
| 画像形式 | WebP をそのまま使用 | JPEG / PNG へ変換（Kindle は WebP 非対応） |
| 扉絵・節絵 | SVG で高品質に表示 | JPEG 画像化して確実に表示 |
| インライン数式 | SVG で高品質に表示 | 単純な式はテキスト化（フォント変更に追従）／複雑な式は SVG 画像 |
| レイアウト | 標準的な EPUB | Kindle KFX の制約に合わせて調整 |

クリーン EPUB は画質・組版を優先するため WebP や SVG をそのまま活かし、Kindle 版は端末での確実な表示を優先して画像形式やレイアウトを変換します。`targets: epub, kindle` と指定すれば、両方を一度に生成できます。

なお Kindle では、画像はリーダーのフォントサイズ変更に追従できません。そこで `E=mc^2` のような単純なインライン数式は、Kindle 版に限り画像ではなく本文テキストに変換して埋め込み、フォントサイズを変えても本文と一緒に拡大・縮小されるようにしています。平方根や総和・積分などテキストで表しきれない複雑な式は、これまでどおり画像として埋め込まれます（そうした式は `$$ … $$` のディスプレイ数式として独立した行に置くと、Kindle でも安定して表示されます）。

### 表紙について

Kindle 版は既定で `embed: false`（表紙を埋め込まない）です。Kindle では本文に表紙を埋め込むと KDP 側の表紙と二重に表示されてしまうため、表紙は KDP の管理画面から別途アップロードする運用を推奨します。

### kindlepreviewer のインストール

`.kpf` への変換には、Amazon が配布する **Kindle Previewer 3** に含まれる `kindlepreviewer` コマンドが必要です。未インストールの場合、Kindle 用の中間 EPUB までは生成されますが、`.kpf` への変換はスキップされ、その旨が警告として表示されます。

macOS であれば、`vs doctor --fix` で Kindle Previewer 3 の導入（Homebrew cask）と `kindlepreviewer` コマンドのパス通し（アプリ内 CLI を呼ぶラッパー作成）をまとめて自動実行できます。`vs doctor` は導入状況の診断（`✅ kindlepreviewer` / 未導入時は 🟡 案内）も行います。

手動で導入する場合は、[Amazon KDP のサイト](https://kdp.amazon.co.jp/ja_JP/help/topic/G202131170)から Kindle Previewer をダウンロードしてください。インストール後、ターミナルで `which kindlepreviewer` を実行し、コマンドにパスが通っているか確認できます。パスが通っていない場合は、Kindle Previewer のインストール先（macOS では `/Applications/Kindle Previewer 3.app` 配下）にパスを通してください。

:::{.note}
**生成された KPF の確認**

`.kpf` ファイルは Kindle Previewer 3 で開いて、実機に近いプレビューで表示を確認できます。KDP にアップロードする前に、扉絵・コード・表・数式などが意図どおり表示されるか確認することをおすすめします。
:::


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

単章ビルドでは、`output.targets` の指定にかかわらず**閲覧用 PDF のみ**が生成されます（印刷入稿用 PDF・EPUB・Kindle は作られません）。目次や索引などの全体構成ページも生成されません。原稿の体裁をすばやく確認するための用途に絞った仕様です。印刷入稿用 PDF や EPUB・Kindle が必要なときは、章を指定せずに `vs build`（全章ビルド）を実行してください。


## 設定ファイルなしのビルド

:::{.section-lead}
書き捨てのメモや企画書を、プロジェクトを作らずに 1 枚だけ組版したいことがあります。`vs build` に `.md` ファイルを直接指定すると、`book.yml` も `catalog.yml` も使わずに PDF を生成します。
:::

```bash
vs build myawesome.md                      # どこで実行しても OK（プロジェクト外でも動く）
vs build ~/notes/idea.md --theme blue      # テーマカラーを指定
vs build contents/00-preface.md            # 執筆中の章を、その場でプレビュー
```

カレントディレクトリに `myawesome.pdf`（元ファイル名の拡張子違い）が生成され、macOS では自動的に開きます。

`--theme` には `book.yml` の `theme.color` と同じ色名（yellow / orange / red / magenta / purple / indigo / navy / blue / cyan / teal / green / lime）に加えて、`--theme '#e91e63'` のような HEX 記法も指定できます。省略時は yellow です。シェルが `#` をコメントとして解釈しないよう、HEX は引用符で囲んでください。

:::{.note}
このモードは「軽量な確認」に用途を絞っています。

- 出力は**閲覧用 PDF のみ**（印刷入稿用 PDF・EPUB・Kindle は作られません）
- 装飾は**画像なし（simple）固定**、版面は B5 判、原稿は常に**本章**として組まれます（`00-` や `99-` で始まるファイル名でも前書き・後書きにはなりません）
- 画像は入力ファイルと同じ場所からの相対パスで解決します（プロジェクトの章を指定したときは、その章の `images/` も探します）
- `codes/` からのコードインクルード、QueryStream 記法、他章へのクロスリファレンス、索引・用語集は使えません
- `--no-resize` や `--compress` などプロジェクト前提のオプションは無視されます（指定すると 🟡 でお知らせします）

きちんとした本に育てるときは `vs new` でプロジェクトを作成してください。
:::


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
| `--theme <color>` | テーマカラーを指定（`.md` ファイルの直接指定時のみ有効） |
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

### フルビルドの流れ

全章ビルドの処理は、大きく 3 つのまとまりに分かれます。

:::{.diagram}
```
共通の下ごしらえ
  画像の最適化 → 扉絵・表紙素材 → 原稿の前処理
  → 索引語のスキャン → HTML 変換 → 前付・後付 → 目次
      │
      ├── PDF の枝
      │     本文 PDF → バックリンクの重複排除
      │     → 表紙・奥付 → 全 PDF の結合 → しおりの付与
      │     → 圧縮・リネーム → 入稿用 PDF
      │
      └── EPUB の枝
            EPUB の生成 → KPF への変換
      │
最後の片付け
```
:::

PDF と EPUB の枝は互いに独立しているため、両方を出力するときは**並列に走ります**。EPUB 側のログは合流時にまとめて出るので、途中で静かに見えても止まっているわけではありません。

どの処理が動くかは `targets` の指定で決まります。`targets: pdf` だけなら EPUB の枝はまるごと省かれ、`print_pdf` を足せば入稿用 PDF の処理が加わります。**処理に通し番号は振られていません**。実行条件によって並びが変わるため、番号ではなくログに出るラベル（`build overall pdf` など）で追いかけてください。

### タイミング表示

`--log=debug`オプションを付けた場合には、ビルド完了時に各ステップの所要時間が表示されます。

:::{.output}
```
== Build Step Timings ==
  - clean                                  0.00s
  - optimize images                        0.07s
  - prepare theme images                   0.00s
  - prepare cover assets                   0.00s
  - preprocess sections                    4.02s
  - index scan and build                   0.64s
  - convert sections html                  5.98s
  - generate part title pages              2.02s
  - generate front and back matter html    0.97s
  - techbook post-process                  0.49s
  - generate toc html                      0.67s
  - build overall pdf                    125.37s
    (vivliostyle build)                 (124.74s)
  - backlink dedup                       123.60s
    (vivliostyle build)                 (123.07s)
  - build front and back matter            0.59s
  - merge all pdfs                         1.24s
  - apply outline to output pdf           25.22s
  - compress, rename and final clean       0.89s
  = TOTAL (sum of steps)                 291.77s
  = WALL (elapsed)                       291.77s
==========================
```
:::

本文 PDF の組版（`build overall pdf`）とバックリンクの重複排除（`backlink dedup`）が大半を占めます。どちらも Vivliostyle が紙面を組み直す処理なので、章が増えるほど伸びます。上は本書（508 ページ）の実測で、全体で約 5 分でした。

執筆中は `vs preflight` でエラーを確認し、`vs build 21` のように章を絞って体裁を見て、最後の仕上げにフルビルドする——という進め方がお勧めです。

`TOTAL` は各処理の所要時間を足したもの、`WALL` は実際に経過した時間です。PDF と EPUB を並列に走らせたときは `WALL` のほうが短くなります。

## book.yml の出力関連設定

:::{.section-lead}
`config/book.yml` の `output` セクションで、出力に関する各種設定を行います。ここでは、設定項目の全体像をまとめます。
:::

```yaml
output:
  # 出力形式（pdf / print_pdf / epub / kindle）
  targets: pdf

  # ファイル名にバージョンを含めるか
  include_version: true

  # PDF プレビュー設定（macOS のみ）
  pdf_preview:
    close_existing_windows: true
    window_bounds: "{0, 0, 1280, 960}"

  # 閲覧用 PDF
  pdf:
    combined: true                     # 表表紙・裏表紙を結合するか
    compress: false                    # 自動圧縮を有効にするか
    techbook: true                     # 絵文字を Twemoji 画像へ差し替えるか（既定: true）

  # 印刷入稿用 PDF
  print_pdf:
    bleed: 3mm                         # 塗り足し幅
    crop_marks: true                   # トンボを付けるか
    full_bleed: false                  # 本文にフチなし要素があるか

  # クリーン EPUB（楽天 Kobo / Apple Books 向け）
  epub:
    embed: true                        # 表紙画像を EPUB に埋め込むか
    layout: reflowable                 # reflowable（リフロー型）/ fixed（固定レイアウト型）

  # Kindle（Amazon KDP 向け・KPF へ自動変換）
  kindle:
    embed: false                       # 表紙画像を埋め込むか（既定: false）
    layout: reflowable                 # reflowable（リフロー型）/ fixed（固定レイアウト型）
```

:::{.column}
**ヒント**: 執筆中は `targets: pdf` で内容を確認し、入稿前に `targets: pdf, print_pdf` に切り替えて入稿用 PDF を生成する、という使い分けがおすすめです。電子書籍も同時に生成したい場合は `targets: pdf, epub, kindle` としてください（クリーン EPUB と Kindle 用 KPF の両方が出力されます）。
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
verify:
  images: true           # 画像パスの存在チェック（既定: true）
  bare_urls: true        # 裸 URL の検出と警告（既定: true）
  external_links: false  # 外部 URL の HTTP 到達性チェック（既定: false）
  timeout: 10            # HTTP チェックのタイムアウト秒数
  max_concurrency: 5     # HTTP チェックの最大同時接続数
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
- `vs doctor --fix` で依存ツール（Vivliostyle、qpdf など）の状態を確認する

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
- `output.targets` が正しく `epub` や `kindle`（電子書籍系）のみになっていることを確認する
- `targets: epub` や `targets: kindle` と指定していれば、PDF 関連の処理は自動的にスキップされる


## ビルド前の高速チェック（vs preflight）

:::{.section-lead}
`vs build` の前に原稿のエラーだけを素早く確認したい場合は、`vs preflight` コマンドが便利です。PDF を生成せず、数秒でチェックを完了します。
:::

「preflight（プリフライト）」とは飛行前点検のことです。パイロットが離陸前に機体を点検するように、ビルド前に原稿を点検するコマンドです。

### vs build との比較

| | `vs preflight` | `vs build` |
|:---|:---|:---|
| 実行時間 | 数秒 | 数分（本書の全章で約 5 分） |
| PDF 生成 | しない | する |
| エラー検出 | その場で報告 | ビルド後に判明 |
| 用途 | 執筆中の頻繁なチェック | 入稿・配布前の最終ビルド |

`vs build` でも同じ検証は行われますが、エラーに気づくのがビルド完了後になります。`vs preflight` を先に実行しておけば、ビルドを待たずに問題を直せます。

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
- **クリーン EPUB**（`targets: epub`）— 楽天 Kobo / Apple Books への配信に
- **Kindle 用 KPF**（`targets: kindle`）— Amazon Kindle（KDP）への配信に
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
