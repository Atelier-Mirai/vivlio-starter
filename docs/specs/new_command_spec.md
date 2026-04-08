# `vs new` コマンド 実装仕様書

**対象バージョン**: Vivlio Starter v0.36.0
**作成日**: 2026-04-08
**CLIフレームワーク**: Samovar ベース

---

## 1. 概要

`vs new <project_name>` コマンドは、Vivlio Starter の新規書籍プロジェクトを作成するコマンドである。

処理の流れは以下のとおり。

1. 引数・オプションのバリデーション
2. 既存ディレクトリの有無チェック
3. 対話形式でユーザーから書籍情報を収集（`--yes` で省略可）
4. `lib/project_scaffold/` のファイル一式を展開し、`book.yml` を書き換える
5. `vs doctor --fix` を自動実行して執筆環境を一括セットアップ
6. 完了メッセージを表示

---

## 2. コマンドシグネチャ

```
vs new <project_name> [options]
```

### 引数

| 引数 | 必須 | 説明 |
|---|---|---|
| `project_name` | ✅ | プロジェクト名。ディレクトリ名および `project.name` として使用される |

### オプション

| オプション | 説明 |
|---|---|
| `--yes` | 対話をスキップし、デフォルト値で book.yml を生成する（上級者向け） |
| `--force` | 既存ディレクトリへの追加展開を許可する（詳細は §5 参照） |
| `--log=debug` | デバッグログを出力する（`vs build --log=debug` と同じ挙動） |

### 使用例

```bash
vs new mybook
vs new mybook --yes
vs new mybook --force
vs new mybook --yes --force
```

---

## 3. ファイル構成

### 3.1 Scaffold ソースの配置（Gem 内部）

```
lib/
  project_scaffold/
    contents/
      00-preface.md
      11-install.md
      ...（サンプル原稿）
    images/
      ...（サンプル画像）
    covers/
      ...（サンプル表紙）
    data/
      ...（サンプルYAML）
    templates/
      ...（章テンプレート）
    sources/
      ...（執筆資料）
    codes/
      ...（サンプルコード）
    stylesheets/
      style.css
    config/
      book.yml              ← 置換処理の対象（ERBではない）
      catalog.yml
      page_presets.yml
      index_glossary_terms.yml
    vivliostyle.config.js   ← vs build 実行時に上書きされるため置換不要
    entries.js
    package.json
    Gemfile
```

**注意**:
- `book.yml` は ERB テンプレートではなく、通常の YAML ファイルとして収録する。
- `new` コマンドが展開後に文字列置換で値を書き込む（詳細は §4 参照）。
- `vivliostyle.config.js` は `vs build` 実行時に Vivlio Starter が適切に上書きするため、`new` コマンドでの置換は不要。そのままコピーする。
- 空ディレクトリは `project_scaffold/` 内に存在しないため、`.keep` ファイルは不要。

### 3.2 展開後のプロジェクト構造

```
<project_name>/
  contents/
  images/
  covers/
  data/
  templates/
  sources/
  codes/
  stylesheets/
    style.css
  config/
    book.yml          ← 書き換え済み
    catalog.yml
    page_presets.yml
    index_glossary_terms.yml
  vivliostyle.config.js
  entries.js
  package.json
  Gemfile
  node_modules/       ← vs doctor --fix により生成
```

---

## 4. book.yml の書き換え

ERB は使用しない。`project_scaffold/config/book.yml` 内にプレースホルダーを埋め込んでおき、コピー後に `String#gsub` で置換する。この方式は既存の `generate_content_from_template` における `{{TITLE}}` 置換と同じアプローチである。

### 4.1 プレースホルダー一覧

`project_scaffold/config/book.yml` に以下のプレースホルダーを記述しておく。

| プレースホルダー | 置換後の値 | 対応する book.yml のキー |
|---|---|---|
| `{{MAIN_TITLE}}` | 対話で入力された書籍名（デフォルト: `"新しい本"`) | `book.main_title` |
| `{{SUBTITLE}}` | 対話で入力された副題（デフォルト: `""` → 空文字） | `book.subtitle` |
| `{{AUTHOR}}` | 対話で入力された著者名（デフォルト: `""`) | `book.author` |
| `{{PUBLISHER}}` | 対話で入力された発行者名（デフォルト: `""`) | `book.publisher` |
| `{{PROJECT_NAME}}` | コマンド引数の `project_name` | `project.name` |

### 4.2 置換処理のイメージ

```ruby
content = File.read(src_path, encoding: "utf-8")
  .gsub("{{MAIN_TITLE}}",   answers[:main_title])
  .gsub("{{SUBTITLE}}",     answers[:subtitle])
  .gsub("{{AUTHOR}}",       answers[:author])
  .gsub("{{PUBLISHER}}",    answers[:publisher])
  .gsub("{{PROJECT_NAME}}", project_name)
File.write(dest_path, content, encoding: "utf-8")
```

### 4.3 `project_scaffold/config/book.yml` 内の記述例

```yaml
book:
  main_title: "{{MAIN_TITLE}}"
  subtitle: "{{SUBTITLE}}"
  ...
  author: "{{AUTHOR}}"
  publisher: "{{PUBLISHER}}"

project:
  name: "{{PROJECT_NAME}}"
```

---

## 5. 対話フロー（インタラクティブモード）

`--yes` が指定されていない場合、以下の順で質問する。
ユーザーが何も入力せずに Enter を押した場合はデフォルト値を使用する。

```
Vivlio Starter へようこそ！新しい書籍プロジェクトを作成します。

書籍名を入力してください（例: はじめての Ruby）: [入力待ち]
副題を入力してください（任意。Enter でスキップ）: [入力待ち]
著者名を入力してください（例: 山田 太郎）: [入力待ち]
発行者・サークル名を入力してください（例: アトリヱ未來）: [入力待ち]

以下の設定でプロジェクトを作成します。

  プロジェクト名: mybook
  書籍名:         はじめての Ruby
  副題:           （なし）
  著者:           山田 太郎
  発行者:         アトリヱ未來

よろしいですか？ [Y/n]: [入力待ち]
```

「n」が入力された場合は中断し、再実行を促す。

```
中断しました。もう一度 vs new mybook を実行してください。
```

### 5.1 `--yes` モード（スキップ）

すべての項目にデフォルト値を適用し、確認プロンプトも省略する。
book.yml は後から直接編集できるため、上級者はこちらが快適。

```
Vivlio Starter: プロジェクト "mybook" を作成しています...（デフォルト設定）
```

### 5.2 完了後のメッセージ（インタラクティブモード共通）

対話・`--yes` いずれの場合も、展開完了後に以下を表示する。

```
book.yml で書籍の詳細設定を変更できます。
書き方の参考は contents/ 内のサンプルファイルをご覧ください。
```

---

## 6. 既存ディレクトリの扱い

### 6.1 デフォルト（`--force` なし）

エラーメッセージを表示して中断する。

```
エラー: ディレクトリ "mybook" はすでに存在します。
上書き展開する場合は --force オプションを指定してください。
  vs new mybook --force
```

### 6.2 `--force` あり

- scaffold 内の各ファイルについて、展開先に同名ファイルが**存在しない**場合のみコピーする。
- 既存ファイルは**スキップ**する（上書きしない）。原稿や設定の編集内容を保護するため。
- スキップされたファイル名はログに出力する。

```
スキップ: mybook/config/book.yml（既存ファイルを保持）
スキップ: mybook/contents/00-preface.md（既存ファイルを保持）
```

---

## 7. `vs doctor --fix` の自動実行

ファイル展開・book.yml 書き換えの完了後、プロジェクトディレクトリ内で `vs doctor --fix` を自動実行する。これにより npm パッケージを含む執筆環境の一式が整う。

### 7.1 実行方法

```ruby
system("cd #{Shellwords.escape(project_name)} && vs doctor --fix")
```

### 7.2 失敗時

エラーメッセージを表示し、手動実行を促す。プロジェクトディレクトリ自体は削除しない。

```
警告: vs doctor --fix が失敗しました。
手動で以下を実行してください。
  cd mybook && vs doctor --fix
```

---

## 8. 完了メッセージ（正常系）

```
✅ プロジェクト "mybook" を作成しました。

book.yml で書籍の設定を変更できます。
書き方の参考は contents/ 内のサンプルファイルをご覧ください。

次のコマンドで執筆を始めましょう！

  cd mybook
  vs build
```

---

## 9. バリデーション

### 9.1 `project_name` の形式チェック

```ruby
/\A[a-zA-Z0-9_\-]+\z/
```

| 条件 | エラーメッセージ |
|---|---|
| 引数が省略された | `エラー: プロジェクト名を指定してください。\n  vs new <project_name>` |
| 使用不可文字を含む | `エラー: プロジェクト名に使用できる文字は英数字・ハイフン・アンダースコアのみです。` |

---

## 10. ファイル配置とクラス構成

### 10.1 ファイル配置

既存コマンドの配置に倣い、以下の1ファイルに実装する。

```
lib/vivlio/starter/cli/samovar/
  build_command.rb     ← 既存
  new_command.rb       ← 新規作成（展開ロジックも統合）
```

### 10.2 統合の判断理由

当初は `NewCommand`（コマンド層）と `ProjectScaffold`（展開ロジック層）の2ファイル分離案も検討したが、以下の理由から **`new_command.rb` への統合**とする。

- `new` コマンドの処理は「ファイルを展開して書き換える」という一連の手続きであり、他のコマンドからの再利用は想定されない。
- 分離すると、処理の流れを追うために2ファイルを行き来することになり、見通しが悪くなる。
- 手続き型のトップダウン構造（引数検証 → 対話 → 展開 → 書換 → doctor 実行 → 完了表示）は、1ファイルに収めたほうが上から下に読める。
- 行数が多少増えても、責務が明確な単一ファイルのほうがメンテナンスしやすい。

展開ロジックはクラス内のプライベートメソッドとして切り出し、`call` メソッドが手続き全体の流れを俯瞰できる構造にする。

### 10.3 `new_command.rb` の骨格

```ruby
# lib/vivlio/starter/cli/samovar/new_command.rb

require "samovar"
require "fileutils"
require "shellwords"

module Vivlio
  module Starter
    module CLI
      module Samovar
        class NewCommand < ::Samovar::Command
          self.description = "新規プロジェクトを作成します"

          options do
            option "--yes",         "対話をスキップしデフォルト設定で作成する"
            option "--force",       "既存ディレクトリへの追加展開を許可する"
            option "--log=<level>", "ログレベル（debug など）"
          end

          many :project_name_args

          SCAFFOLD_SOURCE = File.expand_path("../../../../project_scaffold", __dir__).freeze

          def call
            project_name = validated_project_name
            check_existing_directory!(project_name)
            answers = collect_answers(project_name)
            expand_scaffold(project_name, answers)
            run_doctor(project_name)
            print_success(project_name)
          end

          private

          def validated_project_name
            # §9 参照
          end

          def check_existing_directory!(project_name)
            # §6 参照
          end

          def collect_answers(project_name)
            # §5 参照。--yes なら即 default_answers を返す
          end

          def default_answers(project_name)
            { main_title: "新しい本", subtitle: "", author: "", publisher: "" }
          end

          def expand_scaffold(project_name, answers)
            # §3・§4 参照。ファイルを再帰コピーし book.yml を置換する
          end

          def rewrite_book_yml(dest_path, answers, project_name)
            # §4.2 参照
          end

          def run_doctor(project_name)
            # §7 参照
          end

          def print_success(project_name)
            # §8 参照
          end

          def debug?
            @options[:"log"] == "debug"
          end

          def log_debug(msg)
            puts "[debug] #{msg}" if debug?
          end
        end
      end
    end
  end
end
```

---

## 11. Scaffold ソースパスの解決

`new_command.rb` が `lib/vivlio/starter/cli/samovar/` に置かれることを前提に、`__dir__` からの相対パスで `project_scaffold/` を指す。

```ruby
SCAFFOLD_SOURCE = File.expand_path("../../../../project_scaffold", __dir__).freeze
# lib/vivlio/starter/cli/samovar/ から4つ上 = lib/
# => lib/project_scaffold/ を指す
```

Gem インストール後も、Gem のインストールパス内で同様に解決される。

---

## 12. ログ・エラー処理方針

- `--log=debug` が指定された場合、コピー中の各ファイルパスやシステムコマンドの詳細を出力する（`vs build --log=debug` と同じ挙動）。
- すべての `File` 操作は例外を捕捉し、ユーザーフレンドリーなメッセージで再出力する。スタックトレースは `--log=debug` 時のみ表示する。
- 致命的エラーでは `exit 1` する。

---

## 13. テスト方針

| テストケース | 確認内容 |
|---|---|
| 正常系（対話あり） | 全ファイルが展開され、book.yml に入力値が反映されている |
| 正常系（`--yes`） | 全ファイルが展開され、book.yml にデフォルト値が入っている |
| `{{PROJECT_NAME}}` 置換 | `project.name` がコマンド引数と一致する |
| 既存ディレクトリ（デフォルト） | エラーで中断し、ディレクトリは変更されない |
| 既存ディレクトリ（`--force`） | 既存ファイルをスキップし、不足ファイルのみ追加される |
| 引数省略 | バリデーションエラーで終了コード 1 |
| 使用不可文字 | バリデーションエラーで終了コード 1 |
| `vs doctor --fix` 失敗 | 警告を出力し、ファイル展開は成功している |
| 対話で「n」 | 中断し、ディレクトリは変更されない |
| `--log=debug` | コピー中のファイルパスが出力される |
