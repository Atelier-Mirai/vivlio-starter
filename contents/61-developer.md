# 開発者向けガイド

:::{.chapter-lead}
本章は Vivlio Starter をフォークして改造・拡張したい開発者向けの情報をまとめています。著者として執筆するだけであれば、この章を読む必要はありません。
:::

## アーキテクチャ概要

Vivlio Starter は Vivliostyle CLI を厚くラップした Ruby gem です。Samovar ベースの CLI フレームワークを採用しています。

```
bin/vs / bin/vivlio-starter
  └─ lib/vivlio/starter/cli/startup.rb   # CLI.start・無効入力時のヘルプ
       └─ cli/loader.rb                  # ドメイン + Samovar の一括 require
            └─ SamovarCommands::RootCommand
                 └─ 各コマンド（build / lint / metrics / ...）

lib/vivlio/starter/cli.rb                # ライブラリからフル CLI を読む場合（startup を経由）
```

### ディレクトリ構造

```
lib/vivlio/starter/
  cli.rb                    # フル CLI 読み込み（内部で startup + loader）
  cli/
    startup.rb              # CLI.start 単一定義
    loader.rb               # ドメイン〜 Samovar の require 順
    samovar/                # Samovar CLI コマンド定義（利用者向け）
      root_command.rb       # コマンドルーティング
      build_command.rb
      lint_command.rb
      ...
    build/                  # ビルドパイプライン
      pipeline.rb           # ステップ登録・実行制御
      image_optimizer.rb    # 画像最適化
      pdf_merger.rb         # PDF 結合
      ...
    pre_process/            # Markdown 前処理
      markdown_preprocessor.rb  # 前処理パイプライン
      markdown_transformer.rb   # 記法変換（include / book-card など）
      ...
    post_process/           # HTML 後処理
    pdf/                    # PDF 読み取り
    lint/                   # Lint 補助
    metrics/                # メトリクス分析
    build.rb                # ビルドコマンド実装
    clean.rb                # クリーンコマンド実装
    create.rb               # 章作成コマンド実装
    ...
```

各コマンドは `cli/samovar/` 配下の Samovar エントリと `cli/` 配下のドメイン実装の2層構造になっています。

## コマンドとファイルの対応

| コマンド | Samovar エントリ | ドメイン実装 |
|---------|----------------|------------|
| `new` | `samovar/new_command.rb` | `cli/new.rb` |
| `import` | `samovar/import_command.rb` | `cli/import.rb` |
| `pdf:read` | `samovar/pdf_command.rb` | `cli/pdf/pdf_read_command.rb` |
| `doctor` | `samovar/doctor_command.rb` | `cli/doctor.rb` |
| `clean` | `samovar/clean_command.rb` | `cli/clean.rb` |
| `create` | `samovar/create_command.rb` | `cli/create.rb` |
| `delete` | `samovar/delete_command.rb` | `cli/delete.rb` |
| `rename` | `samovar/rename_command.rb` | `cli/rename.rb` |
| `renumber` | `samovar/rename_command.rb`（`RenumberCommand`） | `cli/rename.rb` |
| `lint` | `samovar/lint_command.rb` | `cli/lint.rb` |
| `metrics` | `samovar/metrics_command.rb` | `cli/metrics.rb` |
| `index:auto` | `samovar/index_command.rb`（`IndexAutoCommand`） | `cli/index.rb`、`cli/index/unified_index_manager.rb` |
| `index:apply` | `samovar/index_command.rb`（`IndexApplyCommand`） | `cli/index.rb`、`cli/index/unified_index_manager.rb` |
| `cover` | `samovar/cover_command.rb` | `cli/cover.rb` |
| `resize` | `samovar/resize_command.rb` | `cli/resize.rb` |
| `build` | `samovar/build_command.rb` | `cli/build.rb`、`cli/build/pipeline.rb` ほか |
| `open` | `samovar/open_command.rb` | （直接実装） |
| `pdf:compress` | `samovar/pdf_command.rb`（`PdfCompressCommand`） | `cli/pdf.rb` |
| `help` | `samovar/help_command.rb` | （直接実装） |

### cli.rb の役割

`lib/vivlio/starter/cli.rb` は以下の役割を担っています。

1. ライブラリからフル CLI を読みたいときの入口（内部で `startup` を読み込む）
2. テストの `require 'vivlio/starter/cli'` の共通 `require` 先

`CLI.start(ARGV)` の定義と無効オプション時の `--help` 誘導は `cli/startup.rb` に単一定義されています。ドメイン〜 Samovar の一括 `require` 順は `cli/loader.rb` に集約されています。

### 利用者コマンド一覧
`vs --help`を実行すると、以下のように示されます。これらは利用者の実行が想定されている公開コマンドです。

```
vs --help
📚 Vivlio Starter - 技術書執筆のためのCLIツール 🛠️
使い方: vs <command> [options]

  プロジェクト管理:
    new              プロジェクトを新規作成します
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
    resize           images/画像をWebP形式に変換・最適化します（--high/--lowで品質変更可）

  ビルド・出力・プレビュー:
    build            書籍全体または指定章をビルドします
    open             生成されたPDFを開きます
    pdf:compress     生成済みPDFを圧縮します

オプション:
  -h, --help       ヘルプを表示
  -v, --verbose    冗長出力を有効化
  --version        バージョン情報を表示

各コマンドの詳細: vs <command> --help
```

### 内部コマンド一覧

以下のコマンドはビルドパイプラインから自動的に呼び出される内部コマンドです。通常は直接実行しません。

| コマンド | 役割 |
|---------|------|
| `pdf` | Vivliostyle CLI を直接呼び出して PDF 生成 |
| `create:titlepage` | タイトルページを生成 |
| `create:colophon` | 奥付を生成 |
| `create:legalpage` | リーガルページを生成 |
| `create:cover` | カバー SVG を生成 |


## プロジェクト概要

### ディレクトリ構成

`vs new` コマンドが `lib/project_scaffold/` の雛形を展開してプロジェクトを生成します。

```bash
vs new mybook
cd mybook
```

を実行すると、以下のように構成されます。

```
mybook/
  contents/          ← 原稿（Markdownファイル）
  images/            ← 画像ファイル
  covers/            ← 表紙画像
  data/              ← QueryStream用データ（YAML）
  templates/         ← 各種雛形ファイル
  sources/           ← 執筆資料やPDFファイル置き場
  codes/             ← 書籍内で掲載するサンプルコード
  stylesheets/       ← CSSスタイルシート
  config/
    book.yml         ← 書籍の設定ファイル
    catalog.yml      ← 章構成
    page_presets.yml ← ページレイアウト設定
    index_glossary_terms.yml     ← 索引・用語集辞書
  vivliostyle.config.js
  package.json
  Gemfile
```

各ディレクトリの役割を技術的な観点から補足します。

`contents/` は原稿の Markdown ファイルを置く場所です。ファイル名は `XX-slug.md` 形式（例: `11-install.md`）で、先頭の数字が章の並び順を決めます。`00-preface.md`（前書き）・`99-postface.md`（後書き）・`90-98`（付録）は特別扱いされます。`catalog.yml` に登録された章のみがビルド対象になります。

`images/` は章ごとのサブディレクトリ（`images/11-install/`）に画像を配置します。Vivliostyle が HTML から相対パスで参照するため、章ファイルと同名のディレクトリに置く必要があります。`vs create` で章を作ると対応するディレクトリも自動生成されます。`vs build` の Step 1 で WebP への変換・最適化が行われます。

`covers/` は表紙・裏表紙の画像を置く場所です。`frontcover_master.png` / `backcover_master.png`（高解像度マスター）を元に、`vs cover` または `vs build` が PDF / JPEG を自動生成します。`covers/bundled/` には gem 同梱の SVG テンプレート（light / dark テーマ）が入っています。

`data/` は QueryStream 記法（`= books | ...`）で本文中に展開する YAML データを置く場所です。書籍紹介カードや技術書一覧など、繰り返し使うデータを外部化できます。

`templates/` は `vs create` が章ファイルを生成する際に使う Markdown 雛形です。`chapter.md`・`preface.md`・`appendix.md` などが同梱されています。

`sources/` は執筆の参考資料や `vs pdf:read` で変換する元 PDF を置く場所です。ビルドには関与しません。

`codes/` は本文中に `` ```include:sample.rb``` `` 記法でインクルードするサンプルコードを置く場所です。`vs import` で Re:VIEW Starter から移行した場合は `source/` の内容がここにコピーされます。

`stylesheets/` は CSS ファイル群です。`theme.css` はビルドのたびに `book.yml` の `theme` セクションから自動生成されるため直接編集しても上書きされます。カスタム CSS は `custom.css` に記述してください。`page-settings.css` がページサイズ・余白を定義し、`chapter.css`・`base.css` などが本文スタイルを担います。

`config/` には各種設定ファイルが入ります。`book.yml` が書籍全体の設定（タイトル・著者・テーマ・ビルドターゲットなど）を管理するメインファイルです。`catalog.yml` が章の並び順と構成を定義します。`index_glossary_terms.yml` が索引・用語集の統合辞書です。`post_replace_list.yml` は HTML 後処理での文字列置換ルールを定義します。`textlint_prh.yml` / `textlint_allowlist.yml` は lint の表記揺れ辞書と許可リストです。


### book.yml

書籍プロジェクト全体の設定を管理するメインファイルです。`Common::CONFIG` として全コマンドから参照されます。主なセクションは以下の通りです。

`book` セクションにタイトル・著者・発行日・ISBN などの書誌情報を記述します。`vs new` 実行時の対話入力で `{{MAIN_TITLE}}` などのプレースホルダーが置換されます。

`project.name` が出力 PDF のファイル名ベースになります（例: `vivlio_starter_v1.0.0.pdf`）。`output.filename.include_version: true` でバージョン番号が付与されます。

`theme` セクションでテーマカラー・章扉の背景画像（`frontispiece`）・節見出しの装飾画像（`ornament`）・見出し記号を設定します。`CssUpdater` がビルドのたびにこの値を `stylesheets/theme.css` の CSS 変数として書き出します。

`page.use` で `page_presets.yml` のプリセット名を指定します（例: `b5_airy`）。

`output.targets` でビルド対象を指定します。`pdf`・`print_pdf`・`epub` をカンマ区切りまたは配列で指定でき、`UnifiedBuildPipeline` がこの値に応じて実行するステップを切り替えます。

`output.cover` でカバーテーマを指定します（`light` / `dark` / カスタム名）。

その他、`metrics`・`index`・`glossary`・`lint`・`spellcheck`・`pdf_read` の各セクションで機能ごとの詳細設定を行います。


### catalog.yml

ビルド対象の章と並び順を定義します。`PREFACE`・`CHAPTERS`・`APPENDICES`・`POSTFACE` の4セクションで構成されます。

```yaml
PREFACE:
  - 00-preface

CHAPTERS:
  - 基礎篇:
      - 01-quickstart
      - 02-install
  - 応用篇:
      - 21-customize

POSTFACE:
  - 99-postface
```

`CHAPTERS` 配下にハッシュキーを置くと「部」（パートタイトルページ）が生成されます。`TokenResolver` がこのファイルを読み込んで章の解決を行います。カタログに登録されていない Markdown ファイルはビルド・lint・metrics の対象外になります。

### page_presets.yml

用紙サイズ・余白・文字サイズ・行送りのプリセットを定義します。`book.yml` の `page.use` で参照されます。

YAML アンカー（`&b5_std`）と継承（`<<: *b5_std`）を使って差分のみ記述する構造になっています。

| プリセット | 用紙 | 特徴 |
|-----------|------|------|
| `b5_standard` | B5 | 日本の技術書の標準 |
| `b5_airy` | B5 | 行間広め・ゆったり |
| `b5_compact` | B5 | 行間詰め・情報量重視 |
| `a5_standard` | A5 | 小ぶりで持ち運びやすい |
| `a4_standard` | A4 | 図版の多いマニュアル向け |
| `b5_custom` など | 各サイズ | 自由にカスタマイズ可 |

`CssUpdater` がこのプリセット値を読み取り、`@page` ルールの `size`・`margin` や本文の `font-size`・`line-height` を `theme.css` に書き出します。


## ビルドパイプライン

Vivlio Starter のエンジンとなる Vivliostyle CLI では、ビルドは次のように行われます。

```bash
# HTML または Markdown から直接 PDF を生成
vivliostyle build manuscript.md -s A4 -o paper.pdf

# vivliostyle.config.js を使って複数ファイルをまとめてビルド
vivliostyle build
```

Vivliostyle CLI は HTML/Markdown を受け取り、CSS 組版で PDF を生成します。`vivliostyle.config.js` に章ファイルの一覧やテーマを記述することで、複数ファイルを1冊にまとめられます。

Vivlio Starter はこの上に前処理・後処理・PDF 結合などのパイプラインを追加し、`vs build` の1コマンドで書籍全体を生成できるようにしています。

`vs build` が実行されると `Build::UnifiedBuildPipeline` が以下のステップを順に実行します。

| ステップ | 処理内容 |
|---------|---------|
| Step 0 | クリーンアップ（中間ファイル削除） |
| Step 1 | 画像最適化（WebP 変換） |
| Step 2 | テーマ画像の準備（frontispiece / ornament） |
| Step 3 | Markdown 前処理（frontmatter 付加・画像パス修正など） |
| Step 4 | 索引スキャン・索引ページ生成 |
| Step 5 | Markdown → HTML 変換（VFM） |
| Step 5b | パートタイトルページ生成（`--log=debug` では Step 5 と合算して表示） |
| Step 6 | 目次生成・entries.js 生成 |
| Step 7 | 全体 PDF 生成（前書き＋目次＋本文＋付録＋後書き＋索引） |
| Step 8 | バックリンク重複排除 |
| Step 9 | 表紙・奥付 PDF 生成 |
| Step 10 | PDF 結合 |
| Step 11 | アウトライン付与 |
| Step 12 | 圧縮・リネーム・最終クリーンアップ |
| Step 13 | 入稿用 PDF 生成（`print_pdf` ターゲット時のみ） |
| Step E | EPUB 生成（`epub` ターゲット時のみ） |

`output.targets` の設定によってステップの組み合わせが変わります。`pdf` のみ・`print_pdf` のみ・`epub` のみ・複数の組み合わせそれぞれで不要なステップがスキップされます。単章ビルド（`vs build 01-intro`）の場合は Step 6〜12・14 をスキップし、Step 5 で entries.js と PDF を直接生成します。

`vs build --log=debug`として実行すると、各ステップの詳細を確認することが出来ます。

ビルドシステムの中核を担う、`pre_process`, `covert`, `post_process`, `pdf`について、次に概要を示します。

### Markdown 前処理（pre_process）

`MarkdownPreprocessor#run` が以下の変換を順に適用します。実装は `cli/pre_process/` 配下に分割されています。

1. フロントマター生成・更新（`frontmatter_generator.rb`）
2. HTML コメント除去
3. QueryStream 記法展開（`= books | ...`）（`data_render.rb`）
4. 画像パス正規化（`image_path_normalizer.rb`）
5. コードインクルード展開（`` ```include:file.rb``` ``）
6. HTML ブロック境界の正規化
7. インラインコード HTML エスケープ
8. `{.text-right}` 記法変換
9. book-card / table-rotate 変換（`markdown_transformer.rb`）
10. リンク脚注化

また、`css_updater.rb` が `config/book.yml` の `theme` セクションを読み取り `stylesheets/theme.css` を生成します。

### HTML 変換（convert）

`ConvertCommands#execute_convert` が VFM（Vivliostyle Flavored Markdown）を呼び出し、前処理済みの `.md` ファイルを `.html` に変換します。実装は `cli/convert.rb` です。

### HTML 後処理（post_process）

`PostProcessCommands#execute_post_process` が生成された HTML に対して以下の処理を順に適用します。実装は `cli/post_process.rb` と `cli/post_process/` 配下のモジュール群です。

1. `<body>` タグへのファイルタイプクラス付与（`body_class_injector.rb`）
2. `config/post_replace_list.yml` に基づく文字列置換（`html_replacer.rb`）
3. `theme.style = image` 時の h2 を `<article.section-topic>` でラップ（`section_wrapper.rb`）
4. sideimage コンテナの正規化・列比率の CSS 変数埋め込み
5. image-group コンテナの列比率設定
6. 章末脚注 → ページ脚注変換（`footnote_converter.rb`）
7. sideimage 内脚注の処理・脚注の出現順再番号付け
8. Prism.js 行番号付与（`prism_lines.rb`）
9. クロスリファレンス用コードブロックのラップ
10. 見出しマーカー・番号スパンの付与（`heading_processor.rb`）

### PDF 生成（pdf）

`PdfCommandRunner` が Vivliostyle CLI を呼び出して HTML から PDF を生成します。実装は `cli/pdf.rb` です。

- 通常の閲覧用 PDF（`PdfCommandRunner`）: `vivliostyle build` を実行し `output.pdf` を生成
- 入稿用 PDF（`PrintPdfCommandRunner`）: トンボ・塗り足し付きで `vivliostyle build` を実行
- PDF 圧縮（`PdfCompressor`）: Ghostscript で圧縮
- PDF を開く（`PdfOpener`）: 生成済み PDF をシステムのデフォルトアプリで開く

`cli/build/` 配下の `PdfMerger`・`PdfFinalizer`・`OutlineExtractor` が PDF 結合・リネーム・アウトライン付与を担います。


### CSS とテーマの仕組み

`stylesheets/theme.css` は `pre_process` の `CssUpdater` によってビルドのたびに自動生成・上書きされます。`config/book.yml` の `theme` セクションの設定値が CSS 変数として書き出されます。

**このため `theme.css` を直接編集しても、次回ビルド時に上書きされます。**

テーマカラーや扉絵の設定は必ず `config/book.yml` の `theme` セクションで行ってください。

著者が追加 CSS を記述したい場合は `stylesheets/custom.css` を使用してください。このファイルはビルド時に上書きされないため、自由に CSS を追記できます。`custom.css` が存在しない場合は自動的に空ファイルが生成されます。

## プロジェクト管理の為のコマンド

Vivlio Starter はプロジェクト管理の為のコマンドとして、次のコマンドを実装しています。

```
プロジェクト管理:
    new              プロジェクトを新規作成します
    import           Re:VIEW Starter プロジェクトを取り込みます
    pdf:read         PDFを解析して Markdown 形式へ変換・抽出します
    doctor           環境診断と不足ツールの自動セットアップ
    clean            生成物やキャッシュを削除します
```

それぞれのコマンドの概要を示します。

### new

`cli/new.rb`（`NewCommands`）が担当します。

プロジェクト名を受け取り、`lib/project_scaffold/` のテンプレートを展開して新規書籍プロジェクトを作成します。対話形式で書籍名・著者名・発行者などを入力でき、入力内容は `config/book.yml` に書き込まれます。展開後は自動的に `vs doctor --fix` を実行して必要ツールをセットアップします。

```bash
vs new mybook
vs new mybook --yes   # 対話をスキップしてデフォルト設定で作成
```

### import

`cli/import.rb`（`ImportCommands`）が担当します。

Re:VIEW Starter プロジェクトを Vivlio Starter 形式に変換してインポートします。`.re` ファイルを Markdown に変換し、画像を WebP に変換、`source/` を `codes/` にコピー、`catalog.yml` / `config.yml` を変換します。

```bash
vs import ../review_starter_project
vs import --force ../review_starter_project   # 確認プロンプトをスキップ
```

### pdf:read

`cli/pdf/pdf_read_command.rb`（`PdfReadCommand`）が担当します。

既存の PDF を解析して Markdown に変換・抽出します。Standard Mode と Enhanced Mode の2段階で機能を提供し、`vivlio-starter-pdf` gem がインストール済みであれば自動的に Enhanced Mode に切り替わります。

| 項目 | Standard Mode | Enhanced Mode |
|------|--------------|--------------|
| ライセンス | MIT | AGPL-3.0 |
| 変換対象 | テキストのみ | テキスト + 画像 + OCR |
| 依存ライブラリ | PDF::Reader | HexaPDF, ruby-vips, Tesseract |

#### Standard Mode

`cli/pdf/standard_provider.rb` が担当します。`PDF::Reader` でテキストを抽出し、Markdown に変換します。

#### Enhanced Mode（vivlio-starter-pdf gem）

AGPL ライセンスの HexaPDF を使用するため、ライセンス分離の目的で別 gem（`vivlio-starter-pdf`）に切り出されています。実装は `/lib/vivlio/starter/pdf/reader.rb`（`Reader`）と `/lib/vivlio/starter/cli/pdf/enhanced_provider.rb`（`EnhancedProvider`）の2層構造です。

`Reader` の処理パイプライン:

1. HexaPDF の `PageTextCollector`（`HexaPDF::Content::Processor` サブクラス）でコンテンツストリームを走査し、テキスト断片を座標付きで収集
2. テキスト品質が低い・テキスト埋め込みなしのページを検出し、OCR（pdftoppm + Tesseract）を自動適用
3. OCR 後のテキストに空白圧縮・括弧正規化・prh 辞書置換・MeCab 改行補正を適用
4. PDF 内の画像オブジェクトを WebP に変換して `images/` に保存
5. スキャン PDF の場合は vips でページ画像を解析し、行プロファイル + ガウシアン平滑化でイラスト領域を自動検出
6. テキスト行と画像参照を Y 座標順に統合して Markdown を生成

`EnhancedProvider` は隠しノンブル書き込み（`stamp_nombre!`）と PDF アウトライン付与（`add_outline!`）を HexaPDF で実装し、`vs build` の Step 11 から呼び出されます。

```bash
vs pdf:read sources/original.pdf
VIVLIO_PDF_PLUGIN=disable vs pdf:read document.pdf  # 強制 Standard Mode
```



### doctor

`cli/doctor.rb`（`DoctorCommands`）が担当します。

Vivlio Starter の動作に必要な外部ツールの存在を診断します。診断対象は qpdf・pdfinfo・Ghostscript・ImageMagick・Inkscape・Vivliostyle CLI・textlint・MeCab・Playwright など多岐にわたります。`--fix` オプションを指定すると、macOS + Homebrew 環境で不足ツールを自動インストールします。

```bash
vs doctor           # 診断のみ
vs doctor --fix     # 不足ツールを自動インストール（macOS）
```

### clean

`cli/clean.rb`（`CleanCommands`）が担当します。

ビルドで生成された中間ファイル（HTML・中間 PDF・`entries.js` など）を削除します。最終 PDF（`output.pdf`）はデフォルトでは保持されます。

```bash
vs clean                       # 中間生成物を削除（最終 PDF は保持）
vs clean --purge               # 最終 PDF も含めてすべて削除
vs clean --cache               # キャッシュディレクトリのみ削除
vs clean --cover               # 生成されたカバー画像のみ削除
vs clean --generated-images    # 生成された扉絵・装飾などの画像を削除
vs clean --index-dictionaries  # 索引・用語集辞書データを削除（確認あり）
vs clean --all                 # --index-dictionaries を除くすべての削除オプションを実行
```


## 執筆・編集支援の為のコマンド

Vivlio Starter は執筆・編集支援の為のコマンドとして、次のコマンドを実装しています。

```
  執筆・編集支援:
    create           章ファイルと画像ディレクトリを生成します
    delete           指定した章の Markdown と画像を削除します
    rename           章の番号やファイル名（スラッグ）を変更します
    renumber         章番号を一括で付け直します
```

それぞれのコマンドの概要を示します。

### TokenResolver — 章番号・スラッグの共通解決モジュール

`create` / `delete` / `rename` / `renumber` をはじめ、`build` / `lint` / `metrics` / `index` など章を対象とするすべてのコマンドは、`cli/token_resolver.rb`（`TokenResolver::Resolver`）を通じて章番号・スラッグを解決します。指定方法は柔軟で、以下のいずれの形式でも受け付けます。

- `11-install` — 番号とスラッグを明示（推奨）
- `11` — 番号のみ。ファイルシステムからスラッグを補完
- `install` — スラッグのみ。カタログ・ファイルシステムを探索し、新規の場合は空き番号を自動割り当て
- `11-13` — 範囲指定。11〜13 番の章をまとめて対象にする

### create

`cli/create.rb`（`CreateCommands`）が担当します。

章 Markdown ファイルと対応する画像ディレクトリを生成し、`config/catalog.yml` に自動追記します。

```bash
vs create 11-install
vs create 11                       # 番号のみ
vs create install                  # スラッグのみ（番号自動割り当て）
vs create 11-install 12-tutorial   # 複数同時作成
```

### delete

`cli/delete.rb`（`DeleteCommands`）が担当します。

指定した章の `contents/XX-slug.md`・`images/XX-slug/` ディレクトリ・`catalog.yml` エントリを一括削除します。章番号・範囲・ファイル名で対象を指定できます。デフォルトでは削除前に確認プロンプトが表示されます。

```bash
vs delete 11-install
vs delete 11              # 番号で指定
vs delete 11-13           # 範囲で指定
vs delete 11 --force      # 確認をスキップ
vs delete 11 --dry-run    # 削除予定を確認のみ
```

### rename

`cli/rename.rb`（`RenameCommandExecutor`）が担当します。

章の番号・スラッグを変更し、Markdown ファイル・画像ディレクトリ・`catalog.yml` を一括で更新します。番号のみ指定した場合はスラッグを維持します。付録（90〜98）の場合は `appendix-a` 形式のスラッグを自動調整します。変更後は古い生成ファイル（HTML）を自動削除します。

```bash
vs rename 11-old 12-new   # 番号とスラッグを変更
vs rename 11 12           # 番号のみ変更（スラッグ維持）
vs rename 11 new-slug     # スラッグのみ変更
```

### renumber

`cli/samovar/rename_command.rb`（`RenumberCommand`）が担当します。実装は `RenameCommandExecutor` を引数なしで呼び出すことで `rename` と共有しています。

全章の連番を一括で付け直します。通常章（01〜89）と付録（90〜98）を分けて処理し、先頭章番号を起点に順に詰めます。`--step` で刻み幅を指定できますが、01〜89 の範囲に収まるよう自動調整されます。

```bash
vs renumber               # 全章を連番付け直し
vs renumber --step 5      # 5 刻みで連番付け直し
```


## 文章校正・統計の為のコマンド

Vivlio Starter は文章校正・統計の為のコマンドとして、次のコマンドを実装しています。

```
  文章校正・統計:
    lint             Markdownをtextlintで検査します
    metrics          Markdownの行数・文字数を集計します
```

### lint

`cli/lint.rb`（`LintCommands`）が担当します。

`contents/` 配下の Markdown を textlint で検査します。日本語技術文書向けのルールセット（`textlint-rule-preset-ja-technical-writing`・`textlint-rule-preset-japanese`・`textlint-rule-prh`）を使用します。textlint の英語エラーメッセージは `TextlintFormatter` が日本語に変換して出力します。

textlint に加えて、独自のスペルチェック（`lint/spell_checker.rb`）も並行して実行します。`config/spellcheck_dictionaries/` の辞書ファイルを `lint/dict_manager.rb` が読み込み、技術用語・固有名詞の誤字を検出します。

原稿内で `<!-- vs-lint-disable -->` / `<!-- vs-lint-enable -->` コメントを使うと、その範囲の lint を無効化できます。これらは実行時に textlint ネイティブの `<!-- textlint-disable -->` 記法に変換されてから渡されます。

```bash
vs lint                    # 全章を検査
vs lint 11-install         # 指定章のみ
vs lint 11-21              # 範囲指定
vs lint --fix              # 自動修正
vs lint --config path/to/.textlintrc.yml  # 設定ファイルを切り替え
```

### metrics

`cli/metrics.rb`（`MetricsCommands`）と `cli/metrics/runner.rb`（`Metrics::Runner`）が担当します。

Markdown の文章品質を多角的に分析します。

分析項目:

- 基本統計: 文字数・行数・文数・節数・読点数
- 語彙難度: 漢字比率・平均語長（MeCab による形態素解析）
- 語彙多様度: TTR（Type-Token Ratio）— 異なり語数 ÷ 総語数
- 読解難度スコア: 日本語版 Flesch/Kincaid を応用したスコアと Easy / Standard / Professional の評価ラベル
- 章・節単位の分量可視化: `[ ]` 枠内に `#` と空白でバーを描画

`catalog.yml` に登録された章のみを対象とし、下書きや退避ファイルは除外します。章を明示指定した場合はカタログ外でも実行します。

分量の基準値は `config/book.yml` の `metrics` セクションで管理します。`compact`（薄い本）/ `standard`（同人誌・技術書）/ `commercial`（商業出版）のプリセットから選択でき、`author_custom` で独自基準も設定できます。

高速化のため、章ごとの解析結果を `.cache/metrics/{basename}.yml` にキャッシュします。Markdown の更新時のみ再解析し、章解析は内部スレッドプールで並列実行します（並列数は `Etc.nprocessors` と上限値の小さい方、`VIVLIO_METRICS_CONCURRENCY` で上書き可能）。

```bash
vs metrics                 # 全章の概要
vs metrics 2               # 第2章のみ（節まで表示）
vs metrics 1-3             # 範囲指定
vs metrics 1,3,5           # 個別指定
vs metrics --all           # 全章を節まで表示
vs metrics --warn          # 警告がある章のみ表示
```

## 索引・用語集の為のコマンド

Vivlio Starter は索引・用語集の為のコマンドとして、次のコマンドを実装しています。

```
  索引・用語集:
    index:auto       索引・用語集の候補を抽出し、確認用ファイルを作成します
    index:apply      確認済みの候補を、プロジェクトの索引辞書に登録・保存します
```

索引・用語集機能は `cli/index/` 配下に実装されており、`UnifiedIndexManager` がプロセス全体を統括します。機能の有効・無効は `config/book.yml` の `index_glossary.enabled` で制御します。

### 設計の基本原則

Vivliostyle の `target-counter` はレンダリング時にページ番号を解決するため、Ruby のビルド時点では実際のページ番号が不明です。そのため「Ruby でリンク構造を作り、CSS でページ番号を流し込む」アーキテクチャを採用しています。

本文中の索引語は `<dfn id="idx-...">` / `<span id="idx-...">` に変換され、索引ページ（`_indexpage.html`）の `<a href="chapter.html#idx-...">` が CSS の `target-counter(attr(href), page)` でページ番号を描画します。

### 統合辞書（index_glossary_terms.yml）

索引と用語集は `config/index_glossary_terms.yml` の単一ファイルで管理します（`UnifiedTermsManager`）。各用語の `flags` フィールドで所属を制御します。

| flags | 掲載先 | 本文への挿入 |
|-------|--------|------------|
| `i` | 索引ページのみ | `<span class="index-term">` |
| `g` | 用語集ページのみ | `<span>` + `<a class="glossary-link">†</a>` |
| `ig` | 索引・用語集の両方 | `<span>` + `<a class="glossary-link">†</a>` |

用語集（`g`）として登録された語は、本文中に上付きの `†`（ダガー）記号が挿入され、クリックで用語集ページへジャンプします。用語集ページには本文への逆引きリンク（バックリンク）も生成されます。

### ワークフロー

```bash
vs index:auto    # 候補抽出 → _index_glossary_review.md 生成
# _index_glossary_review.md を編集（[i]/[g]/[ig]/[r] でフラグ付け）
vs index:apply   # 編集内容を index_glossary_terms.yml に反映
vs build         # ビルド時に索引・用語集ページを自動生成
```

### index:auto の処理フロー

`UnifiedIndexManager#auto_process!` が以下を順に実行します。

1. `IndexCandidateExtractor` が本文をスキャンして索引候補を抽出
   - 構造的抽出: 見出し・強調（`**...**`）・コードスパン・`[用語|読み]` 記法
   - MeCab による名詞・複合名詞の自動抽出
   - 定義表現パターン（「〜とは」「〜を…と定義」など）の検出
2. `ScoringEngine` が候補にスコアを付与（TF-IDF・定義パターン・見出し近傍・専門用語辞書など）
3. スコアに応じて自動承認（`auto_approve_threshold` 以上）またはレビュー待ちに仕分け
4. `ReviewMarkdownGenerator` が `_index_glossary_review.md` を生成

`_index_glossary_review.md` では `[i]` / `[g]` / `[ig]` / `[r]`（リジェクト）でフラグを付けます。定義表現が検出された語は `[ig]` が初期値となり、説明文の候補も自動挿入されます。

### index:apply の処理フロー

`UnifiedIndexManager#apply_markdown_review!` が以下を実行します。

1. `_index_glossary_review.md` を解析してフラグと説明文を取得
2. `UnifiedTermsManager` が `index_glossary_terms.yml` を更新
3. `IndexMatchScanner` が本文 Markdown を再スキャンし `_index_matches.yml` を更新
4. `UnifiedPageBuilder` が `_indexpage.html` と `_glossarypage.html` を生成
5. `_index_glossary_review.md` を削除

### vs build との連携

`vs build` の Step 4（索引スキャン・索引ページ生成）で `IndexCommands.process_index_for_build!` が呼ばれます。`IndexMatchScanner` が `[用語|読み]` 記法を `<dfn>/<span>` に変換し、`UnifiedPageBuilder` が索引・用語集ページを生成します。

Step 8（バックリンク重複排除）では Playwright + Vivliostyle preview による DOM 解析で、同一ページを指す索引リンクの重複を排除します（`BacklinkDedupOrchestrator`）。これにより、1章が複数ページにまたがる場合でも正確なページ番号が索引に掲載されます。

### 本文中の記法

著者は Markdown 内で以下の記法を使って索引語を指定できます。

```markdown
[レスポンシブデザイン|れすぽんしぶでざいん]とは...  # 読み付き（推奨）
[引数]を渡すと...                                    # 読み省略（MeCab で自動推測）
```

初出箇所は `<dfn>`、2回目以降は `<span>` に変換されます。コードブロックやリンク記法（`[text](url)`）は誤検出しないよう除外されます。



## 画像・カバーの為のコマンド

Vivlio Starter は画像・カバーの為のコマンドとして、次のコマンドを実装しています。

```
  画像・カバー:
    cover            表紙・裏表紙の画像を生成します（A4/B5/A5/EPUB対応）
    resize           images/画像をWebP形式に変換・最適化します（--high/--lowで品質変更可）
```

### cover

`cli/create.rb`（`CreateCommands`）が担当します。

`config/book.yml` の `output.cover` に指定したテーマ名に基づいて、表紙・裏表紙の PDF / JPEG を生成します。`vs build` 実行時に必要なカバーが存在しない場合は自動生成されます。

テーマには `light`・`dark`（gem 同梱の SVG テンプレート）と、著者が用意したカスタム PNG を使う方法があります。

| テーマ | ソース | 説明 |
|--------|--------|------|
| `light` / `dark` | `covers/bundled/` の SVG テンプレート | パレット・テキストを `book.yml` の値で置換して生成 |
| カスタム名（例: `mybook`） | `covers/frontcover_mybook.png` など | 著者が用意した高解像度 PNG から変換 |

生成されるファイルは `output.targets` の設定に応じて変わります。

- `pdf` → `frontcover_{theme}_{size}_rgb.pdf`
- `print_pdf` → `frontcover_{theme}_{size}_cmyk.pdf`（トンボ・塗り足し付き）
- `epub` → `cover_{theme}.jpg`（1600×2560 px）

SVG → PDF の変換は `rsvg-convert`（優先）または ImageMagick で行います。`book.yml` の更新日時とソースファイルの更新日時を比較し、変更がない場合は再生成をスキップします。

```bash
vs cover                   # book.yml の設定に従って一括生成
```

### resize

`cli/resize.rb`（`ResizeCommands`）が担当します。

`images/` 配下の PNG / JPEG を WebP に変換・最適化します。`vs build` の Step 1 でも自動実行されます。品質プリセットは `--high` / `--low` で切り替えられます。

| プリセット | quality | max_px |
|-----------|---------|--------|
| `--high` | 90 | 2000 |
| 標準（省略時） | 85 | 1600 |
| `--low` | 75 | 1200 |

```bash
vs resize                  # 標準品質で変換
vs resize --high           # 高品質
vs resize --low            # 軽量
```

## ビルド・出力・プレビューの為のコマンド

Vivlio Starter はビルド・出力・プレビューの為のコマンドとして、次のコマンドを実装しています。

```
  ビルド・出力・プレビュー:
    build            書籍全体または指定章をビルドします
    open             生成されたPDFを開きます
    pdf:compress     生成済みPDFを圧縮します
```

ビルドについては、冒頭で詳しく述べていますので、残りの `open`・`pdf:compress` について概要を記します。

### open

`cli/pdf.rb`（`PdfOpener`）が担当します。macOS 専用の機能です。

生成済みの PDF を macOS の Preview.app で開きます。引数を省略した場合は、圧縮版（`output_compressed.pdf`）と通常版（`output.pdf`）の両方が存在すれば更新日時が新しい方を自動選択します。`book.yml` の `output.pdf_preview` セクションでウィンドウ位置（`window_bounds`）や既存ウィンドウを閉じるか（`close_existing_windows`）を設定できます。

```bash
vs open                    # 最新の PDF を自動選択して開く
vs open 11-install         # 指定した PDF を開く
```

### pdf:compress

`cli/pdf.rb`（`PdfCompressor`）が担当します。

Ghostscript（`gs`）を使って生成済み PDF を圧縮します。引数を省略した場合は `book.yml` の `pdf.output_file` を入力とし、`pdf.output_file_compressed` を出力先とします。出力ファイル名を省略した場合は入力ファイル名に `_compressed` を付与します（例: `output.pdf` → `output_compressed.pdf`）。

圧縮設定は `-dPDFSETTINGS=/ebook`（解像度 150dpi 相当）で固定です。`vs build` の Step 12 でも `book.yml` の `pdf.compress: true` 設定時に自動実行されます。

```bash
vs pdf:compress                        # book.yml の設定に従って圧縮
vs pdf:compress input.pdf              # 指定ファイルを圧縮（output: input_compressed.pdf）
vs pdf:compress input.pdf output.pdf   # 入出力を明示
```

## QueryStream

QueryStream は、`data/*.yml` のデータと `templates/_book.md` などのテンプレートを組み合わせて、原稿内の記法を自動展開する機能です。

技術書では「参考書籍の紹介」「おすすめツール一覧」のように、同じフォーマットで複数のアイテムを並べる場面が頻繁にあります。これを Markdown で手書きすると、書籍が増えるたびに原稿を直接編集する必要があり、レイアウト変更も一括でできません。QueryStream はこの課題を解決するために設計しました。データを YAML で一元管理し、テンプレートでレイアウトを定義することで、原稿には `= books | tags=ruby` の1行を書くだけで済みます。

実装は `query-stream` gem として独立しており、`lib/vivlio/starter/cli/pre_process/data_render.rb` が呼び出します。

### 記法

原稿内に1行で書きます。パイプ（`|`）で区切られた最大5ステージのパイプラインです。

```
= [源泉] | [抽出条件] | [ソート] | [件数] | [スタイル]
```

```markdown
= books                                    # 全件展開
= books | tags=ruby                        # 絞り込み
= books | tags=ruby | -title | 5 | :full   # 全ステージ指定
= book | 楽しいRuby                         # 一件検索（title で照合）
= prefectures | region=関東, 関西           # OR 条件
= elements | atomic_number=1..10           # 範囲指定
```

各ステージはトークンの形式から自動判別されるため、途中のステージを省略できます。

### 内部実装（query-stream gem）

`lib/query_stream/` 配下に以下のモジュールが分担します。

`QueryStreamParser` が `= books | tags=ruby | :full` をパースして `{ source:, filters:, sort:, limit:, style: }` の構造化ハッシュを返します。

`DataResolver` がデータファイルを探索します。`books` と書けば `data/books.yml` を、`book` と書いても複数形に補完して同じファイルを探します。YAML（`.yml` / `.yaml`）と JSON（`.json`）をサポートします。

`FilterEngine` が AND / OR / 比較演算子 / 範囲指定によるフィルタリングとソートを行います。日付フィールドは `Date` オブジェクトと文字列を自動正規化して比較します。

`TemplateCompiler` がテンプレートにデータを流し込みます。`= key` のみの行はキーの値に展開し、値が `nil` / 空文字なら行ごとスキップします。`= key` を含まない行（テーブルのヘッダー行など）は一度だけ出力し、含む行のみ各レコードで反復します。VFM の `:::{.book-card}` フェンスが動的行を囲んでいる場合はフェンスごと反復します。

### テンプレートの命名規約

```
templates/
  _book.md              # デフォルト（= books で使用）
  _book.full.md         # :full スタイル
  _book.table.md        # :table スタイル
```

データ名の複数形（`books`）は単数形（`book`）に自動変換してテンプレートを解決します。スタイルを追加したい場合は `_book.mystyle.md` を置くだけで `= books | :mystyle` が有効になります。

### 新しいデータ種別の追加

`data/elements.yml` を作り `templates/_element.md` を置くだけで、設定変更なしに `= elements` が使えるようになります。

## CrossReference

CrossReference は、図・表・コードリストに「章番号＋連番」を自動付与し、本文中から `@id` 記法でリンク付き参照を生成する機能です。「図 3-2 を参照してください」のような記述を手書きせずに済みます。

実装は `cli/pre_process/cross_reference_processor.rb`（`CrossReferenceProcessor`）で、`vs build` の前処理パイプライン内で実行されます。

### 著者向けの記法

キャプション行に `@id` を付けると、直後のブロック種別（コードブロック → リスト、テーブル → 表、画像 → 図）を自動判別してナンバリングします。

```markdown
** 回転テーブルのCSS定義 @css-table-rotate **
```css
table { border-collapse: collapse; }
```

本文中で参照するには `@css-table-rotate` と書くだけです。ビルド時に「リスト 3-2」のようなリンク付きテキストに置換されます。

### 内部処理フロー

`process_cross_references` が以下を順に実行します。

1. `LabelCollectorContext` が全章を走査し、`** タイトル @id **` 形式のキャプション行を収集してラベルマップを構築します。重複 ID はエラーとして記録します。
2. `CaptionedBlockTransformer` がキャプション行とその直後のブロックを HTML に変換し、`id` 属性と章番号付き連番（`リスト 3-2` など）を埋め込みます。
3. `ReferenceReplacer` が本文中の `@id` をラベルマップと照合し、番号付きリンクに置換します。コードブロック・インラインコード内の `@` は置換対象外です。

`@auto` / `@omakase` / `@id` は予約済み ID として番号付与のみ行い、参照リンクは生成しません。



## テスト

Vivlio Starter は Minitest を使用しています。`test/test_helper.rb` で `minitest/autorun` と `minitest/pride`（カラー出力）を読み込んでいます。

```bash
bundle exec rake test
```

Rakefile の `Rake::TestTask` が `test/**/*_test.rb` パターンにマッチするファイルをすべて実行します。`test/` 直下の `test_*.rb`（`test_backlink_deduplicator.rb` など）も対象です。

テストはコマンド・モジュールごとにファイルが分かれており、主な構成は以下の通りです。

| ディレクトリ / ファイル | 対象 |
|------------------------|------|
| `cli/*_test.rb` | 各コマンド（create / delete / rename / lint / cover など）のユニットテスト |
| `cli/build_integration_test.rb` | ビルドパイプラインの統合テスト |
| `cli/samovar_smoke_test.rb` | Samovar コマンド定義のスモークテスト |
| `cli/token_resolver_test.rb` | TokenResolver の章番号・スラッグ解決 |
| `cli/build/` | PDF ビルド・ページレイアウト・ページマッピング |
| `cli/index/` | 索引・用語集の各コンポーネント（10ファイル） |
| `cli/metrics/` | メトリクス分析の各コンポーネント（8ファイル） |
| `cli/lint/` | スペルチェック・辞書管理・トークナイザー |
| `cli/pdf/` | pdf:read コマンド・Enhanced Mode プロバイダー |
| `cli/import/` | Re:VIEW Starter インポート処理 |
| `test_backlink_deduplicator.rb` | バックリンク重複排除（Playwright 連携） |

外部ツール（Vivliostyle CLI・textlint・Ghostscript など）に依存するテストは `stub` でモックしており、ツール未インストール環境でも実行できます。





## 参考資料

本章で触れた各機能の詳細な設計意図・データ構造・実装計画は、`docs/specs/` 配下の仕様書に記録されています。公開リポジトリ [https://github.com/Atelier-Mirai/vivlio-starter/tree/master/docs/specs](https://github.com/Atelier-Mirai/vivlio-starter/tree/master/docs/specs) から参照できます。

主な仕様書:

| ファイル | 内容 |
|---------|------|
| `indexing_implementation_spec.md` | 索引システムの実装仕様（単一の真実ソース） |
| `index_glossary_spec.md` | 索引・用語集統合仕様 |
| `index_dedup_and_unification_spec.md` | ページ番号重複排除・統合仕様 |
| `metrics_spec.md` | 文章品質メトリクスの指標定義と出力仕様 |
| `cover_spec.md` / `cover_auto_generation_spec.md` | カバー画像生成仕様 |
| `query_stream_spec.md` | QueryStream 記法の文法・実装方針 |

機能追加・変更の経緯は `CHANGELOG.md` に記録されています。フォークして開発する際は、変更前に該当する仕様書を確認し、実装後は `CHANGELOG.md` を更新してください。



## 使用している Vivliostyle のバージョン

Vivlio Starter が依存する Vivliostyle 関連パッケージのバージョンは以下の通りです（`package.json` で管理）。

| パッケージ | バージョン | 役割 |
|-----------|-----------|------|
| `@vivliostyle/cli` | 10.5.0 | CSS 組版エンジン CLI。`vs build` から呼び出して PDF を生成 |
| `@vivliostyle/vfm` | 2.6.0 | Vivliostyle Flavored Markdown。Markdown → HTML 変換 |
| `@vivliostyle/core` | 2.41.0 | Vivliostyle のコアレンダリングエンジン |

最新バージョンは [npmjs.com/@vivliostyle/cli](https://www.npmjs.com/package/@vivliostyle/cli) で確認できます。バージョンアップ後は `npm update` を実行してください。

## 開発環境

本ドキュメント執筆時点の開発環境は以下の通りです。フォークして開発する際の参考にしてください。

**OS・言語ランタイム**

| 項目 | バージョン |
|------|-----------|
| macOS | Tahoe 26.3.1 (25D2128) |
| Ruby | 4.0.2 (2026-03-17 revision d3da9fec82) +PRISM [arm64-darwin25] |
| Node.js | v25.9.0 |

**主要 gem・npm パッケージ**

| パッケージ | バージョン |
|-----------|-----------|
| RuboCop | 1.86.1 |
| @vivliostyle/cli | 10.5.0 |
| @vivliostyle/vfm | 2.6.0 |
| @vivliostyle/core | 2.41.0 |

**外部ツール（`vs doctor` が確認するもの）**

| ツール | バージョン |
|--------|-----------|
| Ghostscript | 10.06.0 |
| ImageMagick | 7.1.2-18 |
| Inkscape | 1.4.3 |
| qpdf | 12.3.2 |
