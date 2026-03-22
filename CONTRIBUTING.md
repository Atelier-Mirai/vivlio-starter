# Contributing to Vivlio Starter

Vivlio Starter へのコントリビューションをありがとうございます！このガイドでは、開発環境のセットアップからコントリビューション方法までを説明します。

## 開発環境

### 必要なツール
- Ruby 3.0+
- Bundler
- Git

### セットアップ
```bash
# リポジトリをクローン
git clone https://github.com/your-org/vivlio-starter.git
cd vivlio-starter

# 依存関係をインストール
bundle install

# 開発用タスクを確認
bundle exec rake -T
```

## テスト

```bash
# 全テスト実行
bundle exec rake test

# 特定のテスト
bundle exec ruby test/vivlio/starter/cli/build_test.rb
```

## コミットメッセージ

Conventional Commits を推奨します：
- `feat:` 新機能
- `fix:` バグ修正
- `docs:` ドキュメント更新
- `style:` コードスタイル
- `refactor:` リファクタリング
- `test:` テスト関連

## プルリクエスト

1. Fork して機能ブランチを作成
2. テストを追加・実行
3. プルリクエストを送信

---

## 開発者向け情報

### リリース手順（RubyGems）

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

### ローカル開発

#### ローカル gem のテスト
```bash
# ローカルで gem をビルド
gem build vivlio-starter.gemspec

# ローカル gem をインストールしてテスト
gem install vivlio-starter-<VERSION>.gem
```

#### scaffold のテスト
```bash
# テスト用プロジェクトを生成
bundle exec exe/vs new test-project

# 生成されたプロジェクトでテスト
cd test-project
vs build
```

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

- ログは `--log=level` で制御します。`level` は次のいずれかです。
  - `error` → レベル0（`log_error` のみ）
  - `warn` → レベル1（`log_warn` 以上）
  - `info` / `success` / `action` → レベル2（標準。`log_info`/`log_success`/`log_action` 以上）
  - `debug` → レベル3（`log_debug` を含む全ログ）
- `--log`（レベル省略）は `--log=info` と同義です。
- 既定（`--log` 未指定）は `warn` レベルです。

## アーキテクチャ概要

Vivlio Starter は Vivliostyle を（かなり厚く）ラップした電子書籍執筆のための Ruby Gem です。Ruby 4.0 以降を前提として、Samovar ベースで開発されています。

### ディレクトリ構造の役割

```yml
# ========================================
# ディレクトリ設定
# ========================================
directories:
  contents: 'contents'        # Markdownファイル
  stylesheets: 'stylesheets' # CSSファイル
  images: 'images'           # 画像ファイル
  codes: 'codes'             # ソースコードファイル
  chapter_templates: 'chapter_templates'     # 章テンプレートファイル
  covers: 'covers'           # カバー画像ファイル
  config: 'config'           # 各種設定ファイル
```

### ビルド・ライフサイクル

`vs build` コマンドが実行された際、以下の内部コマンドが順番に呼ばれます：

1. **clean** - クリーンアップ処理
2. **optimize images** - 画像の最適化
3. **prepare theme images** - テーマ画像の準備
4. **build sections html** - 各セクションのHTMLをビルド
5. **generate toc and pdf** - 目次 (TOC) を生成し、PDFとして出力
6. **build overall pdf and split** - 全体PDFを生成し、TOC と sections に分割
7. **build 02-03-front.pdf** - 前付 (titlepage, legalpage, colophonpage) のPDFをビルド
8. **build front pages and tail** - 前ページおよび後書きページのビルド
9. **merge all pdfs with outline** - 全ての中間PDFを結合（アウトライン情報を含む）
10. **apply outline to output pdf** - 出力されたPDFにアウトライン（しおり）を適用
11. **compress pdf** - PDFの圧縮処理
12. **rename output pdfs** - 出力PDFのファイル名をリネーム
13. **final clean** - 最終的なクリーンアップ処理

### コマンド群

#### 利用者が用いるコマンド
```
help, new, build, clean, delete, doctor,
create, rename, renumber, pdf:compress, resize, resize:high, resize:medium, resize:low,
index, index:auto, index:apply, open, import, glossary, lint, metrics, cover
```

#### 内部コマンド
```
entries, create:titlepage, create:colophon, create:legalpage,
pre_process, convert, post_process, toc, pdf, vivliostyle
```

内部コマンドは、主にビルドパイプラインの中間処理や自動生成ステップとして利用します。個別に実行することはできません。`vs build` が必要に応じて呼び出します。

## 詳細設計ドキュメント

Vivlio Starter の具体的なロジックや仕様については、以下の詳細設計ドキュメントを参照してください。

**フォーク開発者向け**: vivlio-starter gem をフォークして開発する方は、これらの仕様書を参考にしてください。

### 主要な仕様書
- **docs/archive/book_build_flow.md** - ビルドプロセスの詳細仕様
- **docs/specs/data_render_spec.md** - データ展開機能（QueryStream）の仕様
- **docs/specs/query_stream_spec.md** - QueryStream パーサーの詳細仕様
- **docs/archive/catalog_spec.md** - カタログ機能の仕様
- **docs/archive/chapters_spec.md** - 章管理の仕様
- **docs/archive/cross_reference_spec.md** - 相互参照機能の仕様
- **docs/archive/index_glossary_spec.md** - 索引・用語集機能の仕様
- **docs/archive/metrics_spec.md** - メトリクス機能の仕様
- **docs/archive/pdf_reader_spec.md** - PDF読み込み機能の仕様

### その他の仕様書
`docs/archive/` ディレクトリには、以下の仕様書が含まれています：
- 各種コマンドの仕様（help, lint, cover, import など）
- PDF関連の仕様（圧縮、印刷入稿、出力命名）
- 画像処理の仕様（OCR、品質向上）
- テキスト処理の仕様（スペルチェック、MeCab処理）

これらの仕様書は、入力と出力、変換ルール、例外処理など、具体的な実装ロジックを詳細に記述しています。

## AI による開発支援

AI（Claude, GPT-5 など）を使ってコードを生成する際の指針：

- **アーキテクチャ理解**: この DEVELOPER_GUIDE と詳細設計ドキュメントを参照
- **テスト駆動**: 既存のテストパターンを参考に、まずテストを記述
- **段階的実装**: 複雑な機能は小さなステップに分割して実装
- **仕様準拠**: 詳細設計ドキュメントの仕様に従って実装

## ライセンス

このプロジェクトは MIT License です。詳細は [LICENSE](./LICENSE) を参照してください。
