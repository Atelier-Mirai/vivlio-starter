# Re:View Starter -> Vivlio Starter 移行仕様書

**File:** `review_to_vivlio_conversion.md`

## 1. 概要
本ドキュメントは、書籍執筆システム「Re:View Starter」のプロジェクトを、新システム「Vivlio Starter」へ移行するための変換ルールを定義する。

## 2. ディレクトリ構成の移行 (Directory Mapping)

| Re:View Starter (Source) | Vivlio Starter (Dest) | 処理内容 |
| :--- | :--- | :--- |
| `contents/` | `contents/` | ファイル名をリネームして移動（詳細は後述） |
| `images/` | `images/` | **ファイル/フォルダ名をリネームして移動**（詳細は後述） |
| `source/` | `codes/` | ディレクトリ名を変更してコピー |

## 3. ファイルのリネームとリインデックス (Renaming & Reindexing)

`contents/` および `images/` ディレクトリ内のリソースに対し、以下のルールで接頭辞（ナンバリング）を変更する。

### 3.1 対象リソース

* **Contents:** `contents/` 直下の `.re` ファイル (例: `01-intro.re`)
* **Images:** `images/` 直下のディレクトリまたはファイルで、Contentsと同様のナンバリング規則を持つもの (例: `images/01-intro/` や `images/01-intro.png`)

### 3.2 ナンバリング変換ルール

元ファイル/ディレクトリの番号に基づき、以下の通り変換を行う。

| 対象範囲 (Re:View) | 変換後 (Vivlio) | 変換ロジック |
| :--- | :--- | :--- |
| `00` (前書き) | `02` | 固定マッピング |
| `01` 〜 `89` (本文) | `11` 〜 `89` | **連番リインデックス** (後述) |
| `90` 〜 `98` (付録等) | `91` 〜 `97` | **連番リインデックス** (後述) |
| `99` (後書き) | `98` | 固定マッピング |

### 3.3 連番リインデックスの仕様 (Renumbering Logic)

本文(`01`〜`89`)および付録(`90`〜`98`)は、元の番号の大小関係を維持したまま、開始番号から順に隙間なく詰め直す。
**この計算結果は `contents/` と `images/` で共通して適用する。**

**【本文の処理例】**
1.  対象ファイル：`01`, `02`, `20`, `21` で始まるものが存在する場合
2.  変換開始番号：`11`
3.  変換結果：
    * `contents/01-xxx.re` -> `contents/11-xxx`
    * `images/01-xxx/` -> `images/11-xxx/`
    * `contents/20-yyy.re` -> `contents/13-yyy` (連番詰め)
    * `images/20-yyy/` -> `images/13-yyy/`

**【オーバーフロー処理】**
* 変換後の番号が範囲上限（本文なら`89`、付録なら`97`）を超えた場合、それ以降のファイルは変換を行わずスキップし、警告を出力する。

### 3.4 ファイル形式の変換
* 移行後のファイル拡張子は、最終的に `.md` (Markdown) とする必要がある。
* 本移行スクリプト完了後、別途変換コマンドを実行し `.re` から `.md` への変換を行うフローとする。

## 4. 設定ファイルの変換 (Config Merging)

Vivlio Starter 環境に存在する **既存の `book.yml` を読み込み**、Re:View の `config.yml` から抽出した値で **該当フィールドを上書き（Update）** する。

### 4.1 基本マッピング（上書きルール）

| Re:View (`config.yml`) | Vivlio (`book.yml`) | 処理 |
| :--- | :--- | :--- |
| `bookname` | `project.name` | 上書き |
| `language` | `project.language` | 上書き |
| `booktitle` | `book.main_title` | 上書き |
| `subtitle` | `book.subtitle` | 上書き |
| `history` (日付) | `book.release` | ネストされた配列から日付文字列を抽出し、上書き |
| `pubevent_name` | `book.series` | 上書き |

### 4.2 特殊フィールドのマッピング（加工して上書き）

#### 著者 (`aut` -> `book.author`)
* `config.yml` の `aut` リストの先頭要素の `name` を取得し、`book.yml` の `book.author`（単一文字列）に上書きする。

#### 発行者・連絡先 (`additional` -> `book.publisher` / `book.contact`)
`config.yml` の `additional` を解析し、該当キーが存在する場合のみ `book.yml` を更新する。

1.  **発行者**
    * `key: 発行者` があれば、その値を `book.publisher` に上書き。
2.  **連絡先**
    * `key: 連絡先` があれば、その値を解析。
    * **メールアドレス形式のみ** を抽出し、`book.contact` (リスト) を**完全に置き換える**（マージではなく置換）。
    * URL (`http`等で始まる文字列) は除外する。