# 電気・電子技術への招待 ～古代の叡智から現代AIまで～

このリポジトリは、Rake ベースのビルドシステムで電子書籍（Vivliostyle PDF）を生成するプロジェクトです。Markdown を前処理し、HTML 変換・差し替え・目次/章立て生成・PDF化・クリーンアップ・表示までを自動化します。

## 特長

- 直感的な Rake タスクでワンコマンドビルド（`rake build`）
- `config/book.yml` による一元的な設定管理
- ファイルタイプに応じたスタイル適用（`<body class="preface|chapter|appendix|postface|colophon">`）
- `vivliostyle.config.js` の自動生成（バックアップは最新版のみ保持）
- 冗長ログの統一制御（`-v` または `VERBOSE=1`）

## 前提条件（依存関係）

- Node.js / npm（`npx vivliostyle` を使用）
- Ruby（Rake 実行）

必要に応じて以下をインストールしてください。
- Vivliostyle CLI は npx 経由で自動取得されます。

### 追加ツールのインストール（PDF 操作）

一括ビルドで PDF のページ数取得・分割/結合を行うため、以下の CLI を利用します。

- pdfinfo（poppler）: PDF のページ数などのメタ情報取得
- qpdf: PDF の分割・結合・ページ抽出（非破壊）
 - Ghostscript: PDF 圧縮（サイズ削減）

インストール（macOS/Homebrew）:

```bash
brew install poppler qpdf ghostscript
```

動作確認:

```bash
pdfinfo -v      # バージョン表示
qpdf --version  # バージョン表示
gs --version    # Ghostscript のバージョン表示
```

補足:

- CI でも `brew install poppler qpdf ghostscript`（または Linux なら `apt-get install poppler-utils qpdf ghostscript`）で導入可能です。
- どちらもビルド時に外部コマンドとして呼び出すのみで、プロジェクトのライセンスには影響しません。

Ghostscript による簡易圧縮例:

```bash
# 画質とサイズのバランス例（/ebook は可読性を保ちつつ縮小）
gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 \
   -dPDFSETTINGS=/ebook -dNOPAUSE -dQUIET -dBATCH \
   -sOutputFile=output.compressed.pdf output.pdf

# より高画質にしたい場合は /prepress、もっと小さくしたい場合は /screen を検討
# /default, /screen, /ebook, /printer, /prepress
```

### Vivliostyle CLI / VFM の導入

本プロジェクトでは、`package.json` の devDependencies に以下を含めています。

- `@vivliostyle/cli`（Vivliostyle CLI）
- `vfm`（Vivliostyle Flavored Markdown）

クリーン環境から始める場合の導入例（任意のパッケージマネージャで可）:

```bash
# npm
npm install --save-dev @vivliostyle/cli vfm

# yarn
yarn add -D @vivliostyle/cli vfm

# pnpm
pnpm add -D @vivliostyle/cli vfm
```

バージョン確認（package.json の scripts を利用）:

```bash
npm run viv:version  # Vivliostyle CLI のバージョン
npm run vfm:version  # VFM のバージョン
```

PDF ビルド（scripts 経由）:

```bash
npm run build:pdf            # vivliostyle build -c vivliostyle.config.js
npm run build:pdf:verbose    # 追加ログ付き
```

備考:

- ローカルにインストール済みの CLI は `npx vivliostyle` / `npx vfm` でも呼び出せます。
- Vivliostyle CLI のバージョンは `package.json` に固定しており、CI/他環境でも同一結果を狙います。

## ディレクトリ構成（抜粋）

```
project/
├─ config/
│  └─ book.yml              # 書籍の設定（タイトル、著者、vivliostyle、pdf など）
├─ content/                 # 章の Markdown 原稿（編集元）
├─ stylesheets/             # PDF 用 CSS
├─ rakelib/                 # Rake タスク群
│  ├─ common.rb             # 共通処理・設定・ログ
│  ├─ options.rb            # オプション解析
│  ├─ pre_process.rake      # 前処理（画像パス付与・フロントマター生成・コード取り込み）
│  ├─ convert.rake          # HTML 変換と置換（vfm -> html, post-replace）
│  ├─ post_process.rake     # HTML ポスト置換
│  ├─ prism_lines.rake      # Prism.js 行番号付与
│  ├─ toc.rake              # 目次（toc.html）生成
│  ├─ entries.rake          # 章立て（entries.js）生成
│  ├─ pdf.rake              # PDF 生成・PDF を開く（open:pdf, エイリアス: open）
│  ├─ clean.rake            # 生成物クリーンアップ
│  ├─ build.rake            # 一括ビルド
│  ├─ create.rake           # 新規章の作成
│  ├─ delete.rake           # 章の削除
│  ├─ renumber.rake         # 章番号の変更・整列
│  └─ vivliostyle.rake      # vivliostyle.config.js 生成/差分
├─ Rakefile                 # エントリポイント
└─ README.md                # このファイル
```

## インストール（Gem/CLI）

本プロジェクトは Gem としても利用できます（CLI 同梱）。

```bash
# Bundler（推奨）
gem "vivlio-starter", "~> 0.1"

# またはローカル .gem を直接インストール
gem install ./vivlio-starter-0.1.0.gem
```

CLI は以下の 2 つのコマンド名で呼び出せます（同等）。

- `vivlio-starter ...`
- `vs ...`（省略形）

主な使い方:

```bash
# タスク一覧（ヘルプ）
vs help

# 一括ビルド（PDF まで）
vs build

# 生成物クリーンアップ
vs clean

# PDF を開く
vs open
```

備考:

- CLI は内部で `Rakefile`/`rakelib/` をロードし、`rake` と同じタスクを提供します。
- `VERBOSE=1` または `-v` で詳細ログを出せます（例: `vs build -v`）。

## クイックスタート

```bash
# 初期化（必要ファイルの雛形など）
rake init

# 全ファイルビルド（PDF 生成まで一括）
rake build

# 生成された PDF を開く
rake open        # または rake open:pdf
```

冗長ログを見たい場合は `-v` もしくは環境変数を利用します。

```bash
rake build -v
VERBOSE=1 rake build
```

## 主なコマンド

- 初期化
  - `rake init`
- ビルド
  - `rake build`
  - `rake build 02-preface`（特定章のみの関連処理）
- 表示
  - `rake open` / `rake open:pdf`
- 生成物削除
  - `rake clean`
- 章の管理
  - 新規作成: `rake create 21-history`
  - 削除: `rake delete 21-history`
  - 番号変更: `rake renumber 31 21`
  - 番号整列: `rake renumber`
- Vivliostyle 設定
  - 生成: `rake vivliostyle:generate_config`（短縮: `rake vs:config`）
- タスク一覧
  - `rake -T` / `rake --tasks` / `rake help`

## 設定（config/book.yml）

`config/book.yml` は、書籍情報・Vivliostyle・PDF の設定を保持します（抜粋）。

```yaml
book:
  title: 電気・電子技術への招待 ～古代の叡智から現代AIまで～
  author: アトリヱ未來
  
  language: ja
vivliostyle:
  reading_progression: ltr
  entries_file: entries.js
  config_file: vivliostyle.config.js
  image: ghcr.io/vivliostyle/cli:9.5.0
pdf:
  output_file: output.pdf
  close_existing_windows: true
  window_bounds: '{3072, 0, 4096, 2160}'
```

`vivliostyle:generate_config` 実行時、既存の `vivliostyle.config.js` がある場合はバックアップを最新版 1 件のみ保持します。

## ビルドの流れ（開発者用）

`rake build` は概ね次の順で実行されます。

1. preprocess.rake
   - 画像パスの付与（例: `![](shogiban.png)` → `![](images/02-preface/shogiban.png)`）
   - フロントマターの生成（既存があれば併合）
   - ソースコードの取り込み
   - プロジェクトルートへ書き出し
2. convert.rake
   - vfm による Markdown → HTML 変換
   - `<body>` にファイルタイプクラスを付与
   - `_post_replace_list.yml` に基づく置換処理
   - Prism.js を用いたソースコードへの行番号追加
3. toc.rake
   - `toc.html` を生成
4. entries.rake
   - `entries.js` を生成
5. pdf.rake
   - `npx vivliostyle build` により PDF 生成
6. clean.rake
   - 生成した PDF 以外の生成物をクリーンアップ
7. pdf.rake
   - `rake open`（=`open:pdf`）で PDF を開く

### ログの冗長度（Verbose）

- `BookBuild.verbose?` により統一制御
- `rake ... -v` または `VERBOSE=1 rake ...` で詳細ログが出ます

## ライセンス

[![License: CC BY-NC-SA 4.0](https://img.shields.io/badge/License-CC_BY--NC--SA_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-nc-sa/4.0/) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)

以下のライセンス文書を参照してください：

- コードのライセンス: [LICENSE](./LICENSE)
- コンテンツのライセンス: [CONTENT-LICENSE.md](./CONTENT-LICENSE.md)
- サードパーティ: [THIRD-PARTY-LICENSES.md](./THIRD-PARTY-LICENSES.md)

本リポジトリは「コード」と「書籍本文（コンテンツ）」でライセンスを分けています。

### ライセンス(コード)
このリポジトリのビルド用スクリプトなどのソースコードは MIT ライセンスです。

- ライセンス本文: [LICENSE](./LICENSE)

### ライセンス(コンテンツ)
本文（`content/` 配下の Markdown、画像・図版・イラスト等）は CC BY-NC-SA 4.0 です（商用利用不可）。

- ライセンス本文: [CONTENT-LICENSE.md](./CONTENT-LICENSE.md)
- クリエイティブ・コモンズ: https://creativecommons.org/licenses/by-nc-sa/4.0/

### 第三者ライセンス（Third-Party Licenses）

本プロジェクトでは PDF/HTML 生成のために Vivliostyle CLI（AGPLv3）を利用しています。

- Vivliostyle ライセンス: https://www.gnu.org/licenses/agpl-3.0.html
- 第三者ライセンス一覧: [THIRD-PARTY-LICENSES.md](./THIRD-PARTY-LICENSES.md)

## リリース手順（RubyGems）

Gem を公開・更新する手順です。

1. バージョン更新
   - `lib/vivlio/starter/version.rb` の `VERSION` を更新
   - CHANGELOG（必要に応じて）更新

2. ビルド
   ```bash
   gem build vivlio-starter.gemspec
   ls *.gem  # 生成物を確認
   ```

3. 公開（RubyGems）
   ```bash
   gem push vivlio-starter-<VERSION>.gem
   ```

4. Git タグ（任意）
   ```bash
   git commit -am "release: v<VERSION>"
   git tag v<VERSION>
   git push --tags
   ```

5. 利用側更新（Bundler）
   - `Gemfile` で `gem "vivlio-starter", "~> <MAJOR>.<MINOR>"` を指定
   - `bundle update vivlio-starter`

## Changelog

変更履歴は `CHANGELOG.md` を参照してください。

