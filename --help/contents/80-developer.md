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

## ディレクトリ構造

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

## ビルドパイプライン

`vs build` が実行されると `Build::UnifiedBuildPipeline` が以下のステップを順に実行します。

| ステップ | 処理内容 |
|---------|---------|
| Step 0 | クリーンアップ（中間ファイル削除） |
| Step 1 | 画像最適化（WebP 変換） |
| Step 2 | frontispiece / ornament 準備 |
| Step 3 | Markdown 前処理（include 展開・画像パス正規化など） |
| Step 4 | VFM による HTML 変換 |
| Step 5 | HTML 後処理（索引タグ付け・置換など） |
| Step 6 | entries.js 生成 |
| Step 7 | Vivliostyle CLI による PDF 生成 |
| Step 8〜 | PDF 結合・圧縮・リネームなど |

## Markdown 前処理（pre_process）

`MarkdownPreprocessor#run` が以下の変換を順に適用します。

1. フロントマター生成・更新
2. HTML コメント除去
3. QueryStream 記法展開（`= books | ...`）
4. 画像パス正規化
5. コードインクルード展開（`` ```include:file.rb``` ``）
6. HTML ブロック境界の正規化
7. インラインコード HTML エスケープ
8. `{.text-right}` 記法変換
9. book-card / table-rotate 変換
10. リンク脚注化

## CSS とテーマの仕組み

`stylesheets/theme.css` は `pre_process` の `CssUpdater` によってビルドのたびに自動生成・上書きされます。`config/book.yml` の `theme` セクションの設定値が CSS 変数として書き出されます。

**このため `theme.css` を直接編集しても、次回ビルド時に上書きされます。**

テーマカラーや扉絵の設定は必ず `config/book.yml` の `theme` セクションで行ってください。

著者が追加 CSS を安全に記述できる仕組み（上書きされないオーバーライド用ファイルなど）は将来の改善課題として CHANGELOG に記録しています。

## cli.rb の役割

`lib/vivlio/starter/cli.rb` は以下の3つの役割を兼ねています。

1. `bin/vs` のエントリポイント（`CLI.start(ARGV)` の定義）
2. 全コマンドモジュールの一括 `require`
3. テストファイルの共通 `require` 先

`help.rb` は `cli.rb` から `require` されているため削除不可ですが、内部の `HelpCommands::HELP_MESSAGE` と `print_help` メソッドは現在使われていません。実際のヘルプ出力は `samovar/help_command.rb` の `HelpCommand` が担っています。これらのリファクタリングは将来の課題として CHANGELOG に記録しています。

## テストの実行

```bash
bundle exec rake test
```

## 内部コマンド一覧

以下のコマンドはビルドパイプラインから自動的に呼び出される内部コマンドです。通常は直接実行しません。

| コマンド | 役割 |
|---------|------|
| `pdf` | Vivliostyle CLI を直接呼び出して PDF 生成 |
| `create:titlepage` | タイトルページを生成 |
| `create:colophon` | 奥付を生成 |
| `create:legalpage` | リーガルページを生成 |
| `create:cover` | カバー SVG を生成 |
