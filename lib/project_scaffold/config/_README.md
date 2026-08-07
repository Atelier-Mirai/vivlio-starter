# config/ — 設定ファイルディレクトリ

書籍プロジェクトの設定をまとめた場所です。
多くの本では `book.yml` と `catalog.yml` だけを触れば足ります。

## ファイル一覧

「編集」欄は、そのファイルを誰が書くかを表します。

| ファイル | 役割 | 編集 |
|----------|------|------|
| `book.yml` | 書籍のメタデータとビルド設定（**最重要**） | 著者が書く |
| `catalog.yml` | ビルドに含める章と、その順序 | 著者が書く（`vs create` も追記） |
| `page_presets.yml` | 判型プリセット（紙サイズ・余白・文字サイズ・行送り） | ふつうは触らない |
| `talk.yml` | 会話文記法 `:::{.talk}` の話者と表示設定 | 使うときだけ書く（任意） |
| `.textlintrc.yml` | textlint の校正ルール本体 | 必要なら書く |
| `textlint_allowlist.yml` | 校正の対象から外す語 | 著者が書く |
| `textlint_rewrite.yml` | 表記揺れの言い換え辞書（prh） | 著者が書く |
| `textlint_dictionaries/` | 同梱の言い換え辞書（9 ファイル） | 触らない |
| `spellcheck_allowlist.yml` | 綴り誤りと指摘しない語 | `vs lint --register` が書く |
| `spellcheck_dictionaries/` | 同梱の英単語辞書（53 ファイル） | 触らない |
| `index_glossary_terms.yml` | 索引・用語集の登録語 | `vs index` が書く |
| `index_glossary_rejected.yml` | 索引・用語集から外した語 | `vs index` が書く |

**`book.yml` / `catalog.yml` / `page_presets.yml` の 3 つは必須**です。
欠けているとコマンドが起動しません。壊してしまったときは `vs doctor --fix` で
雛形から復元できます（元のファイルは `.bak` へ退避されます）。

## どこに書けばよいか

設定の置き場所は役割で分かれています。迷ったらこの表を引いてください。

| したいこと | 書く場所 |
|---|---|
| 本の作り方を決める（判型・書体・出力形式・索引など） | `book.yml` |
| 章を足す・順序を変える | `catalog.yml` |
| 文体を選ぶ（一文の長さ、和欧間スペース、末尾長音など） | `book.yml` の `lint:` |
| 校正ルールそのものを変える（漢字の連続数など） | `.textlintrc.yml` |
| **この語は直さなくてよい**と決める | `textlint_allowlist.yml` |
| **この語は綴り誤りではない**と決める | `spellcheck_allowlist.yml` |
| 独自の言い換えを決める（「ユーザ」→「ユーザー」など） | `textlint_rewrite.yml` |

## book.yml について

書籍タイトル・著者名・判型・出力形式など、プロジェクト全体の設定を管理します。
まずここを編集してください。

先頭に【主なセクション】の目次があり、本文のセクションと同じ順に並んでいます。
見やすいようにコメントを付けていますので、参考にしてください。

```yaml
# ======= セクション =======
  # ------- 小見出し -------
  key: value # このキーの説明
             # 続きはここへぶら下げる
             # 選択肢は「値 … 説明」の形で並べる
```

## catalog.yml について

ビルドに含める章と順序を決めます。`vs create` で章を作ると自動で追記されます。
順序を変えるときはこのファイルを直接編集してください。
行をコメントアウトすれば、その章だけビルドから外せます。

## page_presets.yml について

`a5_compact` `b5_standard` のような判型プリセットの中身です。
`book.yml` の `page.use` で選びます。独自のプリセットを足すこともできます。

## talk.yml について

会話文記法 `:::{.talk}` の話者（`name` / `color` / `avatar`）と表示設定を書きます。
**このファイルは任意**です。会話文を使わないなら、まるごと削除して構いません。

## 索引・用語集の辞書について

`index_glossary_terms.yml` と `index_glossary_rejected.yml` は著者が選んだ用語が蓄積されていく索引・用語集の為の辞書です。
`vs index:auto` コマンドを実行すると、`_index_glossary_review.md` が作成されますので、索引や用語集にしたい語句を編集し、`vs index:apply`** を実行してください。システムにより、`index_glossary_terms.yml` と `index_glossary_rejected.yml` が自動生成されます。

消すときは `vs clean --index-dictionaries` を使ってください
（確認プロンプトが出ます）。
