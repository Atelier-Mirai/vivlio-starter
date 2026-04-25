# Import コマンドの使い方

:::{.chapter-lead}
Vivlio Starter の `vs import` コマンドを使うと、Re:VIEW Starter プロジェクトを丸ごと Vivlio プロジェクトに移行できます。本章では前提条件から実行手順、トラブルシューティングまで、著者が自力で移行を完了できるよう手順をまとめました。
:::

## 事前準備と実行

### 必要ツール

下記が揃っているか `vs doctor --fix` で確認・自動インストールしてください。

- Ruby 4.x / Bundler
- node / npm
- ImageMagick, qpdf, pdfinfo, Ghostscript, mecab
- waifu2x-ncnn-vulkan（任意）
- Rouge（コードブロック言語推定用 gem）

### Starter プロジェクトの確認

`starter_project/` 直下に次のファイルが必須です。

| 必須ファイル | 用途 |
| --- | --- |
| `lib/ruby/review-markdownmaker.rb` / `review-markdownbuilder.rb` | Markdown 生成 |
| `config.yml` / `config-starter.yml` | 書籍情報 |
| `catalog.yml` | 目次 |
| `contents/*.re` | 原稿 |
| `images/` | 画像（png/jpg/gif） |

### 実行コマンド

まず `vs new` で空のプロジェクトを作成し、そこに Starter プロジェクトをインポートします。

```zsh
vs new mybook
cd mybook
vs import ../starter_project            # 通常
vs import --force ../starter_project    # 確認を省略したい場合
```

インポート対象ディレクトリは Starter プロジェクトのルートを指定します。

| オプション | 説明 |
| --- | --- |
| `--force` | 既存ディレクトリの削除確認をスキップ |
| `VS_DEBUG=1` | 例外発生時にフルスタックトレースを表示 |

## 処理フローとログ

`vs import` を実行すると、以下の処理が順に実行されます。

1. **クリーンアップ** — Vivlio 側の `contents/`, `images/`, `codes/` を削除して作り直します。
2. **Markdown 生成** — Starter 側で `rake markdown` を自動実行し、`bookname-md/` を生成（既存があれば再利用）。
3. **Markdown 追従変換** — 生 Markdown を `temp/` にコピーし、以下の変換を適用してから `contents/` へ移動します。
   - フェンスブロック（`[abstract]` など）→ `:::{.class}`
   - `<dl>` / `<table>` / `<img>` 変換、ルビ `{漢字|よみ}`
   - 画像パスを `![](foo.webp)` に統一
   - コードブロックキャプション → `` ```lang:filename ``
   - 言語未指定フェンスは Rouge で自動推定（`$`/`%` で始まる行があれば強制 `zsh`）
4. **画像処理** — Starter `images/` をコピー → WebP 化 → 元画像（png/jpg/gif）は削除。`config-starter.yml` に `frontcover_pdffile` があれば `covers/` へコピーし、`book.yml` の `output.cover.front` を更新。
5. **codes/ へのコピー** — Starter `source/` 配下をそのまま `codes/` へコピー。
6. **YAML 変換** — `catalog.yml`（`PREDEF→PREFACE` 等のキー変換、`.re` 拡張子除去）、`config.yml`（`book.main_title` 等を `book.yml` に反映）、`config-starter.yml`（`starter.pagesize` を `page.use` にマッピング）を変換。コメントは保持されます。
7. **片付け** — Vivlio 側 `temp/` と Starter 側 `bookname-md/` を削除。

### 実行中のログ例

```
[Step 1] 既存ディレクトリを削除します
  削除: contents/
[Step 2] .re → .md 変換を実行します
  rake markdown を実行中...
  15 個の Markdown ファイルを検出しました
  コピー: 01-intro.md → temp/
  追従変換を実行中...
[Step 3] 画像を WebP に変換します
  42 個の画像をコピーしました
  旧画像 (png/jpg/gif) を 42 個削除しました
[Step 5] catalog.yml を変換します
  config/catalog.yml を更新しました（コメント保持）
[Step 6] config.yml を変換します
  config/book.yml を更新しました（コメント保持）
インポートが完了しました
```

## インポート後の確認

インポートが完了したら、以下の点を確認してください。

1. `contents/` に Markdown が揃っているか
2. `.webp` 以外の画像が残っていないか
3. `covers/` に表紙 PDF がコピーされ、`config/book.yml` の `output.cover.front` が更新されているか
4. `config/book.yml` の `book.main_title` などが期待どおりか（コメントが消えていないか）
5. `config/catalog.yml` の章名が `.re` を含んでいないか

確認が済んだら `vs build` を実行して、章構成・画像・表紙が意図どおりになっているか PDF で確認してください。

:::{.notice}
画像は WebP のみ残るため、元画像が必要な場合は事前にバックアップを取ってください。
:::

## トラブルシューティング

| 症状 | 原因 | 解決策 |
| --- | --- | --- |
| Starter スクリプトが見つからない | `lib/ruby/review-markdownmaker.rb` が存在しない | Starter のルートを正しく指定する |
| `rake markdown` が失敗する | Starter 側 gem が未インストール | Starter ディレクトリで `bundle install`、または依存 gem を整える |
| Rouge が見つからない | gem が未インストール | `vs doctor --fix` or `gem install rouge` |
| 表紙 PDF がコピーされない | `frontcover_pdffile` が PNG など PDF 以外 | 仕様通り PDF のみに対応。Starter 側設定を修正 |
| `config/book.yml` の値が更新されない | 対応パスが見つからない | コメントやインデントが崩れていないか確認 |

:::{.column}
**ヒント**  
問題があれば `VS_DEBUG=1 vs import ...` で再実行し、ログから原因を特定するのが近道です。
:::
