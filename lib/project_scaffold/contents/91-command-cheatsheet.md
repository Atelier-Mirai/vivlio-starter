# コマンド早見表

:::{.chapter-lead}
`vs` の全コマンドとオプションを一覧できる早見表です。詳しい使い方と実行例は「解説章」列の章を参照してください。`-h` / `--help` は全コマンド共通のため、各表からは省いています。対象章を取るコマンドは、章番号（`21`）・範囲（`11-21`）・スラッグ（`21-markdown`）のいずれでも指定できます。
:::

### コマンド一覧

:::{.long-table}
| コマンド | 機能 | 解説章 |
|:---|:---|:---|
| `vs new` | プロジェクトを新規作成 | 新規プロジェクトの作成 |
| `vs upgrade` | 本体 gem・雛形・外部ツールをまとめて最新化 | 環境診断（vs doctor） |
| `vs import` | Re:VIEW Starter プロジェクトを取り込み | Import コマンドの使い方 |
| `vs pdf:read` | PDF を解析して Markdown へ変換・抽出 | PDF 読み取りコマンドの使い方 |
| `vs doctor` | 環境診断と不足ツールの自動セットアップ | 環境診断（vs doctor） |
| `vs clean` | 生成物やキャッシュを削除 | ユーティリティ・コマンド集 |
| `vs create` | 章ファイルと画像ディレクトリを生成 | 章の管理 |
| `vs delete` | 指定した章の Markdown と画像を削除 | 章の管理 |
| `vs rename` | 章の番号やスラッグを変更 | 章の管理 |
| `vs renumber` | 章番号を一括で付け直す（rename の別名） | 章の管理 |
| `vs lint` | Markdown を textlint・スペルチェックで検査 | 文章校正（vs lint） |
| `vs metrics` | 行数・文字数など文章メトリクスを集計 | Metrics |
| `vs index:auto` | 索引・用語集の候補を抽出しレビュー用ファイルを生成 | 索引・用語集機能 |
| `vs index:apply` | レビュー結果を索引辞書に登録・保存 | 索引・用語集機能 |
| `vs cover` | 表紙・裏表紙の画像を生成（A4/B5/A5/EPUB） | カバー画像の生成 |
| `vs resize` | images/ の画像を WebP に変換・最適化 | ユーティリティ・コマンド集 |
| `vs preflight` | ビルド前の原稿エラーチェックを高速実行 | ビルド（vs build） |
| `vs build` | 書籍全体または指定章をビルド | ビルド（vs build） |
| `vs open` | 生成された PDF を開く（macOS 専用） | ユーティリティ・コマンド集 |
| `vs pdf:compress` | 生成済み PDF を圧縮 | ユーティリティ・コマンド集 |
| `vs pdf:pages` | PDF をページ単位で JPEG 画像に切り出し | ビルド（vs build） |
| `vs pdf:rasterize` | PDF をラスタライズして再結合（Type3 フォント対策） | ビルド（vs build） |
:::

グローバルオプション: `-h` / `--help`（ヘルプ）・`-v` / `--verbose`（冗長出力）・`--version`（バージョン表示）。

## プロジェクト管理

### `vs new` — プロジェクトの新規作成

`vs new <プロジェクト名> [オプション]`

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| `--yes` / `-y` | 対話をスキップしデフォルト設定で作成する |
| `--add-missing` | 既存ディレクトリに不足ファイルだけを追加する（既存は保持） |
| `--log <level>` | ログレベル（`debug` など） |
:::

### `vs upgrade` — 本体・雛形・ツールの一括更新

`vs upgrade [オプション]`

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| `--dry-run` | 計画（何が追加/更新/競合か）の表示のみで書き込みしない |
| `--yes` / `-y` | 競合以外（追加＋未カスタムの更新）を確認なしで適用する |
| `--skip-self-update` | vivlio-starter 本体の gem 更新を行わない |
:::

### `vs import` — Re:VIEW Starter からの移行

`vs import <プロジェクトのディレクトリ> [オプション]`

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| `--force` | 確認プロンプトをスキップして実行する |
:::

### `vs pdf:read` — PDF から Markdown を抽出

`vs pdf:read <FILE>`（FILE は章トークン `01-foo` または PDF ファイルパス）

### `vs doctor` — 環境診断とセットアップ

`vs doctor [オプション]`

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| `--fix` | 不足ツールを自動インストールする（一部確認あり） |
| `--yes` / `-y` | 確認プロンプトをスキップする（`--fix` 指定時のみ有効） |
:::

### `vs clean` — 生成物・キャッシュの削除

`vs clean [オプション]`

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| `--purge` / `-P` | 生成物（PDF 含む）をすべて削除する |
| `--cache` / `-C` | キャッシュのみを削除する |
| `--cover` | 生成されたカバー画像のみを削除する |
| `--generated-images` | 生成された扉絵/装飾などの画像を削除する |
| `--index-dictionaries` | 索引・用語集辞書データを削除する（確認あり） |
| `--all` | `--index-dictionaries` を除くすべての削除オプションをまとめて実行する |
:::

## 執筆・編集支援

### `vs create` — 章の作成

`vs create <章スラッグ>`（複数可。例: `vs create 30-tips`）

### `vs delete` — 章の削除

`vs delete <対象>`（章番号 / 範囲 / ファイル名）

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| `--force` / `-f` | 確認なしで削除を実行する（`--yes` / `-y` は互換の別名） |
| `--verbose` / `-v` | 冗長ログを表示する |
:::

### `vs rename` / `vs renumber` — 章番号・スラッグの変更

`vs rename <旧> <新>`（省略すると一括連番モード。`renumber` は別名）

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| `--force` / `-f` / `-y` | 確認なしで変更を実行する |
| `--step <n>` / `-s <n>` | 章番号の刻み幅を指定する（既定: 1） |
:::

## 文章校正・統計

### `vs lint` — 文章校正

`vs lint [対象ファイル]`（省略時は全 Markdown。章番号 `91 93` や範囲 `11-21` も可）

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| `--fix` | 自動修正可能なエラーを修正する |
| `--textlint-only` | 日本語校正（textlint）のみ実行する |
| `--spellcheck-only` | スペルチェックのみ実行する |
| `--register` | スペルチェックの未知語を `config/user_words.txt` へ一括登録する（textlint は実行しない） |
:::

### `vs metrics` — 文章メトリクス

`vs metrics [対象章]`（省略時は全章の概要。`2`・`1,3,5`・`1-3,5,8-10` のような指定が可能）

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| `--all` | 解析結果＋推敲用の参考資料も表示する |
| `--sections` | 全章を節まで展開する |
| `--warn` | 警告がある章のみ節まで展開する |
| `--json` / `--yaml` | JSON / YAML 形式で出力する（参考資料を含む） |
:::

## 索引・用語集

### `vs index:auto` — 候補の抽出

`vs index:auto [対象ファイル]`（省略時は全章。候補を抽出・分類し `_index_review.md` を生成）

### `vs index:apply` — 辞書への登録

`vs index:apply`（レビュー結果を `index_glossary_terms.yml` に適用）

どちらも `--verbose` / `-v` で詳細出力になります。

## 画像・カバー

### `vs cover` — カバー画像の生成

`vs cover [対象]`（`auto` / `a4` / `b5` / `a5` / `epub`。既定: `auto`）

### `vs resize` — 画像の WebP 変換

`vs resize [ディレクトリ]`（省略時は `images/` 全体。`vs resize 01-intro` のように章だけも可）

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| `--force` / `-f` | 既存ファイルも強制再生成する |
| `--high` / `--low` | 高品質 / 軽量品質プリセットを使う |
| `--delete-originals` | 変換後に元の PNG/JPG ファイルを削除する（確認あり） |
:::

## ビルド・出力・プレビュー

### `vs preflight` — ビルド前チェック

`vs preflight [対象章]`（省略時は全章。エラー 1 件以上で終了コード 1）

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| `--no-resize` | 画像最適化をスキップする（既定: 実行） |
| `--no-verify` | リンク・画像の基本検証をスキップする（既定: 実行） |
| `--verify-links` | 外部 URL の HTTP 到達性チェックも実行する |
| `--log <level>` | ログレベルを指定する（`error` / `warn` / `info` / `debug`） |
:::

### `vs build` — 書籍のビルド

`vs build [対象章]`（省略時は書籍全体。章番号 / 範囲 / ベース名で単章・部分ビルド）

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| `--no-resize` | 画像最適化をスキップする（既定: 実行） |
| `--high` / `--medium` / `--low` | 画像最適化の品質プリセット |
| `--no-compress` | PDF 圧縮をスキップする |
| `--no-clean` | 中間生成物のクリーンアップをスキップする（既定: 実行） |
| `--no-verify` | リンク・画像の基本検証をスキップする（既定: 実行） |
| `--verify-links` | 外部 URL の HTTP 到達性チェックも実行する |
| `--log <level>` | ログレベルを指定する（`error` / `warn` / `info` / `debug`） |
:::

### `vs open` — PDF を開く（macOS 専用）

`vs open [ファイル名]`（拡張子 `.pdf` は省略可。省略時はビルド生成物を自動選択し、プロジェクトルート → `sources/` の順で探索）

### `vs pdf:compress` — PDF の圧縮

`vs pdf:compress [入力PDF] [出力PDF]`（省略時: `output/book.pdf` → `output/book_compressed.pdf`）

### `vs pdf:pages` — ページの JPEG 切り出し

`vs pdf:pages <入力PDF> [オプション]`（入力省略時はビルド生成物）

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| `--dpi <値>` | 解像度（既定: 350） |
| `--quality <値>` | JPEG 品質 1〜100（既定: 95） |
| `--pages <指定>` | ページ指定（例: `1,3,5-8`） |
| `--output <dir>` | 出力ディレクトリ（既定: `<basename>_images`） |
:::

### `vs pdf:rasterize` — PDF のラスタライズ再結合

`vs pdf:rasterize <入力PDF> [オプション]`（Type3 フォント対策。入力省略時はビルド生成物）

:::{.long-table}
| オプション | 説明 |
|:---|:---|
| `--dpi <値>` | 解像度（既定: 350） |
| `--quality <値>` | JPEG 品質 1〜100（既定: 95） |
| `--clean` | 中間 JPEG を処理後に削除する |
:::
