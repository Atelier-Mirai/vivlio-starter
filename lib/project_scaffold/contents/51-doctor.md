# 環境の診断と更新

:::{.chapter-lead}
Vivlio Starter で本を作るには、組版や画像処理などを担う外部ツールが必要です。新しい環境を用意したときや、ビルドが急に通らなくなったときは、`vs doctor` で不足しているツールを調べられます。必要なら `--fix` で導入もできます。現在お使いの環境を新しいバージョンへ更新するには `vs upgrade` を使います。この章では、それぞれの役割と使いどころを見ていきます。
:::

## vs doctor とは

:::{.section-lead}
`vs doctor` は、Vivlio Starter に必要なツールや設定ファイルを調べるコマンドです。ビルドや lint が失敗したときも、まず環境に不足がないかを確かめられます。
:::

新しい Mac で執筆を始める前に実行しておくと、必要なツールを一覧で確認できます。作業中にコマンドが動かなくなった場合も、原因を絞り込む手がかりになります。

Vivlio Starter gem の導入や Ruby 環境の構築については、@chapref:ch-install を参照してください。

### 診断対象ツール

| ツール | 用途 |
|--------|------|
| Xcode Command Line Tools | macOS のビルドツールチェーン（macOS のみ） |
| `node` / `npm` | JavaScript ランタイム（Vivliostyle CLI の前提） |
| `vivliostyle` | PDF 生成エンジン |
| `textlint` | 文章校正ツール |
| `qpdf` | PDF 分割・結合・ページ操作 |
| `pdfinfo` (poppler) | PDF メタデータ取得 |
| `pdftoppm` (poppler) | PDF ページの画像化（`vs pdf:pages`・OCR） |
| `gs` (Ghostscript) | PDF 圧縮 |
| `imagemagick` | 画像変換・リサイズ |
| `inkscape` | SVG ラスタライズの予備経路（任意） |
| `rsvg-convert` (librsvg) | EPUB 扉絵・節絵の合成画像ラスタライズ |
| `vips` (libvips) | 高速画像処理 |
| `tesseract` | OCR エンジン |
| tesseract 日本語データ | Tesseract の日本語学習データ |
| `mecab` | 索引の読み自動推測・交ぜ書き検出の第 2 層 |
| `mathjax-full` | 数式の SVG 化（npm パッケージ） |
| `mermaid` (`mmdc`) | ダイアグラムの画像化（npm パッケージ） |
| `guesslang` | `vs lint` でのコードブロックの言語推定（npm パッケージ `@vscode/vscode-languagedetection`） |
| `waifu2x-ncnn-vulkan` | AI 画像拡大（オプション） |
| `kindlepreviewer` (Kindle Previewer) | Kindle（KPF）変換（任意・targets: kindle 用） |
| Google Fonts 用 SSL 証明書 | Google Fonts ダウンロード（macOS のみ） |

### あるのに動かない場合を見つける

ツールが入っていても、版が古いと正しく動かないことがあります。`vs doctor` は、見つかったツールの版も確かめます。

Kindle Previewer 3 が入っていれば、4 への更新を案内します（@chapref:ch-build）。Apple Silicon の Mac で Rosetta 2 が入っていなければ、導入のコマンドを案内します。`config/book.yml` の `targets` に `kindle` がある本では、`--fix` が Rosetta 2 を入れます（管理者のパスワードを尋ねます）。

**Node.js は、Vivliostyle が求める版以上を使います。** Vivliostyle は版ごとに必要な Node.js の版を決めています（Vivliostyle CLI 11 なら 22.12 以上）。`vs doctor` は、ビルドで実際に使われる Vivliostyle の要求を読み、それより古い Node.js が入っていると更新を案内します。

:::{.output}
```text
✅ node: OK
🟡 Node.js 20.19.0 は Vivliostyle CLI 11.3.3 の要求を満たしません（22.12.0 以上が必要です）
        → brew upgrade node
          Homebrew 以外（nvm など）で入れた場合は、その道具で 22.12.0 以上へ更新してください。
```
:::

### 設定ファイルの診断

書籍プロジェクト内で実行した場合は、外部ツールに加えて `config/` 内の設定ファイルも診断します。

- **必須設定ファイル**（`config/book.yml` / `config/catalog.yml`）が存在し、YAML として正しく読み込めるかを確認します。
- **任意設定ファイル**（textlint の設定や辞書ディレクトリなど）の有無を確認します。

必要なファイルが揃っていれば、次のように表示されます。

:::{.output}
```text
✅ config/ 設定ファイル: OK
```
:::

`--fix` を付けると、不足している設定ファイルや辞書を `vs new` の雛形から補います。`book.yml` が破損して読み込めない場合は、**書名や著者名など、取り出せる値をできるだけ残して**テンプレートから作り直します。元のファイルはバックアップされるので、復元後に内容を確認できます。

## 基本的な使い方

:::{.section-lead}
まず `vs doctor` で診断結果を見てから、必要に応じて `--fix` を付けて実行します。どのツールを導入するのか確認してから進められます。
:::

### 診断のみ実行

```bash
vs doctor
```

ツールの状態を一覧で表示します。このコマンドだけではインストールや設定の変更は行いません。

:::{.output}
```text
🔎 環境診断を開始します…
✅ config/ 設定ファイル: OK
✅ Xcode Command Line Tools: OK
✅ node: OK
✅ textlint: OK
✅ vivliostyle: OK
✅ qpdf: OK
❌ pdfinfo: 見つかりません
✅ gs: OK
✅ imagemagick: OK
…
不足しているツール: pdfinfo (poppler)
ヒント: macOS の場合は `vs doctor --fix` で自動インストールを試行できます
```
:::

### 自動インストール（--fix）

```bash
vs doctor --fix
```

診断で不足が見つかったツールをインストールします。macOS では主に Homebrew を使います。Homebrew 自体や Xcode Command Line Tools が入っていない場合は、その導入前に確認を求められます。

Node.js も対象です。vivliostyle や textlint など、npm で導入するツールは Node.js の準備が済んでからインストールされます。

Vivliostyle CLI は、`vivliostyle` の別名として `vs` というコマンドも入れます。Vivlio Starter の `vs` と同じ名前なので、`--fix` はこの別名を外します（`vs upgrade` も同じです）。Vivliostyle は `vivliostyle` の名前でそのまま使えます。

:::{.output}
```text
🛠 不足しているツールをインストールします…
🔁 インストール後の再診断…
✅ すべてのツールがインストールされました
```
:::

### 確認プロンプトをスキップ（--yes）

```bash
vs doctor --fix --yes
```

`--yes`（短縮形は `-y`）を `--fix` と組み合わせると、Xcode Command Line Tools や Homebrew の導入時に出る確認を省略できます。CI/CD やセットアップ用のスクリプトなど、対話せずに実行したいときに使います。

## 自動インストールの対応範囲

:::{.section-lead}
`--fix` による外部ツールの自動インストールは、macOS と Homebrew の組み合わせに対応しています。Linux や Windows では、必要なツールを手動で導入してください。
:::

macOS では、ツールに応じて次の経路で導入します。

| 導入経路 | ツール |
|------|------|
| `brew install` | `node`・`qpdf`・`pdfinfo`・`pdftoppm`・`gs`・`imagemagick`・`inkscape`・`librsvg`・`vips`・`tesseract`・`mecab` |
| `npm install -g` | `vivliostyle`・`textlint` と推奨ルール・`mathjax-full`・`mermaid-cli`・Guesslang |

npm で導入するツールには Node.js が必要です。まだ入っていなければ、Homebrew で Node.js を導入してから npm の処理へ進みます。

次の四つは、確認や追加の処理が必要です。

- **Xcode Command Line Tools**（`xcode-select --install`）と **Homebrew**（公式インストーラ）— 入っていない場合は、導入前に確認を求められます
- **textlint** — 本体と一緒に日本語技術書向けのルールセットを導入し、設定ファイルを `config/` に配置します
- **`waifu2x-ncnn-vulkan`** — Homebrew では配布されていないため、GitHub Releases からダウンロードします
- **Kindle Previewer** — `config/book.yml` の `targets` に `kindle` がある本でだけ、`brew install --cask kindle-previewer` でアプリを入れ、コマンドから呼び出すためのラッパーを作ります。Apple Silicon の Mac には Rosetta 2 も入れます。どちらも管理者のパスワードを尋ねます。アプリがすでに入っていれば、ラッパーだけを作ります

インストール手順や対応する版は変わることがあります。ここにない方法で導入するときや、案内どおりに進まないときは、各ツールの公式ドキュメントで現在の手順を確認してください。

## vs upgrade — 環境をまとめて最新化する

:::{.section-lead}
`vs upgrade` は、使っている執筆環境をまとめて更新するコマンドです。プロジェクトの直下で実行すると、Vivlio Starter 本体、プロジェクトの雛形、外部ツールの順に更新します。
:::

1. **`vivlio-starter` 本体の更新** — 新版があれば、確認後に `gem update vivlio-starter` を実行します。その後の処理は**新しい版で自動的に続行**するため、雛形の取り込みをやり直す必要はありません
2. **プロジェクトの雛形追従** — 新しい版のスタイルシートやテンプレートを既存プロジェクトへ取り込み、最後に `Gemfile.lock` が指す版も合わせます
3. **外部ツールの一括更新** — Homebrew（formula / cask）、npm、gem で導入したツールの更新計画を示し、確認後にまとめて更新します。Kindle Previewer はアプリの更新機能で上がるので、計画では対象外と表示します

```bash
vs upgrade                    # 計画を提示 → 確認しながら適用
vs upgrade --dry-run          # 計画（何が追加/更新/合流/競合か）の表示のみ
vs upgrade --yes              # 競合以外（追加・未カスタムの更新・自動合流）を確認なしで適用
vs upgrade --skip-self-update # 本体 gem の更新だけ行わない
```

プロジェクトの外で実行すると、雛形の追従を省き、本体と外部ツールだけを更新します。

更新後の診断では、不足しているツールの導入も行います。通常は `vs doctor --fix` を続けて実行する必要はありません。外部ツールがすべて最新で、不足も無いときは、診断を省きます。設定ファイルや証明書まで確かめるときは `vs doctor` を実行します。

### 雛形の追従

雛形の各ファイルは、変更の状態に応じて分類されます。実際に適用する前に、次のような計画表で確認できます。

| 分類 | 意味 | 動作 |
|------|------|------|
| 追加 | 雛形の新規ファイル | コピーします |
| 更新 | 雛形は変更され、手元では未変更 | 新しい雛形を適用します（`--yes` で確認なし） |
| 合流 | 雛形と手元で**別の箇所**を変更 | 両方の変更を自動で取り込みます（確認なし） |
| 競合 | 雛形と手元で**同じ箇所**を変更 | diff を示し、1 件ずつ確認します（y/n/d） |
| 整理 | `book.yml` の廃止キーと新しい設定など | 示した箇所だけを直します（`--yes` で確認なし） |

:::{.output}
```text
🔍 雛形との差分を確認しています…（gem 1.2.0 の雛形）
📋 更新計画:
   追加   stylesheets/talk.css
   更新   stylesheets/chapter-common.css
   合流   stylesheets/preface.css
   競合   stylesheets/custom.css
   整理   config/book.yml
            廃止キーを削除します（index.max_sub_references）
            新しい設定キーを追加します（theme.lead_size ほか 8 件）
```
:::

たとえば、自分でスタイルシートの末尾に規則を加え、新しい雛形では先頭が改良された場合は「合流」です。**変更箇所が離れていれば、両方を残して取り込めます。** 同じ箇所を変更していた場合は「競合」となり、差分を見て適用するか選びます。適用すると自分の変更が失われることも、その場で示されます。元のファイルは退避されるため、必要なら戻せます。

:::{.note}
**原稿と辞書は構造的に安全です**

`contents/`・`images/`・`covers/`（`bundled/`・`templates/` を除く）・`codes/`・`data/` と、`book.yml`・`catalog.yml`・索引/用語集辞書・ユーザー辞書は「著者データ領域」です。`vs upgrade` はこれらを雛形で上書きしません。`book.yml` だけは、廃止されたキーを削除し、新しいキーを追加します。書いてある値とコメントはそのまま残ります。更新対象のファイルも、上書きする前に `.cache/vs/upgrade-backup/` へ退避します。変更を戻したいときは、そこから元の内容を確認できます。
:::

同梱の素材は著者データ領域の外にあり、新しい雛形に合わせて更新されます。表紙のテンプレート（`covers/bundled/`）、自作の表紙の雛形（`covers/templates/`）、扉絵・装飾画像（`stylesheets/images/bundled/`）、テーマ色（`stylesheets/theme.css`）です。新しく同梱された素材も追加されます。

著者が雛形のファイルを変更したかどうかは、`vs new` が作る `config/scaffold.lock` で判定します。このファイルは手で編集せず、Git にコミットしてください。

### 雛形の更新の知らせ

`gem update` だけで本体を更新すると、スタイルシートの改良はプロジェクトへ届きません。そこで、全章の `vs build` と `vs preflight` は、雛形のスタイルシートや `book.yml` に書ける設定が新しくなっていれば、最後に知らせます。

:::{.output}
```text
💡 雛形が新しくなっています（CSS: colophon.css ほか 3 件・book.yml の設定: 2 件）
        vs upgrade で確かめられます
```
:::

`vs build 11` のように章を指定したときは知らせません。`vs upgrade` を実行すると、次に雛形が変わるまで消えます。競合を断ったスタイルシートも、次に雛形が変わるまで知らせません。

増えた設定は、`vs upgrade` が `book.yml` へコメントごと追加します。更新計画に「整理」の行として示し、確認で「いいえ」と答えれば追加しません。値は既定値なので、組み上がりは変わりません。雛形の並びのとおりに差し込み、ほかの行には触れません。変更前のファイルは `.cache/vs/upgrade-backup/` に残ります。

:::{.output}
```text
✅ book.yml に新しい設定を 2 つ追加しました（値は既定値なので、組み上がりは変わりません）
        theme.lead_size
        index_glossary.exclude_chapters
        設定の詳細は vs config:book theme.lead_size として確認できます
```
:::

追加するのは、新しい設定につき 1 回だけです。追加された設定を消しても、次の `vs upgrade` で戻ることはありません。`--dry-run` では、追加する行を見せるだけです。

`theme: { color: red }` のように 1 行にまとめて書いた区分には追加できないので、追加する行を並べます。使いたい設定だけを `config/book.yml` へ写してください。

### Gemfile.lock の追随

雛形を取り込んだあと、`Gemfile.lock` が指す Vivlio Starter の版を、使っている版に合わせます（`bundle update vivlio-starter` に相当します）。失敗したときは 🟡 で手動の対処方法を案内します。

:::{.note}
**`vs` が `Bundler::GemNotFound` で起動しないとき**

1.0.0 より前の版で作ったプロジェクトでは、`vs` の起動時に `Could not find vivlio-starter-… in locally installed gems` というエラーが出ることがあります。`Gemfile.lock` に記録された版が手元にないためで、この状態では `vs upgrade` も実行できません。`vs` を使わずに gem を更新してください。

```bash
gem update vivlio-starter
```

1.0.0 以降の `vs` は `Gemfile.lock` を見ずに起動します。gem の更新後は `vs upgrade` を実行し、残りの環境を整えられます。
:::

### 外部ツールの一括更新

雛形を取り込んだあと、導入済みの外部ツールを調べます。更新計画には、対象のツール、現在と更新後の版、導入経路が表示されます。内容を確認してから更新を進めます。

:::{.output}
```text
🔍 外部ツールのバージョンを確認しています…
📋 更新計画:
   qpdf              12.1.0  → 12.2.1   (brew)
   vivliostyle CLI   10.6.0  → 11.2.0   (npm・node と連動)
   node              22.11.0 → 変更なし  (brew・最新)
   ...
更新を実行しますか？ [y/N]: y
⬆️  qpdf を更新中…
✅ qpdf: 更新しました
🩺 更新後の診断を実行します…
✅ 更新完了: 2 件成功 / 0 件失敗
```
:::

外部ツールの更新には、次のような扱いがあります。

- 不足しているツールも導入します（`vs doctor --fix` 相当）。更新後に診断をもう一度実行し、ツールを正常に使えるか確かめます
- 一部のツールで更新に失敗しても、ほかのツールの処理は続けます。失敗したものには、手動での復旧コマンドを示します
- node を更新するときは、版の組み合わせによる不具合を避けるため、vivliostyle CLI も同時に最新版へ更新します
- Ruby 本体は自動更新しません。新版がある場合は、実行の最後に「📣 お知らせ」として、rbenv など使用中の導入経路に合った手順を示します
- ツールの更新に対応するのは macOS と Homebrew の組み合わせです。それ以外の環境では、この処理だけをスキップします
- ネットワークに接続できない場合は、更新が途中で止まるのを避けるため、実行前に中断します

## vs doctor と vs upgrade の使い分け

二つのコマンドは、環境に問題があるかを調べたいのか、新しい版へ更新したいのかで選びます。

| | `vs doctor` | `vs upgrade` |
|------|------|------|
| 答える問い | 「必要なツールは揃っている？」 | 「使っている環境を更新したい」 |
| 性質 | 読み取り専用の診断（`--fix` で修復） | 環境を変更する更新 |
| ネットワーク | 不要（オフラインで動く） | 必要（gem / brew / npm へ照会） |
| 所要時間 | 数秒 | 数分 |
| 使いどころ | ビルドが突然失敗した・新しい環境を整える | 動いている環境を定期的に更新する |

ビルドが失敗したときは、まず `vs doctor` で不足や設定の問題を確かめてください。原因が分からないまま `vs upgrade` を実行すると、複数のツールの版が変わり、かえって問題を切り分けにくくなることがあります。

新しい Mac をセットアップするときは、@chapref:ch-install の導入スクリプトを使います。Homebrew・Ruby・Vivlio Starter と、`vs doctor --fix` が入れるツールをまとめて入れます。`vs upgrade` の外部ツール更新は、Homebrew がない環境では行われません。

## トラブルシューティング

| 症状 | 原因 | 解決策 |
|------|------|--------|
| `brew` が見つからない | Homebrew 未インストール | `vs doctor --fix` で自動インストール、または[https://brew.sh](https://brew.sh)を参照 |
| `npm` が見つからない | node 未インストール | `vs doctor --fix` で node をインストール後、再実行 |
| Xcode CLT のインストールが完了しない | GUI 承認が必要 | インストーラの完了後に `vs doctor --fix` を再実行 |
| `waifu2x` が Linux / Windows で自動インストールされない | macOS のみ対応 | 各ツールの公式サイトを参照して手動インストール |
| Google Fonts の SSL エラーが解消しない | 証明書パスが未反映 | シェルを再起動して `SSL_CERT_FILE` が有効になっているか確認 |

:::{.tip}
`vs doctor` は繰り返し実行できます。ツールを手動で導入したあとも、もう一度実行すれば正しく認識されているか確認できます。
:::
