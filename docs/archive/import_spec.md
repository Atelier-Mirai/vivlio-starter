# Vivlio Starter Import Spec

Re:VIEW Starter（以下「Starter」）プロジェクトを vivlio-starter に取り込む `vs import` コマンドの仕様である。

---

## 1. 想定ディレクトリとクリーンアップ

| Starter 側 | Vivlio 側 | 処理 |
| --- | --- | --- |
| `contents/*.re` | `contents/*.md` | Markdown 化＋追従変換 |
| `images/*` | `images/*.webp` のみ | WebP 変換＋元画像削除 |
| `source/*` | `codes/*` | ディレクトリ構造を維持してコピー |

- `vs import` 開始時に `contents/`, `images/`, `codes/` をまとめて削除し、空の状態から再生成する。`--force` なしの場合は確認プロンプトを表示する。
- 削除対象はプロジェクトルート直下の 3 ディレクトリのみ。`temp/` 等には触れない。
- 以降の処理は必ず Vivlio プロジェクトルートで実行する。

---

## 2. 実行フロー

1. **Starter ディレクトリ検証**: `lib/ruby/review-markdownmaker.rb` / `review-markdownbuilder.rb` の存在を必須とする。
2. **Cleanup**: 既存 `contents/`, `images/`, `codes/` を削除・再生成。
3. **Markdown 生成**: Starter 側で `rake markdown` を自動実行（`bookname-md/` を生成）。既存の `*-md/` が有効なら再利用する。
4. **Markdown 追従変換**: 生成物を `temp/` にコピーし、追従変換を加えたのち `contents/` へ移動。
5. **画像処理**: `images/` をコピー → WebP 変換 → 元画像削除。必要なら waifu2x を利用。
6. **source → codes**: `source/` 内のファイルを `codes/` にコピー。
7. **YAML 変換**: `catalog.yml`, `config.yml`, `config-starter.yml` を Vivlio 用設定に書き換え。コメントは保持。
8. **frontcover_pdffile**: `config-starter.yml` に指定があれば `/images/` から `covers/` へコピーし、`book.yml` の `output.cover.front` を更新。
9. **片付け**: Vivlio 側 `temp/` 削除、Starter 側 `bookname-md/` も削除。

---

## 3. Markdown 変換仕様

### 3.1 基本ルール

| 処理 | 仕様 |
| --- | --- |
| img タグ → Markdown | `<img src=".../foo.png">` → `![](foo.webp)` |
| 画像パス縮約 | `![alt](./images/path/foo.jpg)` → `![alt](foo.webp)`（`alt` 内の `[]` も許容） |
| 改行タグ | 単独 `<br>` 行を `{.aki}` に置換 |
| `[abstract]` 等 | `[abstract]...[/abstract]` → `:::{.chapter-lead} ... :::`（タグごとにクラス変更） |
| `[column]` | タイトル任意。`::: {.column}\n<title>\n<body>\n:::` |
| `[quote]` | 引用部の各行先頭に `>` を付与し、末尾に空行を追加 |
| dl/dt/dd | `<dl><dt>A</dt><dd>B</dd>...</dl>` → `- **A**\n    B`。改行継続箇所は 2 スペース挿入 |
| HTML table | `<div class="table">` + `<table>` を Markdown 表へ。caption は `**...**` の見出しとして出力 |
| ルビ | `漢字（かな）` / `漢字（カナ）` → `{漢字|かな}`。直前の連続漢字のみ対象 |

### 3.2 コードブロック

- `<span class="caption">▼foo.rb</span>` の直後にあるコードフェンスを ```` ```rb:foo.rb ```` へ変換（拡張子なしは `text`）。
- **言語推定**: 言語指定のないフェンスは Rouge による自動推定を行う。
  - 行頭が `$` または `%` のコマンド行を含む場合は強制的に `zsh`。
  - 既に言語があるフェンスは変更しない。
  - Rouge で推定できない場合は `text`。
  - マッピング: `javascript→js`, `typescript→ts`, `markdown→md`, `plaintext→text`, `bash/shell→zsh`。
  - Rouge を使用するため `vs doctor --fix` は `gem install rouge` を行う。

---

## 4. 画像と PDF

### 4.1 WebP パイプライン

1. Starter の `images/` を Vivlio の `images/` へディレクトリ構造を維持したままコピー。
2. `ResizeCommands.execute_resize_medium('images')` で WebP 化。
3. `.png/.jpg/.jpeg/.gif` を完全削除し、`images/` には WebP のみ残す。

### 4.2 frontcover_pdffile

- `config-starter.yml` に `starter.frontcover_pdffile: hyoshi.pdf` がある場合:
  - Starter 側 `/images/hyoshi.pdf` を `vivlio-starter/covers/hyoshi.pdf` にコピー（同名は上書き可）。
  - `config/book.yml` の `output.cover.front` を `hyoshi.pdf` に更新。
  - PDF 以外（PNG 等）が指定されていても処理しない（スキップ）。

---

## 5. YAML / メタデータ変換

### 5.1 catalog.yml

| Starter キー | Vivlio キー |
| --- | --- |
| `PREDEF` | `PREFACE` |
| `CHAPS` | `CHAPTERS` |
| `APPENDIX` | `APPENDICES` |
| `POSTDEF` | `POSTFACE` |

- `.re` 拡張子を再帰的に取り除く。例: `00-preface.re` → `00-preface`。
- `Build::CatalogUpdater` を用い、コメント・空行を保持したまま書き換える。

### 5.2 config.yml → config/book.yml

| Starter キー | Vivlio キー | 備考 |
| --- | --- | --- |
| `booktitle` | `book.main_title` | 改行はスペースに置換 |
| `subtitle` | `book.subtitle` | 〃 |
| `language` | `book.language` | |
| `bookname` | `project.name` | 同時に `project.version = "0.1.0"` を固定値で設定 |
| `aut` | `book.author` | 配列の場合は最初の `name` を採用 |
| `additional.key = 発行者` | `book.publisher` | テキスト抽出後に空白除去 |
| `additional.key = 連絡先` | `book.contact` | @ を含む値のみ採用 |
| `history[0]` | `book.release` | 最初の履歴を採用 |
| `pubevent_name` | `book.series` | |
| `starter.pagesize` | `page.use` | `B5→b5_airy`, `A5→a5_compact`, その他 `a4_standard` |

- 既存コメントを保持するため、YAML を文字列で読み込み、対象パスの値のみ置換する。
- 値は常に UTF-8 でダブルクォートし、`"` / `\` はエスケープする。

### 5.3 output.cover

- `frontcover_pdffile` がコピー済みであれば `output.cover.front` を必ず更新する。

---

## 6. 一時ファイルとクリーンアップ

- Vivlio 側 `temp/` は `contents/` への移動後に削除。
- Starter 側 `bookname-md/` も import 完了時に削除（`config.yml` の `bookname` + `-md`）。
<!-- - 旧仕様の `temp_manual` など手動コピー用ディレクトリは廃止済み。 -->

---

## 7. 依存ツール (`vs doctor --fix`)

不足している場合は `--fix` が Homebrew / npm / gem を用いて自動導入する。

| ツール | 目的 |
| --- | --- |
| node / npm | Vivliostyle CLI, textlint の実行 |
| Vivliostyle CLI (@vivliostyle/cli) | PDF ビルド |
| textlint & 推奨ルール | 原稿チェック |
| qpdf / pdfinfo / Ghostscript / ImageMagick | PDF・画像処理 |
| waifu2x-ncnn-vulkan | 画像アップスケール |
| mecab | 索引用読み推定 |
| **rouge (gem)** | Markdown コードブロック言語推定 |

Rouge は `gem install rouge` で導入し、存在チェックも行う。

---

## 8. テストとリファクタリング

- `import.rb` は責務ごとに `Import::MarkdownConverter` / `Import::ImageProcessor` / `Import::YamlProcessor` へ分離して実装する。
- Minitest のテストケースは既存 `test/` ディレクトリに追加し、特に Markdown 追従変換周りを重点的に網羅する。
- Ruby 4.0 前提の `ruby-refactoring` スキルに従い、最新構文・コメント整備で保守性を高める。

---

## 9. コマンド例とヒント

```zsh
vs new mybook
cd mybook
vs import ../review_starter_directory          # 基本形
vs import --force ../review_starter_directory  # 確認なし
```

- Starter 側で `rake markdown` を事前実行する必要はない（import 時に自動実行）。
- 画像は WebP のみが `images/` に残る。元画像が必要な場合は import 前に別途バックアップを取ること。
- 失敗時は `VS_DEBUG=1` を付けて再実行し、スタックトレースを確認する。

---

## 10. 参考リソース

- `docs/specs/import_spec.md` … 追従変換・YAML 変換の詳細仕様（本書）
- `lib/vivlio/starter/cli/import/*.rb` … `vs import` コマンド関連の実装コード
- `test/vivlio/starter/cli/import/*_test.rb` … Markdown 変換や画像処理などの挙動テスト

仕様変更時は本ファイルとともに、実装・テストの更新も忘れずに行うこと。

---

本仕様書を最新ソースコードと同時に更新し、将来の保守時に参照すること。
