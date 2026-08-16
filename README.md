# はじめての技術書づくり ～Vivlio Starter 実践ガイド～

「自分の本を作ってみたい」——そう思ったことはありませんか。日々の仕事で培った技術的な知見、趣味で深めた専門知識、あるいは誰かに伝えたい物語。Vivlio Starter は、Markdown で書いた原稿から高品質な PDF・EPUB を生成する書籍制作システムです。CSS 組版エンジン Vivliostyle をコアに据え、執筆から入稿に至るすべての工程を自動化します。

![Vivlio Starter ロゴ](docs/logos/vs_vivlio_starter_logo_outline.svg)

> **ブランドアイデンティティ**
> ロゴの緑は Markdown から始まる執筆の第一歩と継続的な成長を表し、青は CLI や CSS 組版が支える技術的信頼性と出力のゴールを象徴します。シンプルな操作で確かな技術に裏打ちされた書籍制作を提供するという Vivlio Starter のメッセージを表現しています。

## Vivlio Starter でできること

- **Markdown で執筆** — 使い慣れた記法でさくさく書ける。特別なフォーマットを覚える必要はありません
- **コマンド一発でビルド** — `vs build` ひとつで、原稿が美しい PDF に変わります
- **印刷入稿に対応** — トンボ・塗り足し付きの PDF を生成。印刷所にそのまま入稿できます
- **電子書籍も出力** — EPUB（Kobo / Apple Books 向け）と Kindle 用 KPF を、配信先ごとに最適化して生成します
- **テーマで簡単デザイン** — `book.yml` でアクセントカラーや扉絵を選ぶだけで、統一感あるデザインに
- **環境構築も自動** — `vs new` でプロジェクトを作成し、`vs doctor` で必要なツールを自動セットアップ

### 執筆を支える機能

- **文章校正（`vs lint`）** — 表記揺れ・冗長表現・文体の混在を検出。英単語の綴りも 50 以上の技術辞書で確認します
- **分量と読みやすさの分析（`vs metrics`）** — 刊行書の実測に基づく基準で、章の分量が適切かを判定。漢字比率・語彙の多様さ・読解難度も測ります
- **索引・用語集の自動生成** — 候補を抽出してレビューし、承認した語だけを登録。「その語を説明している章」を指すページを太字で先頭に並べます
- **図解注釈（`:::{.showcase}`）** — スクリーンショットの枠・矢印・丸数字を原稿に文字で書くと、ビルド時に画像へ焼き込まれます。画像編集ソフトは要りません
- **ダイアグラム（` ```mermaid `）** — フローチャートやシーケンス図をテキストで描けます
- **会話文（`:::{.talk}`）** — 「キー: 発話」を並べるだけで、話者ごとに色分けした吹き出しになります
- **環境の一括更新（`vs upgrade`）** — 本体 gem・プロジェクトの雛形・外部ツールを 1 コマンドで最新化します

## 執筆ワークフロー

Vivlio Starter を使った書籍制作は、5つのステップで完結します。

| ステップ | 主なコマンド | 内容 |
| :--- | :--- | :--- |
| ① プロジェクト作成 | `vs new mybook` | 雛形生成＋必要ツール自動セットアップ |
| ② 執筆 | `vs create 10-intro` | 章ファイルを追加して Markdown で執筆 |
| | `vs build 10-intro` | 章単位で素早く確認 |
| ③ 整える | `vs lint` | 文章を校正（textlint） |
| | `vs metrics` | 原稿の分量と読みやすさを確認 |
| | `vs preflight` | ビルド前の原稿エラーを数秒で検出 |
| ④ ビルド | `vs build` | 書籍全体をビルド（カバー未生成時は自動生成） |
| ⑤ 入稿・配布 | — | 生成済みファイルを提出・アップロード |

②と③は何度でも繰り返せます。書いては整え、また書く——この往復が、読みやすい技術書を仕上げる近道です。

## クイックスタート

### 前提条件

- **Ruby 3.4 以上**（CLI 実行に必要。3.4.10 と 4.0.6 で動作確認）
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

### Markdown 1 枚をそのまま PDF に

プロジェクトを作らずに、手元の Markdown を 1 枚だけ組版することもできます。

```bash
vs build myawesome.md                  # カレントディレクトリに myawesome.pdf を生成
vs build ~/notes/idea.md --theme blue  # テーマカラーを指定
```

`book.yml` も `catalog.yml` も使わない軽量経路です。出力は閲覧用 PDF のみ・装飾は画像なし（simple）固定で、コードインクルードやクロスリファレンス、索引・用語集は使えません。

## ディレクトリ構成

```
mybook/
  contents/       ← 原稿（Markdown ファイル）
  images/         ← 画像ファイル
  covers/         ← 表紙・裏表紙用の画像ファイル
  data/           ← 本文へ展開するデータ（YAML 形式）
  templates/      ← 章の雛形とデータ展開テンプレート
  sources/        ← 執筆資料や PDF ファイル置き場
  codes/          ← 本文へ取り込むサンプルコード
  stylesheets/    ← CSS スタイルシート
  config/         ← 各種設定ファイル
    book.yml      ← 書籍の設定
    catalog.yml   ← 章構成
    scaffold.lock ← 雛形マニフェスト（自動生成）
  README.md
  Gemfile
  package.json
  .gitignore
```

ビルドの生成物（表紙の PDF・扉絵の合成画像・キャッシュ）は `.cache/vs/` 配下に出力されるため、原稿のディレクトリと混ざりません。

## コマンド一覧

```bash
vs --help
```

```
📚 Vivlio Starter - 技術書執筆のためのCLIツール 🛠️
使い方: vs <command> [options]

  プロジェクト管理:
    new              新しい書籍プロジェクトを作成します
    upgrade          本体 gem・プロジェクト雛形・外部ツールをまとめて最新化します
    import           Re:VIEW Starter プロジェクトを取り込みます
    pdf:read         PDF を Markdown へ変換します
    doctor           環境診断と不足ツールの自動セットアップを行います
    clean            生成物やキャッシュを削除します

  執筆・編集支援:
    create           章ファイルと画像ディレクトリを生成します
    delete           指定した章の Markdown と画像を削除します
    rename           章の番号やファイル名（スラッグ）を変更します
    renumber         章番号を一括で付け直します

  文章校正・統計:
    lint             contents/ 以下の Markdown を textlint で検査します
    metrics          Markdown の行数・文字数を集計します

  索引・用語集:
    index            索引・用語集のサブコマンド一覧を表示します
    index:plan       索引語数の目安と現況を表示します（辞書は変更しません）
    index:auto       索引・用語集の候補を抽出し、確認用ファイルを作成します
    index:apply      確認済みの候補を索引辞書（index_glossary_terms.yml）に登録します
    index:export     用語集・棄却語を index_library.yml へ書き出します
    index:import     index_library.yml から用語集・棄却語を取り込みます

  画像・カバー:
    cover            表紙・裏表紙の画像を生成します（A4/B5/A5/EPUB）
    resize           images/ の画像を WebP へ変換・最適化します（--high/--low で品質変更）

  ビルド・出力・プレビュー:
    preflight        ビルド前の原稿エラーチェックを高速実行します
    build            書籍全体または指定章をビルドします
    open             生成された PDF を開きます（macOS 専用）
    pdf:compress     生成済みの PDF を圧縮します
    pdf:pages        PDF をページ単位で JPEG 画像に切り出します
    pdf:rasterize    PDF をラスタライズして再結合します（Type3 フォント対策）
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

`--log` が使えるのは処理の段階が多い `vs build` / `vs preflight` / `vs new` です。
ほかのコマンドは実行結果を最後に 1 行で報告します。

### ビルド中の進捗表示（スピナー）

`vs build` は端末で実行すると、いま何をしているかをスピナーで表示します。

```
⠹ ビルド中: build overall pdf … (12/18)
```

括弧の中は「全体の何段階目か」です。段階の数は `output.targets` の指定によって変わります。

次の場合は自動的に表示されません（出力を汚さないため）。

- パイプ・リダイレクト経由での実行（`vs build | tee log.txt` など）や CI
- `--log` を指定したとき（逐次ログが流れるため）

意図的に止めたいときは `VS_NO_SPINNER=1` を指定します。

```bash
VS_NO_SPINNER=1 vs build
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
- **数式の画像化**: LaTeX 記法を MathJax で SVG へ焼き込み（PDF・EPUB・Kindle で同じ見た目）
- **図の生成**: ` ```mermaid ` のダイアグラムと `:::{.showcase}` の図解注釈を画像化
- **索引スキャン**: 辞書に登録した語を本文から探し、初出とそれ以降を区別してタグ付け
- **CSS 自動更新**: テーマカラー・スタイル・マーカー・ページ設定を動的生成
- **目次の自動生成**: `catalog.yml` に記載された各章の見出しを自動抽出

### 後処理（vivliostyle 呼び出し後）

- **重複バックリンク排除**: 生成済み PDF の named destinations からページマッピングを取得し、索引・用語集の重複リンクを浄化
- **PDF アウトライン付与**: PDF にしおり（ブックマーク）を付与（別 gem `vivlio-starter-pdf` の導入時。本体のみでも他の処理はすべて動きます）
- **表紙 PDF 結合**: frontcover/backcover を本文 PDF と結合
- **奥付の偶数ページ調整**: 奥付が必ず左ページ（偶数）に来るよう空白ページを自動挿入
- **PDF 圧縮**: Ghostscript による高品質圧縮
- **ファイルリネーム**: `mybook_v0.1.0.pdf` のようにプロジェクト名・バージョンを反映
- **入稿用 PDF の導出**: 閲覧用 PDF の中間成果物からトンボ・塗り足し付きの PDF を作成
- **EPUB / Kindle の生成**: ターゲットごとに最適化した EPUB を組み、Kindle は KPF へ変換

### ビルド時間の内訳

Vivlio Starter の使い方を解説したガイドブック『はじめての技術書づくり』（A4・347 ページ・`contents/` に原稿があります）の全章ビルドで約 5 分。大半は Vivliostyle が紙面を組む時間です。

```
vivliostyle 本体:      約 85%（本文 PDF の組版・バックリンク解決の再組版）
vivlio-starter の処理: 約 15%（前処理・後処理・PDF 結合・しおり付与）
```

原稿の前処理は 4 秒、HTML 変換は 6 秒ほどで終わります。執筆中は `vs preflight`（数秒）と単章ビルド（約 30 秒）で確認し、仕上げに全章ビルドするのが快適です。

## 設定（config/book.yml）

`config/book.yml` は、書籍情報・Vivliostyle・PDF の設定を一元管理します。

```yaml
book:
  main_title: "はじめての技術書づくり"
  subtitle: "Vivlio Starter 実践ガイド"
  author: "早乙女 遙香"
  language: "ja"

theme:
  style: image      # image: 扉絵あり / simple: 扉絵なし
  color: green      # アクセントカラー（12 色 ＋ HEX 指定）

page:
  use: b5_standard  # 判型と版面のプリセット

output:
  targets: pdf      # pdf / print_pdf / epub / kindle（併記可）
```

設定できる項目は書籍情報・テーマ・版面・出力形式のほか、校正・分量分析・索引・PDF 読み取りまで一通り揃っています。すべて既定値を持っているので、書かなければ既定で動きます。設定項目ごとの解説は `contents/41-book-yml.md`（ガイドブックの「config/book.yml リファレンス」の章）にあります。

## 追加ツールのインストール（PDF 操作）

一括ビルドで PDF のページ数取得・分割/結合を行うため、以下の CLI を利用します。`vs doctor --fix` で自動導入されますが、手動でインストールする場合は以下の通りです。

導入済みツールの更新は `vs upgrade` で一括して行えます。vivlio-starter 本体の gem 更新・プロジェクト雛形の追従とあわせて、更新計画（現在版 → 最新版）を提示し、確認後に brew / npm / gem をまとめて更新して再診断します（不足ツールのインストールも同時に行われます。`--yes` で確認スキップ、`--dry-run` で計画表示のみ）。

```bash
brew install poppler qpdf ghostscript imagemagick librsvg vips mecab
npm install -g @vivliostyle/cli @vivliostyle/vfm textlint mathjax-full @mermaid-js/mermaid-cli
```

| ツール | 用途 |
|---|---|
| Vivliostyle CLI（vivliostyle） | CSS 組版による PDF 生成 |
| VFM（vfm） | Markdown → HTML 変換 |
| pdfinfo / pdftoppm / pdftotext（poppler） | PDF のメタ情報取得・ページの画像化・しおり生成 |
| qpdf | PDF の分割・結合・ページ抽出 |
| Ghostscript | PDF 圧縮 |
| ImageMagick | 画像変換（WebP 等） |
| librsvg（rsvg-convert） | 扉絵・図解注釈の合成画像のラスタライズ |
| libvips | 高速画像処理 |
| MeCab | 索引の読みの自動推測 |
| mathjax-full | 数式の SVG 化 |
| mermaid-cli（mmdc） | ダイアグラムの画像化 |

### Vivliostyle CLI / VFM

Markdown → HTML の変換は VFM（Vivliostyle Flavored Markdown）が、HTML → PDF の組版は Vivliostyle CLI が担います。`vs build` は両方を**コマンドとして**呼ぶため、**グローバル（`-g`）に導入**してください（上の `npm install -g …` に含まれています）。

```bash
npm install -g @vivliostyle/cli @vivliostyle/vfm
```

> ⚠️ **VFM のパッケージ名は `@vivliostyle/vfm` です。** npm の `vfm` は同名の**まったく別のパッケージ**（Vue 用のフォームバリデーション）なので、入れても `vs build` は動きません。

`package.json` の devDependencies にも同じ 2 つを記載していますが、そちらはプロジェクトで使うバージョンを記録するためのもので、`--save-dev` によるローカル導入では `vivliostyle` / `vfm` コマンドは PATH に現れません。

導入できているかは `vs doctor` が検査します（不足していれば `vs doctor --fix` で導入できます）。

## 出力形式

`config/book.yml` の `output.targets` で指定します。カンマ区切りで併記できます。

| 頒布先 | 指定する値 | 生成されるもの |
| :--- | :--- | :--- |
| 技術書典・コミケ（印刷所入稿） | `print_pdf` | トンボ・塗り足し付き PDF（CMYK 表紙は PDF/X-1a） |
| ダウンロード販売・PDF 配布 | `pdf` | 閲覧用 PDF（表紙結合済み） |
| 楽天 Kobo・Apple Books・BOOTH | `epub` | クリーン EPUB |
| Amazon Kindle（KDP） | `kindle` | KPF（Kindle Previewer 経由で自動変換） |

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
