# Import コマンドの使い方

:::{.chapter-lead}
Vivlio Starter の `vs import` コマンドを使うと、Re:VIEW Starter プロジェクトを丸ごと Vivlio プロジェクトに移行できます。本章では前提条件から実行手順、トラブルシューティングまで、著者が自力で移行を完了できるよう手順をまとめました。
:::

## 事前準備と実行

### 必要ツール

下記が揃っているか `vs doctor --fix` で確認・自動インストールしてください。

- Ruby 3.4 以上 / Bundler
- node / npm
- ImageMagick, qpdf, pdfinfo, Ghostscript, mecab
- `waifu2x-ncnn-vulkan`（任意）
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

1. **クリーンアップ** — Vivlio 側の `contents/`, `images/`, `codes/` を削除して作り直し。索引・用語集の辞書（`config/index_glossary_terms.yml`・`config/index_glossary_rejected.yml`）も空に戻す。いま消した原稿を説明するデータのため。
2. **Markdown 生成** — Starter 側で `rake markdown` を自動実行し、`bookname-md/` を生成（既存があれば再利用）。
3. **Markdown 追従変換** — 生 Markdown を `temp/` にコピーし、以下の変換を適用してから `contents/` へ移動します。
   - フェンスブロック（`[abstract]` など）→ `:::{.class}`
   - `<dl>` / `<table>` / `<img>` 変換、ルビ `{漢字|よみ}`
   - 画像パスを `![](foo.webp)` に統一
   - コードブロックキャプション → `` ```lang:filename ``
   - 言語未指定フェンスは Rouge で自動推定（`$`/`%` で始まる行があれば強制 `zsh`）
   - `//sideimage` → `:::{.sideimage}`・`:::{.sideimage-right}`（`side=R` で右寄せ。幅 `30mm` は版面幅に対する比率 `{width=22%}` へ換算）
   - `//output` → `:::{.output}`、`//cmd` → `:::{.terminal}`（実行結果や端末に行番号を付けないため）
   - `//clearpage` → `@pagebreak`（囲みの中に入らないよう、囲みの手前へ置きます）
4. **画像処理** — Starter `images/` をコピー → WebP 化 → 元画像（png/jpg/gif）は削除。
5. **codes/ へのコピー** — Starter `source/` 配下をそのまま `codes/` へコピー。
6. **YAML 変換** — `catalog.yml` は行単位の書き換え（`PREDEF→PREFACE` 等のキー変換と `.re` 除去だけ）。部・コメント・コメントアウトした章は原文のまま残る。`config.yml` は `book.main_title` などを `book.yml` へ反映。`config-starter.yml` の `starter.pagesize` は同じ判型の標準プリセット（`B5` なら `b5_standard`）へ対応づけ。
7. **表紙の取り込み** — `config-starter.yml` の `frontcover_pdffile`・`backcover_pdffile` にある PDF を `covers/` へコピー。その 1 ページめを `frontcover_master.png`・`backcover_master.png` へ変換する。あわせて `book.yml` の `output.cover` を `master` に揃える。
8. **片付け** — Vivlio 側 `temp/` と Starter 側 `bookname-md/` を削除。

:::{.note}
**サイドイメージは `.re` 原稿を読み直して復元しています**

Re:VIEW の Markdown 変換は `//sideimage` を「画像 ＋ 空行 ＋ 本文」へ平坦化し、**囲みの終わりを示す印を残しません**。変換後の Markdown だけを見ても、どこまでが画像の脇に置く本文なのか決められないということです。

そこで取り込みでは、章ごとに `.re` 原稿を開き直します。`//sideimage` … `//}` の囲みが何ブロックぶんの本文を抱えていたかを読み取り、同じ範囲を `:::{.sideimage}` で囲みます。推測ではなく原文の構造をそのまま移すので、段落が複数あっても箇条書きを含んでいても崩れません。

画像名が原稿と一致せず置き場所を決められなかったときは、章名と画像名を挙げて 🟡 でお知らせします。その箇所だけ手で囲んでください。

同じ理由で `//output`・`//cmd` を原稿から復元しています。Re:VIEW は `//list` と `//output` を同じコードフェンスへ落とすため、変換後の Markdown だけではソースコードと実行結果を見分けられません。見分けがつかないと、実行結果にまで行番号が付いてしまいます。逐語ブロックは 1 命令につき必ず 1 フェンスなので、原稿とフェンスを出現順に突き合わせます。数が合わない章は**何もせず** 🟡 でお知らせします。
:::

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
  config/catalog.yml を更新しました（部・コメントは原文のまま）
[Step 6] config.yml を変換します
  config/book.yml を更新しました（コメント保持）
  表表紙の PDF をコピーしました: hyoshi.pdf → covers/
  frontcover_master.png を生成しました: covers/frontcover_master.png
🟡   裏表紙は雛形の見本画像のままです。
        対処: covers/backcover_master.png を自分の裏表紙画像に置き換えてください。
✅ インポートしました（contents/ に 7 章）
```

## インポート後の確認

インポートが完了したら、以下の点を確認してください。

1. `contents/` に Markdown が揃っているか
2. `.webp` 以外の画像が残っていないか
3. `covers/frontcover_master.png` と `backcover_master.png` が自分の表紙になっているか
4. `config/book.yml` の `book.main_title` などが期待どおりか（コメントが消えていないか）
5. `config/catalog.yml` の章名が `.re` を含んでいないか

確認が済んだら `vs build` を実行して、章構成・画像・表紙が意図どおりか PDF で確かめてください。索引・用語集を使う本なら、そのあと `vs index:auto` で辞書を作り直します。

:::{.notice}
画像は WebP のみ残るため、元画像が必要な場合は事前にバックアップを取ってください。
:::

## トラブルシューティング

| 症状 | 原因 | 解決策 |
| --- | --- | --- |
| Starter スクリプトが見つからない | `lib/ruby/review-markdownmaker.rb` が存在しない | Starter のルートを正しく指定する |
| `rake markdown` が失敗する | Starter 側 gem が未インストール | Starter ディレクトリで `bundle install`、または依存 gem を整える |
| Rouge が見つからない | gem が未インストール | `vs doctor --fix` or `gem install rouge` |
| 表紙 PDF がコピーされない | `frontcover_pdffile` が PNG など PDF 以外 | 取り込みは PDF のみ対応。`covers/frontcover_master.png` を直接置き換える |
| 裏表紙が雛形の見本画像のまま | Starter 側に `backcover_pdffile` の指定がない | `covers/backcover_master.png` を自分の画像に置き換える |
| 判型が雛形のまま | `starter.pagesize` が A5・B5 以外 | `config/book.yml` の `page.use` を自分で指定する |
| サイドイメージが囲まれない | 画像名が `.re` 原稿と一致しない | 🟡 が挙げた章と画像名の箇所を `:::{.sideimage}` … `:::` で手で囲む |
| `config/book.yml` の値が更新されない | 対応パスが見つからない | コメントやインデントが崩れていないか確認 |

:::{.column}
**ヒント**  
問題があれば `VS_DEBUG=1 vs import ...` で再実行し、ログから原因を特定するのが近道です。
:::
