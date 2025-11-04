# はじめての技術書づくり ～Vivlio Starter 実践ガイド～

このリポジトリは、Thor ベースの CLI（`vs`/`vivlio-starter`）で電子書籍（Vivliostyle PDF）を生成するプロジェクトです。Markdown を前処理し、HTML 変換・差し替え・目次/章立て生成・PDF化・クリーンアップ・表示までを自動化します。

![Vivlio Starter ロゴ](dev-notes/vivlio_starter_logo.webp)

> **ブランドアイデンティティ**  
> ロゴの緑は Markdown から始まる執筆の第一歩と継続的な成長を表し、青は CLI や CSS 組版が支える技術的信頼性と出力のゴールを象徴します。シンプルな操作で確かな技術に裏打ちされた書籍制作を提供するという Vivlio Starter のメッセージを表現しています。

## 特長
Vivlio Starter は Markdown から HTMLに変換、CSS組版技術を用いて、電子書籍（Vivliostyle PDF）を生成します。
直感的な CLI コマンドでワンコマンドビルド（`vs build`）や、`config/book.yml` による一元的な設定管理、ファイルタイプに応じたスタイル適用（`<body class="preface|chapter|appendix|postface|colophon">`）など、便利な機能を提供します。

- 直感的な CLI コマンドでワンコマンドビルド（`vs build`）
- `config/book.yml` による一元的な設定管理
- ファイルタイプに応じたスタイル適用（`<body class="preface|chapter|appendix|postface|colophon">`）
- `vivliostyle.config.js` の自動生成（バックアップは最新版のみ保持）
- 冗長ログの統一制御（`--log[=level]`）

## 前提条件（依存関係）

- Node.js / npm（`npx vivliostyle` や textlint を使用）
- Ruby（CLI 実行）

必要に応じて以下をインストールしてください。
- Vivliostyle CLI は npx 経由で自動取得されます。
- Textlint は npm でグローバル導入するか、`vs doctor --fix` による自動導入を利用できます。
- Ruby の導入は同梱スクリプト `bin/install-ruby.zsh` が簡単・安全です（対話/無人どちらも可）。
  - 例: `bin/install-ruby.zsh`（対話）/ `bin/install-ruby.zsh -y`（無人）
  - 依存の自動診断/導入: `vs doctor --fix`

### 追加ツールのインストール（PDF 操作）

一括ビルドで PDF のページ数取得・分割/結合を行うため、以下の CLI を利用します。

- pdfinfo（poppler）: PDF のページ数などのメタ情報取得
- qpdf: PDF の分割・結合・ページ抽出（非破壊）
- Ghostscript: PDF 圧縮（サイズ削減）
- ImageMagick: 画像変換（WebP 等）

インストール（macOS/Homebrew）:

```bash
brew install poppler qpdf ghostscript imagemagick
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
gs -sDEVICE=pdfwrite -dPDFSETTINGS=/ebook -dCompatibilityLevel=1.7 \
   -dNOPAUSE -dQUIET -dBATCH -sOutputFile=output.compressed.pdf output.pdf
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
├─ contents/                # 章の Markdown 原稿（編集元）
├─ stylesheets/             # PDF 用 CSS
├─ bin/
│  └─ install-ruby.zsh      # Ruby の自動セットアップスクリプト（macOS）
├─ lib/                     # CLI/ロジック（Thor ベースの `vs`）
└─ README.md                # このファイル
```

### 主要コマンド（抜粋）

- ビルド: `vs build` / `vs build <chapter_id>`
- 文章校正: `vs text:lint` / `vs text:check`
- 表示: `vs open` / `vs open:pdf`
- 生成物削除: `vs clean`
- 章の作成/削除/変更: `vs create <id>` / `vs delete <id>` / `vs rename <old> <new>` / `vs renumber [<from> <to>]`
- Vivliostyle 設定生成: `vs vivliostyle:config`
- ヘルプ: `vs help` / `vs <cmd> --help`

## インストール（Gem/CLI）

本プロジェクトは Gem としても利用できます（CLI 同梱）。

```bash
# Bundler（推奨）
gem "vivlio-starter", "~> 0.6"

# または RubyGems から直接インストール
gem install vivlio-starter
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

- CLI は Thor ベースで、`vs`（または `vivlio-starter`）として利用できます。
- ログ出力は `--log[=level]` で制御できます（後述）。

## クイックスタート（プロジェクト生成）

```bash
# 新しい書籍プロジェクトを作成
vs new mybook

cd mybook

# 執筆開始（テンプレートの 02-preface.md を編集）
# Windsurf の場合
windsurf contents/02-preface.md
# （CLI 未設定の場合の代替）open -a "Windsurf" contents/02-preface.md
# VS Code の場合
code contents/02-preface.md

# 全ファイルビルド（PDF 生成まで一括）
vs build

# 生成された PDF を開く
vs open          # = vs open:pdf
```

ログ出力レベルを指定するには `--log[=level]` を使います。

```bash
# 既定（指定なし）: warn レベル（警告・エラーのみ）
vs build

# 標準（おすすめ）: info レベル（情報/成功/操作ログを含む）
vs build --log          # = --log=info と同義

# デバッグ: debug レベル（すべてのログを出力）
vs build --log=debug

# 最小: error レベル（エラーのみ）
vs build --log=error
```

## 主なコマンド

- ビルド
  - `vs build`
  - `vs build 02-preface`（特定章のみの関連処理）
- 表示
  - `vs open` / `vs open:pdf`
- 生成物削除
  - `vs clean`
- 章の管理
  - 新規作成: `vs create 21-history`
  - 削除: `vs delete 21-history`
  - リネーム: `vs rename 31-history 21-history`
  - 番号変更: `vs renumber 31 21`
  - 番号整列: `vs renumber`
- Vivliostyle 設定
  - 生成: `vs vivliostyle:config`
- タスク一覧/ヘルプ
  - `vs help` / `vs <cmd> --help`

## 設定（config/book.yml）

`config/book.yml` は、書籍情報・Vivliostyle・PDF の設定を保持します（抜粋）。

```yaml
book:
  main_title: 'はじめての技術書づくり'
  subtitle: 'Vivlio Starter 実践ガイド'
  author: アトリヱ未來
  
  language: ja
vivliostyle:
  reading_progression: ltr
  entries_file: entries.js
  config_file: vivliostyle.config.js
pdf:
  output_file: output.pdf
  close_existing_windows: true
  window_bounds: '{3072, 0, 4096, 2160}'
```

`vs vivliostyle:config` 実行時、既存の `vivliostyle.config.js` がある場合はバックアップを最新版 1 件のみ保持します。

## ビルドの流れ（開発者用）

`vs build` は概ね次の順で実行されます（内部処理の概要）。

1. 前処理
   - 画像パスの付与（例: `![](shogiban.png)` → `![](images/02-preface/shogiban.png)`）
   - フロントマターの生成（既存があれば併合）
   - ソースコードの取り込み
   - プロジェクトルートへ書き出し
2. 変換
   - vfm による Markdown → HTML 変換
   - `<body>` にファイルタイプクラスを付与
   - `_post_replace_list.yml` に基づく置換処理
   - Prism.js を用いたソースコードへの行番号追加
3. 目次/章立て
   - `toc.html` / `entries.js` を生成
4. PDF 生成
   - `vivliostyle build` により PDF 生成（圧縮を既定で実施、スキップ可）
5. クリーン/表示
   - 生成物のクリーンアップ
   - `vs open` で PDF を開く

### ログの冗長度（Logging）

- ログは `--log[=level]` で制御します。`level` は次のいずれかです。
  - `error` → レベル0（`log_error` のみ）
  - `warn` → レベル1（`log_warn` 以上）
  - `info` / `success` / `action` → レベル2（標準。`log_info`/`log_success`/`log_action` 以上）
  - `debug` → レベル3（`log_debug` を含む全ログ）
- `--log`（レベル省略）は `--log=info` と同義です。
- 既定（`--log` 未指定）は `warn` レベルです。

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

