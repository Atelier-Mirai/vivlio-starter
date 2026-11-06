# コマンド早見表

:::{.chapter-lead}
作業に合う `vs` コマンドを探し、使えるオプションを確かめるための早見表です。実行例や詳しい手順は「解説章」列からたどれます。`-h` / `--help` はすべてのコマンドで使えるため、個々の表では省きました。対象章を受け取るコマンドには、章番号（`21`）、範囲（`11-21`）、スラッグ（`markdown-tutorial`）を指定できます（@pageref:chapter-targets）。分冊の本では、`vs build`・`vs preflight`・`vs lint`・`vs metrics`・`vs cover` に巻の `id` も指定できます。
:::

### コマンド一覧

:::{.long-table}
| コマンド | 機能 | 解説章 |
|:---|:---|:---|
| `vs new` | プロジェクトを新規作成 | 新規プロジェクトの作成 |
| `vs upgrade` | 本体・雛形・外部ツールを最新化 | 環境の診断と更新 |
| `vs import` | Re:VIEW Starter の本を取り込み | Re:VIEW Starter からの移行 |
| `vs pdf:read` | PDF から Markdown を抽出 | PDF からの原稿の取り出し |
| `vs doctor` | ツールと設定ファイルを診断・修正 | 環境の診断と更新 |
| `vs config` | `config:` で始まるコマンドの一覧 | book.yml・catalog.yml リファレンス |
| `vs config:book` | `book.yml` の設定の説明と値 | book.yml・catalog.yml リファレンス |
| `vs config:catalog` | `catalog.yml` の書き方と章立て | book.yml・catalog.yml リファレンス |
| `vs config:talk` | `talk.yml` の書き方と話者 | 拡張記法リファレンス |
| `vs clean` | 生成物やキャッシュを削除 | 補助コマンドとカスタマイズ |
| `vs create` | 章を作成 | 章の管理 |
| `vs delete` | 章を削除 | 章の管理 |
| `vs rename` | 章の番号やスラッグを変更 | 章の管理 |
| `vs renumber` | 章番号を一括で付け直す | 章の管理 |
| `vs lint` | 原稿の日本語と英単語の綴りを検査 | 文章校正 |
| `vs metrics` | 行数・文字数などを集計 | 原稿の分量と難度の計測 |
| `vs index` | `index:` で始まるコマンドの一覧 | 索引・用語集機能 |
| `vs index:plan` | 索引語数の目安と登録の状況を表示 | 索引・用語集機能 |
| `vs index:auto` | 索引語の候補を抽出 | 索引・用語集機能 |
| `vs index:apply` | レビュー結果を辞書に登録 | 索引・用語集機能 |
| `vs index:export` | 用語集の説明文などを書き出し | 索引・用語集機能 |
| `vs index:import` | 書き出したライブラリを取り込み | 索引・用語集機能 |
| `vs cover` | 表紙・裏表紙の画像を生成 | カバー画像の生成 |
| `vs preflight` | ビルド前に原稿のエラーを検査 | ビルド |
| `vs build` | 書籍全体または指定章をビルド | ビルド |
| `vs open` | 生成した PDF を開く（macOS 専用） | 補助コマンドとカスタマイズ |
| `vs pdf:compress` | 生成した PDF を圧縮 | 補助コマンドとカスタマイズ |
| `vs pdf:pages` | PDF のページを JPEG に切り出し | 補助コマンドとカスタマイズ |
:::

グローバルオプション: `-h` / `--help`（ヘルプ）・`--version`（バージョン表示）。

## プロジェクト管理

### `vs new` — プロジェクトの新規作成

`vs new <プロジェクト名>`

### `vs upgrade` — 本体・雛形・ツールの一括更新

`vs upgrade [オプション]`

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| `--dry-run` | 計画（追加・更新・合流・競合）を表示するだけで、何も変更しない |
:::

### `vs import` — Re:VIEW Starter からの移行

`vs import <プロジェクトのディレクトリ>`（`catalog.yml` に載っている章を取り込む）

### `vs pdf:read` — PDF から Markdown を抽出

`vs pdf:read <PDF> [<章の名前>] [オプション]`（PDF は `sources/` の中のファイル名、または `/` を含むパス）

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| `--pages <範囲>` | 読むページ（`12-30`・`31-48,52`・`-11`・`238-`）。章の名前を添える |
| `--force` | 同じ章がすでにあれば、読み直して置き換える |
| `--log` | ページ数などの経過を表示する（`--log=debug` で詳細） |
:::

### `vs doctor` — 環境の診断と修正

`vs doctor [オプション]`

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| `--fix` | 診断で見つかった問題を修正する（ツールのインストール・設定ファイルの復元） |
:::

### `vs config` — 設定の書き方を調べる

`vs config`（設定の書き方を調べるコマンドの一覧を表示する）

`vs config:book [区分 / キー / 探す言葉]`（省略すると区分の一覧。キーを指定すると、説明と今の値を表示する）

`vs config:catalog`（`catalog.yml` の書き方と、この本の章立てを表示する）

`vs config:talk [display: のキー / 探す言葉]`（省略すると `talk.yml` の書き方と、この本の話者を表示する）

### `vs clean` — 生成物・キャッシュの削除

`vs clean [オプション]`

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| （なし） | キャッシュ（`.cache/`）を削除する |
| `--purge` / `-P` | キャッシュと、プロジェクト直下の生成物（PDF・EPUB など）を削除する |
| `--index-dictionaries` | 索引・用語集の辞書だけを削除する（確認あり） |
:::

## 執筆・編集支援

### `vs create` — 章の作成

`vs create <章>`（例: `vs create 11-intro`。番号を省くと最後の章の次に作る。複数可）

### `vs delete` — 章の削除

`vs delete <対象章>`（削除の前に確認を求める）

### `vs rename` / `vs renumber` — 章番号・スラッグの変更

`vs rename <旧> <新>`（章の番号やスラッグを変更する）

`vs renumber [--step <n>]`（章番号を一括で付け直す。`--step` / `-s` は番号の刻み幅で、既定は 1）

## 文章校正・統計

### `vs lint` — 文章校正

`vs lint [対象章]`（省略時は `catalog.yml` の全章）

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| `--fix` | 自動修正可能なエラーを修正する |
| `--register` | スペルチェックの未知語をユーザー辞書へ一括登録する |
:::

### `vs metrics` — 文章メトリクス

`vs metrics [対象章]`（省略時は全章の概要。章を指定すると節まで表示する）

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| `--sections` | 全章を節まで展開する |
| `--warn` | 警告がある章のみ節まで展開する |
:::

## 索引・用語集

### `vs index` — 索引・用語集のコマンド

`vs index`（`index:` で始まるコマンドの一覧と、作業の流れを表示する）

`vs index:plan [対象章]`（索引語数の目安と登録の状況を表示する。辞書もレビューファイルも変更しない）

`vs index:auto [対象章]`（索引・用語集の候補を抽出し、レビューファイルを作る）

`vs index:apply`（レビュー結果を `config/index_glossary_terms.yml` に登録する）

`vs index:export [パス]`（用語集の説明文・棄却した語・読みの補正を書き出す。省略時は `index_library.yml`）

`vs index:import [パス]`（書き出したファイルを取り込む。追記だけで、この本の辞書にある語は変えない）

## 画像・カバー

### `vs cover` — カバー画像の生成

`vs cover [巻]`（判型は `book.yml` の `page.use`、形式は `output.targets` に従う。分冊の本は巻の `id`、全巻なら `all`）

## ビルド・出力・プレビュー

### `vs preflight` — ビルド前チェック

`vs preflight [対象章]`（省略時は全章）

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| `--verify-links` | 外部 URL の到達性も確かめる |
| `--log <level>` | 表示するログの水準を指定する（`error` / `warn` / `info` / `debug`） |
:::

### `vs build` — 書籍のビルド

`vs build [対象章]`（省略時は書籍全体。分冊の本は巻の `id`、全巻なら `all`。`.md` ファイルの直接指定は @pageref:direct-build）

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| `--compress`<br>`--no-compress` | その回だけ PDF を圧縮する / しない |
| `--verify-links` | 外部 URL の到達性を確かめる |
| `--theme <color>` | テーマカラーを指定する（`.md` ファイルを直接ビルドするときだけ） |
| `--log <level>` | 表示するログの水準を指定する（`error` / `warn` / `info` / `debug`） |
:::

### `vs open` — PDF を開く（macOS 専用）

`vs open [ファイル名]`（拡張子 `.pdf` は省略可。省略時は本全体の閲覧用 PDF）

### `vs pdf:compress` — PDF の圧縮

`vs pdf:compress [入力PDF] [出力PDF]`（入力の省略時は本全体の閲覧用 PDF。出力の省略時は、入力名に `_compressed` を付けた名前）

### `vs pdf:pages` — ページの JPEG 切り出し

`vs pdf:pages [入力PDF] [オプション]`（入力の省略時は本全体の閲覧用 PDF）

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| `--dpi <値>` | 解像度（既定: 350） |
| `--quality <値>` | JPEG 品質 1〜100（既定: 95） |
| `--pages <指定>` | ページ指定（例: `1,3,5-8`） |
| `--output <dir>` | 出力ディレクトリ（既定: `<basename>_images`） |
:::
