# ビルド

:::{.chapter-lead}
一章分の原稿ができた場合も、書籍全体の形を確かめたい場合も、`vs build` で組版結果を見られます。完成時には閲覧用 PDF、印刷入稿用 PDF、EPUB、Kindle 用 KPF まで、必要な形式を選んで生成できます。

本章では、まず一冊を作る手順を示し、その後に出力形式ごとの違いと確認方法を説明します。
:::

## はじめてのビルド

:::{.section-lead}
`config/catalog.yml` に章を登録してあれば、まず次のコマンドで本全体をビルドできます。
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

:::{.tip}
執筆中は `targets: pdf` で内容を確認し、入稿前に `targets: pdf, print_pdf` に切り替えて入稿用 PDF を作る、という使い分けができます。電子書籍も同時に作るなら `targets: pdf, epub, kindle` です。`output` セクションの設定の一覧は @chapref:ch-book-yml にあります。
:::


## 閲覧用 PDF のビルド

:::{.section-lead}
`targets: pdf` は、執筆中の紙面確認にも、完成後の配布にも使える PDF を生成します。まずこの形式で本文とページの流れを確かめると、ほかの形式に進みやすくなります。
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

技術書典などの入稿システムでエラーになりやすい絵文字（Type 3 フォントエラー）を回避するための専用モードです。

```yaml
output:
  pdf:
    techbook: true                    # true で自動的に絵文字を画像に置き換える
```

`true` にしておくと、原稿中のカラー絵文字が Twemoji の SVG 画像に置き換えられ、絵文字に由来する Type 3 フォントを避けられます。**既定で有効**です。入稿前には、印刷所の条件と生成した PDF の表示も確認してください。

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
印刷所へ渡す PDF は `targets: print_pdf` で生成します。トンボ（トリムマーク）と塗り足し（ブリード）が付くため、仕上がりサイズだけでなく、紙端の見え方も確認してください。
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

入稿用 PDF は、既定では閲覧用 PDF と同じレンダリング結果から導出されます。本文が完全に同一のため、閲覧用でチェックした内容がそのまま入稿物になり、ビルド時間も短縮されます。本文に紙端まで届く画像や背景（フチなし要素）がある場合のみ `full_bleed: true` を指定してください。塗り足し込みで個別にレンダリングされます（詳細は @chapref:ch-book-yml を参照）。

### 入稿用の表紙

印刷入稿用の表紙は、本文とは別のファイルとしてプロジェクト直下に `janken_frontcover_v0.1.0.pdf` のような名前で出力されます（@chapref:ch-cover）。Japan Color 2001 Coated の ICC プロファイルで CMYK に変換し、出力インテントを埋め込んだ PDF/X-1a:2001 として書き出します（`@vivliostyle/cli` 同梱の ICC を自動利用）。別のプロファイルを使いたいときだけ、パスを指定してください。

```yaml
output:
  print_pdf:
    icc_profile: /path/to/JapanColor2001Coated.icc
```

:::{.note}
**閲覧用と入稿用の同時ビルド**

`targets: pdf, print_pdf` と指定すると、両方を一度にビルドできます。閲覧用 PDF で内容を確認しながら、入稿用 PDF も同時に準備できるので便利です。
:::


## EPUB のビルド（クリーン EPUB）

:::{.section-lead}
楽天 Kobo や Apple Books 向けの EPUB は、`targets: epub` で生成します。本文が画面幅に合わせて流れる形式なので、PDF とは別に、電子書籍リーダーで見出し・画像・リンクの見え方を確かめます。Kindle 向けには、後述の `targets: kindle` を使います。
:::

```yaml
output:
  targets: epub
  epub:
    embed: true                # 表紙画像を EPUB に埋め込む
    layout: reflowable         # リフロー型（固定レイアウト型は将来対応）
```

```bash
vs build
```

### カバー画像

EPUB の表紙は、ビルドのときに `output.cover` のテーマの表紙画像（既定では `covers/frontcover_master.png`）から 1,600 × 2,560 px の JPEG を作って使います。左右が切り落とされるので、文字は中央寄りに置いてください（@chapref:ch-cover）。

| 設定 | 説明 |
|:---|:---|
| `embed: true` | 表紙画像を EPUB に埋め込む（楽天 Kobo / Apple Books 向け） |
| `embed: false` | 表紙画像を埋め込まない |

クリーン EPUB（`targets: epub`）では既定で `embed: true` です。Kindle 向けの表紙の扱いは後述の「Kindle のビルド」を参照してください。

### レイアウト方式

使えるのはリフロー型（`reflowable`）だけです。端末の画面の幅と文字の大きさに合わせて、本文が折り返されます。固定レイアウト型（`fixed`）は将来の対応で、いま `fixed` を指定すると `reflowable` に直すよう知らせます。

### メタデータ

EPUB のメタデータ（タイトル、著者名、言語、ISBN など）は `book` セクションから自動的に取得されます。別途設定する必要はありません。

```yaml
book:
  main_title: "はじめての技術書づくり"
  subtitle: "Vivlio Starter 実践ガイド"
  author: "アトリヱ未來"
  language: "ja"
  isbn: ''
```

### ファイルサイズの自動最適化

EPUB では、フォントや画像の扱いを調整してファイルサイズを抑えます。この軽量化のために、著者が追加で設定する項目はありません。

- **フォントを埋め込みません**: 本文（明朝体）・見出し（ゴシック体）・コード（等幅）は、リーダー側の標準フォントで表示されます。`font-family` には `serif` / `sans-serif` / `monospace` の総称ファミリが指定されるため、書体の系統（明朝／ゴシック／等幅）はどの端末でも保たれます。これにより、数十 MB に及ぶフォント実体を同梱せずに済みます。
- **絵文字はそのまま表示されます**: PDF とは異なり、EPUB ではリーダー側のカラー絵文字フォントで表示されるため、画像化（Twemoji 化）は行いません。原稿に書いた絵文字がそのまま使われます。
- **画像を版面に見合う大きさまで縮めます**: 紙面に対して解像度が過剰な画像は、実際の表示サイズを測ったうえで必要なぶんまで縮小した派生に差し替えられます。`images/` の画像そのものは書き換えません。本書での実測は **30.5 MB → 18.1 MB（約 4 割減）** です。
- **epubcheck への対応**: 生成時に EPUB の構造を調整し、epubcheck でエラーになりにくい形へ整えます。配信前には生成物を実際に検証し、ストアごとの要件も確認してください。

### EPUB の確認

生成された EPUB は、配信先に近い環境で開いて確認してください。macOS の「ブック」アプリや Calibre などで、文字サイズを変えたときの改行や画像の収まり方も見ておくと安心です。


## Kindle のビルド

:::{.section-lead}
Amazon Kindle（KDP）向けには `targets: kindle` を指定します。Kindle 用に調整した中間 EPUB を作り、`kindlepreviewer` で `.kpf` へ変換します。図や数式の扱いが通常の EPUB と異なるため、完成後は Kindle Previewer で確認してください。
:::

```yaml
output:
  targets: kindle
  kindle:
    embed: false               # 表紙画像を埋め込まない（KDP で別途アップロード）
    layout: reflowable         # リフロー型（固定レイアウト型は将来対応）
```

```bash
vs build
```

ビルドが完了すると、プロジェクトルートに `janken_v0.1.0.kpf` のようなファイルが生成されます。KDP の管理画面では、この `.kpf` をアップロードしてください。

### クリーン EPUB との違い

Kindle の表示エンジン（KFX）は、EPUB の一部の画像形式や CSS に対応していません。そこで `kindle` では、Kindle で確実に表示できる形へ変えた中間 EPUB を作ってから、`.kpf` へ変換します。著者が原稿を書き分ける必要はありません。

| 項目 | `epub`（クリーン EPUB） | `kindle`（KPF） |
|:---|:---|:---|
| 配信先 | 楽天 Kobo / Apple Books | Amazon Kindle（KDP） |
| 最終成果物 | `.epub` | `.kpf` |
| 画像 | WebP・SVG のまま | JPEG / PNG に変換 |
| 扉絵・節絵 | SVG のまま（拡大しても鮮明） | JPEG に変換 |
| インライン数式 | SVG の画像 | 単純な式はテキスト、それ以外は画像 |
| ディスプレイ数式 | SVG の画像 | PNG の画像 |

**インライン数式は、Kindle では文字の大きさに合わせて変わります。** 画像は読者が文字を大きくしても追従しないので、テキストにできる式は Kindle 版でテキストに変えます。``E=mc^2`` は上付き文字のテキストに、``√(GM/R)`` のように整えきれない素の表記は書いたとおりの文字になります。テキストにできない LaTeX の式は画像のまま残るので、Kindle Previewer で大きさを確かめてください。**複雑な式はディスプレイ数式（`$$ … $$`）で書く**と、本文の途中に大きさの変わらない画像を置かずに済みます。

Kindle 用の中間 EPUB には、SVG を 1 枚も入れません。SVG が同梱されていると、Kindle Previewer が高度な組版（Enhanced Typesetting）を使えないと判断し、`.kpf` ではなく古い形式の `.mobi` になるためです。SVG で描いた図は画像に変えて入れるので、細い線や小さな文字が読めるかを Kindle Previewer で確かめてください。

### 表紙について

Kindle 版は既定で `embed: false`（表紙を埋め込まない）です。Kindle では本文に表紙を埋め込むと KDP 側の表紙と二重に表示されてしまうため、表紙は KDP の管理画面から別途アップロードする運用を推奨します。

### kindlepreviewer のインストール

`.kpf` への変換には、Amazon が配布する **Kindle Previewer** に含まれる `kindlepreviewer` コマンドが必要です。未インストールの場合、Kindle 用の中間 EPUB までは生成されますが、`.kpf` への変換はスキップされ、その旨が警告として表示されます。

現在配布されているのは **Kindle Previewer 4** です。3 をお使いでしたら、4 へ更新してください。Amazon公式も、3 はサポートしていません。

macOS であれば、`vs doctor --fix` で Kindle Previewer の導入（Homebrew cask）と `kindlepreviewer` コマンドのパス通し（アプリ内 CLI を呼ぶラッパー作成）をまとめて自動実行できます。`vs doctor` は導入の有無に加えて、版が古くないか、変換に必要な環境が揃っているかも確かめます。

手動で導入する場合は、[Amazon KDP のサイト](https://kdp.amazon.co.jp/ja_JP/help/topic/G202131170)から Kindle Previewer をダウンロードしてください。インストール後、ターミナルで `which kindlepreviewer` を実行し、コマンドにパスが通っているか確認できます。パスが通っていない場合は、Kindle Previewer のインストール先（macOS では `/Applications/Kindle Previewer 4.app` 配下）にパスを通してください。

Kindle Previewer は macOS 版と Windows 版だけが配布されており、Linux（WSL を含む）では `.kpf` への変換を行えません。Linux で執筆する場合は、Kindle 用の中間 EPUB までを生成し、変換は macOS か Windows で行ってください。

:::{.tip}
**Apple Silicon の Mac をお使いの場合**

Kindle Previewer 4 は、見かけのうえでは Apple Silicon に対応していますが、変換を実際に行う部分は Intel 版のままです。そのため Rosetta 2 が入っていないと、`.kpf` への変換だけが次のエラーで失敗します。

```text
bad CPU type in executable
```

新しい Mac には Rosetta が最初から入っていないことがあります。次のコマンドで導入してください。

```bash
sudo softwareupdate --install-rosetta --agree-to-license
```

`vs doctor` も、この状態を見つけたら同じ案内を出します。
:::

:::{.note}
**生成された KPF の確認**

`.kpf` ファイルは Kindle Previewer で開いて、実機に近いプレビューで表示を確認できます。KDP にアップロードする前に、扉絵・コード・表・数式などが意図どおり表示されるか確認することをお勧めします。
:::

## 単章ビルド

:::{.section-lead}
執筆中は、章番号やファイル名を指定すると、その章だけを組版できます。本文を直したあと、見出しや図の収まりをすぐ確かめたいときに使います。
:::

```bash
vs build 11             # 11 章をビルド
vs build 11 13          # 11 章と 13 章をビルド
vs build 11-13          # 11 章から 13 章までをビルド
vs build 11-intro       # ファイル名で指定
```

章の書き方は @ch-chapter-management の章の @pageref:chapter-targets で説明しています。

単章ビルドでは、`output.targets` の指定にかかわらず**閲覧用 PDF のみ**が生成されます（印刷入稿用 PDF・EPUB・Kindle は作られません）。目次や索引などの全体構成ページも生成されません。原稿の体裁をすばやく確認するための用途に絞った仕様です。印刷入稿用 PDF や EPUB・Kindle が必要なときは、章を指定せずに `vs build`（全章ビルド）を実行してください。


## 設定ファイルなしのビルド

:::{.section-lead}
配布資料などを、プロジェクトを作らずに 1 本だけ組版したいことがあります。`vs build` に `.md` ファイルを直接指定すると、`book.yml` も `catalog.yml` も使わずに PDF を生成します。
:::

```bash
vs build myawesome.md                      # どこで実行しても OK（プロジェクト外でも動く）
vs build ~/notes/idea.md --theme blue      # ディレクトリやテーマカラーを指定
vs build contents/00-preface.md            # 執筆中の章を、その場でプレビュー
```

カレントディレクトリに `myawesome.pdf`（元ファイル名の拡張子違い）が生成され、macOS では自動的に開きます。

`--theme` には `book.yml` の `theme.color` と同じ色名（yellow / orange / red / magenta / purple / indigo / navy / blue / cyan / teal / green / lime）に加えて、`--theme '#e91e63'` のような HEX 記法も指定できます。省略時は blue です（本の既定の green は扉絵に合わせた色なので、扉絵を使わない配布資料向けに別の色にしています）。シェルが `#` をコメントとして解釈しないよう、HEX は引用符で囲んでください。

:::{.note}
このモードは「軽量な確認」に用途を絞っています。

- 出力は**閲覧用 PDF のみ**（印刷入稿用 PDF・EPUB・Kindle は作られません）
- 装飾は**画像なし（simple）固定**、版面は B5 判、原稿は常に**本章**として組まれます（`00-` や `99-` で始まるファイル名でも前書き・後書きにはなりません）
- 節（`##`）ごとの改ページはせず、続けて組みます（数ページの配布資料に余白が出すぎないように）
- プロジェクトの章を `.md` で指定しても、`book.yml` の設定（テーマカラーなど）は使いません。本の設定で組むなら、拡張子を付けずに `vs build 00-preface` のように指定します
- 章が一つだけのときは章番号を付けません（章扉に「第1章」を出さず、節は「1」「2」、図表は「図 1」と振ります）
- 章見出し（`#`）を複数書くと、`#` ごとに章として組みます（「第1章」「第2章」と番号が付き、節番号も章ごとに振り直されます）
- 画像は入力ファイルと同じ場所からの相対パスで解決します（プロジェクトの章を指定したときは、その章の `images/` も探します）
- `codes/` からのコードインクルード、QueryStream 記法、他章へのクロスリファレンス、索引・用語集は使えません
- `--compress` などプロジェクト前提のオプションは無視されます（指定すると 🟡 でお知らせします）

きちんとした本に育てるときは `vs new` でプロジェクトを作成してください。
:::


## コマンドラインオプション

:::{.section-lead}
一度だけ圧縮の有無を変えたり、問題を調べるために中間ファイルを残したりするときは、コマンドラインオプションを使います。
:::

```bash
vs build --help     # ヘルプを表示
```

### 主要オプション一覧

| オプション | 説明 |
|:---|:---|
| `--compress` / `--no-compress` | PDF 圧縮の有効 / 無効 |
| `--no-clean` | 中間生成物を残す（デバッグ用） |
| `--verify-links` | 外部 URL の HTTP 到達性チェックを有効にする |
| `--theme <color>` | テーマカラーを指定（`.md` ファイルの直接指定時のみ有効） |
| `--log <level>` | ログレベルを指定（error / warn / info / debug） |

### 使用例

```bash
# デバッグ用に中間ファイルを残す
vs build --no-clean

# 詳細なログを表示
vs build --log debug
```


## リンク・画像の自動検証

:::{.section-lead}
`vs build` では、原稿中の画像パスや URL も検証します。参照先が見つからないまま完成稿へ進まないよう、ビルド結果に出る警告も確認してください。
:::

検証はビルドを止めません。問題が見つかった場合は警告として報告され、ビルド自体は続行します。

### 検証される内容

**画像パスの存在チェック**

原稿内の画像記法 `![代替テキスト](foo.png)` を検証します。参照先のファイルが存在しない場合、ビルド後に警告が表示されます。

:::{.output}
```text
🔴 11-intro.md:15 - 画像 'foo.png' が見つかりません（代替画像を使用します）
        画像の場所: images/11-intro/foo.png
```
:::

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

問題がない場合は、次のように表示されます。

:::{.output}
```text
✅ リンク・画像の検証が完了しました（問題なし）
```
:::

問題がある場合は、次のように表示されます。

:::{.output}
```text
🔍 リンク・画像検証の結果:
        画像: 2 件の課題（存在しない画像: 2）
        リンク: 1 件の問題（裸 URL: 1）
        外部URL到達性チェック: スキップ（--verify-links で有効化）
```
:::

### 外部 URL の到達性チェック

`--verify-links` オプションを付けると、外部 URL に実際に HTTP リクエストを送信して到達性を確認します。ネットワークに依存するため、既定では行いません。

```bash
vs build --verify-links
```

到達できない URL が見つかった場合、サマリーに詳細が表示されます。

:::{.output}
```text
🔍 リンク・画像検証の結果:
   リンク: 1 件の問題（リンク切れ: 1）
   外部URL: 15 件チェック → 14 OK, 1 NG
     ❌ https://example.com/deleted-page → 404 Not Found
        参照元: 21-markdown-tutorial.md:88
```
:::

| ステータス | 判定 |
|:---|:---|
| 2xx | OK |
| 3xx | OK（リダイレクト先は追跡しない） |
| 4xx | 警告（リンク切れの可能性） |
| 5xx | 警告（サーバーエラー） |
| タイムアウト | 警告（到達不能） |

### book.yml での設定

外部 URL を毎回確かめるかどうかは、`config/book.yml` で決めます。画像と裸 URL の確認は常に行うので、設定はありません。

```yaml
verify:
  external_links: false  # 外部 URL の HTTP 到達性チェック（既定: false）
  timeout: 10            # HTTP チェックのタイムアウト秒数
  max_concurrency: 5     # HTTP チェックの最大同時接続数
```

`external_links: false` のままでも、`--verify-links` を付けたビルドでは外部 URL を確かめます。

:::{.note}
**コードブロック内は検証対象外**

コードブロック（`` ``` `` 〜 `` ``` ``）やインラインコード（`` ` `` 〜 `` ` ``）内の画像記法・URL は検証されません。サンプルコードとして URL を掲載している場合でも、誤検知の心配はありません。
:::


## 特殊記号や絵文字の自動処理

:::{.section-lead}
印刷所の入稿チェックでは、PDF に **Type 3 フォント**（文字の形を描画命令で持つフォント）が含まれていると指摘されることがあります。Vivlio Starter は、原因になりやすいものをビルド時に自動で処理するので、著者が原稿で対策する必要はありません。
:::

- **絵文字**: `output.pdf.techbook: true`（既定）のとき、本文の絵文字を Twemoji の画像に置き換えます。画像のクレジットは奥付に自動で入ります。EPUB では置き換えず、リーダーの絵文字で表示します。
- **見出しの記号**: 目見出し・号見出しの前の `♣` `♦` などの記号も、画像に置き換えます。
- **SVG 図版の文字**: 図に出る文字だけを書籍の書体から取り出して図に埋め込むので、どの環境でも同じ書体で組まれます。
- **波ダッシュ**: 入力環境によって別の文字コードになりやすい `〜` を、表紙・本文・奥付で一つにそろえます。

入稿用 PDF を作ったら、特殊記号や図の文字の見え方を開いて確かめ、入稿先の条件とも照らし合わせてください。

## トラブルシューティング

:::{.section-lead}
Vivliostyle などのツールがない・動かないときは、`vs doctor --fix` で導入してください。ここでは、ツールを入れても直らない症状を扱います。
:::

### 同じ表示のまま長時間止まって見える

**症状**: `ビルド中: build overall pdf …` や `ビルド中: backlink dedup …` から進まない。

**解決方法**:
- **そのまま待つ**。組版は正常に進んでいる
- 初回のビルドでは画像の変換（WebP 化と、PDF 向け派生の生成）が走る。2 回目以降は変換済みのものをそのまま使うため、この待ち時間は生じない
- それでも異常に長いと感じたら `vs doctor --fix` で依存ツール（Vivliostyle、qpdf など）の状態を確認する

**PDF は 2 回組まれます。** 索引や用語集のページ番号は、実際に組版してみるまで決まりません。そこで 1 回目（`build overall pdf`）でどの語が何ページに来るかを測り、番号を確定させてから 2 回目（`backlink dedup`）を組み直します。本書（27 章・384 ページ）ではそれぞれ約 2 分かかり、**合わせてビルド時間の 7 割以上** を占めます。スピナーがこの二つで長く止まるのは、そのためです。PDF と EPUB を両方出力するときは並列に組むので、EPUB 側のログは最後にまとめて出ます。

### ビルドを中断したあと、PDF の生成に失敗する

**症状**: `Ctrl+C` で中断した次のビルドで、PDF の生成に失敗する。または本文が欠落する。

**解決方法**:
- `vs doctor --fix` を実行してからビルドし直す

ビルドを途中で止めると、Vivliostyle が内部で使う Chrome は展開の途中で壊れ、そのまま残ることもあります。`vs doctor` はこの壊れたキャッシュを見つけて 🟡 で知らせ、`--fix` をつけると削除します。次のビルドで自動的に取得し直されるので、著者が手で消す必要はありません。

## まとめ

:::{.section-lead}
`vs build` には、一章の紙面を確かめる使い方と、本全体を各配布先の形式へ仕上げる使い方があります。原稿の段階に合わせてビルドの範囲を選べます。
:::

本章で紹介した内容を振り返ります。

- **閲覧用 PDF**（`targets: pdf`）— 内容確認と配布に
- **印刷入稿用 PDF**（`targets: print_pdf`）— 同人印刷所への入稿に
- **クリーン EPUB**（`targets: epub`）— 楽天 Kobo / Apple Books への配信に
- **Kindle 用 KPF**（`targets: kindle`）— Amazon Kindle（KDP）への配信に
- **単章ビルド**（`vs build 11`）— 執筆中のすばやい確認に
- **リンク・画像検証**（`--verify-links`）— リンク切れ・欠落画像の早期発見に
- **特殊記号・絵文字の対策** — Type 3 フォントや波ダッシュに起因する問題を抑える

ビルドの前後に使う `vs preflight`（組版を待たない原稿の点検）と、`vs pdf:pages`・`vs pdf:rasterize`（PDF のページの画像化）は @chapref:ch-utility で扱います。

まず原稿の参照先を `vs preflight` で確かめ、PDF で紙面を読み、配布先に合わせて EPUB や KPF も確認する。ビルドは、その読み返しを何度でも繰り返せるようにする工程です。

生成物を確認して文章へ戻りたくなったら、`vs metrics` で章ごとの分量や読みやすさの傾向を、`vs lint` で表記の揺れや綴りを確認できます。直した箇所を再びビルドし、紙面で読み直してください。
