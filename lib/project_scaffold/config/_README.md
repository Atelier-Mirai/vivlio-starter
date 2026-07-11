# config/ — 設定ファイルディレクトリ

書籍プロジェクトの各種設定ファイルを配置するディレクトリです。

## 主要ファイル

| ファイル | 役割 |
|----------|------|
| `book.yml` | 書籍のメタデータ・ビルド設定（最重要） |
| `catalog.yml` | ビルド対象の章リスト（章の順序を定義） |
| `page_presets.yml` | 用紙サイズ等のプリセット定義 |
| `index_glossary_terms.yml` | 索引・用語集の登録済み用語(vs indexにより生成) |
| `index_glossary_rejected.yml` | 索引・用語集の除外用語(vs indexにより生成) |
| `.textlintrc.yml` | textlint の校正ルール設定 |
| `textlint_allowlist.yml` | textlint の許可リスト（誤検知を除外） |
| `textlint_prh.yml` | 表記揺れ検出の辞書設定 |
| `textlint_dictionaries/` | 表記揺れ辞書ファイル群 |

## book.yml について

書籍タイトル・著者名・出版情報・ビルドオプションなど、プロジェクト全体の設定を管理する中心ファイルです。まずここを編集して書籍情報を設定してください。

## catalog.yml について

ビルドに含める章の順序を定義します。`vs create` で章を作成すると自動追記されます。章の順序変更はこのファイルを直接編集してください。

## 用紙サイズ等のプリセット定義
`page_presets.yml` には、用紙サイズ等のプリセット定義が記載されています。著者独自の指定を行うことも可能です。

## 索引辞書ファイルについて

`index_glossary_terms.yml` と `index_glossary_rejected.yml` は `vs index:auto` / `vs index:apply` コマンドで管理されます。著者が登録した用語データが蓄積されるため、削除する際は `vs clean --index-dictionaries` で確認プロンプト付きで削除できます。
