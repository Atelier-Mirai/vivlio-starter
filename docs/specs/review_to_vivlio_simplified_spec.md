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
| `00` (前書き) |  | contents/, images/ともに移行しない |
| `01` 〜 `89` (本文) | `11` 〜 `89` | **連番リインデックス** (後述) |
| `90` 〜 `98` (付録等) | `91` 〜 上限は定めず連番で移行する | **連番リインデックス** (後述) |
| `99` (後書き) |  | contents/, images/ともに移行しない |

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
* 変換後の番号が範囲上限（本文なら`89`、付録なら`97`）を超えた場合、
本文は、89を越えることはないが、付録については上限チェックは行わない。付録は 91 + index として実装して良い。

### 3.4 ファイル形式の変換
* 移行後のファイル拡張子は、最終的に `.md` (Markdown) とする必要がある。
* 本移行スクリプト完了後、別途変換コマンドを実行し `.re` から `.md` への変換を行うフローとする。

## 対象ディレクトリ
| ディレクトリ名             | .reファイル数  |
| :------------------------- | :------------- |
| book_janken                | 20             |
| book_sakura_fubuki         | 16             |
| book_study_js              | 23             |
| book_yutakana_website_old  | 22             |

これらのディレクトリ内のファイルを、source_material内の対応するディレクトリ(contents/, images/, codes/)へ移行する。

book_janken ~ book_yutakana_website_oldまでの全部の章を連番にして、
/Users/mirai/projects/vivlio-starter/source_material/contents/ と
/Users/mirai/projects/vivlio-starter/source_material/images/ に移行する。

images/logo.png のような 番号なしの共通画像 は、存在しないはずであるが、もし存在する場合は、logo-2.png などとリネームして移行する。

source/ → codes/ の中身は「そのままコピー」で良い。codes/ のディレクトリ構造はフラットで良い。もし重複するファイル名があれば、filename-2.js, filename-3.js などとリネームして移行する。

4冊を連番にするときの「並び順」 例）book_janken → book_sakura_fubuki → book_study_js → book_yutakana_website_old
の順に、
各ディレクトリ内で 01-*.re, 02-*.re, … を番号順に並べてから移行します。

つまり、11から30くらいまでは、jankenの章を移行する。
31から50くらいまでは、sakura_fubukiの章を移行する。
51から70くらいまでは、study_jsの章を移行する。
71から90くらいまでは、yutakana_website_oldの章を移行する。
ようになります。

付録 (90〜98) も、本文と同様に
book_janken → … → book_yutakana_website_old の順で、
各ディレクトリ内を番号順に並べてから 91 以降の連番を割り当てる。



