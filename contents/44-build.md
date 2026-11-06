# ビルド

:::{.chapter-lead}
一章分の原稿ができた場合も、書籍全体の形を確かめたい場合も、`vs build` で組版結果を見られます。完成時には閲覧用 PDF、印刷入稿用 PDF、EPUB、Kindle 用 KPF まで、必要な形式を選んで生成できます。

本章では、まず一冊を作る手順を示し、その後に出力形式ごとの違いと確認方法を説明します。組む前に原稿の問題だけを手早く確かめる `vs preflight` も、あわせて紹介します。
:::

** 本章で扱うコマンドと設定 **

| コマンド・設定 | 目的 |
| :--- | :--- |
| `vs build` | 本全体を組む |
| `output.targets` | 出力する形式を選ぶ |
| `vs build lower` | 分冊の本で、巻を選んで組む |
| `vs build 11` | 指定した章だけを組む |
| `vs preflight` | 組まずに原稿を点検する |
| `vs build memo.md` | 設定ファイルなしで 1 本の原稿を組む |

## はじめてのビルド

:::{.section-lead}
`config/catalog.yml` に章を登録してあれば、まず次のコマンドで本全体をビルドできます。
:::

```bash
vs build
```

引数なしで実行すると、`config/catalog.yml` に登録した全章を組む**フルビルド**を行います。分冊の本で巻を選んで組む方法は、@pageref:build-volumes で説明しています。

### 出力形式の選択

出力する形式は、`config/book.yml` の `output.targets` で選びます。既定は `pdf` です。

| 形式 | 生成物 | 用途 |
|:---|:---|:---|
| `pdf` | 閲覧用 PDF | 画面での確認、配布 |
| `print_pdf` | 印刷入稿用 PDF | 印刷所への入稿（トンボ・塗り足し付き） |
| `epub` | EPUB | 楽天 Kobo、Apple Books への配信 |
| `kindle` | Kindle 用 KPF | Amazon Kindle（KDP）への配信 |

:::{.text-table}
生成したファイルは、プロジェクト直下に置かれます。ファイル名には、`book.yml` の `project.name` と `project.version` を使います。

```yaml:config/book.yml
project:
  name: "mybook"        # ファイル名
  version: "0.1.0"      # 書籍の版
  include_version: true # 版を付ける
```

`include_version` を `false` にすると、ファイル名に版（`_v0.1.0`）を付けません。

**この設定のときのファイル名**

| 形式 | ファイル名 |
|:---|:---|
| `pdf` | `mybook_v0.1.0.pdf` |
| `print_pdf` | `mybook_print_v0.1.0.pdf` |
| `epub` | `mybook_v0.1.0.epub` |
| `kindle` | `mybook_v0.1.0.kpf` |
:::

複数の形式を作るときは、カンマで区切って並べます。`[pdf, epub, kindle]` のように配列でも書けます。

```yaml:config/book.yml
output:
  targets: pdf, print_pdf      # 閲覧用 PDF と印刷入稿用 PDF
```

執筆中は `pdf` だけで内容を確かめ、入稿の前に `pdf, print_pdf` へ切り替えます。電子書籍も作るなら `pdf, epub, kindle` です。`output` セクションの設定の一覧は @chapref:ch-book-yml にあります。

### オプション

`vs build` には次のオプションを付けられます。一覧は `vs build --help` でも表示できます。

| オプション | 説明 |
|:---|:---|
| `--compress`<br>`--no-compress` | その回だけ PDF を圧縮する / しない（@pageref:pdf-compress） |
| `--verify-links` | 外部 URL の到達性を確かめる（@pageref:verify-links） |
| `--theme <color>` | テーマカラーを指定する（@pageref:direct-build） |
| `--log <level>` | 表示するログの水準を指定する（error / warn / info / debug） |

`--log` だけを付けると `info` になり、処理の経過が詳しく表示されます。

### ビルドに時間がかかるとき

全章のビルドには数分かかります。本書（約 290 ページ）では、閲覧用 PDF だけで約 3 分、四つの形式すべてで約 4 分です。進み具合は `ビルド中: build overall pdf … (12/25)` のように表示されます。

表示が長い間進まないように見えても、多くは組版の途中です。次のことを確かめてください。

- 初回のビルドは、画像を PDF 用に変換する分だけ長くかかる（`optimize images`）。2 回目以降は変換済みの画像を使う
- Mac がスリープしていないか確かめる。スリープしている間は、ビルドも止まる
- それでも異常に長いと感じたら、`vs doctor --fix` で依存ツール（Vivliostyle、qpdf など）の状態を確認する


## 閲覧用 PDF のビルド

:::{.section-lead}
`targets: pdf` は、執筆中の紙面確認にも、完成後の配布にも使える PDF を生成します。表紙の結合、圧縮、絵文字の扱いは `output.pdf` で設定します。
:::

### 表紙の結合

閲覧用 PDF には、本文の前に表紙が、後ろに裏表紙が付きます。付けないときは `combined` を `false` にします。

```yaml:config/book.yml
output:
  pdf:
    combined: true       # false にすると表紙と裏表紙を付けない
```

表紙の PDF は、ビルドのたびに `book.cover` で選んだデザインから作り直します。デザインの選び方は @chapref:ch-cover で説明します。

### PDF の圧縮 @pdf-compress

メールで送る、Web で配布するなど、ファイルを小さくしたいときは、`compress` を `true` にします。既定は `false` です。

```yaml:config/book.yml
output:
  pdf:
    compress: true
```

閲覧用 PDF とは別に、画像の解像度を 150 dpi に下げた `mybook_v0.1.0_compressed.pdf` を作ります。圧縮前の `mybook_v0.1.0.pdf` も残り、ビルド後にプレビューで開くのは圧縮した PDF です。圧縮には Ghostscript を使うので、ビルドの時間が延びます。

印刷入稿用 PDF は圧縮しません。`compress` が `true` のときも、入稿用 PDF は圧縮前の紙面から作るので、画像の解像度は下がりません。

その回のビルドだけ切り替えるときは、コマンドラインで指定します。ビルド済みの PDF を後から圧縮するときは、`vs pdf:compress` を使います（@chapref:ch-utility）。

```bash
vs build --compress      # 今回だけ圧縮する
vs build --no-compress   # 今回だけ圧縮しない
```

### 技術書典向けモード（techbook）

技術書典などの入稿では、カラー絵文字が Type 3 フォントとして PDF に入っていると、エラーになることがあります。`techbook` が `true`（既定）なら、本文の絵文字を Twemoji の SVG 画像に置き換えて、これを避けます。

```yaml:config/book.yml
output:
  pdf:
    techbook: true       # 絵文字を Twemoji の画像に置き換える
```

画像のクレジットは、タイトルページの次のページに入ります（`legal.twemoji`）。絵文字のほかに Type 3 を避けるために行う処理は、@pageref:type3-fonts で説明します。

### PDF のしおり（アウトライン）

PDF ビューアーの「しおり」（ブックマーク）に、章・節・小節の見出しが並びます。前書き・目次・付録・索引・用語集も、それぞれの名前で並びます。しおりをクリックすると、節と小節はその見出しの位置へ、章は章扉のページへ移動します。

しおりを付けるには、拡張機能 `vivlio-starter-pdf` が必要です。@chapref:ch-install の導入スクリプトでインストールした場合は、インストール済みです。インストールされていないときは、ビルドの途中に、インストールのコマンド（`gem install vivlio-starter-pdf`）が 💡 で表示されます。

### PDF プレビュー

macOS では、ビルドが終わるとプレビューで PDF を開きます。開く前にプレビューのウィンドウをすべて閉じ、開いた PDF を `window_bounds` の位置と大きさで表示します。

```yaml:config/book.yml
output:
  pdf_preview:
    close_existing_windows: true            # 閉じて並べる（false: 開くだけ）
    window_bounds: "{0, 0, 1280, 960}"      # 表示位置とサイズ
```

ウィンドウを閉じて並べるには、プレビューを操作する許可が要ります。導入スクリプトで「許可」と答えていれば、そのまま使えます。

許可は、ビルドを実行するアプリ（ターミナルやエディタ）ごとに要ります。導入スクリプトを使わなかった場合や、別のアプリでビルドした場合は、最初のビルドで macOS が「"ターミナル"から"プレビュー"を制御しようとしています」と確認します。「許可」をクリックすると、次からは確認されません。

許可しなかった場合も、PDF は開きます。最初の 1 回だけ、許可する手順が 💡 で表示されます。後から許可するときは、システム設定の「プライバシーとセキュリティ」→「オートメーション」で、お使いのアプリの「プレビュー」をオンにします。

ほかの PDF を開いたまま書くなど、プレビューのウィンドウを閉じたくない場合は、`close_existing_windows` を `false` にします。


## 印刷入稿用 PDF のビルド

:::{.section-lead}
印刷所へ渡す PDF は `targets: print_pdf` で生成します。トンボ（トリムマーク）と塗り足し（ブリード）が付くため、仕上がりサイズだけでなく、紙端の見え方も確認してください。
:::

```yaml:config/book.yml
output:
  targets: print_pdf
  print_pdf:
    bleed: 3mm           # 塗り足し幅
    crop_marks: true      # トンボを付ける
    full_bleed: false     # 本文にフチなし要素があるか
```

入稿用 PDF は `mybook_print_v0.1.0.pdf` の名前で作られ、トンボと塗り足しに加えて隠しノンブルも入ります。主要な同人印刷所（ねこのしっぽ、日光企画など）の入稿条件に対応しています。

入稿用 PDF は、閲覧用 PDF と同じ組版結果にトンボと塗り足しを加えて作ります。本文が同一なので、閲覧用で確かめた紙面がそのまま入稿物になります。本文に紙端まで届く画像や背景（フチなし要素）がある場合だけ、`full_bleed: true` を指定してください。入稿用 PDF を塗り足し付きで組み直すので、フチなし要素の端に白い筋が出ません。組み直す分、ビルドの時間は延びます。

### 入稿用の表紙

入稿用の表紙と裏表紙は、本文とは別のファイルとして、プロジェクト直下に出力されます（`mybook_frontcover_v0.1.0.pdf`・`mybook_backcover_v0.1.0.pdf`）。塗り足しの埋め方や色の変換は @pageref:print-cover で説明します。

CMYK への変換には、`@vivliostyle/cli` と一緒にインストールされる Japan Color 2001 Coated の ICC プロファイルを使います。印刷所から別のプロファイルを指定されたときは、そのファイルのパスを書きます。

```yaml:config/book.yml
output:
  print_pdf:
    icc_profile: /path/to/JapanColor2001Coated.icc
```


## EPUB のビルド

:::{.section-lead}
楽天 Kobo や Apple Books 向けの EPUB は、`targets: epub` で生成します。本文が画面幅に合わせて流れる形式なので、PDF とは別に、macOS の「ブック」アプリや Calibre などで、文字サイズを変えたときの改行や画像の収まり方を確かめます。Kindle 向けには、後述の `targets: kindle` を使います。
:::

```yaml:config/book.yml
output:
  targets: epub
  epub:
    embed: true                # 表紙画像を EPUB に埋め込む
    layout: reflowable         # リフロー型
```

EPUB はリフロー型（`reflowable`）で作ります。端末の画面の幅と文字の大きさに合わせて、本文が折り返されます。

### 表紙

EPUB には、`book.cover` で選んだ表紙から作った 1,600 × 2,560 px の JPEG が埋め込まれます。同じ JPEG がプロジェクト直下にも置かれます（`mybook_frontcover_v0.1.0.jpg`）。左右が切り落とされるので、文字は中央寄りに置いてください（@chapref:ch-cover）。表紙を埋め込まないときは、`embed` を `false` にします。

### メタデータ

EPUB のメタデータ（書名、著者名、言語、ISBN など）には、`book` セクションの値を使います。EPUB のために別に書く必要はありません。

### フォントと画像

EPUB ではフォントを埋め込まず、本文・見出し・コードはリーダーの明朝体・ゴシック体・等幅の書体で表示されます。絵文字も画像にせず、リーダーの絵文字で表示します。画像は紙面に見合う大きさまで縮めて収録します（`images/` の画像は書き換えません）。いずれも著者が設定する項目はありません。


## Kindle のビルド

:::{.section-lead}
Amazon Kindle（KDP）向けには `targets: kindle` を指定します。Kindle 用に調整した中間 EPUB を作り、`kindlepreviewer` で `.kpf` へ変換します。図や数式の扱いが通常の EPUB と異なるため、完成後は Kindle Previewer で確認してください。
:::

```yaml:config/book.yml
output:
  targets: kindle
```

ビルドが完了すると、プロジェクト直下に `mybook_v0.1.0.kpf` が生成されます。KDP の管理画面では、この `.kpf` をアップロードしてください。

表紙は `.kpf` に含めず（`kindle.embed: false`）、KDP の登録画面で別にアップロードします。KDP の決まりで、本の中に表紙を含めると、KDP が追加する表紙と合わせて二重になるためです。アップロードする表紙には、プロジェクト直下の `mybook_frontcover_v0.1.0.jpg` を使ってください（@chapref:ch-cover）。

### EPUB との違い

Kindle の表示エンジン（KFX）は、EPUB の一部の画像形式や CSS に対応していません。そこで `kindle` では、Kindle で確実に表示できる形へ変えた中間 EPUB を作ってから、`.kpf` へ変換します。著者が原稿を書き分ける必要はありません。

| 項目 | `epub` | `kindle` |
|:---|:---|:---|
| 配信先 | 楽天 Kobo / Apple Books | Amazon Kindle（KDP） |
| 最終成果物 | `.epub` | `.kpf` |
| 画像 | WebP・SVG のまま | JPEG / PNG に変換 |
| 扉絵・節絵 | SVG のまま（拡大しても鮮明） | JPEG に変換 |
| インライン数式 | SVG の画像 | 単純な式はテキスト、それ以外は画像 |
| ディスプレイ数式 | SVG の画像 | PNG の画像 |

**インライン数式は、Kindle では文字の大きさに合わせて変わります。** 画像は読者が文字を大きくしても追従しないので、テキストにできる式は Kindle 版でテキストに変えます。``E=mc^2`` は上付き文字のテキストに、``√(GM/R)`` のように整えきれない素の表記は書いたとおりの文字になります。テキストにできない LaTeX の式は画像のまま残るので、Kindle Previewer で大きさを確かめてください。**複雑な式はディスプレイ数式（`$$ … $$`）で書く**と、本文の途中に大きさの変わらない画像を置かずに済みます。

### Kindle Previewer のインストール @kindle-previewer

`.kpf` への変換には、Amazon が配布する **Kindle Previewer 4** に含まれる `kindlepreviewer` コマンドが必要です。インストールされていない場合、Kindle 用の中間 EPUB までは生成されますが、`.kpf` への変換は省略され、ビルドの最後に 💡 でインストール方法が表示されます。

`targets` に `kindle` がある本で `vs doctor --fix` を実行すると、Homebrew で Kindle Previewer をインストールし、`kindlepreviewer` コマンドを使えるようにします（管理者のパスワードを尋ねます）。導入スクリプトで Kindle 向けにも作ると答えた場合は、インストール済みです。インストール後の更新は、アプリの更新機能で行えます。

Kindle Previewer 3 では `.kpf` へ変換しません。3 をお使いでしたら、4 へ更新してから `vs doctor --fix` を実行してください。

`vs doctor --fix` を使わずにインストールしたときは、`which kindlepreviewer` でコマンドにパスが通っているかを確かめてください。

:::{.tip}
**Apple Silicon の Mac をお使いの場合**

Kindle Previewer 4 のアプリは Apple Silicon に対応していますが、変換するプログラムは Intel 用です。そのため Rosetta 2 がインストールされていないと、`.kpf` への変換だけが `bad CPU type in executable` というエラーで失敗します。

新しい Mac には、Rosetta 2 がインストールされていないことがあります。`targets` に `kindle` がある本では、`vs doctor --fix` が Kindle Previewer と一緒にインストールします。手動でインストールする場合は、次のコマンドを実行します。

```bash
sudo softwareupdate --install-rosetta --agree-to-license
```
:::

KDP にアップロードする前に、`.kpf` を Kindle Previewer で開き、扉絵・図・コード・表・数式が意図どおり表示されるか（図の細い線や小さな文字が読めるか）を確かめてください。

## 分冊と合本のビルド @build-volumes

:::{.section-lead}
上下巻のように分冊にした本では、巻を選んで組むことも、全巻を一冊にまとめた合本を組むこともできます。巻の書き方（`catalog.yml` の `VOLUMES:`）は @pageref:volumes で説明しています。
:::

```bash
vs build lower   # 下巻を組む（巻の id を書く）
vs build all     # 全巻を、巻の順に一巻ずつ組む
vs build         # 全巻を一冊にまとめた合本を組む
```

<!-- no-lint -->
巻を選んで組むと、出力ファイル名に巻の `id` が入り（`mybook_lower_v0.1.0.pdf`）、目次の題は「下巻 目次」のように巻の名前を添えたものになります。合本は、全巻の本文と付録を一冊にまとめて組みます（載る前書き・後書きは @pageref:book-matter）。校正や、電子版の合本に使います。

巻でも合本でも、`output.targets` に書いた形式をすべて作ります。巻を選んで組んだときは、印刷入稿用 PDF・EPUB・Kindle 用 KPF の名前にも、巻の `id` が入ります。

`vs build all` は、途中の巻で組版に失敗すると、そこで止まります。それまでに組んだ巻の出力は残るので、直したら `vs build lower` のように、止まった巻から組み直せます。

巻の `id` は、章と並べて書けません（`vs build lower 21` はエラーになります）。章を指定すると単章ビルドになり、巻は章から決まります。一つの巻に収まる章はその巻の番号の振り方で組み（`vs build 21`）、別の巻の章を並べたとき（`vs build 11 21`）は、巻のない本と同じように指定した章をすべて組みます。

`vs preflight lower`・`vs lint lower`・`vs metrics lower` のように、ほかのコマンドでも巻を選べます。選ばなければ、すべての巻の原稿を対象にします。


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

章の指定方法は @ch-chapter-management の章の @pageref:chapter-targets で説明しています。

単章ビルドでは、`output.targets` の指定にかかわらず**閲覧用 PDF のみ**が生成され、目次や索引のページも作られません。PDF の圧縮もしません。印刷入稿用 PDF や EPUB・Kindle が必要なときは、章を指定せずに `vs build` を実行してください。


## 原稿の点検 @preflight

:::{.section-lead}
組版を待たずに原稿の問題を確かめたいときは、`vs preflight` を使います。PDF を生成せず、画像やコードの参照先などを短時間で確認できるので、章を書き終えたときに実行すると、置き忘れを早く見つけられます。
:::

### vs build との比較

| | `vs preflight` | `vs build` |
|:---|:---|:---|
| 実行時間 | 数秒 | 数分（本書の全章で約 3 分） |
| PDF 生成 | しない | する |
| 用途 | 執筆中の頻繁なチェック | 入稿・配布前の最終ビルド |

`vs build` も、組み始める前に同じ点検をして 🔴・🟡 を表示します。ただし、そのまま組版へ進むので、終わるまで数分かかります。`vs preflight` は点検だけで終わるので、直してはすぐに確かめ直せます。

### 基本的な使い方

```bash
vs preflight         # 全章をチェック
vs preflight 11      # 11章だけチェック
vs preflight 21-24   # 21〜24章をチェック
vs preflight intro   # スラッグが intro の章をチェック
```

章の指定方法は、単章ビルドと同じです。

### 実行結果の見方

`🔴` は品質エラー（著者の意図が成果物に反映されない）、`🟡` は警告（確認を促したい）を表します。検出できる主な問題の種別は、次のとおりです。

| 種別 | 記号 |
|:---|:---:|
| 画像ファイル不在 | 🔴 |
| コードインクルードファイル不在 | 🔴 |
| QueryStream 雛形ファイル不在 | 🔴 |
| ラベル ID重複 | 🔴 |
| 未定義のラベル | 🟡 |
| 孤立ラベル | 🟡 |
| `stylesheets/` に定義のないクラス名 | 🟡 |
| 本の書体にない字 | 🟡 |
| 組めない数式 | 🟡 |

たとえば `vs preflight 95` で 95 章を点検し、画像とコードのファイルが見つからなかったときは、次のように出力されます。

:::{.output}
```text
🔴 95-sample.md:17 - 画像 photoelectric.png が見つかりません（代替画像を使用します）
        画像の場所: images/95-sample/photoelectric.png
🔴 95-sample.md:234 - ソースコード mass_energys.rb が見つかりません
        コードの場所: codes/mass_energys.rb
🔍 リンク・画像検証の結果:
        画像: 1 件の課題（存在しない画像: 1）
        ソースコード: 1 件の課題（存在しないファイル: 1）
        外部URL到達性チェック: スキップ（--verify-links で有効化）

📋 章別サマリー
   95 挑戦することの贈り物        🔴 エラー 2 件
❌ Preflight 完了: エラー 2 件・警告 0 件 — 詳細は上記を確認してください
   文章校正（表記揺れ・スペル）は vs lint で行えます。
```
:::

章を指定せずに `vs preflight` で全章を点検すると、章別サマリーに全章が並び、課題のある章に件数が付きます。課題がない場合には、次のように出力されます。

:::{.output}
```text
✅ Preflight 完了: 良好な状態です
   文章校正（表記揺れ・スペル）は vs lint で行えます。
```
:::

警告だけのときは「❗ Preflight 完了: 警告 2 件（ビルドは可能です）」のように出力され、そのままビルドへ進めます。

### オプション

| オプション | 説明 |
|:---|:---|
| `--verify-links` | 外部 URL の到達性も確かめる（@pageref:verify-links） |
| `--log <level>` | 表示するログの水準を指定する（error / warn / info / debug） |
| `-h` / `--help` | ヘルプを表示 |



## 設定ファイルなしのビルド @direct-build

:::{.section-lead}
配布資料などを、プロジェクトを作らずに 1 本だけ組版したいことがあります。`vs build` に `.md` ファイルを直接指定すると、`book.yml` も `catalog.yml` も使わずに PDF を生成します。
:::

```bash
vs build myawesome.md                      # プロジェクトの外でも実行できる
vs build ~/notes/idea.md --theme blue      # ディレクトリやテーマカラーを指定
```

カレントディレクトリに `myawesome.pdf`（元ファイル名の拡張子違い）が生成され、macOS では自動的に開きます。

`--compress` を付けると、圧縮した `myawesome_compressed.pdf` も作り、そちらを開きます。配る前にファイルを小さくするときに使います。画像の多い資料ほど小さくなります。

資料の URL が正しいかを確かめるときは、`--verify-links` を付けます。書籍のビルドと同じく、外部 URL に実際にリクエストを送り、リンク切れを報告します（@pageref:verify-links）。

`--theme` には `book.yml` の `theme.color` と同じ色名（yellow / orange / red / magenta / purple / indigo / navy / blue / cyan / teal / green / lime）に加えて、`--theme '#e91e63'` のような HEX 記法も指定できます。省略時は blue です。シェルが `#` をコメントとして解釈しないよう、HEX は引用符で囲んでください。

:::{.note}
このモードは、配布資料のような短い原稿の組版向けです。

- 出力は**閲覧用 PDF のみ**です（印刷入稿用 PDF・EPUB・Kindle は作られません）
- 装飾は**画像なし（simple）**、判型は A4 判に決まっています
- 節（`##`）ごとの改ページはせず、続けて組みます
- 章が一つだけのときは章番号を付けません（節は「1」「2」、図表は「図 1」と振ります）
- 章見出し（`#`）を複数書くと、`#` ごとに「第1章」「第2章」と章として組みます
- `---` だけの行を書くと、その位置で改ページします（章見出しの直前の `---` は無視します）
- 画像は入力ファイルと同じ場所からの相対パスで解決します
- `codes/` からのコードインクルード、QueryStream 記法、他章へのクロスリファレンス、索引・用語集は使えません

書籍として仕上げるときは `vs new` でプロジェクトを作成してください。
:::


## 画像・リンクの自動検証

:::{.section-lead}
`vs build` では、原稿中の画像パスや URL も検証します。参照先が見つからないまま完成稿へ進まないよう、ビルド結果に出る報告も確認してください。
:::

問題が見つかってもビルドは中断せず、最後まで組んでから報告します。

### 画像パスの確認

原稿内の画像記法 `![代替テキスト](foo.png)` の参照先にファイルがないと、その行を 🔴 で報告し、紙面には代わりの画像を置きます。

:::{.output}
```text
🔴 11-intro.md:15 - 画像 'foo.png' が見つかりません（代替画像を使用します）
        画像の場所: images/11-intro/foo.png
```
:::

ビルドの最後には、見つかった問題の件数がまとめて表示されます（形は @pageref:preflight の出力例と同じです）。

### 外部 URL の到達性チェック @verify-links

`--verify-links` オプションを付けると、外部 URL に実際に HTTP リクエストを送信して到達性を確認します。リンク記法の URL も、本文にそのまま書いた URL も確かめます。そのまま書いた URL は、全角の括弧や句読点の手前までを URL とみなします。ネットワークに依存するため、既定では行いません。

応答が 400 番台・500 番台のとき、時間内に応答がないとき、接続できないときは、リンク切れとして 🔴 で報告します。300 番台（リダイレクト）は、リダイレクト先を確かめずに到達できたとみなします。

:::{.output}
```text
🔍 リンク・画像検証の結果:
        リンク: 1 件の問題（リンク切れ: 1）
🔴 21-markdown-tutorial.md:88 - リンク切れを検出しました
        URL: https://example.com/deleted-page → 404 Not Found
```
:::

毎回確かめるときは、`config/book.yml` の `verify.external_links` を `true` にします（@chapref:ch-book-yml）。コードブロックやインラインコードの中の画像記法・URL は検証しません。


## 記号と絵文字の自動処理 @type3-fonts

:::{.section-lead}
印刷所の入稿チェックでは、PDF に **Type 3 フォント**（文字の形を描画命令で持つフォント）が含まれていると指摘されることがあります。Vivlio Starter は、原因になりやすい字をビルド時に自動で処理し、処理できない字は報告します。
:::

絵文字、見出しの記号、本の書体にない記号や漢字、図（SVG）の中の字は、ビルドのときに PDF で組める形へ自動で置き換わります。原稿を書き分ける必要はなく、原稿のファイルも書き換えません。

本の書体にない漢字は、その字を持つ書体から字の形を取り出して組みます。保存した形は、ほかのコンピュータでも同じ形で組むために使うので、`images/gaiji/` は削除せずに管理してください。

それでも組めない字や数式は、`vs build` と `vs preflight` が組む前に、原稿の行と修正方法を表示します（例の `〓` の位置には実際の字が出ます）。漢字なら、その字を持つ書体（思源宋体・Noto Serif CJK など）をインストールしても組めます。

:::{.output}
```text
🟡 51-numbers.md:88 - 本の書体にない字があります: 〓
        → 〓 → 本の書体にある字に置き換える（組む PC の書体で代わりに組まれ、Type 3 になると入稿で断られることがあります）
🟡 51-numbers.md:120 - 数式が組めていません: $x^a^b$
        → 上付きが重なっています。{ } でまとめてください（例: x^a^b → x^{a^b}）
```
:::

全章の `vs build` は、仕上がった PDF の Type 3 も調べ、ページと字を報告します。入稿用 PDF では、記号や図の文字の見え方を開いて確かめ、入稿先の条件とも照らし合わせてください。
