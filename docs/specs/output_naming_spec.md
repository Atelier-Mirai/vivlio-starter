# 💾 出力ファイル名の命名規則仕様

## 1. 命名規則の基本構造

`vs build` コマンドで生成される最終出力ファイル名は、以下の3つの要素を組み合わせた構造となります。

$$\text{ファイル名} = \text{ベース名} \quad + \quad [\text{ターゲット接頭辞}] \quad + \quad [\text{バージョン}] \quad + \quad \text{拡張子}$$

### 1.1. 設定パラメータ

ファイル名の各要素は、`book.yml` の以下の設定を参照します。

| 設定項目 | 値の由来 |
| :--- | :--- |
| **ベース名** | `project.name` (例: `vivlio_starter`) |
| **バージョン** | `project.version` (例: `v1.0.0`) |
| **ターゲット** | `output.targets` (例: `pdf`, `print_pdf`, `epub`) |
| **バージョン有無** | `output.filename.include_version` (Boolean) |

## 2. ターゲット別ファイル名定義

ファイル名にバージョンを含めるかどうか (`output.filename.include_version`) に応じて、以下の規則でファイル名が決定されます。

| ターゲット | バージョンなし (`false`) | バージョンあり (`true`) | 構造の定義 |
| :--- | :--- | :--- | :--- |
| **`pdf`** | `vivlio_starter.pdf` | `vivlio_starter_v1.0.0.pdf` | `[ベース名]_[v] [バージョン] .pdf` |
| **`print_pdf`** | `vivlio_starter_print.pdf` | `vivlio_starter_print_v1.0.0.pdf` | `[ベース名]_print_[v] [バージョン] .pdf` |
| **`epub`** | `vivlio_starter.epub` | `vivlio_starter_v1.0.0.epub` | `[ベース名]_[v] [バージョン] .epub` |

### 補足事項: ファイル名要素の詳細

* **バージョンの形式**: バージョン番号の前には、接頭辞「$\text{v}$」が付きます（例: `_v1.0.0`）。
* **`print_pdf` ターゲット接頭辞**: `print_pdf` ターゲットの場合、ファイル名には `_print` が含められ、一般の $\text{PDF}$ と区別されます。