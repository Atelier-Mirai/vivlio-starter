# Re:VIEW Starter からの移行仕様

## 概要

Re:VIEW Starter（以下「Starter」）プロジェクトを vivlio-starter プロジェクトへ移行する際のファイル配置・変換ルールを定義する。

## 想定ディレクトリ構成

- `review_starter_directory/`
  - `contents/`
  - `images/`
  - `source/`
- `vivlio-starter/`
  - `contents/`
  - `images/`（webp 化後）
  - `codes/`

| Starter | vivlio-starter | 変換内容 |
| --- | --- | --- |
| `contents/*.re` | `contents/*.md` | Markdown 化 |
| `images/*` | `images/*.webp` | WebP 変換、解像度補完 |
| `source/*` | `codes/*` | 変換なし（ディレクトリ構造維持） |

## インポート前のクリーンアップ方針

- `vs import` 実行時には、既存の `contents/` `images/` `codes/` を一度削除してからインポートを行う。  
  - サンプル原稿とインポート結果が混在すると著者が編集しづらいため、空の状態から再生成する。  
  - 将来的に差分移行が必要な場合は、別途バックアップや除外オプションを検討する。
- 削除するディレクトリはプロジェクトルートのものに限定し、`temp/` や `fonts/` など他ディレクトリへは影響を与えない。
- 削除前に警告メッセージを表示し、ユーザーが「はい」を選択した場合のみ削除を実行する（`--force` 指定時はすべての確認プロンプトを省略して処理を継続し、CI 等での無人実行を可能にする）。

## 実行コマンド例

```zsh
vs new mybook
cd mybook
vs import ../review_starter_directory
```

`review_starter_directory` は Starter プロジェクトのルートを指し、上記のディレクトリ構成がそろっていることを前提とする。

## 変換仕様

### `.re` → `.md`

1. Starter 同梱のスクリプトを使用して Re:VIEW 原稿を Markdown へ変換する。  
   - `review_starter_directory/lib/ruby/review-markdownmaker.rb`  
   - `review_starter_directory/lib/ruby/review-markdownbuilder.rb`
2. 例: `system("ruby review_starter_directory/lib/ruby/review-markdownmaker.rb")` を実行すると `.md` が生成される。
3. 生成された Markdown を vivlio-starter 側の `temp/` に配置し、`scripts/review_to_vivlio_md.rb` で追従変換を実施する。
   - `scripts/review_to_vivlio_md.rb` は、Starter の `lib/ruby/review-markdownmaker.rb` と `lib/ruby/review-markdownbuilder.rb` を用いて生成された Markdown を変換するための雛形となる。
   - ここでいう「変換スクリプト実行」とは、上記 2 つの Starter 付属スクリプトを起動して Markdown を得る処理を指す。該当ファイルが見つからない場合はエラーで終了させる。
4. 調整後のファイルを `contents/` へ移動する。

### 画像（`jpg` / `gif` / `png`）→ `webp`

- Starter で使用しているビットマップ画像はすべて WebP 化する。
- 低解像度画像は waifu2x を用いてアップスケールし、Vivliostyle での表示品質を担保する。
- 変換には `vs build` Step 2（optimize images）と同じ `ResizeCommands`（標準プリセット: quality=85 / max_px=1600 / webp:method=6）を用いる。これによりビルド時の最適化基準と揃えられる。
- ImageMagick は `vs doctor --fix` で導入されている前提だが、環境に存在しない場合はエラー終了（追加のフォールバック処理は行わない）。

### `source/` → `codes/`

- `source/` 以下のファイルやサブディレクトリをそのまま `codes/` 以下へコピーする。
- 変換処理は行わないが、相対パスが変わる場合は参照箇所の更新が必要になる。

## メタデータ関連

### `catalog.yml`

`catalog.yml` は基本的にそのまま移行するが、節名キーを Vivlio 形式に合わせて補正する。

| Starter | vivlio-starter |
| --- | --- |
| `PREDEF` | `PREFACE` |
| `CHAPS` | `CHAPTERS` |
| `APPENDIX` | `APPENDICES` |
| `POSTDEF` | `POSTFACE` |

また、`00-preface.re` のように、starterでは、拡張子を含めてファイル名を指定するが、vivlio-starterでは、拡張子を除いたファイル名を指定するので、`.re`を除いたファイル名を指定するようにする。

### `config.yml` → `book.yml`

Starter の `config.yml` から値を抽出し、 vivlio-starter の `book.yml` に投入する。

| Starter キー | vivlio-starter キー | 備考 |
| --- | --- | --- |
| `booktitle` | `main_title` |  |
| `subtitle` | `subtitle` |  |
| `language` | `language` |  |
| `bookname` | `project_name` |  |
| `aut` | `author` |  |
| `additional.key: 発行者` | `publisher` | 値のみを移す |
| `additional.key: 連絡先` | `contact` | メールアドレスのみ |
| `history[0]` | `release` | 最初の履歴を採用 |
| `pubevent_name` | `series` |  |

### `config-starter.yml` → `config/book.yml`

- `pagesize` を `page.use` に対応付ける。
- `pagesize: B5` → `page.use: b5_airy`
- `pagesize: A5` → `page.use: a5_compact`

その他のキーは別途検討し、必要に応じて `config/book.yml` に追加していく。
