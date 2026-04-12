# 新規プロジェクトの作成（vs new）

:::{.chapter-lead}
クイックスタートで `vs new` をひと通り体験した方向けの詳細リファレンスです。`--yes` や `--force` などのオプション、プロジェクト名のルール、ディレクトリ構成の意味を確認したくなったときに戻ってきてください。急いでいる方は読み飛ばして次の章へ進んでも構いません。
:::

## 基本的な使い方

:::{.section-lead}
プロジェクト名を指定して `vs new` を実行すると、対話形式で書籍情報を入力できます。
:::

```bash
vs new mybook
```

実行すると、以下の質問が順に表示されます。何も入力せずに Enter を押すとデフォルト値が使われます。

```
Vivlio Starter へようこそ！新しい書籍プロジェクトを作成します。

書籍名を入力してください（例: はじめての Ruby）: はじめての Ruby
副題を入力してください（任意。Enter でスキップ）:
著者名を入力してください（例: 山田 太郎）: 山田 太郎
発行者・サークル名を入力してください（例: アトリヱ未來）: アトリヱ未來

以下の設定でプロジェクトを作成します。

  プロジェクト名: mybook
  書籍名:         はじめての Ruby
  副題:           （なし）
  著者:           山田 太郎
  発行者:         アトリヱ未來

よろしいですか？ [Y/n]:
```

確認で Enter（または `Y`）を押すと、プロジェクトが作成されます。`n` を入力すると中断されます。

## 生成されるプロジェクトの構成

`vs new mybook` を実行すると、以下のようなディレクトリ構造が生成されます。

```
mybook/
  contents/          ← 原稿（Markdownファイル）
  images/            ← 画像ファイル
  covers/            ← 表紙・裏表紙用の画像ファイル
  data/              ← 書籍内で展開したいQueryStream用データ（YAML形式）
  templates/         ← 各種雛形ファイル置き場
  sources/           ← 執筆資料やPDFファイル置き場
  codes/             ← 書籍内で掲載するサンプルコード
  stylesheets/       ← CSSスタイルシート
  config/
    book.yml         ← 書籍の設定ファイル
    catalog.yml      ← 章構成
    page_presets.yml ← ページレイアウト設定
    index_glossary_terms.yml     ← 用語集
  vivliostyle.config.js
  entries.js
  package.json
  Gemfile
```

入力した書籍名・著者名などは `config/book.yml` に自動的に書き込まれます。後から `book.yml` を直接編集して変更することもできます。

## 各ディレクトリの役割

:::{.section-lead}
それぞれのディレクトリの概要を以下に記します。使ううちに自然と慣れてくるものも多いので、今は「こういうものがあるんだな」と軽く流してもらって構いません。各ディレクトリの下には `_README.md` が置かれていますので、必要になったときに改めて参照できます。また、本書の後半でそれぞれの機能をより詳しく解説していますので、そちらも合わせて読むと理解が深まります。
:::

### contents/

書籍の本文となる Markdown ファイルを配置するディレクトリです。ファイル名は `NN-slug.md` 形式（例: `01-quickstart.md`）で、先頭の数字が章の並び順を決めます。

| 範囲 | 用途 |
|------|------|
| `00` | 前書き・はじめに |
| `01-89` | 通常の章 |
| `90-98` | 付録 |
| `99` | 後書き・おわりに |

```bash
vs create 11-intro     # 章ファイルと画像ディレクトリを生成
vs delete 11-intro     # 章を削除
vs rename 11 12        # 章番号を変更
vs renumber            # 章番号を一括で整列
```

ビルド対象は `config/catalog.yml` に登録された章のみです。

### images/

書籍内で使用する画像ファイルを配置するディレクトリです。章ごとにサブディレクトリを作成して管理します。`vs create` で章を作成すると対応する画像ディレクトリが自動生成されます。

原稿には `.webp` 形式を推奨します。PNG/JPG は `vs resize` で WebP に変換できます。`vs build` 実行時にも自動で WebP 変換が行われます。

```bash
vs resize              # images/ 全体を標準品質で WebP 変換
vs resize --high       # 高品質で変換（quality=90）
```

### covers/

書籍の表紙・裏表紙に使用する画像ファイルを配置するディレクトリです。`vs cover` または `vs build` で自動生成されます。

`config/book.yml` の `output.cover` でテーマ名を指定します。`light` / `dark` は gem 同梱テンプレートを使用します。著者が用意した PNG/SVG を使う場合は `covers/frontcover_<theme>.png` を配置してください。

```bash
vs cover               # book.yml の設定に従ってカバー画像を生成
vs clean --cover       # 生成されたカバー画像を削除
```

### data/

原稿内で展開する外部データ（YAML形式）を配置するディレクトリです。QueryStream 記法と組み合わせて使います。

```markdown
= books                    # 全件展開
= books | tags=ruby        # タグで絞り込み
= books | -year | 3        # 年度降順・3件
```

データの展開テンプレートは `templates/` ディレクトリに配置します（`data/books.yml` → `templates/_book.md`）。

### templates/

章ファイルの雛形と QueryStream のデータ展開テンプレートを配置するディレクトリです。`vs create` で章ファイルを生成する際に章番号の範囲に応じて自動選択されます（`chapter.md`・`preface.md`・`appendix.md`・`postface.md`）。テンプレート内の `{{TITLE}}` は章のスラッグに自動置換されます。

章テンプレートのカスタマイズ方法や QueryStream テンプレートの詳細は「ユーティリティ・コマンド集」と「QueryStream」の章を参照すると理解が深まります。

### sources/

執筆の参考資料や素材となるファイルを自由に配置するディレクトリです。ビルド対象外です。`vs pdf:read` で PDF から Markdown を抽出する際の入力ファイルとして活用できます。

```bash
vs pdf:read reference        # sources/reference.pdf を自動探索
```

### codes/

書籍内で掲載するサンプルコードを配置するディレクトリです。原稿から `include` 記法で参照できます。

```markdown
```include:sample.rb```
```include:01-intro/hello.rb:10-20```
```

### stylesheets/

書籍のレイアウトとデザインを定義する CSS ファイルを配置するディレクトリです。テーマカラーや扉絵などのデザイン設定は `config/book.yml` の `theme` セクションで行います。`theme.css` はビルド時に自動生成されるため、直接編集しても次回ビルド時に上書きされます。カスタム CSS は `custom.css` に記述してください。

### config/

書籍プロジェクトの各種設定ファイルを配置するディレクトリです。

| ファイル | 役割 |
|----------|------|
| `book.yml` | 書籍のメタデータ・ビルド設定（最重要） |
| `catalog.yml` | ビルド対象の章リスト（章の順序を定義） |
| `page_presets.yml` | 用紙サイズ等のプリセット定義 |
| `index_glossary_terms.yml` | 索引・用語集の登録済み用語 |
| `post_replace_list.yml` | ビルド後処理の文字列置換ルール |
| `.textlintrc.yml` | textlint の校正ルール設定 |

## 対話をスキップする（--yes）

`--yes` オプションを付けると、すべての質問をスキップしてデフォルト値でプロジェクトを作成します。`book.yml` は後から自由に編集できるため、上級者にはこちらが快適です。

```bash
vs new mybook --yes
```

### デフォルト値

| 項目 | デフォルト値 |
|------|------------|
| 書籍名 | 新しい本 |
| 副題 | （空） |
| 著者名 | （空） |
| 発行者 | （空） |

## 既存ディレクトリへの追加展開（--force）

同名のディレクトリがすでに存在する場合、通常はエラーになります。

```
エラー: ディレクトリ "mybook" はすでに存在します。
上書き展開する場合は --force オプションを指定してください。
  vs new mybook --force
```

`--force` を付けると、既存ファイルはそのまま保持し、不足しているファイルだけを追加します。原稿や設定の編集内容が上書きされることはありません。

```bash
vs new mybook --force
```

スキップされたファイルはログに表示されます。

```
スキップ: mybook/config/book.yml（既存ファイルを保持）
スキップ: mybook/contents/00-preface.md（既存ファイルを保持）
```

:::{.column}
**💡 --force の使いどころ**

Vivlio Starter のバージョンアップで新しいテンプレートやスタイルシートが追加された場合、`--force` で既存プロジェクトに不足ファイルだけを補完できます。
:::

## --yes と --force の組み合わせ

対話のスキップと追加展開を同時に指定することもできます。

```bash
vs new mybook --yes --force
```

## 環境セットアップの自動実行

プロジェクト作成後、`vs doctor --fix` が自動的に実行されます。これにより npm パッケージのインストールなど、執筆に必要な環境が一括でセットアップされます。

万が一 `vs doctor --fix` が失敗した場合は、プロジェクト自体は残ったまま警告が表示されます。手動で再実行してください。

```bash
cd mybook
vs doctor --fix
```

## デバッグログ（--log debug）

トラブルシューティング用に、コピー中のファイルパスやコマンドの詳細を表示できます。

```bash
vs new mybook --yes --log debug
```

## オプション一覧

| オプション | 説明 |
|------------|------|
| `--yes` / `-y` | 対話をスキップしデフォルト設定で作成する |
| `--force` | 既存ディレクトリへの追加展開を許可する |
| `--log debug` | デバッグログを出力する |

## プロジェクト名のルール

プロジェクト名には **英数字・ハイフン・アンダースコア** のみ使用できます。

```bash
# OK
vs new mybook
vs new my-book
vs new my_book_2

# NG（エラーになります）
vs new "my book"
vs new my/book
```

## 作成後の次のステップ

プロジェクトが作成されたら、以下のコマンドで執筆を始められます。

```bash
cd mybook
vs build
```

`contents/` 内のサンプルファイルを参考に、原稿を書き始めてください。書籍の設定を変更したい場合は `config/book.yml` を編集します。詳しくは「book.yml 設定リファレンス」の章を参照してください。
