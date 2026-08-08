# 環境の診断と更新（vs doctor / vs upgrade）

:::{.chapter-lead}
Vivlio Starter の動作には、いくつかの外部ツールが必要です。`vs doctor` を使うと、必要なツールがすべて揃っているかを一括で確認でき、不足していれば `--fix` オプションで自動インストールできます。すでに動いている環境をまとめて最新へ引き上げるのは `vs upgrade` の担当です。この章では、環境を整える 2 つのコマンドを続けて解説します。
:::

## vs doctor とは

:::{.section-lead}
`vs doctor` は、Vivlio Starter が依存する外部ツールの存在を診断するコマンドです。ビルドや lint が突然失敗したとき、まず `vs doctor` を実行するのが近道です。
:::

新しい環境でプロジェクトを始めるときや、コマンドが予期せず失敗するときに実行してください。不足しているツールを一覧で確認できます。

なお、Vivlio Starter gem 自体のインストール手順や Ruby 環境の構築については、「インストール」の章を参照してください。

### 診断対象ツール

| ツール | 用途 |
|--------|------|
| Xcode Command Line Tools | macOS のビルドツールチェーン（macOS のみ） |
| node / npm | JavaScript ランタイム（Vivliostyle CLI の前提） |
| vivliostyle | PDF 生成エンジン |
| textlint | 文章校正ツール |
| qpdf | PDF 分割・結合・ページ操作 |
| pdfinfo (poppler) | PDF メタデータ取得 |
| pdftoppm (poppler) | PDF ページの画像化（OCR 用） |
| gs (Ghostscript) | PDF 圧縮 |
| imagemagick | 画像変換・リサイズ |
| inkscape | SVG ラスタライズの予備経路（任意） |
| rsvg-convert (librsvg) | EPUB 扉絵・節絵の合成画像ラスタライズ |
| vips (libvips) | 高速画像処理 |
| tesseract | OCR エンジン |
| tesseract 日本語データ | Tesseract の日本語学習データ |
| mecab | 索引機能の読み自動推測 |
| rouge | コードブロック言語推定（Ruby gem） |
| mathjax-full | 数式の SVG 化（npm パッケージ） |
| mermaid (mmdc) | ダイアグラムの画像化（npm パッケージ） |
| `waifu2x-ncnn-vulkan` | AI 画像拡大（オプション） |
| kindlepreviewer (Kindle Previewer 3) | Kindle（KPF）変換（任意・targets: kindle 用） |
| Google Fonts 用 SSL 証明書 | Google Fonts ダウンロード（macOS のみ） |

### 設定ファイルの診断

外部ツールに加えて、`vs doctor` はプロジェクト内の `config/` 配下の設定ファイルも診断します（書籍プロジェクト内で実行した場合のみ）。

- **必須設定ファイル**（`config/book.yml` / `config/catalog.yml`）が存在し、YAML として正しく読み込めるかを確認します。
- **任意設定ファイル**（textlint の設定や辞書ディレクトリなど）の有無を確認します。

すべて揃っていれば次のように表示されます。

```
✅ config/ 設定ファイル: OK
```

`--fix` を付けて実行すると、不足している設定ファイルや辞書を scaffold（`vs new` の雛形）から復元します。破損して読み込めない `book.yml` がある場合は、**壊れたファイルから復元できる値（書名・著者名など）を可能な限り救出**したうえで初期状態のテンプレートへ書き戻します。元の破損ファイルはバックアップが取得されるため、安心して復元できます。

## 基本的な使い方

:::{.section-lead}
`vs doctor` は診断のみ、`vs doctor --fix` は診断＋自動インストールです。まず診断だけ実行して状況を確認するのがおすすめです。
:::

### 診断のみ実行

```bash
vs doctor
```

不足しているツールを検出して一覧表示します。インストールは行いません。

```
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

### 自動インストール（--fix）

```bash
vs doctor --fix
```

診断後、不足しているツールを自動インストールします。macOS では Homebrew 経由でインストールします。Homebrew 自体や Xcode Command Line Tools が未インストールの場合は、インストール前に確認プロンプトが表示されます。

Node.js（node@20 優先）も自動インストールの対象です。vivliostyle や textlint など npm に依存するツールは、Node.js のインストール後に続けてインストールされます。

```
🛠 Homebrew による不足ツールのインストールを実行します…
🔁 インストール後の再診断…
✅ すべてのツールがインストールされました
```

### 確認プロンプトをスキップ（--yes）

```bash
vs doctor --fix --yes
```

`--yes`（または `-y`）は `--fix` と組み合わせて使うオプションです。Xcode Command Line Tools や Homebrew のインストール確認をスキップして、すべて自動で進めます。CI/CD 環境や自動セットアップスクリプトで活用できます。

## vs doctor のコマンドオプション

```
doctor [--fix] [--yes/-y] [-h/--help]
```

| オプション | 説明 |
|------------|------|
| `--fix` | 不足ツールを自動インストール（一部確認あり） |
| `--yes` / `-y` | 確認プロンプトをスキップ（`--fix` 指定時のみ有効） |
| `-h` / `--help` | ヘルプを表示 |

## 自動インストールの対応範囲

:::{.section-lead}
`--fix` による自動インストールは macOS + Homebrew 環境でのみ対応しています。Linux や Windows では手動セットアップが必要です。
:::

macOS では、ツールの種類に応じて 3 つの経路のいずれかで導入します。

| 導入経路 | ツール |
|------|------|
| `brew install` | node・qpdf・pdfinfo・pdftoppm・gs・imagemagick・inkscape・librsvg・vips・tesseract・mecab |
| `npm install -g` | vivliostyle・textlint と推奨ルール・mathjax-full・mermaid-cli |
| `gem install` | rouge |

npm 経由のものは node が前提です。node が未導入なら先に Homebrew で入れてから続けてインストールされるため、順番を気にする必要はありません。

この規則から外れるものが 4 つあります。

- **Xcode Command Line Tools**（`xcode-select --install`）と **Homebrew**（公式インストーラ）— 未導入なら、インストール前に確認プロンプトが出ます
- **textlint** — 日本語技術書向けのルールセットまで一括で導入し、設定ファイルも `config/` へ自動配置します
- **waifu2x-ncnn-vulkan** — Homebrew では配布されていないため、GitHub Releases から直接ダウンロードします
- **Kindle Previewer 3** — `brew install --cask kindle-previewer` に加えて起動用のラッパーを作ります。`targets: kindle` で Kindle 用ファイルを作るときだけ必要な任意ツールです

各ツールの詳細なインストール方法や最新の手順については、各ツールの公式サイトや最新のドキュメントを参照してください。ツールのバージョンや手順は変わることがあるため、公式情報や AI アシスタントで確認するのが確実です。

## vs upgrade — 環境をまとめて最新化する

:::{.section-lead}
`vs upgrade` は、執筆環境をまとめて最新化するコマンドです。プロジェクトの直下で 1 回実行するだけで、本体・雛形・外部ツールの 3 つを順に更新します。
:::

1. **vivlio-starter 本体の更新** — 新版が公開されていれば、確認のうえ `gem update vivlio-starter` を実行し、**新しい版で続きを自動実行**します（古い雛形で取り込んでしまい、更新後にもう一度やり直す二度手間がありません）
2. **プロジェクトの雛形追従** — バージョンアップで改良された雛形（スタイルシート・テンプレートなど）を既存プロジェクトへ取り込みます
3. **外部ツールの一括更新** — Homebrew（formula / cask）・npm・gem の複数系統に散らばる導入済みツールを、更新計画の確認後にまとめて最新版へ更新します

```bash
vs upgrade                    # 計画を提示 → 確認しながら適用
vs upgrade --dry-run          # 計画（何が追加/更新/競合か）の表示のみ
vs upgrade --yes              # 競合以外（追加＋未カスタムの更新）を確認なしで適用
vs upgrade --skip-self-update # 本体 gem の更新だけ行わない
```

不足ツールのインストールは更新後の再診断で自動的に行われるため、`vs doctor --fix` を別途実行する必要はありません。

### 雛形の追従

各ファイルは次のように分類され、計画表として提示されます。

| 分類 | 意味 | 動作 |
|------|------|------|
| 追加 | 雛形の新規ファイル | コピーします |
| 更新 | 雛形が改良・あなたは未変更 | 適用します（`--yes` で確認なし） |
| 競合 | 雛形もあなたも変更 | diff を提示し、1 件ずつ確認します（y/n/d） |
| 保持 | 著者データ領域 | **絶対に触りません** |

```
🔍 雛形との差分を確認しています…（gem 1.2.0 の雛形）
📋 更新計画:
   追加   stylesheets/talk.css
   更新   stylesheets/chapter-common.css
   競合   stylesheets/custom.css
   保持   config/book.yml
```

:::{.note}
**原稿と辞書は構造的に安全です**

`contents/`・`images/`・`covers/`・`codes/`・`data/` と、`book.yml`・`catalog.yml`・索引/用語集辞書・ユーザー辞書は「著者データ領域」として一律対象外です。upgrade がこれらを書き換えることはありません。さらに、上書きが起きるファイルは適用前に必ず `.cache/vs/upgrade-backup/` へ退避されるので、いつでも元に戻せます。
:::

「著者が触ったかどうか」の判定には、`vs new` が展開時に生成する `config/scaffold.lock`（雛形マニフェスト）を使います。自動生成ファイルなので手動編集せず、git にはコミットしてください。lock がない古いプロジェクトでも動作しますが、初回は差分のあるファイルがすべて「競合」として確認になります（適用後は lock が記録され、次回からスムーズになります）。

### 外部ツールの一括更新

雛形の追従に続けて、導入済み外部ツールの更新計画（どのツールを・どの版からどの版へ・どの系統で）が提示され、確認後にまとめて更新されます。

```
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

いくつかの補足があります。

- 不足しているツールのインストールもあわせて行われます（`vs doctor --fix` 相当）。更新後には診断を自動で再実行し、更新によってツールが壊れていないかまで確認します
- ツール単位で失敗しても処理は最後まで続行し、失敗したツールには手動での復旧コマンドを提示します
- node を更新するときは vivliostyle CLI も必ず同時に最新へ更新されます（バージョンの組み合わせによる不具合を避けるための連動規則です）
- Ruby 本体は自動更新の対象外です。新版が公開されている場合は、実行の末尾に「📣 お知らせ」としてお使いの導入経路（rbenv など）に合った更新手順を案内します
- ツール更新は macOS + Homebrew 環境のみ対応です。他の環境ではこのフェーズだけがスキップされます
- ネットワークに接続できない場合は、中途半端な更新を避けるため実行前に中断します

## vs doctor と vs upgrade の使い分け

2 つのコマンドは、医者にたとえると**`vs doctor` は健康診断、`vs upgrade` は治療・整備**です。答える問いが違います。

| | `vs doctor` | `vs upgrade` |
|------|------|------|
| 答える問い | 「いま何が壊れている？」 | 「全部新しくしたい」 |
| 性質 | 読み取り専用の診断（`--fix` で修復） | 環境を変更する更新 |
| ネットワーク | 不要（オフラインで動く） | 必要（gem / brew / npm へ照会） |
| 所要時間 | 数秒 | 数分 |
| 使いどころ | ビルドが突然失敗した・新しい環境を作る | 動いている環境の定期メンテナンス |

迷ったら次の一言で選べます。

- **調子が悪い・初めての環境** → `vs doctor`（必要なら `--fix`）
- **元気だけど新しくしたい** → `vs upgrade`

ビルドが失敗したとき、原因が分からないまま `vs upgrade` で最新化するのは、診断せずに手術するようなものです。バージョンが動くと問題の切り分けがかえって難しくなることもあるため、まず `vs doctor` で「何が壊れているか」を確認してから対処するのが近道です。

また、まっさらな Mac のセットアップは `vs doctor --fix` の専任領域です。Homebrew や Xcode Command Line Tools の導入確認から行えるのは doctor だけで、`vs upgrade` のツール更新は Homebrew がない環境ではスキップされます。

## 実行例

### 新しい Mac でセットアップする

```bash
# まず診断して何が必要か確認
vs doctor

# 不足ツールをまとめてインストール
vs doctor --fix
```

### CI/CD 環境でセットアップする

```bash
# 確認プロンプトをすべてスキップして自動インストール
vs doctor --fix --yes
```

### ビルドが失敗したときのトラブルシューティング

```bash
# 環境を診断して原因を特定
vs doctor
```

### ツールを定期的に最新へ保つ

```bash
# 更新計画を確認してから一括更新（本体 gem・雛形の追従もまとめて）
vs upgrade
```

## トラブルシューティング

| 症状 | 原因 | 解決策 |
|------|------|--------|
| `brew` が見つからない | Homebrew 未インストール | `vs doctor --fix` で自動インストール、または[https://brew.sh](https://brew.sh)を参照 |
| `npm` が見つからない | node 未インストール | `vs doctor --fix` で node をインストール後、再実行 |
| Xcode CLT のインストールが完了しない | GUI 承認が必要 | インストーラの完了後に `vs doctor --fix` を再実行 |
| `waifu2x` が Linux / Windows で自動インストールされない | macOS のみ対応 | 各ツールの公式サイトを参照して手動インストール |
| Google Fonts の SSL エラーが解消しない | 証明書パスが未反映 | シェルを再起動して `SSL_CERT_FILE` が有効になっているか確認 |

:::{.column}
**ヒント**  
`vs doctor` はいつでも何度でも実行できます。ツールを手動でインストールした後に再実行すれば、正しく認識されているか確認できます。
:::
