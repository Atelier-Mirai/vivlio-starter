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

本リポジトリは「コード」と「書籍本文（コンテンツ）」でライセンスを分けています。

- コード（Rake タスク、スクリプト等）: MIT License
  - 詳細は `LICENSE` を参照してください。
- 本文（`content/` 配下の Markdown、画像・図版・イラスト等）: CC BY-NC-SA 4.0
  - 詳細は `LICENSE-content` を参照してください。
  - 商用利用は不可です。商用での利用については著作権者にお問い合わせください。
