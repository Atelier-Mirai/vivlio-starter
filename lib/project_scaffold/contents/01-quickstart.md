# クイックスタート

:::{.chapter-lead}
この章では、Vivlio Starter をインストールして、最初の PDF を生成するまでの流れを体験します。難しいことは何もありません。コマンドをいくつか入力するだけで、あなたの本が完成します。
:::

## Ruby のインストール

Vivlio Starter は Ruby で動作します。すでに Ruby がインストール済みの方は、次の「Vivlio Starter のインストール」に進んでください。

```bash
# Ruby がインストール済みか確認
ruby -v
```

`ruby 4.0.2` のようにバージョンが表示されれば準備完了です。

### はじめて Ruby をインストールする場合

同梱のスクリプトを使うと、必要なツールを自動でセットアップできます。ターミナルを開いて、次のコマンドを実行してください。

```bash
bin/install-ruby.zsh
```

:::{.column}
**💡 ターミナルの開き方（macOS）**

- Spotlight から: `Cmd + Space` →「Terminal」と入力 → `Enter`
- Finder から: アプリケーション → ユーティリティ → Terminal.app
:::

スクリプトは次の作業を自動で行います。

- Xcode コマンドラインツールの確認・インストール案内
- Homebrew（macOS 用パッケージマネージャ）の導入
- rbenv（Ruby バージョン管理ツール）の導入
- 最新安定版 Ruby のインストールとグローバル設定
- bundler のインストール

完了したら、シェルを再読み込みします。

```bash
exec zsh -l
```

再度バージョンを確認して、表示されれば成功です。

```bash
ruby -v   # ruby 4.0.2 (2026-03-16 ...) と表示されれば OK
```

### 将来 Ruby をアップグレードする場合

新しいバージョンがリリースされたときは、バージョンを指定して実行します。

```bash
bin/install-ruby.zsh -v 4.1.0
```

## Vivlio Starter のインストール

Ruby の準備ができたら、Vivlio Starter をインストールします。

```bash
gem install vivlio-starter
```

## 新規プロジェクトの作成

インストールが完了したら、新しい書籍プロジェクトを作成します。`mybook` はプロジェクト名です。お好きな名前に変えてください。

```bash
vs new mybook
cd mybook
```

## ディレクトリ構成

`vs new` コマンドが自動的にプロジェクトの雛形を生成します。

```
mybook/
  contents/          ← 原稿（Markdownファイル）
  images/            ← 画像ファイル
  covers/            ← 表紙画像
  data/              ← 書籍内で展開したいQueryStream用データ（YAML）
  templates/         ← 各種雛形ファイル置き場
  sources/           ← 執筆資料やPDFファイル置き場
  codes/             ← 書籍内で掲載するサンプルコード
  stylesheets/       ← CSSスタイルシート
  config/
    book.yml         ← 書籍の設定ファイル
    catalog.yml      ← 章構成
    page_presets.yml ← ページレイアウト設定
    index_glossary_terms.yml     ← 用語集
  vivliostyle.config.js
  entries.js
  package.json
  Gemfile
```

まずは `contents/` フォルダに注目してください。ここに原稿となる Markdown ファイルが収まっています。`00-preface.md` や `11-install.md` などのサンプルファイルが最初から入っており、これらが執筆の参考になります。

## はじめてのビルド

さっそく PDF を生成してみましょう。

```bash
vs build
```

しばらく待つと、`output.pdf` が生成されて自動的に開きます。これがあなたの最初の技術書です！

:::{.column}
**💡 ヒント**

`contents/` 以下のサンプルファイルは、執筆の書き方見本にもなっています。どんな Markdown を書けばどんな PDF になるのか、実際のファイルを見ながら学べます。
:::

## コマンド一覧

Vivlio Starter にはさまざまなコマンドが用意されています。`vs help` で一覧を確認できます。

```bash
vs help
```

```
Vivlio Starter - 技術書執筆のためのCLIツール
使い方: vs <command> [options]

  プロジェクト管理:
    new              プロジェクトを新規作成します
    import           Re:VIEW Starter プロジェクトを取り込みます
    doctor           環境診断と不足ツールの自動セットアップ
    clean            生成物やキャッシュを削除します

  執筆・編集支援:
    create           章ファイルと画像ディレクトリを生成します
    delete           指定した章の Markdown と画像を削除します
    rename           章のスラッグ/番号を変更します
    renumber         章番号を一括で付け直します
    open             生成されたPDFを開きます（macOS専用）

  文章校正・用語:
    lint             Markdownをtextlintで検査、スペルチェックも行ないます
    metrics          Markdownの行数・文字数を集計します

  アセット・索引:
    cover            カバー画像を生成します（A4/B5/A5/EPUB）
    resize           画像をWebPに変換します
    index            索引機能（index:auto / index:apply）

  ビルド・出力:
    build            書籍全体または指定章をビルドします
    pdf:compress     生成済みPDFを圧縮します
```

たくさんありますが、**全部を覚える必要はありません**。まずはこの3つだけで十分です。

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

## 新しい章を作る

それでは、実際に新しい章を追加してみましょう。

```bash
vs create 10-awesome
```

`contents/10-awesome.md` と `images/10-awesome/` ディレクトリが自動的に生成されます。`10-awesome.md` を開いて、自由に内容を書いてみてください。

書き終わったら、ビルドして確認します。

```bash
vs build 10-awesome
```

章を指定してビルドすると、その章だけが素早く PDF 化されます。全体をビルドするより速いので、執筆中の確認に便利です。

すべての章を書き終わったら、最後にもう一度 `vs build` を実行してください。表紙・目次・索引・奥付まで揃った、完成した本が出来上がります！

```bash
vs build
```

:::{.text-right}
**さあ、あなたの技術書を書き始めましょう！**
:::
