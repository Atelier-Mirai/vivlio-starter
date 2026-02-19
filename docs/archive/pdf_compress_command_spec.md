# vs pdf:compress コマンド仕様書

## 概要
`vs pdf:compress` コマンドは、指定された PDF ファイルを圧縮し、圧縮後の PDF ファイルを生成するためのユーティリティです。  
入力ファイル名および出力ファイル名の指定に応じて動作を自動的に切り替えます。

---

## コマンド書式

```bash
vs pdf:compress INPUT [OUTPUT]
```

通常の CLI 利用では、圧縮対象となる `INPUT` を必ず指定します。  
引数無しの `vs pdf:compress` は、`build.rb` や `build_helper.rb` などからの **内部処理専用** の呼び出しとして扱います。

---

## 引数

| 引数 | 必須 | 説明 |
|------|------|------|
| `INPUT` | はい | 圧縮対象とする PDF ファイル名。通常はユーザーが明示的に指定する。 |
| `OUTPUT` | いいえ | 圧縮後の出力ファイル名。省略時は `INPUT` に `_compressed` をサフィックスとして付加した名前で出力する。 |

※ 引数無しで呼び出された場合は、`config/book.yml` の設定をもとに内部的に `INPUT` / `OUTPUT` が決定されます（後述）。

---

## 動作仕様

1. 通常の CLI 利用時の挙動（`INPUT` 必須）

| 実行例 | 入力ファイル | 出力ファイル | 動作概要 |
|--------|---------------|---------------|------------|
| `vs pdf:compress filename.pdf` | `filename.pdf` | `filename_compressed.pdf` | 指定されたファイルを圧縮。 |
| `vs pdf:compress input.pdf output.pdf` | `input.pdf` | `output.pdf` | 入力・出力を明示指定して圧縮。 |

2. 引数無しの `vs pdf:compress` は、ビルドスクリプトからの内部利用専用とする。

   - 入力ファイル: `config/book.yml` の `pdf.output_file` を使用（未設定時は `output.pdf`）。
   - 出力ファイル: `pdf.output_file_compressed` を使用（未設定時は `output_compressed.pdf` 相当）。
   - この挙動は CLI の `--help` には掲載せず、`build.rb` / `build_helper.rb` などからの内部呼び出しを想定する。

3. 出力ファイル名に `_compressed` サフィックスが自動付与されるのは、`OUTPUT` が明示されていない場合のみ。  
4. 出力フォーマットは常に PDF。ファイルの拡張子は `.pdf` とする。

---

## 使用例

- **例1（内部処理向け・CLIヘルプ非掲載）:**  
  `vs pdf:compress`

  `config/book.yml` の設定に従い、例えば `output.pdf` を読み込み、`output_compressed.pdf` を生成する。  
  主に `build.rb` / `build_helper.rb` などからの内部呼び出しを想定し、一般ユーザー向けの CLI では `INPUT` を必ず指定する。

- **例2:**  
  `vs pdf:compress project_1.2.pdf`

  `project_1.2.pdf` を圧縮し、`project_1.2_compressed.pdf` を生成。

- **例3:**  
  `vs pdf:compress draft.pdf final.pdf`

  `draft.pdf` を圧縮し、`final.pdf` として出力。

---

## 備考

- フルビルドでは `projectname_version.pdf` が生成されるため、この仕様で自動的に `projectname_version_compressed.pdf` が出力される。  
- 単章ビルド（例: `16-ai.pdf`）でも同様の動作が適用される。  
- 引数無しの `vs pdf:compress` は、旧仕様 (`output.pdf -> output_compressed.pdf`) との互換性を維持するために残しているが、主に `build.rb` / `build_helper.rb` からの **内部利用向け** 挙動として扱う。  
- 一般ユーザー向けの利用案内では、`vs pdf:compress INPUT [OUTPUT]` を基本形として示す。