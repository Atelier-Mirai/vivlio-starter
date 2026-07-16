# はじめての技術書づくり ～Vivlio Starter 実践ガイド～

「自分の本を作ってみたい」——そう思ったことはありませんか。日々の仕事で培った技術的な知見、趣味で深めた専門知識、あるいは誰かに伝えたい物語。Vivlio Starter は、Markdown で書いた原稿から高品質な PDF・EPUB を生成する書籍制作システムです。CSS 組版エンジン Vivliostyle をコアに据え、執筆から入稿に至るすべての工程を自動化します。

![Vivlio Starter ロゴ](docs/logos/vs_vivlio_starter_logo_outline.svg)

> **ブランドアイデンティティ**
> ロゴの緑は Markdown から始まる執筆の第一歩と継続的な成長を表し、青は CLI や CSS 組版が支える技術的信頼性と出力のゴールを象徴します。シンプルな操作で確かな技術に裏打ちされた書籍制作を提供するという Vivlio Starter のメッセージを表現しています。

## Vivlio Starter でできること

- **Markdown で執筆** — 使い慣れた記法でさくさく書ける。特別なフォーマットを覚える必要はありません
- **コマンド一発でビルド** — `vs build` ひとつで、原稿が美しい PDF に変わります
- **印刷入稿に対応** — トンボ・塗り足し付きの PDF を生成。印刷所にそのまま入稿できます
- **電子書籍も出力** — EPUB 形式での出力にも対応。電子出版の道も開かれています
- **テーマで簡単デザイン** — `book.yml` でアクセントカラーや扉絵を選ぶだけで、統一感あるデザインに
- **環境構築も自動** — `vs new` でプロジェクトを作成し、`vs doctor` で必要なツールを自動セットアップ

## 執筆ワークフロー

Vivlio Starter を使った書籍制作は、5つのステップで完結します。

| ステップ | 主なコマンド | 内容 |
| :--- | :--- | :--- |
| ① プロジェクト作成 | `vs new mybook` | 雛形生成＋必要ツール自動セットアップ |
| ② 執筆 | `vs create 10-intro` | 章ファイルを追加して Markdown で執筆 |
| | `vs build 10-intro` | 章単位で素早く確認 |
| ③ 整える | `vs lint` | 文章を校正（textlint） |
| | `vs metrics` | 原稿の統計を確認 |
| ④ ビルド | `vs build` | 書籍全体をビルド（カバー未生成時は自動生成） |
| ⑤ 入稿・配布 | — | 生成済みファイルを提出・アップロード |

②と③は何度でも繰り返せます。書いては整え、また書く——この往復が、読みやすい技術書を仕上げる近道です。

## クイックスタート

### 前提条件

- **Ruby**（CLI 実行に必要）
- **Node.js / npm**（Vivliostyle CLI や textlint に必要）

Ruby が未導入の場合は、同梱スクリプトで自動セットアップできます。

```bash
bin/install-ruby.zsh        # 対話モード
bin/install-ruby.zsh -y     # 無人モード
```

### インストール

```bash
gem install vivlio-starter
```

### プロジェクト作成からビルドまで

```bash
# 新しい書籍プロジェクトを作成
vs new mybook
cd mybook

# さっそく PDF を生成
vs build

# 生成された PDF を開く
vs open
```

`vs new` が内部で `vs doctor --fix` を自動的に呼び出し、Vivliostyle や ImageMagick など必要な外部ツールを一括でセットアップします。

### 新しい章を作る

```bash
vs create 10-awesome        # 章ファイルと画像ディレクトリを生成
vs build  10-awesome        # その章だけ素早くビルドして確認
```

すべての章を書き終わったら `vs build` で全体をビルドすれば、表紙・目次・索引・奥付まで揃った本が完成します。

## ディレクトリ構成

```
mybook/
  contents/          ← 原稿（Markdown ファイル）
  images/            ← 画像ファイル
  covers/            ← 表紙・裏表紙用の画像ファイル
  data/              ← QueryStream 用データ（YAML 形式）
  templates/         ← 各種雛形ファイル
  sources/           ← 執筆資料や PDF ファイル
  codes/             ← 書籍内で掲載するサンプルコード
  stylesheets/       ← CSS スタイルシート
  config/
    book.yml         ← 書籍の設定ファイル
    catalog.yml      ← 章構成
    page_presets.yml ← ページレイアウト設定
  Gemfile
  package.json
```

## コマンド一覧

```bash
vs --help
```

```
📚 Vivlio Starter - 技術書執筆のためのCLIツール 🛠️
使い方: vs <command> [options]

  プロジェクト管理:
    new              プロジェクトを新規作成します
    upgrade          プロジェクトを新しい雛形に追従させます（gem 更新後の取り込み）
    import           Re:VIEW Starter プロジェクトを取り込みます
    pdf:read         PDFを解析して Markdown 形式へ変換・抽出します
    doctor           環境診断と不足ツールの自動セットアップ
    clean            生成物やキャッシュを削除します

  執筆・編集支援:
    create           章ファイルと画像ディレクトリを生成します
    delete           指定した章の Markdown と画像を削除します
    rename           章の番号やファイル名（スラッグ）を変更します
    renumber         章番号を一括で付け直します

  文章校正・統計:
    lint             Markdownをtextlintで検査します
    metrics          Markdownの行数・文字数を集計します

  索引・用語集:
    index:auto       索引・用語集の候補を抽出し、確認用ファイルを作成します
    index:apply      確認済みの候補を、プロジェクトの索引辞書に登録・保存します

  画像・カバー:
    cover            表紙・裏表紙の画像を生成します（A4/B5/A5/EPUB対応）
    resize           images/画像をWebP形式に変換・最適化します

  ビルド・出力・プレビュー:
    build            書籍全体または指定章をビルドします
    open             生成されたPDFを開きます
    pdf:compress     生成済みPDFを圧縮します
```

まずはこの3つだけで十分です。

| コマンド | 用途 |
|---|---|
| `vs build` | PDF を生成する |
| `vs create` | 新しい章を作る |
| `vs delete` | 章を削除する |

各コマンドの詳細は `--help` オプションで確認できます。

```bash
vs build --help
vs create --help
```

### ログ出力レベル

```bash
vs build              # warn（既定: 警告・エラーのみ）
vs build --log        # info（おすすめ: 情報/成功/操作ログを含む）
vs build --log=debug  # debug（すべてのログを出力）
vs build --log=error  # error（エラーのみ）
```

## Vivlio Starter のしくみ

Vivlio Starter は、Vivliostyle をコアエンジンとして活用する独自ビルドシステムです。単なるラッパーではなく、執筆から入稿まで必要な処理の約半分を独自に担っています。

### 前処理（vivliostyle 呼び出し前）

- **QueryStream 展開**: `data/*.yml` のデータを `templates/` のテンプレートで自動展開
- **画像最適化**: WebP 変換・リサイズ（high/medium/low プリセット）
- **クロスリファレンス**: 図・表・コードリストへの参照を自動解決
- **フロントマター生成**: book.yml の設定を各章に自動反映
- **ソースコード読み込み**: `codes/` からコードを埋め込み、行番号を付与
- **脚注変換**: 外部リンクをページ脚注に自動変換
- **CSS 自動更新**: テーマカラー・スタイル・マーカー・ページ設定を動的生成
- **目次の自動生成**: `catalog.yml` に記載された各章の見出しを自動抽出

### 後処理（vivliostyle 呼び出し後）

- **重複バックリンク排除**: 生成済み PDF の named destinations からページマッピングを取得し、索引・用語集の重複リンクを浄化
- **PDF アウトライン付与**: HexaPDF により PDF にしおり（ブックマーク）を付与
- **表紙 PDF 結合**: frontcover/backcover を本文 PDF と結合
- **奥付の偶数ページ調整**: 奥付が必ず左ページ（偶数）に来るよう空白ページを自動挿入
- **PDF 圧縮**: Ghostscript による高品質圧縮
- **ファイルリネーム**: `mybook_v0.1.0.pdf` のようにプロジェクト名・バージョンを反映

### ビルド時間の内訳

```
vivliostyle 本体:      約 52%（PDF レンダリング）
vivlio-starter の処理: 約 48%（前処理・後処理）
```

## 設定（config/book.yml）

`config/book.yml` は、書籍情報・Vivliostyle・PDF の設定を一元管理します。

```yaml
book:
  main_title: 'はじめての技術書づくり'
  subtitle: 'Vivlio Starter 実践ガイド'
  author: アトリヱ未來
  language: ja
vivliostyle:
  reading_progression: ltr
pdf:
  output_file: output.pdf
  close_existing_windows: true
  window_bounds: '{3072, 0, 4096, 2160}'
```

## 追加ツールのインストール（PDF 操作）

一括ビルドで PDF のページ数取得・分割/結合を行うため、以下の CLI を利用します。`vs doctor --fix` で自動導入されますが、手動でインストールする場合は以下の通りです。

```bash
brew install poppler qpdf ghostscript imagemagick
```

| ツール | 用途 |
|---|---|
| pdfinfo（poppler） | PDF のメタ情報取得 |
| qpdf | PDF の分割・結合・ページ抽出 |
| Ghostscript | PDF 圧縮 |
| ImageMagick | 画像変換（WebP 等） |

### Vivliostyle CLI / VFM

`package.json` の devDependencies に `@vivliostyle/cli` と `vfm` を含めています。クリーン環境から始める場合:

```bash
npm install --save-dev @vivliostyle/cli vfm
```

## 出力形式

| 頒布先 | 使用するファイル | 設定 |
| :--- | :--- | :--- |
| 技術書典・コミケ（印刷所入稿） | `print_pdf`（トンボ付き） | `output.targets` |
| ダウンロード販売・PDF 配布 | `pdf`（閲覧用） | `output.targets` |
| BOOTH・Kindle 等（電子書籍） | `epub` | `output.targets` |

## ライセンス

[![License: CC BY-NC-SA 4.0](https://img.shields.io/badge/License-CC_BY--NC--SA_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-nc-sa/4.0/) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)

本リポジトリは「コード」と「書籍本文（コンテンツ）」でライセンスを分けています。

| 対象 | ライセンス | 詳細 |
|---|---|---|
| ソースコード | MIT | [LICENSE](./LICENSE) |
| 書籍本文（`contents/` 配下） | CC BY-NC-SA 4.0 | [CONTENT-LICENSE.md](./CONTENT-LICENSE.md) |
| サードパーティ | 各ライセンス | [THIRD-PARTY-LICENSES.md](./THIRD-PARTY-LICENSES.md) |

### vivlio-starter-pdf について

PDF しおり（アウトライン）付与など一部の高度な機能は、`vivlio-starter-pdf`（AGPL ライセンス）として分離されています。一般の著者の方はセットでのご利用をお勧めします。企業での自社製品への組み込みをお考えの場合は、本体（MIT）のみをご利用ください。

### 第三者ライセンス

本プロジェクトでは PDF/HTML 生成のために Vivliostyle CLI（AGPLv3）を利用しています。

- Vivliostyle ライセンス: https://www.gnu.org/licenses/agpl-3.0.html
- 第三者ライセンス一覧: [THIRD-PARTY-LICENSES.md](./THIRD-PARTY-LICENSES.md)

## 開発者向け情報

開発・コントリビューションに関しては [CONTRIBUTING.md](./CONTRIBUTING.md) を参照してください。

## Changelog

変更履歴は [CHANGELOG.md](./CHANGELOG.md) を参照してください。
