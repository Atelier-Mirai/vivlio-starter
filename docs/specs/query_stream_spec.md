# query-stream gem 仕様書

## 1. 概要

`query-stream` は、YAMLまたはJSONのデータファイルとテンプレートファイルを組み合わせて、テキストコンテンツ内のQueryStream記法を展開する汎用Rubyライブラリである。

もともと [vivlio-starter](https://github.com/mirai/vivlio-starter)（電子書籍執筆支援gem）の `data_render` 機能として設計されたが、静的サイトジェネレーター・ドキュメント生成・コンテンツ管理など幅広い用途に応用できる汎用DSLとして独立させた。

### 特徴

- **シンプルな記法** — `= books | tags=ruby | -title | 5 | :full` のような直感的なQueryStream記法
- **設定より規約** — ファイルを置くだけで自動的に記法が有効になる
- **読み取り専用** — CRUD のうち Read のみ。JOIN なし。シンプルさを維持する
- **出力形式を内包** — スタイル名とテンプレートで出力形式まで一行で指定できる
- **データソース** — YAML / JSON をサポート

---

## 2. インストール

```ruby
# Gemfile
gem 'query-stream'
```

```bash
bundle install
```

### 命名規約

| 種別 | 名前 |
|---|---|
| gem名 | `query-stream` |
| ディレクトリ名 | `query-stream/` |
| モジュール名 | `QueryStream` |
| メインファイル | `lib/query_stream.rb` |

Rubyのgem命名規約ではハイフンが「名前空間の区切り」を意味することがある（例: `rack-attack` → `Rack::Attack`）。`query-stream` も `Query::Stream` と解釈される可能性があるが、モジュール名は `QueryStream` として定義すること。

```ruby
# ✅ 正しい
module QueryStream
end

# ❌ 使わない
module Query
  module Stream
  end
end
```

---

## 3. 用語

| 用語 | 説明 |
|---|---|
| **QueryStream記法** | `= books \| tags=ruby \| :full` のような展開指示。パイプ（`\|`）で5ステージを区切る |
| **源泉** | データファイル名（`books`, `elements` 等） |
| **抽出条件** | フィルタリング条件（`tags=ruby`, `temp>=20` 等） |
| **ソート** | 並び替え指定（`-date`, `+title` 等） |
| **件数** | 取得件数制限（`5`, `10` 等） |
| **スタイル** | 出力テンプレートのバリエーション名（`:full`, `:table.html` 等） |
| **テンプレート** | データを流し込む雛形ファイル（`_book.md`, `_book.full.md` 等） |
| **TemplateCompiler** | テンプレートの独自記法を解釈してテキストを生成するコンパイラ |

---

## 4. QueryStream 記法

### 4.1 基本構造

```
= [源泉] | [抽出条件] | [ソート] | [件数] | [スタイル]
```

ステージの順序は固定。各ステージはトークンの形式が異なるため、パーサーが自動判別する。末尾のステージから順に省略可能。

| ステージ | 形式 | 省略時のデフォルト |
|---|---|---|
| 源泉 | データ名（単複どちらでも可） | 省略不可 |
| 抽出条件 | `field=value`、比較演算子、範囲指定等 | 全件 |
| ソート | `-field`（降順）/ `+field` or `field`（昇順） | 主キーの昇順 |
| 件数 | 正の整数 | 全件 |
| スタイル | `:stylename` または `:stylename.ext` | デフォルトテンプレート |

**トークンの自動判別：**

| トークンの形式 | 判別結果 |
|---|---|
| `field=value`、`field>=value`、`field=20..25` 等 | 抽出条件 |
| `-field` または `+field` で始まる | ソート |
| 正の整数のみ | 件数 |
| `:stylename` で始まる | スタイル |

### 4.2 源泉ステージ

データファイル名（拡張子なし）を指定する。単数形・複数形どちらでも記述可能。複数形は単数形に自動変換してテンプレートを解決する。

```
= books      # → data/books.yml + _book.md（複数件展開）
= book       # → data/books.yml + _book.md（一件展開）
= elements   # → data/elements.yml + _element.md
= weather_reports  # → data/weather_reports.yml + _weather_report.md
```

### 4.3 抽出ステージ

#### 主キーによる一件検索

値のみを指定すると、以下の優先順位で主キー候補フィールドを検索する。

| 優先順位 | フィールド名 | 典型的な用途 |
|---|---|---|
| 1 | `id` | 汎用的な一意識別子 |
| 2 | `no` | 番号（商品番号、整理番号等） |
| 3 | `code` | コード（都道府県コード、商品コード等） |
| 4 | `slug` | URL用識別子（Bridgetown / Jekyll 等） |
| 5 | `name` | 名称（人名、地名、商品名等） |
| 6 | `title` | タイトル（書籍、記事、映画等） |

`id` は省略可能。`id` がない場合、`no`, `code`, `slug`, `name`, `title` の順で自動解決する。

```
= book | 楽しいRuby      # title にマッチ
= prefecture | 東京都    # name にマッチ
= prefecture | 13        # code にマッチ
= element | H            # id にマッチ
= post | my-first-post   # slug にマッチ
```

派生キー（`name_ja`, `name_en` 等）は主キー候補に含まない。`field=value` 形式で明示指定する。

```
= books | tags=ruby
= prefectures | region=関東
= elements | category=nonmetal
```

#### 同一フィールドのOR（カンマ区切り）

```
= books | tags=ruby, javascript
= prefectures | region=関東, 関西
= weather_reports | condition=晴, 曇, 薄曇
```

#### 条件演算子

| 演算子 | 意味 |
|---|---|
| `AND` / `and` / `&&` | AND条件 |
| `OR` / `or` / `\|\|` | OR条件 |

```
= books | tags=ruby && tags=beginner
= weather_reports | location=東京 AND condition=晴, 曇
= elements | category=nonmetal AND phase_at_stp=gas
```

パース規則:
1. `AND` / `and` / `&&` で分割して複数の条件節に分ける
2. 各条件節内のカンマ区切りは同一フィールドへの OR として扱う
3. AND の優先順位は OR（カンマ）より高い

#### 比較演算子・範囲指定

| 記法 | 意味 |
|---|---|
| `=` / `==` | 等しい |
| `!=` | 等しくない |
| `>` / `>=` / `<` / `<=` | 比較 |
| `field=20..25` | 20以上25以下（両端含む）|
| `field=20...25` | 20以上25未満（終端除く）|
| `field=20..` | 20以上（上限なし）|
| `field=..25` | 25以下（下限なし）|

比較演算子記法と範囲オブジェクト記法はどちらも使用可能。

| 比較演算子記法 | 範囲オブジェクト記法 | 意味 |
|---|---|---|
| `field >= 20` | `field=20..` | 20以上 |
| `field <= 25` | `field=..25` | 25以下 |
| `field > 20` | — | 20より大きい |
| `field < 25` | `field=...25` | 25未満 |
| `field >= 20 AND field <= 25` | `field=20..25` | 20以上25以下 |
| `field >= 20 AND field < 25` | `field=20...25` | 20以上25未満 |

**日付の比較：**

YAMLは `2024-01-01`（クォートなし）を `Date` オブジェクトとして解析し、`"2024-01-01"`（クォートあり）を `String` として解析する。著者がクォートの有無を意識しなくて済むよう、FilterEngine は比較前に値を自動的に正規化する。

```yaml
date: 2024-01-01    # Date オブジェクトとして解析される
date: "2024-01-01"  # String として解析される（自動変換される）
```

```ruby
# FilterEngine 内での正規化
def normalize_value(value)
  case value
  when Date, Time then value
  when String     then Date.parse(value) rescue value
  else value
  end
end
```

文字列型・日付型どちらで記述しても同じ比較結果になる。

```
= weather_reports | date=2024-01-01..2024-12-31   # 2024年のデータ
= weather_reports | date >= 2024-06-01             # 2024年6月以降
```

無効な日付（例: `2026-02-29` は閏年でないため無効）が含まれる場合は ERROR を出力して処理を中断する。著者のデータ誤りを早期に検出するためフォールバックは行わない。

```ruby
def normalize_value(value)
  case value
  when Date, Time then value
  when String
    begin
      Date.parse(value)
    rescue Date::Error
      raise QueryStream::InvalidDateError, "無効な日付: #{value}"
    end
  else value
  end
end
```

### 4.4 ソートステージ

フィールド名の前に `-`（降順）または `+`（昇順）を付ける。`+` は省略可能。省略時は主キーの昇順。

```
= weather_reports | | -date       # date の降順
= books | | +title                # title の昇順（+は省略可能）
= books | tags=ruby | -title      # 絞り込み＋ソート
```

### 4.5 件数ステージ

正の整数で件数を指定する。省略時は全件。

```
= weather_reports | | | 5         # 先頭5件
= books | tags=ruby | -title | 5  # 絞り込み＋ソート＋件数
```

### 4.6 スタイルステージ

`:stylename` 形式で指定する。出力形式を拡張子で指定することもできる。

```
= books | :full                   # → _book.full.md（Markdown出力）
= books | :table.html             # → _book.table.html（HTML出力）
= books | :card.html              # → _book.card.html（HTML出力）
= books | :json                   # → _book.json（JSON出力）
```

省略時はデフォルトテンプレート（`_book.md`）を使用。

### 4.7 記法例まとめ

```
# 書籍
= books                                                    # 全件・デフォルト
= books | tags=ruby                                        # 抽出のみ
= books | tags=ruby && tags=beginner                       # AND絞り込み
= books | tags=ruby, javascript                            # OR絞り込み
= books | tags=ruby | :full                                # 抽出＋スタイル（途中省略）
= books | :full                                            # 全件・fullスタイル
= book | 楽しいRuby                                        # タイトルで一件
= book | 楽しいRuby | :standard                            # スタイル指定
= books | :table.html                                      # HTML表形式で出力

# 都道府県
= prefectures | region=関東, 関西 | :full                  # OR絞り込み＋スタイル
= prefecture | 東京都                                      # name で一件
= prefecture | 13                                          # code で一件

# 気象観測
= weather_reports | location=東京 AND condition=晴, 曇
= weather_report | location=東京 AND date=2024-01-01
# 関東の晴・曇・薄曇かつ最低気温20度以上25度未満・日付降順・5件・fullスタイル
= weather_reports | region=関東 and condition=晴, 曇, 薄曇 and temp_min_c=20...25 | -date | 5 | :full

# 元素
= elements | category=nonmetal AND phase_at_stp=gas | :full
= element | 水素
= element | symbol=H
= elements | :table.html                                   # HTML表形式で出力
```

---

## 5. データファイル仕様

### 5.1 サポートするデータ形式

| 形式 | 拡張子 | 備考 |
|---|---|---|
| YAML | `.yml` / `.yaml` | 推奨。配列・ネスト構造に対応 |
| JSON | `.json` | YAML と同じ構造で記述 |

CSVは将来の検討課題（ネスト構造を表現できないため制約が多い）。

### 5.2 データファイル規約

**複数値フィールドの記法**

配列とカンマ区切り文字列のどちらでも記述可能。

```yaml
tags: [ruby, beginner]    # 配列形式
tags: ruby, beginner      # カンマ区切り文字列形式（同じ結果）
```

**キー名の単複**

著者に委ねる。ただし同一ファイル内では統一すること。

**`id` フィールド**

省略可能。`id` がない場合、`title`, `name`, `code`, `no` などで主キー自動解決する。

### 5.3 データファイル例

**`data/books.yml`**

```yaml
- title: 楽しいRuby
  author: 高橋征義
  desc: Rubyを楽しく学べる入門書。
  tags: [ruby, beginner]
  cover: ruby-enjoyer.webp

- title: はじめてのC
  author: 柴田望洋
  desc: C言語の定番入門書。
  tags: [c, beginner]
```

**`data/prefectures.yml`**

```yaml
- name: 北海道
  capital: 札幌市
  region: 北海道
  code: 1
  population: 5224614
  area_sq_km: 83424.31

- name: 東京都
  capital: 新宿区
  region: 関東
  code: 13
  population: 14047594
  area_sq_km: 2194.07
```

**`data/weather_reports.yml`**

```yaml
- location: 東京
  date: 2024-01-01
  condition: 晴
  temp_max_c: 12.2
  temp_min_c: 1.5
  precipitation_mm: 0.0

- location: 東京
  date: 2024-06-15
  condition: 雨
  temp_max_c: 25.8
  temp_min_c: 18.2
  precipitation_mm: 15.5
```

---

## 6. テンプレートファイル仕様

### 6.1 ディレクトリ構成

```
templates/
  _book.md              # デフォルト（Markdown出力）
  _book.full.md         # fullスタイル
  _book.standard.md     # standardスタイル
  _book.table.html      # HTML表形式
  _book.card.html       # HTMLカード形式
```

### 6.2 命名規約

```
_[データ名].md                    # デフォルトテンプレート（Markdown）
_[データ名].[スタイル名].md        # Markdownバリエーション
_[データ名].[スタイル名].html      # HTML出力
_[データ名].[スタイル名].json      # JSON出力
```

- 先頭の `_` はパーシャルを示す（Hanami / Rails の規約に準拠）。
- `_books.md`（複数形）は不要。`= books` と書かれた場合、自動的に `_book.md` を使って反復する。
- スタイルを追加したい場合は `_book.myStyle.md` を置くだけで `= books | :myStyle` が有効になる。
- 将来的に ERB / Slim 等のテンプレートエンジンに対応する場合は `_book.md.erb` / `_book.md.slim` として拡張する。現時点では独自記法のみサポート。

### 6.3 テンプレート記法

YAMLのキー名がそのままテンプレートの変数名になる。

```markdown
# templates/_book.md
### = title
**著者**: = author
= desc
![](cover){width=40% align=right}
```

**変換ルール：**

| 入力パターン | 変換後 | 備考 |
|---|---|---|
| `= key` のみの行 | `key` の値を展開 | nil/空文字なら行ごとスキップ |
| `prefix = key` | `key` の値を展開 | prefix はMarkdown記法等 |
| `![](key)` | `key` の値を展開 | nil/空文字なら行ごとスキップ |
| `![](file.png)` | リテラル出力 | 拡張子ありはそのまま通す |
| `= key` を含まない行 | リテラル出力 | ヘッダー行等は一度だけ出力 |
| 空行 | 改行出力 | |

**`= key` を含む行のみ反復し、含まない行は一度だけ出力される。**

```markdown
# templates/_book.table.html（表形式の例）
<table>
<tr><th>タイトル</th><th>著者</th></tr>
<tr><td>= title</td><td>= author</td></tr>
</table>
```

出力結果：

```html
<table>
<tr><th>タイトル</th><th>著者</th></tr>
<tr><td>楽しいRuby</td><td>高橋征義</td></tr>
<tr><td>はじめてのC</td><td>柴田望洋</td></tr>
</table>
```

### 6.4 入出力例

**`data/books.yml`**

```yaml
- title: 楽しいRuby
  author: 高橋征義
  desc: Rubyを楽しく学べる入門書。
  cover: ruby-enjoyer.webp

- title: はじめてのC
  author: 柴田望洋
  desc: C言語の定番入門書。
  cover:
```

**`templates/_book.md`**

```markdown
### = title
**著者**: = author
= desc
![](cover){width=40% align=right}
```

**レンダリング結果**

```markdown
### 楽しいRuby
**著者**: 高橋征義
Rubyを楽しく学べる入門書。
![](ruby-enjoyer.webp){width=40% align=right}

### はじめてのC
**著者**: 柴田望洋
C言語の定番入門書。
```

- `cover` が nil の「はじめてのC」では `![](cover)` の行がスキップされる。
- テンプレートの空行が書籍間の区切りとして出力される。

---

## 7. 設定

### 7.1 設定方法

```ruby
QueryStream.configure do |config|
  config.data_dir       = 'data'              # データファイルのディレクトリ
  config.templates_dir  = 'templates'         # テンプレートファイルのディレクトリ
  config.default_format = :md                 # デフォルト出力形式（:md / :html / :json）
  config.logger         = Logger.new($stdout) # ログ出力先
end
```

### 7.2 デフォルト値

| 設定キー | デフォルト値 | 説明 |
|---|---|---|
| `data_dir` | `'data'` | データファイルのディレクトリ |
| `templates_dir` | `'templates'` | テンプレートファイルのディレクトリ |
| `default_format` | `:md` | スタイル省略時のデフォルト出力形式 |
| `logger` | `Logger.new($stdout)` | ログ出力先 |

`default_format` とテンプレートの対応：

| `default_format` | スタイル省略時のテンプレート |
|---|---|
| `:md`（デフォルト） | `_book.md` |
| `:html` | `_book.html` |
| `:json` | `_book.json` |

### 7.3 フレームワークへの組み込み

各フレームワークへの組み込みは将来の検討課題。現時点では `QueryStream.render` を利用側で呼び出す形での使用を想定している。

```ruby
# 利用側での呼び出し例
source = File.read('contents/05-references.md')
result = QueryStream.render(source)
File.write('05-references.md', result)
```

将来的に以下のようなプラグイン・アダプターの提供を検討する：

- `query-stream-bridgetown` — Bridgetown プラグイン
- `query-stream-jekyll` — Jekyll プラグイン
- `query-stream-middleman` — Middleman 拡張

---

## 8. CLI

query-stream は他のツールに組み込んで使うライブラリであるため、CLIは最小限とする。`--version` オプションのみ提供する。

```bash
$ bundle exec query-stream --version
query-stream 0.1.0
```

### 8.1 実装（samovar を使用）

samovar は宣言的クラスベースDSLで、サブコマンドや自動ドキュメント生成に優れたオプションパーサーである。vivlio-starter と同じエコシステム（ioquatix / Samuel Williams 製）。

```ruby
# Gemfile
gem 'samovar'
```

```ruby
# lib/query_stream/command.rb
require 'samovar'

module QueryStream
  module Command
    class Top < Samovar::Command
      self.description = "QueryStream - YAML/JSON data renderer"

      options do
        option '--version', "Print version and exit"
      end

      def call
        if @options[:version]
          puts "query-stream #{QueryStream::VERSION}"
        else
          puts self.usage
        end
      end
    end
  end
end
```

```ruby
# bin/query_stream
#!/usr/bin/env ruby
require 'query_stream'
QueryStream::Command::Top.call(ARGV)
```

---

## 9. 使い方

### 9.1 基本的な使い方

```ruby
require 'query_stream'

# テキスト内のQueryStream記法を展開
source = File.read('contents/05-references.md')
result = QueryStream.render(source)
File.write('05-references.md', result)
```

### 9.2 単独でのレンダリング

```ruby
# QueryStream記法を直接レンダリング
result = QueryStream.render_query('= books | tags=ruby | :full')
puts result
```

### 9.3 スキャンのみ

```ruby
# QueryStream記法が含まれているか確認
queries = QueryStream.scan('contents/05-references.md')
# => ["= books | tags=ruby | :full", "= element | 水素"]
```

---

## 10. 内部実装方針

### 10.1 クラス構成

```ruby
module QueryStream
  class QueryStreamParser   # 構文解析
    # "= books | tags=ruby | :full" をパースして返す
    # => { source: "books", filter: ..., sort: ..., limit: nil, style: "full", format: "md" }
    def parse(query) = ...
  end

  class DataResolver        # データ特定・単複解決・主キー解決
    def resolve(source) = ...
  end

  class FilterEngine        # AND/OR/比較/Range によるフィルタリング
    def filter(data, conditions) = ...
  end

  class TemplateCompiler    # テンプレートの独自記法 → テキスト生成
    def self.compile(template, records) = ...
  end
end
```

たかだか数百件のデータから抽出する処理であるため、過大な設計は避ける。シンプルな実装に努めること。

### 10.2 QueryStream 実装案

```ruby
# 1. Source（データロード）
data = YAML.load_file('data/weather_reports.yml', symbolize_names: true)

# 2. Filter（条件によるフィルタリング）
data = data.select {
  ['晴', '曇', '薄曇'].include?(it[:condition]) && it[:temp_min_c] >= 20
}

# 3. Sort（並び替え）
data = data.sort_by { it[:date] }.reverse

# 4. Limit（件数制限）
data = data.first(5)

# 5. Render（テンプレートに流し込む）
result = TemplateCompiler.compile(template, data)
```

### 10.3 単数形/複数形の自動解決

```ruby
def singularize(word)
  case word.to_s
  in /(.*)ies$/              then "#{$1}y"      # categories → category
  in /(.*)([sxz]|ch|sh)es$/ then "#{$1}#{$2}"  # branches → branch
  in /(.*)ves$/              then "#{$1}f"       # shelves → shelf
  in /(.*)s$/                then $1             # elements → element
  else word                                      # data, sheep（不変）
  end
end
```

---

## 11. エラーハンドリング

### 11.1 例外クラス

```ruby
module QueryStream
  # 基底クラス
  class Error   < StandardError; end
  class Warning < StandardError; end

  # ERROR系（処理を中断）
  class TemplateNotFoundError  < Error; end  # テンプレートファイルが存在しない
  class DataNotFoundError      < Error; end  # データファイルが存在しない
  class UnknownKeyError        < Error; end  # テンプレート内に存在しないキー
  class InvalidDateError       < Error; end  # 無効な日付

  # WARNING系（処理を続行）
  class AmbiguousQueryWarning  < Warning; end  # 一件検索で複数件ヒット
  class NoResultWarning        < Warning; end  # 一件検索で0件ヒット
end
```

### 11.2 挙動一覧

| 状況 | 例外クラス | 挙動 |
|---|---|---|
| テンプレートファイルが存在しない | `TemplateNotFoundError` | ERROR を出力して処理を中断 |
| データファイルが存在しない | `DataNotFoundError` | ERROR を出力して処理を中断 |
| テンプレート内に存在しないキーが記述されている | `UnknownKeyError` | ERROR を出力して処理を中断 |
| データファイル内に無効な日付が含まれる（例: `2026-02-29`） | `InvalidDateError` | ERROR を出力して処理を中断 |
| 一件検索で複数件ヒット | `AmbiguousQueryWarning` | WARNING を出力し明示指定を促す |
| 一件検索で0件ヒット | `NoResultWarning` | WARNING を出力 |

フォールバックは行わない。

### 11.3 利用側でのハンドリング例

```ruby
begin
  result = QueryStream.render(source)
rescue QueryStream::TemplateNotFoundError => e
  puts "テンプレートが見つかりません: #{e.message}"
rescue QueryStream::InvalidDateError => e
  puts "無効な日付です: #{e.message}"
rescue QueryStream::Error => e
  puts "QueryStream エラー: #{e.message}"
end

# WARNING は rescue せず logger で受け取る
QueryStream.configure do |config|
  config.logger = Logger.new($stdout)
end
```

---

## 12. テスト方針

書籍・気象・都道府県・元素など複数のデータ種別を用いて、以下の観点でテストを充実させる。

- 単数形/複数形の自動解決
- 主キー自動解決（`id`, `no`, `code`, `slug`, `name`, `title`）
- AND / OR 条件の組み合わせ
- 比較演算子・範囲指定（`>=`, `..`, `...`）
- ソート（昇順・降順）・件数制限
- `:stylename` 記法によるテンプレート選択
- 出力形式（`.md`, `.html`, `.json`）の切り替え
- nil/空文字フィールドの行スキップ
- 存在しないキー・テンプレート・データファイルのエラー処理

---

## 13. 拡張性

- `data/` に YAML / JSON を追加するだけで新しいデータ種別が使用可能になる。
- `templates/` にファイルを追加するだけで新しいスタイル・出力形式が使用可能になる。
- 将来的に ERB / Slim 等のテンプレートエンジンへの対応を検討する（`_book.md.erb` 等）。
- 将来的に CSV データソースへの対応を検討する（ネスト構造の制約あり）。

---

## 14. Q&A

**Q: 範囲演算子 `field=20..25` の `...` はMarkdown原稿内で省略記号と誤認されやすいのでは？**

A: 代替記法は用意しない。範囲指定構文であることは文脈から明らかであり、QueryStream は Ruby の Range 記法をそのまま使用することでパーサーの負担を軽減する。

**Q: JOIN や GROUP BY は対応しないのか？**

A: 意図的に対象外とする。数百件程度のYAML/JSONデータから抽出する用途に特化しており、シンプルさを維持することが設計方針である。複雑なデータ操作が必要な場合はデータベースを使用すること。
